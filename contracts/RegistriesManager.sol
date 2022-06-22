// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./interfaces/IErrorsRegistries.sol";
import "./interfaces/IRegistry.sol";

/// @title Registries Manager - Periphery smart contract for managing components and agents
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract RegistriesManager is IErrorsRegistries, IStructs {
    event OwnerUpdated(address indexed owner);
    event Pause(address indexed owner);
    event Unpause(address indexed owner);

    // Component registry address
    address public immutable componentRegistry;
    // Agent registry address
    address public immutable agentRegistry;
    // Owner address
    address public owner;
    // Mint fee
    uint256 private _mintFee;
    // Pause switch
    bool public paused;

    constructor(address _componentRegistry, address _agentRegistry) {
        componentRegistry = _componentRegistry;
        agentRegistry = _agentRegistry;
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

    /// @dev Mints agent.
    /// @param agentOwner Owner of the agent.
    /// @param developer Developer of the agent.
    /// @param agentHash IPFS hash of the agent.
    /// @param description Description of the agent.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted agent.
    function mintAgent(
        address agentOwner,
        address developer,
        Multihash memory agentHash,
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
    function updateAgentHash(uint256 tokenId, Multihash memory agentHash) external {
        return IRegistry(agentRegistry).updateHash(msg.sender, tokenId, agentHash);
    }

    /// @dev Mints component.
    /// @param componentOwner Owner of the component.
    /// @param developer Developer of the component.
    /// @param componentHash IPFS hash of the component.
    /// @param description Description of the component.
    /// @param dependencies Set of component dependencies in a sorted ascending order.
    /// @return The id of a minted component.
    function mintComponent(
        address componentOwner,
        address developer,
        Multihash memory componentHash,
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
    function updateComponentHash(uint256 tokenId, Multihash memory componentHash) external {
        return IRegistry(componentRegistry).updateHash(msg.sender, tokenId, componentHash);
    }

    /// @dev Pauses the contract.
    function pause() external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = true;
        emit Pause(owner);
    }

    /// @dev Unpauses the contract.
    function unpause() external {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        paused = false;
        emit Unpause(owner);
    }
}
