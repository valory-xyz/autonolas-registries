// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IService} from "../contracts/interfaces/IService.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeProxy} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import {GnosisSafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import {Test} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";
import {ERC721TokenReceiver} from "../lib/solmate/src/tokens/ERC721.sol";
import {GnosisSafeMultisig} from "../contracts/multisigs/GnosisSafeMultisig.sol";
import {ServiceRegistryL2} from "../contracts/ServiceRegistryL2.sol";
import {ServiceRegistryTokenUtility} from "../contracts/ServiceRegistryTokenUtility.sol";
import {OperatorWhitelist} from "../contracts/utils/OperatorWhitelist.sol";
import {ServiceManager} from "../contracts/ServiceManager.sol";
import {ServiceManagerProxy} from "../contracts/ServiceManagerProxy.sol";
import {MockIdentityRegistry} from "../contracts/test/MockIdentityRegistry.sol";
import {IdentityRegistryBridger} from "../contracts/8004/IdentityRegistryBridger.sol";
import {IdentityRegistryBridgerProxy} from "../contracts/8004/IdentityRegistryBridgerProxy.sol";
import "../contracts/staking/StakingNativeToken.sol";
import {StakingToken} from "../contracts/staking/StakingToken.sol";
import {StakingBase, ReentrancyGuard} from "../contracts/staking/StakingBase.sol";
import {StakingActivityChecker} from "../contracts/staking/StakingActivityChecker.sol";

// Service staking interface (subset used by the attacker helpers below).
interface IStakingForAttacker {
    function stake(uint256 serviceId) external;
    function stake(uint256 serviceId, uint256 rewardDistributionInfo) external;
    function checkpointAndClaim(uint256 serviceId) external returns (uint256);
    function deposit(uint256 amount) external;
}

interface IERC721ApprovalsForAttacker {
    function approve(address spender, uint256 serviceId) external;
}

/// @dev Attacker that owns a staked service and attempts a nested `receive{value}` re-entry during
///      the outer `_withdraw` call. Uses a low-level call so the re-entry failure does not propagate
///      as a revert — the outer claim still completes, and tests can then inspect the attacker's
///      recorded attack state to confirm the lock fired.
contract NestedReceiveAttacker is ERC721TokenReceiver {
    address payable public staking;
    address public serviceRegistry;

    uint256 public reentryAmount;
    bool public reentryArmed;
    bool public reentryAttempted;
    bool public reentrySucceeded;
    bytes4 public reentryErrorSelector;

    constructor(address _staking, address _serviceRegistry) {
        staking = payable(_staking);
        serviceRegistry = _serviceRegistry;
    }

    function armReentry(uint256 amount) external {
        reentryArmed = true;
        reentryAmount = amount;
    }

    function stake(uint256 serviceId, uint256 rewardDistributionInfo) external {
        IERC721ApprovalsForAttacker(serviceRegistry).approve(staking, serviceId);
        IStakingForAttacker(staking).stake(serviceId, rewardDistributionInfo);
    }

    function checkpointAndClaim(uint256 serviceId) external returns (uint256) {
        return IStakingForAttacker(staking).checkpointAndClaim(serviceId);
    }

    receive() external payable {
        if (!reentryArmed) {
            return;
        }
        reentryArmed = false;
        reentryAttempted = true;

        (bool ok, bytes memory reason) = staking.call{value: reentryAmount}("");
        reentrySucceeded = ok;
        if (!ok && reason.length >= 4) {
            reentryErrorSelector = bytes4(reason);
        }
    }
}

/// @dev ERC20 token with a transferFrom hook that attempts to re-enter `deposit()` on the staking
///      contract during the outer `deposit()`'s safeTransferFrom. Uses a low-level call so the
///      re-entry failure can be observed without the hook itself reverting — a hook revert would
///      make the outer deposit fail with `TokenTransferFailed` before we can confirm the lock was
///      the specific cause.
contract ReentrantHookERC20 is ERC20 {
    address public staking;
    uint256 public reentryAmount;
    bool public reentryArmed;
    bool public reentryAttempted;
    bool public reentrySucceeded;
    bytes4 public reentryErrorSelector;

    constructor() ERC20("Reentrant Hook Token", "RHT", 18) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setStaking(address _staking) external {
        staking = _staking;
    }

    function armReentry(uint256 amount) external {
        reentryArmed = true;
        reentryAmount = amount;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool ok = super.transferFrom(from, to, amount);
        if (reentryArmed) {
            reentryArmed = false;
            reentryAttempted = true;
            (bool callOk, bytes memory reason) =
                staking.call(abi.encodeWithSignature("deposit(uint256)", reentryAmount));
            reentrySucceeded = callOk;
            if (!callOk && reason.length >= 4) {
                reentryErrorSelector = bytes4(reason);
            }
        }
        return ok;
    }
}

