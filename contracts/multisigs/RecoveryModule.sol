// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {GnosisSafeStorage} from "@gnosis.pm/safe-contracts/contracts/examples/libraries/GnosisSafeStorage.sol";

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

    /// @dev Allows to add a new owner to the Safe and update the threshold at the same time.
    ///      This can only be done via a Safe transaction.
    /// @notice Adds the owner `owner` to the Safe and updates the threshold to `_threshold`.
    /// @param owner New owner address.
    /// @param _threshold New threshold.
    function addOwnerWithThreshold(address owner, uint256 _threshold) external;

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

    /// @dev Returns multisig threshold.
    /// @return Multisig threshold.
    function getThreshold() external view returns (uint256);
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

    /// @dev Gets service agent instances.
    /// @param serviceId ServiceId.
    /// @return numAgentInstances Number of agent instances.
    /// @return agentInstances Pre-allocated list of agent instance addresses.
    function getAgentInstances(uint256 serviceId) external view returns (uint256 numAgentInstances, address[] memory agentInstances);
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Only `registry` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param registry Required sender address as a registry.
error RegistryOnly(address sender, address registry);

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

/// @dev Caught reentrancy violation.
error ReentrancyGuard();


/// @title RecoveryModule - Smart contract for Safe recovery module for scenarios when the access is lost
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract RecoveryModule is GnosisSafeStorage {
    event EnabledModule(address indexed module);
    event AccessRecovered(address indexed serviceOwner, uint256 indexed serviceId);
    event ServiceRedeployed(address indexed serviceOwner, uint256 indexed serviceId, address[] owners, uint256 threshold);

    // Resulting recover threshold is always one
    uint256 public constant RECOVER_THRESHOLD = 1;
    // Default data length for service redeployment: encoded uint256 = 32 (bytes)
    uint256 public constant DEFAULT_DATA_LENGTH = 32;
    // Sentinel address
    address internal constant SENTINEL_ADDRESS = address(0x1);

    // Address of the contract: used to ensure that the contract is only ever `DELEGATECALL`-ed
    address private immutable self;
    // Multisend contract address
    address public immutable multiSend;
    // Service Registry contract address
    address public immutable serviceRegistry;

    // Reentrancy lock
    uint256 internal _locked = 1;

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

        // Check that the Safe proxy nonce is zero: able to execute only during the multisig initialization
        if (nonce > 0) {
            revert ZeroNonceOnly();
        }

        // Enable the module
        modules[self] = modules[SENTINEL_ADDRESS];
        modules[SENTINEL_ADDRESS] = self;

        emit EnabledModule(self);
    }

    /// @dev Recovers service multisig access for a specified service Id.
    /// @notice Only service owner is entitled to recover and become the ultimate multisig owner.
    /// @param serviceId Service Id.
    function recoverAccess(uint256 serviceId) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

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

        // Check for zero address to prevent execution before initial service is deployment
        if (multisig == address(0)) {
            revert ZeroAddress();
        }

        // Get multisig owners
        address[] memory multisigOwners = IMultisig(multisig).getOwners();

        // Remove all the owners and swap the last one with the service owner
        // Get number of owners
        uint256 numOwners = multisigOwners.length;
        // Each operation payload
        bytes memory payload;
        // Overall multi send data payload
        bytes memory msPayload;

        // In case of more than one agent instance address, we need to add all of them except for the first one,
        // after that swap the first agent instance with the current service owner, and then update the threshold
        // Remove agent instances as original multisig owners and leave only the last one to swap later
        for (uint256 i = 0; i < numOwners - 1; ++i) {
            payload = abi.encodeCall(IMultisig.removeOwner, (SENTINEL_ADDRESS, multisigOwners[i], RECOVER_THRESHOLD));
            msPayload = bytes.concat(msPayload, abi.encodePacked(IMultisig.Operation.Call, multisig, uint256(0),
                payload.length, payload));
        }

        // Swap the first agent instance address with the service owner address using the sentinel address as the previous one
        payload = abi.encodeCall(IMultisig.swapOwner, (SENTINEL_ADDRESS, multisigOwners[numOwners - 1], msg.sender));
        // Concatenate multi send payload with the packed data of (operation, multisig address, value(0), payload length, payload)
        msPayload = bytes.concat(msPayload, abi.encodePacked(IMultisig.Operation.Call, multisig, uint256(0),
            payload.length, payload));

        // Multisend call to execute all the payloads
        payload = abi.encodeCall(IMultiSend.multiSend, (msPayload));

        // Execute module call
        IMultisig(multisig).execTransactionFromModule(multiSend, 0, payload, IMultisig.Operation.DelegateCall);

        emit AccessRecovered(msg.sender, serviceId);

        _locked = 1;
    }

    /// @dev Updates and/or verifies the existent gnosis safe multisig for changed owners and threshold.
    /// @notice This function operates with existent multisig proxy that is requested to be updated in terms of
    ///         the set of owners' addresses and the threshold. There are two scenarios possible:
    ///         1. The multisig proxy is already updated before reaching this function. Then the multisig address
    ///            must be passed as a payload such that its owners and threshold are verified against those specified
    ///            in the argument list.
    ///         2. The multisig proxy is not yet updated. Then the service Id must be passed in a packed bytes of
    ///            data in order to update multisig owners to match service agent instances. The updated multisig
    ///            proxy is then going to be verified with the provided set of owners' addresses and the threshold.
    ///         Note that owners' addresses in the multisig are stored in reverse order compared to how they were added:
    ///         https://etherscan.io/address/0xd9db270c1b5e3bd161e8c8503c55ceabee709552#code#F6#L56
    /// @param multisigOwners Set of updated multisig owners to verify against.
    /// @param threshold Updated number for multisig transaction confirmations.
    /// @param data Packed data containing multisig service Id.
    /// @return multisig Multisig address.
    function create(
        address[] memory multisigOwners,
        uint256 threshold,
        bytes memory data
    ) external returns (address multisig) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check that msg.sender is the Service Registry contract
        // This means that the create() call is authorized by the service owner
        if (msg.sender != serviceRegistry) {
            revert RegistryOnly(msg.sender, serviceRegistry);
        }

        // Check for the correct data length
        uint256 dataLength = data.length;
        if (dataLength != DEFAULT_DATA_LENGTH) {
            revert IncorrectDataLength(DEFAULT_DATA_LENGTH, dataLength);
        }

        // Get number of owners
        uint256 numOwners = multisigOwners.length;
        // Each operation payload
        bytes memory payload;
        // Overall multi send data payload
        bytes memory msPayload;

        // Decode the service Id
        uint256 serviceId = abi.decode(data, (uint256));

        // Get service owner
        address serviceOwner = IServiceRegistry(serviceRegistry).ownerOf(serviceId);
        uint256 checkThreshold;
        // Get service multisig
        (, multisig, , checkThreshold, , , ) = IServiceRegistry(serviceRegistry).mapServices(serviceId);

        // Check for zero address to prevent execution during initial service deployment
        if (multisig == address(0)) {
            revert ZeroAddress();
        }

        // Check service threshold
        if (checkThreshold != threshold) {
            revert WrongThreshold(checkThreshold, threshold);
        }

        // Check owners vs agent instances: this prevents modification of another service Id via a create() function
        (, address[] memory agentInstances) = IServiceRegistry(serviceRegistry).getAgentInstances(serviceId);
        if (numOwners != agentInstances.length) {
            revert WrongNumOwners(agentInstances.length, numOwners);
        }
        for (uint256 i = 0; i < numOwners; ++i) {
            if (multisigOwners[i] != agentInstances[i]) {
                revert WrongOwner(multisigOwners[i]);
            }
        }

        // Get multisig owners
        address[] memory checkOwners = IMultisig(multisig).getOwners();

        // If service owner is still the only multisig owner, multisig must be updated with provided owners list
        if (checkOwners.length == 1 && checkOwners[0] == serviceOwner) {
            // Add agent instances as multisig owners without changing threshold
            for (uint256 i = 0; i < numOwners; ++i) {
                payload = abi.encodeCall(IMultisig.addOwnerWithThreshold, (multisigOwners[i], RECOVER_THRESHOLD));
                msPayload = bytes.concat(msPayload, abi.encodePacked(IMultisig.Operation.Call, multisig, uint256(0),
                    payload.length, payload));
            }

            // Remove service owner address using the first agent instance address as the previous one, and update threshold
            payload = abi.encodeCall(IMultisig.removeOwner, (multisigOwners[0], serviceOwner, threshold));
            // Concatenate multi send payload with the packed data of (operation, multisig address, value(0), payload length, payload)
            msPayload = bytes.concat(msPayload, abi.encodePacked(IMultisig.Operation.Call, multisig, uint256(0),
                payload.length, payload));

            // Multisend call to execute all the payloads
            payload = abi.encodeCall(IMultiSend.multiSend, (msPayload));

            // Execute module call
            IMultisig(multisig).execTransactionFromModule(multiSend, 0, payload, IMultisig.Operation.DelegateCall);
        }

        // Get multisig owners and threshold
        checkOwners = IMultisig(multisig).getOwners();
        checkThreshold = IMultisig(multisig).getThreshold();

        // Verify updated multisig proxy for provided owners and threshold
        if (threshold != checkThreshold) {
            revert WrongThreshold(checkThreshold, threshold);
        }
        if (numOwners != checkOwners.length) {
            revert WrongNumOwners(checkOwners.length, numOwners);
        }
        // The owners' addresses in the multisig itself are stored in reverse order compared to how they were added:
        // https://etherscan.io/address/0xd9db270c1b5e3bd161e8c8503c55ceabee709552#code#F6#L56
        // Thus, the check must be carried out accordingly.
        for (uint256 i = 0; i < numOwners; ++i) {
            if (multisigOwners[i] != checkOwners[numOwners - i - 1]) {
                revert WrongOwner(multisigOwners[i]);
            }
        }

        emit ServiceRedeployed(serviceOwner, serviceId, multisigOwners, threshold);

        _locked = 1;
    }
}
