// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ServiceStakingBase} from "./ServiceStakingBase.sol";
import {SafeTransferLib} from "../utils/SafeTransferLib.sol";
import "../interfaces/IToken.sol";

// Service Registry Token Utility interface
interface IServiceTokenUtility {
    /// @dev Gets the service security token info.
    /// @param serviceId Service Id.
    /// @return Token address.
    /// @return Token security deposit.
    function mapServiceIdTokenDeposit(uint256 serviceId) external view returns (address, uint96);
}

/// @dev The token does not have enough decimals.
/// @param token Token address.
/// @param decimals Number of decimals.
error NotEnoughTokenDecimals(address token, uint8 decimals);

/// @dev The staking token is wrong.
/// @param expected Expected staking token.
/// @param provided Provided staking token.
error WrongStakingToken(address expected, address provided);

/// @dev Received lower value than the expected one.
/// @param provided Provided value is lower.
/// @param expected Expected value.
error LowerThan(uint256 provided, uint256 expected);

/// @title ServiceStakingToken - Smart contract for staking a service by its owner when the service has an ERC20 token as the deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingToken is ServiceStakingBase {
    // Minimum number of token decimals
    uint8 public constant MIN_DECIMALS = 4;

    // ServiceRegistryTokenUtility address
    address public immutable serviceRegistryTokenUtility;
    // Security token address for staking corresponding to the service deposit token
    address public immutable stakingToken;

    /// @dev ServiceStakingToken constructor.
    /// @param _apy Staking APY (in single digits).
    /// @param _minStakingDeposit Minimum staking deposit for a service to be eligible to stake.
    /// @param _stakingRatio Staking ratio: number of seconds per nonce (in 18 digits).
    /// @param _serviceRegistry ServiceRegistry contract address.
    /// @param _serviceRegistryTokenUtility ServiceRegistryTokenUtility contract address.
    /// @param _stakingToken Address of a service staking token.
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
        // Initial checks
        if (_stakingToken == address(0) || _serviceRegistryTokenUtility == address(0)) {
            revert ZeroAddress();
        }

        stakingToken = _stakingToken;
        serviceRegistryTokenUtility = _serviceRegistryTokenUtility;

        // Calculate minBalance based on decimals
        uint8 decimals = IToken(_stakingToken).decimals();
        if (decimals < MIN_DECIMALS) {
            revert NotEnoughTokenDecimals(_stakingToken, decimals);
        } else {
            minBalance = 10 ** (decimals - MIN_DECIMALS);
        }
    }

    /// @dev Checks token staking deposit.
    /// @param serviceId Service Id.
    function _checkTokenStakingDeposit(uint256 serviceId, uint256) internal view override {
        // Get the service staking token and deposit
        (address token, uint96 stakingDeposit) =
            IServiceTokenUtility(serviceRegistryTokenUtility).mapServiceIdTokenDeposit(serviceId);

        // The staking token must match the contract token
        if (stakingToken != token) {
            revert WrongStakingToken(stakingToken, token);
        }

        // The staking deposit must be greater or equal to the minimum defined one
        if (stakingDeposit < minStakingDeposit) {
            revert LowerThan(stakingDeposit, minStakingDeposit);
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
        // Add to the overall balance
        SafeTransferLib.safeTransferFrom(stakingToken, msg.sender, address(this), amount);

        // Add to the contract and available rewards balances
        uint256 newBalance = balance + amount;
        uint256 newAvailableRewards = availableRewards + amount;

        // Record the new actual balance and available rewards
        balance = newBalance;
        availableRewards = newAvailableRewards;

        emit Deposit(msg.sender, amount, newBalance, newAvailableRewards);
    }
}