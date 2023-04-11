// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./SafeGuard.sol";

interface ISafeGuard {
    /// @dev Initializes the Safe Guard instance by setting its owner.
    /// @param _owner Safe Guard owner address.
    function initialize (address _owner) external;
}

/// @dev Safe Guard already exists.
/// @param guard Safe Guard address.
error SafeGuardALreadyExists(address guard);

/// @dev The call must be strictly made via a delegatecall.
/// @param instance Guard Factory instance.
error DelegateCallOnly(address instance);

/// @dev Failed to create a Safe Guard contract for the caller.
/// @param caller Caller address.
error FailedCreateSafeGuard(address caller);

/// @title GuardFactory - Smart contract for deployment of Safe Guard contracts via the Factory functionality
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract GuardFactory {
    event ChangedGuard(address indexed guard);

    // keccak256("guard_manager.guard.address")
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;
    // The deployed factory instance address
    address public immutable factoryInstance;

    /// @dev Guard Factory constructor.
    constructor () {
        factoryInstance = address(this);
    }

    /// @dev Creates a safe guard that checks transactions before and after safe transaction executions.
    /// @notice This function must be called via a delegatecall only.
    /// @notice The function ultimately follows the standard Safe Guard creation routine where it sets the guard address
    ///         into its dedicated guard slot followed by the event emit defined in GuardManager contract.
    /// @param guardOwner The owner of the created Safe Guard.
    function createGuardForSafe(address guardOwner) external {
        // Check for the delegatecall
        if (address(this) == factoryInstance) {
            revert DelegateCallOnly(factoryInstance);
        }

        // Check that the guard slot is empty
        bytes32 slot = GUARD_STORAGE_SLOT;
        address guard;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            guard := sload(slot)
        }
        if (guard != address(0)) {
            revert SafeGuardALreadyExists(guard);
        }

        // Bytecode of the Safe Guard contract
        bytes memory bytecode = abi.encodePacked(type(SafeGuard).creationCode);
        // Supposedly the address(this) is the unique address of a safe contract that calls this guard creation function
        // Supposedly the same Safe contract is not going to create a guard, delete it and try to create again
        // in the same block. Thus, the combination of the Safe address and the block timestamp will be unique
        bytes32 salt = keccak256(abi.encodePacked(address(this), block.timestamp));

        // Create Safe Guard instance and write it into its designated slot
        // solhint-disable-next-line no-inline-assembly
        assembly {
            guard := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        // Check for the guard creation
        if(guard == address(0)) {
            revert FailedCreateSafeGuard(address(this));
        }
        // Initialize the guard by setting its owner
        ISafeGuard(guard).initialize(guardOwner);
        // Write guard address into the guard slot
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, guard)
        }
        emit ChangedGuard(guard);
    }
}