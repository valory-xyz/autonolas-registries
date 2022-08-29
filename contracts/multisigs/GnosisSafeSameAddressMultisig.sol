// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

// Gnosis Safe Master Copy interface extracted from the mainnet: https://etherscan.io/address/0xd9db270c1b5e3bd161e8c8503c55ceabee709552#code#F6#L126
interface IGnosisSafe {
    /// @dev Gets set of owners.
    /// @return Set of Safe owners.
    function getOwners() external view returns (address[] memory);

    /// @dev Gets threshold.
    /// @return Threshold
    function getThreshold() external view returns (uint256);
}

/// @dev Provided incorrect data length.
/// @param expected Expected minimum data length.
/// @param provided Provided data length.
error IncorrectDataLength(uint256 expected, uint256 provided);

/// @dev Provided incorrect multisig threshold.
/// @param expected Expected threshold.
/// @param provided Provided threshold.
error WrongThreshold(uint256 expected, uint256 provided);

/// @dev Provided incorrect number of owners.
/// @param expected Expected number of owners.
/// @param provided Provided number of owners.
error WrongNumOwners(uint256 expected, uint256 provided);

/// @dev Provided incorrect multisig owner.
/// @param provided Provided owner address.
error WrongOwner(address provided);

/// @title Gnosis Safe Same Address - Smart contract for Gnosis Safe verification of an already existent multisig address.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract GnosisSafeSameAddressMultisig {
    // Default data size to be parsed as an address of a Gnosis Safe multisig proxy address
    uint256 public constant DEFAULT_DATA_LENGTH = 20;

    /// @dev Verifies the existent gnosis safe multisig for changed owners and threshold.
    /// @notice The multisig is supposedly updated before reaching this step such that new multisig is not created.
    ///         Note that the order of owners' addresses in the multisig is in reverse order, see comments below.
    /// @param owners Set of multisig owners.
    /// @param threshold Number of required confirmations for a multisig transaction.
    /// @param data Packed data containing address of an existent gnosis safe multisig.
    /// @return multisig Address of a multisig (proxy).
    function create(
        address[] memory owners,
        uint256 threshold,
        bytes memory data
    ) external view returns (address multisig)
    {
        // Check for the correct data length
        if (data.length != DEFAULT_DATA_LENGTH) {
            revert IncorrectDataLength(DEFAULT_DATA_LENGTH, data.length);
        }

        // Read the proxy multisig address (20 bytes)
        assembly {
            multisig := mload(add(data, DEFAULT_DATA_LENGTH))
        }

        // Get the provided multisig owners and threshold
        address[] memory checkOwners = IGnosisSafe(multisig).getOwners();
        uint256 checkThreshold = IGnosisSafe(multisig).getThreshold();

        // Verify the multisig for owners and threshold
        if (threshold != checkThreshold) {
            revert WrongThreshold(checkThreshold, threshold);
        }
        uint256 numOwners = owners.length;
        if (numOwners != checkOwners.length) {
            revert WrongNumOwners(checkOwners.length, numOwners);
        }
        // The owners' addresses in the multisig itself are stored in reverse order compared to how they were added:
        // https://etherscan.io/address/0xd9db270c1b5e3bd161e8c8503c55ceabee709552#code#F6#L56
        // Thus, the check must be carried out accordingly.
        for (uint256 i = 0; i < numOwners; ++i) {
            if (owners[i] != checkOwners[numOwners - i - 1]) {
                revert WrongOwner(owners[i]);
            }
        }
    }
}