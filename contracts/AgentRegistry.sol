// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./UnitRegistry.sol";
import "./interfaces/IRegistry.sol";

/// @title Agent Registry - Smart contract for registering agents
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract AgentRegistry is UnitRegistry {
    // Component registry
    address public immutable componentRegistry;

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
        unitType = UnitType.Agent;
    }

    /// @dev Checks provided component dependencies.
    /// @param dependencies Set of component dependencies.
    function _checkDependencies(uint32[] memory dependencies, uint256) internal virtual override {
        // Check that the agent has at least one component
        if (dependencies.length == 0) {
            revert ZeroValue();
        }

        // Get the components total supply
        uint256 componentTotalSupply = IRegistry(componentRegistry).totalSupply();
        uint256 lastId;
        for (uint256 iDep = 0; iDep < dependencies.length; ++iDep) {
            if (dependencies[iDep] < (lastId + 1) || dependencies[iDep] > componentTotalSupply) {
                revert ComponentNotFound(dependencies[iDep]);
            }
            lastId = dependencies[iDep];
        }
    }

    /// @dev Gets linearized set of subcomponents of a provided component Id.
    /// @notice For agents this means getting the linearized map of components from the componentRegistry contract.
    /// @param componentId Component Id.
    /// @return subComponentIds Set of subcomponents.
    function _getSubComponents(uint32 componentId) internal view virtual override returns (uint32[] memory subComponentIds) {
        (subComponentIds, ) = IRegistry(componentRegistry).getLocalSubComponents(uint256(componentId));
    }
}
