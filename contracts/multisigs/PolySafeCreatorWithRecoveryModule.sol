// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Poly Safe Proxy Factory: https://polygonscan.com/address/0xaacfeea03eb1561c4e67d661e40682bd20e3541b#code
interface IPolySafeProxyFactory {
    // Signature struct
    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @dev Creates Poly Safe proxy contract.
    function createProxy(address paymentToken, uint256 payment, address payable paymentReceiver, Sig memory createSig)
        external;

    /// @dev Computes Poly Safe proxy address based on owner account.
    function computeProxyAddress(address owner) external view returns (address);
}

// Safe Master Copy corresponding to Polygon mainnet: https://polygonscan.com/address/0xd9db270c1b5e3bd161e8c8503c55ceabee709552#code
interface ISafe {
    /// @dev Gets Safe's set of owners.
    function getOwners() external view returns (address[] memory);

    /// @dev Gets Safe threshold.
    function getThreshold() external view returns (uint256);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Multisig already exists.
/// @param multisig Multisig address.
error MultisigAlreadyExists(address multisig);

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

/// @title PolySafeCreatorWithRecoveryModule - Smart contract for Poly Safe multisig implementation with Recovery Module
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract PolySafeCreatorWithRecoveryModule {
    event MultisigCreated(address indexed multisig, address indexed owner);

    // Poly Safe Factory address
    address public immutable polySafeProxyFactory;
    // Recovery Module address
    address public immutable recoveryModule;

    /// @dev PolySafeCreator constructor.
    /// @param _polySafeProxyFactory Poly Safe proxy factory address.
    /// @param _recoveryModule Recovery Module address.
    constructor(address _polySafeProxyFactory, address _recoveryModule) {
        if (_polySafeProxyFactory == address(0) || _recoveryModule == address(0)) {
            revert ZeroAddress();
        }

        polySafeProxyFactory = _polySafeProxyFactory;
        recoveryModule = _recoveryModule;
    }

    /// @dev Creates poly safe multisig.
    /// @param owners Set of multisig owners.
    /// @param threshold Number of required confirmations for a multisig transaction.
    /// @param data Packed data related to the creation of a chosen multisig.
    /// @return multisig Address of a created multisig.
    function create(address[] memory owners, uint256 threshold, bytes memory data) external returns (address multisig) {
        // PolySafe is created based on one owner only
        if (owners.length != 1) {
            revert WrongNumOwners(1, owners.length);
        }

        // Decode provided data
        (address paymentToken, uint256 payment, address payable paymentReceiver, IPolySafeProxyFactory.Sig memory sig) =
            abi.decode(data, (address, uint256, address, IPolySafeProxyFactory.Sig));

        // Calculate multisig address
        multisig = IPolySafeProxyFactory(polySafeProxyFactory).computeProxyAddress(owners[0]);

        // Check that multisig is not yet deployed
        if (multisig.code.length > 0) {
            revert MultisigAlreadyExists(multisig);
        }

        // Create a poly safe multisig via its proxy factory
        IPolySafeProxyFactory(polySafeProxyFactory).createProxy(paymentToken, payment, paymentReceiver, sig);

        // Check for zero address
        if (multisig == address(0)) {
            revert ZeroAddress();
        }

        // Get provided proxy multisig owners and threshold
        address[] memory checkOwners = ISafe(multisig).getOwners();
        uint256 checkThreshold = ISafe(multisig).getThreshold();

        // Verify multisig proxy for provided owners and threshold
        if (threshold != checkThreshold) {
            revert WrongThreshold(checkThreshold, threshold);
        }
        uint256 numOwners = owners.length;
        if (numOwners != checkOwners.length) {
            revert WrongNumOwners(checkOwners.length, numOwners);
        }

        // Check for owner address match
        if (owners[0] != checkOwners[0]) {
            revert WrongOwner(owners[0]);
        }

        emit MultisigCreated(multisig, owners[0]);
    }
}
