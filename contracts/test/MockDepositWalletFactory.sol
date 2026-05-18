// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Mock of Polymarket's deposit wallet runtime: a minimal contract that exposes the EOA owner via `owner()`.
/// @notice Polymarket's real deposit wallet (`0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB` on Polygon, deployed
///         behind a solady `deployDeterministicERC1967WithImmutableArgs` UUPS-style proxy) carries a much larger
///         surface — session signers, timelocked withdrawals, ERC-7739 signature validation. None of that is
///         exercised by the `SafeAndDepositWalletCreator`, which verifies `code.length`, the factory's
///         `predictWalletAddress` CREATE2 prediction, and the wallet's `owner()`. This mock keeps the test surface
///         narrow. Owner is set via `initialize` (not the constructor), so the CREATE2 address is independent of
///         the owner — mirroring the real factory where `LibClone.deployDeterministicERC1967` produces an address
///         that depends only on `(factory, impl, walletId)`.
contract MockDepositWallet {
    address public owner;

    function initialize(address _owner) external {
        require(owner == address(0), "already initialized");
        owner = _owner;
    }
}

/// @dev Mock of Polymarket's `DepositWalletFactory` semantics for unit testing.
/// @notice The real factory (`0x00000000000Fb5C9ADea0298D729A0CB3823Cc07` on Polygon) gates `deploy` with
///         `onlyOperator`; the mock is permissionless so unit tests can drive it directly. Salt scheme matches
///         the real factory's relayer convention: `salt = keccak256(abi.encode(factory, walletId))`, where the
///         relayer-client uses `walletId = bytes32(uint256(uint160(owner)))` per the merged `derive.js` source
///         (one owner = one wallet, ever).
///         The `_implementation` argument to `predictWalletAddress` is part of the canonical factory ABI but the
///         mock ignores it: the test wallet bytecode is fixed, so address determinism comes from `(factory, id)`
///         alone. Tests that need to exercise an implementation mismatch can rely on the SafeAndDepositWalletCreator
///         passing its pinned `depositWalletImplementation` immutable into the call — the mock returns the same
///         address regardless, mirroring how a real factory pinned to a single impl behaves under the convention.
contract MockDepositWalletFactory {
    event DepositWalletDeployed(address indexed wallet, address indexed owner);

    /// @dev Provided arrays length mismatch.
    error LengthMismatch();

    /// @dev Deploys mock deposit wallets at deterministic CREATE2 addresses, then initializes each with its owner.
    /// @param _owners Owner EOA for each wallet.
    /// @param _ids Wallet id used in the salt (relayer convention is `bytes32(uint256(uint160(owner)))`).
    function deploy(address[] calldata _owners, bytes32[] calldata _ids) external {
        if (_owners.length != _ids.length) {
            revert LengthMismatch();
        }
        for (uint256 i = 0; i < _owners.length; ++i) {
            bytes32 salt = keccak256(abi.encode(address(this), _ids[i]));
            MockDepositWallet wallet = new MockDepositWallet{salt: salt}();
            wallet.initialize(_owners[i]);
            emit DepositWalletDeployed(address(wallet), _owners[i]);
        }
    }

    /// @dev Mirrors the real factory's `predictWalletAddress(_implementation, _id)`. Returns the deterministic
    ///      CREATE2 address that `deploy` would assign for `_id`. The mock ignores `_implementation` because the
    ///      test wallet has fixed bytecode (no proxy + impl indirection).
    /// @param _implementation Unused in the mock; preserved for ABI parity with the real factory.
    /// @param _id Wallet id (relayer convention is `bytes32(uint256(uint160(owner)))`).
    /// @return Predicted deposit wallet address.
    function predictWalletAddress(address _implementation, bytes32 _id) external view returns (address) {
        _implementation; // silence unused-parameter warning
        bytes32 salt = keccak256(abi.encode(address(this), _id));
        bytes memory initCode = type(MockDepositWallet).creationCode;
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(initCode)));
        return address(uint160(uint256(hash)));
    }

    /// @dev Convenience wrapper: derives the relayer-convention walletId from `_owner` and returns the predicted
    ///      wallet address. The `_implementation` argument is irrelevant in the mock — see `predictWalletAddress`.
    function computeWalletAddress(address _owner) external view returns (address) {
        bytes32 walletId = bytes32(uint256(uint160(_owner)));
        bytes32 salt = keccak256(abi.encode(address(this), walletId));
        bytes memory initCode = type(MockDepositWallet).creationCode;
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(initCode)));
        return address(uint160(uint256(hash)));
    }
}
