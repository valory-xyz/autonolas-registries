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

// Generic Safe multisig interface
interface ISafe {
    enum Operation {
        Call,
        DelegateCall
    }

    /// @dev Allows to execute a Safe transaction confirmed by required number of owners and then pays the account that submitted the transaction.
    ///      Note: The fees are always transferred, even if the user transaction fails.
    /// @param to Destination address of Safe transaction.
    /// @param value Ether value of Safe transaction.
    /// @param data Data payload of Safe transaction.
    /// @param operation Operation type of Safe transaction.
    /// @param safeTxGas Gas that should be used for the Safe transaction.
    /// @param baseGas Gas costs that are independent of the transaction execution(e.g. base transaction fee, signature check, payment of the refund)
    /// @param gasPrice Gas price that should be used for the payment calculation.
    /// @param gasToken Token address (or 0 if ETH) that is used for the payment.
    /// @param refundReceiver Address of receiver of gas payment (or 0 if tx.origin).
    /// @param signatures Packed signature data ({bytes32 r}{bytes32 s}{uint8 v})
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external payable returns (bool success);

    /// @dev Allows to add a module to the whitelist.
    /// @param module Module to be whitelisted.
    function enableModule(address module) external;

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

    // keccak256(
    //     "EIP712Domain(uint256 chainId,address verifyingContract)"
    // );
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        0x47e79534a245952e8b16893a336b85a3d9ea9fa8c573f3d803afb92a79469218;

    // keccak256(
    //     "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
    // );
    bytes32 private constant SAFE_TX_TYPEHASH = 0xbb8310d486368db6bd6f849402fdd73ad53d316b5a4b2644ad6efe0f941286d8;

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

    /// @dev Creates Poly Safe multisig.
    /// @notice Number of owners and threshold is required to be 1.
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
        (IPolySafeProxyFactory.Sig memory safeCreateSig, bytes memory enableModuleSig) =
            abi.decode(data, (IPolySafeProxyFactory.Sig, bytes));

        // Calculate multisig address
        multisig = IPolySafeProxyFactory(polySafeProxyFactory).computeProxyAddress(owners[0]);

        // Check that multisig is not yet deployed
        if (multisig.code.length > 0) {
            revert MultisigAlreadyExists(multisig);
        }

        // Create a poly safe multisig via its proxy factory with all payment related values equal to zero
        IPolySafeProxyFactory(polySafeProxyFactory).createProxy(address(0), 0, payable(address(0)), safeCreateSig);

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

        // Enable module payload
        bytes memory execData = abi.encodeCall(ISafe.enableModule, (recoveryModule));

        // Enable Recovery Module
        // to = multisig, value = 0, operation = Call, all payment related = 0
        ISafe(multisig)
            .execTransaction(
                multisig, 0, execData, ISafe.Operation.Call, 0, 0, 0, address(0), payable(address(0)), enableModuleSig
            );

        // TODO Check for event compatibility
        emit MultisigCreated(multisig, owners[0]);
    }

    /// @dev Gets hash that is required to be signed by multisig owner in order to enable Recovery Module.
    /// @param owner Multisig owner.
    /// @return Transaction hash bytes.
    function getEnableModuleTransactionHash(address owner) external view returns (bytes32) {
        // Enable module payload
        bytes memory data = abi.encodeCall(ISafe.enableModule, (recoveryModule));

        // Calculate multisig address
        address multisig = IPolySafeProxyFactory(polySafeProxyFactory).computeProxyAddress(owner);

        // Get domain separator value using calculated multisig address
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_SEPARATOR_TYPEHASH, block.chainid, multisig));

        // Get SafeTx hash
        // to = multisig, value = 0, operation = Call, all payment related = 0, nonce = 0
        bytes32 safeTxHash = keccak256(
            abi.encode(
                SAFE_TX_TYPEHASH, multisig, 0, keccak256(data), ISafe.Operation.Call, 0, 0, 0, address(0), address(0), 0
            )
        );

        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, safeTxHash));
    }
}
