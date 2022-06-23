// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./GenericManager.sol";
import "./interfaces/IRegistry.sol";

/// @title Registries Manager - Periphery smart contract for managing components and agents
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract RegistriesManager is GenericManager {
    // Component registry address
    address public immutable componentRegistry;
    // Agent registry address
    address public immutable agentRegistry;
    // Mint fee
    uint256 private _mintFee;

    constructor(address _componentRegistry, address _agentRegistry) {
        componentRegistry = _componentRegistry;
        agentRegistry = _agentRegistry;
        owner = msg.sender;
    }

    /// @dev Creates agent.
    /// @param agentOwner Owner of the agent.
    /// @param developer Developer of the agent.
    /// @param agentHash IPFS hash of the agent.
    /// @param description Description of the agent.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted agent.
    function createAgent(
        address agentOwner,
        address developer,
        IRegistry.Multihash memory agentHash,
        string memory description,
        uint256[] memory dependencies
    ) external returns (uint256)
    {
        // Check if the minting is paused
        if (paused) {
            revert Paused();
        }
        return IRegistry(agentRegistry).create(agentOwner, developer, agentHash, description, dependencies);
    }

    /// @dev Updates the agent hash.
    /// @param tokenId Token Id.
    /// @param agentHash New IPFS hash of the agent.
    function updateAgentHash(uint256 tokenId, IRegistry.Multihash memory agentHash) external {
        return IRegistry(agentRegistry).updateHash(msg.sender, tokenId, agentHash);
    }

    /// @dev Creates component.
    /// @param componentOwner Owner of the component.
    /// @param developer Developer of the component.
    /// @param componentHash IPFS hash of the component.
    /// @param description Description of the component.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted component.
    function createComponent(
        address componentOwner,
        address developer,
        IRegistry.Multihash memory componentHash,
        string memory description,
        uint256[] memory dependencies
    ) external returns (uint256)
    {
        // Check if the minting is paused
        if (paused) {
            revert Paused();
        }
        return IRegistry(componentRegistry).create(componentOwner, developer, componentHash, description, dependencies);
    }

    /// @dev Updates the component hash.
    /// @param tokenId Token Id.
    /// @param componentHash New IPFS hash of the component.
    function updateComponentHash(uint256 tokenId, IRegistry.Multihash memory componentHash) external {
        return IRegistry(componentRegistry).updateHash(msg.sender, tokenId, componentHash);
    }
}
