pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";
import {IService} from "../contracts/interfaces/IService.sol";
import {IRegistry} from "../contracts/interfaces/IRegistry.sol";
import {IdentityRegistryBridger} from "../contracts/8004/IdentityRegistryBridger.sol";
import {RegistriesManager} from "../contracts/RegistriesManager.sol";
import {ServiceManager} from "../contracts/ServiceManager.sol";

interface IReputationRegistry {
    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external;
}

contract BaseSetup is Test {
    Utils internal utils;
    IdentityRegistryBridger internal identityRegistryBridger;
    ServiceManager internal serviceManager;
    RegistriesManager internal registriesManager;

    address payable[] internal users;
    address internal deployer;
    address internal operator;

    // Contract addresses
    address internal constant CONTRACT_OWNER = 0x52370eE170c0E2767B32687166791973a0dE7966;
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant REGISTRIES_MANAGER = 0x13bb1605DDD353Ff4da9a9b1a70e20B4B1C48fC4;
    address internal constant SERVICE_MANAGER = 0x22808322414594A2a4b8F46Af5760E193D316b5B;
    address internal constant safeMultisigWithRecoveryModule = 0x164e1CA068afeF66EFbB9cA19d904c44E8386fd9;
    address internal constant IDENTITY_REGISTRY_BRIDGER = 0x2c5c0a88c86b8E672673F2f4B1bbA4B83F2C64BA;
    address internal constant IDENTITY_REGISTRY = 0x8004A818BFB912233c491871b3d84c89A494BD9e;
    address internal constant REPUTATION_REGISTRY = 0x8004B663056A597Dffe9eCcC1965A193B7388713;
    uint96 internal constant SECURITY_DEPOSIT = 1;
    uint32 internal constant THRESHOLD = 1;

    bytes32 internal configHash = keccak256(abi.encode(deployer));
    uint32[] internal agentIds;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(50);
        deployer = users[0];
        vm.label(deployer, "Deployer");
        operator = users[1];
        vm.label(operator, "Operator");

        // Get contracts
        serviceManager = ServiceManager(SERVICE_MANAGER);
        identityRegistryBridger = IdentityRegistryBridger(IDENTITY_REGISTRY_BRIDGER);
        registriesManager = RegistriesManager(REGISTRIES_MANAGER);

        // Get funds for deployer and operator
        vm.deal(deployer, 5 ether);
        vm.deal(operator, 5 ether);

        // Default agent Ids
        agentIds = new uint32[](1);
        agentIds[0] = 1;

        // Create component and agent
        registriesManager.create(IRegistry.UnitType.Component, deployer, configHash, new uint32[](0));
        registriesManager.create(IRegistry.UnitType.Agent, deployer, configHash, agentIds);
    }
}

contract IdentityRegistry is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Create services and link them with identity registry by creating corresponding agents.
    function testCreateServicesLinkIdentityRegistry() public {
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0] = IService.AgentParams({slots: 1, bond: SECURITY_DEPOSIT});

        uint256 numServices = 10;
        uint256 serviceId;
        address[] memory agentInstances;

        // Create services, activate, register and deploy
        for (uint256 i = 0; i < numServices; ++i) {
            vm.startPrank(deployer);
            // Create
            serviceId = serviceManager.create(deployer, ETH_ADDRESS, configHash, agentIds, agentParams, THRESHOLD);

            // Activate registration
            serviceManager.activateRegistration{value: SECURITY_DEPOSIT}(serviceId);
            vm.stopPrank();

            // Register agent instances
            agentInstances = new address[](1);
            agentInstances[0] = users[i + 2];
            vm.prank(operator);
            serviceManager.registerAgents{value: SECURITY_DEPOSIT}(serviceId, agentInstances, agentIds);

            // Deploy
            vm.prank(deployer);
            serviceManager.deploy(serviceId, safeMultisigWithRecoveryModule, "");
        }

        // Create agents and link services in 2 sets
        identityRegistryBridger.linkServiceIdAgentIds(numServices / 2);
        identityRegistryBridger.linkServiceIdAgentIds(numServices / 2 + 1);

        // Link ServiceManager and IRB
        vm.prank(CONTRACT_OWNER);
        serviceManager.setIdentityRegistryBridger(IDENTITY_REGISTRY_BRIDGER);

        // Create one more service which is already 8004 compatible
        vm.startPrank(deployer);
        // Create service
        serviceId = serviceManager.create(deployer, ETH_ADDRESS, configHash, agentIds, agentParams, THRESHOLD);

        // Activate registration
        serviceManager.activateRegistration{value: SECURITY_DEPOSIT}(serviceId);
        vm.stopPrank();

        // Register agent instances
        agentInstances = new address[](1);
        agentInstances[0] = users[numServices + 2];
        vm.prank(operator);
        serviceManager.registerAgents{value: SECURITY_DEPOSIT}(serviceId, agentInstances, agentIds);

        // Deploy service
        vm.prank(deployer);
        serviceManager.deploy(serviceId, safeMultisigWithRecoveryModule, "");

        // Perform one more link try
        identityRegistryBridger.linkServiceIdAgentIds(1);

        // Next time it reverts because first service is set to zero
        vm.expectRevert();
        identityRegistryBridger.linkServiceIdAgentIds(1);
    }

    /// @dev Gives feedback to agents.
    function testGiveFeedback() public {
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0] = IService.AgentParams({slots: 1, bond: SECURITY_DEPOSIT});

        // Create service, activate, register and deploy
        vm.startPrank(deployer);
        // Create
        uint256 serviceId = serviceManager.create(deployer, ETH_ADDRESS, configHash, agentIds, agentParams, THRESHOLD);

        // Activate registration
        serviceManager.activateRegistration{value: SECURITY_DEPOSIT}(serviceId);
        vm.stopPrank();

        // Register agent instances
        address[] memory agentInstances = new address[](1);
        agentInstances[0] = users[2];
        vm.prank(operator);
        serviceManager.registerAgents{value: SECURITY_DEPOSIT}(serviceId, agentInstances, agentIds);

        // Deploy
        vm.prank(deployer);
        serviceManager.deploy(serviceId, safeMultisigWithRecoveryModule, "");

        // Create agent and link service
        uint256[] memory agentIds = identityRegistryBridger.linkServiceIdAgentIds(1);

        // Authorize feedback
        address clientAddress = users[3];

        // Leave feedback
        uint256 agentId = agentIds[0];
        int128 score = 100;
        uint8 decimals = 1;
        string memory tag1;
        string memory tag2;
        string memory endpoint;
        string memory feedbackUri;
        bytes32 feedbackHash;

        // Give 3 feedbacks by client
        vm.startPrank(clientAddress);
        IReputationRegistry(REPUTATION_REGISTRY).giveFeedback(agentId, score, decimals, tag1, tag2, feedbackUri,
            endpoint, feedbackHash);
        IReputationRegistry(REPUTATION_REGISTRY).giveFeedback(agentId, score, decimals, tag1, tag2, feedbackUri,
            endpoint, feedbackHash);
        IReputationRegistry(REPUTATION_REGISTRY).giveFeedback(agentId, score, decimals, tag1, tag2, feedbackUri,
            endpoint, feedbackHash);
        vm.stopPrank();
    }
}
