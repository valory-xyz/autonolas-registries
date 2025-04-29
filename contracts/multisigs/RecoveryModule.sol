// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {GnosisSafeStorage} from "@gnosis.pm/safe-contracts/contracts/examples/libraries/GnosisSafeStorage.sol";
import "hardhat/console.sol";

/// @dev Sage multi send interface
interface IMultiSend {
    /// @dev Sends multiple transactions and reverts all if one fails.
    /// @param transactions Encoded transactions. Each transaction is encoded as a packed bytes of
    ///                     operation has to be uint8(0) in this version (=> 1 byte),
    ///                     to as a address (=> 20 bytes),
    ///                     value as a uint256 (=> 32 bytes),
    ///                     payload length as a uint256 (=> 32 bytes),
    ///                     payload as bytes.
    ///                     see abi.encodePacked for more information on packed encoding
    /// @notice The code is for most part the same as the normal MultiSend (to keep compatibility),
    ///         but reverts if a transaction tries to use a delegatecall.
    /// @notice This method is payable as delegatecalls keep the msg.value from the previous call
    ///         If the calling method (e.g. execTransaction) received ETH this would revert otherwise
    function multiSend(bytes memory transactions) external payable;
}

/// @dev Safe multisig interface
interface IMultisig {
    enum Operation {Call, DelegateCall}

    /// @dev Allows to remove an owner from the Safe and update the threshold at the same time.
    ///      This can only be done via a Safe transaction.
    /// @notice Removes the owner `owner` from the Safe and updates the threshold to `_threshold`.
    /// @param prevOwner Owner that pointed to the owner to be removed in the linked list
    /// @param owner Owner address to be removed.
    /// @param _threshold New threshold.
    function removeOwner(address prevOwner, address owner, uint256 _threshold) external;

    /// @dev Allows to swap/replace an owner from the Safe with another address.
    ///      This can only be done via a Safe transaction.
    /// @notice Replaces the owner `oldOwner` in the Safe with `newOwner`.
    /// @param prevOwner Owner that pointed to the owner to be replaced in the linked list
    /// @param oldOwner Owner address to be replaced.
    /// @param newOwner New owner address.
    function swapOwner(address prevOwner, address oldOwner, address newOwner) external;

    /// @dev Allows a Module to execute a Safe transaction without any further confirmations.
    /// @param to Destination address of module transaction.
    /// @param value Ether value of module transaction.
    /// @param data Data payload of module transaction.
    /// @param operation Operation type of module transaction.
    function execTransactionFromModule(address to, uint256 value, bytes memory data, Operation operation) external
        returns (bool success);

    /// @dev Returns array of owners.
    /// @return Array of Safe owners.
    function getOwners() external view returns (address[] memory);
}

/// @dev Service Registry interface
interface IServiceRegistry {
    enum ServiceState {
        NonExistent,
        PreRegistration,
        ActiveRegistration,
        FinishedRegistration,
        Deployed,
        TerminatedBonded
    }

    /// @dev Gets the service instance from the map of services.
    /// @param serviceId Service Id.
    /// @return securityDeposit Registration activation deposit.
    /// @return multisig Service multisig address.
    /// @return configHash IPFS hashes pointing to the config metapayload.
    /// @return threshold Agent instance signers threshold.
    /// @return maxNumAgentInstances Total number of agent instances.
    /// @return numAgentInstances Actual number of agent instances.
    /// @return state Service state.
    function mapServices(uint256 serviceId) external view returns (uint96 securityDeposit, address multisig,
        bytes32 configHash, uint32 threshold, uint32 maxNumAgentInstances, uint32 numAgentInstances, ServiceState state);

