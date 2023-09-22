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
    constructor(uint256 _apy, uint256 _minSecurityDeposit, uint256 _stakingRatio, address _serviceRegistry)
      ServiceStakingBase(_apy, _minSecurityDeposit, _stakingRatio, _serviceRegistry)
    {}

    function _checkTokenSecurityDeposit(uint256 serviceId) internal view override {
        // Get the service security token and deposit
        (uint96 securityDeposit, , , , , , ) = IService(serviceRegistry).mapServices(serviceId);
        
        // The security deposit must be greater or equal to the minimum defined one
        if (securityDeposit < minSecurityDeposit) {
            revert();
        }
    }

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
        rewardsPerSecond = (newBalance * apy) / (100 * 365 days);

        // Record the new actual balance
        balance = newBalance;
    }
}