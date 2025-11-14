// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Only `maintainer` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param maintainer Required sender address as a maintainer.
error MaintainerOnly(address sender, address maintainer);

/// @dev Provided zero address.
error ZeroAddress();


enum ApplicationType {
    NON_EXISTENT,
    PEARL,
    OTHER
}

/// @title Application Classifier - Smart contract for classifying AI Agent / Service Ids
contract ApplicationClassifier {
    event OwnerUpdated(address indexed owner);
    event MaintainerUpdated(address indexed maintainer);
    event ImplementationUpdated(address indexed implementation);
    event ServiceApplicationTypeUpdated(uint256 indexed serviceId, ApplicationType appType);

    // Version number
    string public constant VERSION = "0.1.0";
    // Code position in storage is keccak256("AGENT_CLASSIFICATION_PROXY") = "bb9cd7ad5e1f45908e302afd60ca4d516c3f75bb78697bb109cf197c033960cc"
    bytes32 public constant AGENT_CLASSIFICATION_PROXY = 0xbb9cd7ad5e1f45908e302afd60ca4d516c3f75bb78697bb109cf197c033960cc;

    // Owner address
    address public owner;
    // Maintainer address
    address public maintainer;

    // Mapping of service Id => application type
    mapping(uint256 => ApplicationType) public mapServiceIdStatuses;

    /// @dev Changes the owner address.
    /// @param newOwner New owner address.
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

    /// @dev Changes the unit maintainer.
    /// @param newMaintainer New maintainer address.
    function changeMaintainer(address newMaintainer) external {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newMaintainer == address(0)) {
            revert ZeroAddress();
        }

        maintainer = newMaintainer;
        emit MaintainerUpdated(newMaintainer);
    }

    /// @dev Changes implementation contract address.
    /// @param newImplementation New implementation contract address.
    function changeImplementation(address newImplementation) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (newImplementation == address(0)) {
            revert ZeroAddress();
        }

        // Store the implementation address
        assembly {
            sstore(AGENT_CLASSIFICATION_PROXY, newImplementation)
        }

        emit ImplementationUpdated(newImplementation);
    }

    /// @dev Records service application type.
    /// @param serviceId Service Id.
    /// @param appType Application type.
    function recordApplicationType(uint256 serviceId, ApplicationType appType) external {
        // Check for access
        if (msg.sender != maintainer) {
            revert MaintainerOnly(msg.sender, maintainer);
        }

        // Record current service type
        mapServiceIdStatuses[serviceId] = appType;

        emit ServiceApplicationTypeUpdated(serviceId, appType);
    }
}
