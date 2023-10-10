// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;
import "../../lib/solmate/src/tokens/ERC721.sol";

// ServiceStaking interface
interface IServiceStaking {
    /// @dev Stakes the service.
    /// @param serviceId Service Id.
    function stake(uint256 serviceId) external;

    /// @dev Unstakes the service.
    /// @param serviceId Service Id.
    function unstake(uint256 serviceId) external;

    /// @dev Checkpoint to allocate rewards up until a current time.
    /// @return All staking service Ids.
    /// @return All staking updated nonces.
    /// @return Number of reward-eligible staking services during current checkpoint period.
    /// @return Eligible service Ids.
    /// @return Eligible service rewards.
    /// @return success True, if the checkpoint was successful.
    function checkpoint() external returns (
        uint256[] memory,
        uint256[] memory,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bool
    );
}

// ServiceRegistry interface
interface IServiceRegistry {
    /// @dev Approves a service for transfer.
    /// @param spender Account address that will be able to transfer the token on behalf of the caller.
    /// @param serviceId Service Id.
    function approve(address spender, uint256 serviceId) external;
}

contract ReentrancyStakingAttacker is ERC721TokenReceiver {
    // Service Staking
    address public immutable serviceStaking;
    // Service Registry
    address public immutable serviceRegistry;
    // Attack argument
    bool public attack = true;
    // Nonce
    uint256 internal _nonce;
    // Owners
    address[] public owners;

    constructor(address _serviceStaking, address _serviceRegistry) {
        serviceStaking = _serviceStaking;
        serviceRegistry = _serviceRegistry;
    }
    
    /// @dev Failing receive.
    receive() external payable {
        revert();
    }

    function setAttack(bool status) external {
        attack = status;
    }

    function setOwner(address owner) external {
        owners.push(owner);
    }

    function inceraseNonce() external {
        _nonce += 1000;
    }

    /// @dev Malicious contract function call during the service token return.
    function onERC721Received(address, address, uint256 serviceId, bytes memory) public virtual override returns (bytes4) {
        if (attack) {
            IServiceStaking(serviceStaking).unstake(serviceId);
        }
        return this.onERC721Received.selector;
    }

    /// @dev Unstake the service.
    function unstake(uint256 serviceId) external {
        IServiceStaking(serviceStaking).unstake(serviceId);
    }

    /// @dev Stake the service and call the checkpoint right away.
    function stakeAndCheckpoint(uint256 serviceId) external {
        IServiceRegistry(serviceRegistry).approve(serviceStaking, serviceId);
        IServiceStaking(serviceStaking).stake(serviceId);
        IServiceStaking(serviceStaking).checkpoint();
    }

    /// @dev Gets set of owners.
    /// @return owners Set of Safe owners.
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /// @dev Gets threshold.
    /// @return Threshold
    function getThreshold() external view returns (uint256) {
        return owners.length;
    }

    /// @dev Gets the multisig nonce.
    /// @return Multisig nonce.
    function nonce() external view returns (uint256) {
        return _nonce;
    }
}