// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../lib/solmate/src/tokens/ERC721.sol";
import "../lib/solmate/src/utils/LibString.sol";
import "./interfaces/IErrorsRegistries.sol";
import "./interfaces/IRegistry.sol";

/// @title Generic Registry - Smart contract for generic registry template
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
abstract contract GenericRegistry is IErrorsRegistries, ERC721 {
    using LibString for uint256;

    event OwnerUpdated(address indexed owner);
    event ManagerUpdated(address indexed manager);
    event BaseURIChanged(string baseURI);

    // Multihash according to self-describing hashes standard. For more information of multihashes please visit https://multiformats.io/multihash/
    struct Multihash {
        // IPFS uses a sha2-256 hashing function. Each IPFS hash has to start with 1220.
        bytes32 hash;
        // Code in hex for sha2-256 is 0x12
        uint8 hashFunction;
        // Length of the hash is 32 bytes, or 0x20 in hex
        uint8 size;
    }

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

    /// @dev Updates the unit hash.
    /// @param unitOwner Owner of the unit.
    /// @param unitId Component Id.
    /// @param unitHash New IPFS hash of the unit.
    /// @return success True, if function executed successfully.
    function updateHash(address unitOwner, uint256 unitId, Multihash memory unitHash) external virtual returns (bool success);

    /// @dev Gets unit hashes.
    /// @param unitId Unit Id.
    /// @return numHashes Number of hashes.
    /// @return unitHashes The list of unit hashes.
    function getHashes(uint256 unitId) external view virtual returns (uint256 numHashes, Multihash[] memory unitHashes);

    /// @dev Returns unit token URI.
    /// @param unitId Unit Id.
    /// @return Unit token URI string.
    function tokenURI(uint256 unitId) public view virtual override returns (string memory) {
        return string.concat(baseURI, unitId.toString());
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
}
