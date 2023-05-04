// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title MockServiceRegistry - Smart contract for mocking some of the service registry functionality
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract MockServiceRegistry {
    mapping(uint256 => address) public mapServiceOwners;

    function setServiceOwner(uint256 serviceId, address serviceOwner) external {
        mapServiceOwners[serviceId] = serviceOwner;
    }

    function ownerOf(uint256 serviceId) external view returns (address serviceOwner){
        serviceOwner = mapServiceOwners[serviceId];
    }

    function mapServices(uint256 serviceId) external view returns (
        uint96,
        address multisig,
        bytes32,
        uint32,
        uint32,
        uint32,
        uint8 state
    ) {
        multisig = mapServiceOwners[serviceId];
        // Hardcode state to be equal to Deployed if the service Id is in the specified range
        if (serviceId > 0 && serviceId < 100) {
            state = 4;
        }

        return (0, multisig, bytes32(0), 0, 0, 0, state);
    }

    /// @dev Gets the operator address from the map of agent instance address => operator address
    function mapAgentInstanceOperators(address agentInstance) external pure returns (address operator) {
        operator = agentInstance;
    }
}
