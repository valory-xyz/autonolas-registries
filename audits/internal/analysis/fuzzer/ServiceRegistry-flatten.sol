// The following code is from flattening this file: ServiceRegistry.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/// @notice Modern, minimalist, and gas efficient ERC-721 implementation.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event Approval(address indexed owner, address indexed spender, uint256 indexed id);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                         METADATA STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    function tokenURI(uint256 id) public view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) internal _ownerOf;

    mapping(address => uint256) internal _balanceOf;

    function ownerOf(uint256 id) public view virtual returns (address owner) {
        require((owner = _ownerOf[id]) != address(0), "NOT_MINTED");
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        require(owner != address(0), "ZERO_ADDRESS");

        return _balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) public getApproved;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 id) public virtual {
        address owner = _ownerOf[id];

        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "NOT_AUTHORIZED");

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        require(from == _ownerOf[id], "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(
            msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[id],
            "NOT_AUTHORIZED"
        );

        // Underflow of the sender's balance is impossible because we check for
        // ownership above and the recipient's balance can't realistically overflow.
        unchecked {
            _balanceOf[from]--;

            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "") ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata data
    ) public virtual {
        transferFrom(from, to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data) ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 id) internal virtual {
        require(to != address(0), "INVALID_RECIPIENT");

        require(_ownerOf[id] == address(0), "ALREADY_MINTED");

        // Counter overflow is incredibly unrealistic.
        unchecked {
            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        emit Transfer(address(0), to, id);
    }

    function _burn(uint256 id) internal virtual {
        address owner = _ownerOf[id];

        require(owner != address(0), "NOT_MINTED");

        // Ownership check above ensures no underflow.
        unchecked {
            _balanceOf[owner]--;
        }

        delete _ownerOf[id];

        delete getApproved[id];

        emit Transfer(owner, address(0), id);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL SAFE MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _safeMint(address to, uint256 id) internal virtual {
        _mint(to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, "") ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }

    function _safeMint(
        address to,
        uint256 id,
        bytes memory data
    ) internal virtual {
        _mint(to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, data) ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }
}

/// @notice A generic interface for a contract which properly accepts ERC721 tokens.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}

/// @notice Efficient library for creating string representations of integers.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/LibString.sol)
library LibString {
    function toString(uint256 n) internal pure returns (string memory str) {
        if (n == 0) return "0"; // Otherwise it'd output an empty string for 0.

        assembly {
            let k := 78 // Start with the max length a uint256 string could be.

            // We'll store our string at the first chunk of free memory.
            str := mload(0x40)

            // The length of our string will start off at the max of 78.
            mstore(str, k)

            // Update the free memory pointer to prevent overriding our string.
            // Add 128 to the str pointer instead of 78 because we want to maintain
            // the Solidity convention of keeping the free memory pointer word aligned.
            mstore(0x40, add(str, 128))

            // We'll populate the string from right to left.
            // prettier-ignore
            for {} n {} {
                // The ASCII digit offset for '0' is 48.
                let char := add(48, mod(n, 10))

                // Write the current character into str.
                mstore(add(str, k), char)

                k := sub(k, 1)
                n := div(n, 10)
            }

            // Shift the pointer to the start of the string.
            str := add(str, k)

            // Set the length of the string to the correct value.
            mstore(str, sub(78, k))
        }
    }
}

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


/// @title Generic Registry - Smart contract for generic registry template
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
abstract contract GenericRegistry is IErrorsRegistries, ERC721 {
    using LibString for uint256;

    event OwnerUpdated(address indexed owner);
    event ManagerUpdated(address indexed manager);
    event BaseURIChanged(string baseURI);

    // Owner address
    address public owner;
    // Unit manager
    address public manager;
    // Base URI
    string public baseURI;
    // Unit counter
    uint256 public totalSupply;
    // Reentrancy lock
    uint256 internal _locked = 1;

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

    /// @dev Changes the unit manager.
    /// @param newManager Address of a new unit manager.
    function changeManager(address newManager) external virtual {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newManager == address(0)) {
            revert ZeroAddress();
        }

        manager = newManager;
        emit ManagerUpdated(newManager);
    }

    /// @dev Checks for the unit existence.
    /// @notice Unit counter starts from 1.
    /// @param unitId Unit Id.
    /// @return true if the unit exists, false otherwise.
    function exists(uint256 unitId) external view virtual returns (bool) {
        return unitId > 0 && unitId < (totalSupply + 1);
    }

    /// @dev Returns unit token URI.
    /// @param unitId Unit Id.
    /// @return Unit token URI string.
    function tokenURI(uint256 unitId) public view virtual override returns (string memory) {
        return string.concat(baseURI, unitId.toString());
    }
    
    /// @dev Sets unit base URI.
    /// @param bURI Base URI string.
    function setBaseURI(string memory bURI) external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero value
        if (bytes(bURI).length == 0) {
            revert ZeroValue();
        }

        baseURI = bURI;
        emit BaseURIChanged(bURI);
    }

    /// @dev Gets the valid unit Id from the provided index.
    /// @notice Unit counter starts from 1.
    /// @param id Unit counter.
    /// @return unitId Unit Id.
    function tokenByIndex(uint256 id) external view virtual returns (uint256 unitId) {
        unitId = id + 1;
        if (unitId > totalSupply) {
            revert Overflow(unitId, totalSupply);
        }
    }
}

