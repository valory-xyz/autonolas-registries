// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IMultisig {
    function nonce() external returns (uint256);
}

interface IService {
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

struct ServiceInfo {
    address multisig;
    address owner;
    uint256 nonce;
    uint256 ts;
    uint256 reward;
}

/// @title ServiceStakingBase - Base abstract smart contract for staking the service by its owner
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract ServiceStakingBase {
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
    // Minimum balance going below which would be considered that the balance is zero
    uint256 public minBalance;
    // Rewards per second
    uint256 public rewardsPerSecond;
    // Mapping of serviceId => staking service info
    mapping (uint256 => ServiceInfo) public mapServiceInfo;
    // Set of currently staking serviceIds
    uint256[] public setServiceIds;

    constructor(uint256 _apy, uint256 _minSecurityDeposit, uint256 _stakingRatio, address _serviceRegistry) {
        apy = _apy;
        minSecurityDeposit = _minSecurityDeposit;
        stakingRatio = _stakingRatio;
        serviceRegistry = _serviceRegistry;
    }

    function _checkTokenSecurityDeposit(uint256 serviceId) internal view virtual {}

    function _withdraw(address to, uint256 amount) internal virtual {}

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
    }

    function _checkpoint(uint256 serviceId) internal returns (uint256 idx) {
        // Get the
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

                // Add the reward
                curInfo.reward += reward;

                // Adjust the starting ts for each service to a current timestamp
                curInfo.ts = block.timestamp;
            }

            balance = lastBalance;
        }

        // Record the current timestamp as the one to make future staking calculations from
        tsLastBalance = block.timestamp;
    }

    function unstake(uint256 serviceId) external {
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        if (msg.sender != sInfo.owner) {
            revert();
        }

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
    }
}