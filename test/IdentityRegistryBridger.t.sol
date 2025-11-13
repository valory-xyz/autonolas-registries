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
        uint8 score,
        bytes32 tag1,
        bytes32 tag2,
        string calldata feedbackUri,
        bytes32 feedbackHash,
        bytes calldata feedbackAuth
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
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant REGISTRIES_MANAGER = 0x13bb1605DDD353Ff4da9a9b1a70e20B4B1C48fC4;
    address internal constant SERVICE_MANAGER = 0x22808322414594A2a4b8F46Af5760E193D316b5B;
    address internal constant safeMultisigWithRecoveryModule = 0x164e1CA068afeF66EFbB9cA19d904c44E8386fd9;
    address internal constant IDENTITY_REGISTRY_BRIDGER = 0xC68b98C7417969c761659634CaE445d605CE0D5B;
    address internal constant IDENTITY_REGISTRY = 0x8004a6090Cd10A7288092483047B097295Fb8847;
    address internal constant REPUTATION_REGISTRY = 0x8004B8FD1A363aa02fDC07635C0c5F94f6Af5B7E;
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

        uint256 numServices = 20;

        // Create services, activate, register and deploy
        for (uint256 i = 0; i < numServices; ++i) {
            vm.startPrank(deployer);
            // Create
            uint256 serviceId = serviceManager.create(deployer, ETH_ADDRESS, configHash, agentIds, agentParams, THRESHOLD);

            // Activate registration
            serviceManager.activateRegistration{value: SECURITY_DEPOSIT}(serviceId);
            vm.stopPrank();

            // Register agent instances
            address[] memory agentInstances = new address[](1);
            agentInstances[0] = users[i + 2];
            vm.prank(operator);
            serviceManager.registerAgents{value: SECURITY_DEPOSIT}(serviceId, agentInstances, agentIds);

            // Deploy
            vm.prank(deployer);
            serviceManager.deploy(serviceId, safeMultisigWithRecoveryModule, "");
        }

        // Create agents and link services in 2 sets
        identityRegistryBridger.linkServiceIdAgentIds(numServices / 2);
        identityRegistryBridger.linkServiceIdAgentIds(numServices / 2);
    }

    /// @dev Signs feedback requests by 8004 operator and leave feedback.
        function testSignFeedbackRequestsAndExecute() public {
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
        uint256[] memory agentIds = identityRegistryBridger.linkServiceIdAgentIds(serviceId);

        // Authorize feedback
        address clientAddress = users[3];
        uint64 indexLimit = 2;
        uint256 expiry = block.timestamp + 1000;

        // Leave feedback
        uint256 agentId = agentIds[0];
        uint8 score = 100;
        bytes32 tag1;
        bytes32 tag2;
        string memory feedbackUri;
        bytes32 feedbackHash;

        // TODO
        // Encode first 224 bytes
        bytes memory feedbackAuth = abi.encode(agentId, clientAddress, indexLimit, expiry, block.chainid,
            IDENTITY_REGISTRY, address(identityRegistryBridger));

        // Try to leave feedback not by authorized client
        vm.prank(deployer);
        vm.expectRevert("Client mismatch");
        IReputationRegistry(REPUTATION_REGISTRY).giveFeedback(agentId, score, tag1, tag2, feedbackUri, feedbackHash,
            feedbackAuth);

        // Give 2 feedbacks by client
        vm.startPrank(clientAddress);
        IReputationRegistry(REPUTATION_REGISTRY).giveFeedback(agentId, score, tag1, tag2, feedbackUri, feedbackHash,
            feedbackAuth);
        IReputationRegistry(REPUTATION_REGISTRY).giveFeedback(agentId, score, tag1, tag2, feedbackUri, feedbackHash,
            feedbackAuth);

        vm.expectRevert("IndexLimit exceeded");
        // The 3rd is reverted as limit index is 2
        IReputationRegistry(REPUTATION_REGISTRY).giveFeedback(agentId, score, tag1, tag2, feedbackUri, feedbackHash,
            feedbackAuth);
        vm.stopPrank();
    }
}
