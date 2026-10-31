pragma solidity ^0.8.30;

import {IService} from "../contracts/interfaces/IService.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeProxy} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import {GnosisSafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import {Test, console} from "forge-std/Test.sol";
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
import {StakingToken} from "../contracts/staking/StakingToken.sol";
import {StakingVerifier} from "../contracts/staking/StakingVerifier.sol";
import {StakingFactory} from "../contracts/staking/StakingFactory.sol";
import {StakingActivityChecker} from "../contracts/staking/StakingActivityChecker.sol";
import {SafeNonceLib} from "../contracts/test/SafeNonceLib.sol";

contract BaseSetup is Test {
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
    StakingToken internal stakingTokenImplementation;
    StakingToken internal stakingToken;
    StakingVerifier internal stakingVerifier;
    StakingFactory internal stakingFactory;
    StakingActivityChecker internal stakingActivityChecker;
    SafeNonceLib internal safeNonceLib;

    address payable[] internal users;
    address[] internal agentInstances;
    uint256[] internal serviceIds;
    uint256[] internal emptyArray;
    address internal deployer;
    address internal operator;
    uint256 internal numServices = 300;
    uint256 internal initialMint = 50_000_000 ether;
    uint256 internal largeApproval = 1_000_000_000 ether;
    uint256 internal oneYear = 365 * 24 * 3600;
    uint32 internal threshold = 1;
    uint96 internal regBond = 0.1 ether;
    uint256 internal regDeposit = 0.1 ether;

    bytes32 internal unitHash = 0x9999999999999999999999999999999999999999999999999999999999999999;
    bytes internal payload;
    uint32[] internal agentIds;

    // Maximum number of staking services
    uint256 internal maxNumServices = 500;
    // Rewards per second
    uint256 internal rewardsPerSecond = 549768518;
    // Minimum service staking deposit value required for staking
    uint256 internal minStakingDeposit = regDeposit;
    // APY limit
    uint256 internal apyLimit = 2 ether;
    // Min number of staking periods before the service can be unstaked
    uint256 internal minNumStakingPeriods = 3;
    // Max number of accumulated inactivity periods after which the service is evicted
    uint256 internal maxNumInactivityPeriods = 3;
    // Liveness period
    uint256 internal livenessPeriod = 1 days;
    // Time for emissions
    uint256 internal timeForEmissions = 1 weeks;
    // Liveness ratio in the format of 1e18
    uint256 internal livenessRatio = 1; // One nonce in 3 hours
    // Number of agent instances in the service
    uint256 internal numAgentInstances = 1;

    function _activityCheckerAddress() internal virtual returns (address) {
        stakingActivityChecker = new StakingActivityChecker(livenessRatio);
        return address(stakingActivityChecker);
    }

    function setUp() public virtual {
        agentIds = new uint32[](1);
        agentIds[0] = 1;

        utils = new Utils();
        users = utils.createUsers(numServices * 2 + 2);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        operator = users[1];
        // Allocate several addresses for agent instances
        agentInstances = new address[](2 * numServices);
        for (uint256 i = 0; i < 2 * numServices; ++i) {
            agentInstances[i] = users[i + 2];
        }

        // Deploying registries contracts
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

        // Deploying multisig contracts and multisig implementation
        gnosisSafe = new GnosisSafe();
        gnosisSafeProxy = new GnosisSafeProxy(address(gnosisSafe));
        gnosisSafeProxyFactory = new GnosisSafeProxyFactory();
        gnosisSafeMultisig = new GnosisSafeMultisig(payable(address(gnosisSafe)), address(gnosisSafeProxyFactory));
        safeNonceLib = new SafeNonceLib();

        // Deploying a token contract and minting to deployer, operator and a current contract
        token = new ERC20Token();
        token.mint(deployer, initialMint);
        token.mint(operator, initialMint);
        token.mint(address(this), initialMint);

        // Get the multisig proxy bytecode hash
        bytes32 multisigProxyHash = keccak256(address(gnosisSafeProxy).code);

        // Deploy service staking verifier
        stakingVerifier = new StakingVerifier(address(token), address(serviceRegistry),
            address(serviceRegistryTokenUtility), minStakingDeposit, timeForEmissions, maxNumServices, apyLimit);

        // Deploy service staking factory
        stakingFactory = new StakingFactory(address(0));

        // Deploy service staking activity checker
        address checkerAddress = _activityCheckerAddress();

        // Deploy service staking native token and arbitrary ERC20 token
        StakingBase.StakingParams memory stakingParams = StakingBase.StakingParams(
            bytes32(uint256(uint160(address(msg.sender)))), maxNumServices, rewardsPerSecond, minStakingDeposit,
            minNumStakingPeriods, maxNumInactivityPeriods, livenessPeriod, timeForEmissions, numAgentInstances,
            emptyArray, 0, bytes32(0), multisigProxyHash, address(serviceRegistry), checkerAddress);
        stakingNativeTokenImplementation = new StakingNativeToken();
        stakingTokenImplementation = new StakingToken();

        // Initialization payload and deployment of stakingNativeToken
        bytes memory initPayload = abi.encodeWithSelector(stakingNativeTokenImplementation.initialize.selector,
            stakingParams, address(serviceRegistry), multisigProxyHash);
        stakingNativeToken = StakingNativeToken(stakingFactory.createStakingInstance(
            address(stakingNativeTokenImplementation), initPayload));

        // Set the stakingVerifier
        stakingFactory.changeVerifier(address(stakingVerifier));
        // Initialization payload and deployment of stakingToken
        initPayload = abi.encodeWithSelector(stakingTokenImplementation.initialize.selector,
            stakingParams, address(serviceRegistryTokenUtility), address(token));
        stakingToken = StakingToken(stakingFactory.createStakingInstance(
            address(stakingTokenImplementation), initPayload));

        // Whitelist multisig implementations
        serviceRegistry.changeMultisigPermission(address(gnosisSafeMultisig), true);

        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0].slots = 1;
        agentParams[0].bond = regBond;

        // Create services, activate them, register agent instances and deploy
        for (uint256 i = 0; i < numServices; ++i) {
            // Create a service
            serviceManager.create(deployer, serviceManager.ETH_TOKEN_ADDRESS(), unitHash, agentIds,
                agentParams, threshold);

            uint256 serviceId = i + 1;
            // Activate registration
            vm.prank(deployer);
            serviceManager.activateRegistration{value: regDeposit}(serviceId);

            // Register agent instances
            address[] memory agentInstancesService = new address[](1);
            agentInstancesService[0] = agentInstances[i];
            vm.prank(operator);
            serviceManager.registerAgents{value: regBond}(serviceId, agentInstancesService, agentIds);

            // Deploy the service
            vm.prank(deployer);
            serviceManager.deploy(serviceId, address(gnosisSafeMultisig), payload);
        }

        // Create services with ERC20 token, activate them, register agent instances and deploy
        vm.prank(deployer);
        token.approve(address(serviceRegistryTokenUtility), initialMint);
        vm.prank(operator);
        token.approve(address(serviceRegistryTokenUtility), initialMint);
        for (uint256 i = 0; i < numServices; ++i) {
            // Create a service
            serviceManager.create(deployer, address(token), unitHash, agentIds, agentParams, threshold);

            uint256 serviceId = i + numServices + 1;
            // Activate registration
            vm.prank(deployer);
            serviceManager.activateRegistration{value: 1}(serviceId);

            // Register agent instances
            address[] memory agentInstancesService = new address[](1);
            agentInstancesService[0] = agentInstances[i + numServices];
            vm.prank(operator);
            serviceManager.registerAgents{value: 1}(serviceId, agentInstancesService, agentIds);

            // Deploy the service
            vm.prank(deployer);
            serviceManager.deploy(serviceId, address(gnosisSafeMultisig), payload);
        }
    }
}

