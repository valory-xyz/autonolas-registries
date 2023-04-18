// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @dev Interface for the service registration token utility manipulation.
interface IServiceTokenUtility {
    /// @dev Creates a record with the token-related information for the specified service.
    /// @param serviceId Service Id.
    /// @param token Token address.
    /// @param agentIds Set of agent Ids.
    /// @param bonds Set of correspondent bonds.
    function createWithToken(uint256 serviceId, address token, uint32[] memory agentIds, uint256[] memory bonds) external;

    /// @dev Deposit a token bond for service registration after its activation.
    /// @param serviceId Correspondent service Id.
    function activationTokenDeposit(uint256 serviceId) external returns (uint256 depositValue);

    /// @dev Updates a service in a CRUD way.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param bonds Set of required bonds to register an instance in the service corresponding to agent Ids.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    function update(
        address serviceOwner,
        bytes32 configHash,
        uint32[] memory agentIds,
        uint256[] memory bonds,
        uint32 threshold,
        uint256 serviceId
    ) external returns (bool success);

    /// @dev Activates the service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function activateRegistration(address serviceOwner, uint256 serviceId) external payable returns (bool success);

    /// @dev Registers agent instances.
    /// @param operator Address of the operator.
    /// @param serviceId Service Id to be updated.
    /// @param agentInstances Agent instance addresses.
    /// @param agentIds Canonical Ids of the agent correspondent to the agent instance.
    /// @return success True, if function executed successfully.
    function registerAgents(
        address operator,
        uint256 serviceId,
        address[] memory agentInstances,
        uint32[] memory agentIds
    ) external payable returns (bool success);

    /// @dev Creates multisig instance controlled by the set of service agent instances and deploys the service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @param multisigImplementation Multisig implementation address.
    /// @param data Data payload for the multisig creation.
    /// @return multisig Address of the created multisig.
    function deploy(
        address serviceOwner,
        uint256 serviceId,
        address multisigImplementation,
        bytes memory data
    ) external returns (address multisig);

    /// @dev Terminates the service.
    /// @param serviceOwner Owner of the service.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    /// @return refund Refund to return to the serviceOwner.
    function terminate(address serviceOwner, uint256 serviceId) external returns (bool success, uint256 refund);

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param operator Operator of agent instances.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function unbond(address operator, uint256 serviceId) external returns (bool success, uint256 refund);
}
