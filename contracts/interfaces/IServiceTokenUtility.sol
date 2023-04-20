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

    /// @dev Deposit a token security deposit for the service registration after its activation.
    /// @param serviceId Service Id.
    /// @return isTokenSecured True if the service Id is token secured, false if ETH secured otherwise.
    function activateRegistrationTokenDeposit(uint256 serviceId) external returns (bool isTokenSecured);

    /// @dev Deposits bonded tokens from the operator during the agent instance registration.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @param agentIds Set of agent Ids for corresponding agent instances opertor is registering.
    /// @return isTokenSecured True if the service Id is token secured, false if ETH secured otherwise.
    function registerAgentsTokenDeposit(
        address operator,
        uint256 serviceId,
        uint32[] memory agentIds
    ) external returns (bool isTokenSecured);

    /// @dev Withdraws a token security deposit to the service owner after the service termination.
    /// @param serviceId Service Id.
    /// @return securityDeposit Returned token security deposit, or zero if the service is ETH-secured.
    function terminationTokenWithdraw(uint256 serviceId) external returns (uint256 securityDeposit);

    /// @dev Withdraws bonded tokens to the operator during the unbond phase.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @return refund Returned bonded token amount, or zero if the service is ETH-secured.
    function unbondTokenRefund(address operator, uint256 serviceId) external returns (uint256 refund);

    /// @dev Gets service token secured status.
    /// @param serviceId Service Id.
    /// @return True if the service Id is token secured.
    function isTokenSecuredService(uint256 serviceId) external view returns (bool);
}
