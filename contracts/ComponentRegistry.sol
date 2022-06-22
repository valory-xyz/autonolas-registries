// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../lib/solmate/src/tokens/ERC721.sol";
import "../lib/solmate/src/utils/LibString.sol";
import "./interfaces/IErrorsRegistries.sol";
import "./interfaces/IRegistry.sol";

/// @title Component Registry - Smart contract for registering components
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ComponentRegistry is IErrorsRegistries, IStructs, ERC721 {
    using LibString for uint256;

    event OwnerUpdated(address indexed owner);
    event ManagerUpdated(address indexed manager);
    event BaseURIChanged(string baseURI);
    event CreateComponent(address indexed componentOwner, Multihash componentHash, uint256 componentId);
    event UpdateHash(address indexed componentOwner, Multihash componentHash, uint256 componentId);

    // Component parameters
    struct Component {
        // Developer of the component
        address developer;
        // IPFS hashes of the component
        // TODO This can be stored outside of component in its separate (componentId <=> set of hashes) map
        // TODO Or (initial hash <=> set of hashes) map. Here we could store only the initial hash
        Multihash[] componentHashes;
        // Description of the component
        // TODO string in struct is very expensive. One solution is bytes32
        string description;
        // Set of component dependencies
        // TODO Think of smaller values than uint256 to save storage
        uint256[] dependencies;
        // Component activity
        // TODO Seems like this variable is not needed, there will be no inactive component, otherwise it could break other dependent ones
        bool active;
    }

    // Owner address
    address public owner;
    // Component manager
    address public manager;
    // Base URI
    string public baseURI;
    // Component counter
    uint256 public totalSupply;
    // Reentrancy lock
    uint256 private _locked = 1;
    // Map of component Id => component
    mapping(uint256 => Component) public mapTokenIdComponent;
    // Map of IPFS hash => component Id
    mapping(bytes32 => uint256) public mapHashTokenId;

    /// @dev Component registry constructor.
    /// @param _name Component registry contract name.
    /// @param _symbol Component registry contract symbol.
    /// @param _baseURI Component registry token base URI.
    constructor(string memory _name, string memory _symbol, string memory _baseURI) ERC721(_name, _symbol) {
        baseURI = _baseURI;
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

    /// @dev Changes the component manager.
    /// @param newManager Address of a new component manager.
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
    // TODO This should go away, to be embedded in the code itself
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

    // TODO This needs to be embedded into the create() function itself to save on gas
    /// @dev Sets the component data.
    /// @param componentId Component Id.
    /// @param developer Developer of the component.
    /// @param componentHash IPFS hash of the component.
    /// @param description Description of the component.
    /// @param dependencies Set of component dependencies.
    function _setComponentInfo(uint256 componentId, address developer, Multihash memory componentHash,
        string memory description, uint256[] memory dependencies)
        private
    {
        Component storage component = mapTokenIdComponent[componentId];
        component.developer = developer;
        // TODO when componentHashes is stored in its own map, or when it becomes just the set of bytes32[3] arrays (v1 Multihash representation),
        // TODO the component is then taken as a memory instance, filled and assigned in a single storage operation
        component.componentHashes.push(componentHash);
        component.description = description;
        component.dependencies = dependencies;
        component.active = true;
//        mapTokenIdComponent[componentId] = component;
        mapHashTokenId[componentHash.hash] = componentId;
    }

    /// @dev Creates component.
    /// @param componentOwner Owner of the component.
    /// @param developer Developer of the component.
    /// @param componentHash IPFS hash of the component.
    /// @param description Description of the component.
    /// @param dependencies Set of component dependencies in a sorted ascending order (component Ids).
    /// @return componentId The id of a minted component.
    function create(address componentOwner, address developer, Multihash memory componentHash, string memory description,
        uint256[] memory dependencies)
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
        if (bytes(description).length == 0) {
            revert EmptyString();
        }
        
        // Check for dependencies validity: must be already allocated, must not repeat
        componentId = totalSupply;
        uint256 lastId;
        for (uint256 iDep = 0; iDep < dependencies.length; ++iDep) {
            if (dependencies[iDep] < (lastId + 1) || dependencies[iDep] > componentId) {
                revert WrongComponentId(dependencies[iDep]);
            }
            lastId = dependencies[iDep];
        }

        // Component with Id = 0 is left empty not to do additional checks for the index zero
        componentId++;
        // Initialize the component and mint its token
        _setComponentInfo(componentId, developer, componentHash, description, dependencies);

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
    function updateHash(address componentOwner, uint256 componentId, Multihash memory componentHash) external
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
        Component storage component = mapTokenIdComponent[componentId];
        component.componentHashes.push(componentHash);
        success = true;

        emit UpdateHash(componentOwner, componentHash, componentId);
    }

    /// @dev Checks for the component existence.
    /// @param componentId Component Id.
    /// @return true if the component exists, false otherwise.
    function exists(uint256 componentId) external view returns (bool) {
        return componentId > 0 && componentId < (totalSupply + 1);
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
        returns (address componentOwner, address developer, Multihash memory componentHash, string memory description,
            uint256 numDependencies, uint256[] memory dependencies)
    {
        // Check for the component existence
        if (componentId > 0 && componentId < (totalSupply + 1)) {
            Component memory component = mapTokenIdComponent[componentId];
            // TODO Here we return the initial hash (componentHashes[0]). With hashes outside of the Component struct,
            // TODO we could just return the component itself
            return (ownerOf(componentId), component.developer, component.componentHashes[0], component.description,
                component.dependencies.length, component.dependencies);
        }
    }

    /// @dev Gets component dependencies.
    /// @param componentId Component Id.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getDependencies(uint256 componentId) external view
        returns (uint256 numDependencies, uint256[] memory dependencies)
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
    /// @return componentHashes The list of component hashes.
    function getHashes(uint256 componentId) external view
        returns (uint256 numHashes, Multihash[] memory componentHashes)
    {
        // Check for the component existence
        if (componentId > 0 && componentId < (totalSupply + 1)) {
            Component memory component = mapTokenIdComponent[componentId];
            return (component.componentHashes.length, component.componentHashes);
        }
    }

    // TODO Alternativly, the component hash can be taken as an URI: string(abi.encodePacked(bytes32));
    /// @dev Returns component token URI.
    /// @param componentId Component Id.
    /// @return Component token URI string.
    function tokenURI(uint256 componentId) public view override returns (string memory) {
        return string.concat(baseURI, componentId.toString());
    }

    /// @dev Sets component base URI.
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
        emit BaseURIChanged(bURI);
    }

    /// @dev Gets the valid component Id from the provided index.
    /// @param id Component counter.
    /// @return componentId Component Id.
    function tokenByIndex(uint256 id) external view returns (uint256 componentId) {
        componentId = id + 1;
        if (componentId > totalSupply) {
            revert Overflow(componentId, totalSupply);
        }
    }
}
