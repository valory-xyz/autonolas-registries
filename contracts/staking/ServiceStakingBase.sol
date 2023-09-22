// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

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

/// @dev Provided zero value.
error ZeroValue();

/// @dev Provided zero address.
error ZeroAddress();

// Service Info struct
struct ServiceInfo {
    // Service multisig address
    address multisig;
    // Service owner
    address owner;
    // Service multisig nonce
    uint256 nonce;
    // Staking time
    uint256 ts;
    // Accumulated service staking reward
    uint256 reward;
}

/// @title ServiceStakingBase - Base abstract smart contract for staking the service by its owner
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract ServiceStakingBase {
    event ServiceStaked(uint256 indexed serviceId, address indexed owner);
    event Checkpoint(uint256 indexed balance);
    event ServiceUnstaked(uint256 indexed serviceId, address indexed owner, uint256 reward);
    event Deposit(address indexed sender, uint256 amount, uint256 newBalance, uint256 rewardsPerSecond);
    event Withdraw(address indexed to, uint256 amount);

    // APY value
    uint256 public immutable apy;
    // Minimum deposit value for staking
    uint256 public immutable minSecurityDeposit;
    // Staking ratio in the format of 1e18
    uint256 public immutable stakingRatio;
    // ServiceRegistry contract address
    address public immutable serviceRegistry;

    // Token / ETH balance
    uint256 public balance;
    // Timestamp of the last checkpoint
    uint256 public tsLastBalance;
    // Minimum balance going below which would be given away, such that the contract balance is set to zero
    uint256 public minBalance;
    // Rewards per second
    uint256 public rewardsPerSecond;
    // Mapping of serviceId => staking service info
    mapping (uint256 => ServiceInfo) public mapServiceInfo;
    // Set of currently staking serviceIds
    uint256[] public setServiceIds;

    /// @dev ServiceStakingBase constructor.
    /// @param _apy Staking APY (in single digits).
    /// @param _minSecurityDeposit Minimum security deposit for a service to be eligible to stake.
    /// @param _stakingRatio Staking ratio: number of seconds per nonce (in 18 digits).
    /// @param _serviceRegistry ServiceRegistry contract address.
    constructor(uint256 _apy, uint256 _minSecurityDeposit, uint256 _stakingRatio, address _serviceRegistry) {
        // Initial checks
        if (_apy == 0 || _minSecurityDeposit == 0 || _stakingRatio == 0) {
            revert ZeroValue();
        }
        if (_serviceRegistry == address(0)) {
            revert ZeroAddress();
        }

        apy = _apy;
        minSecurityDeposit = _minSecurityDeposit;
        stakingRatio = _stakingRatio;
        serviceRegistry = _serviceRegistry;
    }

    /// @dev Checks token security deposit.
    /// @param serviceId Service Id.
    function _checkTokenSecurityDeposit(uint256 serviceId) internal view virtual {}

    /// @dev Withdraws the reward amount to a service owner.
    /// @param to Address to.
    /// @param amount Amount to withdraw.
    function _withdraw(address to, uint256 amount) internal virtual {}

    /// @dev Stakes the service.
    /// @param serviceId Service Id.
    function stake(uint256 serviceId) external {
        // Check the service conditions for staking
        (, address multisig, , , , , uint8 state) = IService(serviceRegistry).mapServices(serviceId);
        // The service must be deployed
        if (state != 4) {
            revert();
        }
        // Check the service security deposit and token, if applicable
        _checkTokenSecurityDeposit(serviceId);

        // Transfer the service for staking
        IService(serviceRegistry).transferFrom(msg.sender, address(this), serviceId);

        // ServiceInfo struct will be an empty one since otherwise the transferFrom above would fail
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        sInfo.multisig = multisig;
        sInfo.owner = msg.sender;
        sInfo.nonce = IMultisig(multisig).nonce();
        sInfo.ts = block.timestamp;

        // Add the service Id to the set of staked services
        setServiceIds.push(serviceId);

        emit ServiceStaked(serviceId, msg.sender);
    }

    /// @dev Checkpoint to allocate rewards up until a current time.
    /// @param serviceId Service Id that unstakes, or 0 if the function is called during the deposit of new funds.
    function _checkpoint(uint256 serviceId) internal returns (uint256 idx) {
        // Get the service Id set length
        uint256 size = setServiceIds.length;
        uint256 lastBalance = balance;

        // If the balance is zero, just bump the timestamp for each of the staking service
        if (lastBalance == 0) {
            for (uint256 i = 0; i < size; ++i) {
                // Set the current timestamp
                mapServiceInfo[setServiceIds[i]].ts = block.timestamp;
            }
        } else {
            uint256 numServices;
            uint256[] memory eligibleServiceIds = new uint256[](size);

            // Calculate each staked service reward eligibility
            for (uint256 i = 0; i < size; ++i) {
                // Get the current service Id
                uint256 curServiceId = setServiceIds[i];

                // Get the service info
                ServiceInfo storage curInfo = mapServiceInfo[curServiceId];

                // Calculate the staking nonce ratio
                uint256 curNonce = IMultisig(curInfo.multisig).nonce();
                // Calculate the nonce ratio in 1e18 value
                uint256 ratio = ((block.timestamp - curInfo.ts) * 1e18) / (curNonce - curInfo.nonce);

                // Record the reward for the service if it has provided enough transactions
                if (ratio >= stakingRatio) {
                    eligibleServiceIds[numServices] = curServiceId;
                    ++numServices;
                } else {
                    // Record current timestamp for each reward ineligible service
                    curInfo.ts = block.timestamp;
                }
                // Record current service multisig nonce
                curInfo.nonce = curNonce;

                // Record the unstaked service Id index in the global set of staked service Ids
                if (curServiceId == serviceId) {
                    idx = i;
                }
            }

            // Calculate each eligible service Id reward
            uint256 tsLast = tsLastBalance;
            // Calculate the maximum possible reward per service during the last deposit period
            uint256 maxRewardsPerService = (rewardsPerSecond * (block.timestamp - tsLast)) / numServices;
            // Traverse all the eligible services and calculate their rewards
            for (uint256 i = 0; i < numServices; ++i) {
                uint256 curServiceId = eligibleServiceIds[i];
                ServiceInfo storage curInfo = mapServiceInfo[curServiceId];

                // Calculate the reward up until now
                // If the staking was longer than the deposited period, the service's timestamp is adjusted such that
                // it is equal to at most the tsLastBalance of the last deposit happening during every _checkpoint() call
                uint256 reward = rewardsPerSecond * (block.timestamp - curInfo.ts);
                // Adjust the reward if it goes out of calculated max bounds
                if (reward > maxRewardsPerService) {
                    reward = maxRewardsPerService;
                }

                // Adjust the deposit balance
                if (lastBalance >= reward) {
                    lastBalance -= reward;
                } else {
                    // This situation must never happen
                    // TODO: Fuzz this
                    reward = lastBalance;
                    lastBalance = 0;
                }

                // Add the calculated reward to the service info
                curInfo.reward += reward;

                // Adjust the starting ts for each service to a current timestamp
                curInfo.ts = block.timestamp;
            }
            // Update the storage balance
            balance = lastBalance;
        }

        // Record the current timestamp such that next calculations start from this point of time
        tsLastBalance = block.timestamp;

        emit Checkpoint(lastBalance);
    }

    /// @dev Unstakes the service.
    /// @param serviceId Service Id.
    function unstake(uint256 serviceId) external {
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        // Check for the service ownership
        if (msg.sender != sInfo.owner) {
            revert();
        }

        // Call the checkpoint and get the service index in the set of services
        uint256 idx = _checkpoint(serviceId);

        // Transfer the service back to the owner
        IService(serviceRegistry).transferFrom(address(this), msg.sender, serviceId);

        // Send the remaining small balance along with the reward if it is below the chosen threshold
        uint256 amount = sInfo.reward;
        uint256 lastBalance = balance;
        if (lastBalance < minBalance) {
            amount += lastBalance;
            balance = 0;
        }

        // Transfer accumulated rewards to the service owner
        if (amount > 0) {
            _withdraw(msg.sender, amount);
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