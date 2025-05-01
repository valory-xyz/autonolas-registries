// The following code is from flattening this file: ServiceRegistry.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// The following code is from flattening this import statement in: ServiceRegistry.sol
// import "./GenericRegistry.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-registries/contracts/GenericRegistry.sol


// The following code is from flattening this import statement in: /home/andrey/valory/audit-process/projects/autonolas-registries/contracts/GenericRegistry.sol
// import "../lib/solmate/src/tokens/ERC721.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-registries/lib/solmate/src/tokens/ERC721.sol

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

// The following code is from flattening this import statement in: /home/andrey/valory/audit-process/projects/autonolas-registries/contracts/GenericRegistry.sol
// import "./interfaces/IErrorsRegistries.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-registries/contracts/interfaces/IErrorsRegistries.sol


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

    /// @dev Gets the hash of the unit.
    /// @param unitId Unit Id.
    /// @return Unit hash.
    function _getUnitHash(uint256 unitId) internal view virtual returns (bytes32);

    /// @dev Returns unit token URI.
    /// @notice Expected multicodec: dag-pb; hashing function: sha2-256, with base16 encoding and leading CID_PREFIX removed.
    /// @param unitId Unit Id.
    /// @return Unit token URI string.
    function tokenURI(uint256 unitId) public view virtual override returns (string memory) {
        bytes32 unitHash = _getUnitHash(unitId);
        // Parse 2 parts of bytes32 into left and right hex16 representation, and concatenate into string
        // adding the base URI and a cid prefix for the full base16 multibase prefix IPFS hash representation
        return string(abi.encodePacked(baseURI, CID_PREFIX, _toHex16(bytes16(unitHash)),
            _toHex16(bytes16(unitHash << 128))));
    }
}

// The following code is from flattening this import statement in: ServiceRegistry.sol
// import "./interfaces/IMultisig.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-registries/contracts/interfaces/IMultisig.sol

