// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

error FailedTransferFrom();
error FailedTransfer();

// ServiceRegistryTokenUtility interface
interface IServiceRegistryTokenUtility {
    /// @dev Deposit a token security deposit for the service registration after its activation.
    /// @param serviceId Service Id.
    /// @return isTokenSecured True if the service Id is token secured, false if ETH secured otherwise.
    function activateRegistrationTokenDeposit(uint256 serviceId) external returns (bool isTokenSecured);

    /// @dev Deposits bonded tokens from the operator during the agent instance registration.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @param agentIds Set of agent Ids for corresponding agent instances opertor is registering.
    /// @return isTokenSecured True if the service Id is token secured, false if ETH secured otherwise.
    function registerAgentsTokenDeposit(
        address operator,
        uint256 serviceId,
        uint32[] memory agentIds
    ) external returns (bool isTokenSecured);

    /// @dev Refunds a token security deposit to the service owner after the service termination.
    /// @param serviceId Service Id.
    /// @return securityRefund Returned token security deposit, or zero if the service is ETH-secured.
    function terminateTokenRefund(uint256 serviceId) external returns (uint256 securityRefund);

    /// @dev Refunds bonded tokens to the operator during the unbond phase.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @return refund Returned bonded token amount, or zero if the service is ETH-secured.
    function unbondTokenRefund(address operator, uint256 serviceId) external returns (uint256 refund);

    /// @dev Drains slashed funds to the drainer address.
    /// @param token Token address.
    /// @return amount Drained amount.
    function drain(address token) external returns (uint256 amount);
}

contract ReentrancyTokenAttacker {
    enum AttackState {
        DEFAULT,
        BALANCE_ZERO,
        BALANCE_REDUCED,
        FAILED_TRANSFER,
        FAILED_TRANSFER_FROM,
        ACTIVATE_REGISTRATION,
        REGISTER_AGENTS,
        TERMINATE,
        UNBOND,
        DRAIN
    }

    address public immutable serviceRegistryTokenUtility;
    AttackState public state;
    uint256 public balance;
    uint32[] public agentIds;

    constructor(address _serviceRegistryTokenUtility) {
        serviceRegistryTokenUtility = _serviceRegistryTokenUtility;
    }

    function setAttackState(AttackState _state) external {
        state = _state;
    }

    function balanceOf(address) external view returns (uint256) {
        return balance;
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function transferFrom(address, address, uint256 amount) external {
        if (state == AttackState.FAILED_TRANSFER_FROM) {
            revert FailedTransferFrom();
        } else if (state == AttackState.BALANCE_ZERO) {
            balance = 0;
        } else if (state == AttackState.BALANCE_REDUCED) {
            balance = 3 * amount;
        } else if (state == AttackState.ACTIVATE_REGISTRATION) {
            IServiceRegistryTokenUtility(serviceRegistryTokenUtility).activateRegistrationTokenDeposit(0);
        } else if (state == AttackState.REGISTER_AGENTS) {
            IServiceRegistryTokenUtility(serviceRegistryTokenUtility).registerAgentsTokenDeposit(address(this), 0, agentIds);
        } else {
            balance += amount;
        }
    }

    function transfer(address, uint256 amount) external {
        if (state == AttackState.FAILED_TRANSFER) {
            revert FailedTransfer();
        } else if (state == AttackState.TERMINATE) {
            IServiceRegistryTokenUtility(serviceRegistryTokenUtility).terminateTokenRefund(0);
        } else if (state == AttackState.UNBOND) {
            IServiceRegistryTokenUtility(serviceRegistryTokenUtility).unbondTokenRefund(address(this), 0);
        }  else if (state == AttackState.DRAIN) {
            IServiceRegistryTokenUtility(serviceRegistryTokenUtility).drain(address(this));
        } else {
            balance += amount;
        }
    }
}