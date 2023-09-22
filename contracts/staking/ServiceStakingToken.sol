// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./ServiceStakingBase.sol";

interface IToken {
    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IServiceTokenUtility {
    /// @dev Gets the service security token info.
    /// @param serviceId Service Id.
    /// @return Token address.
    /// @return Token security deposit.
    function mapServiceIdTokenDeposit(uint256 serviceId) external view returns (address, uint96);
}

/// @dev Failure of a transfer.
/// @param token Address of a token.
/// @param from Address `from`.
/// @param to Address `to`.
/// @param value Value.
error TransferFailed(address token, address from, address to, uint256 value);

/// @title ServiceStakingToken - Smart contract for staking the service by its owner having an ERC20 token as a deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingToken is ServiceStakingBase {
    // ServiceRegistryTokenUtility address
    address public immutable serviceRegistryTokenUtility;
    // Security token address for staking corresponding to the service deposit token
    address public immutable securityToken;

    /// @dev ServiceStakingToken constructor.
    /// @param _apy Staking APY (in single digits).
    /// @param _minSecurityDeposit Minimum security deposit for a service to be eligible to stake.
    /// @param _stakingRatio Staking ratio: number of seconds per nonce (in 18 digits).
    /// @param _serviceRegistry ServiceRegistry contract address.
    /// @param _serviceRegistryTokenUtility ServiceRegistryTokenUtility contract address.
    /// @param _securityToken Address of a service security token.
    constructor(
        uint256 _apy,
        uint256 _minSecurityDeposit,
        uint256 _stakingRatio,
        address _serviceRegistry,
        address _serviceRegistryTokenUtility,
        address _securityToken
    )
        ServiceStakingBase(_apy, _minSecurityDeposit, _stakingRatio, _serviceRegistry)
    {
        // TODO: calculate minBalance
        // Initial checks
        if (_securityToken == address(0) || _serviceRegistryTokenUtility == address(0)) {
            revert ZeroAddress();
        }

        securityToken = _securityToken;
        serviceRegistryTokenUtility = _serviceRegistryTokenUtility;
    }

    /// @dev Safe token transferFrom implementation.
    /// @notice The implementation is fully copied from the audited MIT-licensed solmate code repository:
    ///         https://github.com/transmissions11/solmate/blob/v7/src/utils/SafeTransferLib.sol
    ///         The original library imports the `ERC20` abstract token contract, and thus embeds all that contract
    ///         related code that is not needed. In this version, `ERC20` is swapped with the `address` representation.
    ///         Also, the final `require` statement is modified with this contract own `revert` statement.
    /// @param token Token address.
    /// @param from Address to transfer tokens from.
    /// @param to Address to transfer tokens to.
    /// @param amount Token amount.
    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        bool success;

        // solhint-disable-next-line no-inline-assembly
        assembly {
        // We'll write our calldata to this slot below, but restore it later.
            let memPointer := mload(0x40)

        // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(0, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(4, from) // Append the "from" argument.
            mstore(36, to) // Append the "to" argument.
            mstore(68, amount) // Append the "amount" argument.

            success := and(
            // Set success to whether the call reverted, if not we check it either
            // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
            // We use 100 because that's the total length of our calldata (4 + 32 * 3)
            // Counterintuitively, this call() must be positioned after the or() in the
            // surrounding and() because and() evaluates its arguments from right to left.
                call(gas(), token, 0, 0, 100, 0, 32)
            )

            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, memPointer) // Restore the memPointer.
        }

        if (!success) {
            revert TransferFailed(token, from, to, amount);
        }
    }

    /// @dev Safe token transfer implementation.
    /// @notice The implementation is fully copied from the audited MIT-licensed solmate code repository:
    ///         https://github.com/transmissions11/solmate/blob/v7/src/utils/SafeTransferLib.sol
    ///         The original library imports the `ERC20` abstract token contract, and thus embeds all that contract
    ///         related code that is not needed. In this version, `ERC20` is swapped with the `address` representation.
    ///         Also, the final `require` statement is modified with this contract own `revert` statement.
    /// @param token Token address.
    /// @param to Address to transfer tokens to.
    /// @param amount Token amount.
    function safeTransfer(address token, address to, uint256 amount) internal {
        bool success;

        // solhint-disable-next-line no-inline-assembly
        assembly {
        // We'll write our calldata to this slot below, but restore it later.
            let memPointer := mload(0x40)

        // Write the abi-encoded calldata into memory, beginning with the function selector.
            mstore(0, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(4, to) // Append the "to" argument.
            mstore(36, amount) // Append the "amount" argument.

            success := and(
            // Set success to whether the call reverted, if not we check it either
            // returned exactly 1 (can't just be non-zero data), or had no return data.
                or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
            // We use 68 because that's the total length of our calldata (4 + 32 * 2)
            // Counterintuitively, this call() must be positioned after the or() in the
            // surrounding and() because and() evaluates its arguments from right to left.
                call(gas(), token, 0, 0, 68, 0, 32)
            )

            mstore(0x60, 0) // Restore the zero slot to zero.
            mstore(0x40, memPointer) // Restore the memPointer.
        }

        if (!success) {
            revert TransferFailed(token, address(this), to, amount);
        }
    }

    /// @dev Checks token security deposit.
    /// @param serviceId Service Id.
    function _checkTokenSecurityDeposit(uint256 serviceId) internal view override {
        // Get the service security token and deposit
        (address token, uint96 securityDeposit) =
            IServiceTokenUtility(serviceRegistryTokenUtility).mapServiceIdTokenDeposit(serviceId);

        // The security token must match the contract token
        if (securityToken != token) {
            revert();
        }

        // The security deposit must be greater or equal to the minimum defined one
        if (securityDeposit < minSecurityDeposit) {
            revert();
        }
    }

    /// @dev Withdraws the reward amount to a service owner.
    /// @param to Address to.
    /// @param amount Amount to withdraw.
    function _withdraw(address to, uint256 amount) internal override {
        safeTransfer(securityToken, to, amount);

        emit Withdraw(to, amount);
    }

    /// @dev Deposits funds for staking.
    /// @param amount Token amount to deposit.
    function deposit(uint256 amount) external {
        // Distribute current staking rewards
        _checkpoint(0);

        // Add to the overall balance
        safeTransferFrom(securityToken, msg.sender, address(this), amount);

        // Add to the overall balance
        uint256 newBalance = balance + amount;

        // Update rewards per second
        uint256 newRewardsPerSecond = (newBalance * apy) / (100 * 365 days);
        rewardsPerSecond = newRewardsPerSecond;

        // Record the new actual balance
        balance = newBalance;

        emit Deposit(msg.sender, amount, newBalance, newRewardsPerSecond);
    }
}