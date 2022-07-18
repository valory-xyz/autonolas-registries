// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./GenericManager.sol";
import "./interfaces/IService.sol";

/// @title Service Manager - Periphery smart contract for managing services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceManager is GenericManager {
    event CreateMultisig(address indexed multisig);

    // Service registry address
    address public immutable serviceRegistry;

    constructor(address _serviceRegistry) {
        serviceRegistry = _serviceRegistry;
        owner = msg.sender;
    }

    /// @dev Creates a new service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Threshold for a multisig composed by agents.
    function create(
        address serviceOwner,
        bytes32 configHash,
        uint32[] memory agentIds,
        IService.AgentParams[] memory agentParams,
        uint32 threshold
    ) external returns (uint256)
    {
        // Check if the minting is paused
        if (paused) {
            revert Paused();
        }
        return IService(serviceRegistry).create(serviceOwner, configHash, agentIds, agentParams,
            threshold);
    }

    /// @dev Updates a service in a CRUD way.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Threshold for a multisig composed by agents.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    function update(
        bytes32 configHash,
        uint32[] memory agentIds,
        IService.AgentParams[] memory agentParams,
        uint32 threshold,
        uint256 serviceId
    ) external returns (bool)
    {
        return IService(serviceRegistry).update(msg.sender, configHash, agentIds, agentParams,
            threshold, serviceId);
    }

    /// @dev Activates the service and its sensitive components.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function activateRegistration(uint256 serviceId) external payable returns (bool success) {
        success = IService(serviceRegistry).activateRegistration{value: msg.value}(msg.sender, serviceId);
    }

    /// @dev Registers agent instances.
    /// @param serviceId Service Id to be updated.
    /// @param agentInstances Agent instance addresses.
    /// @param agentIds Canonical Ids of the agent correspondent to the agent instance.
    /// @return success True, if function executed successfully.
    function registerAgents(
        uint256 serviceId,
        address[] memory agentInstances,
        uint32[] memory agentIds
    ) external payable returns (bool success) {
        success = IService(serviceRegistry).registerAgents{value: msg.value}(msg.sender, serviceId, agentInstances, agentIds);
    }

    /// @dev Creates multisig instance controlled by the set of service agent instances and deploys the service.
    /// @param serviceId Correspondent service Id.
    /// @param multisigImplementation Multisig implementation address.
    /// @param data Data payload for the multisig creation.
    /// @return multisig Address of the created multisig.
    function deploy(
        uint256 serviceId,
        address multisigImplementation,
        bytes memory data
    ) external returns (address multisig)
    {
        multisig = IService(serviceRegistry).deploy(msg.sender, serviceId, multisigImplementation, data);
        emit CreateMultisig(multisig);
    }

    /// @dev Terminates the service.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund Refund for the service owner.
    function terminate(uint256 serviceId) external returns (bool success, uint256 refund) {
        (success, refund) = IService(serviceRegistry).terminate(msg.sender, serviceId);
    }

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function unbond(uint256 serviceId) external returns (bool success, uint256 refund) {
        (success, refund) = IService(serviceRegistry).unbond(msg.sender, serviceId);
    }
}
