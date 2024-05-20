// Sources flattened with hardhat v2.22.4 https://hardhat.org

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @dev Zero implementation address.
error ZeroImplementationAddress();

/*
* This is a Service Staking proxy contract.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Special service staking implementation address slot is produced by hashing the "SERVICE_STAKING_PROXY"
* string in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title StakingProxy - Smart contract for service staking proxy
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract StakingProxy {
    // Code position in storage is keccak256("SERVICE_STAKING_PROXY") = "0x9e5e169c1098011e4e5940a3ec1797686b2a8294a9b77a4c676b121bdc0ebb5e"
    bytes32 public constant SERVICE_STAKING_PROXY = 0x9e5e169c1098011e4e5940a3ec1797686b2a8294a9b77a4c676b121bdc0ebb5e;

    /// @dev StakingProxy constructor.
    /// @param implementation Service staking implementation address.
    constructor(address implementation) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (implementation == address(0)) {
            revert ZeroImplementationAddress();
        }

        // Store the service staking implementation address
        assembly {
            sstore(SERVICE_STAKING_PROXY, implementation)
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external payable {
        assembly {
            let implementation := sload(SERVICE_STAKING_PROXY)
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }

    /// @dev Gets the implementation address.
    function getImplementation() external view returns (address implementation) {
        assembly {
            implementation := sload(SERVICE_STAKING_PROXY)
        }
    }
}

pragma solidity ^0.8.25;

// Staking interface
interface IStaking {
    /// @dev Gets emissions amount.
    /// @return Emissions amount.
    function emissionsAmount() external view returns (uint256);
}

// Staking verifier interface
interface IStakingVerifier {
    /// @dev Verifies a service staking implementation contract.
    /// @param implementation Service staking implementation contract address.
    /// @return success True, if verification is successful.
    function verifyImplementation(address implementation) external view returns (bool);

    /// @dev Verifies a service staking proxy instance.
    /// @param instance Service staking proxy instance.
    /// @param implementation Service staking implementation.
    /// @return True, if verification is successful.
    function verifyInstance(address instance, address implementation) external view returns (bool);

    /// @dev Gets emissions amount limit for a specific staking proxy instance.
    /// @return Emissions amount limit.
    function getEmissionsAmountLimit(address) external view returns (uint256);
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

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

/// @dev Caught reentrancy violation.
error ReentrancyGuard();

// Instance params struct
struct InstanceParams {
    // Implementation of a created proxy instance
    address implementation;
    // Instance deployer
    address deployer;
    // Instance status flag
    bool isEnabled;
}

/// @title StakingFactory - Smart contract for service staking factory
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract StakingFactory {
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
    // Reentrancy lock
    uint256 internal _locked = 1;

    // Mapping of staking service proxy instances => InstanceParams struct
    mapping(address => InstanceParams) public mapInstanceParams;

    /// @dev StakingFactory constructor.
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
        bytes memory deploymentData = abi.encodePacked(type(StakingProxy).creationCode,
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
    function createStakingInstance(
        address implementation,
        bytes memory initPayload
    ) external returns (address payable instance) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

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
        if (localVerifier != address(0) && !IStakingVerifier(localVerifier).verifyImplementation(implementation)) {
            revert UnverifiedImplementation(implementation);
        }

        uint256 localNonce = nonce;
        // Get salt based on chain Id and nonce values
        bytes32 salt = keccak256(abi.encodePacked(block.chainid, localNonce));
        // Get the deployment data based on the proxy bytecode and the implementation address
        bytes memory deploymentData = abi.encodePacked(type(StakingProxy).creationCode,
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
        if (localVerifier != address(0) && !IStakingVerifier(localVerifier).verifyInstance(instance, implementation)) {
            revert UnverifiedProxy(instance);
        }

        // Record instance params
        InstanceParams memory instanceParams = InstanceParams(implementation, msg.sender, true);
        mapInstanceParams[instance] = instanceParams;
        // Increase the nonce
        nonce = localNonce + 1;

        emit InstanceCreated(msg.sender, instance, implementation);

        _locked = 1;
    }

    /// @dev Sets the instance status flag.
    /// @param instance Proxy instance address.
    /// @param isEnabled Activity flag.
    function setInstanceStatus(address instance, bool isEnabled) external {
        // Get proxy instance params
        InstanceParams storage instanceParams = mapInstanceParams[instance];
        address deployer = instanceParams.deployer;

        // Check for the instance deployer
        if (msg.sender != deployer) {
            revert OwnerOnly(msg.sender, deployer);
        }

        instanceParams.isEnabled = isEnabled;
    }
    
    /// @dev Verifies a service staking contract instance.
    /// @param instance Service staking proxy instance.
    /// @return True, if verification is successful.
    function verifyInstance(address instance) public view returns (bool) {
        // Get proxy instance params
        InstanceParams storage instanceParams = mapInstanceParams[instance];
        address implementation = instanceParams.implementation;

        // Check that the implementation corresponds to the proxy instance
        if (implementation == address(0)) {
            return false;
        }

        // Check for the instance being active
        if (!instanceParams.isEnabled) {
            return false;
        }

        // Provide additional checks, if needed
        address localVerifier = verifier;
        if (localVerifier != address(0)) {
            return IStakingVerifier(localVerifier).verifyInstance(instance, implementation);
        }

        return true;
    }

    /// @dev Verifies staking proxy instance and gets emissions amount.
    /// @param instance Staking proxy instance.
    /// @return amount Emissions amount.
    function verifyInstanceAndGetEmissionsAmount(address instance) external view returns (uint256 amount) {
        // Verify the proxy instance
        bool success = verifyInstance(instance);

        if (success) {
            // Get the proxy instance emissions amount
            amount = IStaking(instance).emissionsAmount();

            // If there is a verifier, adjust the amount
            address localVerifier = verifier;
            if (localVerifier != address(0)) {
                // Get the max possible emissions amount
                uint256 maxEmissions = IStakingVerifier(localVerifier).getEmissionsAmountLimit(instance);
                // Limit excessive emissions amount
                if (amount > maxEmissions) {
                    amount = maxEmissions;
                }
            }
        }
    }
}
