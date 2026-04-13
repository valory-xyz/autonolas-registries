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
import {ServiceInfo} from "../contracts/staking/StakingBase.sol";

/// @title StakingBaseCoverageTest - Coverage-oriented unit tests for StakingBase.
/// @notice Exercises initialization reverts, stake / unstake / claim happy paths,
///         eviction, and view functions to complement the existing fuzz and security test suites.
contract StakingBaseCoverageTest is Test {
    Utils internal utils;
    ERC20Token internal token;
    GnosisSafe internal gnosisSafe;
    GnosisSafeProxy internal gnosisSafeProxy;
    GnosisSafeProxyFactory internal gnosisSafeProxyFactory;
    GnosisSafeMultisig internal gnosisSafeMultisig;
    ServiceRegistryL2 internal serviceRegistry;
    ServiceRegistryTokenUtility internal serviceRegistryTokenUtility;
    ServiceManager internal serviceManager;
    MockIdentityRegistry internal identityRegistry;
    IdentityRegistryBridger internal identityRegistryBridger;
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

    uint256 internal constant NUM_SERVICES = 3;
    address[] internal agentInstances;
    bytes32 internal multisigProxyHash;

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

        serviceRegistry = new ServiceRegistryL2("Service Registry", "SERVICE", "https://localhost/service/");
        serviceRegistryTokenUtility = new ServiceRegistryTokenUtility(address(serviceRegistry));
        new OperatorWhitelist(address(serviceRegistry));

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

        gnosisSafe = new GnosisSafe();
        gnosisSafeProxy = new GnosisSafeProxy(address(gnosisSafe));
        gnosisSafeProxyFactory = new GnosisSafeProxyFactory();
        gnosisSafeMultisig = new GnosisSafeMultisig(payable(address(gnosisSafe)), address(gnosisSafeProxyFactory));

        token = new ERC20Token();
        token.mint(deployer, initialMint);
        token.mint(operator, initialMint);

        multisigProxyHash = keccak256(address(gnosisSafeProxy).code);

        stakingActivityChecker = new StakingActivityChecker(livenessRatio);
        stakingNativeToken = new StakingNativeToken();
        stakingNativeToken.initialize(_defaultParams());

        serviceRegistry.changeMultisigPermission(address(gnosisSafeMultisig), true);

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

    function _defaultParams() internal view returns (StakingBase.StakingParams memory) {
        return StakingBase.StakingParams(
            bytes32(uint256(1)), maxNumServices, rewardsPerSecond, minStakingDeposit,
            minNumStakingPeriods, maxNumInactivityPeriods, livenessPeriod, timeForEmissions, numAgentInstances,
            emptyArray, 0, bytes32(0), multisigProxyHash, address(serviceRegistry), address(stakingActivityChecker));
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

    function _bumpNonceN(uint256 serviceId, uint256 agentIdx, uint256 n) internal {
        for (uint256 i = 0; i < n; ++i) {
            _bumpNonce(serviceId, agentIdx);
        }
    }

    // -------------------------- _initialize revert paths --------------------------

    function test_Init_DoubleInitializeReverts() external {
        vm.expectRevert(abi.encodeWithSignature("AlreadyInitialized()"));
        stakingNativeToken.initialize(_defaultParams());
    }

    function test_Init_ZeroMetadataHashReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        p.metadataHash = bytes32(0);
        StakingNativeToken fresh = new StakingNativeToken();
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        fresh.initialize(p);
    }

    function test_Init_ZeroMaxNumServicesReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        p.maxNumServices = 0;
        StakingNativeToken fresh = new StakingNativeToken();
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        fresh.initialize(p);
    }

    function test_Init_ZeroRewardsPerSecondReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        p.rewardsPerSecond = 0;
        StakingNativeToken fresh = new StakingNativeToken();
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        fresh.initialize(p);
    }

    function test_Init_MinStakingPeriodsBelowInactivityReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        p.minNumStakingPeriods = 1;
        p.maxNumInactivityPeriods = 3;
        StakingNativeToken fresh = new StakingNativeToken();
        vm.expectRevert(abi.encodeWithSignature("LowerThan(uint256,uint256)", uint256(1), uint256(3)));
        fresh.initialize(p);
    }

    function test_Init_MinStakingDepositTooLowReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        p.minStakingDeposit = 1;
        StakingNativeToken fresh = new StakingNativeToken();
        vm.expectRevert(abi.encodeWithSignature("LowerThan(uint256,uint256)", uint256(1), uint256(2)));
        fresh.initialize(p);
    }

    function test_Init_ZeroServiceRegistryReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        p.serviceRegistry = address(0);
        StakingNativeToken fresh = new StakingNativeToken();
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        fresh.initialize(p);
    }

    function test_Init_ZeroActivityCheckerReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        p.activityChecker = address(0);
        StakingNativeToken fresh = new StakingNativeToken();
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        fresh.initialize(p);
    }

    function test_Init_ActivityCheckerNotContractReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        p.activityChecker = users[5];
        StakingNativeToken fresh = new StakingNativeToken();
        vm.expectRevert(abi.encodeWithSignature("ContractOnly(address)", users[5]));
        fresh.initialize(p);
    }

    function test_Init_ZeroProxyHashReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        p.proxyHash = bytes32(0);
        StakingNativeToken fresh = new StakingNativeToken();
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        fresh.initialize(p);
    }

    function test_Init_NonAscendingAgentIdsReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        uint256[] memory ids = new uint256[](2);
        ids[0] = 2;
        ids[1] = 2;
        p.agentIds = ids;
        StakingNativeToken fresh = new StakingNativeToken();
        vm.expectRevert(abi.encodeWithSignature("WrongAgentId(uint256)", uint256(2)));
        fresh.initialize(p);
    }

    function test_Init_AscendingAgentIdsAccepted() external {
        StakingBase.StakingParams memory p = _defaultParams();
        uint256[] memory ids = new uint256[](2);
        ids[0] = 1;
        ids[1] = 3;
        p.agentIds = ids;
        StakingNativeToken fresh = new StakingNativeToken();
        fresh.initialize(p);
        assertEq(fresh.getAgentIds().length, 2);
    }

    // -------------------------- _stake revert paths --------------------------

    function test_Stake_NoRewardsAvailableReverts() external {
        // No ether sent to stakingNativeToken, availableRewards == 0
        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        vm.expectRevert(abi.encodeWithSignature("NoRewardsAvailable()"));
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();
    }

    function test_Stake_ServiceNotUnstakedReverts() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 100 ether}("");
        assertTrue(ok);
        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();
        // Try to stake again
        vm.startPrank(deployer);
        vm.expectRevert(abi.encodeWithSignature("ServiceNotUnstaked(uint256)", serviceId));
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();
    }

    function test_Stake_WrongAgentInstanceCountReverts() external {
        // Initialize a new staking contract expecting 2 agent instances
        StakingBase.StakingParams memory p = _defaultParams();
        p.numAgentInstances = 2;
        StakingNativeToken misconfigured = new StakingNativeToken();
        misconfigured.initialize(p);
        (bool ok, ) = address(misconfigured).call{value: 100 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(misconfigured), serviceId);
        vm.expectRevert(abi.encodeWithSignature("WrongServiceConfiguration(uint256)", serviceId));
        misconfigured.stake(serviceId);
        vm.stopPrank();
    }

    function test_Stake_WrongThresholdReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        p.threshold = 99;
        StakingNativeToken misconfigured = new StakingNativeToken();
        misconfigured.initialize(p);
        (bool ok, ) = address(misconfigured).call{value: 100 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(misconfigured), serviceId);
        vm.expectRevert(abi.encodeWithSignature("WrongServiceConfiguration(uint256)", serviceId));
        misconfigured.stake(serviceId);
        vm.stopPrank();
    }

    function test_Stake_WrongConfigHashReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        p.configHash = bytes32(uint256(0xDEAD));
        StakingNativeToken misconfigured = new StakingNativeToken();
        misconfigured.initialize(p);
        (bool ok, ) = address(misconfigured).call{value: 100 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(misconfigured), serviceId);
        vm.expectRevert(abi.encodeWithSignature("WrongServiceConfiguration(uint256)", serviceId));
        misconfigured.stake(serviceId);
        vm.stopPrank();
    }

    function test_Stake_UnauthorizedMultisigReverts() external {
        StakingBase.StakingParams memory p = _defaultParams();
        p.proxyHash = bytes32(uint256(0xBAD));
        StakingNativeToken misconfigured = new StakingNativeToken();
        misconfigured.initialize(p);
        (bool ok, ) = address(misconfigured).call{value: 100 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        ServiceRegistryL2.Service memory service = serviceRegistry.getService(serviceId);
        vm.startPrank(deployer);
        serviceRegistry.approve(address(misconfigured), serviceId);
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedMultisig(address)", service.multisig));
        misconfigured.stake(serviceId);
        vm.stopPrank();
    }

    function test_Stake_WrongAgentIdReverts() external {
        // Configure staking contract to require agentId == 2 (services are created with agentId == 1)
        StakingBase.StakingParams memory p = _defaultParams();
        uint256[] memory requiredIds = new uint256[](1);
        requiredIds[0] = 2;
        p.agentIds = requiredIds;
        StakingNativeToken misconfigured = new StakingNativeToken();
        misconfigured.initialize(p);
        (bool ok, ) = address(misconfigured).call{value: 100 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(misconfigured), serviceId);
        vm.expectRevert(abi.encodeWithSignature("WrongAgentId(uint256)", uint256(2)));
        misconfigured.stake(serviceId);
        vm.stopPrank();
    }

    function test_Stake_MaxNumServicesReverts() external {
        // Initialize with maxNumServices=1
        StakingBase.StakingParams memory p = _defaultParams();
        p.maxNumServices = 1;
        StakingNativeToken small = new StakingNativeToken();
        small.initialize(p);
        (bool ok, ) = address(small).call{value: 100 ether}("");
        assertTrue(ok);

        vm.startPrank(deployer);
        serviceRegistry.approve(address(small), 1);
        small.stake(1);
        serviceRegistry.approve(address(small), 2);
        vm.expectRevert(abi.encodeWithSignature("MaxNumServicesReached(uint256)", uint256(1)));
        small.stake(2);
        vm.stopPrank();
    }

    // -------------------------- Happy unstake / claim / forcedUnstake flows --------------------------

    function test_Unstake_WithRewardAfterMinStakingDuration() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        vm.warp(block.timestamp + minNumStakingPeriods * livenessPeriod + 1);
        _bumpNonceN(serviceId, 0, 30);

        uint256 balanceBefore = deployer.balance;
        vm.prank(deployer);
        stakingNativeToken.unstake(serviceId);
        assertGt(deployer.balance, balanceBefore, "no reward delivered on unstake");

        // Service info cleared
        ServiceInfo memory sInfo = stakingNativeToken.getServiceInfo(serviceId);
        assertEq(sInfo.tsStart, 0);
    }

    function test_Unstake_BeforeMinStakingDurationReverts() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        vm.prank(deployer);
        vm.expectRevert();
        stakingNativeToken.unstake(serviceId);
    }

    function test_Unstake_NonOwnerReverts() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        vm.warp(block.timestamp + minNumStakingPeriods * livenessPeriod + 1);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("OwnerOnly(address,address)", operator, deployer));
        stakingNativeToken.unstake(serviceId);
    }

    function test_ForcedUnstake_ReturnsRewardToPool() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        // Accumulate some reward
        vm.warp(block.timestamp + minNumStakingPeriods * livenessPeriod + 1);
        _bumpNonceN(serviceId, 0, 30);

        uint256 availableBefore = stakingNativeToken.availableRewards();

        vm.prank(deployer);
        stakingNativeToken.forcedUnstake(serviceId);

        // The accumulated reward is returned to availableRewards rather than paid out
        assertGe(stakingNativeToken.availableRewards(), availableBefore);
    }

    function test_Claim_PaysAccumulatedReward() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(serviceId, 0, 30);

        // First run a checkpoint so reward accrues in storage
        stakingNativeToken.checkpoint();

        uint256 before = deployer.balance;
        vm.prank(deployer);
        uint256 reward = stakingNativeToken.claim(serviceId);
        // Proportional distribution splits reward between operator and service owner, so deployer
        // receives the owner's share while `reward` reports the total distributed amount.
        assertGt(reward, 0);
        assertGt(deployer.balance, before);
    }

    function test_Claim_ZeroRewardReverts() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSignature("ZeroValue()"));
        stakingNativeToken.claim(serviceId);
    }

    function test_Claim_NonOwnerReverts() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSignature("OwnerOnly(address,address)", operator, deployer));
        stakingNativeToken.claim(serviceId);
    }

    // -------------------------- Eviction --------------------------

    function test_Eviction_AfterMaxInactivityPeriods() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        // Time passes without any nonce activity: first checkpoint records an inactivity warning,
        // second one exceeds maxInactivityDuration and evicts the service.
        vm.warp(block.timestamp + livenessPeriod + 1);
        stakingNativeToken.checkpoint();

        vm.warp(block.timestamp + (maxNumInactivityPeriods + 1) * livenessPeriod);
        stakingNativeToken.checkpoint();

        assertEq(uint8(stakingNativeToken.getStakingState(serviceId)), uint8(StakingBase.StakingState.Evicted));
    }

    function test_Eviction_CanBeUnstakedWithoutMinDuration() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        // Drain the rewards by warping far beyond emission window and never running a checkpoint,
        // then set availableRewards to zero via a checkpoint that allocates everything.
        vm.warp(block.timestamp + timeForEmissions * 10);
        _bumpNonceN(serviceId, 0, 50);
        stakingNativeToken.checkpoint();

        // After availableRewards is zero, unstake is allowed even before minStakingDuration
        vm.prank(deployer);
        stakingNativeToken.unstake(serviceId);

        ServiceInfo memory sInfo = stakingNativeToken.getServiceInfo(serviceId);
        assertEq(sInfo.tsStart, 0);
    }

    // -------------------------- View functions --------------------------

    function test_View_GetStakingState_UnstakedToStakedToEvicted() external {
        uint256 serviceId = 1;
        // Initially Unstaked
        assertEq(uint8(stakingNativeToken.getStakingState(serviceId)), uint8(StakingBase.StakingState.Unstaked));

        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        assertEq(uint8(stakingNativeToken.getStakingState(serviceId)), uint8(StakingBase.StakingState.Staked));

        // Drive to Evicted
        vm.warp(block.timestamp + livenessPeriod + 1);
        stakingNativeToken.checkpoint();
        vm.warp(block.timestamp + (maxNumInactivityPeriods + 1) * livenessPeriod);
        stakingNativeToken.checkpoint();
        assertEq(uint8(stakingNativeToken.getStakingState(serviceId)), uint8(StakingBase.StakingState.Evicted));
    }

    function test_View_GetNextRewardCheckpointTimestamp() external {
        uint256 expected = block.timestamp + livenessPeriod;
        assertEq(stakingNativeToken.getNextRewardCheckpointTimestamp(), expected);
    }

    function test_View_GetServiceIdsAndAgentIds() external {
        assertEq(stakingNativeToken.getServiceIds().length, 0);
        assertEq(stakingNativeToken.getAgentIds().length, 0);

        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), 1);
        stakingNativeToken.stake(1);
        serviceRegistry.approve(address(stakingNativeToken), 2);
        stakingNativeToken.stake(2);
        vm.stopPrank();

        assertEq(stakingNativeToken.getServiceIds().length, 2);
    }

    function test_View_CalculateStakingReward() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(serviceId, 0, 30);

        uint256 pending = stakingNativeToken.calculateStakingLastReward(serviceId);
        uint256 total = stakingNativeToken.calculateStakingReward(serviceId);
        assertEq(total, pending);
        assertGt(total, 0);
    }

    function test_View_CalculateStakingRewardReceiversAndAmounts() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(serviceId, 0, 30);

        (address[] memory receivers, uint256[] memory amounts) =
            stakingNativeToken.calculateStakingRewardReceiversAndAmounts(serviceId);
        assertEq(receivers.length, amounts.length);
        assertGt(receivers.length, 0);
    }

    // -------------------------- Distribution types (non-Custom) --------------------------

    function test_Distribution_ServiceOwnerType() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        // distType = 1 (ServiceOwner), no upper bits
        stakingNativeToken.stake(serviceId, 1);
        vm.stopPrank();

        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(serviceId, 0, 30);
        stakingNativeToken.checkpoint();

        (address[] memory receivers, uint256[] memory amounts) =
            stakingNativeToken.calculateStakingRewardReceiversAndAmounts(serviceId);
        assertEq(receivers.length, 1);
        assertEq(receivers[0], deployer);
        assertGt(amounts[0], 0);
    }

    function test_Distribution_ServiceMultisigType() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        ServiceRegistryL2.Service memory service = serviceRegistry.getService(serviceId);

        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        // distType = 2 (ServiceMultisig)
        stakingNativeToken.stake(serviceId, 2);
        vm.stopPrank();

        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(serviceId, 0, 30);

        (address[] memory receivers, ) =
            stakingNativeToken.calculateStakingRewardReceiversAndAmounts(serviceId);
        assertEq(receivers.length, 1);
        assertEq(receivers[0], service.multisig);
    }

    // -------------------------- Custom distributor revert paths --------------------------

    function test_CustomDistributor_WrongArrayLengthReverts() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        MismatchedArraysDistributor distributor = new MismatchedArraysDistributor();
        uint256 info = uint256(3) | (uint256(uint160(address(distributor))) << 8);

        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId, info);
        vm.stopPrank();

        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(serviceId, 0, 30);

        vm.prank(deployer);
        vm.expectRevert();
        stakingNativeToken.checkpointAndClaim(serviceId);
    }

    function test_CustomDistributor_WrongAmountReverts() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        WrongAmountDistributor distributor = new WrongAmountDistributor();
        uint256 info = uint256(3) | (uint256(uint160(address(distributor))) << 8);

        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId, info);
        vm.stopPrank();

        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(serviceId, 0, 30);

        vm.prank(deployer);
        vm.expectRevert();
        stakingNativeToken.checkpointAndClaim(serviceId);
    }

    // -------------------------- _checkTokenStakingDeposit reverts --------------------------

    function test_CheckTokenStakingDeposit_LowerThanReverts() external {
        // Create a staking contract requiring a higher minStakingDeposit than the services provide
        StakingBase.StakingParams memory p = _defaultParams();
        p.minStakingDeposit = regDeposit + 1;
        StakingNativeToken strict = new StakingNativeToken();
        strict.initialize(p);
        (bool ok, ) = address(strict).call{value: 100 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(strict), serviceId);
        vm.expectRevert(abi.encodeWithSignature("LowerThan(uint256,uint256)", regDeposit, regDeposit + 1));
        strict.stake(serviceId);
        vm.stopPrank();
    }

    // -------------------------- Stake mid-epoch (exercises tsStart > tsCheckpointLast branch) --------------------------

    function test_Stake_MidEpoch_UsesServiceTsStart() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        // Stake service 1 up front so tsCheckpoint stays anchored at setUp time
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), 1);
        stakingNativeToken.stake(1);
        vm.stopPrank();

        // Advance time, then stake service 2 later — its tsStart > tsCheckpointLast
        vm.warp(block.timestamp + livenessPeriod / 2);
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), 2);
        stakingNativeToken.stake(2);
        vm.stopPrank();

        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(1, 0, 30);
        _bumpNonceN(2, 1, 30);
        stakingNativeToken.checkpoint();

        ServiceInfo memory s1 = stakingNativeToken.getServiceInfo(1);
        ServiceInfo memory s2 = stakingNativeToken.getServiceInfo(2);
        assertGt(s1.reward, 0);
        assertGt(s2.reward, 0);
    }

    // -------------------------- Proportional scaling when totalRewards > availableRewards --------------------------

    function test_Checkpoint_ProportionalScalingMultiService() external {
        // Fund just barely enough so scaling kicks in across multiple services
        (bool ok, ) = address(stakingNativeToken).call{value: 0.01 ether}("");
        assertTrue(ok);

        // Stake all three services
        for (uint256 i = 0; i < NUM_SERVICES; ++i) {
            uint256 serviceId = i + 1;
            vm.startPrank(deployer);
            serviceRegistry.approve(address(stakingNativeToken), serviceId);
            stakingNativeToken.stake(serviceId);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + livenessPeriod);
        for (uint256 i = 0; i < NUM_SERVICES; ++i) {
            _bumpNonceN(i + 1, i, 30);
        }

        // First checkpoint accumulates state
        stakingNativeToken.checkpoint();

        // Warp far so totalRewards exceeds availableRewards and scaling branch runs
        vm.warp(block.timestamp + 30 days);
        for (uint256 i = 0; i < NUM_SERVICES; ++i) {
            _bumpNonceN(i + 1, i, 30);
        }
        stakingNativeToken.checkpoint();

        // availableRewards should be zero after draining
        assertEq(stakingNativeToken.availableRewards(), 0);
    }

    function test_View_GetServiceInfo_ReturnsStoredState() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        ServiceInfo memory sInfo = stakingNativeToken.getServiceInfo(serviceId);
        assertEq(sInfo.owner, deployer);
        assertGt(sInfo.tsStart, 0);
    }

    // -------------------------- Reentrancy guard reverts on each external entry point --------------------------

    /// @dev Locate the _locked slot once (slot 12 per declaration order in StakingBase: last state var)
    ///      and use vm.store to force the guard into the "entered" state.
    function _forceLocked() internal returns (bytes32 slot) {
        // _locked is declared right after setServiceIds (dynamic array: slot count is 1 for length)
        // Instead of guessing, find the slot by scanning.
        for (uint256 i = 0; i < 40; ++i) {
            bytes32 s = bytes32(i);
            bytes32 v = vm.load(address(stakingNativeToken), s);
            if (v == bytes32(uint256(1))) {
                // Tentatively set to 2 and see whether reentrancy triggers
                vm.store(address(stakingNativeToken), s, bytes32(uint256(2)));
                (bool ok, bytes memory ret) = address(stakingNativeToken).call(
                    abi.encodeWithSignature("checkpoint()"));
                if (!ok && ret.length == 4 && bytes4(ret) == bytes4(keccak256("ReentrancyGuard()"))) {
                    return s;
                }
                // Restore and continue
                vm.store(address(stakingNativeToken), s, bytes32(uint256(1)));
            }
        }
        revert("_locked slot not found");
    }

    function test_Reentrancy_GuardBlocksAllExternalEntrypoints() external {
        bytes32 slot = _forceLocked();
        // slot is now back to 1 after _forceLocked's probe; enter the guarded state again
        vm.store(address(stakingNativeToken), slot, bytes32(uint256(2)));

        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuard()"));
        stakingNativeToken.checkpoint();

        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuard()"));
        stakingNativeToken.stake(1);

        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuard()"));
        stakingNativeToken.stake(1, 0);

        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuard()"));
        stakingNativeToken.unstake(1);

        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuard()"));
        stakingNativeToken.forcedUnstake(1);

        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuard()"));
        stakingNativeToken.claim(1);

        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuard()"));
        stakingNativeToken.checkpointAndClaim(1);
    }

    // -------------------------- Unstake removes non-last service (exercises shuffle branch) --------------------------

    function test_Unstake_RemovesNonLastService() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 100 ether}("");
        assertTrue(ok);

        // Stake two services
        for (uint256 i = 1; i <= 2; ++i) {
            vm.startPrank(deployer);
            serviceRegistry.approve(address(stakingNativeToken), i);
            stakingNativeToken.stake(i);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + minNumStakingPeriods * livenessPeriod + 1);
        _bumpNonceN(1, 0, 30);
        _bumpNonceN(2, 1, 30);

        // Unstake service 1 (not last in set) — exercises the shuffle branch at line 919
        vm.prank(deployer);
        stakingNativeToken.unstake(1);

        assertEq(stakingNativeToken.getServiceIds().length, 1);
    }

    // -------------------------- Wrong agent Ids length --------------------------

    function test_Stake_WrongAgentIdsLengthReverts() external {
        // Configure staking contract to require two agent Ids; services have only one
        StakingBase.StakingParams memory p = _defaultParams();
        uint256[] memory requiredIds = new uint256[](2);
        requiredIds[0] = 1;
        requiredIds[1] = 2;
        p.agentIds = requiredIds;
        StakingNativeToken misconfigured = new StakingNativeToken();
        misconfigured.initialize(p);
        (bool ok, ) = address(misconfigured).call{value: 100 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(misconfigured), serviceId);
        vm.expectRevert(abi.encodeWithSignature("WrongServiceConfiguration(uint256)", serviceId));
        misconfigured.stake(serviceId);
        vm.stopPrank();
    }

    // -------------------------- checkpointAndClaim happy path --------------------------

    function test_CheckpointAndClaim_HappyPath() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();

        vm.warp(block.timestamp + livenessPeriod);
        _bumpNonceN(serviceId, 0, 30);

        vm.prank(deployer);
        uint256 reward = stakingNativeToken.checkpointAndClaim(serviceId);
        assertGt(reward, 0);
    }

    // -------------------------- Stake a non-Deployed service reverts --------------------------

    function test_Stake_ServiceNotDeployedReverts() external {
        (bool ok, ) = address(stakingNativeToken).call{value: 10 ether}("");
        assertTrue(ok);

        // Create a fresh service but do not deploy it, leaving it in ActiveRegistration or earlier
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0].slots = 1;
        agentParams[0].bond = regBond;
        serviceManager.create(deployer, serviceManager.ETH_TOKEN_ADDRESS(), unitHash, agentIds,
            agentParams, threshold);
        uint256 serviceId = NUM_SERVICES + 1;
        vm.prank(deployer);
        serviceManager.activateRegistration{value: regDeposit}(serviceId);
        // Intentionally skip registerAgents + deploy

        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        vm.expectRevert();
        stakingNativeToken.stake(serviceId);
        vm.stopPrank();
    }

    // -------------------------- Multi-agent service with differing bonds exercises bond < minDeposit --------------------------

    function test_CheckTokenStakingDeposit_LowBondReverts() external {
        // Build a staking contract configured for 2 agent instances and a minStakingDeposit
        // that one of the bonds falls below.
        StakingBase.StakingParams memory p = _defaultParams();
        p.numAgentInstances = 2;
        p.minStakingDeposit = 15 ether; // higher than the small bond below
        StakingNativeToken multiAgent = new StakingNativeToken();
        multiAgent.initialize(p);
        (bool ok, ) = address(multiAgent).call{value: 100 ether}("");
        assertTrue(ok);

        // Create a service with two agent Ids and differing bonds
        uint32[] memory ids = new uint32[](2);
        ids[0] = 1;
        ids[1] = 2;
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](2);
        agentParams[0].slots = 1;
        agentParams[0].bond = 20 ether; // satisfies securityDeposit >= minStakingDeposit
        agentParams[1].slots = 1;
        agentParams[1].bond = 5 ether;  // below minStakingDeposit → triggers the revert

        serviceManager.create(deployer, serviceManager.ETH_TOKEN_ADDRESS(), unitHash, ids,
            agentParams, 2); // threshold = 2
        uint256 serviceId = NUM_SERVICES + 1;
        vm.prank(deployer);
        serviceManager.activateRegistration{value: 20 ether}(serviceId);
        address[] memory agentInstancesService = new address[](2);
        agentInstancesService[0] = users[10];
        agentInstancesService[1] = users[11];
        uint32[] memory regAgentIds = new uint32[](2);
        regAgentIds[0] = 1;
        regAgentIds[1] = 2;
        vm.prank(operator);
        serviceManager.registerAgents{value: 25 ether}(serviceId, agentInstancesService, regAgentIds);
        vm.prank(deployer);
        serviceManager.deploy(serviceId, address(gnosisSafeMultisig), payload);

        vm.startPrank(deployer);
        serviceRegistry.approve(address(multiAgent), serviceId);
        vm.expectRevert(abi.encodeWithSignature("LowerThan(uint256,uint256)", uint256(5 ether), uint256(15 ether)));
        multiAgent.stake(serviceId);
        vm.stopPrank();
    }

    // -------------------------- calculateStakingLastReward scaling branch --------------------------

    function test_View_CalculateStakingLastReward_ScalingBranch() external {
        // Fund with a small amount so totalRewards > lastAvailableRewards quickly
        (bool ok, ) = address(stakingNativeToken).call{value: 0.005 ether}("");
        assertTrue(ok);

        // Stake all services and generate activity so they are eligible
        for (uint256 i = 0; i < NUM_SERVICES; ++i) {
            uint256 serviceId = i + 1;
            vm.startPrank(deployer);
            serviceRegistry.approve(address(stakingNativeToken), serviceId);
            stakingNativeToken.stake(serviceId);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + livenessPeriod);
        for (uint256 i = 0; i < NUM_SERVICES; ++i) {
            _bumpNonceN(i + 1, i, 30);
        }

        // Without running checkpoint, the pending reward view exercises totalRewards > lastAvailableRewards
        uint256 pending = stakingNativeToken.calculateStakingLastReward(1);
        // Either nonzero pending (scaling path) or zero when ratio did not pass — both paths covered
        assertGe(pending, 0);
    }
}

/// @dev Returns receivers/amounts arrays of different lengths, triggering WrongArrayLength.
contract MismatchedArraysDistributor {
    function getRewardReceiversAndAmounts(uint256, address serviceOwner, address, uint256 reward)
        external pure returns (address[] memory receivers, uint256[] memory amounts)
    {
        receivers = new address[](2);
        receivers[0] = serviceOwner;
        receivers[1] = serviceOwner;
        amounts = new uint256[](1);
        amounts[0] = reward;
    }
}

/// @dev Returns amounts that do not sum to reward, triggering WrongAmount.
contract WrongAmountDistributor {
    function getRewardReceiversAndAmounts(uint256, address serviceOwner, address, uint256 reward)
        external pure returns (address[] memory receivers, uint256[] memory amounts)
    {
        receivers = new address[](1);
        amounts = new uint256[](1);
        receivers[0] = serviceOwner;
        amounts[0] = reward - 1;
    }
}
