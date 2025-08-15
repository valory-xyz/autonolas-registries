// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {StakingBase} from "./StakingBase.sol";

/// @dev Failure of a transfer.
/// @param token Address of a token.
/// @param from Address `from`.
/// @param to Address `to`.
/// @param value Value.
error TransferFailed(address token, address from, address to, uint256 value);

/// @title StakingNativeToken - Smart contract for staking a service with the service having a native network token as the deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract StakingNativeToken is StakingBase {
    /// @dev StakingNativeToken initialization.
    /// @param _stakingParams Service staking parameters.
    function initialize(StakingParams memory _stakingParams) external {
        _initialize(_stakingParams);
    }

    /// @dev Transfers reward amount.
    /// @param to Address to.
    /// @param amount Amount to withdraw.
    function _transfer(address to, uint256 amount) internal override {
        // Transfer the amount
        (bool success, ) = to.call{value: amount}("");
        if (!success) {
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