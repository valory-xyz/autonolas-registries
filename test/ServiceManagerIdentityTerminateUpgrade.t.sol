// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ServiceManager} from "../contracts/ServiceManager.sol";
import {IService} from "../contracts/interfaces/IService.sol";

interface IServiceRegistryView {
    function mapServices(uint256 serviceId)
        external
        view
        returns (uint96, address, bytes32, uint32, uint32, uint32, uint8);
}

interface IIdentityRegistryBridgerView {
    function serviceManager() external view returns (address);
    function mapServiceIdAgentIds(uint256 serviceId) external view returns (uint256);
    function mapMultisigAgentIds(address multisig) external view returns (uint256);
    function setMetadata(string memory metadataKey, bytes memory metadataValue) external;
    function setAgentWallet(uint256 deadline, bytes memory signature) external;
    function unsetAgentWallet() external;
}

interface IIdentityRegistryView {
    function getMetadata(uint256 agentId, string memory key) external view returns (bytes memory);
    function eip712Domain()
        external
        view
        returns (bytes1, string memory, string memory, uint256, address, bytes32, uint256[] memory);
}

interface IRecoveryModuleAccess {
    function recoverAccess(uint256 serviceId) external;
}

interface ISafeMinimal {
    function nonce() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool);
}

error ZeroValue();

