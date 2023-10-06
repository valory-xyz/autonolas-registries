// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ServiceStakingBase} from "./ServiceStakingBase.sol";

/// @title ServiceStakingNativeToken - Smart contract for staking a service with the service having a native network token as the deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingNativeToken is ServiceStakingBase {
    /// @dev ServiceStakingNativeToken constructor.
    /// @param _stakingParams Service staking parameters.
    /// @param _serviceRegistry ServiceRegistry contract address.
    constructor(StakingParams memory _stakingParams, address _serviceRegistry)
        ServiceStakingBase(_stakingParams, _serviceRegistry)
    {}

    /// @dev Withdraws the reward amount to a service owner.
    /// @param to Address to.
    /// @param amount Amount to withdraw.
    function _withdraw(address to, uint256 amount) internal override {
        // Update the contract balance
        // TODO: Fuzz this such that the amount is never bigger than the balance
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