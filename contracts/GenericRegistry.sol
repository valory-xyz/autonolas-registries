// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../lib/solmate/src/tokens/ERC721.sol";
import "./interfaces/IErrorsRegistries.sol";

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
    // base16 multibase CID prefix to complement the base URI
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
}
