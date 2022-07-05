// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./GenericRegistry.sol";

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
        // Description of the unit
        bytes32 description;
        // Primary IPFS hash of the unit
        bytes32 unitHash;
        // Set of component dependencies (agents are also based on components)
        // We believe that the system is expected to support no more than 2^32-1 components
        uint32[] dependencies;
    }

    // Type of the unit: component or unit
    UnitType public unitType;
    // Map of unit Id => set of updated IPFS hashes
    mapping(uint256 => bytes32[]) public mapUnitIdHashes;
    // Map of IPFS hash => unit Id
    mapping(bytes32 => uint32) public mapHashUnitId;
    // Map of unit Id => set of subcomponents (possible to derive from any registry)
    mapping(uint256 => uint32[]) public mapSubComponents;
    // Map of unit Id => unit
    mapping(uint256 => Unit) public mapUnits;

    /// @dev Checks the provided component dependencies.
    /// @param dependencies Set of component dependencies.
    /// @param maxUnitId Maximum unit Id.
    function _checkDependencies(uint32[] memory dependencies, uint256 maxUnitId) internal virtual;

    /// @dev Creates unit.
    /// @param unitOwner Owner of the unit.
    /// @param description Description of the unit.
    /// @param unitHash IPFS CID hash of the unit.
    /// @param dependencies Set of unit dependencies in a sorted ascending order (unit Ids).
    /// @return unitId The id of a minted unit.
    function create(address unitOwner, bytes32 description, bytes32 unitHash, uint32[] memory dependencies)
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
        if (unitHash == "0x") {
            revert ZeroValue();
        }

        // Check for the existent IPFS hashes
        if (mapHashUnitId[unitHash] > 0) {
            revert HashExists();
        }

        // Checks for non-empty description and unit dependency
        if (description == 0) {
            revert ZeroValue();
        }
        
        // Check for dependencies validity: must be already allocated, must not repeat
        unitId = totalSupply;
        _checkDependencies(dependencies, unitId);

        // Unit with Id = 0 is left empty not to do additional checks for the index zero
        unitId++;

        // Initialize the unit and mint its token
        Unit memory unit = Unit(description, unitHash, dependencies);
        mapUnits[unitId] = unit;
        mapHashUnitId[unitHash] = uint32(unitId);

        // Update the map of subcomponents
        uint32[] memory subComponentIds = getSubComponents(dependencies);
        // We need to add a current component Id to the set of subcomponents if the unit is a component
        if (unitType == UnitType.Component) {
            uint256 subLen = subComponentIds.length + 1;
            uint32[] memory addSubComponentIds = new uint32[](subLen);
            for (uint256 i = 0; i < subLen - 1; ++i) {
                addSubComponentIds[i] = subComponentIds[i];
            }
            addSubComponentIds[subLen - 1] = uint32(unitId);
            subComponentIds = addSubComponentIds;
        }
        mapSubComponents[unitId] = subComponentIds;

        // Safe mint is needed since contracts can create units as well
        _safeMint(unitOwner, unitId);
        totalSupply = unitId;

        emit CreateUnit(unitId, unitType, unitHash);
        _locked = 1;
    }

    /// @dev Updates the unit hash.
    /// @param unitOwner Owner of the unit.
    /// @param unitId Unit Id.
    /// @param unitHash New IPFS hash of the unit.
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

        // Check for the existent IPFS hashes
        if (mapHashUnitId[unitHash] > 0) {
            revert HashExists();
        }

        mapUnitIdHashes[unitId].push(unitHash);
        success = true;

        emit UpdateUnitHash(unitId, unitType, unitHash);
    }

    // TODO As mentioned earlier, this can go away with the unit owner, dependencies and set of hashes returned separately,
    // TODO and the rest is just the unit struct publicly available
    /// @dev Gets the unit info.
    /// @param unitId Unit Id.
    /// @return unitOwner Owner of the unit.
    /// @return unitHash The primary unit IPFS hash.
    /// @return description The unit description.
    /// @return numDependencies The number of units in the dependency list.
    /// @return dependencies The list of unit dependencies.
    function getInfo(uint256 unitId) external view virtual
        returns (address unitOwner, bytes32 unitHash, bytes32 description,
            uint256 numDependencies, uint32[] memory dependencies)
    {
        // Check for the unit existence
        if (unitId > 0 && unitId < (totalSupply + 1)) {
            Unit memory unit = mapUnits[unitId];
            // TODO we could just return the unit itself
            return (ownerOf(unitId), unit.unitHash, unit.description, unit.dependencies.length, unit.dependencies);
        }
    }

    /// @dev Gets unit dependencies.
    /// @param unitId Unit Id.
    /// @return numDependencies The number of units in the dependency list.
    /// @return dependencies The list of unit dependencies.
    function getDependencies(uint256 unitId) external view virtual
        returns (uint256 numDependencies, uint32[] memory dependencies)
    {
        // Check for the unit existence
        if (unitId > 0 && unitId < (totalSupply + 1)) {
            Unit memory unit = mapUnits[unitId];
            return (unit.dependencies.length, unit.dependencies);
        }
    }

    /// @dev Gets updated unit hashes.
    /// @param unitId Unit Id.
    /// @return numHashes Number of hashes.
    /// @return unitHashes The list of updated unit hashes (without the primary one).
    function getUpdatedHashes(uint256 unitId) external view virtual
        returns (uint256 numHashes, bytes32[] memory unitHashes)
    {
        // Check for the unit existence
        if (unitId > 0 && unitId < (totalSupply + 1)) {
            bytes32[] memory hashes = mapUnitIdHashes[unitId];
            return (hashes.length, hashes);
        }
    }

    /// @dev Gets subcomponents of a provided unit Id.
    /// @param unitId Unit Id.
    /// @return subComponentIds Set of subcomponents.
    function _getSubComponents(uint32 unitId) internal view virtual returns (uint32[] memory subComponentIds);

    /// @dev Gets the set of subcomponent Ids.
    /// @param unitIds Unit Ids.
    /// @param subComponentIds Subcomponent Ids.
    function getSubComponents(uint32[] memory unitIds) public view virtual returns (uint32[] memory subComponentIds) {
        uint256 numUnits = unitIds.length;
        // Array of numbers of components per each unit Id
        uint256[] memory numComponents = new uint256[](numUnits);
        // 2D array of all the sets of components per each unit Id
        uint32[][] memory components = new uint32[][](numUnits);

        // Get total possible number of components and lists of components
        uint maxNumComponents;
        for (uint256 i = 0; i < numUnits; ++i) {
            components[i] = _getSubComponents(unitIds[i]);
            numComponents[i] = components[i].length;
            maxNumComponents += numComponents[i];
        }

        // Lists of components are sorted, take unique values in ascending order
        uint32[] memory allComponents = new uint32[](maxNumComponents);
        // Processed component counter
        uint256[] memory processedComponents = new uint256[](numUnits);
        // Minimal component Id
        uint32 minComponent;
        // Overall component counter
        uint256 counter;
        // Iterate until we process all components, at the maximum of the sum of all the components in all units
        for (counter = 0; counter < maxNumComponents; ++counter) {
            // Index of a minimal component
            uint256 minIdxComponent;
            // Amount of components identified as the next minimal component number
            uint256 numComponentsCheck;
            uint32 tryMinComponent = type(uint32).max;
            // Assemble an array of all first components from each component array
            for (uint256 i = 0; i < numUnits; ++i) {
                // Either get a component that has a higher id than the last one ore reach the end of the processed Ids
                for (; processedComponents[i] < numComponents[i]; ++processedComponents[i]) {
                    if (minComponent < components[i][processedComponents[i]]) {
                        // Out of those component Ids that are higher than the last one, pick the minimal one
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

        subComponentIds = new uint32[](counter);
        for (uint256 i = 0; i < counter; ++i) {
            subComponentIds[i] = allComponents[i];
        }
    }
}
