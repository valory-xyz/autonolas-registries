pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {IToken} from "../contracts/interfaces/IToken.sol";
import {IService} from "../contracts/interfaces/IService.sol";
import {IdentityRegistryBridger} from "../contracts/8004/IdentityRegistryBridger.sol";
import {ServiceManager} from "../contracts/ServiceManager.sol";

contract BaseSetup is Test {
    Utils internal utils;
    IdentityRegistryBridger internal identityRegistryBridger;
    ServiceManager internal serviceManager;

    address payable[] internal users;
    address internal deployer;
    address internal operator;

    // Contract addresses
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal constant SERVICE_MANAGER = 0x52beace64D3E5e59A03d8e5c7a1fC7b59f635b22;
    address internal constant safeMultisigWithRecoveryModule = 0x164e1CA068afeF66EFbB9cA19d904c44E8386fd9;
    address internal constant IDENTITY_REGISTRY_BRIDGER = 0x293b030678996ac600CAF53854177F60894DAF7A;
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

        // Deploy V2 oracle
        serviceManager = ServiceManager(SERVICE_MANAGER);
        identityRegistryBridger = IdentityRegistryBridger(IDENTITY_REGISTRY_BRIDGER);

        // Get funds for deployer and operator
        vm.deal(deployer, 5 ether);
        vm.deal(operator, 5 ether);

        // Default agent Ids
        agentIds = new uint32[](1);
        agentIds[0] = 1;
    }
}

contract IdentityRegistry is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Create 10 services and link them with identity registry by creating corresponding agents.
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
}
