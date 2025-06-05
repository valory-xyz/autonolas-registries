// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Service Registry interface
interface IServiceRegistry {
    enum ServiceState {
        NonExistent,
        PreRegistration,
        ActiveRegistration,
        FinishedRegistration,
        Deployed,
        TerminatedBonded
    }

    /// @dev Gets the service instance from the map of services.
    /// @param serviceId Service Id.
    /// @return securityDeposit Registration activation deposit.
    /// @return multisig Service multisig address.
    /// @return configHash IPFS hash pointing to the config metadata.
    /// @return threshold Agent instance signers threshold.
    /// @return maxNumAgentInstances Total number of agent instances.
    /// @return numAgentInstances Actual number of agent instances.
    /// @return state Service state.
    function mapServices(uint256 serviceId) external view returns (uint96 securityDeposit, address multisig,
        bytes32 configHash, uint32 threshold, uint32 maxNumAgentInstances, uint32 numAgentInstances, ServiceState state);

    /// @dev Gets the owner of a specified service Id.
    /// @param serviceId Service Id.
    /// @return serviceOwner Service owner address.
    function ownerOf(uint256 serviceId) external view returns (address serviceOwner);

    /// @dev Gets service registry baseURI
    function baseURI() external view returns(string memory);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

/// @dev Account is unauthorized.
/// @param account Account address.
error UnauthorizedAccount(address account);

/// @title ComplementaryServiceMetadata - Complementary Service Metadata contract to manage complementary service hashes
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ComplementaryServiceMetadata {
    event ComplementaryMetadataUpdated(uint256 indexed serviceId, bytes32 indexed hash);

    // Olas mech version number
    string public constant VERSION = "0.1.0";
    // To better understand the CID anatomy, please refer to: https://proto.school/anatomy-of-a-cid/05
    // CID = <multibase_encoding>multibase_encoding(<cid-version><multicodec><multihash-algorithm><multihash-length><multihash-hash>)
    // CID prefix = <multibase_encoding>multibase_encoding(<cid-version><multicodec><multihash-algorithm><multihash-length>)
    // to complement the multibase_encoding(<multihash-hash>)
    // multibase_encoding = base16 = "f"
    // cid-version = version 1 = "0x01"
    // multicodec = dag-pb = "0x70"
    // multihash-algorithm = sha2-256 = "0x12"
    // multihash-length = 256 bits = "0x20"
    string public constant CID_PREFIX = "f01701220";

    // Service Registry address
    address public immutable serviceRegistry;

    // Service registry base URI
    string public baseURI;

    // Reentrancy lock
    uint256 internal _locked = 1;

    // Mapping of serviceId => actual metadata hash
    mapping(uint256 => bytes32) public mapServiceHashes;

    /// @dev ComplementaryServiceMetadata constructor.
    /// @param _serviceRegistry Service Registry address.
    constructor(address _serviceRegistry) {
        // Check for zero address
        if (_serviceRegistry == address(0)) {
            revert ZeroAddress();
        }

        serviceRegistry = _serviceRegistry;
        baseURI = IServiceRegistry(serviceRegistry).baseURI();
    }

    // Open sourced from: https://stackoverflow.com/questions/67893318/solidity-how-to-represent-bytes32-as-string
    /// @dev Converts bytes16 input data to hex16.
    /// @notice This method converts bytes into the same bytes-character hex16 representation.
    /// @param data bytes16 input data.
    /// @return result hex16 conversion from the input bytes16 data.
    function _toHex16(bytes16 data) internal pure returns (bytes32 result) {
        result = bytes32 (data) & 0xFFFFFFFFFFFFFFFF000000000000000000000000000000000000000000000000 |
            (bytes32 (data) & 0x0000000000000000FFFFFFFFFFFFFFFF00000000000000000000000000000000) >> 64;
        result = result & 0xFFFFFFFF000000000000000000000000FFFFFFFF000000000000000000000000 |
            (result & 0x00000000FFFFFFFF000000000000000000000000FFFFFFFF0000000000000000) >> 32;
        result = result & 0xFFFF000000000000FFFF000000000000FFFF000000000000FFFF000000000000 |
            (result & 0x0000FFFF000000000000FFFF000000000000FFFF000000000000FFFF00000000) >> 16;
        result = result & 0xFF000000FF000000FF000000FF000000FF000000FF000000FF000000FF000000 |
            (result & 0x00FF000000FF000000FF000000FF000000FF000000FF000000FF000000FF0000) >> 8;
        result = (result & 0xF000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000) >> 4 |
            (result & 0x0F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F00) >> 8;
        result = bytes32 (0x3030303030303030303030303030303030303030303030303030303030303030 +
        uint256 (result) +
        (uint256 (result) + 0x0606060606060606060606060606060606060606060606060606060606060606 >> 4 &
            0x0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F) * 39);
    }

    /// @dev Changes metadata hash.
    /// @param serviceId Service id.
    /// @param hash Updated metadata hash.
    function changeHash(uint256 serviceId, bytes32 hash) external {
        // Reentrancy guard
        if (_locked == 2) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for msg.sender access to change hash
        if (!isAbleChangeHash(msg.sender, serviceId)) {
            revert UnauthorizedAccount(msg.sender);
        }

        // Update service hash
        mapServiceHashes[serviceId] = hash;

        emit ComplementaryMetadataUpdated(serviceId, hash);

        _locked = 1;
    }

    /// @dev Checks if account is able to change service metadata hash.
    /// @param account Account address.
    /// @param serviceId Service id.
    /// @return True if account has access, false otherwise.
    function isAbleChangeHash(address account, uint256 serviceId) public view returns (bool) {
        // Get service multisig and state
        (, address multisig, , , , , IServiceRegistry.ServiceState state) =
            IServiceRegistry(serviceRegistry).mapServices(serviceId);

        // Check for multisig access when the service is deployed
        if (state == IServiceRegistry.ServiceState.Deployed) {
            if (account != multisig) {
                return false;
            }
        } else {
            // Get service owner
            address serviceOwner = IServiceRegistry(serviceRegistry).ownerOf(serviceId);

            // Check for service owner
            if (account != serviceOwner) {
                return false;
            }
        }

        return true;
    }

    /// @dev Returns complementary service token URI.
    /// @notice Expected multicodec: dag-pb; hashing function: sha2-256, with base16 encoding and leading CID_PREFIX removed.
    /// @param serviceId Service Id.
    /// @return Complementary service token URI string.
    function complementaryTokenURI(uint256 serviceId) public view returns (string memory) {
        bytes32 serviceHash = mapServiceHashes[serviceId];
        // Parse 2 parts of bytes32 into left and right hex16 representation, and concatenate into string
        // adding the base URI and a cid prefix for the full base16 multibase prefix IPFS hash representation
        return string(abi.encodePacked(baseURI, CID_PREFIX, _toHex16(bytes16(serviceHash)),
            _toHex16(bytes16(serviceHash << 128))));
    }
}
