// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

/// @dev Required interface for the component / agent manipulation.
interface IRegistry {
    // Multihash according to self-describing hashes standard. For more information of multihashes please visit https://multiformats.io/multihash/
    struct Multihash {
        // IPFS uses a sha2-256 hashing function. Each IPFS hash has to start with 1220.
        bytes32 hash;
        // Code in hex for sha2-256 is 0x12
        uint8 hashFunction;
        // Length of the hash is 32 bytes, or 0x20 in hex
        uint8 size;
    }

    /// @dev Creates component / agent.
    /// @param owner Owner of the component / agent.
    /// @param developer Developer of the component / agent.
    /// @param mHash IPFS hash of the component / agent.
    /// @param description Description of the component / agent.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted component / agent.
    function create(
        address owner,
        address developer,
        Multihash memory mHash,
        bytes32 description,
        uint32[] memory dependencies
    ) external returns (uint256);

    /// @dev Updates the component / agent hash.
    /// @param owner Owner of the component / agent.
    /// @param unitId Unit Id.
    /// @param mHash New IPFS hash of the component / agent.
    function updateHash(address owner, uint256 unitId, Multihash memory mHash) external;

    /// @dev Check for the component / agent existence.
    /// @param unitId Unit Id.
    /// @return true if the component / agent exists, false otherwise.
    function exists(uint256 unitId) external view returns (bool);

    /// @dev Gets the component / agent info.
    /// @param unitId Unit Id.
    /// @return owner Owner of the component / agent.
    /// @return developer The component developer.
    /// @return mHash The primary component / agent IPFS hash.
    /// @return description The component / agent description.
    /// @return numDependencies The number of components in the dependency list.
    /// @return dependencies The list of component dependencies.
    function getInfo(uint256 unitId) external view returns (
        address owner,
        address developer,
        Multihash memory mHash,
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

    /// @dev Gets updated component / agent hashes.
    /// @param unitId Unit Id.
    /// @return numHashes Number of hashes.
    /// @return mHashes The list of component / agent hashes.
    function getUpdatedHashes(uint256 unitId) external view returns (uint256 numHashes, Multihash[] memory mHashes);

    /// @dev Gets the total supply of components / agents.
    /// @return Total supply.
    function totalSupply() external view returns (uint256);

    /// @dev Gets the valid component Id from the provided index.
    /// @param id Component counter.
    /// @return componentId Component Id.
    function tokenByIndex(uint256 id) external view returns (uint256 componentId);
}