contract StakingGasLimit is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Test service staking with random number of executed tx-s (nonces) per day.
    function testNonces() external {
        // Send funds to a native token staking contract
        address(stakingNativeToken).call{value: 1000000 ether}("");

        // Stake services
        for (uint256 i = 0; i < numServices; ++i) {
            uint256 serviceId = i + 1;
            vm.startPrank(deployer);
            serviceRegistry.approve(address(stakingNativeToken), serviceId);
            stakingNativeToken.stake(serviceId);
            vm.stopPrank();
        }

        // Get the Safe data payload
        payload = abi.encodeWithSelector(bytes4(keccak256("getThreshold()")));
        // Number of services
        for (uint256 j = 0; j < numServices; ++j) {
            uint256 serviceId = j + 1;
            ServiceRegistryL2.Service memory service = serviceRegistry.getService(serviceId);
            address payable multisig = payable(service.multisig);

            // Get the nonce before
            uint256 nonceBefore = GnosisSafe(multisig).nonce();

            // Increase multisig nonce
            // Get the signature
            bytes memory signature = new bytes(65);
            bytes memory bAddress = abi.encode(agentInstances[j]);
            for (uint256 b = 0; b < 32; ++b) {
                signature[b] = bAddress[b];
            }
            for (uint256 b = 32; b < 64; ++b) {
                signature[b] = bytes1(0x00);
            }
            signature[64] = bytes1(0x01);

            vm.prank(agentInstances[j]);
            GnosisSafe(multisig).execTransaction(multisig, 0, payload, Enum.Operation.Call, 0, 0, 0, address(0),
                payable(address(0)), signature);

            // Get the nonce after transactions
            uint256 nonceAfter = GnosisSafe(multisig).nonce();
            assertGe(nonceAfter, nonceBefore);
        }

        // Move several liveness checks ahead
        vm.warp(block.timestamp + livenessPeriod + 100);

        // Call the checkpoint
        stakingNativeToken.checkpoint();
    }
}
// Synthetic checker for bounding checkpoint cost, not a production checker implementation.
contract CheckpointGasChecker {
    uint256 public nonce;
    uint256 public count = 4;
    bool public failRead;
    bool public failRatio;

    function configure(uint256 value, uint256 size, bool readFailure, bool ratioFailure) external {
        nonce = value;
        count = size;
        failRead = readFailure;
        failRatio = ratioFailure;
    }

    function _consumeAllowance() private view {
        // Checkpoint calls receive 100k gas. Leave enough to encode the return value. Uncapped stake()
        // reads spend a bounded 97k instead of consuming the enclosing transaction's entire allowance.
        uint256 remaining = gasleft();
        uint256 floor = remaining > 100_000 ? remaining - 97_000 : 1_500;
        assembly {
            for {} gt(gas(), floor) {} {}
        }
    }

    function getMultisigNonces(address) external view returns (uint256[] memory values) {
        if (failRead) {
            assembly { invalid() }
        }
        values = new uint256[](count);
        for (uint256 i; i < values.length; ++i) {
            values[i] = nonce;
        }
        _consumeAllowance();
    }

    function isRatioPass(uint256[] calldata, uint256[] calldata, uint256) external view returns (bool) {
        if (failRatio) {
            assembly { invalid() }
        }
        _consumeAllowance();
        return true;
    }
}

