// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

/// @dev Required interface for the component / agent manipulation.
interface IRegistry {
    /// @dev Creates component / agent.
    /// @param unitOwner Owner of the component / agent.
    /// @param description Description of the component / agent.
    /// @param unitHash IPFS hash of the component / agent.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted component / agent.
    function create(
        address unitOwner,
        bytes32 description,
        bytes32 unitHash,
        uint32[] memory dependencies
    ) external returns (uint256);

    /// @dev Updates the component / agent hash.
    /// @param owner Owner of the component / agent.
    /// @param unitId Unit Id.
    /// @param unitHash New IPFS hash of the component / agent.
    /// @return success True, if function executed successfully.
    function updateHash(address owner, uint256 unitId, bytes32 unitHash) external returns (bool success);

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
}
