// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ServiceStakingBase} from "./ServiceStakingBase.sol";
import {SafeTransferLib} from "../utils/SafeTransferLib.sol";
import "../interfaces/IToken.sol";
import "../interfaces/IServiceTokenUtility.sol";

/// @title ServiceStakingToken - Smart contract for staking a service by its owner when the service has an ERC20 token as the deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingToken is ServiceStakingBase {
    // ServiceRegistryTokenUtility address
    address public immutable serviceRegistryTokenUtility;
    // Security token address for staking corresponding to the service deposit token
    address public immutable stakingToken;

    /// @dev ServiceStakingToken constructor.
    /// @param _apy Staking APY (in single digits).
    /// @param _minStakingDeposit Minimum security deposit for a service to be eligible to stake.
    /// @param _stakingRatio Staking ratio: number of seconds per nonce (in 18 digits).
    /// @param _serviceRegistry ServiceRegistry contract address.
    /// @param _serviceRegistryTokenUtility ServiceRegistryTokenUtility contract address.
    /// @param _stakingToken Address of a service security token.
    constructor(
        uint256 _apy,
        uint256 _minStakingDeposit,
        uint256 _stakingRatio,
        address _serviceRegistry,
        address _serviceRegistryTokenUtility,
        address _stakingToken
    )
        ServiceStakingBase(_apy, _minStakingDeposit, _stakingRatio, _serviceRegistry)
    {
        // TODO: calculate minBalance
        // Initial checks
        if (_stakingToken == address(0) || _serviceRegistryTokenUtility == address(0)) {
            revert ZeroAddress();
        }

        stakingToken = _stakingToken;
        serviceRegistryTokenUtility = _serviceRegistryTokenUtility;
    }

    /// @dev Checks token security deposit.
    /// @param serviceId Service Id.
    function _checkTokenSecurityDeposit(uint256 serviceId) internal view override {
        // Get the service security token and deposit
        (address token, uint96 stakingDeposit) =
            IServiceTokenUtility(serviceRegistryTokenUtility).mapServiceIdTokenDeposit(serviceId);

        // The security token must match the contract token
        if (stakingToken != token) {
            revert();
        }

        // The security deposit must be greater or equal to the minimum defined one
        if (stakingDeposit < minStakingDeposit) {
            revert();
        }
    }

    /// @dev Withdraws the reward amount to a service owner.
    /// @param to Address to.
    /// @param amount Amount to withdraw.
    function _withdraw(address to, uint256 amount) internal override {
        // Update the contract balance
        balance -= amount;

        SafeTransferLib.safeTransfer(stakingToken, to, amount);

        emit Withdraw(to, amount);
    }

    /// @dev Deposits funds for staking.
    /// @param amount Token amount to deposit.
    function deposit(uint256 amount) external {
        // Distribute current staking rewards
        _checkpoint(0);

        // Add to the overall balance
        SafeTransferLib.safeTransferFrom(stakingToken, msg.sender, address(this), amount);

        // Add to the contract and available rewards balances
        uint256 newBalance = balance + amount;
        uint256 newAvailableRewards = availableRewards + amount;

        // Update rewards per second
        uint256 newRewardsPerSecond = (newAvailableRewards * apy) / (100 * 365 days);
        rewardsPerSecond = newRewardsPerSecond;

        // Record the new actual balance and available rewards
        balance = newBalance;
        availableRewards = newAvailableRewards;

        emit Deposit(msg.sender, amount, newBalance, newAvailableRewards, newRewardsPerSecond);
    }
}