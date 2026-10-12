// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ServiceManager} from "../contracts/ServiceManager.sol";
import {
    HashNotApproved,
    HashNotValidated,
    IncorrectSignatureLength,
    WrongOperatorAddress
} from "../contracts/utils/OperatorSignedHashes.sol";

/// @dev The live v1.2.0 ServiceManager: the functions this test calls before the upgrade.
interface IServiceManagerV1 {
    struct AgentParams {
        uint32 slots;
        uint96 bond;
    }

    function VERSION() external view returns (string memory);
    function owner() external view returns (address);
    function changeImplementation(address implementation) external;
    function create(
        address serviceOwner,
        address token,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint32 threshold
    ) external returns (uint256);
    function activateRegistration(uint256 serviceId) external payable returns (bool);
    function terminate(uint256 serviceId) external returns (bool, uint256);
    function operatorApproveHash(bytes32 hash) external;
    function registerAgentsWithSignature(
        address operator,
        uint256 serviceId,
        address[] memory agentInstances,
        uint32[] memory agentIds,
        bytes memory signature
    ) external payable returns (bool);
    function unbondWithSignature(address operator, uint256 serviceId, bytes memory signature)
        external
        returns (bool, uint256);
    function getRegisterAgentsHash(
        address operator,
        address serviceOwner,
        uint256 serviceId,
        address[] memory agentInstances,
        uint32[] memory agentIds,
        uint256 nonce
    ) external view returns (bytes32);
    function getUnbondHash(address operator, address serviceOwner, uint256 serviceId, uint256 nonce)
        external
        view
        returns (bytes32);
    function getOperatorRegisterAgentsNonce(address operator, uint256 serviceId) external view returns (uint256);
    function getOperatorUnbondNonce(address operator, uint256 serviceId) external view returns (uint256);
}

/// @dev Contract operator implementing the existing custom interface ServiceManager supports for contract signatures:
///      the signature bytes are `(operator address, 0, 4)` and carry no signer data, so the contract decides from the
///      digest alone, here from digests its controller approved (as MockOperatorContract does). It also accepts the
///      native refund on unbonding.
contract ContractOperator {
    address public immutable controller;
    mapping(bytes32 => bool) public approvedHashes;

    constructor(address _controller) {
        controller = _controller;
    }

    function approveHash(bytes32 hash) external {
        require(msg.sender == controller, "controller only");
        approvedHashes[hash] = true;
    }

    function isValidSignature(bytes32 hash, bytes memory) external view returns (bytes4 magicValue) {
        if (approvedHashes[hash]) {
            magicValue = 0x1626ba7e;
        }
    }

    receive() external payable {}
}

interface ISafe {
    function setup(
        address[] calldata owners,
        uint256 threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;
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
    function VERSION() external view returns (string memory);
}

interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes memory initializer, uint256 saltNonce)
        external
        returns (address proxy);
}

interface IServiceRegistryState {
    function mapServices(uint256 serviceId)
        external
        view
        returns (uint96, address, bytes32, uint32, uint32, uint32, uint8);
}

