// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IService} from "../contracts/interfaces/IService.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeProxy} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import {GnosisSafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import {Test, Vm, stdStorage, StdStorage} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {ERC20Token} from "../contracts/test/ERC20Token.sol";
import {GnosisSafeMultisig} from "../contracts/multisigs/GnosisSafeMultisig.sol";
import {ServiceRegistryL2} from "../contracts/ServiceRegistryL2.sol";
import {ServiceRegistryTokenUtility} from "../contracts/ServiceRegistryTokenUtility.sol";
import {ServiceManager} from "../contracts/ServiceManager.sol";
import {ServiceManagerProxy} from "../contracts/ServiceManagerProxy.sol";
import {MockIdentityRegistry} from "../contracts/test/MockIdentityRegistry.sol";
import {IdentityRegistryBridger} from "../contracts/8004/IdentityRegistryBridger.sol";
import {IdentityRegistryBridgerProxy} from "../contracts/8004/IdentityRegistryBridgerProxy.sol";
import "../contracts/staking/StakingNativeToken.sol";
import {StakingToken} from "../contracts/staking/StakingToken.sol";

/// @dev Activity checker with directly settable counters [nonce, deliveries] per multisig.
/// @notice isRatioPass applies the MechActivityChecker rule (requester V1 is the same rule over requests):
///         both counters must grow, deliveries must not exceed the nonce growth, and the delivery rate must
///         reach the liveness ratio. Per multisig, a read can revert, exhaust its gas, return more than the
///         maximum number of counters, return a non-canonical encoding, or return an empty array.
contract MockCounterActivityChecker {
    enum Mode {
        Normal,
        RevertRead,
        EmptyRead,
        OutOfGasRead,
        OversizedRead,
        NonCanonicalRead
    }

    uint256 public immutable livenessRatio;
    // Ratio checks revert when set
    bool public ratioReverts;
    mapping(address => uint256[2]) public counters;
    mapping(address => Mode) public modes;

    constructor(uint256 _livenessRatio) {
        livenessRatio = _livenessRatio;
    }

    function addCounters(address multisig, uint256 nonceDelta, uint256 deliveriesDelta) external {
        counters[multisig][0] += nonceDelta;
        counters[multisig][1] += deliveriesDelta;
    }

    function setMode(address multisig, Mode mode) external {
        modes[multisig] = mode;
    }

    function setRatioReverts(bool value) external {
        ratioReverts = value;
    }

    function getMultisigNonces(address multisig) external view returns (uint256[] memory nonces) {
        Mode mode = modes[multisig];
        if (mode == Mode.RevertRead) {
            revert();
        }
        if (mode == Mode.EmptyRead) {
            return nonces;
        }
        if (mode == Mode.OutOfGasRead) {
            // Spin until the call's gas allowance is exhausted
            while (true) {}
        }
        if (mode == Mode.OversizedRead) {
            // One counter more than StakingBase.MAX_ACTIVITY_CHECKER_NONCES
            return new uint256[](5);
        }
        if (mode == Mode.NonCanonicalRead) {
            // A two-element array whose offset word is 0x40 instead of the canonical 0x20
            bytes memory raw = abi.encode(uint256(0x40), uint256(0), uint256(2), uint256(1), uint256(1));
            assembly {
                return(add(raw, 0x20), mload(raw))
            }
        }
        nonces = new uint256[](2);
        nonces[0] = counters[multisig][0];
        nonces[1] = counters[multisig][1];
    }

    function isRatioPass(uint256[] memory curNonces, uint256[] memory lastNonces, uint256 ts)
        external view returns (bool ratioPass)
    {
        if (ratioReverts) {
            revert();
        }
        if (ts > 0 && curNonces[0] > lastNonces[0] && curNonces[1] > lastNonces[1]) {
            uint256 diffNonces = curNonces[0] - lastNonces[0];
            uint256 diffDeliveries = curNonces[1] - lastNonces[1];
            if (diffDeliveries <= diffNonces) {
                ratioPass = ((diffDeliveries * 1e18) / ts >= livenessRatio);
            }
        }
    }
}

