// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title MockOperatorContract - Smart contract for mocking the operator contract functionality to verify hashes
contract MockOperatorContract {
    mapping(bytes32 => bool) public approvedHashes;

    function approveHash(bytes32 hash) external {
        approvedHashes[hash] = true;
    }

    function isValidSignature(bytes32 hash, bytes memory) external view returns (bytes4 magicValue) {
        if (approvedHashes[hash]) {
            magicValue = 0x1626ba7e;
        }
    }
}