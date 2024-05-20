pragma solidity =0.8.25;

import {IService} from "../contracts/interfaces/IService.sol";
import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {GnosisSafeProxy} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import {GnosisSafeProxyFactory} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxyFactory.sol";
import {Test} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {ERC20Token} from "../contracts/test/ERC20Token.sol";
import {ServiceRegistryL2} from "../contracts/ServiceRegistryL2.sol";
import {ServiceRegistryTokenUtility} from "../contracts/ServiceRegistryTokenUtility.sol";
import {ServiceManagerToken} from "../contracts/ServiceManagerToken.sol";
import {OperatorWhitelist} from "../contracts/utils/OperatorWhitelist.sol";
import {GnosisSafeMultisig} from "../contracts/multisigs/GnosisSafeMultisig.sol";
import "../contracts/staking/StakingNativeToken.sol";
import {StakingToken} from "../contracts/staking/StakingToken.sol";
import {StakingVerifier} from "../contracts/staking/StakingVerifier.sol";
import {StakingFactory} from "../contracts/staking/StakingFactory.sol";
import {StakingActivityChecker} from "../contracts/staking/StakingActivityChecker.sol";
import {SafeNonceLib} from "../contracts/test/SafeNonceLib.sol";

contract BaseSetup is Test {
    Utils internal utils;
    ERC20Token internal token;
    ServiceRegistryL2 internal serviceRegistry;
    ServiceRegistryTokenUtility internal serviceRegistryTokenUtility;
    OperatorWhitelist internal operatorWhitelist;
    ServiceManagerToken internal serviceManagerToken;
    GnosisSafe internal gnosisSafe;
    GnosisSafeProxy internal gnosisSafeProxy;
    GnosisSafeProxyFactory internal gnosisSafeProxyFactory;
    GnosisSafeMultisig internal gnosisSafeMultisig;
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
    uint256 internal numServices = 3;
    uint256 internal initialMint = 50_000_000 ether;
    uint256 internal largeApproval = 1_000_000_000 ether;
    uint256 internal oneYear = 365 * 24 * 3600;
    uint32 internal threshold = 1;
    uint96 internal regBond = 1000;
    uint256 internal regDeposit = 1000;
    uint256 internal numDays = 10;

    bytes32 internal unitHash = 0x9999999999999999999999999999999999999999999999999999999999999999;
    bytes internal payload;
    uint32[] internal agentIds;

    // Maximum number of staking services
    uint256 internal maxNumServices = 10;
    // Rewards per second
    uint256 internal rewardsPerSecond = 0.0001 ether;
    // Minimum service staking deposit value required for staking
    uint256 internal minStakingDeposit = regDeposit;
    // Min number of staking periods before the service can be unstaked
    uint256 internal minNumStakingPeriods = 3;
    // Max number of accumulated inactivity periods after which the service is evicted
    uint256 internal maxNumInactivityPeriods = 3;
    // Liveness period
    uint256 internal livenessPeriod = 1 days;
    // Time for emissions
    uint256 internal timeForEmissions = 1 weeks;
    // Liveness ratio in the format of 1e18
    uint256 internal livenessRatio = 0.0001 ether; // One nonce in 3 hours
    // Number of agent instances in the service
    uint256 internal numAgentInstances = 1;

    function setUp() public virtual {
        agentIds = new uint32[](1);
        agentIds[0] = 1;

        utils = new Utils();
        users = utils.createUsers(20);
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
        serviceManagerToken = new ServiceManagerToken(address(serviceRegistry), address(serviceRegistryTokenUtility), address(operatorWhitelist));
        serviceRegistry.changeManager(address(serviceManagerToken));
        serviceRegistryTokenUtility.changeManager(address(serviceManagerToken));

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
        stakingVerifier = new StakingVerifier(address(token), rewardsPerSecond, timeForEmissions, maxNumServices);

        // Deploy service staking factory
        stakingFactory = new StakingFactory(address(0));

        // Deploy service staking activity checker
        stakingActivityChecker = new StakingActivityChecker(livenessRatio);

        // Deploy service staking native token and arbitrary ERC20 token
        StakingBase.StakingParams memory stakingParams = StakingBase.StakingParams(
            bytes32(uint256(uint160(address(msg.sender)))), maxNumServices, rewardsPerSecond, minStakingDeposit,
            minNumStakingPeriods, maxNumInactivityPeriods, livenessPeriod, timeForEmissions, numAgentInstances,
            emptyArray, 0, bytes32(0), multisigProxyHash, address(serviceRegistry), address(stakingActivityChecker));
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
            serviceManagerToken.create(deployer, serviceManagerToken.ETH_TOKEN_ADDRESS(), unitHash, agentIds,
                agentParams, threshold);

            uint256 serviceId = i + 1;
            // Activate registration
            vm.prank(deployer);
            serviceManagerToken.activateRegistration{value: regDeposit}(serviceId);

            // Register agent instances
            address[] memory agentInstancesService = new address[](1);
            agentInstancesService[0] = agentInstances[i];
            vm.prank(operator);
            serviceManagerToken.registerAgents{value: regBond}(serviceId, agentInstancesService, agentIds);

            // Deploy the service
            vm.prank(deployer);
            serviceManagerToken.deploy(serviceId, address(gnosisSafeMultisig), payload);
        }

        // Create services with ERC20 token, activate them, register agent instances and deploy
        vm.prank(deployer);
        token.approve(address(serviceRegistryTokenUtility), initialMint);
        vm.prank(operator);
        token.approve(address(serviceRegistryTokenUtility), initialMint);
        for (uint256 i = 0; i < numServices; ++i) {
            // Create a service
            serviceManagerToken.create(deployer, address(token), unitHash, agentIds, agentParams, threshold);

            uint256 serviceId = i + numServices + 1;
            // Activate registration
            vm.prank(deployer);
            serviceManagerToken.activateRegistration{value: 1}(serviceId);

            // Register agent instances
            address[] memory agentInstancesService = new address[](1);
            agentInstancesService[0] = agentInstances[i + numServices];
            vm.prank(operator);
            serviceManagerToken.registerAgents{value: 1}(serviceId, agentInstancesService, agentIds);

            // Deploy the service
            vm.prank(deployer);
            serviceManagerToken.deploy(serviceId, address(gnosisSafeMultisig), payload);
        }
    }
}

