// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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

// Polymarket Deposit Wallet interface: https://polygonscan.com/address/0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB#code
interface IDepositWallet {
    /// @dev Returns the EOA address that owns the deposit wallet.
    /// @notice The owner is enforced as an externally owned account by the wallet's
    ///         pure-ECDSA `_erc1271IsValidSignatureNowCalldata` override; smart contracts
    ///         (including Safes) cannot be owners. The owner signs `WALLET` batches via the
    ///         Polymarket relayer and CLOB orders via ERC-7739-wrapped POLY_1271 signatures.
    function owner() external view returns (address);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Provided incorrect data length.
/// @param expected Expected data length.
/// @param provided Provided data length.
error IncorrectDataLength(uint256 expected, uint256 provided);

/// @dev Provided incorrect number of owners.
/// @param expected Expected number of owners.
/// @param provided Provided number of owners.
error WrongNumOwners(uint256 expected, uint256 provided);

/// @dev Deposit wallet has no code at the provided address.
/// @param depositWallet Deposit wallet address.
error DepositWalletNotDeployed(address depositWallet);

/// @dev Provided incorrect deposit wallet owner.
/// @param expected Expected deposit wallet owner.
/// @param provided Provided deposit wallet owner.
error WrongDepositWalletOwner(address expected, address provided);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @title SafeAndDepositWalletCreator - Smart contract for Safe multisig creation linked to a Polymarket deposit wallet
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @notice The Safe multisig is the OLAS service multisig (governance, custody, ERC-8004 agent wallet, RecoveryModule).
///         The Polymarket deposit wallet is a separate per-service trading account, deployed out-of-band by Polymarket's
///         relayer with the agent-instance EOA as its owner. The two are independent peers bridged by the agent-instance
///         EOA: the EOA is one of the Safe's owners and the deposit wallet's sole EOA owner. The deposit wallet cannot
///         be owned by the Safe because its `_erc1271IsValidSignatureNowCalldata` is pure ECDSA, foreclosing
///         smart-contract ownership.
///         Pre-deploy ordering: Pearl client predicts the deposit wallet address off-chain (deterministic CREATE2 from
///         the agent-instance EOA), HTTP-calls Polymarket's relayer to deploy the deposit wallet via
///         `DepositWalletFactory.deploy` (operator-gated, no on-chain meta-tx variant available), then submits
///         `ServiceManager.deploy(serviceId, this, data)` which calls this contract's `create()` to deploy the Safe with
///         RecoveryModule enabled atomically and verify the pre-deployed deposit wallet.
contract SafeAndDepositWalletCreator {
    event MultisigCreated(address indexed multisig, address indexed agentInstance);
    event DepositWalletLinked(address indexed multisig, address indexed depositWallet);

    // Selector of the Safe setup function
    bytes4 public constant SAFE_SETUP_SELECTOR = 0xb63e800d;
    // Encoded selector of the Recovery module enableModule function
    bytes4 public constant ENABLE_MODULE_SELECTOR = 0x24292962;
    // Default data length: address + uint256 + address = 3 full slots = 96 (bytes)
    uint256 public constant DEFAULT_DATA_LENGTH = 96;

    // Safe contract address
    address public immutable safe;
    // Safe Factory contract address
    address public immutable safeProxyFactory;
    // Recovery module address
    address public immutable recoveryModule;
    // Polymarket Deposit Wallet Factory address
    address public immutable depositWalletFactory;

    // Multisig address => linked deposit wallet address
    mapping(address => address) public mapMultisigDepositWallets;

    // Reentrancy lock
    uint256 internal _locked = 1;

    /// @dev SafeAndDepositWalletCreator constructor.
    /// @param _safe Safe contract address.
    /// @param _safeProxyFactory Safe proxy factory contract address.
    /// @param _recoveryModule Recovery module address.
    /// @param _depositWalletFactory Polymarket Deposit Wallet Factory address.
    constructor (
        address _safe,
        address _safeProxyFactory,
        address _recoveryModule,
        address _depositWalletFactory
    ) {
        // Check for zero addresses
        if (_safe == address(0) || _safeProxyFactory == address(0) || _recoveryModule == address(0)
            || _depositWalletFactory == address(0)) {
            revert ZeroAddress();
        }

        safe = _safe;
        safeProxyFactory = _safeProxyFactory;
        recoveryModule = _recoveryModule;
        depositWalletFactory = _depositWalletFactory;
    }

    /// @dev Creates a Safe multisig with Recovery Module enabled atomically and links it to a pre-deployed deposit wallet.
    /// @notice Number of owners is required to be 1: the agent-instance EOA that bridges the Safe and the deposit wallet.
    ///         The deposit wallet must already be deployed by Polymarket's relayer at the address provided in `data`.
    /// @param owners Set of multisig owners. Must contain a single agent-instance EOA matching the deposit wallet owner.
    /// @param threshold Number of required confirmations for a multisig transaction.
    /// @param data Encoded `(address fallbackHandler, uint256 saltNonce, address depositWallet)` payload.
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

        // Single owner is required: the agent-instance EOA that owns the deposit wallet
        if (owners.length != 1) {
            revert WrongNumOwners(1, owners.length);
        }

        // Check for correct data length
        uint256 dataLength = data.length;
        if (dataLength != DEFAULT_DATA_LENGTH) {
            revert IncorrectDataLength(DEFAULT_DATA_LENGTH, dataLength);
        }

        // Decode fallback handler, salt nonce and pre-deployed deposit wallet address
        (address fallbackHandler, uint256 saltNonce, address depositWallet) =
            abi.decode(data, (address, uint256, address));

        // Verify the deposit wallet is deployed at the expected address
        if (depositWallet.code.length == 0) {
            revert DepositWalletNotDeployed(depositWallet);
        }

        // Verify the deposit wallet owner matches the agent-instance EOA: this is the bridge invariant linking the
        // two peers and the load-bearing check enforced by Polymarket's pure-ECDSA `_erc1271IsValidSignatureNowCalldata`.
        // Combined with code.length, the owner() lookup also implicitly authenticates the deposit wallet shape:
        // a non-DW contract at the predicted address would either lack `owner()` (revert) or return a non-matching
        // address (revert). A bytecode-hash check is not feasible because Polymarket's wallets use solady's
        // `deployDeterministicERC1967WithImmutableArgs` variant, which bakes per-wallet immutable args
        // (factory, walletId) into the proxy bytecode — so each wallet has a distinct runtime codehash.
        address depositWalletOwner = IDepositWallet(depositWallet).owner();
        if (depositWalletOwner != owners[0]) {
            revert WrongDepositWalletOwner(owners[0], depositWalletOwner);
        }

        // Convert enableModule selector into bytes
        bytes memory payload = bytes.concat(ENABLE_MODULE_SELECTOR);

        // Encode the gnosis setup function parameters
        bytes memory safeParams = abi.encodeWithSelector(SAFE_SETUP_SELECTOR, owners, threshold, recoveryModule,
            payload, fallbackHandler, address(0), 0, payable(address(0)));

        // Create a gnosis safe multisig via the proxy factory
        multisig = ISafeProxyFactory(safeProxyFactory).createProxyWithNonce(safe, safeParams, saltNonce);

        // Record the on-chain link such that third parties (8004 indexers, dashboards, traders) can discover a
        // service's deposit wallet from its Safe without trusting off-chain configuration
        mapMultisigDepositWallets[multisig] = depositWallet;

        emit MultisigCreated(multisig, owners[0]);
        emit DepositWalletLinked(multisig, depositWallet);

        _locked = 1;
    }
}
