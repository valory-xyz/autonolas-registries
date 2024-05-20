// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {StakingBase} from "./StakingBase.sol";
import {SafeTransferLib} from "../utils/SafeTransferLib.sol";

/// @dev Provided zero token address.
error ZeroTokenAddress();

// Service Registry Token Utility interface
interface IServiceTokenUtility {
    /// @dev Gets the service security token info.
    /// @param serviceId Service Id.
    /// @return Token address.
    /// @return Token security deposit.
    function mapServiceIdTokenDeposit(uint256 serviceId) external view returns (address, uint96);

    /// @dev Gets the agent Id bond in a specified service.
    /// @param serviceId Service Id.
    /// @param serviceId Agent Id.
    /// @return bond Agent Id bond in a specified service Id.
    function getAgentBond(uint256 serviceId, uint256 agentId) external view returns (uint256 bond);
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
error ValueLowerThan(uint256 provided, uint256 expected);

/// @title StakingToken - Smart contract for staking a service by its owner when the service has an ERC20 token as the deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract StakingToken is StakingBase {
    // ServiceRegistryTokenUtility address
    address public serviceRegistryTokenUtility;
    // Security token address for staking corresponding to the service deposit token
    address public stakingToken;

    /// @dev StakingToken initialization.
    /// @param _stakingParams Service staking parameters.
    /// @param _serviceRegistryTokenUtility ServiceRegistryTokenUtility contract address.
    /// @param _stakingToken Address of a service staking token.
    function initialize(
        StakingParams memory _stakingParams,
        address _serviceRegistryTokenUtility,
        address _stakingToken
    ) external
    {
        _initialize(_stakingParams);

        // Initial checks
        if (_stakingToken == address(0) || _serviceRegistryTokenUtility == address(0)) {
            revert ZeroTokenAddress();
        }

        stakingToken = _stakingToken;
        serviceRegistryTokenUtility = _serviceRegistryTokenUtility;
    }

    /// @dev Checks token staking deposit.
    /// @param serviceId Service Id.
    /// @param serviceAgentIds Service agent Ids.
    function _checkTokenStakingDeposit(uint256 serviceId, uint256, uint32[] memory serviceAgentIds) internal view override {
        // Get the service staking token and deposit
        (address token, uint96 stakingDeposit) =
            IServiceTokenUtility(serviceRegistryTokenUtility).mapServiceIdTokenDeposit(serviceId);

        // The staking token must match the contract token
        if (stakingToken != token) {
            revert WrongStakingToken(stakingToken, token);
        }

        uint256 minDeposit = minStakingDeposit;

        // The staking deposit must be greater or equal to the minimum defined one
        if (stakingDeposit < minDeposit) {
            revert ValueLowerThan(stakingDeposit, minDeposit);
        }

        // Check agent Id bonds to be not smaller than the minimum required deposit
        for (uint256 i = 0; i < serviceAgentIds.length; ++i) {
            uint256 bond = IServiceTokenUtility(serviceRegistryTokenUtility).getAgentBond(serviceId, serviceAgentIds[i]);
            if (bond < minDeposit) {
                revert ValueLowerThan(bond, minDeposit);
            }
        }
    }

    /// @dev Withdraws the reward amount to a service owner.
    /// @notice The balance is always greater or equal the amount, as follows from the Base contract logic.
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
        // Add to the contract and available rewards balances
        uint256 newBalance = balance + amount;
        uint256 newAvailableRewards = availableRewards + amount;

        // Record the new actual balance and available rewards
        balance = newBalance;
        availableRewards = newAvailableRewards;

        // Add to the overall balance
        SafeTransferLib.safeTransferFrom(stakingToken, msg.sender, address(this), amount);

        emit Deposit(msg.sender, amount, newBalance, newAvailableRewards);
    }
}