contract Staking is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Test service staking with random number of executed tx-s (nonces) per day.
    /// @param numNonces Number of nonces per day.
    function testNonces(uint8 numNonces) external {
        // Send funds to a native token staking contract
        address(stakingNativeToken).call{value: 100 ether}("");

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
        // Number of days
        for (uint256 i = 0; i < numDays; ++i) {
            // Number of services
            for (uint256 j = 0; j < numServices; ++j) {
                uint256 serviceId = j + 1;
                ServiceRegistryL2.Service memory service = serviceRegistry.getService(serviceId);
                address payable multisig = payable(service.multisig);

                // Get the nonce before
                uint256 nonceBefore = GnosisSafe(multisig).nonce();

                // Execute a specified number of nonces
                for (uint8 n = 0; n < numNonces; ++n) {
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
                }

                // Get the nonce after transactions
                uint256 nonceAfter = GnosisSafe(multisig).nonce();
                assertGe(nonceAfter, nonceBefore);
            }

            // Move several liveness checks ahead
            vm.warp(block.timestamp + livenessPeriod * stakingNativeToken.maxNumInactivityPeriods() + 1);

            // Call the checkpoint
            stakingNativeToken.checkpoint();

            // Unstake if there are no available rewards
            if (stakingNativeToken.availableRewards() == 0) {
                for (uint256 j = 0; j < numServices; ++j) {
                    uint256 serviceId = j + 1;
                    // Unstake if the service is not yet unstaked, otherwise ignore
                    if (uint8(stakingNativeToken.getStakingState(serviceId)) > 0) {
                        vm.startPrank(deployer);
                        stakingNativeToken.unstake(serviceId);
                        vm.stopPrank();
                    }
                }
            }
        }
    }

    /// @dev Test service staking with random number of executed tx-s (nonces) per day.
    /// @notice Service Id == 3 is inactive, i.e., doe not execute tx-s.
    /// @param numNonces Number of nonces per day.
    function testNoncesLimited(uint8 numNonces) external {
        // Send funds to a native token staking contract
        address(stakingNativeToken).call{value: 100 ether}("");

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
        // Number of days
        for (uint256 i = 0; i < numDays; ++i) {
            // Number of services that perform tx-s except for the serviceId == 3
            for (uint256 j = 0; j < numServices - 1; ++j) {
                uint256 serviceId = j + 1;
                ServiceRegistryL2.Service memory service = serviceRegistry.getService(serviceId);
                address payable multisig = payable(service.multisig);

                // Get the nonce before
                uint256 nonceBefore = GnosisSafe(multisig).nonce();

                // Execute a specified number of nonces
                for (uint8 n = 0; n < numNonces; ++n) {
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
                }

                // Get the nonce after transactions
                uint256 nonceAfter = GnosisSafe(multisig).nonce();
                assertGe(nonceAfter, nonceBefore);
            }

            // Move several liveness checks ahead
            vm.warp(block.timestamp + livenessPeriod * stakingNativeToken.maxNumInactivityPeriods() + 1);

            // Call the checkpoint
            stakingNativeToken.checkpoint();

            // Unstake if there are no available rewards
            if (stakingNativeToken.availableRewards() == 0) {
                for (uint256 j = 0; j < numServices; ++j) {
                    uint256 serviceId = j + 1;
                    // Unstake if the service is not yet unstaked, otherwise ignore
                    if (uint8(stakingNativeToken.getStakingState(serviceId)) > 0) {
                        vm.startPrank(deployer);
                        stakingNativeToken.unstake(serviceId);
                        vm.stopPrank();
                    }
                }
            }
        }
    }

    /// @dev Test service staking with random number of nonces that can be manipulated.
    /// @param numNonces Number of nonces to increase / decrease per day.
    function testManipulateNonces(uint128 numNonces) external {
        // Send funds to a native token staking contract
        address(stakingNativeToken).call{value: 100 ether}("");

        // Stake services
        for (uint256 i = 0; i < numServices; ++i) {
            uint256 serviceId = i + 1;
            vm.startPrank(deployer);
            serviceRegistry.approve(address(stakingNativeToken), serviceId);
            stakingNativeToken.stake(serviceId);
            vm.stopPrank();
        }

        // Number of days
        for (uint256 i = 0; i < numDays; ++i) {
            // Get the Safe data payload
            if (numDays & uint256(1) == 0) {
                // Even days - increase the nonce
                payload = abi.encodeWithSelector(bytes4(keccak256("increaseNonce(uint256)")), numNonces);
            } else {
                // Odd days - decrease the nonce
                payload = abi.encodeWithSelector(bytes4(keccak256("decreaseNonce(uint256)")), numNonces);
            }

            // Number of services
            for (uint256 j = 0; j < numServices; ++j) {
                uint256 serviceId = j + 1;
                ServiceRegistryL2.Service memory service = serviceRegistry.getService(serviceId);
                address payable multisig = payable(service.multisig);

                // Execute a tx to increase / decrease the specified number of nonces
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

                // Execute the tx
                vm.prank(agentInstances[j]);
                GnosisSafe(multisig).execTransaction(address(safeNonceLib), 0, payload, Enum.Operation.DelegateCall,
                    0, 0, 0, address(0), payable(address(0)), signature);
            }

            // Move several liveness checks ahead
            vm.warp(block.timestamp + livenessPeriod * stakingNativeToken.maxNumInactivityPeriods() + 1);

            // Call the checkpoint
            stakingNativeToken.checkpoint();

            // Unstake if there are no available rewards
            if (stakingNativeToken.availableRewards() == 0) {
                for (uint256 j = 0; j < numServices; ++j) {
                    uint256 serviceId = j + 1;
                    // Unstake if the service is not yet unstaked, otherwise ignore
                    if (uint8(stakingNativeToken.getStakingState(serviceId)) > 0) {
                        vm.startPrank(deployer);
                        stakingNativeToken.unstake(serviceId);
                        vm.stopPrank();
                    }
                }
            }
        }
    }

    /// @dev Test service staking based on ERC20 token with random number of executed tx-s (nonces) per day.
    /// @param numNonces Number of nonces per day.
    function testNoncesToken(uint8 numNonces) external {
        // Send tokens to a ERC20 token staking contract
        token.approve(address(stakingToken), 100 ether);
        stakingToken.deposit(100 ether);

        // Stake services
        for (uint256 i = 0; i < numServices; ++i) {
            uint256 serviceId = i + numServices + 1;
            vm.startPrank(deployer);
            serviceRegistry.approve(address(stakingToken), serviceId);
            stakingToken.stake(serviceId);
            vm.stopPrank();
        }

        // Get the Safe data payload
        payload = abi.encodeWithSelector(bytes4(keccak256("getThreshold()")));
        // Number of days
        for (uint256 i = 0; i < numDays; ++i) {
            // Number of services
            for (uint256 j = 0; j < numServices; ++j) {
                uint256 serviceId = j + numServices + 1;
                ServiceRegistryL2.Service memory service = serviceRegistry.getService(serviceId);
                address payable multisig = payable(service.multisig);

                // Get the nonce before
                uint256 nonceBefore = GnosisSafe(multisig).nonce();

                // Execute a specified number of nonces
                for (uint8 n = 0; n < numNonces; ++n) {
                    // Get the signature
                    bytes memory signature = new bytes(65);
                    bytes memory bAddress = abi.encode(agentInstances[j + numServices]);
                    for (uint256 b = 0; b < 32; ++b) {
                        signature[b] = bAddress[b];
                    }
                    for (uint256 b = 32; b < 64; ++b) {
                        signature[b] = bytes1(0x00);
                    }
                    signature[64] = bytes1(0x01);
                    vm.prank(agentInstances[j + numServices]);
                    GnosisSafe(multisig).execTransaction(multisig, 0, payload, Enum.Operation.Call, 0, 0, 0, address(0),
                        payable(address(0)), signature);
                }

                // Get the nonce after transactions
                uint256 nonceAfter = GnosisSafe(multisig).nonce();
                assertGe(nonceAfter, nonceBefore);
            }

            // Move several liveness checks ahead
            vm.warp(block.timestamp + livenessPeriod * stakingToken.maxNumInactivityPeriods() + 1);

            // Call the checkpoint
            stakingToken.checkpoint();

            // Unstake if there are no available rewards
            if (stakingToken.availableRewards() == 0) {
                for (uint256 j = 0; j < numServices; ++j) {
                    uint256 serviceId = j + numServices + 1;
                    // Unstake if the service is not yet unstaked, otherwise ignore
                    if (uint8(stakingToken.getStakingState(serviceId)) > 0) {
                        vm.startPrank(deployer);
                        stakingToken.unstake(serviceId);
                        vm.stopPrank();
                    }
                }
            }
        }
    }
}