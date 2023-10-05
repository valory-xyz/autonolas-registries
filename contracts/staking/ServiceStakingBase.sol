// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ERC721TokenReceiver} from "../../lib/solmate/src/tokens/ERC721.sol";
import "../interfaces/IErrorsRegistries.sol";

// Multisig interface
interface IMultisig {
    /// @dev Gets the multisig nonce.
    /// @return Multisig nonce.
    function nonce() external view returns (uint256);
}

// Service Registry interface
interface IService {
    enum UnitType {
        Component,
        Agent
    }

    /// @dev Transfers the service that was previously approved to this contract address.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param id Service Id.
    function safeTransferFrom(address from, address to, uint256 id) external;

    /// @dev Gets service parameters from the map of services.
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

    /// @dev Gets the full set of linearized components / canonical agent Ids for a specified service.
    /// @notice The service must be / have been deployed in order to get the actual data.
    /// @param serviceId Service Id.
    /// @return numUnitIds Number of component / agent Ids.
    /// @return unitIds Set of component / agent Ids.
    function getUnitIdsOfService(UnitType unitType, uint256 serviceId) external view
        returns (uint256 numUnitIds, uint32[] memory unitIds);
}

/// @dev No rewards are available in the contract.
error NoRewardsAvailable();

/// @dev Maximum number of staking services is reached.
/// @param maxNumServices Maximum number of staking services.
error MaxNumServicesReached(uint256 maxNumServices);

/// @dev Received lower value than the expected one.
/// @param provided Provided value is lower.
/// @param expected Expected value.
error LowerThan(uint256 provided, uint256 expected);

