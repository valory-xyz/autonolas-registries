// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ServiceStakingBase} from "./ServiceStakingBase.sol";
import "../interfaces/IService.sol";

/// @title ServiceStakingToken - Smart contract for staking a service by its owner when the service has an ETH as the deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStaking is ServiceStakingBase {
    /// @dev ServiceStaking constructor.
    /// @param _apy Staking APY (in single digits).
    /// @param _minStakingDeposit Minimum security deposit for a service to be eligible to stake.
    /// @param _stakingRatio Staking ratio: number of seconds per nonce (in 18 digits).
    /// @param _serviceRegistry ServiceRegistry contract address.
    constructor(uint256 _apy, uint256 _minStakingDeposit, uint256 _stakingRatio, address _serviceRegistry)
      ServiceStakingBase(_apy, _minStakingDeposit, _stakingRatio, _serviceRegistry)
    {
        // TODO: calculate minBalance
    }

    /// @dev Checks token security deposit.
    /// @param serviceId Service Id.
    function _checkTokenSecurityDeposit(uint256 serviceId) internal view override {
        // Get the service security token and deposit
        (uint96 stakingDeposit, , , , , , ) = IService(serviceRegistry).mapServices(serviceId);
        
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

        // Transfer the amount
        (bool result, ) = to.call{value: amount}("");
        if (!result) {
            revert TransferFailed(address(0), address(this), to, amount);
        }
    }

    receive() external payable {
        // Distribute current staking rewards
        _checkpoint(0);

        // Add to the contract and available rewards balances
        uint256 newBalance = balance + msg.value;
        uint256 newAvailableRewards = availableRewards + msg.value;

        // Update rewards per second
        uint256 newRewardsPerSecond = (newAvailableRewards * apy) / (100 * 365 days);
        rewardsPerSecond = newRewardsPerSecond;

        // Record the new actual balance and available rewards
        balance = newBalance;
        availableRewards = newAvailableRewards;

        emit Deposit(msg.sender, msg.value, newBalance, newAvailableRewards, newRewardsPerSecond);
    }
}