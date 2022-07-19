// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./UnitRegistry.sol";

/// @title Component Registry - Smart contract for registering components
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ComponentRegistry is UnitRegistry {
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
