// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721TokenReceiver} from "../../lib/solmate/src/tokens/ERC721.sol";

interface IERC721 {
    /// @dev Gives permission to `spender` to transfer `tokenId` token to another account.
    function approve(address spender, uint256 id) external;

    /// @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface IIdentityRegistry {
    struct MetadataEntry {
        string key;
        bytes value;
    }

    function register(string memory tokenUri, MetadataEntry[] memory metadata) external returns (uint256 agentId);

    function setMetadata(uint256 agentId, string memory key, bytes memory value) external;

    function setAgentUri(uint256 agentId, string calldata newUri) external;

    function getMetadata(uint256 agentId, string memory key) external view returns (bytes memory);
}

interface IServiceRegistry {
    enum ServiceState {
        NonExistent,
        PreRegistration,
        ActiveRegistration,
        FinishedRegistration,
        Deployed,
        TerminatedBonded
    }

    /// @dev Gets service instance params.
    /// @param serviceId Service Id.
    /// @return securityDeposit Registration activation deposit.
    /// @return multisig Service multisig address.
    /// @return configHash IPFS hashes pointing to the config metadata.
    /// @return threshold Agent instance signers threshold.
    /// @return maxNumAgentInstances Total number of agent instances.
    /// @return numAgentInstances Actual number of agent instances.
    /// @return state Service state.
    function mapServices(uint256 serviceId) external view returns (uint96 securityDeposit, address multisig,
        bytes32 configHash, uint32 threshold, uint32 maxNumAgentInstances, uint32 numAgentInstances, ServiceState state);

    /// @dev Checks for the unit existence.
    /// @notice Service counter starts from 1.
    /// @param serviceId Service Id.
    /// @return true if service exists, false otherwise.
    function exists(uint256 serviceId) external view returns (bool);
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
    event ServiceAgentLinked(uint256 indexed serviceId, uint256 indexed agentId, address serviceMultisig);
    event AgentUriUpdated(uint256 indexed serviceId, uint256 indexed agentId, string tokenUri);
    event AgentMultisigUpdated(uint256 indexed serviceId, uint256 indexed agentId, address oldMultisig, address indexed newMultisig);
    event StartLinkServiceIdUpdated(uint256 indexed serviceId);

    // Version number
    string public constant VERSION = "0.1.0";
    // Ecosystem metadata key
    string public constant ECOSYSTEM_METADATA_KEY = "ecosystem";
    // Agent wallet multisig metadata key
    string public constant AGENT_WALLET_METADATA_KEY = "agentWallet";
    // Service Registry metadata key
    string public constant SERVICE_REGISTRY_METADATA_KEY = "serviceRegistry";
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

    // Starting service Id for linking with agent Id
    uint256 public startLinkServiceId;

    // Reentrancy lock
    uint256 internal _locked = 1;

    // Mapping of service Id => 8004 agent Id
    mapping(uint256 => uint256) public mapServiceIdAgentIds;
    // Mapping of multisig address => 8004 agent Id
    mapping(address => uint256) public mapMultisigAgentIds;

    /// @dev IdentityRegistryBridger constructor.
    /// @param _identityRegistry 8004 Identity Registry address.
    /// @param _serviceRegistry Service Registry address.
    constructor (address _identityRegistry, address _serviceRegistry) {
        // Check for zero addresses
        if (_identityRegistry == address(0) || _serviceRegistry == address(0)) {
            revert ZeroAddress();
        }

        identityRegistry = _identityRegistry;
        serviceRegistry = _serviceRegistry;
    }

