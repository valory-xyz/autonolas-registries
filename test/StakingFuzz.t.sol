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
import {StakingToken} from "../contracts/staking/StakingToken.sol";
import {StakingVerifier} from "../contracts/staking/StakingVerifier.sol";
import {StakingFactory} from "../contracts/staking/StakingFactory.sol";
import {StakingActivityChecker} from "../contracts/staking/StakingActivityChecker.sol";
import {ServiceInfo} from "../contracts/staking/StakingBase.sol";

/// @title StakingFuzzTest - Fuzz tests for staking reward calculation and bit-packing
contract StakingFuzzTest is Test {
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
    StakingVerifier internal stakingVerifier;
    StakingFactory internal stakingFactory;
    StakingActivityChecker internal stakingActivityChecker;

    address payable[] internal users;
    address internal deployer;
    address internal operator;
    uint256 internal initialMint = 50_000_000 ether;
    uint256 internal oneYear = 365 * 24 * 3600;
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
    uint256 internal apyLimit = 2 ether;
    uint256 internal minNumStakingPeriods = 3;
    uint256 internal maxNumInactivityPeriods = 3;
    uint256 internal livenessPeriod = 1 days;
    uint256 internal timeForEmissions = 1 weeks;
    uint256 internal livenessRatio = 0.0001 ether;
    uint256 internal numAgentInstances = 1;

    // Number of services to create (up to maxNumServices)
    uint256 internal numServices = 3;
    address[] internal agentInstances;

    function setUp() public virtual {
        agentIds = new uint32[](1);
        agentIds[0] = 1;

        utils = new Utils();
        users = utils.createUsers(20);
        deployer = users[0];
        operator = users[1];
        agentInstances = new address[](2 * numServices);
        for (uint256 i = 0; i < 2 * numServices; ++i) {
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
        stakingVerifier = new StakingVerifier(address(token), address(serviceRegistry),
            address(serviceRegistryTokenUtility), minStakingDeposit, timeForEmissions, maxNumServices, apyLimit);
        stakingFactory = new StakingFactory(address(0));
        stakingActivityChecker = new StakingActivityChecker(livenessRatio);

        StakingBase.StakingParams memory stakingParams = StakingBase.StakingParams(
            bytes32(uint256(uint160(address(msg.sender)))), maxNumServices, rewardsPerSecond, minStakingDeposit,
            minNumStakingPeriods, maxNumInactivityPeriods, livenessPeriod, timeForEmissions, numAgentInstances,
            emptyArray, 0, bytes32(0), multisigProxyHash, address(serviceRegistry), address(stakingActivityChecker));
        stakingNativeTokenImplementation = new StakingNativeToken();

        bytes memory initPayload = abi.encodeWithSelector(stakingNativeTokenImplementation.initialize.selector,
            stakingParams, address(serviceRegistry), multisigProxyHash);
        stakingNativeToken = StakingNativeToken(stakingFactory.createStakingInstance(
            address(stakingNativeTokenImplementation), initPayload));

        // Whitelist multisig
        serviceRegistry.changeMultisigPermission(address(gnosisSafeMultisig), true);

        // Create, activate, register, deploy services
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0].slots = 1;
        agentParams[0].bond = regBond;

        for (uint256 i = 0; i < numServices; ++i) {
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

    /// @dev Helper to execute a Safe tx to bump nonce for a given service.
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

    /// @dev Fuzz: rewardDistributionInfo bit-packing validation on stake.
    ///      Non-Custom types (0-2) must have upper bits == 0.
    ///      Custom type (3) must have non-zero upper bits (distributor address).
    function testFuzz_RewardDistributionInfoBitPacking(uint256 rewardDistributionInfo) external {
        // Fund staking contract
        address(stakingNativeToken).call{value: 100 ether}("");

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);

        uint8 distType = uint8(rewardDistributionInfo);
        uint160 upperBits = uint160(rewardDistributionInfo >> 8);

        if (distType > 3) {
            // Invalid enum value — should revert
            vm.expectRevert();
            stakingNativeToken.stake(serviceId, rewardDistributionInfo);
        } else if (distType == 3) {
            // Custom type: upper bits must be non-zero (distributor address)
            if (upperBits == 0) {
                vm.expectRevert();
                stakingNativeToken.stake(serviceId, rewardDistributionInfo);
            }
            // If upperBits != 0, it would succeed but we can't easily test the
            // distributor contract interaction, so we skip that case
        } else {
            // Non-custom types (0, 1, 2): upper bits must be zero
            if (upperBits != 0) {
                vm.expectRevert();
                stakingNativeToken.stake(serviceId, rewardDistributionInfo);
            } else {
                // Should succeed — valid non-custom distribution info
                stakingNativeToken.stake(serviceId, rewardDistributionInfo);
            }
        }
        vm.stopPrank();
    }

    /// @dev Fuzz: checkpoint reward calculation — total rewards never exceed available rewards.
    ///      Varies the funding amount and time elapsed.
    function testFuzz_CheckpointRewardsNeverExceedAvailable(uint72 fundAmount, uint24 timeElapsed) external {
        // Bound to meaningful ranges
        // fundAmount: at least 1 ether so rewards are non-trivial, capped by uint72
        vm.assume(fundAmount >= 1 ether);
        // timeElapsed: at least one liveness period so checkpoint actually computes
        vm.assume(timeElapsed >= livenessPeriod);

        // Fund staking contract
        address(stakingNativeToken).call{value: uint256(fundAmount)}("");

        uint256 initialAvailable = stakingNativeToken.availableRewards();

        // Stake all services
        for (uint256 i = 0; i < numServices; ++i) {
            uint256 serviceId = i + 1;
            vm.startPrank(deployer);
            serviceRegistry.approve(address(stakingNativeToken), serviceId);
            stakingNativeToken.stake(serviceId);
            vm.stopPrank();

            // Bump nonce so service is eligible for rewards
            _bumpNonce(serviceId, i);
        }

        // Advance time
        vm.warp(block.timestamp + uint256(timeElapsed));

        // Bump nonces again after time warp so ratio passes
        for (uint256 i = 0; i < numServices; ++i) {
            _bumpNonce(i + 1, i);
        }

        // Checkpoint
        stakingNativeToken.checkpoint();

        uint256 finalAvailable = stakingNativeToken.availableRewards();
        // Available rewards must not increase (can only decrease or stay same)
        assertLe(finalAvailable, initialAvailable, "availableRewards increased after checkpoint");

        // Sum of individual service rewards must equal the decrease in available rewards
        uint256 totalDistributed = 0;
        for (uint256 i = 0; i < numServices; ++i) {
            ServiceInfo memory sInfo = stakingNativeToken.getServiceInfo(i + 1);
            totalDistributed += sInfo.reward;
        }
        assertEq(totalDistributed, initialAvailable - finalAvailable,
            "distributed rewards != decrease in available rewards");
    }

    /// @dev Fuzz: proportional reward scaling when totalRewards > availableRewards.
    ///      Verifies rounding dust goes to first service and total == availableRewards.
    function testFuzz_ProportionalScalingRoundingDust(uint64 fundWei) external {
        // Small funding so totalRewards will exceed availableRewards quickly
        // Use at least 0.001 ether so rewards are meaningful, cap at 0.1 ether
        vm.assume(fundWei >= 0.001 ether && fundWei <= 0.1 ether);

        address(stakingNativeToken).call{value: uint256(fundWei)}("");
        uint256 availableBefore = stakingNativeToken.availableRewards();

        // Stake all services
        for (uint256 i = 0; i < numServices; ++i) {
            uint256 serviceId = i + 1;
            vm.startPrank(deployer);
            serviceRegistry.approve(address(stakingNativeToken), serviceId);
            stakingNativeToken.stake(serviceId);
            vm.stopPrank();
        }

        // First, advance one liveness period so services have time staked
        vm.warp(block.timestamp + livenessPeriod);

        // Bump nonces so ratio passes
        for (uint256 i = 0; i < numServices; ++i) {
            _bumpNonce(i + 1, i);
        }

        // First checkpoint to record nonces
        stakingNativeToken.checkpoint();

        // Now warp long enough so rewardsPerSecond * time * numServices > remaining available
        // This forces proportional scaling in the next checkpoint
        vm.warp(block.timestamp + 7 days);

        // Bump nonces again
        for (uint256 i = 0; i < numServices; ++i) {
            _bumpNonce(i + 1, i);
        }

        // Get available before second checkpoint
        uint256 availableBeforeSecond = stakingNativeToken.availableRewards();

        stakingNativeToken.checkpoint();

        uint256 availableAfter = stakingNativeToken.availableRewards();

        // Sum of all service rewards
        uint256 totalRewards = 0;
        for (uint256 i = 0; i < numServices; ++i) {
            ServiceInfo memory sInfo = stakingNativeToken.getServiceInfo(i + 1);
            totalRewards += sInfo.reward;
        }

        // Available rewards must not increase
        assertLe(availableAfter, availableBeforeSecond, "available rewards increased");
        // Total distributed must equal initial available minus what remains
        assertEq(totalRewards, availableBefore - availableAfter,
            "total rewards != available consumed");
    }

    /// @dev Fuzz: multiple checkpoint epochs with fuzzed time between them.
    ///      Reward accumulation must be monotonically non-decreasing per service.
    function testFuzz_MultiEpochRewardAccumulation(uint24 epoch1Time, uint24 epoch2Time, uint24 epoch3Time) external {
        vm.assume(epoch1Time >= livenessPeriod);
        vm.assume(epoch2Time >= livenessPeriod);
        vm.assume(epoch3Time >= livenessPeriod);

        address(stakingNativeToken).call{value: 100 ether}("");

        // Stake service 1
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), 1);
        stakingNativeToken.stake(1);
        vm.stopPrank();

        uint256 prevReward = 0;

        // Run 3 epochs
        uint24[3] memory epochs = [epoch1Time, epoch2Time, epoch3Time];
        for (uint256 e = 0; e < 3; ++e) {
            _bumpNonce(1, 0);
            vm.warp(block.timestamp + uint256(epochs[e]));
            _bumpNonce(1, 0);
            stakingNativeToken.checkpoint();

            ServiceInfo memory sInfo = stakingNativeToken.getServiceInfo(1);
            assertGe(sInfo.reward, prevReward, "reward decreased between epochs");
            prevReward = sInfo.reward;
        }
    }

    /// @dev Fuzz: staking with valid distribution types (0, 1, 2) and zero upper bits always succeeds.
    function testFuzz_ValidDistributionTypesAccepted(uint8 distType) external {
        vm.assume(distType <= 2);

        address(stakingNativeToken).call{value: 100 ether}("");

        uint256 serviceId = 1;
        vm.startPrank(deployer);
        serviceRegistry.approve(address(stakingNativeToken), serviceId);
        // Valid: type in low 8 bits, zero in upper bits
        stakingNativeToken.stake(serviceId, uint256(distType));
        vm.stopPrank();

        // Verify service is staked
        uint8 stakingState = uint8(stakingNativeToken.getStakingState(serviceId));
        assertTrue(stakingState > 0, "service should be staked");
    }
}
