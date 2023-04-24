// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title MockServiceRegistry - Smart contract for mocking some of the service registry functionality
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract MockServiceRegistry {
    mapping(uint256 => address) mapServiceOwners;

    function setServiceOwner(uint256 serviceId, address serviceOwner) external {
        mapServiceOwners[serviceId] = serviceOwner;
    }

    function ownerOf(uint256 serviceId) external view returns (address serviceOwner){
        serviceOwner = mapServiceOwners[serviceId];
    }
}
