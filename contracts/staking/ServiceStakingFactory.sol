// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IErrorsRegistries} from "../interfaces/IErrorsRegistries.sol";
import {ServiceStakingProxy} from "./ServiceStakingProxy.sol";

interface IVerifier {
    /// @dev Verifies a service staking implementation contract.
    /// @param implementation Service staking implementation contract address.
    /// @return success True, if verification is successful.
    function verifyImplementation(address implementation) external view returns (bool);

    /// @dev Verifies a service staking proxy instance.
    /// @param instance Service staking proxy instance.
    /// @param implementation Service staking implementation.
    /// @return True, if verification is successful.
    function verifyInstance(address instance, address implementation) external view returns (bool);
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

/// @dev Implementation is not verified.
/// @param implementation Implementation address.
error UnverifiedImplementation(address implementation);

/// @dev Proxy instance is not verified.
/// @param instance Proxy instance address.
error UnverifiedProxy(address instance);

/// @title ServiceStakingFactory - Smart contract for service staking factory
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingFactory is IErrorsRegistries {
    event OwnerUpdated(address indexed owner);
    event VerifierUpdated(address indexed verifier);
    event InstanceCreated(address indexed sender, address indexed instance, address indexed implementation);

    // Minimum data length that contains at least a selector (4 bytes or 32 bits)
    uint256 public constant SELECTOR_DATA_LENGTH = 4;
    // Nonce
    uint256 public nonce;
    // Contract owner address
    address public owner;
    // Verifier address
    address public verifier;
    // Mapping of staking service proxy instances => implementation address
    mapping(address => address) public mapInstanceImplementations;

    /// @dev ServiceStakingFactory constructor.
    /// @param _verifier Verifier contract address (can be zero).
    constructor(address _verifier) {
        owner = msg.sender;
        verifier = _verifier;
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

    /// @dev Calculates a new proxy address based on the deployment data and provided nonce.
    /// @notice New address = first 20 bytes of keccak256(0xff + address(this) + s + keccak256(deploymentData)).
    /// @param implementation Implementation contract address.
    /// @param localNonce Nonce.
    function getProxyAddressWithNonce(address implementation, uint256 localNonce) public view returns (address) {
        // Get salt based on chain Id and nonce values
        bytes32 salt = keccak256(abi.encodePacked(block.chainid, localNonce));

        // Get the deployment data based on the proxy bytecode and the implementation address
        bytes memory deploymentData = abi.encodePacked(type(ServiceStakingProxy).creationCode,
            uint256(uint160(implementation)));

        // Get the hash forming the contract address
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), address(this), salt, keccak256(deploymentData)
            )
        );

        return address(uint160(uint256(hash)));
    }

    /// @dev Calculates a new proxy address based on the deployment data and utilizing a current contract nonce.
    /// @param implementation Implementation contract address.
    function getProxyAddress(address implementation) external view returns (address) {
        return getProxyAddressWithNonce(implementation, nonce);
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
        if (initPayload.length < SELECTOR_DATA_LENGTH) {
            revert IncorrectDataLength(initPayload.length, SELECTOR_DATA_LENGTH);
        }

        // Provide additional checks, if needed
        address localVerifier = verifier;
        if (localVerifier != address(0) && !IVerifier(localVerifier).verifyImplementation(implementation)) {
            revert UnverifiedImplementation(implementation);
        }

        uint256 localNonce = nonce;
        // Get salt based on chain Id and nonce values
        bytes32 salt = keccak256(abi.encodePacked(block.chainid, localNonce));
        // Get the deployment data based on the proxy bytecode and the implementation address
        bytes memory deploymentData = abi.encodePacked(type(ServiceStakingProxy).creationCode,
            uint256(uint160(implementation)));

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

        // Check that the created proxy instance does not violate defined limits
        if (localVerifier != address(0) && !IVerifier(localVerifier).verifyInstance(instance, implementation)) {
            revert UnverifiedProxy(instance);
        }

        mapInstanceImplementations[instance] = implementation;
        nonce = localNonce + 1;

        emit InstanceCreated(msg.sender, instance, implementation);
    }

    /// @dev Verifies a service staking contract instance.
    /// @param instance Service staking proxy instance.
    /// @return success True, if verification is successful.
    function verifyInstance(address instance) external view returns (bool success) {
        address implementation = mapInstanceImplementations[instance];
        if (implementation == address(0)) {
            return false;
        }

        // Provide additional checks, if needed
        address localVerifier = verifier;
        if (localVerifier != address (0)) {
            success = IVerifier(localVerifier).verifyInstance(instance, implementation);
        } else {
            success = true;
        }
    }
}