// SPDX-License-Identifier: MIT

import "solana";

/// @title Service Registry Solana - Smart contract for registering services on the Solana chain.
/// @dev Underlying canonical agents and components are not checked for their validity since they are set up on the L1 mainnet.
///      The architecture is optimistic, in the sense that service owners are assumed to reference existing and relevant agents.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
contract ServiceRegistrySolana {
    event OwnerUpdated(address indexed metadataAuthority);
    event BaseURIChanged(string baseURI);
    event DrainerUpdated(address indexed drainer);
    event Deposit(address indexed sender, uint32 amount);
    event Refund(address indexed receiver, uint32 amount);
    event CreateService(uint32 indexed serviceId, bytes32 configHash);
    event UpdateService(uint32 indexed serviceId, bytes32 configHash);
    event RegisterInstance(address indexed operator, uint32 indexed serviceId, address indexed agentInstance, uint32 agentId);
    event CreateMultisigWithAgents(uint32 indexed serviceId, address indexed multisig);
    event ActivateRegistration(uint32 indexed serviceId);
    event TerminateService(uint32 indexed serviceId);
    event OperatorSlashed(uint32 amount, address indexed operator, uint32 indexed serviceId);
    event OperatorUnbond(address indexed operator, uint32 indexed serviceId);
    event DeployService(uint32 indexed serviceId);
    event Drain(address indexed drainer, uint32 amount);

    enum ServiceState {
        NonExistent,
        PreRegistration,
        ActiveRegistration,
        FinishedRegistration,
        Deployed,
        TerminatedBonded
    }

    // Service parameters
    struct Service {
        address serviceOwner;
        // Registration activation deposit
        // This is enough for 1b+ ETH or 1e27
        uint32 securityDeposit;
        // Multisig address for agent instances
        address multisig;
        // IPFS hashes pointing to the config metadata
        bytes32 configHash;
        // Agent instance signers threshold: must no less than ceil((n * 2 + 1) / 3) of all the agent instances combined
        // This number will be enough to have ((2^32 - 1) * 3 - 1) / 2, which is bigger than 6.44b
        uint32 threshold;
        // Total number of agent instances. We assume that the number of instances is bounded by 2^32 - 1
        uint32 maxNumAgentInstances;
        // Actual number of agent instances. This number is less or equal to maxNumAgentInstances
        uint32 numAgentInstances;
        // Service state
        ServiceState state;
        // Canonical agent Ids for the service. Individual agent Id is bounded by the max number of agent Id
        uint32[] agentIds;
        uint32[] slots;
        uint32[] bonds;
    }

    // The public key for the authority that should sign every change to the NFT's URI
    address public metadataAuthority;
    // Base URI
    string public baseURI;
    // Service counter
    uint32 public totalSupply;
    // Reentrancy lock
    uint32 internal _locked = 1;
    // To better understand the CID anatomy, please refer to: https://proto.school/anatomy-of-a-cid/05
    // CID = <multibase_encoding>multibase_encoding(<cid-version><multicodec><multihash-algorithm><multihash-length><multihash-hash>)
    // CID prefix = <multibase_encoding>multibase_encoding(<cid-version><multicodec><multihash-algorithm><multihash-length>)
    // to complement the multibase_encoding(<multihash-hash>)
    // multibase_encoding = base16 = "f"
    // cid-version = version 1 = "0x01"
    // multicodec = dag-pb = "0x70"
    // multihash-algorithm = sha2-256 = "0x12"
    // multihash-length = 256 bits = "0x20"
    string public constant CID_PREFIX = "f01701220";
    // The amount of funds slashed. This is enough for 1b+ ETH or 1e27
    uint32 public slashedFunds;
    // Drainer address: set by the government and is allowed to drain ETH funds accumulated in this contract
    address public drainer;
    // Service registry version number
    string public constant VERSION = "1.0.0";
    // Map of service Id => set of IPFS hashes pointing to the config metadata
    mapping(uint32 => bytes32[]) public mapConfigHashes;
    // Map of operator address => (serviceId => set of registered agent instance addresses)
    mapping(address => mapping(uint32 => address[])) public mapOperatorAndServiceIdAgentInstanceAddresses;
    // Map of operator address => (serviceId => set of registered agent Ids)
    mapping(address => mapping(uint32 => uint32[])) public mapOperatorAndServiceIdAgentInstanceAgentIds;
    // Map of service Id => (canonical agent Id => number of agent instances)
    mapping(uint32 => mapping(uint32 => uint32)) public mapServiceAndAgentIdAgentSlots;
    // Map of service Id => (canonical agent Id => instance registration bond)
    mapping(uint32 => mapping(uint32 => uint32)) public mapServiceAndAgentIdAgentBonds;
    // Actual agent instance addresses. Map of service Id => (canonical agent Id => Set of agent instance addresses).
    mapping(uint32 => mapping(uint32 => address[])) public mapServiceAndAgentIdAgentInstances;
    // Map of operator address => (serviceId => agent instance bonding / escrow balance)
    mapping(address => mapping(uint32 => uint32)) public mapOperatorAndServiceIdOperatorBalances;
    // Map of agent instance address => service id it is registered with and operator address that supplied the instance
    mapping (address => address) public mapAgentInstanceOperators;
    // Map of policy for multisig implementations
    mapping (address => bool) public mapMultisigs;
    // Set of services
    Service[type(uint32).max] services;


    /// @dev Service registry constructor.
    /// @param _metadataAuthority Agent contract symbol.
    /// @param _baseURI Agent registry token base URI.
    constructor(address _metadataAuthority, string memory _baseURI)
    {
        metadataAuthority = _metadataAuthority;
        baseURI = _baseURI;
    }

    /// Requires the signature of the metadata authority.
    function requireSigner(address authority) internal view {
        for(uint32 i=0; i < tx.accounts.length; i++) {
            if (tx.accounts[i].key == authority) {
                require(tx.accounts[i].is_signer, "the authority account must sign the transaction");
                return;
            }
        }

        revert("The authority is missing");
    }

    /// @dev Changes the metadataAuthority address.
    /// @param newOwner Address of a new metadataAuthority.
    function changeOwner(address newOwner) external {
        // Check for the metadata authority
        requireSigner(metadataAuthority);

        // Check for the zero address
        if (newOwner == address(0)) {
            revert("Zero Address");
        }

        metadataAuthority = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Changes the drainer.
    /// @param newDrainer Address of a drainer.
    function changeDrainer(address newDrainer) external {
        // Check for the metadata authority
        requireSigner(metadataAuthority);

        // Check for the zero address
        if (newDrainer == address(0)) {
            revert("ZeroAddress");
        }

        drainer = newDrainer;
        emit DrainerUpdated(newDrainer);
    }

    function transfer(uint32 serviceId, address newServiceOwner) public {
        // Check for the service authority
        address serviceOwner = services[serviceId].serviceOwner;
        requireSigner(serviceOwner);

        services[serviceId].serviceOwner = newServiceOwner;

    }

    /// @dev Going through basic initial service checks.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param slots Set of agent instances number for each agent Id.
    /// @param bonds Corresponding set of required bonds to register an agent instance in the service.
    function _initialChecks(
        bytes32 configHash,
        uint32[] memory agentIds,
        uint32[] memory slots,
        uint32[] memory bonds
    ) private pure
    {
        // Check for the non-zero hash value
        if (configHash == 0) {
            revert("ZeroValue");
        }

        // Checking for non-empty arrays and correct number of values in them
        if (agentIds.length == 0 || agentIds.length != slots.length || agentIds.length != bonds.length) {
            revert("WrongArrayLength");
        }

        // Check for duplicate canonical agent Ids
        uint32 lastId = 0;
        for (uint32 i = 0; i < agentIds.length; i++) {
            if (agentIds[i] < (lastId + 1)) {
                revert("WrongAgentId");
            }
            lastId = agentIds[i];
        }
    }

    /// @dev Sets the service data.
    /// @param service A service instance to fill the data for.
    /// @param agentIds Canonical agent Ids.
    /// @param slots Set of agent instances number for each agent Id.
    /// @param bonds Corresponding set of required bonds to register an agent instance in the service.
    /// @param size Size of a canonical agent ids set.
    /// @param serviceId ServiceId.
    function _setServiceData(
        Service memory service,
        uint32[] memory agentIds,
        uint32[] memory slots,
        uint32[] memory bonds,
        uint32 size,
        uint32 serviceId
    ) private
    {
        // Security deposit
        uint32 securityDeposit = 0;
        // Add canonical agent Ids for the service and the slots map
        service.agentIds = agentIds;
        service.slots = slots;
        service.bonds = bonds;
        for (uint32 i = 0; i < size; i++) {
            service.maxNumAgentInstances += slots[i];
            // Security deposit is the maximum of the canonical agent registration bond
            if (bonds[i] > securityDeposit) {
                securityDeposit = bonds[i];
            }
        }
        service.securityDeposit = securityDeposit;

        // Check for the correct threshold: no less than ceil((n * 2 + 1) / 3) of all the agent instances combined
        uint32 checkThreshold = service.maxNumAgentInstances * 2 + 1;
        if (checkThreshold % 3 == 0) {
            checkThreshold = checkThreshold / 3;
        } else {
            checkThreshold = checkThreshold / 3 + 1;
        }
        if (service.threshold < checkThreshold || service.threshold > service.maxNumAgentInstances) {
            revert("WrongThreshold");
        }
    }

    /// @dev Creates a new service.
    /// @notice If agentIds are not sorted in ascending order then the function that executes initial checks gets reverted.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param slots Set of agent instances number for each agent Id.
    /// @param bonds Corresponding set of required bonds to register an agent instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function create(
        address serviceOwner,
        bytes32 configHash,
        uint32[] memory agentIds,
        uint32[] memory slots,
        uint32[] memory bonds,
        uint32 threshold
    ) external returns (uint32 serviceId)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert("ReentrancyGuard");
        }
        _locked = 2;

        // Check for the non-empty service owner address
        if (serviceOwner == address(0)) {
            revert("ZeroAddress");
        }

        // Execute initial checks
        _initialChecks(configHash, agentIds, slots, bonds);

        // Check that there are no zero number of slots for a specific canonical agent id and no zero registration bond
        for (uint32 i = 0; i < agentIds.length; i++) {
            if (slots[i] == 0 || bonds[i] == 0) {
                revert("ZeroValue");
            }
        }

        // Create a new service Id
        serviceId = totalSupply;
        serviceId++;

        // Set high-level data components of the service instance
        Service service;
        // Updating high-level data components of the service
        service.threshold = threshold;
        // Assigning the initial hash
        service.configHash = configHash;
        // Set the initial service state
        service.state = ServiceState.PreRegistration;

        // Set service data
        _setServiceData(service, agentIds, slots, bonds, agentIds.length, serviceId);

        // Mint the service instance to the service owner and record the service structure
        service.serviceOwner = serviceOwner;

        services[serviceId] = service;
        totalSupply = serviceId;

        emit CreateService(serviceId, configHash);

        _locked = 1;
    }

    // TODO: Fix update how we fixed it in the updated manager
    /// @dev Updates a service in a CRUD way.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @notice If agentIds are not sorted in ascending order then the function that executes initial checks gets reverted.
    /// @param slots Set of agent instances number for each agent Id.
    /// @param bonds Corresponding set of required bonds to register an agent instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    function update(
        bytes32 configHash,
        uint32[] memory agentIds,
        uint32[] memory slots,
        uint32[] memory bonds,
        uint32 threshold,
        uint32 serviceId
    ) external returns (bool success)
    {
        Service service = services[serviceId];

        // Check for the service authority
        address serviceOwner = service.serviceOwner;
        requireSigner(serviceOwner);

        if (service.state != ServiceState.PreRegistration) {
            revert("WrongServiceState");
        }

        // Execute initial checks
        _initialChecks(configHash, agentIds, slots, bonds);

        // Updating high-level data components of the service
        service.threshold = threshold;
        service.maxNumAgentInstances = 0;

        // Check if the previous hash is the same / hash was not updated
        bytes32 lastConfigHash = service.configHash;
        if (lastConfigHash != configHash) {
            mapConfigHashes[serviceId].push(lastConfigHash);
            service.configHash = configHash;
        }

        // Set service data and record the modified service struct
        uint32 size = agentIds.length;
        _setServiceData(service, agentIds, slots, bonds, size, serviceId);
        services[serviceId] = service;

        emit UpdateService(serviceId, configHash);
        success = true;
    }

    /// @dev Activates the service.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function activateRegistration(uint32 serviceId) external payable returns (bool success)
    {
        Service service = services[serviceId];

        // Check for the service authority
        address serviceOwner = service.serviceOwner;
        requireSigner(serviceOwner);

        // Service must be inactive
        if (service.state != ServiceState.PreRegistration) {
            revert("ServiceMustBeInactive");
        }

        // TODO: Need to check that the balance of the escrow for the serviceOwner has enough balance
//        if (msg.value != service.securityDeposit) {
//            revert IncorrectRegistrationDepositValue(msg.value, service.securityDeposit, serviceId);
//        }

        // Activate the agent instance registration
        service.state = ServiceState.ActiveRegistration;

        emit ActivateRegistration(serviceId);
        success = true;
    }

    /// @dev Registers agent instances.
    /// @param operator Address of the operator.
    /// @param serviceId Service Id to register agent instances for.
    /// @param agentInstances Agent instance addresses.
    /// @param agentIds Canonical Ids of the agent correspondent to the agent instance.
    /// @return success True, if function executed successfully.
    function registerAgents(
        address operator,
        uint32 serviceId,
        address[] memory agentInstances,
        uint32[] memory agentIds
    ) external payable returns (bool success)
    {
        // Check if the length of canonical agent instance addresses array and ids array have the same length
        if (agentInstances.length != agentIds.length) {
            revert("WrongArrayLength");
        }

        Service storage service = services[serviceId];
        // The service has to be active to register agents
        if (service.state != ServiceState.ActiveRegistration) {
            revert("WrongServiceState");
        }

        // Check for the sufficient amount of bond fee is provided
        uint32 numAgents = agentInstances.length;
        uint32 totalBond = 0;
        for (uint32 i = 0; i < numAgents; ++i) {
            // Check if canonical agent Id exists in the service
            // TODO: correct
            uint32 slots = service.slots[i];
            uint32 bond = service.bonds[i];
            if (slots == 0) {
                revert("AgentNotInService");
            }
            totalBond += bond;
        }
        // TODO: Check the escrow balance
//        if (msg.value != totalBond) {
//            revert("IncorrectAgentBondingValue");
//        }

        // Operator address must not be used as an agent instance anywhere else
        if (mapAgentInstanceOperators[operator] != address(0)) {
            revert("WrongOperator");
        }

        for (uint32 i = 0; i < numAgents; ++i) {
            address agentInstance = agentInstances[i];
            uint32 agentId = agentIds[i];

            // Operator address must be different from agent instance one
            if (operator == agentInstance) {
                revert("WrongOperator");
            }

            // Check if the agent instance is already engaged with another service
            if (mapAgentInstanceOperators[agentInstance] != address(0)) {
                revert("AgentInstanceRegistered");
            }

            // Check if there is an empty slot for the agent instance in this specific service
            if (mapServiceAndAgentIdAgentInstances[serviceId][agentIds[i]].length == service.slots[i]) {
                revert("AgentInstancesSlotsFilled");
            }

            // Add agent instance and operator and set the instance engagement
            mapServiceAndAgentIdAgentInstances[serviceId][agentIds[i]].push(agentInstance);
            mapOperatorAndServiceIdAgentInstanceAddresses[operator][serviceId].push(agentInstance);
            mapOperatorAndServiceIdAgentInstanceAgentIds[operator][serviceId].push(agentId);
            service.numAgentInstances++;
            mapAgentInstanceOperators[agentInstance] = operator;

            emit RegisterInstance(operator, serviceId, agentInstance, agentId);
        }

        // If the service agent instance capacity is reached, the service becomes finished-registration
        if (service.numAgentInstances == service.maxNumAgentInstances) {
            service.state = ServiceState.FinishedRegistration;
        }

        // Update operator's bonding balance
        mapOperatorAndServiceIdOperatorBalances[operator][serviceId] += totalBond;

        emit Deposit(operator, totalBond);
        success = true;
    }

    /// @dev Creates multisig instance controlled by the set of service agent instances and deploys the service.
    /// @param serviceId Correspondent service Id.
    /// @param multisigImplementation Multisig implementation address.
    /// @param data Data payload for the multisig creation.
    /// @return multisig Address of the created multisig.
    function deploy(
        uint32 serviceId,
        address multisigImplementation,
        bytes memory data
    ) external returns (address multisig)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert("ReentrancyGuard");
        }
        _locked = 2;

        Service service = services[serviceId];

        // Check for the service authority
        address serviceOwner = service.serviceOwner;
        requireSigner(serviceOwner);

        // Check for the whitelisted multisig implementation
        if (!mapMultisigs[multisigImplementation]) {
            revert("UnauthorizedMultisig");
        }

        if (service.state != ServiceState.FinishedRegistration) {
            revert("WrongServiceState");
        }

        // Get all agent instances for the multisig
        address[] memory agentInstances = _getAgentInstances(service, serviceId);

        // TODO: Understand the multisig workflow
        // Create a multisig with agent instances
        multisig = address(0);//IMultisig(multisigImplementation).create(agentInstances, service.threshold, data);

        service.multisig = multisig;
        service.state = ServiceState.Deployed;

        emit CreateMultisigWithAgents(serviceId, multisig);
        emit DeployService(serviceId);

        _locked = 1;
    }

    /// @dev Slashes a specified agent instance.
    /// @param agentInstances Agent instances to slash.
    /// @param amounts Correspondent amounts to slash.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    function slash(address[] memory agentInstances, uint32[] memory amounts, uint32 serviceId) external
        returns (bool success)
    {
        // Check if the service is deployed
        // Since we do not kill (burn) services, we want this check to happen in a right service state.
        // If the service is deployed, it definitely exists and is running. We do not want this function to be abused
        // when the service was deployed, then terminated, then in a sleep mode or before next deployment somebody
        // could use this function and try to slash operators.
        Service service = services[serviceId];
        if (service.state != ServiceState.Deployed) {
            revert("WrongServiceState");
        }

        // Check for the array size
        if (agentInstances.length != amounts.length) {
            revert("WrongArrayLength");
        }

        // Only the multisig of a correspondent address can slash its agent instances
        requireSigner(service.multisig);

        // Loop over each agent instance
        uint32 numInstancesToSlash = agentInstances.length;
        for (uint32 i = 0; i < numInstancesToSlash; ++i) {
            // Get the service Id from the agentInstance map
            address operator = mapAgentInstanceOperators[agentInstances[i]];
            // Slash the balance of the operator, make sure it does not go below zero
            uint32 balance = mapOperatorAndServiceIdOperatorBalances[operator][serviceId];
            if ((amounts[i] + 1) > balance) {
                // We cannot add to the slashed amount more than the balance of the operator
                slashedFunds += balance;
                balance = 0;
            } else {
                slashedFunds += amounts[i];
                balance -= amounts[i];
            }
            mapOperatorAndServiceIdOperatorBalances[operator][serviceId] = balance;

            emit OperatorSlashed(amounts[i], operator, serviceId);
        }
        success = true;
    }

    /// @dev Terminates the service.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    /// @return refund Refund to return to the service owner.
    function terminate(uint32 serviceId) external returns (bool success, uint32 refund)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert("ReentrancyGuard");
        }
        _locked = 2;

        Service service = services[serviceId];

        // Check for the service authority
        address serviceOwner = service.serviceOwner;
        requireSigner(serviceOwner);

        // Check if the service is already terminated
        if (service.state == ServiceState.PreRegistration || service.state == ServiceState.TerminatedBonded) {
            revert("WrongServiceState");
        }
        // Define the state of the service depending on the number of bonded agent instances
        if (service.numAgentInstances > 0) {
            service.state = ServiceState.TerminatedBonded;
        } else {
            service.state = ServiceState.PreRegistration;
        }

        // Delete the sensitive data
        for (uint32 i = 0; i < service.agentIds.length; ++i) {
            delete mapServiceAndAgentIdAgentInstances[serviceId][service.agentIds[i]];
        }

        // Return registration deposit back to the service owner
        refund = service.securityDeposit;
        // TODO: Figure out the escrow release
