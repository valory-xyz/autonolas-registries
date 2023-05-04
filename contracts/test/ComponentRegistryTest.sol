// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../ComponentRegistry.sol";

error DifferentTokenURIs();

/// @title Unit Registry - Smart contract for registering generalized units / units
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract ComponentRegistryTest is ComponentRegistry {
    // Hex symbols to compare hex values against
    bytes16 public constant _HEX_SYMBOLS = "0123456789abcdef";

    constructor(string memory _name, string memory _symbol, string memory _baseURI)
        ComponentRegistry(_name, _symbol, _baseURI)
    {}


    /// @dev Checks token URI with two different methods.
    /// @param unitId Unit Id.
    function checkTokenURI(uint256 unitId) public view {
        bytes32 unitHash = mapUnits[unitId].unitHash;
        // Get the token URI with the implementation from GenericRegistry
        string memory str1 = tokenURI(unitId);

        // Get the token URI from the alternative implementation of OpenZeppelin
        uint256 value = uint256(unitHash);
        bytes memory buffer = new bytes(64);
        for (uint256 i = 63; i > 0; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        buffer[0] = _HEX_SYMBOLS[value & 0xf];
        string memory str2 = string(abi.encodePacked(baseURI, CID_PREFIX, buffer));

        // Compare two obtained tokenURI-s
        if (keccak256(abi.encodePacked((str1))) != keccak256(abi.encodePacked((str2)))) {
            revert DifferentTokenURIs();
        }
    }
}
