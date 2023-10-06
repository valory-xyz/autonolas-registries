// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;
import "../../lib/solmate/src/tokens/ERC721.sol";

// ServiceRegistry interface
interface IServiceRegistry {
    /// @dev Creates a new service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function create(
        address serviceOwner,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint32 threshold
    ) external returns (uint256 serviceId);

    /// @dev Creates multisig instance controlled by the set of service agent instances and deploys the service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @param multisigImplementation Multisig implementation address.
    /// @param data Data payload for the multisig creation.
    /// @return multisig Address of the created multisig.
    function deploy(
        address serviceOwner,
        uint256 serviceId,
        address multisigImplementation,
        bytes memory data
    ) external returns (address multisig);

    /// @dev Terminates the service.
    /// @param serviceOwner Owner of the service.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    /// @return refund Refund to return to the service owner.
    function terminate(address serviceOwner, uint256 serviceId) external returns (bool success, uint256 refund);

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param operator Operator of agent instances.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function unbond(address operator, uint256 serviceId) external returns (bool success, uint256 refund);

    /// @dev Drains slashed funds.
    /// @return amount Drained amount.
    function drain() external returns (uint256 amount);
}

interface IUnitRegistry {
    /// @dev Creates unit.
    /// @param unitOwner Owner of the unit.
    /// @param unitHash IPFS CID hash of the unit.
    /// @param dependencies Set of unit dependencies in a sorted ascending order (unit Ids).
    /// @return unitId The id of a minted unit.
    function create(address unitOwner, bytes32 unitHash, uint32[] memory dependencies)
        external returns (uint256 unitId);
}

struct AgentParams {
    // Number of agent instances. This number is limited by the number of agent instances
    uint32 slots;
    // Bond per agent instance. This is enough for 1b+ ETH or 1e27
    uint96 bond;
}

contract ReentrancyAttacker is ERC721TokenReceiver {
    // Component Registry
    address public immutable componentRegistry;
    // Service Registry
    address public immutable serviceRegistry;

    address public serviceOwner;
    bytes32 public configHash;
    uint32[] public agentIds;
    AgentParams[] public agentParams;
    uint32 public threshold;
    bool public badAction;
    bool public attackOnCreate;
    bool public attackOnTerminate;
    bool public attackOnUnbond;

    constructor(address _componentRegistry, address _serviceRegistry) {
        componentRegistry = _componentRegistry;
        serviceRegistry = _serviceRegistry;
    }
    
    /// @dev wallet
    receive() external payable {
        if (attackOnTerminate) {
            IServiceRegistry(serviceRegistry).terminate(address(this), 0);
        } else if (attackOnUnbond) {
            IServiceRegistry(serviceRegistry).unbond(address(this), 0);
        } else {
            IServiceRegistry(serviceRegistry).drain();
        }
        attackOnTerminate = false;
        attackOnUnbond = false;
        badAction = true;
    }

    /// @dev Lets attacker call create a component with onERC721Receive during the token mint.
    function createBadComponent(
        address _unitOwner,
        bytes32 _unitHash,
        uint32[] memory _dependencies
    ) external returns (uint256 unitId)
    {
        unitId = IUnitRegistry(componentRegistry).create(_unitOwner, _unitHash, _dependencies);
    }

    /// @dev Lets attacker call create a service with onERC721Receive during the token mint.
    function createBadService(
        address _serviceOwner,
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
        configHash = _configHash;
        serviceId = IServiceRegistry(serviceRegistry).create(_serviceOwner, _configHash, _agentIds,
            _agentParams, _threshold);
    }

    /// @dev Sets the attack during creation of a service.
    function setAttackOnCreate(bool _attackOnCreate) external {
        attackOnCreate = _attackOnCreate;
    }

    /// @dev Malicious contract function call during the token mint.
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        if (attackOnCreate) {
            uint256 unitId;
            if (serviceRegistry == address(0)) {
                uint32[] memory dependencies = new uint32[](1);
                unitId = IUnitRegistry(componentRegistry).create(address(this), configHash, dependencies);
            } else {
                unitId = IServiceRegistry(serviceRegistry).create(address(this), configHash, agentIds, agentParams, 6);
            }
            badAction = true;
        }
        return this.onERC721Received.selector;
    }

    /// @dev Lets attacker call the deploy() function to return to it via a multisig implementation.
    function deployBadMultisig(
        address _serviceOwner,
        uint256 _serviceId,
        address _multisigImplementation,
        bytes memory _data
    ) external returns (address)
    {
        return IServiceRegistry(serviceRegistry).deploy(_serviceOwner, _serviceId, _multisigImplementation, _data);
    }

    /// @dev Simulation of a multisig implementation create() function of the attacker
    function create(
        address[] memory,
        uint256,
        bytes memory
    ) external returns (address)
    {
        IServiceRegistry(serviceRegistry).deploy(serviceOwner, 0, address(this), "0x");
        badAction = true;
        return address(this);
    }

    /// @dev Lets the attacker call back its contract to get back to the terminate() function.
    function terminateBadRefund(address _serviceOwner, uint256 _serviceId) external returns (bool, uint256) {
        attackOnTerminate = true;
        return IServiceRegistry(serviceRegistry).terminate(_serviceOwner, _serviceId);
    }

    /// @dev Lets the attacker call back its contract to get back to the unbond() function.
    function unbondBadOperator(address operator, uint256 serviceId) external returns (bool, uint256) {
        attackOnUnbond = true;
        return IServiceRegistry(serviceRegistry).unbond(operator, serviceId);
    }

    /// @dev Lets the attacker call back its contract to get back to the drain() function.
    function drainFromBadAddress() external returns (uint256) {
        return IServiceRegistry(serviceRegistry).drain();
    }
}