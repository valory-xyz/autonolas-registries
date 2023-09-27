// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../interfaces/IErrorsRegistries.sol";

// Multisig interface
interface IMultisig {
    /// @dev Gets the multisig nonce.
    /// @return Multisig nonce.
    function nonce() external view returns (uint256);
}

// Service Registry interface
interface IService {
    /// @dev Transfers the service that was previously approved to this contract address.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param id Service Id.
    function transferFrom(address from, address to, uint256 id) external;

    /// @dev Gets the service instance from the map of services.
    /// @param serviceId Service Id.
    /// @return securityDeposit Registration activation deposit.
    /// @return multisig Service multisig address.
    /// @return configHash IPFS hashes pointing to the config metadata.
    /// @return threshold Agent instance signers threshold.
    /// @return maxNumAgentInstances Total number of agent instances.
    /// @return numAgentInstances Actual number of agent instances.
    /// @return state Service state.
    function mapServices(uint256 serviceId) external view returns (
        uint96 securityDeposit,
        address multisig,
        bytes32 configHash,
        uint32 threshold,
        uint32 maxNumAgentInstances,
        uint32 numAgentInstances,
        uint8 state
    );
}

/// @dev Received lower value than the expected one.
/// @param provided Provided value is lower.
/// @param expected Expected value.
error LowerThan(uint256 provided, uint256 expected);

/// @dev Service is not staked.
/// @param serviceId Service Id.
error ServiceNotStaked(uint256 serviceId);

// Service Info struct
struct ServiceInfo {
    // Service multisig address
    address multisig;
    // Service owner
    address owner;
    // Service multisig nonce
    uint256 nonce;
    // Staking start time
    uint256 tsStart;
    // Accumulated service staking reward
    uint256 reward;
}

