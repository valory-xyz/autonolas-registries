// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ServiceStakingBase} from "./ServiceStakingBase.sol";

/// @title ServiceStakingToken - Smart contract for staking a service by its owner when the service has an ETH as the deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStaking is ServiceStakingBase {
    /// @dev ServiceStaking constructor.
    /// @param _maxNumServices Maximum number of staking services.
    /// @param _rewardsPerSecond Staking rewards per second (in single digits).
    /// @param _minStakingDeposit Minimum staking deposit for a service to be eligible to stake.
    /// @param _livenessRatio Liveness ratio: number of nonces per second (in 18 digits).
    /// @param _serviceRegistry ServiceRegistry contract address.
    constructor(
        uint256 _maxNumServices,
        uint256 _rewardsPerSecond,
        uint256 _minStakingDeposit,
        uint256 _livenessRatio,
        address _serviceRegistry
    )
      ServiceStakingBase(_maxNumServices, _rewardsPerSecond, _minStakingDeposit, _livenessRatio, _serviceRegistry)
    {}

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
        // Add to the contract and available rewards balances
        uint256 newBalance = balance + msg.value;
        uint256 newAvailableRewards = availableRewards + msg.value;

        // Record the new actual balance and available rewards
        balance = newBalance;
        availableRewards = newAvailableRewards;

        emit Deposit(msg.sender, msg.value, newBalance, newAvailableRewards);
    }
}