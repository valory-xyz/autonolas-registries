// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../interfaces/IErrorsRegistries.sol";

// Multisig interface
interface IMultisig {
    /// @dev Gets the multisig nonce.
    /// @return Multisig nonce.
    function nonce() external returns (uint256);
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
    event Checkpoint(uint256 indexed balance, uint256 numServices);
    event ServiceUnstaked(uint256 indexed serviceId, address indexed owner, uint256 reward);
    event Deposit(address indexed sender, uint256 amount, uint256 newBalance, uint256 newAvailableRewards);
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

    /// @dev Checkpoint to allocate rewards up until a current time.
    /// @param serviceId Service Id that unstakes, or 0 if the function is called during the deposit of new funds.
    function _checkpoint(uint256 serviceId) internal returns (uint256 idx) {
        // Get the service Id set length
        uint256 size = setServiceIds.length;
        uint256 lastAvailableRewards = availableRewards;
        uint256 tsCheckpointLast = tsCheckpoint;

        // Number of services eligible for the reward during the current checkpoint
        uint256 numServices;

        // If available rewards are not zero, proceed with staking calculation
        // Otherwise, just bump the timestamp of last checkpoint
        if (serviceId > 0 && lastAvailableRewards > 0) {
            uint256[] memory eligibleServiceIds = new uint256[](size);
            uint256[] memory eligibleServiceRewards = new uint256[](size);
            uint256[] memory serviceIds = new uint256[](size);
            uint256[] memory serviceNonces = new uint256[](size);
            uint256 totalRewards;

            // Calculate each staked service reward eligibility
            for (uint256 i = 0; i < size; ++i) {
                // Get the current service Id
                serviceIds[i] = setServiceIds[i];

                // Get the service info
                ServiceInfo storage curInfo = mapServiceInfo[serviceIds[i]];

                // Calculate the staking nonce ratio
                uint256 curNonce = IMultisig(curInfo.multisig).nonce();
                // Get the last service checkpoint: staking start time or the global checkpoint timestamp
                uint256 serviceCheckpoint = tsCheckpointLast;
                // Adjust the service checkpoint time if the service was staking less than the current staking period
                if (curInfo.tsStart > tsCheckpointLast) {
                    serviceCheckpoint = curInfo.tsStart;
                }
                // Calculate the liveness ratio in 1e18 value
                uint256 ratio;
                // If the checkpoint was called in the exactly same block, the ratio is zero
                if (block.timestamp > tsCheckpointLast) {
                    ratio = ((curNonce - curInfo.nonce) * 1e18) / (block.timestamp - serviceCheckpoint);
                }

                // Record the reward for the service if it has provided enough transactions
                if (ratio >= livenessRatio) {
                    // Calculate the reward up until now and record its value for the corresponding service
                    uint256 reward = rewardsPerSecond * (block.timestamp - serviceCheckpoint);
                    totalRewards += reward;
                    eligibleServiceRewards[numServices] = reward;
                    eligibleServiceIds[numServices] = serviceIds[i];
                    ++numServices;
                }

                // Record current service multisig nonce
                serviceNonces[i] = curNonce;

                // Record the unstaked service Id index in the global set of staked service Ids
                if (serviceIds[i] == serviceId) {
                    idx = i;
                }
            }

            // If total allocated rewards are not enough, adjust the reward value
            if (totalRewards > lastAvailableRewards) {
                // Traverse all the eligible services and adjust their rewards proportional to leftovers
                for (uint256 i = 0; i < numServices; ++i) {
                    uint256 curServiceId = eligibleServiceIds[i];
                    mapServiceInfo[curServiceId].reward +=
                        (eligibleServiceRewards[i] * lastAvailableRewards) / totalRewards;
                }

                // Set available rewards to zero
                lastAvailableRewards = 0;
            } else {
                // Traverse all the eligible services and add to their rewards
                for (uint256 i = 0; i < numServices; ++i) {
                    uint256 curServiceId = eligibleServiceIds[i];
                    mapServiceInfo[curServiceId].reward += eligibleServiceRewards[i];
                }

                // Adjust available rewards
                lastAvailableRewards -= totalRewards;
            }

            // Update the storage value of available rewards
            availableRewards = lastAvailableRewards;

            // Updated current service nonces
            for (uint256 i = 0; i < size; ++i) {
                // Get the current service Id
                uint256 curServiceId = serviceIds[i];
                mapServiceInfo[curServiceId].nonce = serviceNonces[i];
            }
        }

        // Record the current timestamp such that next calculations start from this point of time
        tsCheckpoint = block.timestamp;

        emit Checkpoint(lastAvailableRewards, numServices);
    }

    /// @dev Public checkpoint function to allocate rewards up until a current time.
    function checkpoint() external {
        _checkpoint(0);
    }

    /// @dev Unstakes the service.
    /// @param serviceId Service Id.
    function unstake(uint256 serviceId) external {
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        // Check for the service ownership
        if (msg.sender != sInfo.owner) {
            revert OwnerOnly(msg.sender, sInfo.owner);
        }

        // Call the checkpoint and get the service index in the set of services
        uint256 idx = _checkpoint(serviceId);

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

        // Clear all the data about the unstaked service
        // Delete the service info struct
        delete mapServiceInfo[serviceId];

        // Update the set of staked service Ids
        setServiceIds[idx] = setServiceIds[setServiceIds.length - 1];
        setServiceIds.pop();

        emit ServiceUnstaked(serviceId, msg.sender, amount);
    }
}