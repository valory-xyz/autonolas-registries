// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Safe Proxy Factory interface extracted from the mainnet: https://etherscan.io/address/0xa6b71e26c5e0845f74c812102ca7114b6a896ab2#code#F2#L61
interface ISafeProxyFactory {
    /// @dev Allows to create new proxy contact and execute a message call to the new proxy within one transaction.
    /// @param _singleton Address of singleton contract.
    /// @param initializer Payload for message call sent to new proxy contract.
    /// @param saltNonce Nonce that will be used to generate the salt to calculate the address of the new proxy contract.
    function createProxyWithNonce(
        address _singleton,
        bytes memory initializer,
        uint256 saltNonce
    ) external returns (address proxy);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided incorrect data length.
/// @param expected Expected minimum data length.
/// @param provided Provided data length.
error IncorrectDataLength(uint256 expected, uint256 provided);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @title SafeMultisigWithRecoveryModule - Smart contract for Safe multisig creation with the recovery module
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract SafeMultisigWithRecoveryModule {
    // Selector of the Safe setup function
    bytes4 public constant SAFE_SETUP_SELECTOR = 0xb63e800d;
    // Encoded selector of the Recovery module enableModule function
    bytes4 public constant ENABLE_MODULE_SELECTOR = 0x24292962;
    // Default data size for several Safe Factory params without payload: address + uint256 = 20 + 32 = 52 (bytes)
    uint256 public constant DEFAULT_DATA_LENGTH = 52;

    // Safe contract address
    address public immutable safe;
    // Safe Factory contract address
    address public immutable safeProxyFactory;
    // Recovery module address
    address public immutable recoveryModule;

    // Reentrancy lock
    uint256 internal _locked = 1;

    /// @dev SafeMultisigWithRecoveryModule constructor.
    /// @param _safe Safe contract address.
    /// @param _safeProxyFactory Safe proxy factory contract address.
    /// @param _recoveryModule Recovery module address.
    constructor (address _safe, address _safeProxyFactory, address _recoveryModule) {
        // Check for zero addresses
        if (_safe == address(0) || _safeProxyFactory == address(0) || _recoveryModule == address(0)) {
            revert ZeroAddress();
        }

        safe = _safe;
        safeProxyFactory = _safeProxyFactory;
        recoveryModule = _recoveryModule;
    }

    /// @dev Creates a Safe multisig.
    /// @param owners Set of multisig owners.
    /// @param threshold Number of required confirmations for a multisig transaction.
    /// @param data Decoded data related to the creation of a chosen multisig.
    /// @return multisig Address of a created multisig.
    function create(
        address[] memory owners,
        uint256 threshold,
        bytes memory data
    ) external returns (address multisig) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        address fallbackHandler;
        uint256 nonce;

        uint256 dataLength = data.length;
        if (dataLength > 0) {
            // Check for correct data length
            if (dataLength != DEFAULT_DATA_LENGTH) {
                revert IncorrectDataLength(DEFAULT_DATA_LENGTH, data.length);
            }

            // Decode fallback handler and nonce
            (fallbackHandler, nonce) = abi.decode(data, (address, uint256));
        }

        // Convert enableModule selector into bytes
        bytes memory payload = bytes.concat(ENABLE_MODULE_SELECTOR);

        // Encode the gnosis setup function parameters
        bytes memory safeParams = abi.encodeWithSelector(SAFE_SETUP_SELECTOR, owners, threshold, recoveryModule,
            payload, fallbackHandler, address(0), 0, payable(address(0)));

        // Create a gnosis safe multisig via the proxy factory
        multisig = ISafeProxyFactory(safeProxyFactory).createProxyWithNonce(safe, safeParams, nonce);

        _locked = 1;
    }
}