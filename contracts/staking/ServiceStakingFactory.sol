// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../interfaces/IErrorsRegistries.sol";
import "./ServiceStakingProxy.sol";

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @dev Proxy creation failed.
/// @param implementation Implementation address.
error ProxyCreationFailed(address implementation);

/// @title ServiceStakingFactory - Smart contract for service staking factory
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingFactory is IErrorsRegistries {
    event OwnerUpdated(address indexed owner);
    event InstanceCreated(address indexed instance, address indexed implementation);

    // Contract owner address
    address public owner;
    // Nonce
    uint256 public nonce;
    // Mapping of staking service implementations => implementation status
    mapping(address => bool) public mapImplementations;
    // Mapping of staking service proxy instances => implementation address
    mapping(address => address) public mapInstanceImplementations;

    function createServiceStakingInstance(
        address implementation,
        bytes memory initPayload
    ) external returns (address instance) {
        // Check for the implementation address
        if (!mapImplementations[implementation]) {
            mapImplementations[implementation] = true;
        }

        // Check for the ERC165 compatibility with ServiceStakingBase
        if (!(IERC165(implementation).supportsInterface(0x01ffc9a7) && // ERC165 Interface ID for ERC165
            IERC165(implementation).supportsInterface(0xa694fc3a) && // bytes4(keccak256("stake(uint256)"))
            IERC165(implementation).supportsInterface(0x2e17de78) && // bytes4(keccak256("unstake(uint256)"))
            IERC165(implementation).supportsInterface(0xc2c4c5c1) && // bytes4(keccak256("checkpoint()"))
            IERC165(implementation).supportsInterface(0x78e06136) && // bytes4(keccak256("calculateServiceStakingReward(uint256)"))
            IERC165(implementation).supportsInterface(0x82a8ea58) // bytes4(keccak256("getServiceInfo(uint256)"))
        )) {
            revert();
        }

        uint256 localNonce = nonce;
        bytes32 salt = keccak256(abi.encodePacked(block.chainid, localNonce));
        bytes memory deploymentData = abi.encodePacked(type(ServiceStakingProxy).creationCode, uint256(uint160(implementation)));
        // solhint-disable-next-line no-inline-assembly
        assembly {
            instance := create2(0x0, add(0x20, deploymentData), mload(deploymentData), salt)
        }
        if (address(instance) == address(0)) {
            revert ProxyCreationFailed(implementation);
        }
        
        // Initialize the proxy instance
        // solhint-disable-next-line no-inline-assembly
        assembly {
            if eq(call(gas(), instance, 0, add(initPayload, 0x20), mload(initPayload), 0, 0), 0) {
                revert(0, 0)
            }
        }

        mapInstanceImplementations[instance] = implementation;
        nonce = localNonce + 1;

        emit InstanceCreated(instance, implementation);
    }
}