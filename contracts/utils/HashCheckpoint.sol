// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @title Hash Checkpoint - Smart contract for checkpointing IPFS hashes on-chain
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract HashCheckpoint {
    error OwnerOnly(address sender, address owner);
    error ZeroAddress();
    error ZeroValue();
    event OwnerUpdated(address indexed owner);
    event ManagerUpdated(address indexed manager);
    event BaseURIChanged(string baseURI);
    event HashUpdated(address indexed emitter, bytes32 hash);

    // Owner address
    address public owner;
    // Base URI
    string public baseURI;
    // To better understand the CID anatomy, please refer to: https://proto.school/anatomy-of-a-cid/05
    // CID = <multibase_encoding>multibase_encoding(<cid-version><multicodec><multihash-algorithm><multihash-length><multihash-hash>)
    // CID prefix = <multibase_encoding>multibase_encoding(<cid-version><multicodec><multihash-algorithm><multihash-length>)
    // to complement the multibase_encoding(<multihash-hash>)
    // multibase_encoding = base16 = "f"
    // cid-version = version 1 = "0x01"
    // multicodec = dag-pb = "0x70"
    // multihash-algorithm = sha2-256 = "0x12"
    // multihash-length = 256 bits = "0x20"
    string public constant CID_PREFIX = "f01701220";
    // Map of address => latest IPFS hash
    mapping (address => bytes32) public latestHashes;

    /// @dev Hash checkpoint constructor.
    /// @param _baseURI Hash registry base URI.
    constructor(string memory _baseURI) {
        baseURI = _baseURI;
        owner = msg.sender;
    }

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

    /// @dev Emits a hash
    /// @param hash The hash to be emitted.
    function checkpoint(bytes32 hash) external virtual {
        latestHashes[msg.sender] = hash;
        emit HashUpdated(msg.sender, hash);
    }

    // Open sourced from: https://stackoverflow.com/questions/67893318/solidity-how-to-represent-bytes32-as-string
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

    /// @dev Latest hash
    /// @notice Expected multicodec: dag-pb; hashing function: sha2-256, with base16 encoding and leading CID_PREFIX removed.
    /// @param _address The address that provided the hash.
    /// @return Latest hash string.
    function latestHash(address _address) public view virtual returns (string memory) {
        bytes32 latest_hash = latestHashes[_address];
        // Parse 2 parts of bytes32 into left and right hex16 representation, and concatenate into string
        // adding the base URI and a cid prefix for the full base16 multibase prefix IPFS hash representation
        return string(abi.encodePacked(CID_PREFIX, _toHex16(bytes16(latest_hash)),
            _toHex16(bytes16(latest_hash << 128))));
    }

    /// @dev Latest hash URI
    /// @notice Expected multicodec: dag-pb; hashing function: sha2-256, with base16 encoding and leading CID_PREFIX removed.
    /// @param _address The address that provided the hash.
    /// @return Latest hash URI string.
    function latestHashURI(address _address) public view virtual returns (string memory) {
        bytes32 latest_hash = latestHashes[_address];
        // Parse 2 parts of bytes32 into left and right hex16 representation, and concatenate into string
        // adding the base URI and a cid prefix for the full base16 multibase prefix IPFS hash representation
        return string(abi.encodePacked(baseURI, CID_PREFIX, _toHex16(bytes16(latest_hash)),
            _toHex16(bytes16(latest_hash << 128))));
    }
}
