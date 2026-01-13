// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IIdentityRegistry {
    function eip712Domain()
    external
    view
    returns (
        bytes1 fields,
        string memory name,
        string memory version,
        uint256 chainId,
        address verifyingContract,
        bytes32 salt,
        uint256[] memory extensions
    );

    function totalSupply() external view returns (uint256);
}

// SafeMultisigWithRecoveryModule interface
interface ISafeMultisigWithRecoveryModule {
    /// @dev Creates a Safe multisig.
    /// @param owners Set of multisig owners.
    /// @param threshold Number of required confirmations for a multisig transaction.
    /// @param data Encoded data related to the creation of a chosen multisig.
    /// @return multisig Address of a created multisig.
    function create(
        address[] memory owners,
        uint256 threshold,
        bytes memory data
    ) external returns (address multisig);
}

interface ISignMessageLib {
    /// @dev Marks a message as signed, so that it can be used with EIP-1271
    /// @notice Marks a message (`_data`) as signed.
    /// @param _data Arbitrary length data that should be marked as signed on the behalf of address(this)
    function signMessage(bytes calldata _data) external;
}

// Safe multi send interface
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

// Generic Safe interface
interface ISafe {
    enum Operation {
        Call,
        DelegateCall
    }

    /// @dev Allows to execute a Safe transaction confirmed by required number of owners and then pays the account that submitted the transaction.
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

    /// @dev Allows to swap/replace an owner from the Safe with another address.
    ///      This can only be done via a Safe transaction.
    /// @notice Replaces the owner `oldOwner` in the Safe with `newOwner`.
    /// @param prevOwner Owner that pointed to the owner to be replaced in the linked list
    /// @param oldOwner Owner address to be replaced.
    /// @param newOwner New owner address.
    function swapOwner(address prevOwner, address oldOwner, address newOwner) external;

}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Execution has failed.
/// @param target Target address.
/// @param payload Payload data.
error ExecutionFailed(address target, bytes payload);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @title SafeMultisigWithRecoveryModule8004 - Smart contract for Safe multisig creation with the recovery module compatible with ERC-8004
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract SafeMultisigWithRecoveryModule8004 {
    bytes32 public constant EIP712DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant AGENT_WALLET_SET_TYPEHASH =
        keccak256("AgentWalletSet(uint256 agentId,address newWallet,address owner,uint256 deadline)");

    // Safe multisig with recovery module processing contract address
    address public immutable safeMultisigWithRecoveryModule;
    // Multisend contract address
    address public immutable multiSend;
    // Safe sign message lib address
    address public immutable signMessageLib;
    // 8004 identity registry address
    address public immutable identityRegistry;
    // Identity registry bridger address
    address public immutable identityRegistryBridger;

    // Reentrancy lock
    uint256 internal _locked = 1;

    /// @dev SafeMultisigWithRecoveryModule8004 constructor.
    constructor(
        address _safeMultisigWithRecoveryModule,
        address _multiSend,
        address _signMessageLib,
        address _identityRegistry,
        address _identityRegistryBridger
    ) {
        // Check for zero addresses
        if (_safeMultisigWithRecoveryModule == address(0) || _multiSend == address(0) || _signMessageLib == address(0)
            || _identityRegistry == address(0) || _identityRegistryBridger == address(0)) {
            revert ZeroAddress();
        }

        safeMultisigWithRecoveryModule = _safeMultisigWithRecoveryModule;
        multiSend = _multiSend;
        signMessageLib = _signMessageLib;
        identityRegistry = _identityRegistry;
        identityRegistryBridger = _identityRegistryBridger;
    }

    function domainSeparatorFor(
        string memory name,
        string memory version,
        uint256 chainId,
        address verifyingContract
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId,
                verifyingContract
            )
        );
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        // EIP-712: keccak256("\x19\x01" || domainSeparator || structHash)
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function computeIdentityRegistryDigest(address multisig) internal view returns (bytes32) {
        // TODO fix when public function is available
        uint256 agentId = 1;//IIdentityRegistry(identityRegistry).totalSupply();

        (, string memory name, string memory version,,,,) = IIdentityRegistry(identityRegistry).eip712Domain();

        bytes32 structHash = keccak256(
            abi.encode(AGENT_WALLET_SET_TYPEHASH, agentId, multisig, identityRegistryBridger, block.timestamp)
        );

        bytes32 ds = domainSeparatorFor(name, version, block.chainid, identityRegistry);

        return toTypedDataHash(ds, structHash);
    }

    /// @dev Creates a Safe multisig.
    /// @param owners Set of multisig owners.
    /// @param threshold Number of required confirmations for a multisig transaction.
    /// @param data Encoded data related to the creation of a chosen multisig.
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

        // TODO Check for owners length and threshold to be 1?
        // TODO decode nonce and add more randomness to it?

        // Create Safe with self as owner
        address[] memory initOwners = new address[](1);
        initOwners[0] = address(this);
        multisig = ISafeMultisigWithRecoveryModule(safeMultisigWithRecoveryModule).create(initOwners, threshold, data);

        // Construct signature for contract execution: works as approved hash tx execution
        bytes32 r = bytes32(uint256(uint160(address(this))));
        bytes memory signature = abi.encodePacked(r, bytes32(0), uint8(1));

        bytes32 digest = computeIdentityRegistryDigest(multisig);

        // Encode sign message function call
        data = abi.encodeCall(ISignMessageLib.signMessage, (abi.encode(digest)));
        // MultiSend payload with the packed data of (operation, multisig address, value(0), payload length, payload)
        bytes memory msPayload = abi.encodePacked(ISafe.Operation.DelegateCall, signMessageLib, uint256(0), data.length, data);

        // Encode swap owner function call
        data = abi.encodeCall(ISafe.swapOwner, (address(0x1), address(this), owners[0]));
        // Concatenate multi send payload with the packed data of (operation, multisig address, value(0), payload length, payload)
        msPayload =
            bytes.concat(msPayload, abi.encodePacked(ISafe.Operation.Call, multisig, uint256(0), data.length, data));

        // Multisend call to execute all the payloads
        msPayload = abi.encodeCall(IMultiSend.multiSend, (msPayload));

        // Execute multisig transaction
        bool success = ISafe(multisig)
            .execTransaction(
            multiSend,
            0,
            msPayload,
            ISafe.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signature
        );

        // Check for success
        if (!success) {
            revert ExecutionFailed(multiSend, msPayload);
        }

        _locked = 1;
    }
}