// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721TokenReceiver} from "../lib/solmate/src/tokens/ERC721.sol";

interface IERC721 {
    /// @dev Gives permission to `spender` to transfer `tokenId` token to another account.
    function approve(address spender, uint256 id) external;

    /// @dev Returns the owner of the `tokenId` token.
    function ownerOf(uint256 tokenId) external view returns (address);

    /// @dev Returns the account approved for `tokenId` token.
    function getApproved(uint256 tokenId) external view returns (address);

    /// @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

interface IIdentityRegistry {
    struct MetadataEntry {
        string key;
        bytes value;
    }

    function register(string memory tokenUri, MetadataEntry[] memory metadata) external returns (uint256 agentId);

    function setAgentUri(uint256 agentId, string calldata newUri) external;
}

interface IServiceManager {
    function serviceRegistry() external returns (address);
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

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @title Identity Registry Bridger - Smart contract for bridging OLAS AI Agent Registry with 8004 Identity Registry
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract IdentityRegistryBridger is ERC721TokenReceiver {
    event OwnerUpdated(address indexed owner);
    event ImplementationUpdated(address indexed implementation);
    event AgentDecoupled(uint256 indexed serviceId, uint256 indexed agentId);
    event AgentRegistered(uint256 indexed serviceId, uint256 indexed agentId, address serviceMultisig, string serviceTokenUri);
    event AgentUpdated(uint256 indexed serviceId, uint256 indexed agentId, address serviceMultisig, string serviceTokenUri);

    // Version number
    string public constant VERSION = "0.1.0";
    // Identity Registry Bridger proxy address slot
    // keccak256("PROXY_IDENTITY_REGISTRY_BRIDGER") = "0x03684189c8fb7a536ac4dbd4b7ad063c37db21bcd0f9c51fe45a4eb16359c165"
    bytes32 public constant PROXY_IDENTITY_REGISTRY_BRIDGER = 0x03684189c8fb7a536ac4dbd4b7ad063c37db21bcd0f9c51fe45a4eb16359c165;

    // Identity Registry 8004 address
    address public immutable identityRegistry;
    // Service Manager address
    address public immutable serviceManager;
    // Service Registry address
    address public immutable serviceRegistry;

    // Owner address
    address public owner;

    // Reentrancy lock
    uint256 internal _locked = 1;

    // Mapping of service Id => 8004 agent Id
    mapping(uint256 => uint256) public mapServiceIdAgentIds;

    /// @dev IdentityRegistryBridger constructor.
    /// @param _serviceManager Service Manager address.
    constructor (address _identityRegistry, address _serviceManager) {
        // Check for zero addresses
        if (_identityRegistry == address(0) || _serviceManager == address(0)) {
            revert ZeroAddress();
        }

        identityRegistry = _identityRegistry;
        serviceManager = _serviceManager;
        serviceRegistry = IServiceManager(_serviceManager).serviceRegistry();
    }

    function _register(uint256 serviceId) internal returns (uint256 agentId) {
        // Get token URI
        string memory tokenUri = IERC721(serviceRegistry).tokenURI(serviceId);

        // Get actual service multisig
        (,address multisig,,,,,) = IServiceRegistry(serviceRegistry).mapServices(serviceId);

        // Check for zero address, although this must never happen
        if (multisig == address(0)) {
            revert ZeroAddress();
        }

        // TODO Work on this block to finalize
        // Assemble OLAS specific metadata entry
        IIdentityRegistry.MetadataEntry[] memory metadataEntries = new IIdentityRegistry.MetadataEntry[](1);
        metadataEntries[0] = IIdentityRegistry.MetadataEntry({
            key: "Ecosystem",
            value: abi.encode("OLAS V1")
        });

        // Create new agent Id
        agentId = IIdentityRegistry(identityRegistry).register(tokenUri, metadataEntries);

        // Link service Id and agent Id
        mapServiceIdAgentIds[serviceId] = agentId;

        // Approve service multisig such that it becomes agentId operator
        IERC721(identityRegistry).approve(multisig, agentId);

        emit AgentRegistered(serviceId, agentId, multisig, tokenUri);
    }

    function _update(uint256 serviceId, uint256 agentId) internal {
        // Get token URI
        string memory serviceTokenUri = IERC721(serviceRegistry).tokenURI(serviceId);

        // Get actual service multisig
        (,address serviceMultisig,,,,,) = IServiceRegistry(serviceRegistry).mapServices(serviceId);

        // Check for zero address, although this must never happen
        if (serviceMultisig == address(0)) {
            revert ZeroAddress();
        }

        // Get 8004 agent Id tokenUri
        string memory agentTokenUri = IERC721(identityRegistry).tokenURI(agentId);
        // Check if tokenUri has changed
        if (keccak256(bytes(serviceTokenUri)) != keccak256(bytes(agentTokenUri))) {
            // Set updated tokenUri
            IIdentityRegistry(identityRegistry).setAgentUri(agentId, serviceTokenUri);
        }

        // Check for multisig change
        address agentServiceMultisig = IERC721(identityRegistry).getApproved(agentId);
        // Check if multisig address has changed
        if (serviceMultisig != agentServiceMultisig) {
            // Approve updated service multisig such that it becomes agentId operator
            IERC721(identityRegistry).approve(serviceMultisig, agentId);
        }

        // TODO Shall we NOT emit anything if nothing has been changed?
        emit AgentUpdated(serviceId, agentId, serviceMultisig, serviceTokenUri);
    }

    /// @dev Initializes proxy contract storage.
    function initialize() external {
        // Check if contract is already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

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

    /// @dev Registers or updates 8004 agent Id corresponding to service Id.
    /// @param serviceId Service Id.
    /// @return agentId Corresponding 8004 agent Id.
    /// @return registered True if registered, otherwise updated.
    function register(uint256 serviceId) external returns (uint256 agentId, bool registered) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for access
        if (msg.sender != serviceManager) {
            revert ManagerOnly(msg.sender, serviceManager);
        }

        // Get corresponding 8004 agent Id
        agentId = mapServiceIdAgentIds[serviceId];

        // TODO: if agent is decoupled - create new (as of now), or revert, or return false?
        // Check existing 8004 agent for not being decoupled
        if (agentId > 0) {
            // Get agent Id owner
            address agentOwner = IERC721(identityRegistry).ownerOf(agentId);
            // Check for agent Id ownership
            if (agentOwner != address(this)) {
                // TODO Have external ownable function to check and decouple agents?
                // Decouple current agent Id
                emit AgentDecoupled(serviceId, agentId);

                // Zero the agent Id such that the new one is created
                agentId = 0;
            }
        }

        // Check for 8004 agent Id correspondence
        if (agentId == 0) {
            registered = true;

            // Create new agent Id
            agentId = _register(serviceId);
        } else {
            // Update agent data, if applicable
            _update(serviceId, agentId);
        }

        _locked = 1;
    }

    /// @dev Links service Ids with created 8004 agent Ids.
    /// @param serviceIds Set of service Ids.
    /// @return agentIds Set of 8004 agent Ids.
    function link(uint256[] memory serviceIds) external returns (uint256[] memory agentIds) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get number of serviceIds
        uint256 numServices = serviceIds.length;
        if (numServices == 0) {
            revert ZeroValue();
        }

        // Allocate agentIds array
        agentIds = new uint256[](numServices);

        // Check for all the service Ids not to have corresponding agent Ids
        for (uint256 i = 0; i < numServices; ++i) {
            // Get corresponding 8004 agent Id
            agentIds[i] = mapServiceIdAgentIds[serviceIds[i]];

            // Check for agent Id to be zero
            if (agentIds[i] == 0) {
                // Create 8004 agent Id for service Id
                agentIds[i] = _register(serviceIds[i]);
            }

            // Otherwise no changes are made
        }

        _locked = 1;
    }
}