/// @title Unit Registry - Smart contract for registering generalized units / units
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
abstract contract UnitRegistry is GenericRegistry {
    event CreateUnit(uint256 unitId, UnitType uType, bytes32 unitHash);
    event UpdateUnitHash(uint256 unitId, UnitType uType, bytes32 unitHash);

    enum UnitType {
        Component,
        Agent
    }

    // Unit parameters
    struct Unit {
        // Primary IPFS hash of the unit
        bytes32 unitHash;
        // Set of component dependencies (agents are also based on components)
        // We assume that the system is expected to support no more than 2^32-1 components
        uint32[] dependencies;
    }

    // Type of the unit: component or unit
    UnitType public immutable unitType;
    // Map of unit Id => set of updated IPFS hashes
    mapping(uint256 => bytes32[]) public mapUnitIdHashes;
    // Map of unit Id => set of subcomponents (possible to derive from any registry)
    mapping(uint256 => uint32[]) public mapSubComponents;
    // Map of unit Id => unit
    mapping(uint256 => Unit) public mapUnits;

    constructor(UnitType _unitType) {
        unitType = _unitType;
    }

    /// @dev Checks the provided component dependencies.
    /// @param dependencies Set of component dependencies.
    /// @param maxUnitId Maximum unit Id.
    function _checkDependencies(uint32[] memory dependencies, uint32 maxUnitId) internal virtual;

    /// @dev Creates unit.
    /// @param unitOwner Owner of the unit.
    /// @param unitHash IPFS CID hash of the unit.
    /// @param dependencies Set of unit dependencies in a sorted ascending order (unit Ids).
    /// @return unitId The id of a minted unit.
    function create(address unitOwner, bytes32 unitHash, uint32[] memory dependencies)
        external virtual returns (uint256 unitId)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for a unit creation
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Checks for a non-zero owner address
        if(unitOwner == address(0)) {
            revert ZeroAddress();
        }

        // Check for the non-zero hash value
        if (unitHash == 0) {
            revert ZeroValue();
        }
        
        // Check for dependencies validity: must be already allocated, must not repeat
        unitId = totalSupply;
        _checkDependencies(dependencies, uint32(unitId));

        // Unit with Id = 0 is left empty not to do additional checks for the index zero
        unitId++;

        // Initialize the unit and mint its token
        Unit storage unit = mapUnits[unitId];
        unit.unitHash = unitHash;
        unit.dependencies = dependencies;

        // Update the map of subcomponents with calculated subcomponents for the new unit Id
        // In order to get the correct set of subcomponents, we need to differentiate between the callers of this function
        // Self contract (unit registry) can only call subcomponents calculation from the component level
        uint32[] memory subComponentIds = _calculateSubComponents(UnitType.Component, dependencies);
        // We need to add a current component Id to the set of subcomponents if the unit is a component
        // For example, if component 3 (c3) has dependencies of [c1, c2], then the subcomponents will return [c1, c2].
        // The resulting set will be [c1, c2, c3]. So we write into the map of component subcomponents: c3=>[c1, c2, c3].
        // This is done such that the subcomponents start getting explored, and when the agent calls its subcomponents,
        // it would have [c1, c2, c3] right away instead of adding c3 manually and then (for services) checking
        // if another agent also has c3 as a component dependency. The latter will consume additional computation.
        if (unitType == UnitType.Component) {
            uint256 numSubComponents = subComponentIds.length;
            uint32[] memory addSubComponentIds = new uint32[](numSubComponents + 1);
            for (uint256 i = 0; i < numSubComponents; ++i) {
                addSubComponentIds[i] = subComponentIds[i];
            }
            // Adding self component Id
            addSubComponentIds[numSubComponents] = uint32(unitId);
            subComponentIds = addSubComponentIds;
        }
        mapSubComponents[unitId] = subComponentIds;

        // Set total supply to the unit Id number
        totalSupply = unitId;
        // Safe mint is needed since contracts can create units as well
        _safeMint(unitOwner, unitId);

        emit CreateUnit(unitId, unitType, unitHash);
        _locked = 1;
    }

    /// @dev Updates the unit hash.
    /// @param unitOwner Owner of the unit.
    /// @param unitId Unit Id.
    /// @param unitHash Updated IPFS hash of the unit.
    /// @return success True, if function executed successfully.
    function updateHash(address unitOwner, uint256 unitId, bytes32 unitHash) external virtual
        returns (bool success)
    {
        // Check the manager privilege for a unit modification
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Checking the unit ownership
        if (ownerOf(unitId) != unitOwner) {
            if (unitType == UnitType.Component) {
                revert ComponentNotFound(unitId);
            } else {
                revert AgentNotFound(unitId);
            }
        }

        // Check for the hash value
        if (unitHash == 0) {
            revert ZeroValue();
        }

        mapUnitIdHashes[unitId].push(unitHash);
        success = true;

        emit UpdateUnitHash(unitId, unitType, unitHash);
    }

    /// @dev Gets the unit instance.
    /// @param unitId Unit Id.
    /// @return unit Corresponding Unit struct.
    function getUnit(uint256 unitId) external view virtual returns (Unit memory unit) {
        unit = mapUnits[unitId];
    }

    /// @dev Gets unit dependencies.
    /// @param unitId Unit Id.
    /// @return numDependencies The number of units in the dependency list.
    /// @return dependencies The list of unit dependencies.
    function getDependencies(uint256 unitId) external view virtual
        returns (uint256 numDependencies, uint32[] memory dependencies)
    {
        Unit memory unit = mapUnits[unitId];
        return (unit.dependencies.length, unit.dependencies);
    }

    /// @dev Gets updated unit hashes.
    /// @param unitId Unit Id.
    /// @return numHashes Number of hashes.
    /// @return unitHashes The list of updated unit hashes (without the primary one).
    function getUpdatedHashes(uint256 unitId) external view virtual
        returns (uint256 numHashes, bytes32[] memory unitHashes)
    {
        unitHashes = mapUnitIdHashes[unitId];
        return (unitHashes.length, unitHashes);
    }

    /// @dev Gets the set of subcomponent Ids from a local map of subcomponent.
    /// @param unitId Component Id.
    /// @return subComponentIds Set of subcomponent Ids.
    /// @return numSubComponents Number of subcomponents.
    function getLocalSubComponents(uint256 unitId) external view
        returns (uint32[] memory subComponentIds, uint256 numSubComponents)
    {
        subComponentIds = mapSubComponents[uint256(unitId)];
        numSubComponents = subComponentIds.length;
    }

    /// @dev Gets subcomponents of a provided unit Id.
    /// @param subcomponentsFromType Type of the unit: component or agent.
    /// @param unitId Unit Id.
    /// @return subComponentIds Set of subcomponents.
    function _getSubComponents(UnitType subcomponentsFromType, uint32 unitId) internal view virtual
        returns (uint32[] memory subComponentIds);

    /// @dev Calculates the set of subcomponent Ids.
    /// @param subcomponentsFromType Type of the unit: component or agent.
    /// @param unitIds Unit Ids.
    /// @return subComponentIds Subcomponent Ids.
    function _calculateSubComponents(UnitType subcomponentsFromType, uint32[] memory unitIds) internal view virtual
        returns (uint32[] memory subComponentIds)
    {
        uint32 numUnits = uint32(unitIds.length);
        // Array of numbers of components per each unit Id
        uint32[] memory numComponents = new uint32[](numUnits);
        // 2D array of all the sets of components per each unit Id
        uint32[][] memory components = new uint32[][](numUnits);

        // Get total possible number of components and lists of components
        uint32 maxNumComponents;
        for (uint32 i = 0; i < numUnits; ++i) {
            // Get subcomponents for each unit Id based on the subcomponentsFromType
            components[i] = _getSubComponents(subcomponentsFromType, unitIds[i]);
            numComponents[i] = uint32(components[i].length);
            maxNumComponents += numComponents[i];
        }

        // Lists of components are sorted, take unique values in ascending order
        uint32[] memory allComponents = new uint32[](maxNumComponents);
        // Processed component counter
        uint32[] memory processedComponents = new uint32[](numUnits);
        // Minimal component Id
        uint32 minComponent;
        // Overall component counter
        uint32 counter;
        // Iterate until we process all components, at the maximum of the sum of all the components in all units
        for (counter = 0; counter < maxNumComponents; ++counter) {
            // Index of a minimal component
            uint32 minIdxComponent;
            // Amount of components identified as the next minimal component number
            uint32 numComponentsCheck;
            uint32 tryMinComponent = type(uint32).max;
            // Assemble an array of all first components from each component array
            for (uint32 i = 0; i < numUnits; ++i) {
                // Either get a component that has a higher id than the last one ore reach the end of the processed Ids
                for (; processedComponents[i] < numComponents[i]; ++processedComponents[i]) {
                    if (minComponent < components[i][processedComponents[i]]) {
                        // Out of those component Ids that are higher than the last one, pick the minimal one
                        if (components[i][processedComponents[i]] < tryMinComponent) {
                            tryMinComponent = components[i][processedComponents[i]];
                            minIdxComponent = i;
                        }
                        // If we found a minimal component Id, we increase the counter and break to start the search again
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

        // Return the exact set of found subcomponents with the counter length
        subComponentIds = new uint32[](counter);
        for (uint32 i = 0; i < counter; ++i) {
            subComponentIds[i] = allComponents[i];
        }
    }

    /// @dev Gets the hash of the unit.
    /// @param unitId Unit Id.
    /// @return Unit hash.
    function _getUnitHash(uint256 unitId) internal view override returns (bytes32) {
        return mapUnits[unitId].unitHash;
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
// The following code is from flattening this import statement in: ServiceRegistry.sol
// import "./interfaces/IRegistry.sol";
// The following code is from flattening this file: /home/andrey/valory/audit-process/projects/autonolas-registries/contracts/interfaces/IRegistry.sol


/// @dev Required interface for the component / agent manipulation.
interface IRegistry {
    enum UnitType {
        Component,
        Agent
    }

    /// @dev Creates component / agent.
    /// @param unitOwner Owner of the component / agent.
    /// @param unitHash IPFS hash of the component / agent.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted component / agent.
    function create(
        address unitOwner,
        bytes32 unitHash,
        uint32[] memory dependencies
    ) external returns (uint256);

    /// @dev Updates the component / agent hash.
    /// @param owner Owner of the component / agent.
    /// @param unitId Unit Id.
    /// @param unitHash Updated IPFS hash of the component / agent.
    /// @return success True, if function executed successfully.
    function updateHash(address owner, uint256 unitId, bytes32 unitHash) external returns (bool success);

    /// @dev Gets subcomponents of a provided unit Id from a local public map.
    /// @param unitId Unit Id.
    /// @return subComponentIds Set of subcomponents.
    /// @return numSubComponents Number of subcomponents.
    function getLocalSubComponents(uint256 unitId) external view returns (uint32[] memory subComponentIds, uint256 numSubComponents);

    /// @dev Calculates the set of subcomponent Ids.
    /// @param unitIds Set of unit Ids.
    /// @return subComponentIds Subcomponent Ids.
    function calculateSubComponents(uint32[] memory unitIds) external view returns (uint32[] memory subComponentIds);

    /// @dev Gets updated component / agent hashes.
    /// @param unitId Unit Id.
    /// @return numHashes Number of hashes.
    /// @return unitHashes The list of component / agent hashes.
    function getUpdatedHashes(uint256 unitId) external view returns (uint256 numHashes, bytes32[] memory unitHashes);

    /// @dev Gets the total supply of components / agents.
    /// @return Total supply.
    function totalSupply() external view returns (uint256);
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


/// @title Component Registry - Smart contract for registering components
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ComponentRegistryFFS is UnitRegistry {
    // Component registry version number
    string public constant VERSION = "1.0.0";

    /// @dev Component registry constructor.
    /// @param _name Component registry contract name.
    /// @param _symbol Component registry contract symbol.
    /// @param _baseURI Component registry token base URI.
    constructor(string memory _name, string memory _symbol, string memory _baseURI)
        UnitRegistry(UnitType.Component)
        ERC721(_name, _symbol)
    {
        baseURI = _baseURI;
        owner = msg.sender;
    }

    /// @dev Checks provided component dependencies.
    /// @param dependencies Set of component dependencies.
    /// @param maxComponentId Maximum component Id.
    function _checkDependencies(uint32[] memory dependencies, uint32 maxComponentId) internal virtual override {
        uint32 lastId;
        for (uint256 iDep = 0; iDep < dependencies.length; ++iDep) {
            if (dependencies[iDep] < (lastId + 1) || dependencies[iDep] > maxComponentId) {
                revert ComponentNotFound(dependencies[iDep]);
            }
            lastId = dependencies[iDep];
        }
    }

    /// @dev Gets subcomponents of a provided component Id.
    /// @notice For components this means getting the linearized map of components from the local map of subcomponents.
    /// @param componentId Component Id.
    /// @return subComponentIds Set of subcomponents.
    function _getSubComponents(UnitType, uint32 componentId) internal view virtual override
        returns (uint32[] memory subComponentIds)
    {
        subComponentIds = mapSubComponents[uint256(componentId)];
    }
}



/// @title Agent Registry - Smart contract for registering agents
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract AgentRegistryFS is UnitRegistry {
    // Component registry
    address public immutable componentRegistry;
    // Agent registry version number
    string public constant VERSION = "1.0.0";

    /// @dev Agent registry constructor.
    /// @param _name Agent registry contract name.
    /// @param _symbol Agent registry contract symbol.
    /// @param _baseURI Agent registry token base URI.
    /// @param _componentRegistry Component registry address.
    constructor(string memory _name, string memory _symbol, string memory _baseURI, address _componentRegistry)
        UnitRegistry(UnitType.Agent)
        ERC721(_name, _symbol)
    {
        baseURI = _baseURI;
        componentRegistry = _componentRegistry;
        owner = msg.sender;
    }

    /// @dev Checks provided component dependencies.
    /// @param dependencies Set of component dependencies.
    function _checkDependencies(uint32[] memory dependencies, uint32) internal virtual override {
        // Check that the agent has at least one component
        if (dependencies.length == 0) {
            revert ZeroValue();
        }

        // Get the components total supply
        uint32 componentTotalSupply = uint32(IRegistry(componentRegistry).totalSupply());
        uint32 lastId;
        for (uint256 iDep = 0; iDep < dependencies.length; ++iDep) {
            if (dependencies[iDep] < (lastId + 1) || dependencies[iDep] > componentTotalSupply) {
                revert ComponentNotFound(dependencies[iDep]);
            }
            lastId = dependencies[iDep];
        }
    }

    /// @dev Gets linearized set of subcomponents of a provided unit Id and a type of a component.
    /// @notice (0) For components this means getting the linearized map of components from the componentRegistry contract.
    /// @notice (1) For agents this means getting the linearized map of components from the local map of subcomponents.
    /// @param subcomponentsFromType Type of the unit: component or agent.
    /// @param unitId Component Id.
    /// @return subComponentIds Set of subcomponents.
    function _getSubComponents(UnitType subcomponentsFromType, uint32 unitId) internal view virtual override
        returns (uint32[] memory subComponentIds)
    {
        // Self contract (agent registry) can only call subcomponents calculation from the component level (0)
        // Otherwise, the subcomponents are already written into the corresponding subcomponents map
        if (subcomponentsFromType == UnitType.Component) {
            (subComponentIds, ) = IRegistry(componentRegistry).getLocalSubComponents(uint256(unitId));
        } else {
            subComponentIds = mapSubComponents[uint256(unitId)];
        }
    }

    /// @dev Calculates the set of subcomponent Ids.
    /// @notice We assume that the external callers calculate subcomponents from the higher unit hierarchy level: agents.
    /// @param unitIds Unit Ids.
    /// @return subComponentIds Subcomponent Ids.
    function calculateSubComponents(uint32[] memory unitIds) external view returns (uint32[] memory subComponentIds)
    {
        subComponentIds = _calculateSubComponents(UnitType.Agent, unitIds);
    }
}


/// @title Service Registry - Smart contract for registering services
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ServiceRegistryF is GenericRegistry {
    event DrainerUpdated(address indexed drainer);
    event Deposit(address indexed sender, uint256 amount);
    event Refund(address indexed receiver, uint256 amount);
    event CreateService(uint256 indexed serviceId);
    event UpdateService(uint256 indexed serviceId, bytes32 configHash);
    event RegisterInstance(address indexed operator, uint256 indexed serviceId, address indexed agentInstance, uint256 agentId);
    event CreateMultisigWithAgents(uint256 indexed serviceId, address indexed multisig);
    event ActivateRegistration(uint256 indexed serviceId);
    event TerminateService(uint256 indexed serviceId);
    event OperatorSlashed(uint256 amount, address indexed operator, uint256 indexed serviceId);
    event OperatorUnbond(address indexed operator, uint256 indexed serviceId);
    event DeployService(uint256 indexed serviceId);
    event Drain(address indexed drainer, uint256 amount);

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
        // Registration activation deposit
        // This is enough for 1b+ ETH or 1e27
        uint96 securityDeposit;
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
    }

    // Agent Registry address
    address public immutable agentRegistry;
    // The amount of funds slashed. This is enough for 1b+ ETH or 1e27
    uint96 public slashedFunds;
    // Drainer address: set by the government and is allowed to drain ETH funds accumulated in this contract
    address public drainer;
    // Service registry version number
    string public constant VERSION = "1.0.0";
    // Map of service Id => set of IPFS hashes pointing to the config metadata
    mapping (uint256 => bytes32[]) public mapConfigHashes;
    // Map of operator address and serviceId => set of registered agent instance addresses
    mapping(uint256 => AgentInstance[]) public mapOperatorAndServiceIdAgentInstances;
    // Service Id and canonical agent Id => number of agent instances and correspondent instance registration bond
    mapping(uint256 => AgentParams) public mapServiceAndAgentIdAgentParams;
    // Actual agent instance addresses. Service Id and canonical agent Id => Set of agent instance addresses.
    mapping(uint256 => address[]) public mapServiceAndAgentIdAgentInstances;
    // Map of operator address and serviceId => agent instance bonding / escrow balance
    mapping(uint256 => uint96) public mapOperatorAndServiceIdOperatorBalances;
    // Map of agent instance address => service id it is registered with and operator address that supplied the instance
    mapping (address => address) public mapAgentInstanceOperators;
    // Map of service Id => set of unique component Ids
    // Updated during the service deployment via deploy() function
    mapping (uint256 => uint32[]) public mapServiceIdSetComponentIds;
    // Map of service Id => set of unique agent Ids
    mapping (uint256 => uint32[]) public mapServiceIdSetAgentIds;
    // Map of policy for multisig implementations
    mapping (address => bool) public mapMultisigs;
    // Map of service counter => service
    mapping (uint256 => Service) public mapServices;

    /// @dev Service registry constructor.
    /// @param _name Service contract name.
    /// @param _symbol Agent contract symbol.
    /// @param _baseURI Agent registry token base URI.
    /// @param _agentRegistry Agent registry address.
    constructor(string memory _name, string memory _symbol, string memory _baseURI, address _agentRegistry)
        ERC721(_name, _symbol)
    {
        baseURI = _baseURI;
        agentRegistry = _agentRegistry;
        owner = msg.sender;
    }

    /// @dev Changes the drainer.
    /// @param newDrainer Address of a drainer.
    function changeDrainer(address newDrainer) external {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newDrainer == address(0)) {
            revert ZeroAddress();
        }

        drainer = newDrainer;
        emit DrainerUpdated(newDrainer);
    }

    /// @dev Going through basic initial service checks.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    function _initialChecks(
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams
    ) private view
    {
        // Check for the non-zero hash value
        if (configHash == 0) {
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
            // As with other units, we assume that the system is not expected to support more than than 2^32-1 services
            // Need to carefully check pairings, since it's hard to find if something is incorrectly misplaced bitwise
            // serviceId occupies first 32 bits
            uint256 serviceAgent = serviceId;
            // agentId takes the second 32 bits
            serviceAgent |= uint256(agentIds[i]) << 32;
            mapServiceAndAgentIdAgentParams[serviceAgent] = agentParams[i];
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
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function create(
        address serviceOwner,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint32 threshold
    ) external returns (uint256 serviceId)
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

        // Check for the non-empty service owner address
        if (serviceOwner == address(0)) {
            revert ZeroAddress();
        }

        // Execute initial checks
        _initialChecks(configHash, agentIds, agentParams);

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
        service.threshold = threshold;
        // Assigning the initial hash
        service.configHash = configHash;
        // Set the initial service state
        service.state = ServiceState.PreRegistration;

        // Set service data
        _setServiceData(service, agentIds, agentParams, agentIds.length, serviceId);
        mapServices[serviceId] = service;
        totalSupply = serviceId;

        // Mint the service instance to the service owner and record the service structure
        _safeMint(serviceOwner, serviceId);

        emit CreateService(serviceId);

        _locked = 1;
    }

    /// @dev Updates a service in a CRUD way.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    function update(
        address serviceOwner,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint32 threshold,
        uint256 serviceId
    ) external returns (bool success)
    {
        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Check for the service ownership
        address actualOwner = ownerOf(serviceId);
        if (actualOwner != serviceOwner) {
            revert OwnerOnly(serviceOwner, actualOwner);
        }

        Service memory service = mapServices[serviceId];
        if (service.state != ServiceState.PreRegistration) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Execute initial checks
        _initialChecks(configHash, agentIds, agentParams);

        // Updating high-level data components of the service
        service.threshold = threshold;
        service.maxNumAgentInstances = 0;

        // Collect non-zero canonical agent ids and slots / costs, remove any canonical agent Ids from the params map
        uint32[] memory newAgentIds = new uint32[](agentIds.length);
        AgentParams[] memory newAgentParams = new AgentParams[](agentIds.length);
        uint256 size;
        for (uint256 i = 0; i < agentIds.length; i++) {
            if (agentParams[i].slots == 0) {
                // Push a pair of key defining variables into one key. Service or agent Ids are not enough by themselves
                // serviceId occupies first 32 bits, agentId gets the next 32 bits
                uint256 serviceAgent = serviceId;
                serviceAgent |= uint256(agentIds[i]) << 32;
                delete mapServiceAndAgentIdAgentParams[serviceAgent];
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
    function activateRegistration(address serviceOwner, uint256 serviceId) external payable returns (bool success)
    {
        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Check for the service ownership
        address actualOwner = ownerOf(serviceId);
        if (actualOwner != serviceOwner) {
            revert OwnerOnly(serviceOwner, actualOwner);
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
            // Push a pair of key defining variables into one key. Service or agent Ids are not enough by themselves
            // serviceId occupies first 32 bits, agentId gets the next 32 bits
            uint256 serviceAgent = serviceId;
            serviceAgent |= uint256(agentIds[i]) << 32;
            AgentParams memory agentParams = mapServiceAndAgentIdAgentParams[serviceAgent];
            if (agentParams.slots == 0) {
                revert AgentNotInService(agentIds[i], serviceId);
            }
            totalBond += agentParams.bond;
        }
        if (msg.value != totalBond) {
            revert IncorrectAgentBondingValue(msg.value, totalBond, serviceId);
        }

        // Operator address must not be used as an agent instance anywhere else
        if (mapAgentInstanceOperators[operator] != address(0)) {
            revert WrongOperator(serviceId);
        }

        // Push a pair of key defining variables into one key. Service Id or operator are not enough by themselves
        // operator occupies first 160 bits
        uint256 operatorService = uint256(uint160(operator));
        // serviceId occupies next 32 bits assuming it is not greater than 2^32 - 1 in value
        operatorService |= serviceId << 160;
        for (uint256 i = 0; i < numAgents; ++i) {
            address agentInstance = agentInstances[i];
            uint32 agentId = agentIds[i];

            // Operator address must be different from agent instance one
            if (operator == agentInstance) {
                revert WrongOperator(serviceId);
            }

            // Check if the agent instance is already engaged with another service
            if (mapAgentInstanceOperators[agentInstance] != address(0)) {
                revert AgentInstanceRegistered(mapAgentInstanceOperators[agentInstance]);
            }

            // Check if there is an empty slot for the agent instance in this specific service
            // serviceId occupies first 32 bits, agentId gets the next 32 bits
            uint256 serviceAgent = serviceId;
            serviceAgent |= uint256(agentIds[i]) << 32;
            if (mapServiceAndAgentIdAgentInstances[serviceAgent].length == mapServiceAndAgentIdAgentParams[serviceAgent].slots) {
                revert AgentInstancesSlotsFilled(serviceId);
            }

            // Add agent instance and operator and set the instance engagement
            mapServiceAndAgentIdAgentInstances[serviceAgent].push(agentInstance);
            mapOperatorAndServiceIdAgentInstances[operatorService].push(AgentInstance(agentInstance, agentId));
            service.numAgentInstances++;
            mapAgentInstanceOperators[agentInstance] = operator;

            emit RegisterInstance(operator, serviceId, agentInstance, agentId);
        }

        // If the service agent instance capacity is reached, the service becomes finished-registration
        if (service.numAgentInstances == service.maxNumAgentInstances) {
            service.state = ServiceState.FinishedRegistration;
        }

        // Update operator's bonding balance
        mapOperatorAndServiceIdOperatorBalances[operatorService] += uint96(msg.value);

        emit Deposit(operator, msg.value);
        success = true;
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
    ) external returns (address multisig)
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

        // Check for the service ownership
        address actualOwner = ownerOf(serviceId);
        if (actualOwner != serviceOwner) {
            revert OwnerOnly(serviceOwner, actualOwner);
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

        // Update maps of service Id to subcomponent and agent Ids
        mapServiceIdSetAgentIds[serviceId] = service.agentIds;
        mapServiceIdSetComponentIds[serviceId] = IRegistry(agentRegistry).calculateSubComponents(service.agentIds);

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
    function slash(address[] memory agentInstances, uint96[] memory amounts, uint256 serviceId) external
        returns (bool success)
    {
        // Check if the service is deployed
        // Since we do not kill (burn) services, we want this check to happen in a right service state.
        // If the service is deployed, it definitely exists and is running. We do not want this function to be abused
        // when the service was deployed, then terminated, then in a sleep mode or before next deployment somebody
        // could use this function and try to slash operators.
        Service memory service = mapServices[serviceId];
        if (service.state != ServiceState.Deployed) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Check for the array size
        if (agentInstances.length != amounts.length) {
            revert WrongArrayLength(agentInstances.length, amounts.length);
        }

        // Only the multisig of a correspondent address can slash its agent instances
        if (msg.sender != service.multisig) {
            revert OnlyOwnServiceMultisig(msg.sender, service.multisig, serviceId);
        }

        // Loop over each agent instance
        uint256 numInstancesToSlash = agentInstances.length;
        for (uint256 i = 0; i < numInstancesToSlash; ++i) {
            // Get the service Id from the agentInstance map
            address operator = mapAgentInstanceOperators[agentInstances[i]];
            // Push a pair of key defining variables into one key. Service Id or operator are not enough by themselves
            // operator occupies first 160 bits
            uint256 operatorService = uint256(uint160(operator));
            // serviceId occupies next 32 bits
            operatorService |= serviceId << 160;
            // Slash the balance of the operator, make sure it does not go below zero
            uint96 balance = mapOperatorAndServiceIdOperatorBalances[operatorService];
            if ((amounts[i] + 1) > balance) {
                // We cannot add to the slashed amount more than the balance of the operator
                slashedFunds += balance;
                balance = 0;
            } else {
                slashedFunds += amounts[i];
                balance -= amounts[i];
            }
            mapOperatorAndServiceIdOperatorBalances[operatorService] = balance;

            emit OperatorSlashed(amounts[i], operator, serviceId);
        }
        success = true;
    }

    /// @dev Terminates the service.
    /// @param serviceOwner Owner of the service.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    /// @return refund Refund to return to the service owner.
    function terminate(address serviceOwner, uint256 serviceId) external returns (bool success, uint256 refund)
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

        // Check for the service ownership
        address actualOwner = ownerOf(serviceId);
        if (actualOwner != serviceOwner) {
            revert OwnerOnly(serviceOwner, actualOwner);
        }

        Service storage service = mapServices[serviceId];
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
        
        // Delete the sensitive data
        delete mapServiceIdSetComponentIds[serviceId];
        delete mapServiceIdSetAgentIds[serviceId];
        for (uint256 i = 0; i < service.agentIds.length; ++i) {
            // serviceId occupies first 32 bits, agentId gets the next 32 bits
            uint256 serviceAgent = serviceId;
            serviceAgent |= uint256(service.agentIds[i]) << 32;
            delete mapServiceAndAgentIdAgentInstances[serviceAgent];
        }

        // Return registration deposit back to the service owner
        refund = service.securityDeposit;
        // By design, the refund is always a non-zero value, so no check is needed here fo that
        (bool result, ) = serviceOwner.call{value: refund}("");
        if (!result) {
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

        // Checks if the operator address is not zero
        if (operator == address(0)) {
            revert ZeroAddress();
        }

        Service storage service = mapServices[serviceId];
        // Service can only be in the terminated-bonded state or expired-registration in order to proceed
        if (service.state != ServiceState.TerminatedBonded) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Check for the operator and unbond all its agent instances
        // Push a pair of key defining variables into one key. Service Id or operator are not enough by themselves
        // operator occupies first 160 bits
        uint256 operatorService = uint256(uint160(operator));
        // serviceId occupies next 32 bits
        operatorService |= serviceId << 160;
        AgentInstance[] memory agentInstances = mapOperatorAndServiceIdAgentInstances[operatorService];
        uint256 numAgentsUnbond = agentInstances.length;
        if (numAgentsUnbond == 0) {
            revert OperatorHasNoInstances(operator, serviceId);
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
        for (uint256 i = 0; i < numAgentsUnbond; i++) {
            // serviceId occupies first 32 bits, agentId gets the next 32 bits
            uint256 serviceAgent = serviceId;
            serviceAgent |= uint256(agentInstances[i].agentId) << 32;
            refund += mapServiceAndAgentIdAgentParams[serviceAgent].bond;
            // Clean-up the sensitive data such that it is not reused later
            delete mapAgentInstanceOperators[agentInstances[i].instance];
        }
        // Clean all the operator agent instances records for this service
        delete mapOperatorAndServiceIdAgentInstances[operatorService];

        // Calculate the refund
        uint96 balance = mapOperatorAndServiceIdOperatorBalances[operatorService];
        // This situation is possible if the operator was slashed for the agent instance misbehavior
        if (refund > balance) {
            refund = balance;
        }

        // Refund the operator
        if (refund > 0) {
            // Operator's balance is essentially zero after the refund
            mapOperatorAndServiceIdOperatorBalances[operatorService] = 0;
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

    /// @dev Gets the service instance.
    /// @param serviceId Service Id.
    /// @return service Corresponding Service struct.
    function getService(uint256 serviceId) external view returns (Service memory service) {
        service = mapServices[serviceId];
    }

    /// @dev Gets service agent parameters: number of agent instances (slots) and a bond amount.
    /// @param serviceId Service Id.
    /// @return numAgentIds Number of canonical agent Ids in the service.
    /// @return agentParams Set of agent parameters for each canonical agent Id.
    function getAgentParams(uint256 serviceId) external view
        returns (uint256 numAgentIds, AgentParams[] memory agentParams)
    {
        Service memory service = mapServices[serviceId];
        numAgentIds = service.agentIds.length;
        agentParams = new AgentParams[](numAgentIds);
        for (uint256 i = 0; i < numAgentIds; ++i) {
            uint256 serviceAgent = serviceId;
            serviceAgent |= uint256(service.agentIds[i]) << 32;
            agentParams[i] = mapServiceAndAgentIdAgentParams[serviceAgent];
        }
    }

    /// @dev Lists all the instances of a given canonical agent Id if the service.
    /// @param serviceId Service Id.
    /// @param agentId Canonical agent Id.
    /// @return numAgentInstances Number of agent instances.
    /// @return agentInstances Set of agent instances for a specified canonical agent Id.
    function getInstancesForAgentId(uint256 serviceId, uint256 agentId) external view
        returns (uint256 numAgentInstances, address[] memory agentInstances)
    {
        uint256 serviceAgent = serviceId;
        serviceAgent |= agentId << 32;
        numAgentInstances = mapServiceAndAgentIdAgentInstances[serviceAgent].length;
        agentInstances = new address[](numAgentInstances);
        for (uint256 i = 0; i < numAgentInstances; i++) {
            agentInstances[i] = mapServiceAndAgentIdAgentInstances[serviceAgent][i];
        }
    }

    /// @dev Gets all agent instances.
    /// @param service Service instance.
    /// @param serviceId ServiceId.
    /// @return agentInstances Pre-allocated list of agent instance addresses.
    function _getAgentInstances(Service memory service, uint256 serviceId) private view
        returns (address[] memory agentInstances)
    {
        agentInstances = new address[](service.numAgentInstances);
        uint256 count;
        for (uint256 i = 0; i < service.agentIds.length; i++) {
            // serviceId occupies first 32 bits, agentId gets the next 32 bits
            uint256 serviceAgent = serviceId;
            serviceAgent |= uint256(service.agentIds[i]) << 32;
            for (uint256 j = 0; j < mapServiceAndAgentIdAgentInstances[serviceAgent].length; j++) {
                agentInstances[count] = mapServiceAndAgentIdAgentInstances[serviceAgent][j];
                count++;
            }
        }
    }

    /// @dev Gets service agent instances.
    /// @param serviceId ServiceId.
    /// @return numAgentInstances Number of agent instances.
    /// @return agentInstances Pre-allocated list of agent instance addresses.
    function getAgentInstances(uint256 serviceId) external view
        returns (uint256 numAgentInstances, address[] memory agentInstances)
    {
        Service memory service = mapServices[serviceId];
        agentInstances = _getAgentInstances(service, serviceId);
        numAgentInstances = agentInstances.length;
    }

    /// @dev Gets previous service config hashes.
    /// @param serviceId Service Id.
    /// @return numHashes Number of hashes.
    /// @return configHashes The list of previous component hashes (excluding the current one).
    function getPreviousHashes(uint256 serviceId) external view
        returns (uint256 numHashes, bytes32[] memory configHashes)
    {
        configHashes = mapConfigHashes[serviceId];
        numHashes = configHashes.length;
    }

    /// @dev Gets the full set of linearized components / canonical agent Ids for a specified service.
    /// @notice The service must be / have been deployed in order to get the actual data.
    /// @param serviceId Service Id.
    /// @return numUnitIds Number of component / agent Ids.
    /// @return unitIds Set of component / agent Ids.
    function getUnitIdsOfService(IRegistry.UnitType unitType, uint256 serviceId) external view
        returns (uint256 numUnitIds, uint32[] memory unitIds)
    {
        if (unitType == IRegistry.UnitType.Component) {
            unitIds = mapServiceIdSetComponentIds[serviceId];
        } else {
            unitIds = mapServiceIdSetAgentIds[serviceId];
        }
        numUnitIds = unitIds.length;
    }

    /// @dev Gets the operator's balance in a specific service.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @return balance The balance of the operator.
    function getOperatorBalance(address operator, uint256 serviceId) external view returns (uint256 balance)
    {
        uint256 operatorService = uint256(uint160(operator));
        operatorService |= serviceId << 160;
        balance = mapOperatorAndServiceIdOperatorBalances[operatorService];
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

    /// @dev Drains slashed funds.
    /// @return amount Drained amount.
    function drain() external returns (uint256 amount) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the drainer address
        if (msg.sender != drainer) {
            revert ManagerOnly(msg.sender, drainer);
        }

        // Drain the slashed funds
        amount = slashedFunds;
        if (amount > 0) {
            slashedFunds = 0;
            // Send the refund
            (bool result, ) = msg.sender.call{value: amount}("");
            if (!result) {
                revert TransferFailed(address(0), address(this), msg.sender, amount);
            }
            emit Drain(msg.sender, amount);
        }

        _locked = 1;
    }

    /// @dev Gets the hash of the service.
    /// @param serviceId Service Id.
    /// @return Service hash.
    function _getUnitHash(uint256 serviceId) internal view override returns (bytes32) {
        return mapServices[serviceId].configHash;
    }
}

contract ServiceRegistryProxy {
    ComponentRegistryFFS public iComponentRegistryFF;
    AgentRegistryFS public iAgentRegistryF;
    ServiceRegistryF public iServiceRegistryF;

    constructor() {
        // Initialize Strategy.
        // "agent", "MECH", "https://localhost/agent/"
        // "agent components", "MECHCOMP","https://localhost/component/"
        iComponentRegistryFF = ComponentRegistryFFS(0x1dC4c1cEFEF38a777b15aA20260a54E584b16C48);
        iAgentRegistryF = AgentRegistryFS(0x1D7022f5B17d2F8B695918FB48fa1089C9f85401);
        iServiceRegistryF = ServiceRegistryF(0x1E2F9E10D02a6b8F8f69fcBf515e75039D2EA30d);
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
        iServiceRegistryF.changeOwner(newOwner);
    }

    /// @dev Changes the unit manager.
    /// @param newManager Address of a new unit manager.
    function changeManager(address newManager) external {
        iServiceRegistryF.changeManager(newManager);
    }

    /// @dev Changes the drainer.
    /// @param newDrainer Address of a drainer.
    function changeDrainer(address newDrainer) external {
        iServiceRegistryF.changeDrainer(newDrainer);
    }

    /// @dev Creates a new service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function create(
        address serviceOwner,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint32 threshold
    ) external returns (uint256 serviceId)
    {
        return iServiceRegistryF.create(serviceOwner, configHash, agentIds, agentParams, threshold);    
    }

    /// @dev Updates a service in a CRUD way.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    function update(
        address serviceOwner,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint32 threshold,
        uint256 serviceId
    ) external returns (bool success)
    {
        return iServiceRegistryF.update(serviceOwner, configHash, agentIds, agentParams, threshold, serviceId);
    }

    /// @dev Activates the service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function activateRegistration(address serviceOwner, uint256 serviceId) external payable returns (bool success)
    {
        return iServiceRegistryF.activateRegistration{value: msg.value}(serviceOwner, serviceId);
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
        return iServiceRegistryF.registerAgents{value: msg.value}(operator, serviceId, agentInstances, agentIds);
    }

    /// @dev Creates multisig instance controlled by the set of service agent instances and deploys the service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @param data Data payload for the multisig creation.
    /// @return multisig Address of the created multisig.
    function deploy(
        address serviceOwner,
        uint256 serviceId,
        address,
        bytes memory data
    ) external returns (address multisig) {
        return iServiceRegistryF.deploy(serviceOwner, serviceId, 0x48BaCB9266a570d521063EF5dD96e61686DbE788, data);
    }

    /// @dev Slashes a specified agent instance.
    /// @param agentInstances Agent instances to slash.
    /// @param amounts Correspondent amounts to slash.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    function slash(address[] memory agentInstances, uint96[] memory amounts, uint256 serviceId) external
        returns (bool success)
    {
        return iServiceRegistryF.slash(agentInstances, amounts, serviceId);
    }

    /// @dev Terminates the service.
    /// @param serviceOwner Owner of the service.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    /// @return refund Refund to return to the service owner.
    function terminate(address serviceOwner, uint256 serviceId) external returns (bool success, uint256 refund)
    {
        return iServiceRegistryF.terminate(serviceOwner, serviceId);
    }

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param operator Operator of agent instances.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function unbond(address operator, uint256 serviceId) external returns (bool success, uint256 refund) {
        return iServiceRegistryF.unbond(operator, serviceId);
    }

    /// @dev Gets the service instance.
    /// @param serviceId Service Id.
    /// @return service Corresponding Service struct.
    function getService(uint256 serviceId) external view returns (ServiceRegistryF.Service memory service) {
        return iServiceRegistryF.getService(serviceId);
    }

    /// @dev Gets service agent parameters: number of agent instances (slots) and a bond amount.
    /// @param serviceId Service Id.
    /// @return numAgentIds Number of canonical agent Ids in the service.
    /// @return agentParams Set of agent parameters for each canonical agent Id.
    function getAgentParams(uint256 serviceId) external view
        returns (uint256 numAgentIds, AgentParams[] memory agentParams)
    {
        return iServiceRegistryF.getAgentParams(serviceId);
    }

    /// @dev Lists all the instances of a given canonical agent Id if the service.
    /// @param serviceId Service Id.
    /// @param agentId Canonical agent Id.
    /// @return numAgentInstances Number of agent instances.
    /// @return agentInstances Set of agent instances for a specified canonical agent Id.
    function getInstancesForAgentId(uint256 serviceId, uint256 agentId) external view
        returns (uint256 numAgentInstances, address[] memory agentInstances) {
        return iServiceRegistryF.getInstancesForAgentId(serviceId, agentId);
    }


    /// @dev Gets service agent instances.
    /// @param serviceId ServiceId.
    /// @return numAgentInstances Number of agent instances.
    /// @return agentInstances Pre-allocated list of agent instance addresses.
    function getAgentInstances(uint256 serviceId) external view
        returns (uint256 numAgentInstances, address[] memory agentInstances)
    {
        return iServiceRegistryF.getAgentInstances(serviceId);
    }

    /// @dev Gets previous service config hashes.
    /// @param serviceId Service Id.
    /// @return numHashes Number of hashes.
    /// @return configHashes The list of previous component hashes (excluding the current one).
    function getPreviousHashes(uint256 serviceId) external view
        returns (uint256 numHashes, bytes32[] memory configHashes)
    {
        return iServiceRegistryF.getPreviousHashes(serviceId);
    }

    /// @dev Gets the full set of linearized components / canonical agent Ids for a specified service.
    /// @notice The service must be / have been deployed in order to get the actual data.
    /// @param serviceId Service Id.
    /// @return numUnitIds Number of component / agent Ids.
    /// @return unitIds Set of component / agent Ids.
    function getUnitIdsOfService(IRegistry.UnitType unitType, uint256 serviceId) external view
        returns (uint256 numUnitIds, uint32[] memory unitIds)
    {
        return iServiceRegistryF.getUnitIdsOfService(unitType, serviceId);
    }

    /// @dev Gets the operator's balance in a specific service.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @return balance The balance of the operator.
    function getOperatorBalance(address operator, uint256 serviceId) external view returns (uint256 balance)
    {
        return iServiceRegistryF.getOperatorBalance(operator, serviceId);
    }

    /// @dev Controls multisig implementation address permission.
    /// @param multisig Address of a multisig implementation.
    /// @param permission Grant or revoke permission.
    /// @return success True, if function executed successfully.
    function changeMultisigPermission(address multisig, bool permission) external returns (bool success) {
        return iServiceRegistryF.changeMultisigPermission(multisig, permission);
    }

    /// @dev Drains slashed funds.
    /// @return amount Drained amount.
    function drain() external returns (uint256 amount) {
        return iServiceRegistryF.drain();
    }
}


