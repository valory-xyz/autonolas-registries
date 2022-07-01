// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./GenericRegistry.sol";

/// @title Component Registry - Smart contract for registering components
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ComponentRegistry is GenericRegistry {
    event CreateComponent(address indexed componentOwner, Multihash componentHash, uint256 componentId);
    event UpdateComponentHash(address indexed componentOwner, Multihash componentHash, uint256 componentId);

    // Component parameters
    struct Component {
        // Primary IPFS hash of the component
        Multihash componentHash;
        // Description of the component
        bytes32 description;
        // Developer of the component
        address developer;
        // Set of component dependencies
        // If one component is created every second, it will take 136 years to get to the 2^32 - 1 number limit
        uint32[] dependencies;
    }

    // Map of IPFS hash => component Id
    mapping(bytes32 => uint256) public mapHashTokenId;
    // Map of component Id => set of updated IPFS hashes
    mapping(uint256 => Multihash[]) public mapTokenIdHashes;
    // Map of component Id => component
    mapping(uint256 => Component) public mapTokenIdComponent;

    /// @dev Component registry constructor.
    /// @param _name Component registry contract name.
    /// @param _symbol Component registry contract symbol.
    /// @param _baseURI Component registry token base URI.
    constructor(string memory _name, string memory _symbol, string memory _baseURI) ERC721(_name, _symbol) {
        baseURI = _baseURI;
        owner = msg.sender;
    }

    // Checks for supplied IPFS hash
    // TODO This should go away, to be embedded in the code itself
    // TODO Will be optimized when Multihash becomes bytes32[]
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

    /// @dev Creates component.
    /// @param componentOwner Owner of the component.
    /// @param developer Developer of the component.
    /// @param componentHash IPFS hash of the component.
    /// @param description Description of the component.
    /// @param dependencies Set of component dependencies in a sorted ascending order (component Ids).
    /// @return componentId The id of a minted component.
    function create(address componentOwner, address developer, Multihash memory componentHash, bytes32 description,
        uint32[] memory dependencies)
        external
        checkHash(componentHash)
        returns (uint256 componentId)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for a component creation
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Checks for owner and developer being not zero addresses
        if(componentOwner == address(0) || developer == address(0)) {
            revert ZeroAddress();
        }

        // Checks for non-empty description and component dependency
        if (description == 0) {
            revert ZeroValue();
        }
        
        // Check for dependencies validity: must be already allocated, must not repeat
        componentId = totalSupply;
        uint256 lastId;
        for (uint256 iDep = 0; iDep < dependencies.length; ++iDep) {
            if (dependencies[iDep] < (lastId + 1) || dependencies[iDep] > componentId) {
                revert ComponentNotFound(dependencies[iDep]);
            }
            lastId = dependencies[iDep];
        }

        // Component with Id = 0 is left empty not to do additional checks for the index zero
        componentId++;

        // Initialize the component and mint its token
        Component memory component = Component(componentHash, description, developer, dependencies);
        mapTokenIdComponent[componentId] = component;
        mapHashTokenId[componentHash.hash] = componentId;

        // Safe mint is needed since contracts can create components as well
        _safeMint(componentOwner, componentId);
        totalSupply = componentId;

        emit CreateComponent(componentOwner, componentHash, componentId);
        _locked = 1;
    }

    /// @dev Updates the component hash.
    /// @param componentOwner Owner of the component.
    /// @param componentId Component Id.
    /// @param componentHash New IPFS hash of the component.
    /// @return success True, if function executed successfully.
    function updateHash(address componentOwner, uint256 componentId, Multihash memory componentHash) external override
        checkHash(componentHash)
        returns (bool success)
    {
        // Check for the manager privilege for a component modification
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Checking the agent ownership
        if (ownerOf(componentId) != componentOwner) {
            revert ComponentNotFound(componentId);
        }
        mapTokenIdHashes[componentId].push(componentHash);
        success = true;

        emit UpdateComponentHash(componentOwner, componentHash, componentId);
    }

    // TODO As mentioned earlier, this can go away with the component owner, dependencies and set of hashes returned separately,
    // TODO and the rest is just the component struct publicly available
    /// @dev Gets the component info.
    /// @param componentId Component Id.
    /// @return componentOwner Owner of the component.
    /// @return developer The component developer.
    /// @return componentHash The primary component IPFS hash.
    /// @return description The component description.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getInfo(uint256 componentId) external view
        returns (address componentOwner, address developer, Multihash memory componentHash, bytes32 description,
            uint256 numDependencies, uint32[] memory dependencies)
    {
        // Check for the component existence
        if (componentId > 0 && componentId < (totalSupply + 1)) {
            Component memory component = mapTokenIdComponent[componentId];
            // TODO Here we return the initial hash (componentHashes[0]). With hashes outside of the Component struct,
            // TODO we could just return the component itself
            return (ownerOf(componentId), component.developer, component.componentHash, component.description,
                component.dependencies.length, component.dependencies);
        }
    }

    /// @dev Gets component dependencies.
    /// @param componentId Component Id.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getDependencies(uint256 componentId) external view
        returns (uint256 numDependencies, uint32[] memory dependencies)
    {
        // Check for the component existence
        if (componentId > 0 && componentId < (totalSupply + 1)) {
            Component memory component = mapTokenIdComponent[componentId];
            return (component.dependencies.length, component.dependencies);
        }
    }

    /// @dev Gets component hashes.
    /// @param componentId Component Id.
    /// @return numHashes Number of hashes.
    /// @return componentHashes The list of updated component hashes (without the primary one).
    function getHashes(uint256 componentId) external view override
        returns (uint256 numHashes, Multihash[] memory componentHashes)
    {
        // Check for the component existence
        if (componentId > 0 && componentId < (totalSupply + 1)) {
            Multihash[] memory hashes = mapTokenIdHashes[componentId];
            return (hashes.length, hashes);
        }
    }
}
