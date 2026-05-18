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

// Polymarket DepositWalletFactory interface (verified source at
// https://polygonscan.com/address/0x00000000000Fb5C9ADea0298D729A0CB3823Cc07#code).
interface IDepositWalletFactory {
    /// @dev Computes the deterministic CREATE2 address that `deploy(...)` would assign for the supplied
    ///      `(_implementation, _id)` pair. Mirrors solady's `LibClone.predictDeterministicAddressERC1967` over
    ///      `salt = keccak256(abi.encode(factory, _id))` and `initCodeHashERC1967(_implementation, encode(factory, _id))`.
    /// @param _implementation Deposit wallet logic implementation the factory should clone.
    /// @param _id Wallet identifier. Relayer convention is `bytes32(uint256(uint160(ownerEOA)))`.
    /// @return Predicted deposit wallet address.
    function predictWalletAddress(address _implementation, bytes32 _id) external view returns (address);
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

/// @dev Provided deposit wallet address does not match the factory's canonical CREATE2 prediction.
/// @param expected Predicted deposit wallet address from `DepositWalletFactory.predictWalletAddress`.
/// @param provided Provided deposit wallet address.
error WrongDepositWalletAddress(address expected, address provided);

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
    // Polymarket Deposit Wallet implementation pinned at deploy time
    // Chain-specific (Polygon: `0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB`, Amoy: `0x50a88fE9…D7Fbd`); a future
    // Polymarket impl rotation would require redeploying (or proxy-upgrading) this creator.
    address public immutable depositWalletImplementation;

    // Multisig address => linked deposit wallet address.
    // Entries are inserted unconditionally by any `create()` caller — the contract itself does not gate writes
    // (matches the open-caller convention of `SafeMultisigWithRecoveryModule` and `PolySafeCreatorWithRecoveryModule`).
    // Consumers reading this mapping for OLAS-service-multisig provenance MUST cross-validate against the canonical
    // `ServiceRegistry`: confirm `ServiceRegistry.mapMultisigs(<creator>) == true` and resolve the multisig back to
    // an existing service via the registry. Entries written via direct calls outside the `ServiceManager.deploy`
    // flow will not satisfy the second condition. The deposit-wallet identity itself is independently authenticated
    // on write by `DepositWalletFactory.predictWalletAddress` + `owner()` (see `create()` below).
    mapping(address => address) public mapMultisigDepositWallets;

    // Reentrancy lock
    uint256 internal _locked = 1;

    /// @dev SafeAndDepositWalletCreator constructor.
    /// @param _safe Safe contract address.
    /// @param _safeProxyFactory Safe proxy factory contract address.
    /// @param _recoveryModule Recovery module address.
    /// @param _depositWalletFactory Polymarket Deposit Wallet Factory address.
    /// @param _depositWalletImplementation Polymarket Deposit Wallet logic implementation cloned by the factory.
    constructor (
        address _safe,
        address _safeProxyFactory,
        address _recoveryModule,
        address _depositWalletFactory,
        address _depositWalletImplementation
    ) {
        // Check for zero addresses
        if (_safe == address(0) || _safeProxyFactory == address(0) || _recoveryModule == address(0)
            || _depositWalletFactory == address(0) || _depositWalletImplementation == address(0)) {
            revert ZeroAddress();
        }

        safe = _safe;
        safeProxyFactory = _safeProxyFactory;
        recoveryModule = _recoveryModule;
        depositWalletFactory = _depositWalletFactory;
        depositWalletImplementation = _depositWalletImplementation;
    }

    /// @dev Creates a Safe multisig with Recovery Module enabled atomically and links it to a pre-deployed deposit wallet.
    /// @notice Number of owners is required to be 1: the agent-instance EOA that bridges the Safe and the deposit wallet.
    ///         The deposit wallet must already be deployed by Polymarket's relayer at the address provided in `data`.
    /// @notice `fallbackHandler` is upstream-supplied and not whitelisted on-chain; in the canonical Pearl flow it is the
    ///         Polygon-canonical `CompatibilityFallbackHandler` (`0xf48f…5e4`) so the Safe's ERC-1271 routes through
    ///         `signedMessages`. Integrators substituting a custom handler accept full responsibility for its behavior.
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

        // Authenticate the deposit wallet against the canonical factory's CREATE2 prediction. Compute the relayer-
        // convention walletId from the agent-instance EOA and require `depositWallet` to match what the canonical
        // `DepositWalletFactory.predictWalletAddress(impl, walletId)` would return. CREATE2 collision rules then
        // guarantee any contract at that address was deployed with the canonical proxy bytecode pointing at the
        // pinned implementation. A bytecode-hash check on the wallet itself is not feasible because Polymarket's
        // wallets use solady's `deployDeterministicERC1967WithImmutableArgs` variant, which bakes per-wallet
        // immutable args (factory, walletId) into the proxy bytecode — so each wallet has a distinct runtime
        // codehash.
        bytes32 walletId = bytes32(uint256(uint160(owners[0])));
        address predictedDepositWallet =
            IDepositWalletFactory(depositWalletFactory).predictWalletAddress(depositWalletImplementation, walletId);
        if (depositWallet != predictedDepositWallet) {
            revert WrongDepositWalletAddress(predictedDepositWallet, depositWallet);
        }

        // Verify the deposit wallet is actually deployed at the canonical address — guards against the relayer-
        // pending-deploy race (off-chain HTTP fired but on-chain `DepositWalletFactory.deploy` not yet mined).
        if (depositWallet.code.length == 0) {
            revert DepositWalletNotDeployed(depositWallet);
        }

        // Belt-and-braces owner cross-check: the load-bearing invariant for the EOA-only-owner design enforced by
        // Polymarket's pure-ECDSA `_erc1271IsValidSignatureNowCalldata`. The factory's `_ids` array is operator-
        // chosen and not constrained on-chain to `bytes32(owner)`, so this check ensures the relayer followed the
        // convention even if a future factory revision relaxed it.
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