//        // By design, the refund is always a non-zero value, so no check is needed here fo that
//        (bool result, ) = serviceOwner.call{value: refund}("");
//        if (!result) {
//            revert TransferFailed(address(0), address(this), serviceOwner, refund);
//        }

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
    function unbond(address operator, uint32 serviceId) external returns (bool success, uint32 refund) {
        // Reentrancy guard
        if (_locked > 1) {
            revert("ReentrancyGuard");
        }
        _locked = 2;

        // Checks if the operator address is not zero
        if (operator == address(0)) {
            revert("ZeroAddress");
        }

        Service service = services[serviceId];
        // Service can only be in the terminated-bonded state or expired-registration in order to proceed
        if (service.state != ServiceState.TerminatedBonded) {
            revert("WrongServiceState");
        }

        // Check for the operator and unbond all its agent instances
        address[] memory agentInstances = mapOperatorAndServiceIdAgentInstanceAddresses[operator][serviceId];
        uint32 numAgentsUnbond = agentInstances.length;
        if (numAgentsUnbond == 0) {
            revert("OperatorHasNoInstances");
        }

        // Subtract number of unbonded agent instances
        service.numAgentInstances -= uint32(numAgentsUnbond);
        // When number of instances is equal to zero, all the operators have unbonded and the service is moved into
        // the PreRegistration state, from where it can be updated / start registration / get deployed again
        if (service.numAgentInstances == 0) {
            service.state = ServiceState.PreRegistration;
        }
        // else condition is redundant here, since the service is either in the TerminatedBonded state, or moved
        // into the PreRegistration state and unbonding is not possible before the new TerminatedBonded state is reached

        // Calculate registration refund and free all agent instances
        for (uint32 i = 0; i < numAgentsUnbond; i++) {
            // TODO: correct
            refund += service.bonds[i];
            // Clean-up the sensitive data such that it is not reused later
            delete mapAgentInstanceOperators[agentInstances[i]];
        }
        // Clean all the operator agent instances records for this service
        delete mapOperatorAndServiceIdAgentInstanceAddresses[operator][serviceId];
        delete mapOperatorAndServiceIdAgentInstanceAgentIds[operator][serviceId];

        // Calculate the refund
        uint32 balance = mapOperatorAndServiceIdOperatorBalances[operator][serviceId];
        // This situation is possible if the operator was slashed for the agent instance misbehavior
        if (refund > balance) {
            refund = balance;
        }

        // Refund the operator
        if (refund > 0) {
            // Operator's balance is essentially zero after the refund
            mapOperatorAndServiceIdOperatorBalances[operator][serviceId] = 0;
            // TODO: Figure out the escrow release
//            // Send the refund
//            (bool result, ) = operator.call{value: refund}("");
//            if (!result) {
//                revert("TransferFailed");
//            }
            emit Refund(operator, refund);
        }

        emit OperatorUnbond(operator, serviceId);
        success = true;

        _locked = 1;
    }

    /// @dev Gets the service instance.
    /// @param serviceId Service Id.
    /// @return service Corresponding Service struct.
    function getService(uint32 serviceId) external view returns (Service memory service) {
        service = services[serviceId];
    }

    /// @dev Gets service agent parameters: number of agent instances (slots) and a bond amount.
    /// @param serviceId Service Id.
    /// @return numAgentIds Number of canonical agent Ids in the service.
    /// @return slots Set of agent instances number for each agent Id.
    /// @return bonds Corresponding set of required bonds to register an agent instance in the service.
    function getAgentParams(uint32 serviceId) external view
        returns (uint32 numAgentIds, uint32[] memory slots, uint32[] memory bonds)
    {
        Service memory service = services[serviceId];
        numAgentIds = service.agentIds.length;
        slots = new uint32[](numAgentIds);
        bonds = new uint32[](numAgentIds);
        for (uint32 i = 0; i < numAgentIds; ++i) {
            slots[i] = service.slots[i];
            bonds[i] = service.bonds[i];
        }
    }

    /// @dev Lists all the instances of a given canonical agent Id if the service.
    /// @param serviceId Service Id.
    /// @param agentId Canonical agent Id.
    /// @return numAgentInstances Number of agent instances.
    /// @return agentInstances Set of agent instances for a specified canonical agent Id.
    function getInstancesForAgentId(uint32 serviceId, uint32 agentId) external view
        returns (uint32 numAgentInstances, address[] memory agentInstances)
    {
        numAgentInstances = mapServiceAndAgentIdAgentInstances[serviceId][agentId].length;
        agentInstances = new address[](numAgentInstances);
        for (uint32 i = 0; i < numAgentInstances; i++) {
            agentInstances[i] = mapServiceAndAgentIdAgentInstances[serviceId][agentId][i];
        }
    }

    /// @dev Gets all agent instances.
    /// @param service Service instance.
    /// @param serviceId ServiceId.
    /// @return agentInstances Pre-allocated list of agent instance addresses.
    function _getAgentInstances(Service memory service, uint32 serviceId) private view
        returns (address[] memory agentInstances)
    {
        agentInstances = new address[](service.numAgentInstances);
        uint32 count = 0;
        for (uint32 i = 0; i < service.agentIds.length; i++) {
            for (uint32 j = 0; j < mapServiceAndAgentIdAgentInstances[serviceId][service.agentIds[i]].length; j++) {
                agentInstances[count] = mapServiceAndAgentIdAgentInstances[serviceId][service.agentIds[i]][j];
                count++;
            }
        }
    }

    /// @dev Gets service agent instances.
    /// @param serviceId ServiceId.
    /// @return numAgentInstances Number of agent instances.
    /// @return agentInstances Pre-allocated list of agent instance addresses.
    function getAgentInstances(uint32 serviceId) external view
        returns (uint32 numAgentInstances, address[] memory agentInstances)
    {
        Service memory service = services[serviceId];
        agentInstances = _getAgentInstances(service, serviceId);
        numAgentInstances = agentInstances.length;
    }

    /// @dev Gets previous service config hashes.
    /// @param serviceId Service Id.
    /// @return numHashes Number of hashes.
    /// @return configHashes The list of previous component hashes (excluding the current one).
    function getPreviousHashes(uint32 serviceId) external view
        returns (uint32 numHashes, bytes32[] memory configHashes)
    {
        configHashes = mapConfigHashes[serviceId];
        numHashes = configHashes.length;
    }

    /// @dev Gets the operator's balance in a specific service.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @return balance The balance of the operator.
    function getOperatorBalance(address operator, uint32 serviceId) external view returns (uint32 balance)
    {
        balance = mapOperatorAndServiceIdOperatorBalances[operator][serviceId];
    }

    /// @dev Controls multisig implementation address permission.
    /// @param multisig Address of a multisig implementation.
    /// @param permission Grant or revoke permission.
    /// @return success True, if function executed successfully.
    function changeMultisigPermission(address multisig, bool permission) external returns (bool success) {
        // Check for the contract authority
        requireSigner(metadataAuthority);

        if (multisig == address(0)) {
            revert("ZeroAddress");
        }
        mapMultisigs[multisig] = permission;
        success = true;
    }

    /// @dev Drains slashed funds.
    /// @return amount Drained amount.
    function drain() external returns (uint32 amount) {
        // Reentrancy guard
        if (_locked > 1) {
            revert("ReentrancyGuard");
        }
        _locked = 2;

        // Check for the drainer address
        requireSigner(drainer);

        // Drain the slashed funds
        amount = slashedFunds;
        if (amount > 0) {
            slashedFunds = 0;
            // TODO: Figure out the amount send
            // Send the amount
//            (bool result, ) = msg.sender.call{value: amount}("");
//            if (!result) {
//                revert TransferFailed(address(0), address(this), msg.sender, amount);
//            }
            emit Drain(drainer, amount);
        }

        _locked = 1;
    }

    function ownerOf(uint32 serviceId) public view returns (address) {
        return services[serviceId].serviceOwner;
    }
    
    /// @dev Checks for the service existence.
    /// @notice Service counter starts from 1.
    /// @param serviceId Service Id.
    /// @return true if the service exists, false otherwise.
    function exists(uint32 serviceId) public view returns (bool) {
        return serviceId > 0 && serviceId < (totalSupply + 1);
    }

    /// @dev Sets service base URI.
    /// @param bURI Base URI string.
    function setBaseURI(string memory bURI) external {
        requireSigner(metadataAuthority);

        // Check for the zero value
        if (bytes(bURI).length == 0) {
            revert("Zero Value");
        }

        baseURI = bURI;
        emit BaseURIChanged(bURI);
    }

    /// @dev Gets the valid service Id from the provided index.
    /// @notice Service counter starts from 1.
    /// @param id Service counter.
    /// @return serviceId Service Id.
    function tokenByIndex(uint32 id) external view returns (uint32 serviceId) {
        serviceId = id + 1;
        if (serviceId > totalSupply) {
            revert("Overflow");
        }
    }

    // Open sourced from: https://stackoverflow.com/questions/67893318/solidity-how-to-represent-bytes32-as-string
    /// @dev Converts bytes16 input data to hex16.
    /// @notice This method converts bytes into the same bytes-character hex16 representation.
    /// @param data bytes16 input data.
    /// @return result hex16 conversion from the input bytes16 data.
    function _toHex16(bytes16 data) internal pure returns (bytes32 result) {
        result = bytes32 (data) & 0xFFFFFFFFFFFFFFFF000000000000000000000000000000000000000000000000 |
        (bytes32 (data) & 0x0000000000000000FFFFFFFFFFFFFFFF00000000000000000000000000000000) >> 64;
        result = result & 0xFFFFFFFF000000000000000000000000FFFFFFFF000000000000000000000000 |
        (result & 0x00000000FFFFFFFF000000000000000000000000FFFFFFFF0000000000000000) >> 32;
        result = result & 0xFFFF000000000000FFFF000000000000FFFF000000000000FFFF000000000000 |
        (result & 0x0000FFFF000000000000FFFF000000000000FFFF000000000000FFFF00000000) >> 16;
        result = result & 0xFF000000FF000000FF000000FF000000FF000000FF000000FF000000FF000000 |
        (result & 0x00FF000000FF000000FF000000FF000000FF000000FF000000FF000000FF0000) >> 8;
        result = (result & 0xF000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000) >> 4 |
        (result & 0x0F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F00) >> 8;
        result = bytes32 (0x3030303030303030303030303030303030303030303030303030303030303030 +
        uint256 (result) +
            (uint256 (result) + 0x0606060606060606060606060606060606060606060606060606060606060606 >> 4 &
            0x0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F) * 39);
    }

    /// @dev Returns service token URI.
    /// @notice Expected multicodec: dag-pb; hashing function: sha2-256, with base16 encoding and leading CID_PREFIX removed.
    /// @param serviceId Service Id.
    /// @return Service token URI string.
    function tokenURI(uint32 serviceId) public view returns (string memory) {
        bytes32 serviceHash = services[serviceId].configHash;
        // Parse 2 parts of bytes32 into left and right hex16 representation, and concatenate into string
        // adding the base URI and a cid prefix for the full base16 multibase prefix IPFS hash representation
        return string(abi.encodePacked(baseURI, CID_PREFIX, _toHex16(bytes16(serviceHash)),
            _toHex16(bytes16(serviceHash << 128))));
    }
}
