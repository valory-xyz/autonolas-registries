// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./AgentRegistry.sol";
import "../interfaces/IErrors.sol";
import "../interfaces/IMultisig.sol";
import "../interfaces/IRegistry.sol";

/// @title Service Registry - Smart contract for registering services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceRegistry is IErrors, IStructs, Ownable, ERC721Enumerable, ReentrancyGuard {
    event Deposit(address sender, uint256 amount);
    event Refund(address sendee, uint256 amount);
    event ServiceRegistryManagerUpdated(address manager);
    event CreateService(address owner, string name, uint256 threshold, uint256 serviceId);
    event UpdateService(address owner, string name, uint256 threshold, uint256 serviceId);
    event RegisterInstance(address operator, uint256 serviceId, address agent, uint256 agentId);
    event CreateMultisigWithAgents(uint256 serviceId, address multisig, address[] agentInstances, uint256 threshold);
    event ActivateRegistration(address owner, uint256 serviceId);
    event DestroyService(address owner, uint256 serviceId);
    event TerminateService(address owner, uint256 serviceId);
    event OperatorSlashed(uint256 amount, address operator, uint256 serviceId);
    event OperatorUnbond(address operator, uint256 serviceId);
    event DeployService(address owner, uint256 serviceId);

    enum ServiceState {
        NonExistent,
        PreRegistration,
        ActiveRegistration,
        FinishedRegistration,
        Deployed,
        TerminatedBonded,
        TerminatedUnbonded
    }

    struct AgentInstance {
        // Address of an agent instance
        address instance;
        // Canonical agent Id
        uint256 id;
    }

    // Service parameters
    struct Service {
        // Registration activation deposit
        uint256 securityDeposit;
        address proxyContract;
        // Multisig address for agent instances
        address multisig;
        // Service name
        string name;
        // Service description
        string description;
        // IPFS hashes pointing to the config metadata
        Multihash[] configHashes;
        // Agent instance signers threshold: must no less than ceil((n * 2 + 1) / 3) of all the agent instances combined
        uint256 threshold;
        // Total number of agent instances
        uint256 maxNumAgentInstances;
        // Actual number of agent instances
        uint256 numAgentInstances;
        // Canonical agent Ids for the service
        uint256[] agentIds;
        // Canonical agent Id => number of agent instances and correspondent instance registration bond
        mapping(uint256 => AgentParams) mapAgentParams;
        // Actual agent instance addresses. Canonical agent Id => Set of agent instance addresses.
        mapping(uint256 => address[]) mapAgentInstances;
        // Operator address => set of registered agent instance addresses
        mapping(address => AgentInstance[]) mapOperatorsAgentInstances;
        // Map of operator address => agent instance bonding / escrow balance
        // TODO Consider merging with another operator-related data structure
        mapping(address => uint256) mapOperatorsBalances;
        // Config hash per agent
//        mapping(uint256 => Multihash) mapAgentHash;
        // Service state
        ServiceState state;
    }

    // Agent Registry
    address public immutable agentRegistry;
    // Service counter
    uint256 private _serviceIds;
    // The amount of funds slashed
    uint256 public slashedFunds;
    // Service Manager
    address private _manager;
    // Map of service counter => service
    mapping (uint256 => Service) private _mapServices;
    // Map of agent instance address => service id it is registered with and operator address that supplied the instance
    mapping (address => address) private _mapAgentInstanceOperators;
    // Map of service Id => set of unique component Ids
    // Updated during the service deployment via deploy() function
    mapping (uint256 => uint256[]) private _mapServiceIdSetComponents;
    // Map of service Id => set of unique agent Ids
    mapping (uint256 => uint256[]) private _mapServiceIdSetAgents;
    // Map of policy for multisig implementations
    mapping (address => bool) public mapMultisigs;

    constructor(string memory _name, string memory _symbol, address _agentRegistry) ERC721(_name, _symbol)
    {
        agentRegistry = _agentRegistry;
    }

    // Only the manager has a privilege to manipulate a service
    modifier onlyManager {
        if (_manager != msg.sender) {
            revert ManagerOnly(msg.sender, _manager);
        }
        _;
    }

    // Only the owner of the service is authorized to manipulate it
    modifier onlyServiceOwner(address owner, uint256 serviceId) {
        if (owner == address(0) || !_exists(serviceId) || ownerOf(serviceId) != owner) {
            revert ServiceNotFound(serviceId);
        }
        _;
    }

    // Check for the service existence
    modifier serviceExists(uint256 serviceId) {
        if (!_exists(serviceId)) {
            revert ServiceDoesNotExist(serviceId);
        }
        _;
    }

    /// @dev Fallback function
    fallback() external payable {
        revert WrongFunction();
    }

    /// @dev Receive function
    receive() external payable {
        revert WrongFunction();
    }

    /// @dev Changes the service manager.
    /// @param newManager Address of a new service manager.
    function changeManager(address newManager) public onlyOwner {
        _manager = newManager;
        emit ServiceRegistryManagerUpdated(_manager);
    }

    /// @dev Going through basic initial service checks.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    function _initialChecks(
        string memory name,
        string memory description,
        Multihash memory configHash,
        uint256[] memory agentIds,
        AgentParams[] memory agentParams
    ) private view
    {
        // Checks for non-empty strings
        if(bytes(name).length == 0 || bytes(description).length == 0) {
            revert EmptyString();
        }

        // Check for the hash format
        if (configHash.hashFunction != 0x12 || configHash.size != 0x20) {
            revert WrongHash(configHash.hashFunction, 0x12, configHash.size, 0x20);
        }

        // Checking for non-empty arrays and correct number of values in them
        if (agentIds.length == 0 || agentIds.length != agentParams.length) {
            revert WrongArrayLength(agentIds.length, agentParams.length);
        }

        // Check for canonical agent Ids existence and for duplicate Ids
        uint256 lastId = 0;
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentIds[i] <= lastId || !IRegistry(agentRegistry).exists(agentIds[i])) {
                revert WrongAgentId(agentIds[i]);
            }
            lastId = agentIds[i];
        }
    }

    /// @dev Sets the service data.
    /// @param service A service instance to fill the data for.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param size Size of a canonical agent ids set.
    function _setServiceData(
        Service storage service,
        string memory name,
        string memory description,
        uint256 threshold,
        uint256[] memory agentIds,
        AgentParams[] memory agentParams,
        uint size
    ) private
    {
        // Updating high-level data components of the service
        service.name = name;
        service.description = description;
        service.threshold = threshold;
        service.maxNumAgentInstances = 0;

        uint256 securityDeposit;

        // Add canonical agent Ids for the service and the slots map
        for (uint256 i = 0; i < size; i++) {
            service.agentIds.push(agentIds[i]);
            service.mapAgentParams[agentIds[i]] = agentParams[i];
            service.maxNumAgentInstances += agentParams[i].slots;
            // Security deposit is the maximum of the canonical agent registration bond
            if (agentParams[i].bond > securityDeposit) {
                securityDeposit = agentParams[i].bond;
            }
        }
        service.securityDeposit = securityDeposit;

        // Check for the correct threshold: no less than ceil((n * 2 + 1) / 3) of all the agent instances combined
        uint256 checkThreshold = service.maxNumAgentInstances * 2 + 1;
        if (checkThreshold % 3 == 0) {
            checkThreshold = checkThreshold / 3;
        } else {
            checkThreshold = checkThreshold / 3 + 1;
        }
        if(service.threshold < checkThreshold || service.threshold > service.maxNumAgentInstances) {
            revert WrongThreshold(service.threshold, checkThreshold, service.maxNumAgentInstances);
        }
    }

    /// @dev Creates a new service.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function createService(
        address owner,
        string memory name,
        string memory description,
        Multihash memory configHash,
        uint256[] memory agentIds,
        AgentParams[] memory agentParams,
        uint256 threshold
    ) external onlyManager returns (uint256 serviceId)
    {
        // Check for the non-empty owner address
        if (owner == address(0)) {
            revert ZeroAddress();
        }

        // Execute initial checks
        _initialChecks(name, description, configHash, agentIds, agentParams);

        // Check that there are no zero number of slots for a specific canonical agent id and no zero registration bond
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentParams[i].slots == 0 || agentParams[i].bond == 0) {
                revert ZeroValue();
            }
        }

        // Create a new service Id
        _serviceIds++;
        serviceId = _serviceIds;

        // Set high-level data components of the service instance
        Service storage service = _mapServices[serviceId];
        // Fist hash is always pushed, since the updated one has to be checked additionally
        service.configHashes.push(configHash);

        // Set service data
        _setServiceData(service, name, description, threshold, agentIds, agentParams, agentIds.length);

        // Mint the service instance to the owner
        _safeMint(owner, serviceId);

        service.state = ServiceState.PreRegistration;

        emit CreateService(owner, name, threshold, serviceId);
    }

    /// @dev Updates a service in a CRUD way.
    /// @param owner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    function update(
        address owner,
        string memory name,
        string memory description,
        Multihash memory configHash,
        uint256[] memory agentIds,
        AgentParams[] memory agentParams,
        uint256 threshold,
        uint256 serviceId
    ) external onlyManager onlyServiceOwner(owner, serviceId) returns (bool success)
    {
        Service storage service = _mapServices[serviceId];
        if (service.state != ServiceState.PreRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Execute initial checks
        _initialChecks(name, description, configHash, agentIds, agentParams);

        // Collect non-zero canonical agent ids and slots / costs, remove any canonical agent Ids from the params map
        uint256[] memory newAgentIds = new uint256[](agentIds.length);
        AgentParams[] memory newAgentParams = new AgentParams[](agentIds.length);
        uint256 size;
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentParams[i].slots == 0) {
                delete service.mapAgentParams[agentIds[i]];
            } else {
                newAgentIds[size] = agentIds[i];
                newAgentParams[size] = agentParams[i];
                size++;
            }
        }
        // Set of canonical agent Ids has to be completely overwritten (push-based)
        delete service.agentIds;
        // Check if the previous hash is the same / hash was not updated
        if (service.configHashes[service.configHashes.length - 1].hash != configHash.hash) {
            service.configHashes.push(configHash);
        }

        // Set service data
        _setServiceData(service, name, description, threshold, newAgentIds, newAgentParams, size);

        emit UpdateService(owner, name, threshold, serviceId);
        success = true;
    }

    /// @dev Activates the service.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function activateRegistration(address owner, uint256 serviceId)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
        nonReentrant
        payable
        returns (bool success)
    {
        Service storage service = _mapServices[serviceId];
        // Service must be inactive
        if (service.state != ServiceState.PreRegistration) {
            revert ServiceMustBeInactive(serviceId);
        }

        if (msg.value != service.securityDeposit) {
            revert IncorrectRegistrationDepositValue(msg.value, service.securityDeposit, serviceId);
        }

        // Activate the agent instance registration
        service.state = ServiceState.ActiveRegistration;

        emit ActivateRegistration(owner, serviceId);
        success = true;
    }

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
    ) external onlyManager nonReentrant payable returns (bool success)
    {
        // Check if the length of canonical agent instance addresses array and ids array have the same length
        if (agentInstances.length != agentIds.length) {
            revert WrongArrayLength(agentInstances.length, agentIds.length);
        }

        Service storage service = _mapServices[serviceId];
        // The service has to be active to register agents
        if (service.state != ServiceState.ActiveRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Check for the sufficient amount of bond fee is provided
        uint256 numAgents = agentInstances.length;
        uint256 totalBond = 0;
        for (uint256 i = 0; i < numAgents; ++i) {
            // Check if canonical agent Id exists in the service
            uint256 agentId = agentIds[i];
            if (service.mapAgentParams[agentId].slots == 0) {
                revert AgentNotInService(agentId, serviceId);
            }
            totalBond += service.mapAgentParams[agentId].bond;
        }
        if (msg.value != totalBond) {
            revert IncorrectAgentBondingValue(msg.value, totalBond, serviceId);
        }

        for (uint256 i = 0; i < numAgents; ++i) {
            address agentInstance = agentInstances[i];
            uint256 agentId = agentIds[i];

            // Operator address must be different from agent instance one
            // Also, operator address must not be used as an agent instance anywhere else
            // TODO Need to check for the agent address to be EOA
            if (operator == agentInstance || _mapAgentInstanceOperators[operator] != address(0)) {
                revert WrongOperator(serviceId);
            }

            // Check if the agent instance is already engaged with another service
            if (_mapAgentInstanceOperators[agentInstance] != address(0)) {
                revert AgentInstanceRegistered(_mapAgentInstanceOperators[agentInstance]);
            }

            // Check if there is an empty slot for the agent instance in this specific service
            if (service.mapAgentInstances[agentId].length == service.mapAgentParams[agentId].slots) {
                revert AgentInstancesSlotsFilled(serviceId);
            }

            // Add agent instance and operator and set the instance engagement
            service.mapAgentInstances[agentId].push(agentInstance);
            service.mapOperatorsAgentInstances[operator].push(AgentInstance(agentInstance, agentId));
            service.numAgentInstances++;
            _mapAgentInstanceOperators[agentInstance] = operator;

            emit RegisterInstance(operator, serviceId, agentInstance, agentId);
        }

        // If the service agent instance capacity is reached, the service becomes finished-registration
        if (service.numAgentInstances == service.maxNumAgentInstances) {
            service.state = ServiceState.FinishedRegistration;
        }

        // Update operator's bonding balance
        service.mapOperatorsBalances[operator] += msg.value;

        emit Deposit(operator, msg.value);
        success = true;
    }

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
    ) external onlyManager onlyServiceOwner(owner, serviceId) returns (address multisig)
    {
        // Check for the whitelisted multisig implementation
        if (!mapMultisigs[multisigImplementation]) {
            revert UnauthorizedMultisig(multisigImplementation);
        }

        Service storage service = _mapServices[serviceId];
        if (service.state != ServiceState.FinishedRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Get all agent instances for the multisig
        address[] memory agentInstances = _getAgentInstances(service);

        // Create a multisig with agent instances
        multisig = IMultisig(multisigImplementation).create(agentInstances, service.threshold, data);

        emit CreateMultisigWithAgents(serviceId, multisig, agentInstances, service.threshold);

        // Update maps of service Id to component and agent Ids
        _updateServiceComponentAgentConnection(serviceId);

        service.multisig = multisig;
        service.state = ServiceState.Deployed;

        emit DeployService(owner, serviceId);
    }

    /// @dev Slashes a specified agent instance.
    /// @param agentInstances Agent instances to slash.
    /// @param amounts Correspondent amounts to slash.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    function slash(address[] memory agentInstances, uint256[] memory amounts, uint256 serviceId) public
        serviceExists(serviceId) returns (bool success)
    {
        // Check for the array size
        if (agentInstances.length != amounts.length) {
            revert WrongArrayLength(agentInstances.length, amounts.length);
        }

        Service storage service = _mapServices[serviceId];
        // Only the multisig of a correspondent address can slash its agent instances
        if (msg.sender != service.multisig) {
            revert OnlyOwnServiceMultisig(msg.sender, service.multisig, serviceId);
        }

        // Loop over each agent instance
        uint256 numInstancesToSlash = agentInstances.length;
        for (uint256 i = 0; i < numInstancesToSlash; ++i) {
            // Get the service Id from the agentInstance map
            address operator = _mapAgentInstanceOperators[agentInstances[i]];

            // Slash the balance of the operator, make sure it does not go below zero
            uint256 balance = service.mapOperatorsBalances[operator];
            if (amounts[i] >= balance) {
                // We can't add to the slashed amount more than the balance
                slashedFunds += balance;
                balance = 0;
            } else {
                slashedFunds += amounts[i];
                balance -= amounts[i];
            }
            service.mapOperatorsBalances[operator] = balance;

            emit OperatorSlashed(amounts[i], operator, serviceId);
        }

        success = true;
    }

    /// @dev Terminates the service.
    /// @param owner Owner of the service.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    /// @return refund Refund to return to the owner.
    function terminate(address owner, uint256 serviceId)
        external
        onlyManager
        onlyServiceOwner(owner, serviceId)
        nonReentrant
        returns (bool success, uint256 refund)
    {
        Service storage service = _mapServices[serviceId];
        // Check if the service is already terminated
        if (service.state == ServiceState.PreRegistration || service.state == ServiceState.TerminatedBonded ||
            service.state == ServiceState.TerminatedUnbonded) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }
        // Define the state of the service depending on the number of bonded agent instances
        if (service.numAgentInstances > 0) {
            service.state = ServiceState.TerminatedBonded;
        } else {
            service.state = ServiceState.TerminatedUnbonded;
        }

        // Return registration deposit back to the owner
        refund = service.securityDeposit;
        // By design, the refund is always a non-zero value, so no check is needed here fo that
        (bool result, ) = owner.call{value: refund}("");
        if (!result) {
            // TODO When ERC20 token is used, change to the address of a token
            revert TransferFailed(address(0), address(this), owner, refund);
        }

        emit Refund(owner, refund);
        emit TerminateService(owner, serviceId);
        success = true;
    }

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param operator Operator of agent instances.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function unbond(address operator, uint256 serviceId) external onlyManager nonReentrant
        returns (bool success, uint256 refund)
    {
        Service storage service = _mapServices[serviceId];
        // Service can only be in the terminated-bonded state or expired-registration in order to proceed
        if (service.state != ServiceState.TerminatedBonded) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Check for the operator and unbond all its agent instances
        AgentInstance[] memory agentInstances = service.mapOperatorsAgentInstances[operator];
        uint256 numAgentsUnbond = agentInstances.length;
        if (numAgentsUnbond == 0) {
            revert OperatorHasNoInstances(operator, serviceId);
        }

        // Subtract number of unbonded agent instances
        service.numAgentInstances -= numAgentsUnbond;
        if (service.numAgentInstances == 0) {
            service.state = ServiceState.TerminatedUnbonded;
        }

        // Calculate registration refund and free all agent instances
        refund = 0;
        for (uint256 i = 0; i < numAgentsUnbond; i++) {
            refund += service.mapAgentParams[agentInstances[i].id].bond;
            // Since the service is done, there's no need to clean-up the service-related data, just the state variables
            delete _mapAgentInstanceOperators[agentInstances[i].instance];
        }

        // Calculate the refund
        uint256 balance = service.mapOperatorsBalances[operator];
        // This situation is possible if the operator was slashed for the agent instance misbehavior
        if (refund > balance) {
            refund = balance;
        }

        // Refund the operator
        if (refund > 0) {
            // Operator's balance is essentially zero after the refund
            service.mapOperatorsBalances[operator] = 0;
            // Send the refund
            (bool result, ) = operator.call{value: refund}("");
            if (!result) {
                // TODO When ERC20 token is used, change to the address of a token
                revert TransferFailed(address(0), address(this), operator, refund);
            }
        }

        emit Refund(operator, refund);
        emit OperatorUnbond(operator, serviceId);
        success = true;
    }

    /// @dev Destroys the service instance.
    /// @param owner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function destroy(address owner, uint256 serviceId) external onlyManager onlyServiceOwner(owner, serviceId)
        returns (bool success)
    {
        Service storage service = _mapServices[serviceId];
        if (service.state != ServiceState.TerminatedUnbonded && service.state != ServiceState.PreRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        _burn(serviceId);

        emit DestroyService(owner, serviceId);
        success = true;
    }

    /// @dev Gets all agent instances
    /// @param agentInstances Pre-allocated list of agent instance addresses.
    /// @param service Service instance.
    function _getAgentInstances(Service storage service) private view
        returns (address[] memory agentInstances)
    {
        agentInstances = new address[](service.numAgentInstances);
        uint256 count;
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            uint256 agentId = service.agentIds[i];
            for (uint256 j = 0; j < service.mapAgentInstances[agentId].length; j++) {
                agentInstances[count] = service.mapAgentInstances[agentId][j];
                count++;
            }
        }
    }

    /// @dev Update the map of service Id => set of components / canonical agent Ids.
    /// @param serviceId Service Id.
    function _updateServiceComponentAgentConnection(uint256 serviceId) private {
        Service storage service = _mapServices[serviceId];
        // Set of canonical agent Ids is straightforward
        _mapServiceIdSetAgents[serviceId] = service.agentIds;

        uint256[] memory agents = service.agentIds;
        uint256 numAgents = agents.length;
        // Array of numbers of components per each agent Id
        uint256[] memory numComponents = new uint256[](numAgents);
        // 2D array of all the sets of components per each agent Id
        uint256[][] memory components = new uint256[][](numAgents);

        // Get total possible number of components and lists of components
        uint maxNumComponents;
        for (uint256 i = 0; i < numAgents; ++i) {
            (numComponents[i], components[i]) = IRegistry(agentRegistry).getDependencies(agents[i]);
            maxNumComponents += numComponents[i];
        }

        // Lists of components are sorted, take unique values in ascending order
        uint256[] memory allComponents = new uint256[](maxNumComponents);
        // Processed component counter
        uint256[] memory processedComponents = new uint256[](numAgents);
        // Minimal component Id
        uint256 minComponent;
        // Overall component counter
        uint256 counter;
        // Iterate until we process all components, at the maximum of the sum of all the components in all agents
        for (counter = 0; counter < maxNumComponents; ++counter) {
            // Index of a minimal component
            uint256 minIdxComponent;
            // Amount of components identified as the next minimal component number
            uint256 numComponentsCheck;
            uint256 tryMinComponent = type(uint256).max;
            // Assemble an array of all first components from each component array
            for (uint256 i = 0; i < numAgents; ++i) {
                // Either get a component that has a higher id than the last one ore reach the end of the processed Ids
                for (; processedComponents[i] < numComponents[i]; ++processedComponents[i]) {
                    if (minComponent < components[i][processedComponents[i]]) {
                        // Out of those component Ids that are higher than the last one, pich the minimal
                        if (components[i][processedComponents[i]] < tryMinComponent) {
                            tryMinComponent = components[i][processedComponents[i]];
                            minIdxComponent = i;
                        }
                        numComponentsCheck++;
                        break;
                    }
                }
            }
            minComponent = tryMinComponent;

            // If minimal component Id is greater than the last one, it should be added, otherwise we reached the end
            if (numComponentsCheck > 0) {
                allComponents[counter] = minComponent;
                processedComponents[minIdxComponent]++;
            } else {
                break;
            }
        }

        uint256[] memory componentIds = new uint256[](counter);
        for (uint256 i = 0; i < counter; ++i) {
            componentIds[i] = allComponents[i];
        }
        _mapServiceIdSetComponents[serviceId] = componentIds;
    }


    /// @dev Checks if the service Id exists.
    /// @param serviceId Service Id.
    /// @return true if the service exists, false otherwise.
    function exists(uint256 serviceId) public view returns (bool) {
        return _exists(serviceId);
    }

    /// @dev Gets the high-level service information.
    /// @param serviceId Service Id.
    /// @return owner Address of the service owner.
    /// @return name Name of the service.
    /// @return description Description of the service.
    /// @return configHash The most recent IPFS hash pointing to the config metadata.
    /// @return threshold Agent instance signers threshold.
    /// @return numAgentIds Number of canonical agent Ids in the service.
    /// @return agentIds Set of service canonical agents.
    /// @return agentParams Set of numbers of agent instances for each canonical agent Id.
    /// @return numAgentInstances Number of registered agent instances.
    /// @return agentInstances Set of agent instances currently registered for the service.
    /// @return multisig Agent instances multisig address.
    function getServiceInfo(uint256 serviceId) public view serviceExists(serviceId)
        returns (address owner, string memory name, string memory description, Multihash memory configHash,
            uint256 threshold, uint256 numAgentIds, uint256[] memory agentIds, AgentParams[] memory agentParams,
            uint256 numAgentInstances, address[] memory agentInstances, address multisig)
    {
        Service storage service = _mapServices[serviceId];
        agentParams = new AgentParams[](service.agentIds.length);
        numAgentInstances = service.numAgentInstances;
        agentInstances = _getAgentInstances(service);
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            agentParams[i] = service.mapAgentParams[service.agentIds[i]];
        }
        owner = ownerOf(serviceId);
        name = service.name;
        description = service.description;
        uint256 configHashesSize = service.configHashes.length - 1;
        configHash = service.configHashes[configHashesSize];
        threshold = service.threshold;
        numAgentIds = service.agentIds.length;
        agentIds = service.agentIds;
        multisig = service.multisig;
    }

    /// @dev Lists all the instances of a given canonical agent Id if the service.
    /// @param serviceId Service Id.
    /// @param agentId Canonical agent Id.
    /// @return numAgentInstances Number of agent instances.
    /// @return agentInstances Set of agent instances for a specified canonical agent Id.
    function getInstancesForAgentId(uint256 serviceId, uint256 agentId) public view serviceExists(serviceId)
        returns (uint256 numAgentInstances, address[] memory agentInstances)
    {
        Service storage service = _mapServices[serviceId];
        numAgentInstances = service.mapAgentInstances[agentId].length;
        agentInstances = new address[](numAgentInstances);
        for (uint256 i = 0; i < numAgentInstances; i++) {
            agentInstances[i] = service.mapAgentInstances[agentId][i];
        }
    }

    /// @dev Gets service config hashes.
    /// @param serviceId Service Id.
    /// @return numHashes Number of hashes.
    /// @return configHashes The list of component hashes.
    function getConfigHashes(uint256 serviceId) public view serviceExists(serviceId)
        returns (uint256 numHashes, Multihash[] memory configHashes)
    {
        Service storage service = _mapServices[serviceId];
        return (service.configHashes.length, service.configHashes);
    }

    /// @dev Gets the set of canonical agent Ids that contain specified service Id.
    /// @param serviceId Service Id.
    /// @return numAgentIds Number of agent Ids.
    /// @return agentIds Set of agent Ids.
    function getAgentIdsOfServiceId(uint256 serviceId) external view
        returns (uint256 numAgentIds, uint256[] memory agentIds)
    {
        agentIds = _mapServiceIdSetAgents[serviceId];
        numAgentIds = agentIds.length;
    }

    /// @dev Gets the set of component Ids that contain specified service Id.
    /// @param serviceId Service Id.
    /// @return numComponentIds Number of component Ids.
    /// @return componentIds Set of component Ids.
    function getComponentIdsOfServiceId(uint256 serviceId) external view
        returns (uint256 numComponentIds, uint256[] memory componentIds)
    {
        componentIds = _mapServiceIdSetComponents[serviceId];
        numComponentIds = componentIds.length;
    }

    /// @dev Gets the service state.
    /// @param serviceId Service Id.
    /// @return state State of the service.
    function getServiceState(uint256 serviceId) public view returns (ServiceState state) {
        state = _mapServices[serviceId].state;
    }

    /// @dev Gets the operator's balance in a specific service.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @return balance The balance of the operator.
    function getOperatorBalance(address operator, uint256 serviceId) public view serviceExists(serviceId)
        returns (uint256 balance)
    {
        balance = _mapServices[serviceId].mapOperatorsBalances[operator];
    }

    /// @dev Controls multisig implementation address permission.
    /// @param multisig Address of a multisig implementation.
    /// @param permission Grant or revoke permission.
    /// @return success True, if function executed successfully.
    function changeMultisigPermission(address multisig, bool permission) public onlyOwner returns (bool success) {
        if (multisig == address(0)) {
            revert ZeroAddress();
        }
        mapMultisigs[multisig] = permission;
        success = true;
    }
}
