// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../lib/solmate/src/tokens/ERC721.sol";
import "../lib/solmate/src/utils/LibString.sol";
import "./interfaces/IErrorsRegistries.sol";
import "./interfaces/IRegistry.sol";

/// @title Agent Registry - Smart contract for registering agents
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract AgentRegistry is IErrorsRegistries, IStructs, ERC721 {
    using LibString for uint256;

    event OwnerUpdated(address indexed owner);
    event ManagerUpdated(address indexed manager);
    event baseURIChanged(string baseURI);
    event CreateAgent(address indexed agentOwner, Multihash agentHash, uint256 agentId);
    event UpdateHash(address indexed agentOwner, Multihash agentHash, uint256 agentId);

    // Agent parameters
    struct Agent {
        // Developer of the agent
        address developer;
        // IPFS hashes of the agent
        Multihash[] agentHashes;
        // Description of the agent
        string description;
        // Set of component dependencies
        uint256[] dependencies;
        // Agent activity
        bool active;
    }

    // Component registry
    address public immutable componentRegistry;
    // Owner address
    address public owner;
    // Agent manager
    address public manager;
    // Base URI
    string public baseURI;
    // Agent counter
    uint256 public totalSupply;
    // Reentrancy lock
    uint256 private _locked = 1;
    // Map of agent Id => agent
    mapping(uint256 => Agent) public mapTokenIdAgent;
    // Map of IPFS hash => agent Id
    mapping(bytes32 => uint256) public mapHashTokenId;

    /// @dev Agent constructor.
    /// @param _name Agent contract name.
    /// @param _symbol Agent contract symbol.
    /// @param _baseURI Agent token base URI.
    /// @param _componentRegistry Component registry address.
    constructor(string memory _name, string memory _symbol, string memory _baseURI, address _componentRegistry)
        ERC721(_name, _symbol) {
        baseURI = _baseURI;
        componentRegistry = _componentRegistry;
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
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

    /// @dev Changes the agent manager.
    /// @param newManager Address of a new agent manager.
    function changeManager(address newManager) external {
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

    // Checks for supplied IPFS hash
    modifier checkHash(Multihash memory hashStruct) {
        // Check hash IPFS current standard validity
        if (hashStruct.hashFunction != 0x12 || hashStruct.size != 0x20) {
            revert WrongHash(hashStruct.hashFunction, 0x12, hashStruct.size, 0x20);
        }
        // Check for the existent IPFS hashes
        if (mapHashTokenId[hashStruct.hash] > 0) {
            revert HashExists();
        }
        _;
    }

    /// @dev Sets the agent data.
    /// @param agentId Agent Id.
    /// @param developer Developer of the agent.
    /// @param agentHash IPFS hash of the agent.
    /// @param description Description of the agent.
    /// @param dependencies Set of component dependencies.
    function _setAgentInfo(uint256 agentId, address developer, Multihash memory agentHash,
        string memory description, uint256[] memory dependencies)
        private
    {
        Agent storage agent = mapTokenIdAgent[agentId];
        agent.developer = developer;
        agent.agentHashes.push(agentHash);
        agent.description = description;
        agent.dependencies = dependencies;
        agent.active = true;
//        mapTokenIdComponent[agentId] = agent;
        mapHashTokenId[agentHash.hash] = agentId;
    }

    /// @dev Creates agent.
    /// @param agentOwner Owner of the agent.
    /// @param developer Developer of the agent.
    /// @param agentHash IPFS hash of the agent.
    /// @param description Description of the agent.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return agentId The id of a minted agent.
    function create(address agentOwner, address developer, Multihash memory agentHash, string memory description,
        uint256[] memory dependencies)
        external
        checkHash(agentHash)
        returns (uint256 agentId)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for an agent creation
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Checks for agentOwner and developer being not zero addresses
        if(agentOwner == address(0) || developer == address(0)) {
            revert ZeroAddress();
        }

        // Checks for non-empty description and component dependency
        if (bytes(description).length == 0) {
            revert EmptyString();
        }
//        require(dependencies.length > 0, "Agent must have at least one component dependency");

        // Check for dependencies validity: must be already allocated, must not repeat
        agentId = totalSupply;
        uint256 componentTotalSupply = IRegistry(componentRegistry).totalSupply();
        uint256 lastId;
        for (uint256 iDep = 0; iDep < dependencies.length; ++iDep) {
            if (dependencies[iDep] < (lastId + 1) || dependencies[iDep] > componentTotalSupply) {
                revert WrongComponentId(dependencies[iDep]);
            }
            lastId = dependencies[iDep];
        }

        // Mint token and initialize the agent
        agentId++;
        // Initialize the agent and mint its token
        _setAgentInfo(agentId, developer, agentHash, description, dependencies);

        // Safe mint is needed since contracts can create agents as well
        _safeMint(agentOwner, agentId);
        totalSupply = agentId;

        emit CreateAgent(agentOwner, agentHash, agentId);
        _locked = 1;
    }

    /// @dev Updates the agent hash.
    /// @param agentOwner Owner of the agent.
    /// @param agentId Agent Id.
    /// @param agentHash New IPFS hash of the agent.
    /// @return success True, if function executed successfully.
    function updateHash(address agentOwner, uint256 agentId, Multihash memory agentHash) external
        checkHash(agentHash) returns (bool success)
    {
        // Check for the manager privilege for an agent modification
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Checking the agent ownership
        if (ownerOf(agentId) != agentOwner) {
            revert AgentNotFound(agentId);
        }
        Agent storage agent = mapTokenIdAgent[agentId];
        agent.agentHashes.push(agentHash);
        success = true;

        emit UpdateHash(agentOwner, agentHash, agentId);
    }

    /// @dev Checks for the agent existence.
    /// @param agentId Agent Id.
    /// @return true if the agent exists, false otherwise.
    function exists(uint256 agentId) external view returns (bool) {
        return agentId > 0 && agentId < (totalSupply + 1);
    }

    /// @dev Gets the agent info.
    /// @param agentId Agent Id.
    /// @return agentOwner Owner of the agent.
    /// @return developer The agent developer.
    /// @return agentHash The primary agent IPFS hash.
    /// @return description The agent description.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getInfo(uint256 agentId) external view
        returns (address agentOwner, address developer, Multihash memory agentHash, string memory description,
            uint256 numDependencies, uint256[] memory dependencies)
    {
        if (agentId == 0 || agentId > totalSupply) {
            revert AgentNotFound(agentId);
        }
        Agent storage agent = mapTokenIdAgent[agentId];
        return (ownerOf(agentId), agent.developer, agent.agentHashes[0], agent.description, agent.dependencies.length,
            agent.dependencies);
    }

    /// @dev Gets agent component dependencies.
    /// @param agentId Agent Id.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getDependencies(uint256 agentId) external view
        returns (uint256 numDependencies, uint256[] memory dependencies)
    {
        if (agentId == 0 || agentId > totalSupply) {
            revert AgentNotFound(agentId);
        }
        Agent storage agent = mapTokenIdAgent[agentId];
        return (agent.dependencies.length, agent.dependencies);
    }

    /// @dev Gets agent hashes.
    /// @param agentId Agent Id.
    /// @return numHashes Number of hashes.
    /// @return agentHashes The list of agent hashes.
    function getHashes(uint256 agentId) external view
        returns (uint256 numHashes, Multihash[] memory agentHashes)
    {
        if (agentId == 0 || agentId > totalSupply) {
            revert AgentNotFound(agentId);
        }
        Agent storage agent = mapTokenIdAgent[agentId];
        return (agent.agentHashes.length, agent.agentHashes);
    }

    /// @dev Returns agent token URI.
    /// @param agentId Agent Id.
    /// @return Agent token URI string.
    function tokenURI(uint256 agentId) public view override returns (string memory) {
        return string.concat(baseURI, agentId.toString());
    }
    
    /// @dev Sets agent base URI.
    /// @param bURI Base URI string.
    function setBaseURI(string memory bURI) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero value
        if (bytes(bURI).length == 0) {
            revert ZeroValue();
        }

        baseURI = bURI;
        emit baseURIChanged(bURI);
    }

    /// @dev Gets the valid agent Id from the provided index.
    /// @param id Agent counter.
    /// @return agentId Agent Id.
    function tokenByIndex(uint256 id) external view returns (uint256 agentId) {
        agentId = id + 1;
        if (agentId > totalSupply) {
            revert Overflow(agentId, totalSupply);
        }
    }
}
