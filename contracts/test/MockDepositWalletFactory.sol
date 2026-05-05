// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Mock of Polymarket's deposit wallet runtime: a minimal contract that exposes the EOA owner via `owner()`.
/// @notice Polymarket's real deposit wallet (`0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB` on Polygon, deployed
///         behind a solady `deployDeterministicERC1967` UUPS-style proxy) carries a much larger surface — session
///         signers, timelocked withdrawals, ERC-7739 signature validation. None of that is exercised by the
///         `SafeAndDepositWalletCreator`, which only verifies `code.length`, `codehash` and `owner`. This mock keeps
///         the test surface narrow.
contract MockDepositWallet {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }
}

/// @dev Mock of Polymarket's `DepositWalletFactory.deploy` semantics for unit testing.
/// @notice The real factory (`0x00000000000Fb5C9ADea0298D729A0CB3823Cc07` on Polygon) gates `deploy` with
///         `onlyOperator`; the mock is permissionless so unit tests can drive it directly. Salt scheme matches
///         the real factory's relayer convention: `salt = keccak256(abi.encode(factory, walletId))`, where the
///         relayer-client uses `walletId = bytes32(uint256(uint160(owner)))` per the merged `derive.js` source
///         (one owner = one wallet, ever).
contract MockDepositWalletFactory {
    event DepositWalletDeployed(address indexed wallet, address indexed owner);

    /// @dev Provided arrays length mismatch.
    error LengthMismatch();

    /// @dev Deploys mock deposit wallets at deterministic CREATE2 addresses.
    /// @param _owners Owner EOA for each wallet.
    /// @param _ids Wallet id used in the salt (relayer convention is `bytes32(uint256(uint160(owner)))`).
    function deploy(address[] calldata _owners, bytes32[] calldata _ids) external {
        if (_owners.length != _ids.length) {
            revert LengthMismatch();
        }
        for (uint256 i = 0; i < _owners.length; ++i) {
            bytes32 salt = keccak256(abi.encode(address(this), _ids[i]));
            address wallet = address(new MockDepositWallet{salt: salt}(_owners[i]));
            emit DepositWalletDeployed(wallet, _owners[i]);
        }
    }

    /// @dev Computes the deterministic CREATE2 address for a deposit wallet owned by `_owner`.
    /// @notice Mirrors the real factory's salt convention with `walletId = bytes32(uint256(uint160(owner)))`.
    /// @param _owner Owner EOA expected to own the deposit wallet.
    /// @return Predicted deposit wallet address.
    function computeWalletAddress(address _owner) external view returns (address) {
        bytes32 walletId = bytes32(uint256(uint160(_owner)));
        bytes32 salt = keccak256(abi.encode(address(this), walletId));
        bytes memory initCode = abi.encodePacked(type(MockDepositWallet).creationCode, abi.encode(_owner));
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(initCode)));
        return address(uint160(uint256(hash)));
    }

}
