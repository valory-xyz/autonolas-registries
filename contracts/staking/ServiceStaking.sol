// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./ServiceStakingBase.sol";

/// @dev Failure of a transfer.
/// @param token Address of a token.
/// @param from Address `from`.
/// @param to Address `to`.
/// @param value Value.
error TransferFailed(address token, address from, address to, uint256 value);

/// @title ServiceStakingToken - Smart contract for staking the service by its owner based ETH as a deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStaking is ServiceStakingBase {
    /// @dev ServiceStaking constructor.
    /// @param _apy Staking APY (in single digits).
    /// @param _minSecurityDeposit Minimum security deposit for a service to be eligible to stake.
    /// @param _stakingRatio Staking ratio: number of seconds per nonce (in 18 digits).
    /// @param _serviceRegistry ServiceRegistry contract address.
    constructor(uint256 _apy, uint256 _minSecurityDeposit, uint256 _stakingRatio, address _serviceRegistry)
      ServiceStakingBase(_apy, _minSecurityDeposit, _stakingRatio, _serviceRegistry)
    {
        // TODO: calculate minBalance
    }

    /// @dev Checks token security deposit.
    /// @param serviceId Service Id.
    function _checkTokenSecurityDeposit(uint256 serviceId) internal view override {
        // Get the service security token and deposit
        (uint96 securityDeposit, , , , , , ) = IService(serviceRegistry).mapServices(serviceId);
        
        // The security deposit must be greater or equal to the minimum defined one
        if (securityDeposit < minSecurityDeposit) {
            revert();
        }
    }

    /// @dev Withdraws the reward amount to a service owner.
    /// @param to Address to.
    /// @param amount Amount to withdraw.
    function _withdraw(address to, uint256 amount) internal override {
        (bool result, ) = to.call{value: amount}("");
        if (!result) {
            revert TransferFailed(address(0), address(this), to, amount);
        }
    }

    receive() external payable {
        // Distribute current staking rewards
        _checkpoint(0);

        // Add to the overall balance
        uint256 newBalance = balance + msg.value;

        // Update rewards per second
        uint256 newRewardsPerSecond = (newBalance * apy) / (100 * 365 days);
        rewardsPerSecond = newRewardsPerSecond;

        // Record the new actual balance
        balance = newBalance;

        emit Deposit(msg.sender, msg.value, newBalance, newRewardsPerSecond);
    }
}