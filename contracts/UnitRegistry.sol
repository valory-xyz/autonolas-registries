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
