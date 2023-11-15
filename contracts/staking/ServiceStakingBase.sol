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
    enum ServiceState {
        NonExistent,
        PreRegistration,
        ActiveRegistration,
        FinishedRegistration,
        Deployed,
        TerminatedBonded
    }

    // Service parameters
    struct Service {
        // Registration activation deposit
        uint96 securityDeposit;
        // Multisig address for agent instances
        address multisig;
        // IPFS hashes pointing to the config metadata
        bytes32 configHash;
        // Agent instance signers threshold
        uint32 threshold;
        // Total number of agent instances
        uint32 maxNumAgentInstances;
        // Actual number of agent instances
        uint32 numAgentInstances;
        // Service state
        ServiceState state;
        // Canonical agent Ids for the service
        uint32[] agentIds;
    }

    /// @dev Transfers the service that was previously approved to this contract address.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param id Service Id.
    function safeTransferFrom(address from, address to, uint256 id) external;

    /// @dev Gets the service instance.
    /// @param serviceId Service Id.
    /// @return service Corresponding Service struct.
    function getService(uint256 serviceId) external view returns (Service memory service);
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

/// @dev Service is not unstaked.
/// @param serviceId Service Id.
error ServiceNotUnstaked(uint256 serviceId);

/// @dev Service is not found.
/// @param serviceId Service Id.
error ServiceNotFound(uint256 serviceId);

/// @dev Service was not staked a minimum required time.
/// @param serviceId Service Id.
/// @param tsProvided Time the service is staked for.
/// @param tsExpected Minimum time the service needs to be staked for.
error NotEnoughTimeStaked(uint256 serviceId, uint256 tsProvided, uint256 tsExpected);

// Service Info struct
struct ServiceInfo {
    // Service multisig address
    address multisig;
    // Service owner
    address owner;
    // Service multisig nonces
    uint256[] nonces;
    // Staking start time
    uint256 tsStart;
    // Accumulated service staking reward
    uint256 reward;
    // Accumulated inactivity that will be used to decide whether the service must be evicted
    uint256 inactivity;
}

