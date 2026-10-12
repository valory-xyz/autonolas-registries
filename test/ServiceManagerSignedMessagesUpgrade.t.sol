// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ServiceManager} from "../contracts/ServiceManager.sol";
import {HashNotApproved, WrongOperatorAddress} from "../contracts/utils/OperatorSignedHashes.sol";

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
    function registerAgents(uint256 serviceId, address[] memory agentInstances, uint32[] memory agentIds)
        external
        payable
        returns (bool);
    function terminate(uint256 serviceId) external returns (bool, uint256);
    function operatorApproveHash(bytes32 hash) external;
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

/// @title ServiceManagerSignedMessagesUpgradeTest
/// @notice Upgrades the live mainnet ServiceManagerProxy from v1.2.0 to the v1.3.0 signed-message format. Operator
///         authorizations made before the upgrade, both signatures and pre-approved hashes, stop authorizing
///         registration and unbonding, because the contract now computes different digests; the stored approvals
///         are left in place. Fresh v1.3.0 signatures and pre-approved hashes work on the same proxy.
///
///         Run: ETH_RPC=<mainnet rpc> forge test --match-contract ServiceManagerSignedMessagesUpgrade -vv
contract ServiceManagerSignedMessagesUpgradeTest is Test {
    address internal constant PROXY = 0x94a1892D91c05D0C61c3f49F42205D2285b914c9;
    address internal constant SERVICE_REGISTRY = 0x48b6af7B12C71f09e2fC8aF4855De4Ff54e775cA;
    address internal constant TOKEN_UTILITY = 0x3Fb926116D454b95c669B6Bf2E7c3bad8d19affA;
    address internal constant ETH_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint96 internal constant BOND = 1 ether;
    uint256 internal constant SERVICE_REGISTRY_FINISHED_REGISTRATION = 3;

    IServiceManagerV1 internal v1 = IServiceManagerV1(PROXY);
    ServiceManager internal v2 = ServiceManager(PROXY);
    address internal serviceOwner = makeAddr("serviceOwner");
    address internal operatorA;
    uint256 internal operatorAKey;
    address internal operatorB = makeAddr("operatorB");
    address internal instanceA = makeAddr("instanceA");
    address internal instanceB = makeAddr("instanceB");

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC"));
        (operatorA, operatorAKey) = makeAddrAndKey("operatorA");
        vm.deal(serviceOwner, 100 ether);
        vm.deal(operatorA, 100 ether);
        assertEq(v1.VERSION(), "1.2.0", "live implementation");
    }

    function _one(address a) internal pure returns (address[] memory out) {
        out = new address[](1);
        out[0] = a;
    }

    function _ids() internal pure returns (uint32[] memory out) {
        out = new uint32[](1);
        out[0] = 1;
    }

    /// @dev Creates and activates a native-token service with two slots of agent 1.
    function _activeService() internal returns (uint256 serviceId) {
        IServiceManagerV1.AgentParams[] memory params = new IServiceManagerV1.AgentParams[](1);
        params[0] = IServiceManagerV1.AgentParams({slots: 2, bond: BOND});
        serviceId = v1.create(serviceOwner, ETH_TOKEN_ADDRESS, bytes32(uint256(1)), _ids(), params, 2);
        vm.prank(serviceOwner);
        v1.activateRegistration{value: BOND}(serviceId);
    }

    function _upgrade() internal {
        ServiceManager impl = new ServiceManager(SERVICE_REGISTRY, TOKEN_UTILITY);
        vm.prank(v1.owner());
        v1.changeImplementation(address(impl));
        assertEq(v2.VERSION(), "1.3.0", "upgraded implementation");
    }

    function _sign(uint256 key, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Signature bytes that select the pre-approved hash path for the operator.
    function _approved(address operator) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes32(uint256(uint160(operator))), bytes32(0), uint8(5));
    }

    function _recover(bytes32 digest, bytes memory signature) internal pure returns (address) {
        (bytes32 r, bytes32 s) = abi.decode(signature, (bytes32, bytes32));
        return ecrecover(digest, uint8(signature[64]), r, s);
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

    function _register(address operator, uint256 serviceId, address[] memory instances, bytes memory signature)
        internal
    {
        vm.prank(serviceOwner);
        v2.registerAgentsWithSignature{value: BOND}(
            operator, serviceId, instances, _ids(), ETH_TOKEN_ADDRESS, BOND, block.timestamp, signature
        );
    }

    /// @notice Registration: a v1 signature and a v1 pre-approved hash made before the upgrade fail after it;
    ///         fresh v1.3.0 ones succeed.
    function test_registerAuthorizationsAcrossTheUpgrade() public {
        uint256 serviceId = _activeService();
        address[] memory instancesA = _one(instanceA);
        address[] memory instancesB = _one(instanceB);

        // Before the upgrade: operator A signs, operator B pre-approves, both in the v1 format
        bytes memory v1SignatureA = _sign(
            operatorAKey,
            v1.getRegisterAgentsHash(
                operatorA,
                serviceOwner,
                serviceId,
                instancesA,
                _ids(),
                v1.getOperatorRegisterAgentsNonce(operatorA, serviceId)
            )
        );
        bytes32 v1HashB = v1.getRegisterAgentsHash(
            operatorB,
            serviceOwner,
            serviceId,
            instancesB,
            _ids(),
            v1.getOperatorRegisterAgentsNonce(operatorB, serviceId)
        );
        vm.prank(operatorB);
        v1.operatorApproveHash(v1HashB);

        _upgrade();

        // The v1 signature recovers a different address against the v1.3.0 digest
        bytes32 v2HashA = _v2RegisterHash(operatorA, serviceId, instancesA);
        vm.expectRevert(
            abi.encodeWithSelector(WrongOperatorAddress.selector, _recover(v2HashA, v1SignatureA), operatorA)
        );
        _register(operatorA, serviceId, instancesA, v1SignatureA);

        // The v1 approval stays stored, but does not authorize the v1.3.0 digest
        assertTrue(v2.isOperatorHashApproved(operatorB, v1HashB), "v1 approval left in place");
        bytes32 v2HashB = _v2RegisterHash(operatorB, serviceId, instancesB);
        vm.expectRevert(abi.encodeWithSelector(HashNotApproved.selector, operatorB, v2HashB, _approved(operatorB)));
        _register(operatorB, serviceId, instancesB, _approved(operatorB));

        // Fresh v1.3.0 authorizations register both operators
        _register(operatorA, serviceId, instancesA, _sign(operatorAKey, v2HashA));
        vm.prank(operatorB);
        v2.operatorApproveHash(v2HashB);
        _register(operatorB, serviceId, instancesB, _approved(operatorB));

        (,,,,,, uint8 state) = IServiceRegistryState(SERVICE_REGISTRY).mapServices(serviceId);
        assertEq(state, SERVICE_REGISTRY_FINISHED_REGISTRATION, "both operators registered");
    }

    /// @notice Unbonding: a v1 signature and a v1 pre-approved hash made before the upgrade fail after it;
    ///         fresh v1.3.0 ones succeed.
    function test_unbondAuthorizationsAcrossTheUpgrade() public {
        uint256 serviceId = _activeService();

        // Both operators register directly, and the service is terminated
        vm.prank(operatorA);
        v1.registerAgents{value: BOND}(serviceId, _one(instanceA), _ids());
        vm.deal(operatorB, 100 ether);
        vm.prank(operatorB);
        v1.registerAgents{value: BOND}(serviceId, _one(instanceB), _ids());
        vm.prank(serviceOwner);
        v1.terminate(serviceId);

        // Before the upgrade: operator A signs, operator B pre-approves, both in the v1 format
        bytes memory v1SignatureA = _sign(
            operatorAKey,
            v1.getUnbondHash(operatorA, serviceOwner, serviceId, v1.getOperatorUnbondNonce(operatorA, serviceId))
        );
        bytes32 v1HashB =
            v1.getUnbondHash(operatorB, serviceOwner, serviceId, v1.getOperatorUnbondNonce(operatorB, serviceId));
        vm.prank(operatorB);
        v1.operatorApproveHash(v1HashB);

        _upgrade();

        uint256 deadline = block.timestamp;
        bytes32 v2HashA = v2.getUnbondHash(
            operatorA, serviceOwner, serviceId, deadline, v2.getOperatorUnbondNonce(operatorA, serviceId)
        );
        vm.expectRevert(
            abi.encodeWithSelector(WrongOperatorAddress.selector, _recover(v2HashA, v1SignatureA), operatorA)
        );
        vm.prank(serviceOwner);
        v2.unbondWithSignature(operatorA, serviceId, deadline, v1SignatureA);

        assertTrue(v2.isOperatorHashApproved(operatorB, v1HashB), "v1 approval left in place");
        bytes32 v2HashB = v2.getUnbondHash(
            operatorB, serviceOwner, serviceId, deadline, v2.getOperatorUnbondNonce(operatorB, serviceId)
        );
        vm.expectRevert(abi.encodeWithSelector(HashNotApproved.selector, operatorB, v2HashB, _approved(operatorB)));
        vm.prank(serviceOwner);
        v2.unbondWithSignature(operatorB, serviceId, deadline, _approved(operatorB));

        // Fresh v1.3.0 authorizations unbond both operators and refund their bonds
        uint256 balanceA = operatorA.balance;
        vm.prank(serviceOwner);
        v2.unbondWithSignature(operatorA, serviceId, deadline, _sign(operatorAKey, v2HashA));
        assertEq(operatorA.balance, balanceA + BOND, "operator A refunded");

        vm.prank(operatorB);
        v2.operatorApproveHash(v2HashB);
        uint256 balanceB = operatorB.balance;
        vm.prank(serviceOwner);
        v2.unbondWithSignature(operatorB, serviceId, deadline, _approved(operatorB));
        assertEq(operatorB.balance, balanceB + BOND, "operator B refunded");
    }
}

interface IServiceRegistryState {
    function mapServices(uint256 serviceId)
        external
        view
        returns (uint96, address, bytes32, uint32, uint32, uint32, uint8);
}
