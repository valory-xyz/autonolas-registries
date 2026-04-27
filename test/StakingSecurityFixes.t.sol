// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IService} from "../contracts/interfaces/IService.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeProxy} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import {GnosisSafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import {Test} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {ERC20Token} from "../contracts/test/ERC20Token.sol";
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
import {StakingActivityChecker} from "../contracts/staking/StakingActivityChecker.sol";
import {ReentrancyStakingAttacker} from "../contracts/test/ReentrancyStakingAttacker.sol";

/// @dev Custom rewards distributor that returns the zero address as a receiver.
contract ZeroAddressDistributor {
    function getRewardReceiversAndAmounts(uint256, address, address, uint256 reward)
        external pure returns (address[] memory receivers, uint256[] memory amounts)
    {
        receivers = new address[](1);
        amounts = new uint256[](1);
        receivers[0] = address(0);
        amounts[0] = reward;
    }
}

/// @dev Custom rewards distributor that returns a valid receiver.
contract ValidDistributor {
    function getRewardReceiversAndAmounts(uint256, address serviceOwner, address, uint256 reward)
        external pure returns (address[] memory receivers, uint256[] memory amounts)
    {
        receivers = new address[](1);
        amounts = new uint256[](1);
        receivers[0] = serviceOwner;
        amounts[0] = reward;
    }
}

