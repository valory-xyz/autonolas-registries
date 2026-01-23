// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721TokenReceiver} from "../../lib/solmate/src/tokens/ERC721.sol";
import {LibString} from "../../lib/solmate/src/utils/LibString.sol";

interface IIdentityRegistry {
    struct MetadataEntry {
        string key;
        bytes value;
    }

    function register(string memory tokenUri, MetadataEntry[] memory metadata) external returns (uint256 agentId);

    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external;

    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external;

    function unsetAgentWallet(uint256 agentId) external;

    function getMetadata(uint256 agentId, string memory key) external view returns (bytes memory);
}

interface IValidationRegistry {
    function validationRequest(
        address validatorAddress,
        uint256 agentId,
        string calldata requestUri,
        bytes32 requestHash
    ) external;
}

interface IServiceRegistry {
    /// @dev Gets service instance params.
    /// @param serviceId Service Id.
    /// @return multisig Service multisig address.
    function mapServices(uint256 serviceId)
        external
        view
        returns (uint96, address multisig, bytes32, uint32, uint32, uint32, uint8);

    /// @dev Gets total supply of services.
    function totalSupply() external view returns (uint256);
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

/// @dev Storage is already initialized.
error AlreadyInitialized();

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev Provided wrong metadata key.
/// @param metadataKey Metadata key.
error WrongMetadataKey(string metadataKey);

/// @dev Provided wrong service Id.
/// @param serviceId Service Id.
error WrongServiceId(uint256 serviceId);

/// @title Identity Registry Bridger - Smart contract for bridging OLAS AI Agent Registry with 8004 Identity Registry
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract IdentityRegistryBridger is ERC721TokenReceiver {
    event OwnerUpdated(address indexed owner);
    event ManagerUpdated(address indexed manager);
    event ImplementationUpdated(address indexed implementation);
    event BaseURIUpdated(string baseURI);
    event ServiceAgentLinked(uint256 indexed serviceId, uint256 indexed agentId);
    event AgentMultisigUpdated(
        uint256 indexed serviceId, uint256 indexed agentId, address oldMultisig, address indexed newMultisig
    );
    event MetadataSet(uint256 indexed agentId, string metadataKey, bytes metadataValue);
    event ValidationRequestSubmitted(
        address indexed sender,
        uint256 indexed agentId,
        address indexed validatorAddress,
        string requestUri,
        bytes32 requestHash
    );
    event StartLinkServiceIdUpdated(uint256 indexed serviceId, bool linkedAll);

    // Version number
    string public constant VERSION = "0.1.0";
    // Ecosystem metadata key
    string public constant ECOSYSTEM_METADATA_KEY = "ecosystem";
    // Ecosystem metadata value
    bytes public constant ECOSYSTEM_METADATA_VALUE = abi.encode("OLAS V1");
    // Service Registry metadata key
    string public constant SERVICE_REGISTRY_METADATA_KEY = "serviceRegistry";
    // Service Id metadata key
    string public constant SERVICE_ID_METADATA_KEY = "serviceId";
    // Agent wallet multisig metadata key
    string public constant AGENT_WALLET_METADATA_KEY = "agentWallet";
    // Identity Registry Bridger proxy address slot
    // keccak256("PROXY_IDENTITY_REGISTRY_BRIDGER") = "0x03684189c8fb7a536ac4dbd4b7ad063c37db21bcd0f9c51fe45a4eb16359c165"
    bytes32 public constant PROXY_IDENTITY_REGISTRY_BRIDGER =
        0x03684189c8fb7a536ac4dbd4b7ad063c37db21bcd0f9c51fe45a4eb16359c165;

    // 8004 Identity Registry address
    address public immutable identityRegistry;
    // 8004 Reputation Registry address
    address public immutable reputationRegistry;
    // 8004 Validation Registry address
    address public immutable validationRegistry;
    // Service Registry address
    address public immutable serviceRegistry;

    // Owner address
    address public owner;
    // Manager address
    address public manager;

    // Base URI
    string public baseURI;

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
    /// @param _reputationRegistry 8004 Reputation Registry address.
    /// @param _validationRegistry 8004 Validation Registry address.
    /// @param _serviceRegistry Service Registry address.
    constructor(
        address _identityRegistry,
        address _reputationRegistry,
        address _validationRegistry,
        address _serviceRegistry
    ) {
        // Check for zero addresses
        if (
            _identityRegistry == address(0) || _reputationRegistry == address(0) || _validationRegistry == address(0)
                || _serviceRegistry == address(0)
        ) {
            revert ZeroAddress();
        }

        identityRegistry = _identityRegistry;
        reputationRegistry = _reputationRegistry;
        validationRegistry = _validationRegistry;
        serviceRegistry = _serviceRegistry;
    }

    /// @dev Gets agent URI.
    /// @param serviceId Service Id.
    /// @return Agent URI string.
    function _getAgentURI(uint256 serviceId) internal view returns (string memory) {
        return string(abi.encodePacked(baseURI, LibString.toString(serviceId)));
    }

    /// @dev Registers 8004 agent Id corresponding to service Id.
    /// @param serviceId Service Id.
    /// @return agentId Corresponding 8004 agent Id.
    function _register(uint256 serviceId) internal returns (uint256 agentId) {
        // Assemble OLAS specific metadata entry
        IIdentityRegistry.MetadataEntry[] memory metadataEntries = new IIdentityRegistry.MetadataEntry[](3);
        metadataEntries[0] =
            IIdentityRegistry.MetadataEntry({key: ECOSYSTEM_METADATA_KEY, value: ECOSYSTEM_METADATA_VALUE});
        metadataEntries[1] =
            IIdentityRegistry.MetadataEntry({key: SERVICE_REGISTRY_METADATA_KEY, value: abi.encode(serviceRegistry)});
        metadataEntries[2] =
            IIdentityRegistry.MetadataEntry({key: SERVICE_ID_METADATA_KEY, value: abi.encode(serviceId)});

        // Get agent URI
        string memory agentURI = _getAgentURI(serviceId);

        // Create new 8004 agent Id
        agentId = IIdentityRegistry(identityRegistry).register(agentURI, metadataEntries);

        // Unset agent wallet because msg.sender is recorded as such in register() function
        IIdentityRegistry(identityRegistry).unsetAgentWallet(agentId);

        // Link service Id and agent Id
        mapServiceIdAgentIds[serviceId] = agentId;

        emit ServiceAgentLinked(serviceId, agentId);
    }

    /// @dev Updates corresponding multisig records and unsets 8004 agent Id old wallet, if it is no longer in use.
    /// @param serviceId Service Id.
    /// @param agentId Corresponding agent Id.
    /// @param oldMultisig Old multisig address.
    /// @param newMultisig New multisig address.
    function _updateAgentWallet(uint256 serviceId, uint256 agentId, address oldMultisig, address newMultisig) internal {
        if (oldMultisig != address(0)) {
            // Unlink old multisig and agentId
            mapMultisigAgentIds[oldMultisig] = 0;

            // Unset old agent wallet
            IIdentityRegistry(identityRegistry).unsetAgentWallet(agentId);
        }
        // Link new multisig and agentId
        mapMultisigAgentIds[newMultisig] = agentId;

        emit AgentMultisigUpdated(serviceId, agentId, oldMultisig, newMultisig);
    }

    /// @dev Initializes proxy contract storage.
    function initialize(string memory _baseURI) external {
        // Check if contract is already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        startLinkServiceId = 1;
        baseURI = _baseURI;
        owner = msg.sender;
    }

    /// @dev Changes contract owner address.
    /// @param newOwner New contract owner address.
    function changeOwner(address newOwner) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Changes contract manager address.
    /// @param newManager New contract manager address.
    function changeManager(address newManager) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (newManager == address(0)) {
            revert ZeroAddress();
        }

        manager = newManager;
        emit ManagerUpdated(newManager);
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
        // solhint-disable-next-line avoid-low-level-calls
        assembly {
            sstore(PROXY_IDENTITY_REGISTRY_BRIDGER, implementation)
        }
        emit ImplementationUpdated(implementation);
    }

