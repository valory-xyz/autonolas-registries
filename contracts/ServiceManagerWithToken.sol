// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./GenericManager.sol";
import "./interfaces/IService.sol";
import "./interfaces/IServiceTokenUtility.sol";

/// @title Service Manager - Periphery smart contract for managing services with custom ERC20 tokens
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract ServiceManagerWithToken is GenericManager {
    event CreateMultisig(address indexed multisig);

    // Service Registry address
    address public immutable serviceRegistry;
    // Service Registry Token Utility address
    address public immutable serviceRegistryTokenUtility;
    // Bond wrapping constant
    uint96 public constant BOND_WRAPPER = 1;

    constructor(address _serviceRegistry, address _serviceRegistryTokenUtility) {
        serviceRegistry = _serviceRegistry;
        serviceRegistryTokenUtility = _serviceRegistryTokenUtility;
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

    /// @dev Creates a new service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param token ERC20 token address.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Threshold for a multisig composed by agents.
    function createWithToken(
        address serviceOwner,
        address token,
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

        // Wrap agent params
        uint256 size = agentParams.length;
        IService.AgentParams[] memory tokenAgentParams = new IService.AgentParams[](size);
        for (uint256 i = 0; i < size; ++i) {
            tokenAgentParams[i].slots = agentParams[i].slots;
            tokenAgentParams[i].bond = BOND_WRAPPER;
        }

        uint256 serviceId = IService(serviceRegistry).create(serviceOwner, configHash, agentIds, tokenAgentParams,
            threshold);

        // Copy actual bond values for each agent Id
        uint256[] memory bonds = new uint256[](size);
        for (uint256 i = 0; i < size; ++i) {
            bonds[i] = agentParams[i].bond;
        }

        // Create a token-related record for the service
        IServiceTokenUtility(serviceRegistryTokenUtility).createWithToken(serviceId, token, agentIds, bonds);
        return serviceId;
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
        // Record the actual ERC20 deposit
        uint256 tokenDeposit = IServiceTokenUtility(serviceRegistryTokenUtility).activationTokenDeposit(serviceId);
        // Register in a main ServiceRegistry contract
        if (tokenDeposit > 0) {
            // If the service Id is based on the ERC20 token, the provided value to the standard registration is 1
            success = IService(serviceRegistry).activateRegistration{value: BOND_WRAPPER}(msg.sender, serviceId);
        } else {
            // Otherwise follow the standard msg.value path
            success = IService(serviceRegistry).activateRegistration{value: msg.value}(msg.sender, serviceId);
        }
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
