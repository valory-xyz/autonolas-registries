// The following code is from flattening this file: RegistriesManager.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// The following code is from flattening this import statement in: RegistriesManager.sol
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

// The following code is from flattening this import statement in: RegistriesManager.sol
// import "./interfaces/IRegistry.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-registries/contracts/interfaces/IRegistry.sol
pragma solidity ^0.8.14;

/// @dev Required interface for the component / agent manipulation.
interface IRegistry {
    /// @dev Creates component / agent.
    /// @param owner Owner of the component / agent.
    /// @param developer Developer of the component / agent.
    /// @param mHash IPFS hash of the component / agent.
    /// @param description Description of the component / agent.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted component / agent.
    function create(
        address owner,
        address developer,
        bytes32 mHash,
        bytes32 description,
        uint32[] memory dependencies
    ) external returns (uint256);

    /// @dev Updates the component / agent hash.
    /// @param owner Owner of the component / agent.
    /// @param unitId Unit Id.
    /// @param mHash New IPFS hash of the component / agent.
    function updateHash(address owner, uint256 unitId, bytes32 mHash) external;

    /// @dev Check for the component / agent existence.
    /// @param unitId Unit Id.
    /// @return true if the component / agent exists, false otherwise.
    function exists(uint256 unitId) external view returns (bool);

    /// @dev Gets the component / agent info.
    /// @param unitId Unit Id.
    /// @return owner Owner of the component / agent.
    /// @return developer The component developer.
    /// @return mHash The primary component / agent IPFS hash.
    /// @return description The component / agent description.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getInfo(uint256 unitId) external view returns (
        address owner,
        address developer,
        bytes32 mHash,
        bytes32 description,
        uint256 numDependencies,
        uint32[] memory dependencies
    );

    /// @dev Gets component / agent dependencies.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getDependencies(uint256 unitId) external view returns (
        uint256 numDependencies,
        uint32[] memory dependencies
    );

    /// @dev Gets subcomponents of a provided unit Id from a local public map.
    /// @param unitId Unit Id.
    /// @return subComponentIds Set of subcomponents.
    /// @return numSubComponents Number of subcomponents.
    function getLocalSubComponents(uint256 unitId) external view returns (uint32[] memory subComponentIds, uint256 numSubComponents);

    /// @dev Gets calculated subcomponents.
    /// @param unitIds Set of unit Ids.
    /// @return subComponentIds Set of subcomponents.
    function getSubComponents(uint32[] memory unitIds) external view returns (uint32[] memory subComponentIds);

    /// @dev Gets updated component / agent hashes.
    /// @param unitId Unit Id.
    /// @return numHashes Number of hashes.
    /// @return mHashes The list of component / agent hashes.
    function getUpdatedHashes(uint256 unitId) external view returns (uint256 numHashes, bytes32[] memory mHashes);

    /// @dev Gets the total supply of components / agents.
    /// @return Total supply.
    function totalSupply() external view returns (uint256);

    /// @dev Gets the valid component Id from the provided index.
    /// @param id Component counter.
    /// @return componentId Component Id.
    function tokenByIndex(uint256 id) external view returns (uint256 componentId);
}


/// @title Registries Manager - Periphery smart contract for managing components and agents
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract RegistriesManager is GenericManager {
    // Component registry address
    address public immutable componentRegistry;
    // Agent registry address
    address public immutable agentRegistry;
    // Mint fee
    uint256 private _creationFee;

    constructor(address _componentRegistry, address _agentRegistry) {
        componentRegistry = _componentRegistry;
        agentRegistry = _agentRegistry;
        owner = msg.sender;
    }

    /// @dev Creates agent.
    /// @param agentOwner Owner of the agent.
    /// @param developer Developer of the agent.
    /// @param agentHash IPFS hash of the agent.
    /// @param description Description of the agent.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a created agent.
    function createAgent(
        address agentOwner,
        address developer,
        bytes32 agentHash,
        bytes32 description,
        uint32[] memory dependencies
    ) external returns (uint256)
    {
        // Check if the creation is paused
        if (paused) {
            revert Paused();
        }
        return IRegistry(agentRegistry).create(agentOwner, developer, agentHash, description, dependencies);
    }

    /// @dev Updates the agent hash.
    /// @param agentId Agent Id.
    /// @param agentHash New IPFS hash of the agent.
    function updateAgentHash(uint256 agentId, bytes32 agentHash) external {
        return IRegistry(agentRegistry).updateHash(msg.sender, agentId, agentHash);
    }

    /// @dev Creates component.
    /// @param componentOwner Owner of the component.
    /// @param developer Developer of the component.
    /// @param componentHash IPFS hash of the component.
    /// @param description Description of the component.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a created component.
    function createComponent(
        address componentOwner,
        address developer,
        bytes32 componentHash,
        bytes32 description,
        uint32[] memory dependencies
    ) external returns (uint256)
    {
        // Check if the creation is paused
        if (paused) {
            revert Paused();
        }
        return IRegistry(componentRegistry).create(componentOwner, developer, componentHash, description, dependencies);
    }

    /// @dev Updates the component hash.
    /// @param componentId Token Id.
    /// @param componentHash New IPFS hash of the component.
    function updateComponentHash(uint256 componentId, bytes32 componentHash) external {
        return IRegistry(componentRegistry).updateHash(msg.sender, componentId, componentHash);
    }
}



