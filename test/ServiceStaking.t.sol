pragma solidity =0.8.21;

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
import {GnosisSafeSameAddressMultisig} from "../contracts/multisigs/GnosisSafeSameAddressMultisig.sol";
import "../contracts/staking/ServiceStakingNativeToken.sol";
import {ServiceStakingToken} from "../contracts/staking/ServiceStakingToken.sol";

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
    GnosisSafeSameAddressMultisig internal gnosisSafeSameAddressMultisig;
    ServiceStakingNativeToken internal serviceStakingNativeToken;
    ServiceStakingToken internal serviceStakingToken;

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
    // Liveness period
    uint256 internal livenessPeriod = 1 days;
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
        agentInstances = new address[](numServices);
        for (uint256 i = 0; i < numServices; ++i) {
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
        gnosisSafeSameAddressMultisig = new GnosisSafeSameAddressMultisig();

        

        // Deploying a token contract and minting to deployer, operator and a current contract
        token = new ERC20Token();
        token.mint(deployer, initialMint);
        token.mint(operator, initialMint);
        token.mint(address(this), initialMint);

        // Deploy service staking native token and arbitraty token
        ServiceStakingBase.StakingParams memory stakingParams = ServiceStakingBase.StakingParams(maxNumServices,
            rewardsPerSecond, minStakingDeposit, livenessPeriod, livenessRatio, numAgentInstances, emptyArray, 0, bytes32(0));
        address[] memory multisigProxyAddresses = new address[](1);
        multisigProxyAddresses[0] = address(gnosisSafeProxy);
        serviceStakingNativeToken = new ServiceStakingNativeToken(stakingParams, address(serviceRegistry),
            multisigProxyAddresses);
        serviceStakingToken = new ServiceStakingToken(stakingParams, address(serviceRegistry), address(serviceRegistryTokenUtility),
            address(token), multisigProxyAddresses);

        // Whitelist multisig implementations
        serviceRegistry.changeMultisigPermission(address(gnosisSafeMultisig), true);
        serviceRegistry.changeMultisigPermission(address(gnosisSafeSameAddressMultisig), true);

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
    }
}

contract ServiceStaking is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Test service staking with random number of executed tx-s (nonces) per day.
    /// @param numNonces Number of nonces per day.
    function testNonces(uint8 numNonces) external {
        // Send funds to a native token staking contract
        address(serviceStakingNativeToken).call{value: 100 ether}("");

        // Stake services
        for (uint256 i = 0; i < 3; ++i) {
            uint256 serviceId = i + 1;
            vm.startPrank(deployer);
            serviceRegistry.approve(address(serviceStakingNativeToken), serviceId);
            serviceStakingNativeToken.stake(serviceId);
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
                // Get the nonce
                uint256 nonce = GnosisSafe(multisig).nonce();
            }

            // Move one day ahead
            vm.warp(block.timestamp + 1 days);

            // Call the checkpoint
            serviceStakingNativeToken.checkpoint();

            // Unstake if there are no available rewards
            if (serviceStakingNativeToken.availableRewards() == 0) {
                for (uint256 j = 0; j < numServices; ++j) {
                    uint256 serviceId = j + 1;
                    // Unstake if the service is not yet unstaked, otherwise ignore
                    if (!serviceStakingNativeToken.isServiceStaked(serviceId)) {
                        vm.startPrank(deployer);
                        serviceStakingNativeToken.unstake(serviceId);
                        vm.stopPrank();
                    }
                }
            }
        }
    }
}