/// @title ServiceManagerContractOperatorUpgradeTest
/// @notice Contract operators across the upgrade of the live mainnet ServiceManagerProxy from v1.2.0 to v1.3.0, for
///         registration and unbonding, with the same operator contract before and after:
///         1. its signing mechanism succeeds on v1.2.0;
///         2. after the upgrade, fresh v1.3.0 authorizations succeed with the same mechanism;
///         3. v1.2.0 authorizations made before the upgrade fail;
///         4. invalid signatures still fail.
///
///         Two mechanisms are covered:
///         - the contract-signature path (`v = 4`), scoped to the existing custom contract-operator interface
///           (`ContractOperator` above). A Safe cannot use this path on either version: the signature bytes are not a
///           valid Safe signature, so the Safe's EIP-1271 handler reverts (`test_safeCannotUseContractSignaturePath`);
///         - the pre-approved hash path (`v = 5`) with a real Safe v1.3.0, the wallet's own transaction calling
///           `operatorApproveHash`.
///
///         Run: ETH_RPC=<mainnet rpc> forge test --match-contract ServiceManagerContractOperatorUpgrade -vv
contract ServiceManagerContractOperatorUpgradeTest is Test {
    address internal constant PROXY = 0x94a1892D91c05D0C61c3f49F42205D2285b914c9;
    address internal constant SERVICE_REGISTRY = 0x48b6af7B12C71f09e2fC8aF4855De4Ff54e775cA;
    address internal constant TOKEN_UTILITY = 0x3Fb926116D454b95c669B6Bf2E7c3bad8d19affA;
    address internal constant ETH_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    // Safe v1.3.0 on Ethereum mainnet
    address internal constant SAFE_SINGLETON = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;
    address internal constant SAFE_PROXY_FACTORY = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;
    address internal constant SAFE_FALLBACK_HANDLER = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;
    uint96 internal constant BOND = 1 ether;
    uint8 internal constant FINISHED_REGISTRATION = 3;

    IServiceManagerV1 internal v1 = IServiceManagerV1(PROXY);
    ServiceManager internal v2 = ServiceManager(PROXY);
    address internal serviceOwner = makeAddr("serviceOwner");
    address internal controller = makeAddr("controller");
    uint256 internal instanceCount;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC"));
        vm.deal(serviceOwner, 100 ether);
        assertEq(v1.VERSION(), "1.2.0", "live implementation");
    }

    // ---------- helpers ----------

    function _ids() internal pure returns (uint32[] memory out) {
        out = new uint32[](1);
        out[0] = 1;
    }

    function _nextInstance() internal returns (address[] memory out) {
        out = new address[](1);
        out[0] = makeAddr(string(abi.encodePacked("instance", vm.toString(++instanceCount))));
    }

    /// @dev Creates and activates a native-token service with `slots` slots of agent 1.
    function _activeService(uint32 slots) internal returns (uint256 serviceId) {
        IServiceManagerV1.AgentParams[] memory params = new IServiceManagerV1.AgentParams[](1);
        params[0] = IServiceManagerV1.AgentParams({slots: slots, bond: BOND});
        serviceId = v1.create(serviceOwner, ETH_TOKEN_ADDRESS, bytes32(uint256(1)), _ids(), params, slots);
        vm.prank(serviceOwner);
        v1.activateRegistration{value: BOND}(serviceId);
    }

    function _upgrade() internal {
        ServiceManager impl = new ServiceManager(SERVICE_REGISTRY, TOKEN_UTILITY);
        vm.prank(v1.owner());
        v1.changeImplementation(address(impl));
        assertEq(v2.VERSION(), "1.3.0", "upgraded implementation");
    }

    /// @dev Signature bytes of the contract-signature path: the operator contract address in r, s = 0, v = 4.
    function _contractSignature(address operator) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32(uint256(uint160(operator))), bytes32(0), uint8(4));
    }

    /// @dev Signature bytes of the pre-approved hash path: the operator address in r, s = 0, v = 5.
    function _approvedSignature(address operator) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32(uint256(uint160(operator))), bytes32(0), uint8(5));
    }

    function _v1RegisterHash(address operator, uint256 serviceId, address[] memory instances)
        internal
        view
        returns (bytes32)
    {
        return v1.getRegisterAgentsHash(
            operator, serviceOwner, serviceId, instances, _ids(), v1.getOperatorRegisterAgentsNonce(operator, serviceId)
        );
    }

    function _v2RegisterHash(address operator, uint256 serviceId, address[] memory instances)
        internal
        view
        returns (bytes32)
    {
        return v2.getRegisterAgentsHash(
            operator,
            serviceOwner,
            serviceId,
            instances,
            _ids(),
            ETH_TOKEN_ADDRESS,
            BOND,
            block.timestamp,
            v2.getOperatorRegisterAgentsNonce(operator, serviceId)
        );
    }

    function _v1Register(address operator, uint256 serviceId, address[] memory instances, bytes memory signature)
        internal
    {
        vm.prank(serviceOwner);
        v1.registerAgentsWithSignature{value: BOND}(operator, serviceId, instances, _ids(), signature);
    }

    function _v2Register(address operator, uint256 serviceId, address[] memory instances, bytes memory signature)
        internal
    {
        vm.prank(serviceOwner);
        v2.registerAgentsWithSignature{value: BOND}(
            operator, serviceId, instances, _ids(), ETH_TOKEN_ADDRESS, BOND, block.timestamp, signature
        );
    }

    function _v1UnbondHash(address operator, uint256 serviceId) internal view returns (bytes32) {
        return v1.getUnbondHash(operator, serviceOwner, serviceId, v1.getOperatorUnbondNonce(operator, serviceId));
    }

    function _v2UnbondHash(address operator, uint256 serviceId) internal view returns (bytes32) {
        return v2.getUnbondHash(
            operator, serviceOwner, serviceId, block.timestamp, v2.getOperatorUnbondNonce(operator, serviceId)
        );
    }

    function _v2Unbond(address operator, uint256 serviceId, bytes memory signature) internal {
        vm.prank(serviceOwner);
        v2.unbondWithSignature(operator, serviceId, block.timestamp, signature);
    }

    function _terminate(uint256 serviceId) internal {
        vm.prank(serviceOwner);
        v1.terminate(serviceId);
    }

    function _state(uint256 serviceId) internal view returns (uint8 state) {
        (,,,,,, state) = IServiceRegistryState(SERVICE_REGISTRY).mapServices(serviceId);
    }

    /// @dev The controller approves a digest in the operator contract; the digest is computed before the prank.
    function _approve(ContractOperator op, bytes32 hash) internal {
        vm.prank(controller);
        op.approveHash(hash);
    }

    /// @dev A 1-of-1 Safe v1.3.0 owned by the controller, with the compatibility fallback handler (EIP-1271).
    function _safe() internal returns (address safe) {
        address[] memory owners = new address[](1);
        owners[0] = controller;
        bytes memory initializer = abi.encodeCall(
            ISafe.setup, (owners, 1, address(0), "", SAFE_FALLBACK_HANDLER, address(0), 0, payable(address(0)))
        );
        safe = ISafeProxyFactory(SAFE_PROXY_FACTORY).createProxyWithNonce(SAFE_SINGLETON, initializer, ++instanceCount);
        assertEq(ISafe(safe).VERSION(), "1.3.0", "Safe version");
    }

    /// @dev The Safe calls `operatorApproveHash(hash)` on the ServiceManager; its owner executes with an approved
    ///      signature (`v = 1`, owner in r).
    function _safeApprove(address safe, bytes32 hash) internal {
        bytes memory ownerSignature = abi.encodePacked(bytes32(uint256(uint160(controller))), bytes32(0), uint8(1));
        vm.prank(controller);
        ISafe(safe)
            .execTransaction(
                PROXY,
                0,
                abi.encodeWithSignature("operatorApproveHash(bytes32)", hash),
                0,
                0,
                0,
                0,
                address(0),
                payable(address(0)),
                ownerSignature
            );
        assertTrue(v2.isOperatorHashApproved(safe, hash), "Safe approval recorded");
    }

    // ---------- contract-signature path, custom contract-operator interface ----------

    function test_contractOperator_registerAcrossTheUpgrade() public {
        ContractOperator op = new ContractOperator(controller);
        address operator = address(op);
        uint256 serviceId = _activeService(3);

        // 1. v1.2.0: the operator contract validates its approved digest
        address[] memory first = _nextInstance();
        _approve(op, _v1RegisterHash(operator, serviceId, first));
        _v1Register(operator, serviceId, first, _contractSignature(operator));

        // A v1.2.0 authorization still pending at the upgrade
        address[] memory second = _nextInstance();
        _approve(op, _v1RegisterHash(operator, serviceId, second));

        _upgrade();

        // 3. The pending v1.2.0 authorization does not validate the v1.3.0 digest
        bytes32 v2Hash = _v2RegisterHash(operator, serviceId, second);
        vm.expectRevert(
            abi.encodeWithSelector(HashNotValidated.selector, operator, v2Hash, _contractSignature(operator))
        );
        _v2Register(operator, serviceId, second, _contractSignature(operator));

        // 4. Invalid signatures: wrong length, and a validation for a different operator
        vm.expectRevert(
            abi.encodeWithSelector(IncorrectSignatureLength.selector, abi.encodePacked(bytes32(0), bytes32(0)), 64, 65)
        );
        _v2Register(operator, serviceId, second, abi.encodePacked(bytes32(0), bytes32(0)));

        address other = makeAddr("otherOperator");
        _approve(op, _v2RegisterHash(other, serviceId, second));
        vm.expectRevert(abi.encodeWithSelector(WrongOperatorAddress.selector, operator, other));
        _v2Register(other, serviceId, second, _contractSignature(operator));

        // 2. v1.3.0: a fresh authorization with the same mechanism succeeds
        _approve(op, v2Hash);
        _v2Register(operator, serviceId, second, _contractSignature(operator));
        assertEq(
            v2.getOperatorRegisterAgentsNonce(operator, serviceId), 2, "two registrations by the contract operator"
        );
    }

    function test_contractOperator_unbondAcrossTheUpgrade() public {
        ContractOperator op = new ContractOperator(controller);
        address operator = address(op);

        // Two services, each with the operator contract registered through its signature, then terminated
        uint256[2] memory serviceIds;
        for (uint256 i = 0; i < 2; ++i) {
            serviceIds[i] = _activeService(1);
            address[] memory instance = _nextInstance();
            _approve(op, _v1RegisterHash(operator, serviceIds[i], instance));
            _v1Register(operator, serviceIds[i], instance, _contractSignature(operator));
            assertEq(_state(serviceIds[i]), FINISHED_REGISTRATION);
            _terminate(serviceIds[i]);
        }

        // 1. v1.2.0: unbond the first service
        _approve(op, _v1UnbondHash(operator, serviceIds[0]));
        uint256 balance = operator.balance;
        vm.prank(serviceOwner);
        v1.unbondWithSignature(operator, serviceIds[0], _contractSignature(operator));
        assertEq(operator.balance, balance + BOND, "v1.2.0 unbond refunded");

        // A v1.2.0 unbond authorization for the second service, still pending at the upgrade
        _approve(op, _v1UnbondHash(operator, serviceIds[1]));

        _upgrade();

        // 3. The pending v1.2.0 authorization does not validate the v1.3.0 digest
        bytes32 v2Hash = _v2UnbondHash(operator, serviceIds[1]);
        vm.expectRevert(
            abi.encodeWithSelector(HashNotValidated.selector, operator, v2Hash, _contractSignature(operator))
        );
        _v2Unbond(operator, serviceIds[1], _contractSignature(operator));

        // 4. Invalid signature: another contract operator that validated nothing
        ContractOperator stranger = new ContractOperator(controller);
        vm.expectRevert(
            abi.encodeWithSelector(
                HashNotValidated.selector,
                address(stranger),
                _v2UnbondHash(address(stranger), serviceIds[1]),
                _contractSignature(address(stranger))
            )
        );
        _v2Unbond(address(stranger), serviceIds[1], _contractSignature(address(stranger)));

        // 2. v1.3.0: a fresh authorization with the same mechanism succeeds
        _approve(op, v2Hash);
        balance = operator.balance;
        _v2Unbond(operator, serviceIds[1], _contractSignature(operator));
        assertEq(operator.balance, balance + BOND, "v1.3.0 unbond refunded");
    }

    // ---------- pre-approved hash path, real Safe v1.3.0 ----------

    function test_safeOperator_registerAcrossTheUpgrade() public {
        address safe = _safe();
        uint256 serviceId = _activeService(2);

        // 1. v1.2.0: the Safe approves the digest in its own transaction
        address[] memory first = _nextInstance();
        _safeApprove(safe, _v1RegisterHash(safe, serviceId, first));
        _v1Register(safe, serviceId, first, _approvedSignature(safe));

        // A v1.2.0 approval still pending at the upgrade
        address[] memory second = _nextInstance();
        bytes32 v1Hash = _v1RegisterHash(safe, serviceId, second);
        _safeApprove(safe, v1Hash);

        _upgrade();

        // 3. The v1.2.0 approval stays stored, but does not authorize the v1.3.0 digest
        assertTrue(v2.isOperatorHashApproved(safe, v1Hash), "v1.2.0 approval left in place");
        bytes32 v2Hash = _v2RegisterHash(safe, serviceId, second);
        vm.expectRevert(abi.encodeWithSelector(HashNotApproved.selector, safe, v2Hash, _approvedSignature(safe)));
        _v2Register(safe, serviceId, second, _approvedSignature(safe));

        // 4. Invalid signature: the approval of another operator does not count for the Safe
        address other = makeAddr("otherOperator");
        vm.prank(other);
        v2.operatorApproveHash(v2Hash);
        vm.expectRevert(abi.encodeWithSelector(WrongOperatorAddress.selector, other, safe));
        _v2Register(safe, serviceId, second, _approvedSignature(other));

        // 2. v1.3.0: a fresh approval through the Safe succeeds
        _safeApprove(safe, v2Hash);
        _v2Register(safe, serviceId, second, _approvedSignature(safe));
        assertEq(_state(serviceId), FINISHED_REGISTRATION, "both Safe registrations");
    }

    function test_safeOperator_unbondAcrossTheUpgrade() public {
        address safe = _safe();

        uint256[2] memory serviceIds;
        for (uint256 i = 0; i < 2; ++i) {
            serviceIds[i] = _activeService(1);
            address[] memory instance = _nextInstance();
            _safeApprove(safe, _v1RegisterHash(safe, serviceIds[i], instance));
            _v1Register(safe, serviceIds[i], instance, _approvedSignature(safe));
            _terminate(serviceIds[i]);
        }

        // 1. v1.2.0: unbond the first service
        _safeApprove(safe, _v1UnbondHash(safe, serviceIds[0]));
        uint256 balance = safe.balance;
        vm.prank(serviceOwner);
        v1.unbondWithSignature(safe, serviceIds[0], _approvedSignature(safe));
        assertEq(safe.balance, balance + BOND, "v1.2.0 unbond refunded");

        // A v1.2.0 approval for the second service, still pending at the upgrade
        bytes32 v1Hash = _v1UnbondHash(safe, serviceIds[1]);
        _safeApprove(safe, v1Hash);

        _upgrade();

        // 3. The v1.2.0 approval stays stored, but does not authorize the v1.3.0 digest
        assertTrue(v2.isOperatorHashApproved(safe, v1Hash), "v1.2.0 approval left in place");
        bytes32 v2Hash = _v2UnbondHash(safe, serviceIds[1]);
        vm.expectRevert(abi.encodeWithSelector(HashNotApproved.selector, safe, v2Hash, _approvedSignature(safe)));
        _v2Unbond(safe, serviceIds[1], _approvedSignature(safe));

        // 4. Invalid signature: wrong length
        bytes memory short = abi.encodePacked(bytes32(uint256(uint160(safe))), bytes32(0));
        vm.expectRevert(abi.encodeWithSelector(IncorrectSignatureLength.selector, short, 64, 65));
        _v2Unbond(safe, serviceIds[1], short);

        // 2. v1.3.0: a fresh approval through the Safe succeeds
        _safeApprove(safe, v2Hash);
        balance = safe.balance;
        _v2Unbond(safe, serviceIds[1], _approvedSignature(safe));
        assertEq(safe.balance, balance + BOND, "v1.3.0 unbond refunded");
    }

    /// @notice Scope: the contract-signature path is not usable by a Safe, on v1.2.0 or v1.3.0. The signature bytes
    ///         `(Safe, 0, 4)` are passed to the Safe's EIP-1271 handler, which checks any non-empty signature as owner
    ///         signatures; `v = 4` is not a Safe signature type, so it reverts with GS026 ("Invalid owner provided").
    function test_safeCannotUseContractSignaturePath() public {
        address safe = _safe();
        uint256 serviceId = _activeService(2);

        address[] memory instance = _nextInstance();
        vm.expectRevert(bytes("GS026"));
        _v1Register(safe, serviceId, instance, _contractSignature(safe));

        _upgrade();

        vm.expectRevert(bytes("GS026"));
        _v2Register(safe, serviceId, instance, _contractSignature(safe));
    }
}
