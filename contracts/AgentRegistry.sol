// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./GenericRegistry.sol";
import "./interfaces/IRegistry.sol";

/// @title Agent Registry - Smart contract for registering agents
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract AgentRegistry is GenericRegistry {
    event CreateAgent(address indexed agentOwner, Multihash agentHash, uint256 agentId);
    event UpdateAgentHash(address indexed agentOwner, Multihash agentHash, uint256 agentId);

    // Agent parameters
    struct Agent {
        // Primary IPFS hashes of the agent
        Multihash agentHash;
        // Description of the agent
        bytes32 description;
        // Developer of the agent
        address developer;
        // Set of component dependencies
        // If one component is created every second, it will take 136 years to get to the 2^32 - 1 number limit
        uint32[] dependencies;
    }

    // Component registry
    address public immutable componentRegistry;
    // Map of IPFS hash => agent Id
    mapping(bytes32 => uint256) public mapHashTokenId;
    // Map of agent Id => set of updated IPFS hashes
    mapping(uint256 => Multihash[]) public mapTokenIdHashes;
    // Map of agent Id => agent
    mapping(uint256 => Agent) public mapTokenIdAgent;

    /// @dev Agent registry constructor.
    /// @param _name Agent registry contract name.
    /// @param _symbol Agent registry contract symbol.
    /// @param _baseURI Agent registry token base URI.
    /// @param _componentRegistry Component registry address.
    constructor(string memory _name, string memory _symbol, string memory _baseURI, address _componentRegistry)
        ERC721(_name, _symbol) {
        baseURI = _baseURI;
        componentRegistry = _componentRegistry;
        owner = msg.sender;
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

    /// @dev Creates agent.
    /// @param agentOwner Owner of the agent.
    /// @param developer Developer of the agent.
    /// @param agentHash IPFS hash of the agent.
    /// @param description Description of the agent.
    /// @param dependencies Set of component dependencies in a sorted ascending order (component Ids).
    /// @return agentId The id of a minted agent.
    function create(address agentOwner, address developer, Multihash memory agentHash, bytes32 description,
        uint32[] memory dependencies)
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
        if (description == 0) {
            revert ZeroValue();
        }

        // Check that the agent has at least one component
        if (dependencies.length == 0) {
            revert ZeroValue();
        }

        // Check for dependencies validity: must be already allocated, must not repeat
        agentId = totalSupply;
        uint256 componentTotalSupply = IRegistry(componentRegistry).totalSupply();
        uint256 lastId;
        for (uint256 iDep = 0; iDep < dependencies.length; ++iDep) {
            if (dependencies[iDep] < (lastId + 1) || dependencies[iDep] > componentTotalSupply) {
                revert ComponentNotFound(dependencies[iDep]);
            }
            lastId = dependencies[iDep];
        }

        // Mint token and initialize the agent
        agentId++;
        // Initialize the agent and mint its token
        Agent memory agent = Agent(agentHash, description, developer, dependencies);
        mapTokenIdAgent[agentId] = agent;
        mapHashTokenId[agentHash.hash] = agentId;

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
    function updateHash(address agentOwner, uint256 agentId, Multihash memory agentHash) external override
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
        mapTokenIdHashes[agentId].push(agentHash);
        success = true;

        emit UpdateAgentHash(agentOwner, agentHash, agentId);
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
        returns (address agentOwner, address developer, Multihash memory agentHash, bytes32 description,
            uint256 numDependencies, uint32[] memory dependencies)
    {
        if (agentId > 0 && agentId < (totalSupply + 1)) {
            Agent memory agent = mapTokenIdAgent[agentId];
            return (ownerOf(agentId), agent.developer, agent.agentHash, agent.description, agent.dependencies.length,
                agent.dependencies);
        }
    }

    /// @dev Gets agent component dependencies.
    /// @param agentId Agent Id.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getDependencies(uint256 agentId) external view
        returns (uint256 numDependencies, uint32[] memory dependencies)
    {
        if (agentId > 0 && agentId < (totalSupply + 1)) {
            Agent memory agent = mapTokenIdAgent[agentId];
            return (agent.dependencies.length, agent.dependencies);
        }
    }

    /// @dev Gets updated agent hashes.
    /// @param agentId Agent Id.
    /// @return numHashes Number of hashes.
    /// @return agentHashes The list of updated agent hashes (without the primary one).
    function getUpdatedHashes(uint256 agentId) external view override
        returns (uint256 numHashes, Multihash[] memory agentHashes)
    {
        if (agentId > 0 && agentId < (totalSupply + 1)) {
            Multihash[] memory hashes = mapTokenIdHashes[agentId];
            return (hashes.length, hashes);
        }
    }
}
