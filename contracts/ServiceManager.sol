// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./GenericManager.sol";
import "./interfaces/IService.sol";

// Treasury related interface
interface IReward {
    /// @dev Deposits ETH from protocol-owned service.
    /// @param serviceIds Set of service Ids.
    /// @param amounts Correspondent set of amounts.
    function depositETHFromServices(uint256[] memory serviceIds, uint256[] memory amounts) external payable;
}

/// @title Service Manager - Periphery smart contract for managing services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceManager is GenericManager {
    event TreasuryUpdated(address indexed treasury);
    event CreateMultisig(address indexed multisig);
    event RewardService(uint256 serviceId, uint256 amount);

    // Service registry address
    address public immutable serviceRegistry;
    // Treasury address
    address public treasury;

    constructor(address _serviceRegistry, address _treasury) {
        serviceRegistry = _serviceRegistry;
        treasury = _treasury;
        owner = msg.sender;
    }

    /// @dev Fallback function
    fallback() external payable {
        revert WrongFunction();
    }

    /// @dev Receive function
    receive() external payable {
        revert WrongFunction();
    }

    /// @dev Changes the treasury address.
    /// @param _treasury Address of a new treasury.
    function changeTreasury(address _treasury) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    /// @dev Creates a new service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Threshold for a multisig composed by agents.
    function serviceCreate(
        address serviceOwner,
        string memory name,
        string memory description,
        bytes32 configHash,
        uint256[] memory agentIds,
        IService.AgentParams[] memory agentParams,
        uint256 threshold
    ) external returns (uint256)
    {
        // Check if the minting is paused
        if (paused) {
            revert Paused();
        }
        return IService(serviceRegistry).create(serviceOwner, name, description, configHash, agentIds, agentParams,
            threshold);
    }

    /// @dev Updates a service in a CRUD way.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Threshold for a multisig composed by agents.
    /// @param serviceId Service Id to be updated.
    function serviceUpdate(
        string memory name,
        string memory description,
        bytes32 configHash,
        uint256[] memory agentIds,
        IService.AgentParams[] memory agentParams,
        uint256 threshold,
        uint256 serviceId
    ) external
    {
        IService(serviceRegistry).update(msg.sender, name, description, configHash, agentIds, agentParams,
            threshold, serviceId);
    }

    /// @dev Activates the service and its sensitive components.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function serviceActivateRegistration(uint256 serviceId) external payable returns (bool success) {
        success = IService(serviceRegistry).activateRegistration{value: msg.value}(msg.sender, serviceId);
    }

    /// @dev Registers agent instances.
    /// @param serviceId Service Id to be updated.
    /// @param agentInstances Agent instance addresses.
    /// @param agentIds Canonical Ids of the agent correspondent to the agent instance.
    /// @return success True, if function executed successfully.
    function serviceRegisterAgents(
        uint256 serviceId,
        address[] memory agentInstances,
        uint256[] memory agentIds
    ) external payable returns (bool success) {
        success = IService(serviceRegistry).registerAgents{value: msg.value}(msg.sender, serviceId, agentInstances, agentIds);
    }

    /// @dev Creates multisig instance controlled by the set of service agent instances and deploys the service.
    /// @param serviceId Correspondent service Id.
    /// @param multisigImplementation Multisig implementation address.
    /// @param data Data payload for the multisig creation.
    /// @return multisig Address of the created multisig.
    function serviceDeploy(
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
    function serviceTerminate(uint256 serviceId) external returns (bool success, uint256 refund) {
        (success, refund) = IService(serviceRegistry).terminate(msg.sender, serviceId);
    }

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function serviceUnbond(uint256 serviceId) external returns (bool success, uint256 refund) {
        (success, refund) = IService(serviceRegistry).unbond(msg.sender, serviceId);
    }

    /// @dev Destroys the service instance and frees up its storage.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function serviceDestroy(uint256 serviceId) external returns (bool success) {
        success = IService(serviceRegistry).destroy(msg.sender, serviceId);
    }

    /// @dev Rewards the protocol-owned service with an ETH payment.
    /// @param serviceId Service Id.
    function serviceReward(uint256 serviceId) external payable
    {
        uint256[] memory serviceIds = new uint256[](1);
        serviceIds[0] = serviceId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = msg.value;
        IReward(treasury).depositETHFromServices{value: msg.value}(serviceIds, amounts);
        emit RewardService(serviceId, msg.value);
    }
}