/// @title ServiceManagerIdentityTerminateUpgradeTest
/// @notice Upgrades the live mainnet ServiceManagerProxy from v1.2.0 and runs the ERC-8004 identity lifecycle against
///         the live IdentityRegistryBridger and ERC-8004 IdentityRegistry. Every case uses a service created on the
///         fork. Termination unlinks the multisig from the service agent Id and unsets the agent wallet; unbonding does
///         not involve the bridger; a redeployment links the deployed multisig again.
///
///         Run: ETH_RPC=<mainnet archive rpc> forge test --match-contract ServiceManagerIdentityTerminateUpgrade -vv
contract ServiceManagerIdentityTerminateUpgradeTest is Test {
    event AgentMultisigUpdated(
        uint256 indexed serviceId, uint256 indexed agentId, address oldMultisig, address indexed newMultisig
    );

    // A block at which the live proxy runs the v1.2.0 implementation 0xA8C5...1f2e. Needs an archive RPC.
    uint256 internal constant FORK_BLOCK = 26_155_957;
    address internal constant LIVE_IMPLEMENTATION = 0xA8C52f0bB977F423E31400d151F1b98181511f2e;
    address internal constant PROXY = 0x94a1892D91c05D0C61c3f49F42205D2285b914c9;
    address internal constant SERVICE_REGISTRY = 0x48b6af7B12C71f09e2fC8aF4855De4Ff54e775cA;
    address internal constant TOKEN_UTILITY = 0x3Fb926116D454b95c669B6Bf2E7c3bad8d19affA; // gitleaks:allow - public ServiceRegistryTokenUtility address, not a secret
    address internal constant BRIDGER = 0x461A76074596F080dfba414532Ab51280611B8e6;
    address internal constant IDENTITY_REGISTRY = 0x8004A169FB4a3325136EB29fA0ceB6D2e539a432;
    address internal constant SAFE_WITH_RECOVERY_MODULE = 0xCb728aefD88FCA806d638EAEeEAcFC03Dd985d70;
    address internal constant RECOVERY_MODULE = 0x69D97b5c4F35fd3A72FA83b6B1eB911c6A8a2e3c;
    // Safe v1.3.0 CompatibilityFallbackHandler and SignMessageLib
    address internal constant FALLBACK_HANDLER = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;
    address internal constant SIGN_MESSAGE_LIB = 0xA65387F16B013cf2Af4605Ad8aA5ec25a2cbA3a2;
    address internal constant ETH_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    bytes32 internal constant PROXY_SERVICE_MANAGER = keccak256("PROXY_SERVICE_MANAGER");
    bytes32 internal constant AGENT_WALLET_SET_TYPEHASH =
        keccak256("AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)");
    uint96 internal constant BOND = 1000;
    uint8 internal constant PRE_REGISTRATION = 1;
    uint8 internal constant DEPLOYED = 4;
    uint8 internal constant TERMINATED_BONDED = 5;

    ServiceManager internal manager = ServiceManager(PROXY);
    IIdentityRegistryBridgerView internal bridger = IIdentityRegistryBridgerView(BRIDGER);
    IIdentityRegistryView internal identity = IIdentityRegistryView(IDENTITY_REGISTRY);
    address internal serviceOwner = makeAddr("serviceOwner");
    address internal operator;
    uint256 internal operatorKey;
    address internal operator2;
    uint256 internal operator2Key;
    uint256 internal safeNonce;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC"), FORK_BLOCK);
        (operator, operatorKey) = makeAddrAndKey("operator");
        (operator2, operator2Key) = makeAddrAndKey("operator2");
        vm.deal(operator2, 1 ether);
        vm.deal(serviceOwner, 1 ether);
        vm.deal(operator, 1 ether);
        assertEq(
            address(uint160(uint256(vm.load(PROXY, PROXY_SERVICE_MANAGER)))),
            LIVE_IMPLEMENTATION,
            "proxy must point at the live implementation"
        );
        assertEq(manager.identityRegistryBridger(), BRIDGER, "live manager must use the bridger");
        assertEq(bridger.serviceManager(), PROXY, "bridger must accept the manager proxy");
    }

    function _upgrade() internal {
        address owner = manager.owner();
        address whitelist = manager.operatorWhitelist();
        ServiceManager implementation = new ServiceManager(SERVICE_REGISTRY, TOKEN_UTILITY);
        vm.prank(owner);
        manager.changeImplementation(address(implementation));
        assertEq(manager.VERSION(), "1.3.0", "upgraded version");
        assertEq(manager.owner(), owner, "owner kept");
        assertEq(manager.identityRegistryBridger(), BRIDGER, "bridger kept");
        assertEq(manager.operatorWhitelist(), whitelist, "operator whitelist kept");
    }

    function _state(uint256 serviceId) internal view returns (uint8 state) {
        (,,,,,, state) = IServiceRegistryView(SERVICE_REGISTRY).mapServices(serviceId);
    }

    /// @dev Creates a one-instance native service; the bridger registers its agent Id at create().
    function _createService() internal returns (uint256 serviceId, uint256 agentId) {
        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 1;
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0] = IService.AgentParams({slots: 1, bond: BOND});
        serviceId = manager.create(serviceOwner, ETH_TOKEN_ADDRESS, bytes32(uint256(0x8004)), agentIds, agentParams, 1);
        agentId = bridger.mapServiceIdAgentIds(serviceId);
        assertGt(agentId, 0, "agent Id registered at create()");
    }

    /// @dev Activates registration and registers one agent instance.
    function _register(uint256 serviceId, address instance) internal {
        vm.prank(serviceOwner);
        manager.activateRegistration{value: BOND}(serviceId);
        address[] memory instances = new address[](1);
        instances[0] = instance;
        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 1;
        vm.prank(operator);
        manager.registerAgents{value: BOND}(serviceId, instances, agentIds);
    }

    /// @dev Deploys a new Safe with the recovery module and the fallback handler enabled.
    function _deployNewSafe(uint256 serviceId) internal returns (address safe) {
        vm.prank(serviceOwner);
        safe = manager.deploy(serviceId, SAFE_WITH_RECOVERY_MODULE, abi.encode(FALLBACK_HANDLER, safeNonce++));
        assertEq(_state(serviceId), DEPLOYED, "deployed");
    }

    function _deployedService(uint256 instanceKey) internal returns (uint256 serviceId, uint256 agentId, address safe) {
        (serviceId, agentId) = _createService();
        _register(serviceId, vm.addr(instanceKey));
        safe = _deployNewSafe(serviceId);
    }

    function _assertLinked(address safe, uint256 agentId, bytes memory value) internal {
        assertEq(bridger.mapMultisigAgentIds(safe), agentId, "multisig linked");
        vm.prank(safe);
        bridger.setMetadata("endpoint", value);
        assertEq(identity.getMetadata(agentId, "endpoint"), value, "multisig can set metadata");
    }

    function _assertUnlinked(address safe) internal {
        assertEq(bridger.mapMultisigAgentIds(safe), 0, "multisig unlinked");
        vm.prank(safe);
        vm.expectRevert(ZeroValue.selector);
        bridger.setMetadata("endpoint", hex"02");
        vm.prank(safe);
        vm.expectRevert(ZeroValue.selector);
        bridger.unsetAgentWallet();
    }

    function _assertIdentityIntact(uint256 serviceId, uint256 agentId) internal view {
        assertEq(bridger.mapServiceIdAgentIds(serviceId), agentId, "agent Id kept");
        assertEq(identity.getMetadata(agentId, "ecosystem"), abi.encode("Olas"), "ecosystem kept");
        assertEq(identity.getMetadata(agentId, "serviceRegistry"), abi.encode(SERVICE_REGISTRY), "registry kept");
        assertEq(identity.getMetadata(agentId, "serviceId"), abi.encode(serviceId), "service Id kept");
    }

    /// @dev Executes a one-owner Safe transaction signed by that owner's key.
    function _safeExec(address safe, uint256 ownerKey, address to, bytes memory data, uint8 operation) internal {
        ISafeMinimal s = ISafeMinimal(safe);
        bytes32 txHash = s.getTransactionHash(to, 0, data, operation, 0, 0, 0, address(0), address(0), s.nonce());
        (uint8 v, bytes32 r, bytes32 sig) = vm.sign(ownerKey, txHash);
        s.execTransaction(to, 0, data, operation, 0, 0, 0, address(0), payable(address(0)), abi.encodePacked(r, sig, v));
    }

    /// @dev The Safe signs the registry's wallet digest (SignMessageLib, EIP-1271) and sets itself as agent wallet.
    function _setSafeAsWallet(address safe, uint256 agentId, uint256 ownerKey) internal {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            identity.eip712Domain();
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
        uint256 deadline = block.timestamp + 100;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(abi.encode(AGENT_WALLET_SET_TYPEHASH, agentId, safe, BRIDGER, deadline))
            )
        );
        _safeExec(
            safe, ownerKey, SIGN_MESSAGE_LIB, abi.encodeWithSignature("signMessage(bytes)", abi.encode(digest)), 1
        );
        vm.prank(safe);
        bridger.setAgentWallet(deadline, "");
        assertEq(identity.getMetadata(agentId, "agentWallet"), abi.encodePacked(safe), "Safe is the agent wallet");
    }

    /// @dev Unbond by the service owner with the operator's signed message.
    function _signedUnbond(uint256 serviceId, address op, uint256 opKey) internal {
        uint256 deadline = block.timestamp + 100;
        bytes32 digest =
            manager.getUnbondHash(op, serviceOwner, serviceId, deadline, manager.getOperatorUnbondNonce(op, serviceId));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(opKey, digest);
        vm.prank(serviceOwner);
        manager.unbondWithSignature(op, serviceId, deadline, abi.encodePacked(r, s, v));
    }

    /// @notice Termination with agents still bonded: the agent wallet is unset, the multisig is unlinked, the identity
    ///         and the multisig binding are kept.
    function test_terminateUnlinksMultisigAndUnsetsWallet() public {
        _upgrade();
        uint256 instanceKey = 0xA11;
        (uint256 serviceId, uint256 agentId, address safe) = _deployedService(instanceKey);
        _assertLinked(safe, agentId, hex"01");
        _setSafeAsWallet(safe, agentId, instanceKey);

        vm.expectEmit(true, true, true, true, BRIDGER);
        emit AgentMultisigUpdated(serviceId, agentId, safe, address(0));
        vm.prank(serviceOwner);
        manager.terminate(serviceId);

        assertEq(_state(serviceId), TERMINATED_BONDED, "agents still bonded");
        _assertUnlinked(safe);
        assertEq(identity.getMetadata(agentId, "agentWallet").length, 0, "agent wallet unset");
        _assertIdentityIntact(serviceId, agentId);
        assertEq(manager.mapMultisigServiceIds(safe), serviceId, "multisig binding kept");
    }

    /// @notice Termination of a service whose agent wallet was never set.
    function test_terminateWithEmptyWallet() public {
        _upgrade();
        (uint256 serviceId, uint256 agentId, address safe) = _deployedService(0xA13);

        vm.prank(serviceOwner);
        manager.terminate(serviceId);

        _assertUnlinked(safe);
        assertEq(identity.getMetadata(agentId, "agentWallet").length, 0, "agent wallet still empty");
        _assertIdentityIntact(serviceId, agentId);
    }

    /// @notice After termination, a direct partial unbond and a signed final unbond make no call to the bridger.
    function test_unbondsAfterTerminationMakeNoBridgerCall() public {
        _upgrade();
        uint32[] memory agentIds = new uint32[](1);
        agentIds[0] = 1;
        IService.AgentParams[] memory agentParams = new IService.AgentParams[](1);
        agentParams[0] = IService.AgentParams({slots: 2, bond: BOND});
        uint256 serviceId =
            manager.create(serviceOwner, ETH_TOKEN_ADDRESS, bytes32(uint256(0x8004)), agentIds, agentParams, 2);
        vm.prank(serviceOwner);
        manager.activateRegistration{value: BOND}(serviceId);
        address[] memory instances = new address[](1);
        instances[0] = vm.addr(0xA16);
        vm.prank(operator);
        manager.registerAgents{value: BOND}(serviceId, instances, agentIds);
        instances[0] = vm.addr(0xA17);
        vm.prank(operator2);
        manager.registerAgents{value: BOND}(serviceId, instances, agentIds);
        address safe = _deployNewSafe(serviceId);
        vm.prank(serviceOwner);
        manager.terminate(serviceId);
        _assertUnlinked(safe);

        // No call of any kind reaches the bridger from here to the end of the test
        vm.expectCall(BRIDGER, "", 0);
        vm.prank(operator);
        manager.unbond(serviceId);
        assertEq(_state(serviceId), TERMINATED_BONDED, "partial unbond");
        _signedUnbond(serviceId, operator2, operator2Key);
        assertEq(_state(serviceId), PRE_REGISTRATION, "final unbond");
    }

    /// @notice Redeployment with the same Safe through the recovery module links it again.
    function test_recoveryRedeploySameSafeLinksAgain() public {
        _upgrade();
        (uint256 serviceId, uint256 agentId, address safe) = _deployedService(0xA14);
        vm.prank(serviceOwner);
        manager.terminate(serviceId);
        vm.prank(operator);
        manager.unbond(serviceId);
        _assertUnlinked(safe);

        vm.prank(serviceOwner);
        IRecoveryModuleAccess(RECOVERY_MODULE).recoverAccess(serviceId);
        assertEq(ISafeMinimal(safe).getOwners()[0], serviceOwner, "service owner recovered the Safe");

        address instance = vm.addr(0xB14);
        _register(serviceId, instance);
        vm.expectEmit(true, true, true, true, BRIDGER);
        emit AgentMultisigUpdated(serviceId, agentId, address(0), safe);
        vm.prank(serviceOwner);
        address redeployed = manager.deploy(serviceId, RECOVERY_MODULE, abi.encode(serviceId));

        assertEq(redeployed, safe, "same Safe");
        assertEq(ISafeMinimal(safe).getOwners()[0], instance, "agent instance owns the Safe");
        _assertLinked(safe, agentId, hex"03");
        _assertIdentityIntact(serviceId, agentId);
    }

    /// @notice Redeployment with a new Safe links only the new one; the previous multisig binding is released.
    function test_redeployNewSafeLinksOnlyNewOne() public {
        _upgrade();
        (uint256 serviceId, uint256 agentId, address oldSafe) = _deployedService(0xA15);
        vm.prank(serviceOwner);
        manager.terminate(serviceId);
        vm.prank(operator);
        manager.unbond(serviceId);

        _register(serviceId, vm.addr(0xB15));
        address newSafe = _deployNewSafe(serviceId);

        assertTrue(newSafe != oldSafe, "new Safe");
        _assertLinked(newSafe, agentId, hex"04");
        _assertUnlinked(oldSafe);
        assertEq(manager.mapMultisigServiceIds(newSafe), serviceId, "new Safe bound");
        assertEq(manager.mapMultisigServiceIds(oldSafe), 0, "old Safe released");
        _assertIdentityIntact(serviceId, agentId);
    }
}