/// @dev Required service configuration is wrong.
/// @param serviceId Service Id.
error WrongServiceConfiguration(uint256 serviceId);

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
abstract contract ServiceStakingBase is ERC721TokenReceiver, IErrorsRegistries {
    struct StakingParams {
        // Maximum number of staking services
        uint256 maxNumServices;
        // Rewards per second
        uint256 rewardsPerSecond;
        // Minimum service staking deposit value required for staking
        uint256 minStakingDeposit;
        // Liveness period
        uint256 livenessPeriod;
        // Liveness ratio in the format of 1e18
        uint256 livenessRatio;
        // Number of agent instances in the service
        uint256 numAgentInstances;
        // Optional agent Ids requirement
        uint256[] agentIds;
        // Optional service multisig threshold requirement
        uint256 threshold;
        // Optional service configuration hash requirement
        bytes32 configHash;
    }

    event ServiceStaked(uint256 indexed serviceId, address indexed owner, address indexed multisig, uint256 nonce);
    event Checkpoint(uint256 availableRewards, uint256 numServices);
    event ServiceUnstaked(uint256 indexed serviceId, address indexed owner, address indexed multisig, uint256 nonce,
        uint256 reward, uint256 tsStart);
    event Deposit(address indexed sender, uint256 amount, uint256 balance, uint256 availableRewards);
    event Withdraw(address indexed to, uint256 amount);

    // Contract version
    string public constant VERSION = "0.1.0";
    // Maximum number of staking services
    uint256 public immutable maxNumServices;
    // Rewards per second
    uint256 public immutable rewardsPerSecond;
    // Minimum service staking deposit value required for staking
    uint256 public immutable minStakingDeposit;
    // Liveness period
    uint256 public immutable livenessPeriod;
    // Liveness ratio in the format of 1e18
    uint256 public immutable livenessRatio;
    // Number of agent instances in the service
    uint256 public immutable numAgentInstances;
    // Optional service multisig threshold requirement
    uint256 public immutable threshold;
    // Optional service configuration hash requirement
    bytes32 public immutable configHash;
    // ServiceRegistry contract address
    address public immutable serviceRegistry;

    // Token / ETH balance
    uint256 public balance;
    // Token / ETH available rewards
    uint256 public availableRewards;
    // Timestamp of the last checkpoint
    uint256 public tsCheckpoint;
    // Optional agent Ids requirement
    uint256[] public agentIds;
    // Mapping of serviceId => staking service info
    mapping (uint256 => ServiceInfo) public mapServiceInfo;
    // Set of currently staking serviceIds
    uint256[] public setServiceIds;

    /// @dev ServiceStakingBase constructor.
    /// @param _stakingParams Service staking parameters.
    /// @param _serviceRegistry ServiceRegistry contract address.
    constructor(StakingParams memory _stakingParams, address _serviceRegistry) {
        // Initial checks
        if (_stakingParams.maxNumServices == 0 || _stakingParams.rewardsPerSecond == 0 ||
            _stakingParams.minStakingDeposit == 0 || _stakingParams.livenessPeriod == 0 ||
            _stakingParams.livenessRatio == 0 || _stakingParams.numAgentInstances == 0) {
            revert ZeroValue();
        }
        if (_serviceRegistry == address(0)) {
            revert ZeroAddress();
        }

        // Assign all the required parameters
        maxNumServices = _stakingParams.maxNumServices;
        rewardsPerSecond = _stakingParams.rewardsPerSecond;
        minStakingDeposit = _stakingParams.minStakingDeposit;
        livenessPeriod = _stakingParams.livenessPeriod;
        livenessRatio = _stakingParams.livenessRatio;
        numAgentInstances = _stakingParams.numAgentInstances;
        serviceRegistry = _serviceRegistry;

        // Assign optional parameters
        threshold = _stakingParams.threshold;
        configHash = _stakingParams.configHash;

        // Assign agent Ids, if applicable
        uint256 size = _stakingParams.agentIds.length;
        uint256 agentId;
        if (size > 0) {
            for (uint256 i = 0; i < size; ++i) {
                // Agent Ids must be unique and in ascending order
                if (_stakingParams.agentIds[i] <= agentId) {
                    revert WrongAgentId(_stakingParams.agentIds[i]);
                }
                agentId = _stakingParams.agentIds[i];
                agentIds.push(agentId);
            }
        }

        // Set the checkpoint timestamp to be the deployment one
        tsCheckpoint = block.timestamp;
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
    function _withdraw(address to, uint256 amount) internal virtual;

    /// @dev Stakes the service.
    /// @param serviceId Service Id.
    function stake(uint256 serviceId) external {
        // Check if there available rewards
        if (availableRewards == 0) {
            revert NoRewardsAvailable();
        }

        // Check for the maximum number of staking services
        uint256 numStakingServices = setServiceIds.length;
        if (numStakingServices == maxNumServices) {
            revert MaxNumServicesReached(maxNumServices);
        }

        // Check the service conditions for staking
        (uint96 stakingDeposit, address multisig, bytes32 hash, uint256 agentThreshold, uint256 maxNumInstances, , uint8 state) =
            IService(serviceRegistry).mapServices(serviceId);

        // Check the number of agent instances
        if (numAgentInstances != maxNumInstances) {
            revert WrongServiceConfiguration(serviceId);
        }

        // Check the configuration hash, if applicable
        if (configHash != bytes32(0) && configHash != hash) {
            revert WrongServiceConfiguration(serviceId);
        }
        // Check the threshold, if applicable
        if (threshold > 0 && threshold != agentThreshold) {
            revert WrongServiceConfiguration(serviceId);
        }
        // The service must be deployed
        if (state != 4) {
            revert WrongServiceState(state, serviceId);
        }
        // Check the agent Ids requirement, if applicable
        uint256 size = agentIds.length;
        if (size > 0) {
            (uint256 numAgents, uint32[] memory agents) =
                IService(serviceRegistry).getUnitIdsOfService(IService.UnitType.Agent, serviceId);

            if (size != numAgents) {
                revert WrongServiceConfiguration(serviceId);
            }
            for (uint256 i = 0; i < numAgents; ++i) {
                if (agentIds[i] != agents[i]) {
                    revert WrongAgentId(agentIds[i]);
                }
            }
        }

        // Check service staking deposit and token, if applicable
        _checkTokenStakingDeposit(serviceId, stakingDeposit);

        // Transfer the service for staking
        IService(serviceRegistry).safeTransferFrom(msg.sender, address(this), serviceId);

        // ServiceInfo struct will be an empty one since otherwise the safeTransferFrom above would fail
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        sInfo.multisig = multisig;
        sInfo.owner = msg.sender;
        uint256 nonce = IMultisig(multisig).nonce();
        sInfo.nonce = nonce;
        sInfo.tsStart = block.timestamp;

        // Add the service Id to the set of staked services
        setServiceIds.push(serviceId);

        emit ServiceStaked(serviceId, msg.sender, multisig, nonce);
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
        // Get the service Ids set length
        uint256 size = setServiceIds.length;
        serviceIds = new uint256[](size);

        // Record service Ids
        for (uint256 i = 0; i < size; ++i) {
            // Get current service Id
            serviceIds[i] = setServiceIds[i];
        }

        // Check the last checkpoint timestamp and the liveness period
        uint256 tsCheckpointLast = tsCheckpoint;
        if (block.timestamp - tsCheckpointLast >= livenessPeriod) {
            // Get available rewards and last checkpoint timestamp
            lastAvailableRewards = availableRewards;

            // If available rewards are not zero, proceed with staking calculation
            if (lastAvailableRewards > 0) {
                // Get necessary arrays
                eligibleServiceIds = new uint256[](size);
                eligibleServiceRewards = new uint256[](size);
                serviceNonces = new uint256[](size);

                // Calculate each staked service reward eligibility
                for (uint256 i = 0; i < size; ++i) {
                    // Get the service info
                    ServiceInfo storage curInfo = mapServiceInfo[serviceIds[i]];

                    // Get current service multisig nonce
                    serviceNonces[i] = IMultisig(curInfo.multisig).nonce();

                    // Calculate the liveness nonce ratio
                    // Get the last service checkpoint: staking start time or the global checkpoint timestamp
                    uint256 serviceCheckpoint = tsCheckpointLast;
                    uint256 ts = curInfo.tsStart;
                    // Adjust the service checkpoint time if the service was staking less than the current staking period
                    if (ts > serviceCheckpoint) {
                        serviceCheckpoint = ts;
                    }

                    // Calculate the liveness ratio in 1e18 value
                    // This subtraction is always positive or zero, as the last checkpoint can be at most block.timestamp
                    ts = block.timestamp - serviceCheckpoint;
                    uint256 ratio;
                    // If the checkpoint was called in the exact same block, the ratio is zero
                    if (ts > 0) {
                        ratio = ((serviceNonces[i] - curInfo.nonce) * 1e18) / ts;
                    }

                    // Record the reward for the service if it has provided enough transactions
                    if (ratio >= livenessRatio) {
                        // Calculate the reward up until now and record its value for the corresponding service
                        uint256 reward = rewardsPerSecond * ts;
                        totalRewards += reward;
                        eligibleServiceRewards[numServices] = reward;
                        eligibleServiceIds[numServices] = serviceIds[i];
                        ++numServices;
                    }
                }
            }
        }
    }

    /// @dev Checkpoint to allocate rewards up until a current time.
    /// @return All staking service Ids.
    /// @return All staking updated nonces.
    /// @return Number of reward-eligible staking services during current checkpoint period.
    /// @return Eligible service Ids.
    /// @return Eligible service rewards.
    /// @return success True, if the checkpoint was successful.
    function checkpoint() public returns (
        uint256[] memory,
        uint256[] memory,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bool success
    )
    {
        // Calculate staking rewards
        (uint256 lastAvailableRewards, uint256 numServices, uint256 totalRewards,
            uint256[] memory eligibleServiceIds, uint256[] memory eligibleServiceRewards,
            uint256[] memory serviceIds, uint256[] memory serviceNonces) = _calculateStakingRewards();

        // If there are eligible services, proceed with staking calculation and update rewards
        if (numServices > 0) {
            // If total allocated rewards are not enough, adjust the reward value
            if (totalRewards > lastAvailableRewards) {
                // Traverse all the eligible services and adjust their rewards proportional to leftovers
                uint256 updatedReward;
                uint256 updatedTotalRewards;
                uint256 curServiceId;
                for (uint256 i = 1; i < numServices; ++i) {
                    // Calculate the updated reward
                    updatedReward = (eligibleServiceRewards[i] * lastAvailableRewards) / totalRewards;
                    // Add to the total updated reward
                    updatedTotalRewards += updatedReward;
                    // Add reward to the overall service reward
                    curServiceId = eligibleServiceIds[i];
                    mapServiceInfo[curServiceId].reward += updatedReward;
                }

                // Process the first service in the set
                updatedReward = (eligibleServiceRewards[0] * lastAvailableRewards) / totalRewards;
                updatedTotalRewards += updatedReward;
                curServiceId = eligibleServiceIds[0];
                // If the reward adjustment happened to have small leftovers, add it to the first service
                if (lastAvailableRewards > updatedTotalRewards) {
                    updatedReward += lastAvailableRewards - updatedTotalRewards;
                }
                // Add reward to the overall service reward
                mapServiceInfo[curServiceId].reward += updatedReward;
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
                // TODO: Fuzz this such that totalRewards is never bigger than lastAvailableRewards
                lastAvailableRewards -= totalRewards;
            }

            // Update the storage value of available rewards
            availableRewards = lastAvailableRewards;
        }

        // If service nonces were updated, then the checkpoint takes place, otherwise only service Ids are returned
        if (serviceNonces.length > 0) {
            // Updated current service nonces
            for (uint256 i = 0; i < serviceIds.length; ++i) {
                // Get the current service Id
                uint256 curServiceId = serviceIds[i];
                mapServiceInfo[curServiceId].nonce = serviceNonces[i];
            }

            // Record the current timestamp such that next calculations start from this point of time
            tsCheckpoint = block.timestamp;

            success = true;

            emit Checkpoint(lastAvailableRewards, numServices);
        }

        return (serviceIds, serviceNonces, numServices, eligibleServiceIds, eligibleServiceRewards, success);
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
        (uint256[] memory serviceIds, , , , , ) = checkpoint();

        // Get the service index in the set of services
        // The index must always exist as the service is currently staked, otherwise it has no record in the map
        uint256 idx;
        for (; idx < serviceIds.length; ++idx) {
            if (serviceIds[idx] == serviceId) {
                break;
            }
        }

        // Transfer the service back to the owner
        IService(serviceRegistry).safeTransferFrom(address(this), msg.sender, serviceId);

        // Transfer accumulated rewards to the service multisig
        if (sInfo.reward > 0) {
            _withdraw(sInfo.multisig, sInfo.reward);
        }

        // Clear all the data about the unstaked service
        // Delete the service info struct
        delete mapServiceInfo[serviceId];

        // Update the set of staked service Ids
        setServiceIds[idx] = setServiceIds[setServiceIds.length - 1];
        setServiceIds.pop();

        emit ServiceUnstaked(serviceId, msg.sender, sInfo.multisig, sInfo.nonce, sInfo.reward, sInfo.tsStart);
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
        (uint256 lastAvailableRewards, uint256 numServices, uint256 totalRewards, uint256[] memory eligibleServiceIds,
            uint256[] memory eligibleServiceRewards, , ) = _calculateStakingRewards();

        // If there are eligible services, proceed with staking calculation and update rewards for the service Id
        if (numServices > 0) {
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