// Run with --isolate: every external call must use a fresh transaction context (cold storage).
// CHECKPOINT_GAS_BUDGET is the full transaction budget, including 21,064 intrinsic gas for checkpoint().
contract StakingTokenCheckpointGas is BaseSetup {
    CheckpointGasChecker internal checker;
    uint256 internal gasBudget;
    uint256 internal constant CHECKPOINT_INTRINSIC_GAS = 21_064;

    function _activityCheckerAddress() internal override returns (address) {
        checker = new CheckpointGasChecker();
        return address(checker);
    }

    function setUp() public override {
        numServices = vm.envOr("CHECKPOINT_SERVICE_COUNT", uint256(44));
        maxNumServices = numServices;
        gasBudget = vm.envOr("CHECKPOINT_GAS_BUDGET", uint256(15_000_000));
        super.setUp();
        token.approve(address(stakingToken), initialMint);
        stakingToken.deposit(initialMint);
        for (uint256 i = numServices + 1; i <= 2 * numServices; ++i) {
            vm.startPrank(deployer);
            serviceRegistry.approve(address(stakingToken), i);
            stakingToken.stake(i);
            vm.stopPrank();
        }
    }

    function _measure(string memory label) internal returns (uint256 numEligible) {
        // Run the reviewed bytecode under the selected execution rules without recompiling it.
        vm.setEvmVersion(vm.envOr("CHECKPOINT_EVM_VERSION", string("prague")));
        uint256 epoch = stakingToken.epochCounter();
        vm.warp(block.timestamp + livenessPeriod + 1);
        (, uint256[] memory eligible, , ) = stakingToken.checkpoint{gas: gasBudget - CHECKPOINT_INTRINSIC_GAS}();
        // In --isolate mode gasTotalUsed already includes intrinsic gas.
        uint256 measured = vm.lastCallGas().gasTotalUsed;
        console.log(label, measured);
        assertLe(measured, gasBudget, "checkpoint transaction budget exceeded");
        assertEq(stakingToken.epochCounter(), epoch + 1, "checkpoint did not execute");
        return eligible.length;
    }

    function testFirstRewardAndSteadyState() public {
        checker.configure(1, 4, false, false);
        assertEq(_measure("first reward / zero-to-nonzero counters"), numServices);
        assertGt(stakingToken.getServiceInfo(numServices + 1).reward, 0);
        checker.configure(2, 4, false, false);
        assertEq(_measure("steady rewards"), numServices);
    }

    function testReadFailureAndRecovery() public {
        checker.configure(0, 4, true, false);
        _measure("first read failure");
        assertTrue(stakingToken.mapServiceIdBaselineMissing(numServices + 1));
        _measure("repeated read failure");
        checker.configure(1, 4, false, false);
        assertEq(_measure("baseline recovery"), 0);
        for (uint256 i = numServices + 1; i <= 2 * numServices; ++i) {
            assertFalse(stakingToken.mapServiceIdBaselineMissing(i));
        }
        assertEq(stakingToken.getServiceInfo(numServices + 1).reward, 0);
    }

    function testRatioFailureAndEviction() public {
        checker.configure(1, 4, false, true);
        _measure("first ratio failure");
        _measure("repeated ratio failure");
        _measure("ratio failure eviction");
        assertEq(stakingToken.getServiceIds().length, 0);
    }

    function testRebaselineAfterRefill() public {
        // Reach an empty reserve through normal reward allocation, then refill after a timestamp gap.
        uint256 emptyAfter = initialMint / (numServices * rewardsPerSecond) + 1;
        vm.warp(block.timestamp + emptyAfter);
        checker.configure(1, 4, false, false);
        assertEq(_measure("reserve exhaustion"), numServices);
        assertEq(stakingToken.availableRewards(), 0);
        vm.warp(block.timestamp + 1);
        token.mint(address(this), initialMint);
        token.approve(address(stakingToken), initialMint);
        stakingToken.deposit(initialMint);
        assertTrue(stakingToken.rebaselinePending());
        checker.configure(2, 4, false, false);
        assertEq(_measure("refill re-baseline"), 0);
        assertFalse(stakingToken.rebaselinePending());
    }
}
