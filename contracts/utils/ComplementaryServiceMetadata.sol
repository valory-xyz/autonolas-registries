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
    /// @return configHash IPFS hashes pointing to the config metapayload.
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

    // Service Registry address
    address public immutable serviceRegistry;

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

        // Get service multisig and state
        (, address multisig, , , , , IServiceRegistry.ServiceState state) =
            IServiceRegistry(serviceRegistry).mapServices(serviceId);

        // Check for multisig access when the service is deployed
        if (state == IServiceRegistry.ServiceState.Deployed) {
            if (msg.sender != multisig) {
                revert UnauthorizedAccount(msg.sender);
            }
        } else {
            // Get service owner
            address serviceOwner = IServiceRegistry(serviceRegistry).ownerOf(serviceId);

            // Check for service owner
            if (msg.sender != serviceOwner) {
                revert UnauthorizedAccount(msg.sender);
            }
        }

        // Update service hash
        mapServiceHashes[serviceId] = hash;

        emit ComplementaryMetadataUpdated(serviceId, hash);

        _locked = 1;
    }
}
