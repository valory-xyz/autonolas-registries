// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./AgentRegistry.sol";
import "./interfaces/IMultisig.sol";
import "./interfaces/IRegistry.sol";
import "hardhat/console.sol";

// This struct is 128 bits in total
struct AgentParams {
    // Number of agent instances. This number is limited by the number of agent instances
    uint32 slots;
    // Bond per agent instance. This is enough for 1b+ ETH or 1e27
    uint96 bond;
}

// This struct is 192 bits in total
struct AgentInstance {
    // Address of an agent instance
    address instance;
    // Canonical agent Id. This number is limited by the max number of agent Ids (see UnitRegistry contract)
    uint32 agentId;
}

/// @title Service Registry - Smart contract for registering services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceRegistry is GenericRegistry {
    event Deposit(address sender, uint256 amount);
    event Refund(address sendee, uint256 amount);
    event CreateService(uint256 serviceId);
    event UpdateService(uint256 serviceId);
    event RegisterInstance(address operator, uint256 serviceId, address agent, uint256 agentId);
    event CreateMultisigWithAgents(uint256 serviceId, address multisig);
    event ActivateRegistration(uint256 serviceId);
    event TerminateService(uint256 serviceId);
    event OperatorSlashed(uint256 amount, address operator, uint256 serviceId);
    event OperatorUnbond(address operator, uint256 serviceId);
    event DeployService(uint256 serviceId);

    enum ServiceState {
        NonExistent,
        PreRegistration,
        ActiveRegistration,
        FinishedRegistration,
        Deployed,
        TerminatedBonded,
        TerminatedUnbonded
    }

    // TODO After all maps are extracted from the struct, this can be treated as memory
    // Service parameters
    struct Service {
        // Registration activation deposit
        // This is enough for 1b+ ETH or 1e27
        uint96 securityDeposit;
        // Multisig address for agent instances
        address multisig;
        // Service name
        bytes32 name;
        // Service description
        bytes32 description;
        // IPFS hashes pointing to the config metadata
        // TODO Do we need to check for already added config hashes same as in components and agents?
        bytes32 configHash;
        // Agent instance signers threshold: must no less than ceil((n * 2 + 1) / 3) of all the agent instances combined
        // This number will be enough to have ((2^32 - 1) * 3 - 1) / 2, which is bigger than 6.44b
        uint32 threshold;
        // Total number of agent instances. We believe that the number of instances is bounded by 2^32 - 1
        uint32 maxNumAgentInstances;
        // Actual number of agent instances. This number is less or equal to maxNumAgentInstances
        uint32 numAgentInstances;
        // Service state
        ServiceState state;
        // Canonical agent Ids for the service. Individual agent Id is bounded by the max number of agent Id
        uint32[] agentIds;
    }

    // Agent Registry
    address public immutable agentRegistry;
    // The amount of funds slashed. This is enough for 1b+ ETH or 1e27
    uint96 public slashedFunds;
    // Map of service Id => set of IPFS hashes pointing to the config metadata
    mapping (uint256 => bytes32[]) public mapConfigHashes;
    // Map of operator address and serviceId => set of registered agent instance addresses
    // TODO If time permits, consider having those not in the map, but in a service array with offsets of the number of agent instances per each agent Id
    mapping(uint256 => AgentInstance[]) public mapOperatorsAgentInstances;
    // Service Id and canonical agent Id => number of agent instances and correspondent instance registration bond
    // TODO consider having those not in the map, but in a service array with offsets of the number of agent instances per each agent Id
    mapping(uint256 => AgentParams) public mapAgentParams;
    // Actual agent instance addresses. Service Id and canonical agent Id => Set of agent instance addresses.
    mapping(uint256 => address[]) public mapAgentInstances;
    // Map of operator address and serviceId => agent instance bonding / escrow balance
    mapping(uint256 => uint96) public mapOperatorsBalances;
    // Map of agent instance address => service id it is registered with and operator address that supplied the instance
    mapping (address => address) public mapAgentInstanceOperators;
    // Map of service Id => set of unique component Ids
    // Updated during the service deployment via deploy() function
    mapping (uint256 => uint32[]) public mapServiceIdSetComponents;
    // Map of service Id => set of unique agent Ids
    mapping (uint256 => uint32[]) public mapServiceIdSetAgents;
    // Map of service counter => service
    mapping (uint256 => Service) public mapServices;
    // Map of policy for multisig implementations
    mapping (address => bool) public mapMultisigs;

    /// @dev Service registry constructor.
    /// @param _name Service contract name.
    /// @param _symbol Agent contract symbol.
    /// @param _agentRegistry Agent registry address.
    constructor(string memory _name, string memory _symbol, address _agentRegistry) ERC721(_name, _symbol)
    {
        agentRegistry = _agentRegistry;
        owner = msg.sender;
    }

    // Only the owner of the service is authorized to manipulate it
    modifier onlyServiceOwner(address serviceOwner, uint256 serviceId) {
        if (serviceOwner == address(0) || serviceId == 0 || serviceId > totalSupply || ownerOf(serviceId) != serviceOwner) {
            revert ServiceNotFound(serviceId);
        }
        _;
    }

    // Check for the service existence
    modifier serviceExists(uint256 serviceId) {
        if (serviceId == 0 || serviceId > totalSupply) {
            revert ServiceNotFound(serviceId);
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

    /// @dev Going through basic initial service checks.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    function _initialChecks(
        bytes32 name,
        bytes32 description,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams
    ) private view
    {
        // Checks for non-empty strings
        if(name == 0 || description == 0) {
            revert ZeroValue();
        }

        // Check for the hash value
        if (configHash == "0x") {
            revert ZeroValue();
        }

        // Checking for non-empty arrays and correct number of values in them
        if (agentIds.length == 0 || agentIds.length != agentParams.length) {
            revert WrongArrayLength(agentIds.length, agentParams.length);
        }

        // Check for canonical agent Ids existence and for duplicate Ids
        uint256 agentTotalSupply = IRegistry(agentRegistry).totalSupply();
        uint256 lastId;
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentIds[i] < (lastId + 1) || agentIds[i] > agentTotalSupply) {
                revert WrongAgentId(agentIds[i]);
            }
            lastId = agentIds[i];
        }
    }

    /// @dev Sets the service data.
    /// @param service A service instance to fill the data for.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param size Size of a canonical agent ids set.
    /// @param serviceId ServiceId.
    function _setServiceData(
        Service storage service,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint256 size,
        uint256 serviceId
    ) private
    {
        uint96 securityDeposit;

        // Add canonical agent Ids for the service and the slots map
        for (uint256 i = 0; i < size; i++) {
            service.agentIds.push(agentIds[i]);
            // Push a pair of key defining variables into one key
            uint256 serviceAgent;
            // Service Id. If one service is created every second, it will take 136 years to get to the 2^32 - 1 number limit
            // TODO Need to carefully check pairings, since it's hard to find if something is incorrectly misplaced bitwise
            serviceAgent |= serviceId << 32;
            serviceAgent |= uint256(agentIds[i]) << 64;
            console.log("creating serviceAgent", serviceAgent);
            mapAgentParams[serviceAgent] = agentParams[i];
            service.maxNumAgentInstances += agentParams[i].slots;
            // Security deposit is the maximum of the canonical agent registration bond
            if (agentParams[i].bond > securityDeposit) {
                securityDeposit = agentParams[i].bond;
            }
        }
        service.securityDeposit = securityDeposit;

        // Check for the correct threshold: no less than ceil((n * 2 + 1) / 3) of all the agent instances combined
        uint256 checkThreshold = uint256(service.maxNumAgentInstances * 2 + 1);
        if (checkThreshold % 3 == 0) {
            checkThreshold = checkThreshold / 3;
        } else {
            checkThreshold = checkThreshold / 3 + 1;
        }
        if (service.threshold < checkThreshold || service.threshold > service.maxNumAgentInstances) {
            revert WrongThreshold(service.threshold, checkThreshold, service.maxNumAgentInstances);
        }
    }

    /// @dev Creates a new service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function create(
        address serviceOwner,
        bytes32 name,
        bytes32 description,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint32 threshold
    ) external returns (uint256 serviceId)
    {
        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Check for the non-empty service owner address
        if (serviceOwner == address(0)) {
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
        serviceId = totalSupply;
        serviceId++;

        // Set high-level data components of the service instance
        Service storage service = mapServices[serviceId];
        // Updating high-level data components of the service
        service.name = name;
        service.description = description;
        service.threshold = threshold;
        service.maxNumAgentInstances = 0;
        // Assigning the initial hash
        service.configHash = configHash;

        // Set service data
        _setServiceData(service, agentIds, agentParams, agentIds.length, serviceId);

        // Mint the service instance to the service owner
        _safeMint(serviceOwner, serviceId);

        service.state = ServiceState.PreRegistration;

        totalSupply = serviceId;
        emit CreateService(serviceId);
    }

    /// @dev Updates a service in a CRUD way.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param name Name of the service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    function update(
        address serviceOwner,
        bytes32 name,
        bytes32 description,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint32 threshold,
        uint256 serviceId
    ) external onlyServiceOwner(serviceOwner, serviceId) returns (bool success)
    {
        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        Service storage service = mapServices[serviceId];
        if (service.state != ServiceState.PreRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Execute initial checks
        _initialChecks(name, description, configHash, agentIds, agentParams);

        // Updating high-level data components of the service
        service.name = name;
        service.description = description;
        service.threshold = threshold;
        service.maxNumAgentInstances = 0;

        // Collect non-zero canonical agent ids and slots / costs, remove any canonical agent Ids from the params map
        uint32[] memory newAgentIds = new uint32[](agentIds.length);
        AgentParams[] memory newAgentParams = new AgentParams[](agentIds.length);
        uint256 size;
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentParams[i].slots == 0) {
                uint256 serviceAgent;
                serviceAgent |= serviceId << 32;
                serviceAgent |= uint256(agentIds[i]) << 64;
                delete mapAgentParams[serviceAgent];
            } else {
                newAgentIds[size] = agentIds[i];
                newAgentParams[size] = agentParams[i];
                size++;
            }
        }
        // Set of canonical agent Ids has to be completely overwritten (push-based)
        delete service.agentIds;
        // Check if the previous hash is the same / hash was not updated
        bytes32 lastConfigHash = service.configHash;
        if (lastConfigHash != configHash) {
            mapConfigHashes[serviceId].push(lastConfigHash);
            service.configHash = configHash;
        }

        // Set service data
        _setServiceData(service, newAgentIds, newAgentParams, size, serviceId);

        emit UpdateService(serviceId);
        success = true;
    }

    /// @dev Activates the service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function activateRegistration(address serviceOwner, uint256 serviceId)
        external
        onlyServiceOwner(serviceOwner, serviceId)
        payable
        returns (bool success)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        Service storage service = mapServices[serviceId];
        // Service must be inactive
        if (service.state != ServiceState.PreRegistration) {
            revert ServiceMustBeInactive(serviceId);
        }

        if (msg.value != service.securityDeposit) {
            revert IncorrectRegistrationDepositValue(msg.value, service.securityDeposit, serviceId);
        }

        // Activate the agent instance registration
        service.state = ServiceState.ActiveRegistration;

        emit ActivateRegistration(serviceId);
        success = true;

        _locked = 1;
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
        uint32[] memory agentIds
    ) external payable returns (bool success)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Check if the length of canonical agent instance addresses array and ids array have the same length
        if (agentInstances.length != agentIds.length) {
            revert WrongArrayLength(agentInstances.length, agentIds.length);
        }

        Service storage service = mapServices[serviceId];
        // The service has to be active to register agents
        if (service.state != ServiceState.ActiveRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Check for the sufficient amount of bond fee is provided
        uint256 numAgents = agentInstances.length;
        uint256 totalBond = 0;
        for (uint256 i = 0; i < numAgents; ++i) {
            // Check if canonical agent Id exists in the service
            uint256 serviceAgent;
            serviceAgent |= serviceId << 32;
            serviceAgent |= uint256(agentIds[i]) << 64;
            // TODO We read each value from the map, this is expensive
            console.log("serviceAgent", serviceAgent);
            console.log("agentIds[i]", agentIds[i]);
            console.log(mapAgentParams[serviceAgent].slots);
            if (mapAgentParams[serviceAgent].slots == 0) {
                revert AgentNotInService(agentIds[i], serviceId);
            }
            totalBond += mapAgentParams[serviceAgent].bond;
        }
        if (msg.value != totalBond) {
            revert IncorrectAgentBondingValue(msg.value, totalBond, serviceId);
        }

        uint256 operatorService;
        operatorService |= uint256(uint160(operator)) << 160;
        operatorService |= serviceId << 192;
        for (uint256 i = 0; i < numAgents; ++i) {
            address agentInstance = agentInstances[i];
            uint32 agentId = agentIds[i];

            // Operator address must be different from agent instance one
            // Also, operator address must not be used as an agent instance anywhere else
            // TODO Need to check for the agent address to be EOA
            if (operator == agentInstance || mapAgentInstanceOperators[operator] != address(0)) {
                revert WrongOperator(serviceId);
            }

            // Check if the agent instance is already engaged with another service
            if (mapAgentInstanceOperators[agentInstance] != address(0)) {
                revert AgentInstanceRegistered(mapAgentInstanceOperators[agentInstance]);
            }

            // Check if there is an empty slot for the agent instance in this specific service
            uint256 serviceAgent;
            serviceAgent |= serviceId << 32;
            serviceAgent |= uint256(agentIds[i]) << 64;
            if (mapAgentInstances[serviceAgent].length == mapAgentParams[serviceAgent].slots) {
                revert AgentInstancesSlotsFilled(serviceId);
            }

            // Add agent instance and operator and set the instance engagement
            mapAgentInstances[serviceAgent].push(agentInstance);
            mapOperatorsAgentInstances[operatorService].push(AgentInstance(agentInstance, agentId));
            service.numAgentInstances++;
            mapAgentInstanceOperators[agentInstance] = operator;

            emit RegisterInstance(operator, serviceId, agentInstance, agentId);
        }

        // If the service agent instance capacity is reached, the service becomes finished-registration
        if (service.numAgentInstances == service.maxNumAgentInstances) {
            service.state = ServiceState.FinishedRegistration;
        }

        // Update operator's bonding balance
        mapOperatorsBalances[operatorService] += uint96(msg.value);

        emit Deposit(operator, msg.value);
        success = true;

        _locked = 1;
    }

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
    ) external onlyServiceOwner(serviceOwner, serviceId) returns (address multisig)
    {
        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Check for the whitelisted multisig implementation
        if (!mapMultisigs[multisigImplementation]) {
            revert UnauthorizedMultisig(multisigImplementation);
        }

        Service storage service = mapServices[serviceId];
        if (service.state != ServiceState.FinishedRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Get all agent instances for the multisig
        address[] memory agentInstances = _getAgentInstances(service, serviceId);

        // Create a multisig with agent instances
        multisig = IMultisig(multisigImplementation).create(agentInstances, service.threshold, data);

        emit CreateMultisigWithAgents(serviceId, multisig);

        // Update maps of service Id to component and agent Ids
        _updateServiceComponentAgentConnection(serviceId);

        service.multisig = multisig;
        service.state = ServiceState.Deployed;

        emit DeployService(serviceId);
    }

    /// @dev Slashes a specified agent instance.
    /// @param agentInstances Agent instances to slash.
    /// @param amounts Correspondent amounts to slash.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    function slash(address[] memory agentInstances, uint96[] memory amounts, uint256 serviceId) external
        serviceExists(serviceId) returns (bool success)
    {
        // Check for the array size
        if (agentInstances.length != amounts.length) {
            revert WrongArrayLength(agentInstances.length, amounts.length);
        }

        Service storage service = mapServices[serviceId];
        // Only the multisig of a correspondent address can slash its agent instances
        if (msg.sender != service.multisig) {
            revert OnlyOwnServiceMultisig(msg.sender, service.multisig, serviceId);
        }

        // Loop over each agent instance
        uint256 numInstancesToSlash = agentInstances.length;
        for (uint256 i = 0; i < numInstancesToSlash; ++i) {
            // Get the service Id from the agentInstance map
            address operator = mapAgentInstanceOperators[agentInstances[i]];
            uint256 operatorService;
            operatorService |= uint256(uint160(operator)) << 160;
            operatorService |= serviceId << 192;

            // Slash the balance of the operator, make sure it does not go below zero
            uint96 balance = mapOperatorsBalances[operatorService];
            if (amounts[i] >= balance) {
                // We can't add to the slashed amount more than the balance
                slashedFunds += balance;
                balance = 0;
            } else {
                slashedFunds += amounts[i];
                balance -= amounts[i];
            }
            mapOperatorsBalances[operatorService] = balance;

            emit OperatorSlashed(amounts[i], operator, serviceId);
        }

        success = true;
    }

    /// @dev Terminates the service.
    /// @param serviceOwner Owner of the service.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    /// @return refund Refund to return to the service owner.
    function terminate(address serviceOwner, uint256 serviceId)
        external
        onlyServiceOwner(serviceOwner, serviceId)
        returns (bool success, uint256 refund)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        Service storage service = mapServices[serviceId];
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

        // Return registration deposit back to the service owner
        refund = service.securityDeposit;
        // By design, the refund is always a non-zero value, so no check is needed here fo that
        (bool result, ) = serviceOwner.call{value: refund}("");
        if (!result) {
            // TODO When ERC20 token is used, change to the address of a token
            revert TransferFailed(address(0), address(this), serviceOwner, refund);
        }

        emit Refund(serviceOwner, refund);
        emit TerminateService(serviceId);
        success = true;

        _locked = 1;
    }

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param operator Operator of agent instances.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function unbond(address operator, uint256 serviceId) external returns (bool success, uint256 refund) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        Service storage service = mapServices[serviceId];
        // Service can only be in the terminated-bonded state or expired-registration in order to proceed
        if (service.state != ServiceState.TerminatedBonded) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Check for the operator and unbond all its agent instances
        uint256 operatorService;
        operatorService |= uint256(uint160(operator)) << 160;
        operatorService |= serviceId << 192;
        AgentInstance[] memory agentInstances = mapOperatorsAgentInstances[operatorService];
        uint256 numAgentsUnbond = agentInstances.length;
        if (numAgentsUnbond == 0) {
            revert OperatorHasNoInstances(operator, serviceId);
        }

        // Subtract number of unbonded agent instances
        service.numAgentInstances -= uint32(numAgentsUnbond);
        if (service.numAgentInstances == 0) {
            service.state = ServiceState.TerminatedUnbonded;
        }

        // Calculate registration refund and free all agent instances
        refund = 0;
        for (uint256 i = 0; i < numAgentsUnbond; i++) {
            uint256 serviceAgent;
            serviceAgent |= serviceId << 32;
            serviceAgent |= uint256(agentInstances[i].agentId) << 64;
            refund += mapAgentParams[serviceAgent].bond;
            // Since the service is done, there's no need to clean-up the service-related data, just the state variables
            delete mapAgentInstanceOperators[agentInstances[i].instance];
        }

        // Calculate the refund
        uint96 balance = mapOperatorsBalances[operatorService];
        // This situation is possible if the operator was slashed for the agent instance misbehavior
        if (refund > balance) {
            refund = balance;
        }

        // Refund the operator
        if (refund > 0) {
            // Operator's balance is essentially zero after the refund
            mapOperatorsBalances[operatorService] = 0;
            // Send the refund
            (bool result, ) = operator.call{value: refund}("");
            if (!result) {
                // TODO When ERC20 token is used, change to the address of a token
                revert TransferFailed(address(0), address(this), operator, refund);
            }
            emit Refund(operator, refund);
        }

        emit OperatorUnbond(operator, serviceId);
        success = true;

        _locked = 1;
    }

    /// @dev Gets all agent instances
    /// @param agentInstances Pre-allocated list of agent instance addresses.
    /// @param service Service instance.
    /// @param serviceId ServiceId.
    function _getAgentInstances(Service storage service, uint256 serviceId) private view
        returns (address[] memory agentInstances)
    {
        agentInstances = new address[](service.numAgentInstances);
        uint256 count;
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            uint256 serviceAgent;
            serviceAgent |= serviceId << 32;
            serviceAgent |= uint256(service.agentIds[i]) << 64;
            for (uint256 j = 0; j < mapAgentInstances[serviceAgent].length; j++) {
                agentInstances[count] = mapAgentInstances[serviceAgent][j];
                count++;
            }
        }
    }

    /// @dev Update the map of service Id => set of components / canonical agent Ids.
    /// @param serviceId Service Id.
    function _updateServiceComponentAgentConnection(uint256 serviceId) private {
        uint32[] memory agentIds = mapServices[serviceId].agentIds;
        mapServiceIdSetAgents[serviceId] = agentIds;
        uint32[] memory subComponentIds = IRegistry(agentRegistry).getSubComponents(agentIds);
        mapServiceIdSetComponents[serviceId] = subComponentIds;
    }

    // TODO This must be split into just returning the Service struct and other values from maps called separately
    /// @dev Gets the high-level service information.
    /// @param serviceId Service Id.
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
    function getServiceInfo(uint256 serviceId) external view serviceExists(serviceId)
        returns (bytes32 name, bytes32 description, bytes32 configHash,
            uint256 threshold, uint256 numAgentIds, uint32[] memory agentIds, AgentParams[] memory agentParams,
            uint256 numAgentInstances, address[] memory agentInstances, address multisig)
    {
        Service storage service = mapServices[serviceId];
        agentParams = new AgentParams[](service.agentIds.length);
        numAgentInstances = service.numAgentInstances;
        agentInstances = _getAgentInstances(service, serviceId);
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            uint256 serviceAgent;
            serviceAgent |= serviceId << 32;
            // TODO Revision of all storage data to greatly reduce gas cost
            serviceAgent |= uint256(service.agentIds[i]) << 64;
            agentParams[i] = mapAgentParams[serviceAgent];
        }
        name = service.name;
        description = service.description;
        configHash = service.configHash;
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
    function getInstancesForAgentId(uint256 serviceId, uint256 agentId) external view serviceExists(serviceId)
        returns (uint256 numAgentInstances, address[] memory agentInstances)
    {
        uint256 serviceAgent;
        serviceAgent |= serviceId << 32;
        serviceAgent |= agentId << 64;
        numAgentInstances = mapAgentInstances[serviceAgent].length;
        agentInstances = new address[](numAgentInstances);
        for (uint256 i = 0; i < numAgentInstances; i++) {
            agentInstances[i] = mapAgentInstances[serviceAgent][i];
        }
    }

    /// @dev Gets previous service config hashes.
    /// @param serviceId Service Id.
    /// @return numHashes Number of hashes.
    /// @return configHashes The list of previous component hashes (excluding the current one).
    function getPreviousHashes(uint256 serviceId) external view serviceExists(serviceId)
        returns (uint256 numHashes, bytes32[] memory configHashes)
    {
        configHashes = mapConfigHashes[serviceId];
        numHashes = configHashes.length;
    }

    /// @dev Gets the set of canonical agent Ids that contain specified service Id.
    /// @param serviceId Service Id.
    /// @return numAgentIds Number of agent Ids.
    /// @return agentIds Set of agent Ids.
    function getAgentIdsOfServiceId(uint256 serviceId) external view
        returns (uint256 numAgentIds, uint32[] memory agentIds)
    {
        agentIds = mapServiceIdSetAgents[serviceId];
        numAgentIds = agentIds.length;
        // TODO This vs if we just get the mapServices[serviceId].agentIds
    }

    /// @dev Gets the set of component Ids that contain specified service Id.
    /// @param serviceId Service Id.
    /// @return numComponentIds Number of component Ids.
    /// @return componentIds Set of component Ids.
    function getComponentIdsOfServiceId(uint256 serviceId) external view
        returns (uint256 numComponentIds, uint32[] memory componentIds)
    {
        componentIds = mapServiceIdSetComponents[serviceId];
        numComponentIds = componentIds.length;
    }

    /// @dev Gets the service state.
    /// @param serviceId Service Id.
    /// @return state State of the service.
    function getServiceState(uint256 serviceId) external view returns (ServiceState state) {
        state = mapServices[serviceId].state;
    }

    /// @dev Gets the operator's balance in a specific service.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @return balance The balance of the operator.
    function getOperatorBalance(address operator, uint256 serviceId) external view serviceExists(serviceId)
        returns (uint256 balance)
    {
        uint256 operatorService;
        operatorService |= uint256(uint160(operator)) << 160;
        operatorService |= serviceId << 192;
        balance = mapOperatorsBalances[operatorService];
    }

    /// @dev Controls multisig implementation address permission.
    /// @param multisig Address of a multisig implementation.
    /// @param permission Grant or revoke permission.
    /// @return success True, if function executed successfully.
    function changeMultisigPermission(address multisig, bool permission) external returns (bool success) {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        if (multisig == address(0)) {
            revert ZeroAddress();
        }
        mapMultisigs[multisig] = permission;
        success = true;
    }
}