/// @title StakingSecurityFixesTest - Unit tests for post-C4R security fixes in StakingBase.
/// @notice Covers:
///         - Reentrancy guards on stake / unstake / forcedUnstake / claim / checkpointAndClaim / checkpoint
///           (audit items 22 and 26).
///         - Custom rewards distributor receiver validation (audit item 23).
///         - Custom rewards distributor contract existence check (audit item 24).
contract StakingSecurityFixesTest is Test {
    Utils internal utils;
    ERC20Token internal token;
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
    StakingNativeToken internal stakingNativeTokenImplementation;
    StakingNativeToken internal stakingNativeToken;
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

    uint256 internal constant NUM_SERVICES = 2;
    address[] internal agentInstances;

    function setUp() public virtual {
        agentIds = new uint32[](1);
        agentIds[0] = 1;

        utils = new Utils();
        users = utils.createUsers(20);
        deployer = users[0];
        operator = users[1];
        agentInstances = new address[](NUM_SERVICES);
        for (uint256 i = 0; i < NUM_SERVICES; ++i) {
            agentInstances[i] = users[i + 2];
        }

        // Deploy registries
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

        // Deploy multisig contracts
        gnosisSafe = new GnosisSafe();
        gnosisSafeProxy = new GnosisSafeProxy(address(gnosisSafe));
        gnosisSafeProxyFactory = new GnosisSafeProxyFactory();
        gnosisSafeMultisig = new GnosisSafeMultisig(payable(address(gnosisSafe)), address(gnosisSafeProxyFactory));

        // Deploy token
        token = new ERC20Token();
        token.mint(deployer, initialMint);
        token.mint(operator, initialMint);

        bytes32 multisigProxyHash = keccak256(address(gnosisSafeProxy).code);

        // Deploy staking infrastructure
        stakingActivityChecker = new StakingActivityChecker(livenessRatio);

        StakingBase.StakingParams memory stakingParams = StakingBase.StakingParams(
            bytes32(uint256(uint160(address(msg.sender)))), maxNumServices, rewardsPerSecond, minStakingDeposit,
            minNumStakingPeriods, maxNumInactivityPeriods, livenessPeriod, timeForEmissions, numAgentInstances,
            emptyArray, 0, bytes32(0), multisigProxyHash, address(serviceRegistry), address(stakingActivityChecker));
        stakingNativeTokenImplementation = new StakingNativeToken();

        // Initialize directly (no proxy) for simpler coverage of reverts
        stakingNativeToken = StakingNativeToken(payable(address(new StakingNativeToken())));
        stakingNativeToken.initialize(stakingParams);

        // Whitelist multisig
        serviceRegistry.changeMultisigPermission(address(gnosisSafeMultisig), true);

        // Create, activate, register, deploy services
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0].slots = 1;
        agentParams[0].bond = regBond;

        for (uint256 i = 0; i < NUM_SERVICES; ++i) {
            serviceManager.create(deployer, serviceManager.ETH_TOKEN_ADDRESS(), unitHash, agentIds,
                agentParams, threshold);
            uint256 serviceId = i + 1;
            vm.prank(deployer);
            serviceManager.activateRegistration{value: regDeposit}(serviceId);
            address[] memory agentInstancesService = new address[](1);
            agentInstancesService[0] = agentInstances[i];
            vm.prank(operator);
            serviceManager.registerAgents{value: regBond}(serviceId, agentInstancesService, agentIds);
            vm.prank(deployer);
            serviceManager.deploy(serviceId, address(gnosisSafeMultisig), payload);
        }
    }

    /// @dev Helper to bump multisig nonce N times to satisfy the liveness ratio check.
    function _bumpNonceN(uint256 serviceId, uint256 agentIdx, uint256 times) internal {
        for (uint256 i = 0; i < times; ++i) {
            _bumpNonce(serviceId, agentIdx);
        }
    }

    function _bumpNonce(uint256 serviceId, uint256 agentIdx) internal {
        ServiceRegistryL2.Service memory service = serviceRegistry.getService(serviceId);
        address payable multisig = payable(service.multisig);
        bytes memory safePayload = abi.encodeWithSelector(bytes4(keccak256("getThreshold()")));

        bytes memory signature = new bytes(65);
        bytes memory bAddress = abi.encode(agentInstances[agentIdx]);
        for (uint256 b = 0; b < 32; ++b) {
            signature[b] = bAddress[b];
        }
        signature[64] = bytes1(0x01);

        vm.prank(agentInstances[agentIdx]);
        GnosisSafe(multisig).execTransaction(multisig, 0, safePayload, Enum.Operation.Call, 0, 0, 0, address(0),
            payable(address(0)), signature);
    }

    /// @dev Item #24: staking with an EOA as custom distributor must revert with ContractOnly.
    function test_CustomDistributor_EOAReverts() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 100 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        // Use an EOA as custom distributor
        address eoaDistributor = users[10];
        uint256 rewardDistributionInfo = uint256(3) | (uint256(uint160(eoaDistributor)) << 8);

        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        vm.expectRevert(abi.encodeWithSignature("ContractOnly(address)", eoaDistributor));
        stakingNativeToken.stake(serviceId, rewardDistributionInfo);
        vm.stopPrank();
    }

    /// @dev Item #24: staking with an undeployed address (code.length == 0) must revert with ContractOnly.
    function test_CustomDistributor_UndeployedAddressReverts() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 100 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        // An address computed but not yet deployed
        address undeployed = address(uint160(uint256(keccak256("undeployed"))));
        assertEq(undeployed.code.length, 0);

        uint256 rewardDistributionInfo = uint256(3) | (uint256(uint160(undeployed)) << 8);

        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        vm.expectRevert(abi.encodeWithSignature("ContractOnly(address)", undeployed));
        stakingNativeToken.stake(serviceId, rewardDistributionInfo);
        vm.stopPrank();
    }

    /// @dev Item #24: staking with a deployed custom distributor contract succeeds.
    function test_CustomDistributor_DeployedContractAccepted() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 100 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        ValidDistributor distributor = new ValidDistributor();
        uint256 rewardDistributionInfo = uint256(3) | (uint256(uint160(address(distributor))) << 8);

        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId, rewardDistributionInfo);
        vm.stopPrank();

        assertEq(uint8(stakingNativeToken.getStakingState(serviceId)), uint8(StakingBase.StakingState.Staked));
    }

    /// @dev Item #23: custom distributor returning address(0) as receiver reverts with ZeroAddress on withdraw.
    function test_CustomDistributor_RejectsZeroAddressReceiver() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 100 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        ZeroAddressDistributor distributor = new ZeroAddressDistributor();
        uint256 rewardDistributionInfo = uint256(3) | (uint256(uint160(address(distributor))) << 8);

        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId, rewardDistributionInfo);
        vm.stopPrank();

        // Accumulate some rewards with enough nonces to pass the liveness ratio check
        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(serviceId, 0, 20);

        // Claim must revert because distributor returns address(0) as receiver
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        stakingNativeToken.checkpointAndClaim(serviceId);
    }

    /// @dev Item #23: custom distributor returning the staking contract as receiver reverts.
    function test_CustomDistributor_RejectsSelfReceiver() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 100 ether}("");
        assertTrue(ok);

        address stakingAddr = address(stakingNativeToken);
        HardcodedSelfDistributor hardcoded = new HardcodedSelfDistributor(stakingAddr);
        uint256 info = uint256(3) | (uint256(uint160(address(hardcoded))) << 8);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId, info);
        vm.stopPrank();

        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(serviceId, 0, 20);

        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedAccount(address)", stakingAddr));
        stakingNativeToken.checkpointAndClaim(serviceId);
    }

    /// @dev Items #22 and #26: claim reentry via ETH callback is blocked by the reentrancy guard.
    ///      The attacker's receive() re-enters checkpointAndClaim; that inner call hits the guard and
    ///      reverts with ReentrancyGuard. The revert propagates through the low-level ETH call in
    ///      _transfer, which then surfaces as TransferFailed on the outer call. The key property
    ///      verified here is that the reentrant claim is not allowed to succeed.
    function test_Reentrancy_ClaimRevertsOnReentry() external {
        ReentrancyStakingAttacker attacker = new ReentrancyStakingAttacker(
            address(stakingNativeToken), address(serviceRegistry));

        (bool ok, ) = address(stakingNativeToken).call{value: 1 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.prank(deployer);
        serviceRegistry.transferFrom(deployer, address(attacker), serviceId);
        attacker.stake(serviceId);

        // Generate enough multisig activity so the ratio passes and a reward accrues
        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(serviceId, 0, 20);

        // The outer call reverts because the inner reentrant call is rejected by the guard.
        // The ETH .call in _transfer swallows the inner ReentrancyGuard() revert and surfaces as TransferFailed.
        vm.expectRevert();
        attacker.checkpointAndClaim(serviceId);
    }

    /// @dev Item #22 support: external checkpoint can still be called normally with the reentrancy guard in place.
    function test_Checkpoint_PublicCallSucceeds() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), 1);
        stakingNativeToken.stake(1);
        vm.stopPrank();

        _bumpNonce(1, 0);
        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonce(1, 0);

        // Must not revert even though external guard is active
        stakingNativeToken.checkpoint();
    }
}

/// @dev Custom distributor that returns a hardcoded self-reference to force the self-receiver check.
contract HardcodedSelfDistributor {
    address internal immutable _target;

    constructor(address target) {
        _target = target;
    }

    function getRewardReceiversAndAmounts(uint256, address, address, uint256 reward)
        external view returns (address[] memory receivers, uint256[] memory amounts)
    {
        receivers = new address[](1);
        amounts = new uint256[](1);
        receivers[0] = _target;
        amounts[0] = reward;
    }
}
