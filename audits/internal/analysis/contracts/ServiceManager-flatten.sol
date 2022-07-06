// The following code is from flattening this file: ServiceManager.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// The following code is from flattening this import statement in: ServiceManager.sol
// import "./GenericManager.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-registries/contracts/GenericManager.sol
pragma solidity ^0.8.15;

// The following code is from flattening this import statement in: /home/andrey/valory/audit-process/projects/autonolas-registries/contracts/GenericManager.sol
// import "./interfaces/IErrorsRegistries.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-registries/contracts/interfaces/IErrorsRegistries.sol
pragma solidity ^0.8.14;

/// @dev Errors.
interface IErrorsRegistries {
    /// @dev Only `manager` has a privilege, but the `sender` was provided.
    /// @param sender Sender address.
    /// @param manager Required sender address as a manager.
    error ManagerOnly(address sender, address manager);

    /// @dev Only `owner` has a privilege, but the `sender` was provided.
    /// @param sender Sender address.
    /// @param owner Required sender address as an owner.
    error OwnerOnly(address sender, address owner);

    /// @dev Hash already exists in the records.
    error HashExists();

    /// @dev Provided zero address.
    error ZeroAddress();

    /// @dev Agent Id is not correctly provided for the current routine.
    /// @param agentId Component Id.
    error WrongAgentId(uint256 agentId);

    /// @dev Wrong length of two arrays.
    /// @param numValues1 Number of values in a first array.
    /// @param numValues2 Numberf of values in a second array.
    error WrongArrayLength(uint256 numValues1, uint256 numValues2);

    /// @dev Canonical agent Id is not found.
    /// @param agentId Canonical agent Id.
    error AgentNotFound(uint256 agentId);

    /// @dev Component Id is not found.
    /// @param componentId Component Id.
    error ComponentNotFound(uint256 componentId);

    /// @dev Multisig threshold is out of bounds.
    /// @param currentThreshold Current threshold value.
    /// @param minThreshold Minimum possible threshold value.
    /// @param maxThreshold Maximum possible threshold value.
    error WrongThreshold(uint256 currentThreshold, uint256 minThreshold, uint256 maxThreshold);

    /// @dev Service Id is not found, although service Id might exist in the records.
    /// @dev serviceId Service Id.
    error ServiceNotFound(uint256 serviceId);

    /// @dev Agent instance is already registered with a specified `operator`.
    /// @param operator Operator that registered an instance.
    error AgentInstanceRegistered(address operator);

    /// @dev Wrong operator is specified when interacting with a specified `serviceId`.
    /// @param serviceId Service Id.
    error WrongOperator(uint256 serviceId);

    /// @dev Operator has no registered instances in the service.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    error OperatorHasNoInstances(address operator, uint256 serviceId);

    /// @dev Canonical `agentId` is not found as a part of `serviceId`.
    /// @param agentId Canonical agent Id.
    /// @param serviceId Service Id.
    error AgentNotInService(uint256 agentId, uint256 serviceId);

    /// @dev The contract is paused.
    error Paused();

    /// @dev Zero value when it has to be different from zero.
    error ZeroValue();

    /// @dev Value overflow.
    /// @param provided Overflow value.
    /// @param max Maximum possible value.
    error Overflow(uint256 provided, uint256 max);

    /// @dev Service must be inactive.
    /// @param serviceId Service Id.
    error ServiceMustBeInactive(uint256 serviceId);

    /// @dev All the agent instance slots for a specific `serviceId` are filled.
    /// @param serviceId Service Id.
    error AgentInstancesSlotsFilled(uint256 serviceId);

    /// @dev Wrong state of a service.
    /// @param state Service state.
    /// @param serviceId Service Id.
    error WrongServiceState(uint256 state, uint256 serviceId);

    /// @dev Only own service multisig is allowed.
    /// @param provided Provided address.
    /// @param expected Expected multisig address.
    /// @param serviceId Service Id.
    error OnlyOwnServiceMultisig(address provided, address expected, uint256 serviceId);

    /// @dev Fallback or receive function.
    error WrongFunction();

    /// @dev Multisig is not whitelisted.
    /// @param multisig Address of a multisig implementation.
    error UnauthorizedMultisig(address multisig);

    /// @dev Incorrect deposit provided for the registration activation.
    /// @param sent Sent amount.
    /// @param expected Expected amount.
    /// @param serviceId Service Id.
    error IncorrectRegistrationDepositValue(uint256 sent, uint256 expected, uint256 serviceId);

    /// @dev Insufficient value provided for the agent instance bonding.
    /// @param sent Sent amount.
    /// @param expected Expected amount.
    /// @param serviceId Service Id.
    error IncorrectAgentBondingValue(uint256 sent, uint256 expected, uint256 serviceId);

