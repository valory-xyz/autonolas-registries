// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "./interfaces/IErrorsRegistries.sol";
import "./interfaces/IService.sol";

interface IToken{
    /// @dev Token allowance.
    /// @param account Account address that approves tokens.
    /// @param spender The target token spender address.
    function allowance(address account, address spender) external view returns (uint256);

    /// @dev Token transferFrom.
    /// @param from Address to transfer tokens from.
    /// @param to Address to transfer tokens to.
    /// @param amount Token amount.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @dev Gets the owner of the token Id.
    /// @param tokenId Token Id.
    /// @return Token Id owner address.
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @title Service Registry Token Utility - Smart contract for registering services that bond with ERC20 tokens
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract ServiceRegistryTokenUtility is IErrorsRegistries {
    event OwnerUpdated(address indexed owner);
    event ManagerUpdated(address indexed manager);
    event ServiceTokenDeposited(address indexed account, address indexed token, uint256 amount);

    // Struct for a token address and a deposit
    struct TokenDeposit {
        // Token address
        address token;
        // Bond per agent instance, enough for 79b+ or 7e28+
        // We assume that deposit value will be bound by that value
        uint96 deposit;
    }

    // Service Registry contract address
    address public immutable serviceRegistry;
    // Owner address
    address public owner;
    // Service Manager contract address;
    address public manager;
    // Map of service Id => address of a token
    mapping(uint256 => TokenDeposit) public mapServiceIdTokenDeposit;
    // Service Id and canonical agent Id => instance registration bond
    mapping(uint256 => uint256) public mapServiceAndAgentIdAgentBond;

    constructor(address _serviceRegistry) {
        serviceRegistry = _serviceRegistry;
        owner = msg.sender;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external virtual {
        // Check for the ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newOwner == address(0)) {
            revert ZeroAddress();
        }

        owner = newOwner;
        emit OwnerUpdated(newOwner);
    }

    /// @dev Changes the unit manager.
    /// @param newManager Address of a new unit manager.
    function changeManager(address newManager) external virtual {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newManager == address(0)) {
            revert ZeroAddress();
        }

        manager = newManager;
        emit ManagerUpdated(newManager);
    }

    /// @dev Creates a record with the token-related information for the specified service.
    /// @param serviceId Service Id.
    /// @param token Token address.
    /// @param agentIds Set of agent Ids.
    /// @param bonds Set of correspondent bonds.
    function createWithToken(uint256 serviceId, address token, uint32[] memory agentIds, uint256[] memory bonds) external {
        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Check for the zero token address
        if (token == address(0)) {
            revert ZeroAddress();
        }
        // TODO Check for the token ERC20 formality
        
        uint256 deposit;
        // Service is newly created and all the array lengths are checked by the original ServiceRegistry create() function
        for (uint256 i = 0; i < agentIds.length; ++i) {
            // Check for a non-zero bond value
            if (bonds[i] == 0) {
                revert ZeroValue();
            }
            // Check for a bond limit value
            if (bonds[i] > type(uint96).max) {
                revert Overflow(bonds[i], type(uint96).max);
            }
            // TODO What if some of the bond amount sum is bigger than the limit as well, but separately it's not
            // TODO Theoretically we should not forbid that as each operator could have a bond with an allowed limit
            
            // Push a pair of key defining variables into one key. Service or agent Ids are not enough by themselves
            // As with other units, we assume that the system is not expected to support more than than 2^32-1 services
            // Need to carefully check pairings, since it's hard to find if something is incorrectly misplaced bitwise
            // serviceId occupies first 32 bits
            uint256 serviceAgent = serviceId;
            // agentId takes the second 32 bits
            serviceAgent |= uint256(agentIds[i]) << 32;
            mapServiceAndAgentIdAgentBond[serviceAgent] = bonds[i];
            
            // Calculating a deposit
            if (bonds[i] > deposit){
                deposit = bonds[i];
            }
        }

        // Associate service Id with the provided token address
        mapServiceIdTokenDeposit[serviceId] = TokenDeposit(token, uint96(deposit));
    }

    /// @dev Deposit a token bond for service registration after its activation.
    /// @param serviceId Correspondent service Id.
    function activationTokenDeposit(uint256 serviceId) external returns (uint256 depositValue)
    {
        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Token address and bond
        TokenDeposit memory tokenDeposit = mapServiceIdTokenDeposit[serviceId];
        address token = tokenDeposit.token;
        if (token != address(0)) {
            depositValue = tokenDeposit.deposit;
            // Check for the allowance against this contract
            address serviceOwner = IToken(serviceRegistry).ownerOf(serviceId);
            uint256 allowance = IToken(token).allowance(serviceOwner, address(this));
            if (allowance < depositValue) {
                revert IncorrectRegistrationDepositValue(allowance, depositValue, serviceId);
            }

            // Transfer tokens from the msg.sender account
            // TODO Re-entrancy
            // TODO Safe transferFrom
            bool success = IToken(token).transferFrom(serviceOwner, address(this), depositValue);
            if (!success) {
                revert TransferFailed(token, serviceOwner, address(this), depositValue);
            }
            emit ServiceTokenDeposited(serviceOwner, token, depositValue);
        }
    }
}
