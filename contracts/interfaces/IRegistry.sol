// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

/// @dev Required interface for the component / agent manipulation.
interface IRegistry {
    /// @dev Creates component / agent.
    /// @param owner Owner of the component / agent.
    /// @param description Description of the component / agent.
    /// @param unitHash IPFS hash of the component / agent.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted component / agent.
    function create(
        address owner,
        bytes32 description,
        bytes32 unitHash,
        uint32[] memory dependencies
    ) external returns (uint256);

    /// @dev Updates the component / agent hash.
    /// @param owner Owner of the component / agent.
    /// @param unitId Unit Id.
    /// @param unitHash New IPFS hash of the component / agent.
    function updateHash(address owner, uint256 unitId, bytes32 unitHash) external;

    /// @dev Check for the component / agent existence.
    /// @param unitId Unit Id.
    /// @return true if the component / agent exists, false otherwise.
    function exists(uint256 unitId) external view returns (bool);

    /// @dev Gets the component / agent info.
    /// @param unitId Unit Id.
    /// @return owner Owner of the component / agent.
    /// @return unitHash The primary component / agent IPFS hash.
    /// @return description The component / agent description.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getInfo(uint256 unitId) external view returns (
        address owner,
        bytes32 unitHash,
        bytes32 description,
        uint256 numDependencies,
        uint32[] memory dependencies
    );

    /// @dev Gets component / agent dependencies.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getDependencies(uint256 unitId) external view returns (
        uint256 numDependencies,
        uint32[] memory dependencies
    );

    /// @dev Gets subcomponents of a provided unit Id from a local public map.
    /// @param unitId Unit Id.
    /// @return subComponentIds Set of subcomponents.
    /// @return numSubComponents Number of subcomponents.
    function getLocalSubComponents(uint256 unitId) external view returns (uint32[] memory subComponentIds, uint256 numSubComponents);

    /// @dev Gets calculated subcomponents.
    /// @param unitIds Set of unit Ids.
    /// @return subComponentIds Set of subcomponents.
    function getSubComponents(uint32[] memory unitIds) external view returns (uint32[] memory subComponentIds);

    /// @dev Gets updated component / agent hashes.
    /// @param unitId Unit Id.
    /// @return numHashes Number of hashes.
    /// @return unitHashes The list of component / agent hashes.
    function getUpdatedHashes(uint256 unitId) external view returns (uint256 numHashes, bytes32[] memory unitHashes);

    /// @dev Gets the total supply of components / agents.
    /// @return Total supply.
    function totalSupply() external view returns (uint256);

    /// @dev Gets the valid component Id from the provided index.
    /// @param id Component counter.
    /// @return componentId Component Id.
    function tokenByIndex(uint256 id) external view returns (uint256 componentId);
}