    /// @dev Failure of a transfer.
    /// @param token Address of a token.
    /// @param from Address `from`.
    /// @param to Address `to`.
    /// @param value Value.
    error TransferFailed(address token, address from, address to, uint256 value);

    /// @dev Caught reentrancy violation.
    error ReentrancyGuard();
}


/// @title Generic Manager - Smart contract for generic registry manager template
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
abstract contract GenericManager is IErrorsRegistries {
    event OwnerUpdated(address indexed owner);
    event Pause(address indexed owner);
    event Unpause(address indexed owner);

    // Owner address
    address public owner;
    // Pause switch
    bool public paused;

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Pauses the contract.
    function pause() external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = true;
        emit Pause(msg.sender);
    }

    /// @dev Unpauses the contract.
    function unpause() external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = false;
        emit Unpause(msg.sender);
    }
}

// The following code is from flattening this import statement in: ServiceManager.sol
// import "./interfaces/IService.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-registries/contracts/interfaces/IService.sol
pragma solidity ^0.8.14;

/// @dev Required interface for the service manipulation.
interface IService{
    struct AgentParams {
        // Number of agent instances
        uint256 slots;
        // Bond per agent instance
        uint256 bond;
    }

    /// @dev Creates a new service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function create(
        address owner,
        string memory name,
        string memory description,
        bytes32 configHash,
        uint256[] memory agentIds,
        AgentParams[] memory agentParams,
        uint256 threshold
    ) external returns (uint256 serviceId);

    /// @dev Updates a service in a CRUD way.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    function update(
        address owner,
        string memory name,
        string memory description,
        bytes32 configHash,
        uint256[] memory agentIds,
        AgentParams[] memory agentParams,
        uint256 threshold,
        uint256 serviceId
    ) external returns (bool success);

    /// @dev Activates the service.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function activateRegistration(address owner, uint256 serviceId) external payable returns (bool success);

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
        uint256[] memory agentIds
    ) external payable returns (bool success);

    /// @dev Creates multisig instance controlled by the set of service agent instances and deploys the service.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @param multisigImplementation Multisig implementation address.
    /// @param data Data payload for the multisig creation.
    /// @return multisig Address of the created multisig.
    function deploy(
        address owner,
        uint256 serviceId,
        address multisigImplementation,
        bytes memory data
    ) external returns (address multisig);

    /// @dev Terminates the service.
    /// @param owner Owner of the service.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    /// @return refund Refund to return to the owner.
    function terminate(address owner, uint256 serviceId) external returns (bool success, uint256 refund);

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param operator Operator of agent instances.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function unbond(address operator, uint256 serviceId) external returns (bool success, uint256 refund);

    /// @dev Destroys the service instance.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function destroy(address owner, uint256 serviceId) external returns (bool success);

    /// @dev Checks if the service Id exists.
    /// @param serviceId Service Id.
    /// @return true if the service exists, false otherwise.
    function exists(uint256 serviceId) external view returns (bool);

    /// @dev Gets the set of service Ids that contain specified agent Id.
    /// @param agentId Agent Id.
    /// @return numServiceIds Number of service Ids.
    /// @return serviceIds Set of service Ids.
    function getServiceIdsCreatedWithAgentId(uint256 agentId) external view
        returns (uint256 numServiceIds, uint256[] memory serviceIds);

    /// @dev Gets the set of service Ids that contain specified component Id (through the agent Id).
    /// @param componentId Component Id.
    /// @return numServiceIds Number of service Ids.
    /// @return serviceIds Set of service Ids.
    function getServiceIdsCreatedWithComponentId(uint256 componentId) external view
        returns (uint256 numServiceIds, uint256[] memory serviceIds);

    /// @dev Gets the set of canonical agent Ids that contain specified service Id.
    /// @param serviceId Service Id.
    /// @return numAgentIds Number of agent Ids.
    /// @return agentIds Set of agent Ids.
    function getAgentIdsOfServiceId(uint256 serviceId) external view
        returns (uint256 numAgentIds, uint256[] memory agentIds);

    /// @dev Gets the set of component Ids that contain specified service Id.
    /// @param serviceId Service Id.
    /// @return numComponentIds Number of component Ids.
    /// @return componentIds Set of component Ids.
    function getComponentIdsOfServiceId(uint256 serviceId) external view
        returns (uint256 numComponentIds, uint256[] memory componentIds);
}


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
        // Check for the treasury address
        if (treasury == address(0)) {
            revert ZeroAddress();
        }

        uint256[] memory serviceIds = new uint256[](1);
        serviceIds[0] = serviceId;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = msg.value;
        IReward(treasury).depositETHFromServices{value: msg.value}(serviceIds, amounts);
        emit RewardService(serviceId, msg.value);
    }
}