    /// @dev Changes agent base URI.
    /// @param newBaseURI New base URI string.
    function changeBaseURI(string memory newBaseURI) external {
        // Check for ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero value
        if (bytes(newBaseURI).length == 0) {
            revert ZeroValue();
        }

        baseURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /// @dev Registers 8004 agent Id corresponding to service Id.
    /// @param serviceId Service Id.
    /// @return agentId Corresponding 8004 agent Id.
    function register(uint256 serviceId) external returns (uint256 agentId) {
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
        // Only allow one agentId per serviceId: skip if agentId has its corresponding serviceId
        if (agentId == 0) {
            // Register new agentId
            agentId = _register(serviceId);
        }

        _locked = 1;
    }

    /// @dev Updates corresponding multisig records and unsets 8004 agent Id old wallet, if it is no longer in use.
    /// @notice This function access is restricted to manager contract that controls agent deployments.
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
            // Update agent wallet in local mapping
            _updateAgentWallet(serviceId, agentId, oldMultisig, newMultisig);
        }

        _locked = 1;
    }

    /// @dev Sets agent wallet.
    /// @notice This is wrapper function that calls IdentityRegistry's one by address(this) as agent Id owner.
    ///         Needs to be called by agent multisig.
    /// @param deadline Specified deadline for signature validation.
    /// @param signature Signature bytes.
    function setAgentWallet(uint256 deadline, bytes memory signature) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get agent Id by msg.sender as its wallet
        uint256 agentId = mapMultisigAgentIds[msg.sender];

        // Check for zero value
        if (agentId == 0) {
            revert ZeroValue();
        }

        // Get service Id
        bytes memory metadata = IIdentityRegistry(identityRegistry).getMetadata(agentId, SERVICE_ID_METADATA_KEY);
        // This must never happen as existing agent Id in mapMultisigAgentIds always has corresponding service Id
        if (metadata.length == 0) {
            revert ZeroValue();
        }
        uint256 serviceId = abi.decode(metadata, (uint256));

        // Get old multisig address
        metadata = IIdentityRegistry(identityRegistry).getMetadata(agentId, AGENT_WALLET_METADATA_KEY);
        // TODO Is this also correct when metadata == "0x"?
        // Decode multisig value
        address oldMultisig = address(bytes20(metadata));

        // Set agent wallet on behalf of agent
        IIdentityRegistry(identityRegistry).setAgentWallet(agentId, msg.sender, deadline, signature);

        emit AgentMultisigUpdated(serviceId, agentId, oldMultisig, msg.sender);

        _locked = 1;
    }

    /// @dev Sets metadata value corresponding to its key.
    /// @param metadataKey Metadata key.
    /// @param metadataValue Metadata value.
    function setMetadata(string memory metadataKey, bytes memory metadataValue) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get agent Id by msg.sender as its wallet
        uint256 agentId = mapMultisigAgentIds[msg.sender];

        // Check for zero value
        if (agentId == 0) {
            revert ZeroValue();
        }

        // Check for default immutable metadata
        if (keccak256(bytes(metadataKey)) == keccak256(bytes(ECOSYSTEM_METADATA_KEY)) ||
            keccak256(bytes(metadataKey)) == keccak256(bytes(SERVICE_REGISTRY_METADATA_KEY)) ||
            keccak256(bytes(metadataKey)) == keccak256(bytes(SERVICE_ID_METADATA_KEY))
        ) {
            revert WrongMetadataKey(metadataKey);
        }

        // Set metadata
        IIdentityRegistry(identityRegistry).setMetadata(agentId, metadataKey, metadataValue);

        emit MetadataSet(agentId, metadataKey, metadataValue);

        _locked = 1;
    }

    /// @dev Agent validation request.
    /// @notice This is wrapper function that calls IdentityRegistry's one by address(this) as agent Id owner.
    ///         Needs to be called by agent multisig.
    /// @param validatorAddress Validator address.
    /// @param requestUri Request URI.
    /// @param requestHash Request hash.
    function validationRequest(address validatorAddress, string calldata requestUri, bytes32 requestHash) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get agent Id by msg.sender as its wallet
        uint256 agentId = mapMultisigAgentIds[msg.sender];

        // Check for zero value
        if (agentId == 0) {
            revert ZeroValue();
        }

        // Call validation request on behalf of agent
        IValidationRegistry(validationRegistry).validationRequest(validatorAddress, agentId, requestUri, requestHash);

        emit ValidationRequestSubmitted(msg.sender, agentId, validatorAddress, requestUri, requestHash);

        _locked = 1;
    }

    /// @dev Links service Ids with registered 8004 agent Ids.
    /// @param numServices Number of services to link.
    /// @return agentIds Set of 8004 agent Ids.
    function linkServiceIdAgentIds(uint256 numServices) external returns (uint256[] memory agentIds) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for zero value
        if (numServices == 0) {
            revert ZeroValue();
        }

        // Get max available service Id
        // service Id numbering starts from id == 1, so last service Id is totalSupply
        uint256 maxServiceId = IServiceRegistry(serviceRegistry).totalSupply();

        // Get first and last service Ids bound
        uint256 startServiceId = startLinkServiceId;
        // Check for zero value: only possible when all legacy services are linked
        if (startServiceId == 0) {
            revert ZeroValue();
        }

        // Note that lastServiceId is not going to be processed, as there is a strict (< numServices) condition
        // lastServiceId is going to be starting service Id in next iteration: processing [serviceId, lastServiceId)
        uint256 lastServiceId = startServiceId + numServices;

        // Adjust last service Id if needed
        if (lastServiceId > maxServiceId) {
            lastServiceId = maxServiceId + 1;
            numServices = lastServiceId - startServiceId;
        }

        // Allocate agentIds array
        agentIds = new uint256[](numServices);

        // Assign agent Ids
        bool linkedAll;
        for (uint256 i = 0; i < numServices; ++i) {
            // Get service Id
            uint256 serviceId = startServiceId + i;

            // Get corresponding 8004 agent Id
            agentIds[i] = mapServiceIdAgentIds[serviceId];
            // Check if agent Id has been registered
            if (agentIds[i] == 0) {
                // Register corresponding 8004 agent Id
                agentIds[i] = _register(serviceId);

                // Get service multisig
                (, address multisig,,,,,) = IServiceRegistry(serviceRegistry).mapServices(serviceId);

                // Check for multisig existence
                if (multisig != address(0)) {
                    // Update agent wallet in local mapping
                    _updateAgentWallet(serviceId, agentIds[i], address(0), multisig);
                }
            } else {
                // Record that all legacy services are linked
                linkedAll = true;
                break;
            }
        }

        // Check if linked all legacy services
        if (linkedAll) {
            // Reset service Id counter such that this function cannot be called anymore
            startLinkServiceId = 0;
        } else {
            // Record start link service Id for next iteration
            startLinkServiceId = lastServiceId;
        }

        emit StartLinkServiceIdUpdated(lastServiceId, linkedAll);

        _locked = 1;
    }

    /// @dev Gets agent URI.
    /// @param serviceId Service Id.
    /// @return Agent URI string.
    function getAgentURI(uint256 serviceId) external view returns (string memory) {
        return _getAgentURI(serviceId);
    }
}