/// @title StakingRebaselineTest - Re-baseline after a refill of an empty reward reserve, and missing baselines.
contract StakingRebaselineTest is Test {
    using stdStorage for StdStorage;

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
    StakingNativeToken internal staking;
    MockCounterActivityChecker internal checker;
    StakingBase.StakingParams internal stakingParams;

    address payable[] internal users;
    address internal deployer;
    address internal operator;
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
    // One delivery passes over any interval up to ~11.5 days
    uint256 internal livenessRatio = 1e12;
    uint256 internal numAgentInstances = 1;

    // Less than a single service earns in one liveness period: the first funded checkpoint drains it
    uint256 internal constant SMALL_FUND = 0.01 ether;
    uint256 internal constant LARGE_FUND = 100 ether;
    uint256 internal constant NUM_SERVICES = 3;
    address[] internal agentInstances;

    bytes32 internal constant REBASELINED_TOPIC = keccak256("ServicesRebaselined(uint256)");
    bytes32 internal constant CHECKPOINT_TOPIC = keccak256("Checkpoint(uint256,uint256,uint256[],uint256[],uint256)");
    bytes32 internal constant BASELINE_MISSING_TOPIC = keccak256("ServiceBaselineMissing(uint256,uint256)");
    bytes32 internal constant BASELINE_RECOVERED_TOPIC = keccak256("ServiceBaselineRecovered(uint256,uint256)");
    bytes32 internal constant EVICTED_TOPIC =
        keccak256("ServicesEvicted(uint256,uint256[],address[],address[],uint256[])");

    function setUp() public {
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

        token = new ERC20Token();

        // Deploy the staking instance
        checker = new MockCounterActivityChecker(livenessRatio);
        stakingParams = StakingBase.StakingParams(
            bytes32(uint256(uint160(address(msg.sender)))), maxNumServices, rewardsPerSecond, minStakingDeposit,
            minNumStakingPeriods, maxNumInactivityPeriods, livenessPeriod, timeForEmissions, numAgentInstances,
            emptyArray, 0, bytes32(0), keccak256(address(gnosisSafeProxy).code), address(serviceRegistry),
            address(checker));
        staking = new StakingNativeToken();
        staking.initialize(stakingParams);

        // Whitelist multisig
        serviceRegistry.changeMultisigPermission(address(gnosisSafeMultisig), true);

        // Create, activate, register and deploy services
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

    // ---------------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------------

    function _fund(uint256 amount) internal {
        (bool success, ) = address(staking).call{value: amount}("");
        assertTrue(success);
    }

    function _multisig(uint256 serviceId) internal view returns (address) {
        return serviceRegistry.getService(serviceId).multisig;
    }

    function _stake(uint256 serviceId) internal {
        vm.startPrank(deployer);
        serviceRegistry.approve(address(staking), serviceId);
        staking.stake(serviceId);
        vm.stopPrank();
    }

    function _stakeAll() internal {
        for (uint256 i = 1; i <= NUM_SERVICES; ++i) {
            _stake(i);
        }
    }

    /// @dev One delivery in one Safe transaction: passes the liveness ratio over one liveness period.
    function _act(uint256 serviceId) internal {
        checker.addCounters(_multisig(serviceId), 1, 1);
    }

    function _actAll() internal {
        for (uint256 i = 1; i <= NUM_SERVICES; ++i) {
            _act(i);
        }
    }

    function _nonces(uint256 serviceId) internal view returns (uint256[] memory) {
        return staking.getServiceInfo(serviceId).nonces;
    }

    function _reward(uint256 serviceId) internal view returns (uint256) {
        return staking.getServiceInfo(serviceId).reward;
    }

    function _inactivity(uint256 serviceId) internal view returns (uint256) {
        return staking.getServiceInfo(serviceId).inactivity;
    }

    function _countLogs(Vm.Log[] memory logs, bytes32 topic) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == topic) {
                ++count;
            }
        }
    }

    /// @dev All services staked with a small reserve, then one active epoch drains it to zero.
    function _stakeAndDrain() internal {
        _fund(SMALL_FUND);
        _stakeAll();
        vm.warp(block.timestamp + livenessPeriod);
        _actAll();
        staking.checkpoint();
        assertEq(staking.availableRewards(), 0);
        assertFalse(staking.rebaselinePending());
    }

    /// @dev All services staked with a large reserve, the first-stake re-baseline already done.
    function _stakeFunded() internal {
        _fund(LARGE_FUND);
        _stakeAll();
        assertFalse(staking.rebaselinePending());
    }

    function _assertRebaselined(uint256 epochBefore) internal view {
        assertFalse(staking.rebaselinePending());
        assertEq(staking.epochCounter(), epochBefore + 1);
        assertEq(staking.tsCheckpoint(), block.timestamp);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Refill flag
    // ---------------------------------------------------------------------------------------------------------------

    function test_NativeRefillOfEmptyReserveSetsFlag() external {
        assertFalse(staking.rebaselinePending());
        _fund(1 ether);
        assertTrue(staking.rebaselinePending());
        assertEq(staking.balance(), 1 ether);
        assertEq(staking.availableRewards(), 1 ether);
    }

    function test_ZeroAdditionsAndFundedTopUpsDoNotSetFlag() external {
        // A zero addition to an empty reserve
        _fund(0);
        assertFalse(staking.rebaselinePending());

        // Refill, then clear the flag with a checkpoint
        _fund(1 ether);
        staking.checkpoint();
        assertFalse(staking.rebaselinePending());

        // A top-up of a funded reserve
        _fund(1 ether);
        assertFalse(staking.rebaselinePending());
    }

    function test_TokenDepositRefillSetsFlag() external {
        StakingToken stakingToken = new StakingToken();
        stakingToken.initialize(stakingParams, address(serviceRegistryTokenUtility), address(token));
        token.mint(address(this), 10 ether);
        token.approve(address(stakingToken), 10 ether);

        // A zero deposit does not set the flag
        stakingToken.deposit(0);
        assertFalse(stakingToken.rebaselinePending());

        // A refill of an empty reserve does
        stakingToken.deposit(1 ether);
        assertTrue(stakingToken.rebaselinePending());
        assertEq(stakingToken.balance(), 1 ether);
        assertEq(stakingToken.availableRewards(), 1 ether);

        // A top-up after the re-baseline does not
        stakingToken.checkpoint();
        assertFalse(stakingToken.rebaselinePending());
        stakingToken.deposit(1 ether);
        assertFalse(stakingToken.rebaselinePending());
    }

    function test_ForcedUnstakeReturnRefillsEmptyReserveAndSetsFlag() external {
        _stakeAndDrain();
        uint256 reward = _reward(1);
        assertGt(reward, 0);
        uint256 balanceBefore = staking.balance();

        // The forfeited reward is returned after the call's own checkpoint, which had nothing to do
        uint256 epochBefore = staking.epochCounter();
        vm.prank(deployer);
        staking.forcedUnstake(1);
        assertEq(staking.epochCounter(), epochBefore);
        assertTrue(staking.rebaselinePending());
        assertEq(staking.availableRewards(), reward);
        // Recycling does not increase the recorded balance
        assertEq(staking.balance(), balanceBefore);

        // The following checkpoint re-baselines
        staking.checkpoint();
        _assertRebaselined(epochBefore);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Re-baseline
    // ---------------------------------------------------------------------------------------------------------------

    function test_BatchedDeliveriesDuringOutageDoNotEvict() external {
        _stakeAndDrain();

        // Outage longer than the maximum inactivity: checkpoints do nothing while the reserve is empty
        vm.warp(block.timestamp + 2 days);
        staking.checkpoint();
        vm.warp(block.timestamp + 3 days);
        // Ten deliveries batched in one Safe transaction during the outage
        checker.addCounters(_multisig(1), 1, 10);

        // Refill and re-baseline: nothing is evicted
        _fund(LARGE_FUND);
        vm.recordLogs();
        staking.checkpoint();
        assertEq(_countLogs(vm.getRecordedLogs(), EVICTED_TOPIC), 0);
        assertEq(uint8(staking.getStakingState(1)), uint8(StakingBase.StakingState.Staked));

        // One delivery after the baseline passes: the gap activity is not carried into the ratio
        uint256 rewardBefore = _reward(1);
        vm.warp(block.timestamp + livenessPeriod);
        _act(1);
        staking.checkpoint();
        assertEq(_reward(1) - rewardBefore, rewardsPerSecond * livenessPeriod);
        assertEq(_inactivity(1), 0);
    }

    function test_QuickRefillReBaselinesAndForfeitsTheIntervalBeforeIt() external {
        _stakeAndDrain();
        uint256 rewardBefore = _reward(1);

        // Refill an hour after the draining checkpoint; the next checkpoint is the re-baseline
        vm.warp(block.timestamp + 1 hours);
        _fund(LARGE_FUND);
        vm.warp(block.timestamp + livenessPeriod - 1 hours);
        _act(1);
        uint256 epochBefore = staking.epochCounter();
        staking.checkpoint();
        _assertRebaselined(epochBefore);
        // The interval before the baseline earns nothing, even though the service was active
        assertEq(_reward(1), rewardBefore);

        // Rewards resume from the baseline
        vm.warp(block.timestamp + livenessPeriod);
        _act(1);
        staking.checkpoint();
        assertEq(_reward(1) - rewardBefore, rewardsPerSecond * livenessPeriod);
    }

    function test_ReBaselinePreservesRewardsAndInactivity() external {
        _fund(SMALL_FUND);
        _stakeAll();
        // Service 3 is inactive in the draining epoch
        vm.warp(block.timestamp + livenessPeriod);
        _act(1);
        _act(2);
        staking.checkpoint();
        assertEq(staking.availableRewards(), 0);
        uint256 reward1 = _reward(1);
        uint256 inactivity3 = _inactivity(3);
        assertGt(reward1, 0);
        assertEq(inactivity3, livenessPeriod);

        // Long outage with activity, then refill
        vm.warp(block.timestamp + 5 days);
        _actAll();
        _fund(LARGE_FUND);

        uint256 epochBefore = staking.epochCounter();
        uint256 epochLength = block.timestamp - staking.tsCheckpoint();
        uint256[] memory empty;
        vm.expectEmit(true, false, false, true, address(staking));
        emit StakingBase.Checkpoint(epochBefore, LARGE_FUND, empty, empty, epochLength);
        vm.recordLogs();
        staking.checkpoint();
        assertEq(_countLogs(vm.getRecordedLogs(), EVICTED_TOPIC), 0);

        _assertRebaselined(epochBefore);
        assertEq(_reward(1), reward1);
        assertEq(_inactivity(3), inactivity3);
        assertEq(staking.availableRewards(), LARGE_FUND);
        // Fresh counters were recorded for every service
        for (uint256 i = 1; i <= NUM_SERVICES; ++i) {
            uint256[] memory nonces = _nonces(i);
            assertEq(nonces[0], checker.counters(_multisig(i), 0));
            assertEq(nonces[1], checker.counters(_multisig(i), 1));
        }
    }

    function test_ReBaselineWithNoServicesUpdatesEpochAndTimestamp() external {
        vm.warp(block.timestamp + 10 days);
        _fund(1 ether);

        uint256 epochLength = block.timestamp - staking.tsCheckpoint();
        uint256[] memory empty;
        vm.expectEmit(true, false, false, true, address(staking));
        emit StakingBase.Checkpoint(0, 1 ether, empty, empty, epochLength);
        staking.checkpoint();
        _assertRebaselined(0);
    }

    function test_FailedReadDuringReBaselineMarksWithoutInactivity() external {
        _stakeAndDrain();
        uint256[] memory noncesBefore = _nonces(1);

        vm.warp(block.timestamp + 5 days);
        _act(1);
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.RevertRead);
        _fund(LARGE_FUND);

        vm.expectEmit(true, true, false, true, address(staking));
        emit StakingBase.ServiceBaselineMissing(staking.epochCounter(), 1);
        staking.checkpoint();

        assertTrue(staking.mapServiceIdBaselineMissing(1));
        assertEq(_inactivity(1), 0);
        assertEq(_nonces(1), noncesBefore);
    }

    /// @dev A normal checkpoint marks service 1 while healthy services exhaust the reserve.
    function _markServiceAndDrain() internal {
        _fund(SMALL_FUND);
        _stakeAll();
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.RevertRead);
        vm.warp(block.timestamp + livenessPeriod);
        _actAll();
        staking.checkpoint();
        assertTrue(staking.mapServiceIdBaselineMissing(1));
        assertEq(_inactivity(1), livenessPeriod);
        assertEq(staking.availableRewards(), 0);
    }

    function test_ReBaselineRecoversAlreadyMarkedService() external {
        _markServiceAndDrain();
        uint256 rewardBefore = _reward(1);
        uint256 inactivityBefore = _inactivity(1);
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.Normal);
        vm.warp(block.timestamp + 5 days);
        _act(1);
        _fund(LARGE_FUND);
        uint256 epochBefore = staking.epochCounter();

        vm.expectEmit(true, true, false, true, address(staking));
        emit StakingBase.ServiceBaselineRecovered(epochBefore, 1);
        vm.recordLogs();
        staking.checkpoint();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertRebaselined(epochBefore);
        assertFalse(staking.mapServiceIdBaselineMissing(1));
        assertEq(_countLogs(logs, BASELINE_RECOVERED_TOPIC), 1);
        assertEq(_countLogs(logs, BASELINE_MISSING_TOPIC), 0);
        assertEq(_nonces(1)[0], checker.counters(_multisig(1), 0));
        assertEq(_nonces(1)[1], checker.counters(_multisig(1), 1));
        assertEq(_reward(1), rewardBefore);
        assertEq(_inactivity(1), inactivityBefore);
        assertEq(staking.availableRewards(), LARGE_FUND);
    }

    function test_ReBaselineRepeatedFailureDoesNotEmitMissingAgain() external {
        _markServiceAndDrain();
        uint256[] memory noncesBefore = _nonces(1);
        uint256 rewardBefore = _reward(1);
        uint256 inactivityBefore = _inactivity(1);
        vm.warp(block.timestamp + 5 days);
        _act(1);
        // A non-reverting hostile response is also a failed read during re-baselining.
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.OversizedRead);
        _fund(LARGE_FUND);
        uint256 epochBefore = staking.epochCounter();

        vm.recordLogs();
        staking.checkpoint();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertRebaselined(epochBefore);
        assertTrue(staking.mapServiceIdBaselineMissing(1));
        assertEq(_countLogs(logs, BASELINE_MISSING_TOPIC), 0);
        assertEq(_countLogs(logs, BASELINE_RECOVERED_TOPIC), 0);
        assertEq(_nonces(1), noncesBefore);
        assertEq(_reward(1), rewardBefore);
        assertEq(_inactivity(1), inactivityBefore);
        assertEq(staking.availableRewards(), LARGE_FUND);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Re-baseline marker event
    // ---------------------------------------------------------------------------------------------------------------

    /// @dev Returns the number of ServicesRebaselined events, and checks each carries the Checkpoint epoch.
    function _countRebaselined(Vm.Log[] memory logs) internal pure returns (uint256 count) {
        uint256 checkpointEpoch = type(uint256).max;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 1 && logs[i].topics[0] == CHECKPOINT_TOPIC) {
                checkpointEpoch = uint256(logs[i].topics[1]);
            }
        }
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 1 && logs[i].topics[0] == REBASELINED_TOPIC) {
                assertEq(uint256(logs[i].topics[1]), checkpointEpoch);
                ++count;
            }
        }
    }

    function test_ServicesRebaselinedOnceOnReBaseline() external {
        uint256 epochBefore = _drainAndRefill();
        vm.expectEmit(true, false, false, true, address(staking));
        emit StakingBase.ServicesRebaselined(epochBefore);
        vm.recordLogs();
        staking.checkpoint();
        assertEq(_countRebaselined(vm.getRecordedLogs()), 1);
    }

    function test_ServicesRebaselinedOnceOnEmptyInstance() external {
        _fund(1 ether);
        vm.expectEmit(true, false, false, true, address(staking));
        emit StakingBase.ServicesRebaselined(0);
        vm.recordLogs();
        staking.checkpoint();
        assertEq(_countRebaselined(vm.getRecordedLogs()), 1);
    }

    function test_ServicesRebaselinedNeverOnNormalCheckpoint() external {
        _stakeFunded();

        // A normal checkpoint with eligible services
        vm.warp(block.timestamp + livenessPeriod);
        _actAll();
        vm.recordLogs();
        staking.checkpoint();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countLogs(logs, CHECKPOINT_TOPIC), 1);
        assertEq(_countRebaselined(logs), 0);

        // A normal checkpoint where no service is eligible: still not a re-baseline
        vm.warp(block.timestamp + livenessPeriod);
        vm.recordLogs();
        staking.checkpoint();
        logs = vm.getRecordedLogs();
        assertEq(_countLogs(logs, CHECKPOINT_TOPIC), 1);
        assertEq(_countRebaselined(logs), 0);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Re-baseline entry points: every _checkpoint() entry runs it, without waiting for the liveness period
    // ---------------------------------------------------------------------------------------------------------------

    function _drainAndRefill() internal returns (uint256 epochBefore) {
        _stakeAndDrain();
        vm.warp(block.timestamp + 5 days);
        _fund(LARGE_FUND);
        assertTrue(staking.rebaselinePending());
        epochBefore = staking.epochCounter();
    }

    function test_EntryPoint_Checkpoint() external {
        uint256 epochBefore = _drainAndRefill();
        staking.checkpoint();
        _assertRebaselined(epochBefore);
    }

    function test_EntryPoint_Stake() external {
        // Stake two services, so that a third one can stake after the refill
        _fund(SMALL_FUND);
        _stake(1);
        _stake(2);
        vm.warp(block.timestamp + livenessPeriod);
        _act(1);
        _act(2);
        staking.checkpoint();
        assertEq(staking.availableRewards(), 0);
        vm.warp(block.timestamp + 5 days);
        _fund(LARGE_FUND);
        uint256 epochBefore = staking.epochCounter();

        _stake(3);
        _assertRebaselined(epochBefore);
    }

    function test_EntryPoint_Unstake() external {
        uint256 epochBefore = _drainAndRefill();
        vm.prank(deployer);
        staking.unstake(1);
        _assertRebaselined(epochBefore);
    }

    function test_EntryPoint_ForcedUnstake() external {
        uint256 epochBefore = _drainAndRefill();
        vm.prank(deployer);
        staking.forcedUnstake(1);
        // The returned reward tops up a funded reserve, so the flag stays clear
        _assertRebaselined(epochBefore);
    }

    function test_EntryPoint_CheckpointAndClaim() external {
        uint256 epochBefore = _drainAndRefill();
        uint256 reward = _reward(1);
        vm.prank(deployer);
        // Only the previously earned reward is claimed
        assertEq(staking.checkpointAndClaim(1), reward);
        _assertRebaselined(epochBefore);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Missing baselines at funded normal checkpoints
    // ---------------------------------------------------------------------------------------------------------------

    function test_FailedReadMarksKeepsCountersAndCountsInactivity() external {
        _stakeFunded();
        uint256[] memory noncesBefore = _nonces(1);
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.RevertRead);

        vm.warp(block.timestamp + livenessPeriod);
        _actAll();
        vm.recordLogs();
        staking.checkpoint();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countLogs(logs, BASELINE_MISSING_TOPIC), 1);

        assertTrue(staking.mapServiceIdBaselineMissing(1));
        assertEq(_nonces(1), noncesBefore);
        assertEq(_reward(1), 0);
        assertEq(_inactivity(1), livenessPeriod);
        // Healthy services earn
        assertEq(_reward(2), rewardsPerSecond * livenessPeriod);

        // A repeated failure counts inactivity again, without a second event
        vm.warp(block.timestamp + livenessPeriod);
        _actAll();
        vm.recordLogs();
        staking.checkpoint();
        assertEq(_countLogs(vm.getRecordedLogs(), BASELINE_MISSING_TOPIC), 0);
        assertEq(_inactivity(1), 2 * livenessPeriod);
        assertEq(_nonces(1), noncesBefore);
        assertEq(_reward(1), 0);
    }

    /// @dev A hostile counter response is a failed read: marked once, counters kept, no reward, inactivity counted.
    function _assertHostileReadIsFailedRead(MockCounterActivityChecker.Mode mode) internal {
        _stakeFunded();
        uint256[] memory noncesBefore = _nonces(1);
        checker.setMode(_multisig(1), mode);

        vm.warp(block.timestamp + livenessPeriod);
        _actAll();
        vm.recordLogs();
        staking.checkpoint();
        assertEq(_countLogs(vm.getRecordedLogs(), BASELINE_MISSING_TOPIC), 1);

        assertTrue(staking.mapServiceIdBaselineMissing(1));
        assertEq(_nonces(1), noncesBefore);
        assertEq(_reward(1), 0);
        assertEq(_inactivity(1), livenessPeriod);
        // The checkpoint completes for everyone else
        assertEq(_reward(2), rewardsPerSecond * livenessPeriod);
        assertEq(_reward(3), rewardsPerSecond * livenessPeriod);
    }

    function test_OutOfGasReadIsFailedRead() external {
        _assertHostileReadIsFailedRead(MockCounterActivityChecker.Mode.OutOfGasRead);
    }

    function test_OversizedReadIsFailedRead() external {
        _assertHostileReadIsFailedRead(MockCounterActivityChecker.Mode.OversizedRead);
    }

    function test_NonCanonicalReadIsFailedRead() external {
        _assertHostileReadIsFailedRead(MockCounterActivityChecker.Mode.NonCanonicalRead);
    }

    function test_RecoveryReadSetsFreshBaselineWithoutRewardOrInactivityChange() external {
        _stakeFunded();
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.RevertRead);
        vm.warp(block.timestamp + livenessPeriod);
        staking.checkpoint();
        assertEq(_inactivity(1), livenessPeriod);

        // Recovery: the stored counters are not scored, the read only records a fresh baseline
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.Normal);
        checker.addCounters(_multisig(1), 5, 5);
        vm.warp(block.timestamp + livenessPeriod);
        vm.expectEmit(true, true, false, true, address(staking));
        emit StakingBase.ServiceBaselineRecovered(staking.epochCounter(), 1);
        staking.checkpoint();

        assertFalse(staking.mapServiceIdBaselineMissing(1));
        assertEq(_reward(1), 0);
        assertEq(_inactivity(1), livenessPeriod);
        uint256[] memory nonces = _nonces(1);
        assertEq(nonces[0], 5);
        assertEq(nonces[1], 5);

        // The next measured passing interval rewards and resets the inactivity
        vm.warp(block.timestamp + livenessPeriod);
        _act(1);
        staking.checkpoint();
        assertEq(_reward(1), rewardsPerSecond * livenessPeriod);
        assertEq(_inactivity(1), 0);
    }

    function test_RatioCheckFailureKeepsReadCounters() external {
        _stakeFunded();
        checker.setRatioReverts(true);
        vm.warp(block.timestamp + livenessPeriod);
        checker.addCounters(_multisig(1), 3, 2);
        staking.checkpoint();

        assertFalse(staking.mapServiceIdBaselineMissing(1));
        uint256[] memory nonces = _nonces(1);
        assertEq(nonces[0], 3);
        assertEq(nonces[1], 2);
        assertEq(_reward(1), 0);
        assertEq(_inactivity(1), livenessPeriod);
    }

    function test_EmptyArrayReadIsValid() external {
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.EmptyRead);
        _stakeFunded();
        assertEq(_nonces(1).length, 0);

        vm.warp(block.timestamp + livenessPeriod);
        vm.recordLogs();
        staking.checkpoint();
        assertEq(_countLogs(vm.getRecordedLogs(), BASELINE_MISSING_TOPIC), 0);

        // Not marked; the checker's own ratio check fails on the empty format, so the service scores inactive
        assertFalse(staking.mapServiceIdBaselineMissing(1));
        assertEq(_inactivity(1), livenessPeriod);
    }

    function test_MarkerClearedOnUnstakeAndStake() external {
        _stakeFunded();
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.RevertRead);
        vm.warp(block.timestamp + livenessPeriod);
        staking.checkpoint();
        assertTrue(staking.mapServiceIdBaselineMissing(1));

        // Unstake clears the marker
        vm.warp(block.timestamp + 3 * livenessPeriod);
        vm.prank(deployer);
        staking.unstake(1);
        assertFalse(staking.mapServiceIdBaselineMissing(1));

        // Stake clears a marker left in storage
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.Normal);
        stdstore.target(address(staking)).sig(staking.mapServiceIdBaselineMissing.selector).with_key(uint256(1))
            .checked_write(true);
        assertTrue(staking.mapServiceIdBaselineMissing(1));
        _stake(1);
        assertFalse(staking.mapServiceIdBaselineMissing(1));
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------------------------------------------------

    function test_ViewsWhileReBaselinePending() external {
        _drainAndRefill();
        _actAll();
        uint256 reward = _reward(1);
        assertGt(reward, 0);

        assertEq(staking.calculateStakingLastReward(1), 0);
        assertEq(staking.calculateStakingReward(1), reward);
    }

    function test_ViewsForMarkedService() external {
        _stakeFunded();
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.RevertRead);
        vm.warp(block.timestamp + livenessPeriod);
        staking.checkpoint();

        // Recovering service: the interval earns nothing; a healthy service earns
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.Normal);
        vm.warp(block.timestamp + livenessPeriod);
        _actAll();
        assertEq(staking.calculateStakingLastReward(1), 0);
        assertEq(staking.calculateStakingLastReward(2), rewardsPerSecond * livenessPeriod);
        assertEq(staking.calculateStakingReward(2), _reward(2) + rewardsPerSecond * livenessPeriod);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Acceptance
    // ---------------------------------------------------------------------------------------------------------------

    /// @dev (a) The first deposit and the first stake perform an empty re-baseline; the first eligible reward
    ///      checkpoint pays normally.
    function test_Acceptance_FirstDepositFirstStake() external {
        vm.warp(block.timestamp + 10 days);
        _fund(LARGE_FUND);
        assertTrue(staking.rebaselinePending());

        uint256 epochLength = block.timestamp - staking.tsCheckpoint();
        uint256[] memory empty;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(staking), 1);
        vm.expectEmit(true, false, false, true, address(staking));
        emit StakingBase.Checkpoint(0, LARGE_FUND, empty, empty, epochLength);
        staking.stake(1);
        vm.stopPrank();
        _assertRebaselined(0);

        vm.warp(block.timestamp + livenessPeriod);
        _act(1);
        staking.checkpoint();
        assertEq(_reward(1), rewardsPerSecond * livenessPeriod);
    }

    /// @dev (b) A persistent counter-read failure eventually evicts the affected service, while healthy services
    ///      continue earning.
    function test_Acceptance_PersistentReadFailureEvicts() external {
        _stakeFunded();
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.RevertRead);

        uint256 maxInactivity = staking.maxInactivityDuration();
        uint256 epochs;
        while (uint8(staking.getStakingState(1)) == uint8(StakingBase.StakingState.Staked)) {
            vm.warp(block.timestamp + livenessPeriod);
            _actAll();
            staking.checkpoint();
            ++epochs;
            assertEq(_reward(2), epochs * rewardsPerSecond * livenessPeriod);
            assertEq(_reward(3), epochs * rewardsPerSecond * livenessPeriod);
        }
        assertEq(uint8(staking.getStakingState(1)), uint8(StakingBase.StakingState.Evicted));
        assertEq(epochs, maxInactivity / livenessPeriod + 1);
        assertEq(_reward(1), 0);
    }

    /// @dev (c) Normal checkpoints before the liveness period add no inactivity and change no baselines.
    function test_Acceptance_LivenessPeriodGate() external {
        _stakeFunded();
        uint256[] memory nonces1 = _nonces(1);
        uint256[] memory nonces2 = _nonces(2);
        uint256 epochBefore = staking.epochCounter();
        uint256 tsBefore = staking.tsCheckpoint();

        // Half a period later, with a failing read and fresh activity
        vm.warp(block.timestamp + livenessPeriod / 2);
        checker.setMode(_multisig(1), MockCounterActivityChecker.Mode.RevertRead);
        _act(2);
        staking.checkpoint();
        assertEq(staking.epochCounter(), epochBefore);
        assertEq(staking.tsCheckpoint(), tsBefore);
        assertFalse(staking.mapServiceIdBaselineMissing(1));
        assertEq(_inactivity(1), 0);
        assertEq(_nonces(1), nonces1);
        assertEq(_nonces(2), nonces2);
    }

    /// @dev (c) Only a pending re-baseline bypasses the liveness period wait.
    function test_Acceptance_PendingReBaselineBypassesLivenessPeriod() external {
        _stakeAndDrain();
        vm.warp(block.timestamp + 1 hours);
        _fund(LARGE_FUND);
        uint256 epochBefore = staking.epochCounter();
        assertLt(block.timestamp - staking.tsCheckpoint(), livenessPeriod);

        staking.checkpoint();
        _assertRebaselined(epochBefore);
    }

    // ERC20 funding with real token-secured services, including reward settlement.
    function _tokenLifecycleSetup() internal returns (StakingToken tokenStaking, uint256[2] memory ids) {
        tokenStaking = new StakingToken();
        tokenStaking.initialize(stakingParams, address(serviceRegistryTokenUtility), address(token));
        token.mint(address(this), LARGE_FUND + SMALL_FUND);
        token.approve(address(tokenStaking), type(uint256).max);
        for (uint256 i = 0; i < 2; ++i) {
            address account = i == 0 ? deployer : operator;
            token.mint(account, 100 ether);
            vm.prank(account);
            token.approve(address(serviceRegistryTokenUtility), type(uint256).max);
        }

        IService.AgentParams[] memory params = new IService.AgentParams[](1);
        params[0] = IService.AgentParams({slots: 1, bond: regBond});
        address[] memory instances = new address[](1);
        for (uint256 i = 0; i < 2; ++i) {
            ids[i] = serviceManager.create(deployer, address(token), unitHash, agentIds, params, threshold);
            vm.prank(deployer);
            serviceManager.activateRegistration{value: 1}(ids[i]);
            instances[0] = users[i + 5];
            vm.prank(operator);
            serviceManager.registerAgents{value: 1}(ids[i], instances, agentIds);
            vm.prank(deployer);
            serviceManager.deploy(ids[i], address(gnosisSafeMultisig), payload);
        }
        tokenStaking.deposit(SMALL_FUND);
        for (uint256 i = 0; i < 2; ++i) {
            vm.startPrank(deployer);
            serviceRegistry.approve(address(tokenStaking), ids[i]);
            tokenStaking.stake(ids[i]);
            vm.stopPrank();
        }
    }

    function _assertTokenClaim(StakingToken tokenStaking, uint256 serviceId, uint256 reward) internal {
        uint256 ownerBefore = token.balanceOf(deployer);
        uint256 operatorBefore = token.balanceOf(operator);
        uint256 heldBefore = token.balanceOf(address(tokenStaking));
        uint256 balanceBefore = tokenStaking.balance();
        uint256 availableBefore = tokenStaking.availableRewards();
        vm.prank(deployer);
        assertEq(tokenStaking.claim(serviceId), reward);
        assertEq(tokenStaking.getServiceInfo(serviceId).reward, 0);
        assertEq(token.balanceOf(operator), operatorBefore + reward / 2);
        assertEq(token.balanceOf(deployer), ownerBefore + reward - reward / 2);
        assertEq(token.balanceOf(address(tokenStaking)), heldBefore - reward);
        assertEq(tokenStaking.balance(), balanceBefore - reward);
        assertEq(tokenStaking.availableRewards(), availableBefore);
    }

    function test_TokenLifecycleRefillFailureRecoveryAndClaim() external {
        (StakingToken tokenStaking, uint256[2] memory ids) = _tokenLifecycleSetup();
        assertEq(serviceRegistry.ownerOf(ids[0]), address(tokenStaking));
        assertEq(serviceRegistry.ownerOf(ids[1]), address(tokenStaking));
        assertFalse(tokenStaking.rebaselinePending());

        uint256[] memory previous = tokenStaking.getServiceInfo(ids[0]).nonces;
        checker.setMode(_multisig(ids[0]), MockCounterActivityChecker.Mode.RevertRead);
        vm.warp(block.timestamp + livenessPeriod);
        _act(ids[1]);
        tokenStaking.checkpoint();
        assertTrue(tokenStaking.mapServiceIdBaselineMissing(ids[0]));
        assertEq(tokenStaking.getServiceInfo(ids[0]).nonces, previous);
        assertEq(tokenStaking.getServiceInfo(ids[0]).inactivity, livenessPeriod);
        assertEq(tokenStaking.getServiceInfo(ids[0]).reward, 0);
        assertEq(tokenStaking.getServiceInfo(ids[1]).reward, SMALL_FUND);
        assertEq(tokenStaking.availableRewards(), 0);

        vm.warp(block.timestamp + 5 days);
        checker.setMode(_multisig(ids[0]), MockCounterActivityChecker.Mode.Normal);
        checker.addCounters(_multisig(ids[0]), 5, 5);
        _act(ids[1]);
        tokenStaking.deposit(LARGE_FUND);
        assertTrue(tokenStaking.rebaselinePending());
        assertEq(token.balanceOf(address(tokenStaking)), SMALL_FUND + LARGE_FUND);
        assertEq(tokenStaking.balance(), SMALL_FUND + LARGE_FUND);
        uint256 epochBefore = tokenStaking.epochCounter();
        vm.expectEmit(true, true, false, true, address(tokenStaking));
        emit StakingBase.ServiceBaselineRecovered(epochBefore, ids[0]);
        tokenStaking.checkpoint();
        assertFalse(tokenStaking.rebaselinePending());
        assertFalse(tokenStaking.mapServiceIdBaselineMissing(ids[0]));
        assertEq(tokenStaking.epochCounter(), epochBefore + 1);
        assertEq(tokenStaking.tsCheckpoint(), block.timestamp);
        assertEq(tokenStaking.getServiceInfo(ids[0]).nonces[0], 5);
        assertEq(tokenStaking.getServiceInfo(ids[0]).nonces[1], 5);
        assertEq(tokenStaking.getServiceInfo(ids[0]).reward, 0);
        assertEq(tokenStaking.getServiceInfo(ids[0]).inactivity, livenessPeriod);
        assertEq(tokenStaking.getServiceInfo(ids[1]).reward, SMALL_FUND);
        assertEq(tokenStaking.getServiceInfo(ids[1]).inactivity, 0);
        assertEq(tokenStaking.availableRewards(), LARGE_FUND);

        vm.warp(block.timestamp + livenessPeriod);
        _act(ids[0]);
        _act(ids[1]);
        tokenStaking.checkpoint();
        uint256 reward = rewardsPerSecond * livenessPeriod;
        assertEq(tokenStaking.getServiceInfo(ids[0]).reward, reward);
        assertEq(tokenStaking.getServiceInfo(ids[0]).inactivity, 0);
        assertEq(tokenStaking.getServiceInfo(ids[1]).reward, SMALL_FUND + reward);
        assertEq(tokenStaking.availableRewards(), LARGE_FUND - 2 * reward);
        _assertTokenClaim(tokenStaking, ids[0], reward);
        _assertTokenClaim(tokenStaking, ids[1], SMALL_FUND + reward);
        assertEq(token.balanceOf(address(tokenStaking)), tokenStaking.balance());
        assertEq(tokenStaking.balance(), tokenStaking.availableRewards());
    }

    function test_PlainClaimWhileRebaselinePendingDoesNotCheckpoint() external {
        uint256 epochBefore = _drainAndRefill();
        uint256 timestampBefore = staking.tsCheckpoint();
        uint256 reward = _reward(1);
        uint256 balanceBefore = staking.balance();
        uint256 ownerBefore = deployer.balance;
        uint256 operatorBefore = operator.balance;
        assertGt(reward, 0);
        vm.recordLogs();
        vm.prank(deployer);
        assertEq(staking.claim(1), reward);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_countLogs(logs, CHECKPOINT_TOPIC), 0);
        assertEq(_countLogs(logs, REBASELINED_TOPIC), 0);
        assertEq(_countLogs(logs, BASELINE_MISSING_TOPIC), 0);
        assertEq(_countLogs(logs, BASELINE_RECOVERED_TOPIC), 0);
        assertTrue(staking.rebaselinePending());
        assertEq(staking.epochCounter(), epochBefore);
        assertEq(staking.tsCheckpoint(), timestampBefore);
        assertEq(staking.availableRewards(), LARGE_FUND);
        assertEq(_reward(1), 0);
        assertEq(staking.balance(), balanceBefore - reward);
        assertEq(deployer.balance, ownerBefore + reward - reward / 2);
        assertEq(operator.balance, operatorBefore + reward / 2);
        assertEq(serviceRegistry.ownerOf(1), address(staking));
        for (uint256 i = 1; i <= NUM_SERVICES; ++i) {
            assertFalse(staking.mapServiceIdBaselineMissing(i));
            assertEq(_inactivity(i), 0);
            assertEq(_nonces(i)[0], 1);
            assertEq(_nonces(i)[1], 1);
        }
        assertEq(staking.calculateStakingLastReward(1), 0);
    }
}
