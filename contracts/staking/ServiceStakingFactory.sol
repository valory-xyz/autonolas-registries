// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../interfaces/IErrorsRegistries.sol";
import "hardhat/console.sol";

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

contract ServiceStakingFactory is IErrorsRegistries {
    event OwnerUpdated(address indexed owner);
    event InstanceCreated(address indexed instance, bytes32 implementationHash);

    // Contract owner address
    address public owner;
    // Mapping of staking service implementation bytecode hashes
    mapping(bytes32 => bool) public mapImplementationHashes;
    // Mapping of staking service instances
    mapping(address => bool) public mapInstances;

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

    function addImplementation(bytes32 implementationHash) external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        mapImplementationHashes[implementationHash] = true;
    }

    function createServiceStakingInstance(bytes memory bytecode, bytes memory initPayload, bytes32 salt) external returns (address instance) {
        // Check for the whitelisted bytecode hash
        bytes32 implementationHash = keccak256(bytecode);
        if (!mapImplementationHashes[implementationHash]) {
            revert();
        }

        assembly {
            instance := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
            if iszero(extcodesize(instance)) {
                revert(0, 0)
            }

            if eq(call(gas(), instance, 0, add(initPayload, 0x20), mload(initPayload), 0, 0), 0) {
                revert(0, 0)
            }
        }
        
        // Check for the ERC165 compatibility with ServiceStakingBase
        if (!(IERC165(instance).supportsInterface(0x01ffc9a7) && // ERC165 Interface ID for ERC165
            IERC165(instance).supportsInterface(0xa694fc3a) && // bytes4(keccak256("stake(uint256)"))
            IERC165(instance).supportsInterface(0x2e17de78) && // bytes4(keccak256("unstake(uint256)"))
            IERC165(instance).supportsInterface(0xc2c4c5c1) && // bytes4(keccak256("checkpoint()"))
            IERC165(instance).supportsInterface(0x78e06136) && // bytes4(keccak256("calculateServiceStakingReward(uint256)"))
            IERC165(instance).supportsInterface(0x82a8ea58) // bytes4(keccak256("getServiceInfo(uint256)"))
        )) {
            revert();
        }

        mapInstances[instance] = true;

        emit InstanceCreated(instance, implementationHash);
    }
}