    /// @dev Gets the owner of a specified service Id.
    /// @param serviceId Service Id.
    /// @return serviceOwner Service owner address.
    function ownerOf(uint256 serviceId) external view returns (address serviceOwner);
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Wrong state of a service.
/// @param state Service state.
/// @param serviceId Service Id.
error WrongServiceState(uint8 state, uint256 serviceId);

/// @dev Must be `DELEGATECALL` only.
error DelegatecallOnly();

/// @dev Nonce must be zero.
error ZeroNonceOnly();

/// @dev Modules must not be initialized.
error EmptyModulesOnly();

/// @dev Modules must not be duplicated.
error DuplicateModule();


/// @title RecoveryModule - Smart contract for Safe recovery module for scenarios when the access is lost
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract RecoveryModule is GnosisSafeStorage {
    event EnabledModule(address indexed module);
    event AccessRecovered(address indexed sender, uint256 indexed serviceId);

    // Resulting threshold is always one
    uint256 public constant THRESHOLD = 1;
    // Sentinel owners address
    address internal constant SENTINEL_OWNERS = address(0x1);

    // Address of the contract: used to ensure that the contract is only ever `DELEGATECALL`-ed
    address private immutable self;
    // Multisend contract address
    address public immutable multiSend;
    // Service Registry contract address
    address public immutable serviceRegistry;

    /// @dev RecoveryModule constructor.
    /// @param _multiSend Multisend contract address.
    /// @param _serviceRegistry Service Registry contract address.
    constructor (address _multiSend, address _serviceRegistry) {
        // Check for zero address
        if (_multiSend == address(0) || _serviceRegistry == address(0)) {
            revert ZeroAddress();
        }

        self = address(this);
        multiSend = _multiSend;
        serviceRegistry = _serviceRegistry;
    }

    /// @dev Enables self address as a multisig module.
    /// @notice This function must only be called via `DELEGATECALL` when a Safe contract is created.
    ///         For enabling module after multisig is created use direct native Safe enableModule() function call.
    function enableModule() external {
        // Check that the function is called via `DELEGATECALL`
        if (address(this) == self) {
            revert DelegatecallOnly();
        }

        // Check that the Safe proxy nonce is zero
        if (nonce > 0) {
            revert ZeroNonceOnly();
        }

        // Check that no modules are initialized
        if (modules[SENTINEL_OWNERS] != SENTINEL_OWNERS) {
            revert EmptyModulesOnly();
        }

        // Module cannot be added twice.
        if (modules[self] != address(0)) {
            revert DuplicateModule();
        }

        // Enable the module
        modules[self] = modules[SENTINEL_OWNERS];
        modules[SENTINEL_OWNERS] = self;

        emit EnabledModule(self);
    }

    /// @dev Recovers service multisig access for a specified service Id.
    /// @notice Only service owner is entitled to recover and become the ultimate multisig owner.
    /// @param serviceId Service Id.
    function recoverAccess(uint256 serviceId) external {
        // Get service owner
        address serviceOwner = IServiceRegistry(serviceRegistry).ownerOf(serviceId);

        // Check service owner
        if (msg.sender != serviceOwner) {
            revert OwnerOnly(msg.sender, serviceOwner);
        }

        // Check service state
        (, address multisig, , , , , IServiceRegistry.ServiceState state) = IServiceRegistry(serviceRegistry).mapServices(serviceId);
        if (state != IServiceRegistry.ServiceState.PreRegistration) {
            revert WrongServiceState(uint8(state), serviceId);
        }

        // Get multisig owners
        address[] memory owners = IMultisig(multisig).getOwners();

        // Remove all the owners and swap the last one with the service owner
        // Get number of owners
        uint256 numOwners = owners.length;
        // Each operation payload
        bytes memory payload;
        // Overall multi send data payload
        bytes memory msPayload;

        // In case of more than one agent instance address, we need to add all of them except for the first one,
        // after that swap the first agent instance with the current service owner, and then update the threshold
        if (numOwners > 1) {
            // Remove agent instances as original multisig owners and leave only the last one to swap later
            for (uint256 i = 0; i < numOwners - 1; ++i) {
                payload = abi.encodeCall(IMultisig.removeOwner, (SENTINEL_OWNERS, owners[i], THRESHOLD));
                msPayload = bytes.concat(msPayload, abi.encodePacked(IMultisig.Operation.Call, multisig, uint256(0),
                    payload.length, payload));
            }
        }

        // Swap the first agent instance address with the service owner address using the sentinel address as the previous one
        payload = abi.encodeCall(IMultisig.swapOwner, (SENTINEL_OWNERS, owners[numOwners - 1], msg.sender));
        // Concatenate multi send payload with the packed data of (operation, multisig address, value(0), payload length, payload)
        msPayload = bytes.concat(msPayload, abi.encodePacked(IMultisig.Operation.Call, multisig, uint256(0),
            payload.length, payload));

        // Multisend call to execute all the payloads
        payload = abi.encodeCall(IMultiSend.multiSend, (msPayload));

        // Execute module call
        IMultisig(multisig).execTransactionFromModule(multiSend, 0, payload, IMultisig.Operation.DelegateCall);

        emit AccessRecovered(msg.sender, serviceId);
    }
}
