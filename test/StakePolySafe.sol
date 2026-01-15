pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.sol";
import {ERC20Token} from "../contracts/test/ERC20Token.sol";
import {ServiceRegistry} from "../contracts/ServiceRegistry.sol";
import {ServiceManager} from "../contracts/ServiceManager.sol";
import {StakingToken} from "../contracts/staking/StakingToken.sol";
import {PolySafeCreatorWithRecoveryModule} from "../contracts/multisigs/PolySafeCreatorWithRecoveryModule.sol";
import {PolySafeProxyFactory} from "../contracts/test/MockPolySafeFactory.sol";
import {IService} from "../contracts/interfaces/IService.sol";

contract BaseSetup is Test {
    Utils internal utils;
    ERC20Token internal olas;
    ServiceRegistry internal serviceRegistry;
    ServiceManager internal serviceManager;
    StakingToken internal stakingToken;
    PolySafeCreatorWithRecoveryModule internal polySafeCreatorWithRecoveryModule;


    address payable[] internal users;
    address internal deployer;

    address internal olasAddress = 0xFEF5d947472e72Efbb2E388c730B7428406F2F95;
    address internal serviceManagerAddress = 0xE3e5Df46060370af5Fd37B2aA11e7dac3cCB4bd0;
    address internal serviceRegistryAddress = 0xE3607b00E75f6405248323A9417ff6b39B244b50;
    address internal serviceRegistryTokenUtilityAddress = 0xa45E64d13A30a51b91ae0eb182e88a40e9b18eD8;
    address internal stakingProxyAddress = 0x25a13AC34D77c46d9DFCCA59AF11377569867414;
    address internal polySafeCreatorWithRecoveryModuleAddress = 0xA749f605D93B3efcc207C54270d83C6E8fa70fF8;
    address internal polySafeSameAddressMultisigAddress = 0xBcb1BAC84B5BcAb350C89c50ADc9064eD15a4485;

    bytes32 internal configHash = 0x4d82a931d803e2b46b0dcd53f558f8de8305fd44b36288b42287ef1450a6611f;
    uint32 internal threshold = 1;

    function setUp() public virtual {
        utils = new Utils();
        users = utils.createUsers(50);
        deployer = users[0];
        vm.label(deployer, "Deployer");

        // Get contracts
        olas = ERC20Token(olasAddress);
        serviceRegistry = ServiceRegistry(serviceRegistryAddress);
        serviceManager = ServiceManager(serviceManagerAddress);
        stakingToken = StakingToken(stakingProxyAddress);
        polySafeCreatorWithRecoveryModule = PolySafeCreatorWithRecoveryModule(polySafeCreatorWithRecoveryModuleAddress);

        // Get funds for deployer and operator
        vm.deal(deployer, 5 ether);
        deal(olasAddress, deployer, 50000 ether);
    }
}

/// @dev Fork test only.
contract StakePolySafe is BaseSetup {
    function setUp() public override {
        super.setUp();
    }

    /// @dev Create service with Poly Safe multisigand stake.
    function testCreatePolySafeAndStake() public {
        // Get agentInstance address and PK
        (address agentInstance, uint256 agentInstancePk) = makeAddrAndKey("agentInstance");
        emit log_address(agentInstance);

        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 86;
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0].slots = 1;
        agentParams[0].bond = 50000000000000000000;

        vm.startPrank(deployer);
        olas.approve(serviceRegistryTokenUtilityAddress, 1000 ether);
        olas.approve(stakingProxyAddress, 100 ether);

        // Fund staking proxy contract
        stakingToken.deposit(100 ether);

        // Create service
        uint256 serviceId = serviceManager.create(deployer, olasAddress, configHash, agentIds, agentParams, threshold);

        // Activate registration
        serviceManager.activateRegistration{value: 1}(serviceId);

        // Register agents
        address[] memory agentInstances = new address[](1);
        agentInstances[0] = agentInstance;
        serviceManager.registerAgents{value: 1}(serviceId, agentInstances, agentIds);
        vm.stopPrank();

        // Get Poly Safe factory digest
        bytes32 polySafeDigest = polySafeCreatorWithRecoveryModule.getPolySafeCreateTransactionHash();

        // Get Poly Safe creation signature
        PolySafeProxyFactory.Sig memory safeCreateSig;
        (safeCreateSig.v, safeCreateSig.r, safeCreateSig.s) = vm.sign(agentInstancePk, polySafeDigest);

        // Get enable module digest
        bytes32 enableModuleDigest = polySafeCreatorWithRecoveryModule.getEnableModuleTransactionHash(agentInstance);

        // Get enable module signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(agentInstancePk, enableModuleDigest);
        bytes memory enableModuleSignature = abi.encodePacked(r, s, v);

        // Encode signatures
        bytes memory data = abi.encode(safeCreateSig, enableModuleSignature);

        vm.startPrank(deployer);
        // Deploy service
        serviceManager.deploy(serviceId, polySafeCreatorWithRecoveryModuleAddress, data);

        // Approve service
        serviceRegistry.approve(stakingProxyAddress, serviceId);

        // Stake service
        stakingToken.stake(serviceId);
        vm.stopPrank();
    }

    /// @dev Create service with Poly Safe multisigand stake.
    function testExternalCreatePolySafeAndStake() public {
        // Get agentInstance address and PK
        (address agentInstance, uint256 agentInstancePk) = makeAddrAndKey("agentInstance");
        emit log_address(agentInstance);

        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 86;
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0].slots = 1;
        agentParams[0].bond = 50000000000000000000;

        vm.startPrank(deployer);
        olas.approve(serviceRegistryTokenUtilityAddress, 1000 ether);
        olas.approve(stakingProxyAddress, 100 ether);

        // Fund staking proxy contract
        stakingToken.deposit(100 ether);

        // Create service
        uint256 serviceId = serviceManager.create(deployer, olasAddress, configHash, agentIds, agentParams, threshold);

        // Activate registration
        serviceManager.activateRegistration{value: 1}(serviceId);

        // Register agents
        address[] memory agentInstances = new address[](1);
        agentInstances[0] = agentInstance;
        serviceManager.registerAgents{value: 1}(serviceId, agentInstances, agentIds);
        vm.stopPrank();

        // Get Poly Safe factory digest
        bytes32 polySafeDigest = polySafeCreatorWithRecoveryModule.getPolySafeCreateTransactionHash();

        // Get Poly Safe creation signature
        PolySafeProxyFactory.Sig memory safeCreateSig;
        (safeCreateSig.v, safeCreateSig.r, safeCreateSig.s) = vm.sign(agentInstancePk, polySafeDigest);

        // Get enable module digest
        bytes32 enableModuleDigest = polySafeCreatorWithRecoveryModule.getEnableModuleTransactionHash(agentInstance);

        // Get enable module signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(agentInstancePk, enableModuleDigest);
        bytes memory enableModuleSignature = abi.encodePacked(r, s, v);

        // Encode signatures
        bytes memory data = abi.encode(safeCreateSig, enableModuleSignature);

        // Create multisig
        address multisig = polySafeCreatorWithRecoveryModule.create(agentInstances, 1, data);

        data = abi.encodePacked(multisig);

        vm.startPrank(deployer);
        // Deploy service with same address multisig
        serviceManager.deploy(serviceId, polySafeSameAddressMultisigAddress, data);

        // Approve service
        serviceRegistry.approve(stakingProxyAddress, serviceId);

        // Stake service
        stakingToken.stake(serviceId);
        vm.stopPrank();
    }
}