/// @title StakingDerivativeReentrancyTest
/// @notice Covers the §A.5 derivative lock extension (internal audit 16):
///
///         - `StakingNativeToken.receive()` and `StakingToken.deposit()` now hold the same
///           `_locked` slot as the seven StakingBase entry points. A nested call from within an
///           outer `_withdraw` (or outer `deposit`) is rejected with `ReentrancyGuard()`.
///         - Honest deposits still succeed.
///
///         The pre-fix defect was a silent `balance` vs `availableRewards` desync: a nested
///         `receive{value: Y}()` during `_withdraw` would write `balance = B + Y` and be overwritten
///         by the outer `balance = updatedBalance` SSTORE, orphaning `Y` wei in the contract. The
///         tests here prove that the nested call is now rejected at its entry, eliminating the
///         class of issue.
contract StakingDerivativeReentrancyTest is Test {
    Utils internal utils;
    ReentrantHookERC20 internal hookToken;
    GnosisSafe internal gnosisSafe;
    GnosisSafeProxy internal gnosisSafeProxy;
    GnosisSafeProxyFactory internal gnosisSafeProxyFactory;
    GnosisSafeMultisig internal gnosisSafeMultisig;
    ServiceRegistryL2 internal serviceRegistry;
    ServiceRegistryTokenUtility internal serviceRegistryTokenUtility;
    OperatorWhitelist internal operatorWhitelist;
    ServiceManager internal serviceManager;
    MockIdentityRegistry internal identityRegistry;
    IdentityRegistryBridger internal identityRegistryBridger;
    StakingNativeToken internal stakingNativeToken;
    StakingToken internal stakingToken;
    StakingActivityChecker internal stakingActivityChecker;

    address payable[] internal users;
    address internal deployer;
    address internal operator;
    uint256 internal initialMint = 50_000_000 ether;
    uint32 internal threshold = 1;
    uint96 internal regBond = 10 ether;
    uint256 internal regDeposit = 10 ether;
    uint256[] internal emptyArray;

    bytes32 internal unitHash = 0x9999999999999999999999999999999999999999999999999999999999999999;
    bytes internal payload;
    uint32[] internal agentIds;

    uint256 internal maxNumServices = 10;
    uint256 internal rewardsPerSecond = 549768518519;
    uint256 internal minStakingDeposit = 10 ether;
    uint256 internal minNumStakingPeriods = 3;
    uint256 internal maxNumInactivityPeriods = 3;
    uint256 internal livenessPeriod = 1 days;
    uint256 internal timeForEmissions = 1 weeks;
    uint256 internal livenessRatio = 0.0001 ether;
    uint256 internal numAgentInstances = 1;

    address[] internal agentInstances;

    function setUp() public virtual {
        agentIds = new uint32[](1);
        agentIds[0] = 1;

        utils = new Utils();
        users = utils.createUsers(20);
        deployer = users[0];
        operator = users[1];
        agentInstances = new address[](2);
        agentInstances[0] = users[2];
        agentInstances[1] = users[3];

        // Registries
        serviceRegistry = new ServiceRegistryL2("Service Registry", "SERVICE", "https://localhost/service/");
        serviceRegistryTokenUtility = new ServiceRegistryTokenUtility(address(serviceRegistry));
        operatorWhitelist = new OperatorWhitelist(address(serviceRegistry));

        serviceManager = new ServiceManager(address(serviceRegistry), address(serviceRegistryTokenUtility));
        bytes memory proxyData = abi.encodeWithSelector(serviceManager.initialize.selector, "");
        ServiceManagerProxy serviceManagerProxy = new ServiceManagerProxy(address(serviceManager), proxyData);
        serviceManager = ServiceManager(address(serviceManagerProxy));

        serviceRegistry.changeManager(address(serviceManager));
        serviceRegistryTokenUtility.changeManager(address(serviceManager));

        identityRegistry = new MockIdentityRegistry();
        identityRegistryBridger = new IdentityRegistryBridger(address(identityRegistry), address(serviceRegistry));
        proxyData = abi.encodeWithSelector(identityRegistryBridger.initialize.selector, "");
        IdentityRegistryBridgerProxy identityRegistryBridgerProxy =
            new IdentityRegistryBridgerProxy(address(identityRegistryBridger), proxyData);
        identityRegistryBridger = IdentityRegistryBridger(address(identityRegistryBridgerProxy));
        serviceManager.setIdentityRegistryBridger(address(identityRegistryBridger));

        // Multisig
        gnosisSafe = new GnosisSafe();
        gnosisSafeProxy = new GnosisSafeProxy(address(gnosisSafe));
        gnosisSafeProxyFactory = new GnosisSafeProxyFactory();
        gnosisSafeMultisig = new GnosisSafeMultisig(payable(address(gnosisSafe)), address(gnosisSafeProxyFactory));

        // Hook token (staking token for StakingToken; also acts as the attacker for deposit()).
        hookToken = new ReentrantHookERC20();
        hookToken.mint(deployer, initialMint);
        hookToken.mint(operator, initialMint);
        hookToken.mint(address(this), initialMint);

        bytes32 multisigProxyHash = keccak256(address(gnosisSafeProxy).code);

        stakingActivityChecker = new StakingActivityChecker(livenessRatio);

        StakingBase.StakingParams memory stakingParams = StakingBase.StakingParams(
            bytes32(uint256(uint160(address(msg.sender)))), maxNumServices, rewardsPerSecond, minStakingDeposit,
            minNumStakingPeriods, maxNumInactivityPeriods, livenessPeriod, timeForEmissions, numAgentInstances,
            emptyArray, 0, bytes32(0), multisigProxyHash, address(serviceRegistry), address(stakingActivityChecker));

        stakingNativeToken = StakingNativeToken(payable(address(new StakingNativeToken())));
        stakingNativeToken.initialize(stakingParams);

        stakingToken = new StakingToken();
        stakingToken.initialize(stakingParams, address(serviceRegistryTokenUtility), address(hookToken));
        hookToken.setStaking(address(stakingToken));

        serviceRegistry.changeMultisigPermission(address(gnosisSafeMultisig), true);

        // Create one native-token-staked service (serviceId = 1).
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0].slots = 1;
        agentParams[0].bond = regBond;

        serviceManager.create(deployer, serviceManager.ETH_TOKEN_ADDRESS(), unitHash, agentIds,
            agentParams, threshold);
        vm.prank(deployer);
        serviceManager.activateRegistration{value: regDeposit}(1);
        address[] memory singleAgent = new address[](1);
        singleAgent[0] = agentInstances[0];
        vm.prank(operator);
        serviceManager.registerAgents{value: regBond}(1, singleAgent, agentIds);
        vm.prank(deployer);
        serviceManager.deploy(1, address(gnosisSafeMultisig), payload);
    }

    function _bumpNonce(uint256 serviceId, address agent) internal {
        ServiceRegistryL2.Service memory service = serviceRegistry.getService(serviceId);
        address payable multisig = payable(service.multisig);
        bytes memory safePayload = abi.encodeWithSelector(bytes4(keccak256("getThreshold()")));

        bytes memory signature = new bytes(65);
        bytes memory bAddress = abi.encode(agent);
        for (uint256 b = 0; b < 32; ++b) {
            signature[b] = bAddress[b];
        }
        signature[64] = bytes1(0x01);

        vm.prank(agent);
        GnosisSafe(multisig).execTransaction(multisig, 0, safePayload, Enum.Operation.Call, 0, 0, 0, address(0),
            payable(address(0)), signature);
    }

    function _bumpNonceN(uint256 serviceId, address agent, uint256 times) internal {
        for (uint256 i = 0; i < times; ++i) {
            _bumpNonce(serviceId, agent);
        }
    }

    /// @dev §A.5 — a nested `receive{value}` call from a reward callback during `_withdraw`
    ///      is rejected by the new lock on `StakingNativeToken.receive()`. The outer claim still
    ///      completes (the attacker's receive swallows the revert via low-level .call), but the
    ///      nested write to `balance` / `availableRewards` never lands — so no desync is possible.
    function test_Reentrancy_NestedReceive_RevertsWithGuard() external {
        NestedReceiveAttacker attacker = new NestedReceiveAttacker(
            address(stakingNativeToken), address(serviceRegistry));

        // Fund staking with rewards and fund the attacker with the amount they will try to inject.
        (bool ok, ) = address(stakingNativeToken).call{value: 100 ether}("");
        assertTrue(ok);
        vm.deal(address(attacker), 10 ether);
        uint256 attackerEthStart = address(attacker).balance;
        uint256 stakingBalanceAfterTopup = stakingNativeToken.balance();
        uint256 stakingRewardsAfterTopup = stakingNativeToken.availableRewards();

        // Transfer the service NFT to the attacker, then stake with ServiceOwner distribution so
        // the full reward is sent straight to the attacker (one _transfer hop, triggers receive()).
        uint256 serviceId = 1;
        vm.prank(deployer);
        serviceRegistry.transferFrom(deployer, address(attacker), serviceId);
        attacker.stake(serviceId, uint256(1)); // RewardDistributionType.ServiceOwner

        // Accrue rewards.
        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(serviceId, agentInstances[0], 20);

        // Arm the attacker: during its receive callback it will attempt a nested 1 ether deposit
        // back into stakingNativeToken. Under the pre-fix contract this silently corrupted state;
        // under §A.5 it must revert with ReentrancyGuard.
        uint256 injection = 1 ether;
        attacker.armReentry(injection);

        attacker.checkpointAndClaim(serviceId);

        // The attacker must have tried the nested call and the call must have been rejected.
        assertTrue(attacker.reentryAttempted(), "attacker did not attempt re-entry");
        assertFalse(attacker.reentrySucceeded(), "nested receive() must be rejected by the lock");
        assertEq(attacker.reentryErrorSelector(), ReentrancyGuard.selector,
            "nested receive() must revert with ReentrancyGuard");

        // No desync: the attacker's ETH was NOT credited into staking's balance.
        assertEq(address(attacker).balance >= attackerEthStart, true, "attacker funds stayed intact");
        assertLe(stakingNativeToken.balance(), stakingBalanceAfterTopup,
            "staking.balance must not have absorbed the attacker's attempted injection");
        assertLe(stakingNativeToken.availableRewards(), stakingRewardsAfterTopup,
            "availableRewards must not have absorbed the attacker's attempted injection");
    }

    /// @dev §A.5 — a nested `deposit()` call from inside `safeTransferFrom` is rejected by the new
    ///      lock on `StakingToken.deposit()`. The hook ERC20's `transferFrom` attempts a low-level
    ///      `deposit(Y)` re-entry from within the outer deposit's safeTransferFrom; the inner
    ///      deposit sees `_locked == 2` and reverts with ReentrancyGuard. The outer deposit still
    ///      completes (the hook swallows the revert), but the re-entry never lands.
    function test_Reentrancy_NestedDeposit_RevertsWithGuard() external {
        uint256 outerAmount = 100 ether;
        uint256 injection = 25 ether;

        hookToken.approve(address(stakingToken), outerAmount);
        uint256 stakingBalanceBefore = stakingToken.balance();
        uint256 stakingRewardsBefore = stakingToken.availableRewards();
        uint256 stakingTokenBalanceBefore = hookToken.balanceOf(address(stakingToken));

        hookToken.armReentry(injection);

        stakingToken.deposit(outerAmount);

        assertTrue(hookToken.reentryAttempted(), "hook token did not attempt re-entry");
        assertFalse(hookToken.reentrySucceeded(), "nested deposit() must be rejected by the lock");
        assertEq(hookToken.reentryErrorSelector(), ReentrancyGuard.selector,
            "nested deposit() must revert with ReentrancyGuard");

        // Outer deposit landed exactly once, no double-counting from the nested call.
        assertEq(stakingToken.balance(), stakingBalanceBefore + outerAmount, "balance delta must equal outerAmount");
        assertEq(stakingToken.availableRewards(), stakingRewardsBefore + outerAmount,
            "availableRewards delta must equal outerAmount");
        assertEq(hookToken.balanceOf(address(stakingToken)), stakingTokenBalanceBefore + outerAmount,
            "staking's token holdings must equal the booked balance");
    }

    /// @dev Honest path: a direct ETH transfer to the native-token staking contract still works
    ///      after the lock extension, and updates balance + availableRewards by msg.value.
    function test_Receive_HonestDepositSucceeds() external {
        uint256 amount = 7 ether;
        uint256 balanceBefore = stakingNativeToken.balance();
        uint256 rewardsBefore = stakingNativeToken.availableRewards();

        (bool ok, ) = address(stakingNativeToken).call{value: amount}("");
        assertTrue(ok, "honest receive must succeed");

        assertEq(stakingNativeToken.balance(), balanceBefore + amount);
        assertEq(stakingNativeToken.availableRewards(), rewardsBefore + amount);
    }

    /// @dev Honest path: a direct deposit() on the token staking contract still works after the
    ///      lock extension, pulls the ERC20 via safeTransferFrom, and updates accounting.
    function test_Deposit_HonestDepositSucceeds() external {
        uint256 amount = 13 ether;
        uint256 balanceBefore = stakingToken.balance();
        uint256 rewardsBefore = stakingToken.availableRewards();
        uint256 heldBefore = hookToken.balanceOf(address(stakingToken));

        // Not arming reentry → hook token behaves as a vanilla ERC20.
        hookToken.approve(address(stakingToken), amount);
        stakingToken.deposit(amount);

        assertEq(stakingToken.balance(), balanceBefore + amount);
        assertEq(stakingToken.availableRewards(), rewardsBefore + amount);
        assertEq(hookToken.balanceOf(address(stakingToken)), heldBefore + amount);
    }

}
