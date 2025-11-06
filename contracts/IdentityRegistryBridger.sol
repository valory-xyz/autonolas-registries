// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721TokenReceiver} from "../lib/solmate/src/tokens/ERC721.sol";

interface IERC721 {
    /// @dev Gives permission to `spender` to transfer `tokenId` token to another account.
    function approve(address spender, uint256 id) external;
}

interface IIdentityRegistry {
    struct MetadataEntry {
        string key;
        bytes value;
    }

    function register(string memory tokenUri, MetadataEntry[] memory metadata) external returns (uint256 agentId);

    function setMetadata(uint256 agentId, string memory key, bytes memory value) external;

    function setAgentUri(uint256 agentId, string calldata newUri) external;
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as a manager.
error ManagerOnly(address sender, address manager);

/// @dev The contract is already initialized.
error AlreadyInitialized();

/// @dev Agent Id is already assigned to service Id.
/// @param agentId Agent Id.
/// @param serviceId Service Id.
error AgentIdAlreadyAssigned(uint256 agentId, uint256 serviceId);

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @title Identity Registry Bridger - Smart contract for bridging OLAS AI Agent Registry with 8004 Identity Registry
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract IdentityRegistryBridger is ERC721TokenReceiver {
    event OwnerUpdated(address indexed owner);
    event ManagerUpdated(address indexed manager);
    event OperatorUpdated(address indexed operator);
    event ImplementationUpdated(address indexed implementation);
    event AgentRegistered(uint256 indexed serviceId, uint256 indexed agentId, address serviceMultisig, string serviceTokenUri);
    event AgentUriUpdated(uint256 indexed serviceId, uint256 indexed agentId, string tokenUri);
    event AgentMultisigUpdated(uint256 indexed serviceId, uint256 indexed agentId, address oldMultisig, address indexed newMultisig);

    // Version number
    string public constant VERSION = "0.1.0";
    // Ecosystem metadata key
    string public constant ECOSYSTEM_METADATA_KEY = "ecosystem";
    // Agent wallet multisig metadata key
    string public constant AGENT_WALLET_MULTISIG_METADATA_KEY = "agentWallet: {multisig}";
    // Service Id metadata key
    string public constant SERVICE_ID_METADATA_KEY = "serviceId";
    // Identity Registry Bridger proxy address slot
    // keccak256("PROXY_IDENTITY_REGISTRY_BRIDGER") = "0x03684189c8fb7a536ac4dbd4b7ad063c37db21bcd0f9c51fe45a4eb16359c165"
    bytes32 public constant PROXY_IDENTITY_REGISTRY_BRIDGER = 0x03684189c8fb7a536ac4dbd4b7ad063c37db21bcd0f9c51fe45a4eb16359c165;

    // Identity Registry 8004 address
    address public immutable identityRegistry;
    // Service Registry address
    address public immutable serviceRegistry;

    // Owner address
    address public owner;
    // Manager address
    address public manager;
    // 8004 Operator address
    address public operator;

    // Reentrancy lock
    uint256 internal _locked = 1;

    // Mapping of service Id => 8004 agent Id
    mapping(uint256 => uint256) public mapServiceIdAgentIds;
    // Mapping of multisig address => 8004 agent Id
    mapping(address => uint256) public mapMultisigAgentIds;

    /// @dev IdentityRegistryBridger constructor.
    /// @param _identityRegistry 8004 Identity Registry address.
    /// @param _serviceRegistry Service Registry address.
    /// @param _operator 8004 Operator address.
    constructor (address _identityRegistry, address _serviceRegistry, address _operator) {
        // Check for zero addresses
        if (_identityRegistry == address(0) || _serviceRegistry == address(0) || _operator == address(0)) {
            revert ZeroAddress();
        }

        identityRegistry = _identityRegistry;
        serviceRegistry = _serviceRegistry;
        operator = _operator;
    }

    /// @dev Initializes proxy contract storage.
    /// @param _manager Manager address.
    function initialize(address _manager) external {
        // Check if contract is already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        manager = _manager;
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

    /// @dev Changes contract manager address.
    /// @param newManager New contract owner address.
    function changeManager(address newManager) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newManager == address(0)) {
            revert ZeroAddress();
        }

        manager = newManager;
        emit ManagerUpdated(newManager);
    }