/// @title ServiceStakingBase - Base abstract smart contract for staking a service by its owner
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract ServiceStakingBase is IErrorsRegistries {
    event ServiceStaked(uint256 indexed serviceId, address indexed owner);
    event Checkpoint(uint256 availableRewards, uint256 numServices);
    event ServiceUnstaked(uint256 indexed serviceId, address indexed owner, uint256 reward, uint256 tsStart);
    event Deposit(address indexed sender, uint256 amount, uint256 balance, uint256 availableRewards);
    event Withdraw(address indexed to, uint256 amount);

    // Rewards per second
    uint256 public immutable rewardsPerSecond;
    // Minimum deposit value for staking
    uint256 public immutable minStakingDeposit;
    // Liveness ratio in the format of 1e18
    uint256 public immutable livenessRatio;
    // ServiceRegistry contract address
    address public immutable serviceRegistry;

    // Token / ETH balance
    uint256 public balance;
    // Token / ETH available rewards
    uint256 public availableRewards;
    // Timestamp of the last checkpoint
    uint256 public tsCheckpoint;
    // Minimum token / ETH balance, will be sent along with unstaked reward when going below that balance value
    uint256 public minBalance;
    // Mapping of serviceId => staking service info
    mapping (uint256 => ServiceInfo) public mapServiceInfo;
    // Set of currently staking serviceIds
    uint256[] public setServiceIds;

    /// @dev ServiceStakingBase constructor.
    /// @param _rewardsPerSecond Staking rewards per second (in single digits).
    /// @param _minStakingDeposit Minimum staking deposit for a service to be eligible to stake.
    /// @param _livenessRatio Staking ratio: number of seconds per nonce (in 18 digits).
    /// @param _serviceRegistry ServiceRegistry contract address.
    constructor(uint256 _rewardsPerSecond, uint256 _minStakingDeposit, uint256 _livenessRatio, address _serviceRegistry) {
        // Initial checks
        if (_rewardsPerSecond == 0 || _minStakingDeposit == 0 || _livenessRatio == 0) {
            revert ZeroValue();
        }
        if (_serviceRegistry == address(0)) {
            revert ZeroAddress();
        }

        rewardsPerSecond = _rewardsPerSecond;
        minStakingDeposit = _minStakingDeposit;
        livenessRatio = _livenessRatio;
        serviceRegistry = _serviceRegistry;
    }

    /// @dev Checks token / ETH staking deposit.
    /// @param stakingDeposit Staking deposit.
    function _checkTokenStakingDeposit(uint256, uint256 stakingDeposit) internal view virtual {
        // The staking deposit derived from a security deposit value must be greater or equal to the minimum defined one
        if (stakingDeposit < minStakingDeposit) {
            revert LowerThan(stakingDeposit, minStakingDeposit);
        }
    }

    /// @dev Withdraws the reward amount to a service owner.
    /// @param to Address to.
    /// @param amount Amount to withdraw.
    function _withdraw(address to, uint256 amount) internal virtual {}

    /// @dev Stakes the service.
    /// @param serviceId Service Id.
    function stake(uint256 serviceId) external {
        // Check the service conditions for staking
        (uint96 stakingDeposit, address multisig, , , , , uint8 state) = IService(serviceRegistry).mapServices(serviceId);
        // The service must be deployed
        if (state != 4) {
            revert WrongServiceState(state, serviceId);
        }
        // Check service staking deposit and token, if applicable
        _checkTokenStakingDeposit(serviceId, stakingDeposit);

        // Transfer the service for staking
        IService(serviceRegistry).transferFrom(msg.sender, address(this), serviceId);

        // ServiceInfo struct will be an empty one since otherwise the transferFrom above would fail
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        sInfo.multisig = multisig;
        sInfo.owner = msg.sender;
        sInfo.nonce = IMultisig(multisig).nonce();
        sInfo.tsStart = block.timestamp;

        // Add the service Id to the set of staked services
        setServiceIds.push(serviceId);

        emit ServiceStaked(serviceId, msg.sender);
    }

    /// @dev Calculates staking rewards for all services at current timestamp.
    /// @param lastAvailableRewards Available amount of rewards.
    /// @param numServices Number of services eligible for the reward that passed the liveness check.
    /// @param totalRewards Total calculated rewards.
    /// @param eligibleServiceIds Service Ids eligible for rewards.
    /// @param eligibleServiceRewards Corresponding rewards for eligible service Ids.
    /// @param serviceIds All the staking service Ids.
    /// @param serviceNonces Current service nonces.
    function _calculateStakingRewards() internal view returns (
        uint256 lastAvailableRewards,
        uint256 numServices,
        uint256 totalRewards,
        uint256[] memory eligibleServiceIds,
        uint256[] memory eligibleServiceRewards,
        uint256[] memory serviceIds,
        uint256[] memory serviceNonces
    )
    {
        // Get available rewards and last checkpoint timestamp
        lastAvailableRewards = availableRewards;
        uint256 tsCheckpointLast = tsCheckpoint;

        // Get the service Ids set length
        uint256 size = setServiceIds.length;
        serviceIds = new uint256[](size);
        serviceNonces = new uint256[](size);

        // Record service Ids and nonces
        for (uint256 i = 0; i < size; ++i) {
            // Get current service Id
            serviceIds[i] = setServiceIds[i];

            // Get current service multisig nonce
            address multisig = mapServiceInfo[serviceIds[i]].multisig;
            serviceNonces[i] = IMultisig(multisig).nonce();
        }

        // If available rewards are not zero, proceed with staking calculation
        if (lastAvailableRewards > 0) {
            // Get necessary arrays
            eligibleServiceIds = new uint256[](size);
            eligibleServiceRewards = new uint256[](size);

            // Calculate each staked service reward eligibility
            for (uint256 i = 0; i < size; ++i) {
                // Get the service info
                uint256 curServiceId = serviceIds[i];
                ServiceInfo storage curInfo = mapServiceInfo[curServiceId];

                // Calculate the staking nonce ratio
                // Get the last service checkpoint: staking start time or the global checkpoint timestamp
                uint256 serviceCheckpoint = tsCheckpointLast;
                // Adjust the service checkpoint time if the service was staking less than the current staking period
                if (curInfo.tsStart > tsCheckpointLast) {
                    serviceCheckpoint = curInfo.tsStart;
                }
                // Calculate the liveness ratio in 1e18 value
                uint256 ratio;
                // If the checkpoint was called in the exactly same block, the ratio is zero
                if (block.timestamp > serviceCheckpoint) {
                    uint256 nonce = serviceNonces[i];
                    ratio = ((nonce - curInfo.nonce) * 1e18) / (block.timestamp - serviceCheckpoint);
                }

                // Record the reward for the service if it has provided enough transactions
                if (ratio >= livenessRatio) {
                    // Calculate the reward up until now and record its value for the corresponding service
                    uint256 reward = rewardsPerSecond * (block.timestamp - serviceCheckpoint);
                    totalRewards += reward;
                    eligibleServiceRewards[numServices] = reward;
                    eligibleServiceIds[numServices] = curServiceId;
                    ++numServices;
                }
            }
        }
    }

    /// @dev Checkpoint to allocate rewards up until a current time.
    /// @return All staking service Ids.
    /// @return Number of staking eligible services.
    /// @return Eligible service Ids.
    /// @return Eligible service rewards.
    function checkpoint() public returns (uint256[] memory, uint256, uint256[] memory, uint256[] memory) {
        // Calculate staking rewards
        (uint256 lastAvailableRewards, uint256 numServices, uint256 totalRewards,
            uint256[] memory eligibleServiceIds, uint256[] memory eligibleServiceRewards,
            uint256[] memory serviceIds, uint256[] memory serviceNonces) = _calculateStakingRewards();

        // If available rewards are not zero, proceed with staking calculation
        if (lastAvailableRewards > 0) {
            // If total allocated rewards are not enough, adjust the reward value
            if (totalRewards > lastAvailableRewards) {
                // Traverse all the eligible services and adjust their rewards proportional to leftovers
                totalRewards = 0;
                for (uint256 i = 0; i < numServices; ++i) {
                    // Calculate the updated reward
                    uint256 updatedReward = (eligibleServiceRewards[i] * lastAvailableRewards) / totalRewards;
                    // Add to the total updated reward
                    totalRewards += updatedReward;
                    // Add reward to the service overall reward
                    uint256 curServiceId = eligibleServiceIds[i];
                    mapServiceInfo[curServiceId].reward += updatedReward;
                }

                // If the reward adjustment happened to have small leftovers, add it to the last traversed service
                if (lastAvailableRewards > totalRewards) {
                    mapServiceInfo[numServices - 1].reward += lastAvailableRewards - totalRewards;
                }
                // Set available rewards to zero
                lastAvailableRewards = 0;
            } else {
                // Traverse all the eligible services and add to their rewards
                for (uint256 i = 0; i < numServices; ++i) {
                    // Add reward to the service overall reward
                    uint256 curServiceId = eligibleServiceIds[i];
                    mapServiceInfo[curServiceId].reward += eligibleServiceRewards[i];
                }

                // Adjust available rewards
                lastAvailableRewards -= totalRewards;
            }

            // Update the storage value of available rewards
            availableRewards = lastAvailableRewards;
        }

        // Updated current service nonces
        for (uint256 i = 0; i < serviceIds.length; ++i) {
            // Get the current service Id
            uint256 curServiceId = serviceIds[i];
            mapServiceInfo[curServiceId].nonce = serviceNonces[i];
        }

        // Record the current timestamp such that next calculations start from this point of time
        tsCheckpoint = block.timestamp;

        emit Checkpoint(lastAvailableRewards, numServices);

        return (serviceIds, numServices, eligibleServiceIds, eligibleServiceRewards);
    }

    /// @dev Unstakes the service.
    /// @param serviceId Service Id.
    function unstake(uint256 serviceId) external {
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        // Check for the service ownership
        if (msg.sender != sInfo.owner) {
            revert OwnerOnly(msg.sender, sInfo.owner);
        }

        // Call the checkpoint
        (uint256[] memory serviceIds, , , ) = checkpoint();

        // Get the service index in the set of services
        // The index must always exist as the service is currently staked, otherwise it has no record in the map
        uint256 idx;
        for (; idx < serviceIds.length; ++idx) {
            if (serviceIds[idx] == serviceId) {
                break;
            }
        }

        // Transfer the service back to the owner
        IService(serviceRegistry).transferFrom(address(this), msg.sender, serviceId);

        // Send the remaining small balance along with the reward if it is below the chosen threshold
        uint256 amount = sInfo.reward;
        uint256 lastAvailableRewards = availableRewards;
        if (lastAvailableRewards < minBalance) {
            amount += lastAvailableRewards;
            availableRewards = 0;
        }

        // Transfer accumulated rewards to the service multisig
        if (amount > 0) {
            _withdraw(sInfo.multisig, amount);
        }

        // Record staking start time
        uint256 tsStart = sInfo.tsStart;

        // Clear all the data about the unstaked service
        // Delete the service info struct
        delete mapServiceInfo[serviceId];

        // Update the set of staked service Ids
        setServiceIds[idx] = setServiceIds[setServiceIds.length - 1];
        setServiceIds.pop();

        emit ServiceUnstaked(serviceId, msg.sender, amount, tsStart);
    }

    /// @dev Calculates service staking reward at current timestamp.
    /// @param serviceId Service Id.
    /// @return reward Service reward.
    function calculateServiceStakingReward(uint256 serviceId) external view returns (uint256 reward) {
        // Get current service reward
        ServiceInfo memory sInfo = mapServiceInfo[serviceId];
        reward = sInfo.reward;

        // Check if the service is staked
        if (sInfo.tsStart == 0) {
            revert ServiceNotStaked(serviceId);
        }

        // Calculate overall staking rewards
        (uint256 lastAvailableRewards, , uint256 totalRewards, uint256[] memory eligibleServiceIds,
            uint256[] memory eligibleServiceRewards, , ) = _calculateStakingRewards();

        // If available rewards are not zero, proceed with staking calculation
        if (lastAvailableRewards > 0) {
            // Get the service index in the eligible service set and calculate its latest reward
            for (uint256 i = 0; i < eligibleServiceIds.length; ++i) {
                if (eligibleServiceIds[i] == serviceId) {
                    // If total allocated rewards are not enough, adjust the reward value
                    if (totalRewards > lastAvailableRewards) {
                        reward += (eligibleServiceRewards[i] * lastAvailableRewards) / totalRewards;
                    } else {
                        reward += eligibleServiceRewards[i];
                    }
                    break;
                }
            }
        }
    }
}