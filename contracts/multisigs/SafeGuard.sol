// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @dev The contract instance is already initialized.
/// @param owner Contract instance owner address.
error Initialized(address owner);

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Guarded condition is detected.
error Guarded();

/// @title SafeGuard - Smart contract for Gnosis Safe Guard functionality
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract SafeGuard {
    event OwnerUpdated(address indexed owner);

    // Safe enum
    enum Operation {Call, DelegateCall}
    // Contract owner
    address public owner;

    /// @dev Initializes the Safe Guard instance by setting its owner.
    /// @param _owner Safe Guard owner address.
    function initialize (address _owner) external {
        if (owner != address(0)) {
            revert Initialized(owner);
        }

        // Check for the zero address
        if (_owner == address(0)) {
            revert ZeroAddress();
        }
        owner = _owner;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
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

    /// @dev Check transaction function implementation before the Safe's execute function call.
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures,
        address msgSender
    ) external {
        // Right now we are blocking all the ETH funds transfer
        if (value > 0) {
            revert Guarded();
        }
    }

    /// @dev Check transaction function implementation after the Safe's execute function call.
    function checkAfterExecution(bytes32 txHash, bool success) external {

    }
}