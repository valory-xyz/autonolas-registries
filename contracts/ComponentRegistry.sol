// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../lib/solmate/src/tokens/ERC721.sol";
import "../lib/solmate/src/utils/LibString.sol";
import "./interfaces/IErrorsRegistries.sol";
import "./interfaces/IRegistry.sol";
import "hardhat/console.sol";

/// @title Component Registry - Smart contract for registering components
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ComponentRegistry is IErrorsRegistries, IStructs, ERC721 {
    using LibString for uint256;

    event OwnerUpdated(address indexed owner);
    event ManagerUpdated(address indexed manager);
    event baseURIChanged(string baseURI);
    event CreateComponent(address indexed componentOwner, Multihash componentHash, uint256 componentId);
    event UpdateHash(address indexed componentOwner, Multihash componentHash, uint256 componentId);

    // Component parameters
    struct Component {
        // Developer of the component
        address developer;
        // IPFS hashes of the component
        // TODO This can be stored outside of component in its separate (componentId <=> set of hashes) map
        Multihash[] componentHashes;
        // Description of the component
        string description;
        // Set of component dependencies
        uint256[] dependencies;
        // Component activity
        bool active;
    }

    // Owner address
    address public owner;
    // Component manager
    address public manager;
    // Base URI
    string public baseURI;
    // Component counter. Component with Id = 0 is left empty not to do additional checks for the index zero
    uint256 public totalSupply = 1;
    // Reentrancy lock
    uint256 private _locked = 1;
    // Map of token Id => component
    // TODO This can be made public, and getInfo function would become obsolete
    mapping(uint256 => Component) private _mapTokenIdComponent;
    // Map of IPFS hash => token Id
    // TODO There is no point of having this private as well
    mapping(bytes32 => uint256) private _mapHashTokenId;

    /// @dev Component constructor.
    /// @param name Component contract name.
    /// @param symbol Component contract symbol.
    /// @param bURI Component token base URI.
    constructor(string memory name, string memory symbol, string memory bURI) ERC721(name, symbol) {
        baseURI = bURI;
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
        if (_mapHashTokenId[hashStruct.hash] > 0) {
            revert HashExists();
        }
        _;
    }

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
        Component storage component = _mapTokenIdComponent[componentId];
        component.developer = developer;
        // TODO when componentHashes is out in its own map, the component is then taken as a memory instance
        component.componentHashes.push(componentHash);
        component.description = description;
        component.dependencies = dependencies;
        component.active = true;
//        _mapTokenIdComponent[componentId] = component;
        _mapHashTokenId[componentHash.hash] = componentId;
    }

    /// @dev Creates component.
    /// @param componentOwner Owner of the component.
    /// @param developer Developer of the component.
    /// @param componentHash IPFS hash of the component.
    /// @param description Description of the component.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
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
            if (dependencies[iDep] < (lastId + 1) || (dependencies[iDep] + 1) > componentId) {
                revert WrongComponentId(dependencies[iDep]);
            }
            lastId = dependencies[iDep];
        }

        // Initialize the component and mint its token
        _setComponentInfo(componentId, developer, componentHash, description, dependencies);

        // Safe mint is needed since contracts can create components as well
        _safeMint(componentOwner, componentId);
        totalSupply = componentId + 1;

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
        Component storage component = _mapTokenIdComponent[componentId];
        component.componentHashes.push(componentHash);
        success = true;

        emit UpdateHash(componentOwner, componentHash, componentId);
    }

    /// @dev Check for the component existence.
    /// @param componentId Component Id.
    /// @return true if the component exists, false otherwise.
    function exists(uint256 componentId) external view returns (bool) {
        return componentId > 0 && componentId < totalSupply;
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
        // TODO These checks can be removed and return empty values instead
        if ((componentId + 1) > totalSupply) {
            revert ComponentNotFound(componentId);
        }
        Component memory component = _mapTokenIdComponent[componentId];
        return (ownerOf(componentId), component.developer, component.componentHashes[0], component.description,
            component.dependencies.length, component.dependencies);
    }

    /// @dev Gets component dependencies.
    /// @param componentId Component Id.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getDependencies(uint256 componentId) external view
        returns (uint256 numDependencies, uint256[] memory dependencies)
    {
        // Check for the component existence
        // TODO These checks can be removed and return empty values instead
        if ((componentId + 1) > totalSupply) {
            revert ComponentNotFound(componentId);
        }
        Component memory component = _mapTokenIdComponent[componentId];
        return (component.dependencies.length, component.dependencies);
    }

    /// @dev Gets component hashes.
    /// @param componentId Component Id.
    /// @return numHashes Number of hashes.
    /// @return componentHashes The list of component hashes.
    function getHashes(uint256 componentId) external view
        returns (uint256 numHashes, Multihash[] memory componentHashes)
    {
        // Check for the component existence
        // TODO These checks can be removed and return empty values instead
        if ((componentId + 1) > totalSupply) {
            revert ComponentNotFound(componentId);
        }
        Component memory component = _mapTokenIdComponent[componentId];
        return (component.componentHashes.length, component.componentHashes);
    }

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
        emit baseURIChanged(bURI);
    }
}
