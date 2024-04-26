// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../interfaces/IErrorsRegistries.sol";
import "./ServiceStakingProxy.sol";

interface IVerifier {
    function verifyImplementation(address implementation) external view returns (bool);
    function verifyInstance(address instance) external view returns (bool);
}

/// @dev Provided incorrect data length.
/// @param expected Expected minimum data length.
/// @param provided Provided data length.
error IncorrectDataLength(uint256 expected, uint256 provided);

/// @dev The deployed implementation must be a contract.
/// @param implementation Implementation address.
error ContractOnly(address implementation);

/// @dev Proxy creation failed.
/// @param implementation Implementation address.
error ProxyCreationFailed(address implementation);

/// @dev Proxy instance initialization failed
/// @param instance Proxy instance address.
error InitializationFailed(address instance);

/// @dev Proxy instance has no implementation in the factory.
/// @param instance Proxy instance address.
error InstanceHasNoImplementation(address instance);

/// @title ServiceStakingFactory - Smart contract for service staking factory
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingFactory is IErrorsRegistries {
    event OwnerUpdated(address indexed owner);
    event VerifierUpdated(address indexed verifier);
    event InstanceCreated(address indexed instance, address indexed implementation);

    // Minimum data length that contains at least a selector (4 bytes or 32 bits)
    uint256 public constant SELECTOR_DATA_LENGTH = 4;
    // Contract owner address
    address public owner;
    // Verifier address
    address public verifier;
    // Nonce
    uint256 public nonce;
    // Mapping of staking service implementations => implementation status
    mapping(address => bool) public mapImplementations;
    // Mapping of staking service proxy instances => implementation address
    mapping(address => address) public mapInstanceImplementations;

    constructor() {
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
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

    /// @dev Changes the verifier address.
    /// @param newVerifier Address of a new verifier.
    function changeVerifier(address newVerifier) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        verifier = newVerifier;
        emit VerifierUpdated(newVerifier);
    }

    /// @dev Creates a service staking contract instance.
    /// @param implementation Service staking blanc implementation address.
    /// @param initPayload Initialization payload.
    function createServiceStakingInstance(
        address implementation,
        bytes memory initPayload
    ) external returns (address payable instance) {
        // Check for the zero implementation address
        if (implementation == address(0)) {
            revert ZeroAddress();
        }

        // Check that the implementation is the contract
        if (implementation.code.length == 0) {
            revert ContractOnly(implementation);
        }

        // The payload length must be at least of the a function selector size
        // TODO calculate the minimum payload for the staking base contract
        if (initPayload.length < SELECTOR_DATA_LENGTH) {
            revert IncorrectDataLength(initPayload.length, SELECTOR_DATA_LENGTH);
        }

        // Check for the implementation address
        if (!mapImplementations[implementation]) {
            mapImplementations[implementation] = true;
        }

        // Provide additional checks, if needed
        address localVerifier = verifier;
        if (localVerifier != address (0) && !IVerifier(localVerifier).verifyImplementation(implementation)) {
            revert();
        }

        uint256 localNonce = nonce;
        bytes32 salt = keccak256(abi.encodePacked(block.chainid, localNonce));
        bytes memory deploymentData = abi.encodePacked(type(ServiceStakingProxy).creationCode, uint256(uint160(implementation)));
        // solhint-disable-next-line no-inline-assembly
        assembly {
            instance := create2(0x0, add(0x20, deploymentData), mload(deploymentData), salt)
        }
        // Check that the proxy creation was successful
        if (instance == address(0)) {
            revert ProxyCreationFailed(implementation);
        }

        // Initialize the proxy instance
        (bool success, bytes memory returnData) = instance.call(initPayload);
        // Process unsuccessful call
        if (!success) {
            // Get the revert message bytes
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            } else {
                revert InitializationFailed(instance);
            }
        }

        mapInstanceImplementations[instance] = implementation;
        nonce = localNonce + 1;

        emit InstanceCreated(instance, implementation);
    }

    /// @dev Verifies a service staking contract instance.
    /// @param instance Service staking proxy instance.
    /// @return success True, if verification is successful.
    function verifyInstance(address instance) external view returns (bool success) {
        address implementation = mapInstanceImplementations[instance];
        if (implementation == address(0)) {
            revert InstanceHasNoImplementation(instance);
        }

        // Provide additional checks, if needed
        address localVerifier = verifier;
        if (localVerifier != address (0)) {
            success = IVerifier(localVerifier).verifyInstance(instance);
        } else {
            success = true;
        }
    }
}