/// @dev Generic multisig.
interface IMultisig {
    /// @dev Creates a multisig.
    /// @param owners Set of multisig owners.
    /// @param threshold Number of required confirmations for a multisig transaction.
    /// @param data Packed data related to the creation of a chosen multisig.
    /// @return multisig Address of a created multisig.
    function create(
        address[] memory owners,
        uint256 threshold,
        bytes memory data
    ) external returns (address multisig);
}

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
contract ServiceRegistryFuzzing is GenericRegistry {
    event Deposit(address indexed sender, uint256 amount);
    event Refund(address indexed sendee, uint256 amount);
    event CreateService(uint256 indexed serviceId);
    event UpdateService(uint256 indexed serviceId, bytes32 configHash);
    event RegisterInstance(address indexed operator, uint256 indexed serviceId, address indexed agentInstance, uint256 agentId);
    event CreateMultisigWithAgents(uint256 indexed serviceId, address indexed multisig);
    event ActivateRegistration(uint256 indexed serviceId);
    event TerminateService(uint256 indexed serviceId);
    event OperatorSlashed(uint256 amount, address indexed operator, uint256 indexed serviceId);
    event OperatorUnbond(address indexed operator, uint256 indexed serviceId);
    event DeployService(uint256 indexed serviceId);

    enum ServiceState {
        NonExistent,
        PreRegistration,
        ActiveRegistration,
        FinishedRegistration,
        Deployed,
        TerminatedBonded
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
        // Total number of agent instances. We assume that the number of instances is bounded by 2^32 - 1
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
    mapping(uint256 => AgentInstance[]) public mapOperatorsAgentInstances;
    // Service Id and canonical agent Id => number of agent instances and correspondent instance registration bond
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

    // Echidna invariant
    bool found = true;

    // for fuzzing
    constructor() ERC721("name", "symbol")
    {
        
        agentRegistry = msg.sender;
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

        // Check for the non-zero hash value
        if (configHash == "0x") {
            revert ZeroValue();
        }

        // Checking for non-empty arrays and correct number of values in them
        if (agentIds.length == 0 || agentIds.length != agentParams.length) {
            revert WrongArrayLength(agentIds.length, agentParams.length);
        }

        // Check for duplicate canonical agent Ids
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
        Service memory service,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint256 size,
        uint256 serviceId
    ) private
    {
        // Security deposit
        uint96 securityDeposit;
        // Add canonical agent Ids for the service and the slots map
        service.agentIds = new uint32[](size);
        for (uint256 i = 0; i < size; i++) {
            service.agentIds[i] = agentIds[i];
            // Push a pair of key defining variables into one key. Service or agent Ids are not enough by themselves
            uint256 serviceAgent;
            // As with other units, we believe that the system is not expected to support more than than 2^32-1 services
            // Need to carefully check pairings, since it's hard to find if something is incorrectly misplaced bitwise
            // serviceId occupies first 32 bits
            serviceAgent |= serviceId << 32;
            // agentId takes the second 32 bits
            serviceAgent |= uint256(agentIds[i]) << 64;
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
        Service memory service;
        // Updating high-level data components of the service
        service.name = name;
        service.description = description;
        service.threshold = threshold;
        service.maxNumAgentInstances = 0;
        // Assigning the initial hash
        service.configHash = configHash;
        // Set the initial service state
        service.state = ServiceState.PreRegistration;

        // Set service data
        _setServiceData(service, agentIds, agentParams, agentIds.length, serviceId);

        // Mint the service instance to the service owner and record the service structure
        _safeMint(serviceOwner, serviceId);
        mapServices[serviceId] = service;

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

        Service memory service = mapServices[serviceId];
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
                // Push a pair of key defining variables into one key. Service or agent Ids are not enough by themselves
                uint256 serviceAgent;
                // serviceId occupies first 32 bits, agentId gets the next 32 bits
                serviceAgent |= serviceId << 32;
                serviceAgent |= uint256(agentIds[i]) << 64;
                delete mapAgentParams[serviceAgent];
            } else {
                newAgentIds[size] = agentIds[i];
                newAgentParams[size] = agentParams[i];
                size++;
            }
        }
        // Check if the previous hash is the same / hash was not updated
        bytes32 lastConfigHash = service.configHash;
        if (lastConfigHash != configHash) {
            mapConfigHashes[serviceId].push(lastConfigHash);
            service.configHash = configHash;
        }

        // Set service data and record the modified service struct
        _setServiceData(service, newAgentIds, newAgentParams, size, serviceId);
        mapServices[serviceId] = service;

        emit UpdateService(serviceId, configHash);
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

        Service memory service = mapServices[serviceId];
        // Service must be inactive
        if (service.state != ServiceState.PreRegistration) {
            revert ServiceMustBeInactive(serviceId);
        }

        if (msg.value != service.securityDeposit) {
            revert IncorrectRegistrationDepositValue(msg.value, service.securityDeposit, serviceId);
        }

        // Activate the agent instance registration
        service.state = ServiceState.ActiveRegistration;
        mapServices[serviceId] = service;

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

        Service memory service = mapServices[serviceId];
        // The service has to be active to register agents
        if (service.state != ServiceState.ActiveRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Check for the sufficient amount of bond fee is provided
        uint256 numAgents = agentInstances.length;
        uint256 totalBond = 0;
        for (uint256 i = 0; i < numAgents; ++i) {
            // Check if canonical agent Id exists in the service
            // Push a pair of key defining variables into one key. Service or agent Ids are not enough by themselves
            uint256 serviceAgent;
            // serviceId occupies first 32 bits, agentId gets the next 32 bits
            serviceAgent |= serviceId << 32;
            serviceAgent |= uint256(agentIds[i]) << 64;
            if (mapAgentParams[serviceAgent].slots == 0) {
                revert AgentNotInService(agentIds[i], serviceId);
            }
            totalBond += mapAgentParams[serviceAgent].bond;
        }
        if (msg.value != totalBond) {
            revert IncorrectAgentBondingValue(msg.value, totalBond, serviceId);
        }

        // Push a pair of key defining variables into one key. Service Id or operator are not enough by themselves
        uint256 operatorService;
        // operator occupies first 160 bits
        operatorService |= uint256(uint160(operator)) << 160;
        // serviceId occupies next 32 bits
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
            // serviceId occupies first 32 bits, agentId gets the next 32 bits
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
        mapServices[serviceId] = service;

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

        Service memory service = mapServices[serviceId];
        if (service.state != ServiceState.FinishedRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Get all agent instances for the multisig
        address[] memory agentInstances = _getAgentInstances(service, serviceId);

        // Create a multisig with agent instances
        multisig = IMultisig(multisigImplementation).create(agentInstances, service.threshold, data);

        // Update maps of service Id to subcomponent and agent Ids
        mapServiceIdSetAgents[serviceId] = service.agentIds;
        mapServiceIdSetComponents[serviceId] = IRegistry(agentRegistry).getSubComponents(service.agentIds);

        service.multisig = multisig;
        service.state = ServiceState.Deployed;
        mapServices[serviceId] = service;

        emit CreateMultisigWithAgents(serviceId, multisig);
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

        address serviceMultisig = mapServices[serviceId].multisig;
        // Only the multisig of a correspondent address can slash its agent instances
        if (msg.sender != serviceMultisig) {
            revert OnlyOwnServiceMultisig(msg.sender, serviceMultisig, serviceId);
        }

        // Loop over each agent instance
        uint256 numInstancesToSlash = agentInstances.length;
        for (uint256 i = 0; i < numInstancesToSlash; ++i) {
            // Get the service Id from the agentInstance map
            address operator = mapAgentInstanceOperators[agentInstances[i]];
            // Push a pair of key defining variables into one key. Service Id or operator are not enough by themselves
            uint256 operatorService;
            // operator occupies first 160 bits
            operatorService |= uint256(uint160(operator)) << 160;
            // serviceId occupies next 32 bits
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

        Service memory service = mapServices[serviceId];
        // Check if the service is already terminated
        if (service.state == ServiceState.PreRegistration || service.state == ServiceState.TerminatedBonded) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }
        // Define the state of the service depending on the number of bonded agent instances
        if (service.numAgentInstances > 0) {
            service.state = ServiceState.TerminatedBonded;
        } else {
            service.state = ServiceState.PreRegistration;
        }
        mapServices[serviceId] = service;

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
        // Push a pair of key defining variables into one key. Service Id or operator are not enough by themselves
        uint256 operatorService;
        // operator occupies first 160 bits
        operatorService |= uint256(uint160(operator)) << 160;
        // serviceId occupies next 32 bits
        operatorService |= serviceId << 192;
        AgentInstance[] memory agentInstances = mapOperatorsAgentInstances[operatorService];
        uint256 numAgentsUnbond = agentInstances.length;
        if (numAgentsUnbond == 0) {
            revert OperatorHasNoInstances(operator, serviceId);
        }

        // Subtract number of unbonded agent instances
        if(service.numAgentInstances < numAgentsUnbond) {
            // echidna_found: PASSED!  
            found = false;
        }

        service.numAgentInstances -= uint32(numAgentsUnbond);
        if (service.numAgentInstances == 0) {
            service.state = ServiceState.PreRegistration;
        }

        // Calculate registration refund and free all agent instances
        refund = 0;
        for (uint256 i = 0; i < numAgentsUnbond; i++) {
            uint256 serviceAgent;
            // serviceId occupies first 32 bits, agentId gets the next 32 bits
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
    function _getAgentInstances(Service memory service, uint256 serviceId) private view
        returns (address[] memory agentInstances)
    {
        agentInstances = new address[](service.numAgentInstances);
        uint256 count;
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            uint256 serviceAgent;
            // serviceId occupies first 32 bits, agentId gets the next 32 bits
            serviceAgent |= serviceId << 32;
            serviceAgent |= uint256(service.agentIds[i]) << 64;
            for (uint256 j = 0; j < mapAgentInstances[serviceAgent].length; j++) {
                agentInstances[count] = mapAgentInstances[serviceAgent][j];
                count++;
            }
        }
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
        Service memory service = mapServices[serviceId];
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

    function echidna_found() public view returns (bool) {
        return(found);
    }
}



