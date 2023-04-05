// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "hardhat/console.sol";

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
contract SafeGuard {
    event OwnerUpdated(address indexed owner);
    event ChangedGuard(address guard);
    // keccak256("guard_manager.guard.address")
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    // Safe enum
    enum Operation {Call, DelegateCall}

    // Contract owner
    address public owner;

    /// @dev Guard constructor.
    /// @param _owner Guard owner address.
    constructor (address _owner) {
        owner = _owner;
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

    /// @dev Sets a guard that checks transactions before and execution.
    /// @notice This function copies the corresponding Safe function such that it is correctly initialized.
    /// @param guard The address of the guard to be used or the 0 address to disable the guard.
    function setGuardForSafe(address guard) external {
        bytes32 slot = GUARD_STORAGE_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, guard)
        }
        emit ChangedGuard(guard);
    }
}