    /// @dev Changes contract manager address.
    /// @param newOperator New contract owner address.
    function changeOperator(address newOperator) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOperator == address(0)) {
            revert ZeroAddress();
        }

        operator = newOperator;
        emit OperatorUpdated(newOperator);
    }

    /// @dev Changes implementation contract address.
    /// @notice Make sure implementation contract has function to change its implementation.
    /// @param implementation Implementation contract address.
    function changeImplementation(address implementation) external {
        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (implementation == address(0)) {
            revert ZeroAddress();
        }

        // Store implementation address under designated storage slot
        assembly {
            sstore(PROXY_IDENTITY_REGISTRY_BRIDGER, implementation)
        }
        emit ImplementationUpdated(implementation);
    }

    /// @dev Registers 8004 agent Id corresponding to service Id.
    /// @param serviceId Service Id.
    /// @param multisig Service multisig.
    /// @param tokenUri Service tokenUri.
    /// @return agentId Corresponding 8004 agent Id.
    function register(uint256 serviceId, address multisig, string memory tokenUri) external returns (uint256 agentId) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for access
        if (msg.sender != manager) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Get corresponding 8004 agent Id
        agentId = mapServiceIdAgentIds[serviceId];
        // This must never happen
        if (agentId > 0) {
            revert AgentIdAlreadyAssigned(agentId, serviceId);
        }

        // TODO Work on this block to finalize: multisig etc
        // Assemble OLAS specific metadata entry
        IIdentityRegistry.MetadataEntry[] memory metadataEntries = new IIdentityRegistry.MetadataEntry[](3);
        metadataEntries[0] = IIdentityRegistry.MetadataEntry({
            key: ECOSYSTEM_METADATA_KEY,
            value: abi.encode("OLAS V1")
        });
        metadataEntries[1] = IIdentityRegistry.MetadataEntry({
            key: AGENT_WALLET_MULTISIG_METADATA_KEY,
            value: abi.encode(multisig)
        });
        metadataEntries[2] = IIdentityRegistry.MetadataEntry({
            key: SERVICE_ID_METADATA_KEY,
            value: abi.encode(serviceId)
        });

        // Create new agent Id
        agentId = IIdentityRegistry(identityRegistry).register(tokenUri, metadataEntries);

        // Link service Id and agent Id
        mapServiceIdAgentIds[serviceId] = agentId;
        // Link multisig and agentId
        mapMultisigAgentIds[multisig] = agentId;

        // Approve agentId operator
        IERC721(identityRegistry).approve(operator, agentId);

        emit AgentRegistered(serviceId, agentId, multisig, tokenUri);

        _locked = 1;
    }

    /// @dev Updated agent URI according to provided service URI.
    /// @param serviceId Service Id.
    /// @param tokenUri Service tokenUri.
    function updateAgentUri(uint256 serviceId, string memory tokenUri) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for access
        if (msg.sender != manager) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Get corresponding agent Id
        uint256 agentId = mapServiceIdAgentIds[serviceId];

        // Modify only if agent Id is already defined, otherwise skip
        if (agentId > 0) {
            // Set tokenUri
            IIdentityRegistry(identityRegistry).setAgentUri(agentId, tokenUri);

            emit AgentUriUpdated(serviceId, agentId, tokenUri);
        }
        _locked = 1;
    }

    /// @dev Updates 8004 agent Id wallet corresponding to service Id multisig.
    /// @param serviceId Service Id.
    /// @param oldMultisig Old multisig address.
    /// @param newMultisig New multisig address.
    function updateAgentWallet(uint256 serviceId, address oldMultisig, address newMultisig) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for access
        if (msg.sender != manager) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Get corresponding agent Id
        uint256 agentId = mapServiceIdAgentIds[serviceId];

        // Modify only if agent Id is already defined, otherwise skip
        if (agentId > 0) {
            // Update agent wallet metadata entry
            IIdentityRegistry(identityRegistry).setMetadata(agentId, AGENT_WALLET_MULTISIG_METADATA_KEY, abi.encode(newMultisig));

            // Unlink old multisig and agentId
            mapMultisigAgentIds[oldMultisig] = 0;
            // Link new multisig and agentId
            mapMultisigAgentIds[newMultisig] = agentId;

            emit AgentMultisigUpdated(serviceId, agentId, oldMultisig, newMultisig);
        }
        _locked = 1;
    }
}