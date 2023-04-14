// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./SafeGuard.sol";

// Safe Guard interface
interface ISafeGuard {
    /// @dev Initializes the Safe Guard instance by setting its owner.
    /// @param _owner Safe Guard owner address.
    function initialize (address _owner) external;
}

// Gnosis Safe interface
interface IGnosisSafe {
    /// @dev Returns array of owners.
    /// @return Array of Safe owners.
    function getOwners() external view returns (address[] memory);
}

/// @dev Safe Guard already exists.
/// @param guard Safe Guard address.
error SafeGuardALreadyExists(address guard);

/// @dev The call must be strictly made via a delegatecall.
/// @param instance Guard Factory instance.
error DelegateCallOnly(address instance);

/// @dev Number of owners is insufficient.
/// @param provided Provided number of owners.
/// @param expected Minimum expected number of owners.
error InsufficientNumberOfOwners(uint256 provided, uint256 expected);

/// @dev Provided incorrect data length.
/// @param expected Expected minimum data length.
/// @param provided Provided data length.
error IncorrectPayloadLength(uint256 expected, uint256 provided);

/// @dev Payload delegatecall transaction failed.
/// @param payload Payload data.
error PayloadExecFailed(bytes payload);

/// @dev Failed to create a Safe Guard contract for the caller.
/// @param caller Caller address.
error FailedCreateSafeGuard(address caller);

/// @title SafeGuardFactory - Smart contract for deployment of Safe Guard contracts via the Factory functionality
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract SafeGuardFactory {
    event ChangedGuard(address indexed guard);

    // keccak256("guard_manager.guard.address")
    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;
    // Default payload length to be processed via a delegatecall
    // If not empty, it has to contain at least an address (20 bytes) and a call signature (4 bytes)
    uint256 public constant DEFAULT_PAYLOAD_LENGTH = 24;
    // The deployed factory instance address
    address public immutable factoryInstance;

    /// @dev Guard Factory constructor.
    constructor () {
        factoryInstance = address(this);
    }

    /// @dev Creates a safe guard that checks transactions before and after safe transaction executions.
    /// @notice This function must be called via a delegatecall only.
    /// @notice The function follows the standard Safe Guard creation routine where it sets the guard address
    ///         into its dedicated guard slot followed by the event emit defined in the GuardManager contract.
    /// @notice A multisig has to have at least three owners to set up a safe guard.
    /// @param payload Custom payload containing at least address and a function signature for a delegatecall.
    function createSafeGuard(bytes memory payload) external {
        // Check for the delegatecall
        if (address(this) == factoryInstance) {
            revert DelegateCallOnly(factoryInstance);
        }

        // Get the number of Safe owners
        address[] memory owners = IGnosisSafe(address(this)).getOwners();
        // Check for the number of owners
        uint256 numOwners = owners.length;
        if (numOwners < 3) {
            revert InsufficientNumberOfOwners(numOwners, 3);
        }

        // Check for the payload length
        uint256 payloadLength = payload.length;
        if (payloadLength > 0 && payloadLength < DEFAULT_PAYLOAD_LENGTH) {
            revert IncorrectPayloadLength(DEFAULT_PAYLOAD_LENGTH, payloadLength);
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

        // Execute the payload, if provided
        // The payload must be executed before the safe guard is set, as the payload could potentially break the guard
        if (payloadLength > 0) {
            address target;
            bool success;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                // First 20 bytes of the payload is address
                target := mload(add(payload, 20))
                // Offset 52 bytes from the payload start: initial 32 bytes plus the target address 20 bytes
                success := delegatecall(gas(), target, add(payload, 52), mload(payload), 0, 0)
            }
            if (!success) {
                revert PayloadExecFailed(payload);
            }
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

        // Initialize the guard by setting its owner as the last one from the list of owners
        ISafeGuard(guard).initialize(owners[numOwners - 1]);
        // Write guard address into the guard slot
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, guard)
        }
        emit ChangedGuard(guard);
    }
}