    /// @dev Registers 8004 agent Id corresponding to service Id.
    /// @param serviceId Service Id.
    /// @param multisig Service multisig.
    /// @param tokenUri Service tokenUri.
    /// @return agentId Corresponding 8004 agent Id.
    function _register(uint256 serviceId, address multisig, string memory tokenUri) internal returns (uint256 agentId)  {
        // Assemble OLAS specific metadata entry
        IIdentityRegistry.MetadataEntry[] memory metadataEntries = new IIdentityRegistry.MetadataEntry[](4);
        metadataEntries[0] = IIdentityRegistry.MetadataEntry({
            key: ECOSYSTEM_METADATA_KEY,
            value: abi.encode("OLAS V1")
        });
        metadataEntries[1] = IIdentityRegistry.MetadataEntry({
            key: AGENT_WALLET_METADATA_KEY,
            value: abi.encode(multisig)
        });
        metadataEntries[2] = IIdentityRegistry.MetadataEntry({
            key: SERVICE_REGISTRY_METADATA_KEY,
            value: abi.encode(serviceRegistry)
        });
        metadataEntries[3] = IIdentityRegistry.MetadataEntry({
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

        emit ServiceAgentLinked(serviceId, agentId, multisig);
    }

    /// @dev Initializes proxy contract storage.
    function initialize() external {
        // Check if contract is already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        startLinkServiceId = 1;
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
        // Only allow one agentId per serviceId
        if (agentId > 0) {
            revert AgentIdAlreadyAssigned(agentId, serviceId);
        }

        agentId = _register(serviceId, multisig, tokenUri);

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
            IIdentityRegistry(identityRegistry).setMetadata(agentId, AGENT_WALLET_METADATA_KEY, abi.encode(newMultisig));

            // Unlink old multisig and agentId
            mapMultisigAgentIds[oldMultisig] = 0;
            // Link new multisig and agentId
            mapMultisigAgentIds[newMultisig] = agentId;

            emit AgentMultisigUpdated(serviceId, agentId, oldMultisig, newMultisig);
        }
        _locked = 1;
    }

    /// @dev Links service Ids with registered 8004 agent Ids.
    /// @param numServices Number of services to link.
    /// @return agentIds Set of 8004 agent Ids.
    function linkServiceIdAgentIds(uint256 numServices) external returns (uint256[] memory agentIds) {
        // Check for zero value
        if (numServices == 0) {
            revert ZeroValue();
        }

        // Allocate serviceIds array
        uint256[] memory serviceIds = new uint256[](numServices);

        uint256 serviceId = startLinkServiceId;
        // Assign service Ids
        for (uint256 i = 0; i < numServices; ++i) {
            serviceIds[i] = serviceId + i;
        }

        serviceId += numServices;
        // Record start link service Id for next iteration
        startLinkServiceId = serviceId;

        // Traverse services and create corresponding 8004 agents
        agentIds = updateOrLinkServiceIdAgentIds(serviceIds);

        emit StartLinkServiceIdUpdated(serviceId);
    }

    /// @dev Updates or links service Ids with registered 8004 agent Ids.
    /// @param serviceIds Set of service Ids.
    /// @return agentIds Corresponding set of 8004 agent Ids.
    function updateOrLinkServiceIdAgentIds(uint256[] memory serviceIds) public returns (uint256[] memory agentIds) {
        // Get number of service Ids
        uint256 numServices = serviceIds.length;
        // Check for zero value
        if (numServices == 0) {
            revert ZeroValue();
        }

        // Allocate agentIds array
        agentIds = new uint256[](numServices);

        // Traverse services and update or create corresponding 8004 agents
        for (uint256 i = 0; i < numServices; ++i) {
            uint256 serviceId = serviceIds[i];

            // Check for service Id existence
            if (!IServiceRegistry(serviceRegistry).exists(serviceId)) {
                continue;
            }

            // Get service multisig
            (,address multisig,,,,,) = IServiceRegistry(serviceRegistry).mapServices(serviceId);
            // Skip services that were never deployed
            if (multisig == address(0)) {
                continue;
            }

            // Get service token URI
            string memory tokenUri = IERC721(serviceRegistry).tokenURI(serviceId);

            // Get corresponding 8004 agent Id
            agentIds[i] = mapServiceIdAgentIds[serviceId];
            // Check if agent Id has been registered
            if (agentIds[i] == 0) {
                // Register corresponding 8004 agent Id
                _register(serviceId, multisig, tokenUri);
            } else {
                uint256 agentId = agentIds[i];

                // Check agentWallet metadata
                bytes memory agentWallet =
                    IIdentityRegistry(identityRegistry).getMetadata(agentId, AGENT_WALLET_METADATA_KEY);
                // Decode multisig value
                address checkMultisig = abi.decode(agentWallet, (address));

                // Check for multisig address difference
                if (checkMultisig != multisig) {
                    // Update agent wallet metadata entry
                    IIdentityRegistry(identityRegistry).setMetadata(agentId, AGENT_WALLET_METADATA_KEY,
                        abi.encode(multisig));
                }

                // Get tokenUri
                string memory checkTokenUri = IERC721(identityRegistry).tokenURI(agentId);

                // Check for tokenUri difference
                if (keccak256(bytes(checkTokenUri)) != keccak256(bytes(tokenUri))) {
                    // Updated tokenUri in 8004 Identity Registry
                    IIdentityRegistry(identityRegistry).setAgentUri(agentId, tokenUri);
                }
            }
        }
    }
}