/// @title ServiceStakingBase - Base abstract smart contract for staking a service by its owner
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract ServiceStakingBase is ERC721TokenReceiver, IErrorsRegistries {
    // Input staking parameters
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

    event ServiceStaked(uint256 indexed serviceId, address indexed owner, address indexed multisig, uint256[] nonces);
    event Checkpoint(uint256 availableRewards, uint256 numServices);
    event ServiceUnstaked(uint256 indexed serviceId, address indexed owner, address indexed multisig, uint256[] nonces,
        uint256 reward, uint256 tsStart);
    event ServiceEvicted(uint256 indexed serviceId, address indexed owner, address indexed multisig, uint256 inactivity);
    event Deposit(address indexed sender, uint256 amount, uint256 balance, uint256 availableRewards);
    event Withdraw(address indexed to, uint256 amount);

    // Contract version
    string public constant VERSION = "0.1.0";
    // Max number of accumulated inactivity periods after which the service can be evicted
    uint256 public constant MAX_INACTIVITY_PERIODS = 3;
    // Maximum number of staking services
    uint256 public immutable maxNumServices;
    // Rewards per second
    uint256 public immutable rewardsPerSecond;
    // Minimum service staking deposit value required for staking
    // The staking deposit must be always greater than 1 in order to distinguish between native and ERC20 tokens
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
    // Approved multisig proxy hash
    bytes32 public immutable proxyHash;
    // Max allowed inactivity
    uint256 public immutable maxAllowedInactivity;

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
    /// @param _proxyHash Approved multisig proxy hash.
    constructor(StakingParams memory _stakingParams, address _serviceRegistry, bytes32 _proxyHash) {
        // Initial checks
        if (_stakingParams.maxNumServices == 0 || _stakingParams.rewardsPerSecond == 0 ||
            _stakingParams.livenessPeriod == 0 || _stakingParams.livenessRatio == 0 ||
            _stakingParams.numAgentInstances == 0) {
            revert ZeroValue();
        }
        if (_stakingParams.minStakingDeposit < 2) {
            revert LowerThan(_stakingParams.minStakingDeposit, 2);
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
        uint256 agentId;
        for (uint256 i = 0; i < _stakingParams.agentIds.length; ++i) {
            // Agent Ids must be unique and in ascending order
            if (_stakingParams.agentIds[i] <= agentId) {
                revert WrongAgentId(_stakingParams.agentIds[i]);
            }
            agentId = _stakingParams.agentIds[i];
            agentIds.push(agentId);
        }

        // Check for the multisig proxy bytecode hash value
        if (_proxyHash == bytes32(0)) {
            revert ZeroValue();
        }

        // Record provided multisig proxy bytecode hash
        proxyHash = _proxyHash;

        // Calculate max allowed inactivity
        maxAllowedInactivity = MAX_INACTIVITY_PERIODS * livenessPeriod;

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

        // Check if the evicted service has not yet unstaked
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        if (sInfo.tsStart > 0) {
            revert ServiceNotUnstaked(serviceId);
        }

        // Check for the maximum number of staking services
        uint256 numStakingServices = setServiceIds.length;
        if (numStakingServices == maxNumServices) {
            revert MaxNumServicesReached(maxNumServices);
        }

        // Check the service conditions for staking
        IService.Service memory service = IService(serviceRegistry).getService(serviceId);

        // Check the number of agent instances
        if (numAgentInstances != service.maxNumAgentInstances) {
            revert WrongServiceConfiguration(serviceId);
        }

        // Check the configuration hash, if applicable
        if (configHash != bytes32(0) && configHash != service.configHash) {
            revert WrongServiceConfiguration(serviceId);
        }
        // Check the threshold, if applicable
        if (threshold > 0 && threshold != service.threshold) {
            revert WrongServiceConfiguration(serviceId);
        }
        // The service must be deployed
        if (service.state != IService.ServiceState.Deployed) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Check that the multisig address corresponds to the authorized multisig proxy bytecode hash
        bytes32 multisigProxyHash = keccak256(service.multisig.code);
        if (proxyHash != multisigProxyHash) {
            revert UnauthorizedMultisig(service.multisig);
        }

        // Check the agent Ids requirement, if applicable
        uint256 size = agentIds.length;
        if (size > 0) {
            uint256 numAgents = service.agentIds.length;

            if (size != numAgents) {
                revert WrongServiceConfiguration(serviceId);
            }
            for (uint256 i = 0; i < numAgents; ++i) {
                if (agentIds[i] != service.agentIds[i]) {
                    revert WrongAgentId(agentIds[i]);
                }
            }
        }

        // Check service staking deposit and token, if applicable
        _checkTokenStakingDeposit(serviceId, service.securityDeposit);

        // ServiceInfo struct will be an empty one since otherwise the safeTransferFrom above would fail
        sInfo.multisig = service.multisig;
        sInfo.owner = msg.sender;
        uint256[] memory nonces = _getMultisigNonces(service.multisig);
        sInfo.nonces = nonces;
        sInfo.tsStart = block.timestamp;

        // Add the service Id to the set of staked services
        setServiceIds.push(serviceId);

        // Transfer the service for staking
        IService(serviceRegistry).safeTransferFrom(msg.sender, address(this), serviceId);

        emit ServiceStaked(serviceId, msg.sender, service.multisig, nonces);
    }

    /// @dev Gets service multisig nonces.
    /// @param multisig Service multisig address.
    /// @return nonces Set of a single service multisig nonce.
    function _getMultisigNonces(address multisig) internal view virtual returns (uint256[] memory nonces) {
        nonces = new uint256[](1);
        nonces[0] = IMultisig(multisig).nonce();
    }

    /// @dev Checks if the service multisig liveness ratio passes the defined liveness threshold.
    /// @notice The formula for calculating the ratio is the following:
    ///         currentNonce - service multisig nonce at time now (block.timestamp);
    ///         lastNonce - service multisig nonce at the previous checkpoint or staking time (tsStart);
    ///         ratio = (currentNonce - lastNonce) / (block.timestamp - tsStart).
    /// @param curNonces Current service multisig set of a single nonce.
    /// @param lastNonces Last service multisig set of a single nonce.
    /// @param ts Time difference between current and last timestamps.
    /// @return ratioPass True, if the liveness ratio passes the check.
    function _isRatioPass(
        uint256[] memory curNonces,
        uint256[] memory lastNonces,
        uint256 ts
    ) internal view virtual returns (bool ratioPass)
    {
        // If the checkpoint was called in the exact same block, the ratio is zero
        // If the current nonce is not greater than the last nonce, the ratio is zero
        if (ts > 0 && curNonces[0] > lastNonces[0]) {
            uint256 ratio = ((curNonces[0] - lastNonces[0]) * 1e18) / ts;
            ratioPass = (ratio >= livenessRatio);
        }
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
        uint256[][] memory serviceNonces,
        uint256[] memory serviceInactivity
    )
    {
        // Check the last checkpoint timestamp and the liveness period, also check for available rewards to be not zero
        uint256 tsCheckpointLast = tsCheckpoint;
        lastAvailableRewards = availableRewards;
        if (block.timestamp - tsCheckpointLast >= livenessPeriod && lastAvailableRewards > 0) {
            // Get the service Ids set length
            uint256 size = setServiceIds.length;

            // Get necessary arrays
            serviceIds = new uint256[](size);
            eligibleServiceIds = new uint256[](size);
            eligibleServiceRewards = new uint256[](size);
            serviceNonces = new uint256[][](size);
            serviceInactivity = new uint256[](size);

            // Calculate each staked service reward eligibility
            for (uint256 i = 0; i < size; ++i) {
                // Get current service Id
                serviceIds[i] = setServiceIds[i];

                // Get the service info
                ServiceInfo storage sInfo = mapServiceInfo[serviceIds[i]];

                // Get current service multisig nonce
                serviceNonces[i] = _getMultisigNonces(sInfo.multisig);

                // Calculate the liveness nonce ratio
                // Get the last service checkpoint: staking start time or the global checkpoint timestamp
                uint256 serviceCheckpoint = tsCheckpointLast;
                uint256 ts = sInfo.tsStart;
                // Adjust the service checkpoint time if the service was staking less than the current staking period
                if (ts > serviceCheckpoint) {
                    serviceCheckpoint = ts;
                }

                // Calculate the liveness ratio in 1e18 value
                // This subtraction is always positive or zero, as the last checkpoint can be at most block.timestamp
                ts = block.timestamp - serviceCheckpoint;
                bool ratioPass = _isRatioPass(serviceNonces[i], sInfo.nonces, ts);

                // Record the reward for the service if it has provided enough transactions
                if (ratioPass) {
                    // Calculate the reward up until now and record its value for the corresponding service
                    eligibleServiceRewards[numServices] = rewardsPerSecond * ts;
                    totalRewards += eligibleServiceRewards[numServices];
                    eligibleServiceIds[numServices] = serviceIds[i];
                    ++numServices;
                } else {
                    serviceInactivity[i] = ts;
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
        uint256[][] memory,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bool success
    )
    {
        // Calculate staking rewards
        (uint256 lastAvailableRewards, uint256 numServices, uint256 totalRewards,
            uint256[] memory eligibleServiceIds, uint256[] memory eligibleServiceRewards,
            uint256[] memory serviceIds, uint256[][] memory serviceNonces,
            uint256[] memory serviceInactivity) = _calculateStakingRewards();

        // If there are eligible services, proceed with staking calculation and update rewards
        if (numServices > 0) {
            uint256 curServiceId;
            // If total allocated rewards are not enough, adjust the reward value
            if (totalRewards > lastAvailableRewards) {
                // Traverse all the eligible services and adjust their rewards proportional to leftovers
                uint256 updatedReward;
                uint256 updatedTotalRewards;
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
                    curServiceId = eligibleServiceIds[i];
                    mapServiceInfo[curServiceId].reward += eligibleServiceRewards[i];
                }

                // Adjust available rewards
                lastAvailableRewards -= totalRewards;
            }

            // Update the storage value of available rewards
            availableRewards = lastAvailableRewards;
        }

        // If service Ids are returned, then the checkpoint takes place
        if (serviceIds.length > 0) {
            // Updated current service nonces
            for (uint256 i = 0; i < serviceIds.length; ++i) {
                // Get the current service Id
                uint256 curServiceId = serviceIds[i];
                mapServiceInfo[curServiceId].nonces = serviceNonces[i];

                // Increase service inactivity if it is greater than zero
                if (serviceInactivity[i] > 0) {
                    mapServiceInfo[curServiceId].inactivity += serviceInactivity[i];
                } else {
                    // Otherwise, set it back to zero
                    mapServiceInfo[curServiceId].inactivity = 0;
                }
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

        // Check that the service has staked long enough, or if there are no rewards left
        uint256 tsStart = sInfo.tsStart;
        uint256 ts = block.timestamp - tsStart;
        if (ts <= maxAllowedInactivity && availableRewards > 0) {
            revert NotEnoughTimeStaked(serviceId, ts, maxAllowedInactivity);
        }

        // Call the checkpoint
        (uint256[] memory serviceIds, , , , , bool success) = checkpoint();

        // If the checkpoint was not successful, the serviceIds set is not returned and needs to be allocated
        if (!success) {
            serviceIds = getServiceIds();
        }

        // Get the service index in the set of services
        // The index must always exist as the service is currently staked, otherwise it has no record in the map
        uint256 idx;
        for (; idx < serviceIds.length; ++idx) {
            if (serviceIds[idx] == serviceId) {
                break;
            }
        }

        // Get the unstaked service data
        uint256 reward = sInfo.reward;
        uint256[] memory nonces = sInfo.nonces;
        address multisig = sInfo.multisig;

        // Clear all the data about the unstaked service
        // Delete the service info struct
        delete mapServiceInfo[serviceId];

        // Update the set of staked service Ids
        // If the index was not found, the service was evicted and is not part of staked services set
        if (idx < serviceIds.length) {
            setServiceIds[idx] = setServiceIds[setServiceIds.length - 1];
            setServiceIds.pop();
        }

        // Transfer the service back to the owner
        IService(serviceRegistry).safeTransferFrom(address(this), msg.sender, serviceId);

        // Transfer accumulated rewards to the service multisig
        if (reward > 0) {
            _withdraw(multisig, reward);
        }

        emit ServiceUnstaked(serviceId, msg.sender, multisig, nonces, reward, tsStart);
    }

    /// @dev Evicts the service due to its extended inactivity.
    function evict(uint256 serviceId) external {
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        // Get the service inactivity time
        uint256 inactivity = sInfo.inactivity;

        // Evict the service if it is inactive more than the max number of inactivity periods
        if (inactivity > maxAllowedInactivity) {
            // Get service Ids to find the service
            uint256[] memory serviceIds = getServiceIds();

            // Get the service index in the set of services
            // The index must always exist if the service is currently staked, otherwise it never existed or was evicted
            uint256 idx;
            for (; idx < serviceIds.length; ++idx) {
                if (serviceIds[idx] == serviceId) {
                    break;
                }
            }

            // The service was already evicted
            if (idx == serviceIds.length) {
                revert ServiceNotFound(serviceId);
            }

            // Evict the service from the set of staked services
            setServiceIds[idx] = setServiceIds[setServiceIds.length - 1];
            setServiceIds.pop();

            emit ServiceEvicted(serviceId, sInfo.owner, sInfo.multisig, inactivity);
        }
    }

    /// @dev Calculates service staking reward during the last checkpoint period.
    /// @param serviceId Service Id.
    /// @return reward Service reward.
    function calculateServiceStakingLastReward(uint256 serviceId) public view returns (uint256 reward) {
        // Calculate overall staking rewards
        (uint256 lastAvailableRewards, uint256 numServices, uint256 totalRewards, uint256[] memory eligibleServiceIds,
            uint256[] memory eligibleServiceRewards, , , ) = _calculateStakingRewards();

        // If there are eligible services, proceed with staking calculation and update rewards for the service Id
        for (uint256 i = 0; i < numServices; ++i) {
            // Get the service index in the eligible service set and calculate its latest reward
            if (eligibleServiceIds[i] == serviceId) {
                // If total allocated rewards are not enough, adjust the reward value
                if (totalRewards > lastAvailableRewards) {
                    reward = (eligibleServiceRewards[i] * lastAvailableRewards) / totalRewards;
                } else {
                    reward = eligibleServiceRewards[i];
                }
                break;
            }
        }
    }

    /// @dev Calculates overall service staking reward at current timestamp.
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

        reward += calculateServiceStakingLastReward(serviceId);
    }

    /// @dev Checks if the service is staked.
    /// @param serviceId.
    /// @return isStaked True, if the service is staked.
    function isServiceStaked(uint256 serviceId) external view returns (bool isStaked) {
        isStaked = (mapServiceInfo[serviceId].tsStart > 0);
    }

    /// @dev Gets the next reward checkpoint timestamp.
    /// @return tsNext Next reward checkpoint timestamp.
    function getNextRewardCheckpointTimestamp() external view returns (uint256 tsNext) {
        // Last checkpoint timestamp plus the liveness period
        tsNext = tsCheckpoint + livenessPeriod;
    }

    /// @dev Gets staked service info.
    /// @param serviceId Service Id.
    /// @return sInfo Struct object with the corresponding service info.
    function getServiceInfo(uint256 serviceId) external view returns (ServiceInfo memory sInfo) {
        sInfo = mapServiceInfo[serviceId];
    }

    /// @dev Gets staked service Ids.
    /// @return Staked service Ids.
    function getServiceIds() public view returns (uint256[] memory) {
        return setServiceIds;
    }

    /// @dev Gets canonical agent Ids from the service configuration.
    /// @return Agent Ids.
    function getAgentIds() external view returns (uint256[] memory) {
        return agentIds;
    }
}