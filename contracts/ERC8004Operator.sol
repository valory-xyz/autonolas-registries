// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IIdentityRegistry {
    function getMetadata(uint256 agentId, string memory key) external view returns (bytes memory);
}

interface IIdentityRegistryBridger {
    function mapMultisigAgentIds(address multisig) external view returns (uint256);
}

interface IValidationRegistry {
    function validationRequest(
        address validatorAddress,
        uint256 agentId,
        string calldata requestUri,
        bytes32 requestHash
    ) external;
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @title ERC8004 Operator - Smart contract for managing requests in 8004 Identity Registry ecosystem
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ERC8004Operator {
    event OwnerUpdated(address indexed owner);
    event FeedbackAuthSubmitted(address indexed sender, uint256 indexed agentId, address indexed clientAddress,
        uint256 indexLimit, uint256 expiry, bytes32 digest);
    event ValidationRequestSubmitted(address indexed sender, uint256 indexed agentId, address indexed validatorAddress,
        string requestUri, bytes32 requestHash);

    // Version number
    string public constant VERSION = "0.1.0";
    // Agent wallet multisig metadata key
    string public constant AGENT_WALLET_MULTISIG_METADATA_KEY = "agentWallet: {multisig}";
    // Contract signature validation value: bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 constant internal EIP1271_MAGIC_VALUE = 0x1626ba7e;

    // Identity Registry 8004 address
    address public immutable identityRegistry;
    // Validation Registry address
    address public immutable validationRegistry;
    // Identity Registry Bridger address
    address public immutable identityRegistryBridger;

    // Owner address
    address public owner;

    // Reentrancy lock
    uint256 internal _locked = 1;

    // Mapping of signed hashes
    mapping(bytes32 => bool) public mapSignedHashes;

    /// @dev IdentityRegistryBridger constructor.
    /// @param _identityRegistry 8004 Identity Registry address.
    /// @param _validationRegistry Validation Registry address.
    /// @param _identityRegistryBridger 8004 Operator address.
    constructor (address _identityRegistry, address _validationRegistry, address _identityRegistryBridger) {
        // Check for zero addresses
        if (_identityRegistry == address(0) || _validationRegistry == address(0) || _identityRegistryBridger == address(0)) {
            revert ZeroAddress();
        }

        identityRegistry = _identityRegistry;
        validationRegistry = _validationRegistry;
        identityRegistryBridger = _identityRegistryBridger;

        owner = msg.sender;
    }

    /// @dev Changes contract owner address.
    /// @param newOwner New contract owner address.
    function changeOwner(address newOwner) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    function _checkAgentWallet(uint256 agentId) internal view {
        // Get agent wallet multisig address in bytes
        bytes memory agentWalletBytes =
            IIdentityRegistry(identityRegistry).getMetadata(agentId, AGENT_WALLET_MULTISIG_METADATA_KEY);

        // Decode agent wallet address
        address agentWallet = abi.decode(agentWalletBytes, (address));

        // Check for access
        if (msg.sender != agentWallet) {
            revert OwnerOnly(msg.sender, agentWallet);
        }
    }

    /// @dev Authorizes feedback for client by corresponding agent.
    function authorizeFeedback(address clientAddress, uint64 indexLimit, uint256 expiry) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get agent Id by msg.sender
        uint256 agentId = IIdentityRegistryBridger(identityRegistryBridger).mapMultisigAgentIds(msg.sender);
        // Check for agent Id existence
        if (agentId == 0) {
            revert ZeroValue();
        }

        // Check for msg.sender to be agent wallet in its metadata
        _checkAgentWallet(agentId);

        // Construct message hash
        bytes32 messageHash = keccak256(
            abi.encode(
                agentId,
                clientAddress,
                indexLimit,
                expiry,
                block.chainid,
                identityRegistry,
                address(this)
            )
        );

        // Get required digest
        bytes32 digest;
        assembly ("memory-safe") {
            mstore(0x00, "\x19Ethereum Signed Message:\n32") // 32 is the bytes-length of messageHash
            mstore(0x1c, messageHash) // 0x1c (28) is the length of the prefix
            digest := keccak256(0x00, 0x3c) // 0x3c is the length of the prefix (0x1c) + messageHash (0x20)
        }

        // Record "signed" digest
        mapSignedHashes[digest] = true;

        emit FeedbackAuthSubmitted(msg.sender, agentId, clientAddress, indexLimit, expiry, digest);

        _locked - 1;
    }

    /// @dev Agent validation request.
    function validationRequest(
        address validatorAddress,
        uint256 agentId,
        string calldata requestUri,
        bytes32 requestHash
    ) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for msg.sender to be agent wallet in its metadata
        _checkAgentWallet(agentId);

        // Call validation request on behalf of agent operator
        IValidationRegistry(validationRegistry).validationRequest(validatorAddress, agentId, requestUri, requestHash);

        emit ValidationRequestSubmitted(msg.sender, agentId, validatorAddress, requestUri, requestHash);

        _locked - 1;
    }

    /// @dev Should return whether the signature provided is valid for the provided data.
    function isValidSignature(bytes32 messageHash, bytes memory) external view returns (bytes4 magicValue) {
        if (mapSignedHashes[messageHash]) {
            magicValue = EIP1271_MAGIC_VALUE;
        }
    }
}