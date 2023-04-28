// The following code is from flattening this file: ServiceRegistryTokenUtility.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// The following code is from flattening this import statement in: ServiceRegistryTokenUtility.sol
// import "./interfaces/IErrorsRegistries.sol";
// The following code is from flattening this file: /home/andrey/valory/autonolas-registries/contracts/interfaces/IErrorsRegistries.sol

/// @dev Errors.
interface IErrorsRegistries {
    /// @dev Only `manager` has a privilege, but the `sender` was provided.
    /// @param sender Sender address.
    /// @param manager Required sender address as a manager.
    error ManagerOnly(address sender, address manager);

    /// @dev Only `owner` has a privilege, but the `sender` was provided.
    /// @param sender Sender address.
    /// @param owner Required sender address as an owner.
    error OwnerOnly(address sender, address owner);

    /// @dev Hash already exists in the records.
    error HashExists();

    /// @dev Provided zero address.
    error ZeroAddress();

    /// @dev Agent Id is not correctly provided for the current routine.
    /// @param agentId Component Id.
    error WrongAgentId(uint256 agentId);

    /// @dev Wrong length of two arrays.
    /// @param numValues1 Number of values in a first array.
    /// @param numValues2 Numberf of values in a second array.
    error WrongArrayLength(uint256 numValues1, uint256 numValues2);

    /// @dev Canonical agent Id is not found.
    /// @param agentId Canonical agent Id.
    error AgentNotFound(uint256 agentId);

    /// @dev Component Id is not found.
    /// @param componentId Component Id.
    error ComponentNotFound(uint256 componentId);

    /// @dev Multisig threshold is out of bounds.
    /// @param currentThreshold Current threshold value.
    /// @param minThreshold Minimum possible threshold value.
    /// @param maxThreshold Maximum possible threshold value.
    error WrongThreshold(uint256 currentThreshold, uint256 minThreshold, uint256 maxThreshold);

    /// @dev Agent instance is already registered with a specified `operator`.
    /// @param operator Operator that registered an instance.
    error AgentInstanceRegistered(address operator);

    /// @dev Wrong operator is specified when interacting with a specified `serviceId`.
    /// @param serviceId Service Id.
    error WrongOperator(uint256 serviceId);

    /// @dev Operator has no registered instances in the service.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    error OperatorHasNoInstances(address operator, uint256 serviceId);

    /// @dev Canonical `agentId` is not found as a part of `serviceId`.
    /// @param agentId Canonical agent Id.
    /// @param serviceId Service Id.
    error AgentNotInService(uint256 agentId, uint256 serviceId);

    /// @dev The contract is paused.
    error Paused();

    /// @dev Zero value when it has to be different from zero.
    error ZeroValue();

    /// @dev Value overflow.
    /// @param provided Overflow value.
    /// @param max Maximum possible value.
    error Overflow(uint256 provided, uint256 max);

    /// @dev Service must be inactive.
    /// @param serviceId Service Id.
    error ServiceMustBeInactive(uint256 serviceId);

    /// @dev All the agent instance slots for a specific `serviceId` are filled.
    /// @param serviceId Service Id.
    error AgentInstancesSlotsFilled(uint256 serviceId);

    /// @dev Wrong state of a service.
    /// @param state Service state.
    /// @param serviceId Service Id.
    error WrongServiceState(uint256 state, uint256 serviceId);

    /// @dev Only own service multisig is allowed.
    /// @param provided Provided address.
    /// @param expected Expected multisig address.
    /// @param serviceId Service Id.
    error OnlyOwnServiceMultisig(address provided, address expected, uint256 serviceId);

    /// @dev Multisig is not whitelisted.
    /// @param multisig Address of a multisig implementation.
    error UnauthorizedMultisig(address multisig);

    /// @dev Incorrect deposit provided for the registration activation.
    /// @param sent Sent amount.
    /// @param expected Expected amount.
    /// @param serviceId Service Id.
    error IncorrectRegistrationDepositValue(uint256 sent, uint256 expected, uint256 serviceId);

    /// @dev Insufficient value provided for the agent instance bonding.
    /// @param sent Sent amount.
    /// @param expected Expected amount.
    /// @param serviceId Service Id.
    error IncorrectAgentBondingValue(uint256 sent, uint256 expected, uint256 serviceId);

    /// @dev Failure of a transfer.
    /// @param token Address of a token.
    /// @param from Address `from`.
    /// @param to Address `to`.
    /// @param value Value.
    error TransferFailed(address token, address from, address to, uint256 value);

    /// @dev Caught reentrancy violation.
    error ReentrancyGuard();
}

// The following code is from flattening this import statement in: ServiceRegistryTokenUtility.sol
// import "./interfaces/IService.sol";
// The following code is from flattening this file: /home/andrey/valory/autonolas-registries/contracts/interfaces/IService.sol

/// @dev Required interface for the service manipulation.
interface IService{
    struct AgentParams {
        // Number of agent instances
        uint32 slots;
        // Bond per agent instance
        uint96 bond;
    }

    /// @dev Creates a new service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @return serviceId Created service Id.
    function create(
        address serviceOwner,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint32 threshold
    ) external returns (uint256 serviceId);

    /// @dev Updates a service in a CRUD way.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids in a sorted ascending order.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Signers threshold for a multisig composed by agent instances.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    function update(
        address serviceOwner,
        bytes32 configHash,
        uint32[] memory agentIds,
        AgentParams[] memory agentParams,
        uint32 threshold,
        uint256 serviceId
    ) external returns (bool success);

    /// @dev Activates the service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function activateRegistration(address serviceOwner, uint256 serviceId) external payable returns (bool success);

    /// @dev Registers agent instances.
    /// @param operator Address of the operator.
    /// @param serviceId Service Id to be updated.
    /// @param agentInstances Agent instance addresses.
    /// @param agentIds Canonical Ids of the agent correspondent to the agent instance.
    /// @return success True, if function executed successfully.
    function registerAgents(
        address operator,
        uint256 serviceId,
        address[] memory agentInstances,
        uint32[] memory agentIds
    ) external payable returns (bool success);

    /// @dev Creates multisig instance controlled by the set of service agent instances and deploys the service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param serviceId Correspondent service Id.
    /// @param multisigImplementation Multisig implementation address.
    /// @param data Data payload for the multisig creation.
    /// @return multisig Address of the created multisig.
    function deploy(
        address serviceOwner,
        uint256 serviceId,
        address multisigImplementation,
        bytes memory data
    ) external returns (address multisig);

    /// @dev Terminates the service.
    /// @param serviceOwner Owner of the service.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    /// @return refund Refund to return to the serviceOwner.
    function terminate(address serviceOwner, uint256 serviceId) external returns (bool success, uint256 refund);

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param operator Operator of agent instances.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function unbond(address operator, uint256 serviceId) external returns (bool success, uint256 refund);
}


// Generic token interface
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

    /// @dev Token transfer.
    /// @param to Address to transfer tokens to.
    /// @param amount Token amount.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Gets the owner of the token Id.
    /// @param tokenId Token Id.
    /// @return Token Id owner address.
    function ownerOf(uint256 tokenId) external view returns (address);
}

// Service Registry interface
interface IServiceUtility{
    /// @dev Gets the service instance from the map of services.
    /// @param serviceId Service Id.
    /// @return securityDeposit Registration activation deposit.
    /// @return multisig Service multisig address.
    /// @return configHash IPFS hashes pointing to the config metadata.
    /// @return threshold Agent instance signers threshold.
    /// @return maxNumAgentInstances Total number of agent instances.
    /// @return numAgentInstances Actual number of agent instances.
    /// @return state Service state.
    function mapServices(uint256 serviceId) external view returns (
        uint96 securityDeposit,
        address multisig,
        bytes32 configHash,
        uint32 threshold,
        uint32 maxNumAgentInstances,
        uint32 numAgentInstances,
        uint8 state
    );

    /// @dev Gets the operator address from the map of agent instance address => operator address
    function mapAgentInstanceOperators(address agentInstance) external view returns (address operator);
}

/// @title Service Registry Token Utility - Smart contract for registering services that bond with ERC20 tokens
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract ServiceRegistryTokenUtility is IErrorsRegistries {
    event OwnerUpdated(address indexed owner);
    event ManagerUpdated(address indexed manager);
    event DrainerUpdated(address indexed drainer);
    event TokenDeposit(address indexed account, address indexed token, uint256 amount);
    event TokenRefund(address indexed account, address indexed token, uint256 amount);
    event OperatorTokenSlashed(uint256 amount, address indexed operator, uint256 indexed serviceId);
    event TokenDrain(address indexed drainer, address indexed token, uint256 amount);

    // Struct for a token address and a security deposit
    struct TokenSecurityDeposit {
        // Token address
        address token;
        // Bond per agent instance, enough for 79b+ or 7e28+
        // We assume that the security deposit value will be bound by that value
        uint96 securityDeposit;
    }

    // Service Registry contract address
    address public immutable serviceRegistry;
    // Owner address
    address public owner;
    // Service Manager contract address;
    address public manager;
    // Drainer address: set by the government and is allowed to drain ETH funds accumulated in this contract
    address public drainer;
    // Reentrancy lock
    uint256 internal _locked = 1;
    // Map of service Id => address of a token
    mapping(uint256 => TokenSecurityDeposit) public mapServiceIdTokenDeposit;
    // Service Id and canonical agent Id => instance registration bond
    mapping(uint256 => uint256) public mapServiceAndAgentIdAgentBond;
    // Map of operator address and serviceId => agent instance bonding / escrow balance
    mapping(uint256 => uint256) public mapOperatorAndServiceIdOperatorBalances;
    // Map of token => slashed funds
    mapping(address => uint256) public mapSlashedFunds;

    /// @dev ServiceRegistryTokenUtility constructor.
    /// @param _serviceRegistry Service Registry contract address.
    constructor(address _serviceRegistry) {
        // Check for the zero address
        if (_serviceRegistry == address(0)) {
            revert ZeroAddress();
        }

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
    /// @param newManager Address of a new manager.
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

    /// @dev Changes the drainer.
    /// @param newDrainer Address of a drainer.
    function changeDrainer(address newDrainer) external {
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (newDrainer == address(0)) {
            revert ZeroAddress();
        }

        drainer = newDrainer;
        emit DrainerUpdated(newDrainer);
    }

    /// @dev Creates a record with the token-related information for the specified service.
    /// @notice We assume that the token is checked for being a non-zero address and a non-ETH address representation
    ///         outside of this function. Here we optimistically check for the token to have a specific `balanceOf`
    ///         view function. It is possible this is the attacker token that has all the required functions defined
    ///         correctly, so there is no point in checking that formality. All the required checks will be done in-place
    ///         where the possibility of misbehavior can be caught by return values of token function.
    /// @param serviceId Service Id.
    /// @param token Token address.
    /// @param agentIds Set of agent Ids.
    /// @param bonds Set of correspondent bonds.
    function createWithToken(
        uint256 serviceId,
        address token,
        uint32[] memory agentIds,
        uint256[] memory bonds
    ) external
    {
        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // TODO Check for the token ERC20 formality
        
        uint256 securityDeposit;
        // Service is newly created and all the array lengths are checked by the original ServiceRegistry create() function
        for (uint256 i = 0; i < agentIds.length; ++i) {
            // Check for a non-zero bond value and skip those with zeros (possible when updating a service)
            if (bonds[i] == 0) {
                continue;
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
            // We follow the optimistic design where existing bonds are just overwritten without a clearing
            // bond values of agent Ids that are not going to be used in the service. This is coming from the fact
            // that all the checks are done on the original ServiceRegistry side
            mapServiceAndAgentIdAgentBond[serviceAgent] = bonds[i];
            
            // Calculating a security deposit
            if (bonds[i] > securityDeposit){
                securityDeposit = bonds[i];
            }
        }

        // Associate service Id with the provided token address
        mapServiceIdTokenDeposit[serviceId] = TokenSecurityDeposit(token, uint96(securityDeposit));
    }

    /// @dev Resets a record with token and security deposit data.
    /// @param serviceId Service Id.
    function resetServiceToken(uint256 serviceId) external {
        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Delete token and security deposit data
        delete mapServiceIdTokenDeposit[serviceId];
    }

    /// @dev Deposit a token security deposit for the service registration after its activation.
    /// @param serviceId Service Id.
    /// @return isTokenSecured True if the service Id is token secured, false if ETH secured otherwise.
    function activateRegistrationTokenDeposit(uint256 serviceId) external returns (bool isTokenSecured) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Token address and bond
        TokenSecurityDeposit memory tokenDeposit = mapServiceIdTokenDeposit[serviceId];
        address token = tokenDeposit.token;
        if (token != address(0)) {
            uint256 securityDeposit = tokenDeposit.securityDeposit;
            // Check for the allowance against this contract
            address serviceOwner = IToken(serviceRegistry).ownerOf(serviceId);

            // Get the service owner allowance to this contract in specified tokens
            uint256 allowance = IToken(token).allowance(serviceOwner, address(this));
            if (allowance < securityDeposit) {
                revert IncorrectRegistrationDepositValue(allowance, securityDeposit, serviceId);
            }

            // Transfer tokens from the serviceOwner account
            // TODO Re-entrancy
            // TODO Safe transferFrom
            bool success = IToken(token).transferFrom(serviceOwner, address(this), securityDeposit);
            if (!success) {
                revert TransferFailed(token, serviceOwner, address(this), securityDeposit);
            }
            isTokenSecured = true;
            emit TokenDeposit(serviceOwner, token, securityDeposit);
        }

        _locked = 1;
    }

    /// @dev Deposits bonded tokens from the operator during the agent instance registration.
    /// @notice This is an optimistic implementation corresponding to registering agent instances by the operator
    ///         assuming that this function is always called in pair with the original Service Registry agent instance
    ///         registration function, where all the necessary validity checks are provided.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @param agentIds Set of agent Ids for corresponding agent instances opertor is registering.
    /// @return isTokenSecured True if the service Id is token secured, false if ETH secured otherwise.
    function registerAgentsTokenDeposit(
        address operator,
        uint256 serviceId,
        uint32[] memory agentIds
    ) external returns (bool isTokenSecured)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Token address
        address token = mapServiceIdTokenDeposit[serviceId].token;
        if (token != address(0)) {
            // Check for the sufficient amount of bond fee is provided
            uint256 numAgents = agentIds.length;
            uint256 totalBond = 0;
            for (uint256 i = 0; i < numAgents; ++i) {
                // Check if canonical agent Id exists in the service
                // Push a pair of key defining variables into one key. Service or agent Ids are not enough by themselves
                // serviceId occupies first 32 bits, agentId gets the next 32 bits
                uint256 serviceAgent = serviceId;
                serviceAgent |= uint256(agentIds[i]) << 32;
                uint256 bond = mapServiceAndAgentIdAgentBond[serviceAgent];
                totalBond += bond;
            }

            // Get the operator allowance to this contract in specified tokens
            uint256 allowance = IToken(token).allowance(operator, address(this));
            if (allowance < totalBond) {
                revert IncorrectRegistrationDepositValue(allowance, totalBond, serviceId);
            }

            // Record the total bond of the operator
            // Push a pair of key defining variables into one key. Service Id or operator are not enough by themselves
            // operator occupies first 160 bits
            uint256 operatorService = uint256(uint160(operator));
            // serviceId occupies next 32 bits
            operatorService |= serviceId << 160;
            totalBond += mapOperatorAndServiceIdOperatorBalances[operatorService];
            mapOperatorAndServiceIdOperatorBalances[operatorService] = totalBond;

            // Transfer tokens from the operator account
            // TODO Re-entrancy
            // TODO Safe transferFrom
            bool success = IToken(token).transferFrom(operator, address(this), totalBond);
            if (!success) {
                revert TransferFailed(token, operator, address(this), totalBond);
            }
            isTokenSecured = true;
            emit TokenDeposit(operator, token, totalBond);
        }

        _locked = 1;
    }

    /// @dev Refunds a token security deposit to the service owner after the service termination.
    /// @param serviceId Service Id.
    /// @return securityRefund Returned token security deposit, or zero if the service is ETH-secured.
    function terminateTokenRefund(uint256 serviceId) external returns (uint256 securityRefund) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Token address and bond
        TokenSecurityDeposit memory tokenDeposit = mapServiceIdTokenDeposit[serviceId];
        address token = tokenDeposit.token;
        if (token != address(0)) {
            securityRefund = tokenDeposit.securityDeposit;
            // Check for the allowance against this contract
            address serviceOwner = IToken(serviceRegistry).ownerOf(serviceId);

            // Transfer tokens to the serviceOwner account
            // TODO Re-entrancy
            // TODO Safe transfer
            bool success = IToken(token).transfer(serviceOwner, securityRefund);
            if (!success) {
                revert TransferFailed(token, address(this), serviceOwner, securityRefund);
            }
            emit TokenRefund(serviceOwner, token, securityRefund);
        }

        _locked = 1;
    }

    /// @dev Refunds bonded tokens to the operator during the unbond phase.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @return refund Returned bonded token amount, or zero if the service is ETH-secured.
    function unbondTokenRefund(address operator, uint256 serviceId) external returns (uint256 refund) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the manager privilege for a service management
        if (manager != msg.sender) {
            revert ManagerOnly(msg.sender, manager);
        }

        // Token address
        address token = mapServiceIdTokenDeposit[serviceId].token;
        if (token != address(0)) {
            // Check for the operator and unbond all its agent instances
            // Push a pair of key defining variables into one key. Service Id or operator are not enough by themselves
            // operator occupies first 160 bits
            uint256 operatorService = uint256(uint160(operator));
            // serviceId occupies next 32 bits
            operatorService |= serviceId << 160;
            // Get the total bond for agent Ids bonded by the operator corresponding to registered agent instances
            refund = mapOperatorAndServiceIdOperatorBalances[operatorService];

            // The zero refund scenario is possible if the operator was slashed for the agent instance misbehavior
            if (refund > 0) {
                // Operator's balance is essentially zero after the refund
                mapOperatorAndServiceIdOperatorBalances[operatorService] = 0;
                // Transfer tokens to the operator account
                // TODO Re-entrancy
                // TODO Safe transfer
                // Refund the operator
                bool success = IToken(token).transfer(operator, refund);
                if (!success) {
                    revert TransferFailed(token, address(this), operator, refund);
                }
                emit TokenRefund(operator, token, refund);
            }
        }

        _locked = 1;
    }

    /// @dev Slashes a specified agent instance.
    /// @param agentInstances Agent instances to slash.
    /// @param amounts Correspondent amounts to slash.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    function slash(address[] memory agentInstances, uint256[] memory amounts, uint256 serviceId) external
        returns (bool success)
    {
        // Check if the service is deployed
        (, address multisig, , , , , uint8 state) = IServiceUtility(serviceRegistry).mapServices(serviceId);
        // ServiceState.Deployed == 4 in the original ServiceRegistry contract
        if (state != 4) {
            revert WrongServiceState(uint256(state), serviceId);
        }

        // Check for the array size
        if (agentInstances.length == 0 || agentInstances.length != amounts.length) {
            revert WrongArrayLength(agentInstances.length, amounts.length);
        }

        // Only the multisig of a correspondent address can slash its agent instances
        if (msg.sender != multisig) {
            revert OnlyOwnServiceMultisig(msg.sender, multisig, serviceId);
        }

        // Token address
        address token = mapServiceIdTokenDeposit[serviceId].token;
        // TODO Verify if that scenario is possible at all, since if correctly updated, token must never be equal to zero, or be called from this contract
        // This is to protect this slash function not to be called for ETH-secured services
        if (token == address(0)) {
            revert ZeroAddress();
        }

        // Loop over each agent instance
        uint256 numInstancesToSlash = agentInstances.length;
        uint256 slashedFunds;
        for (uint256 i = 0; i < numInstancesToSlash; ++i) {
            // Get the service Id from the agentInstance map
            address operator = IServiceUtility(serviceRegistry).mapAgentInstanceOperators(agentInstances[i]);
            // Push a pair of key defining variables into one key. Service Id or operator are not enough by themselves
            // operator occupies first 160 bits
            uint256 operatorService = uint256(uint160(operator));
            // serviceId occupies next 32 bits
            operatorService |= serviceId << 160;
            // Slash the balance of the operator, make sure it does not go below zero
            uint256 balance = mapOperatorAndServiceIdOperatorBalances[operatorService];
            // Skip the zero balance
            if (balance == 0) {
                continue;
            } else if (amounts[i] >= balance) {
                // We cannot add to the slashed amount more than the balance of the operator
                slashedFunds += balance;
                balance = 0;
            } else {
                // Slash the specified amount
                slashedFunds += amounts[i];
                balance -= amounts[i];
            }
            mapOperatorAndServiceIdOperatorBalances[operatorService] = balance;

            emit OperatorTokenSlashed(amounts[i], operator, serviceId);
        }
        slashedFunds += mapSlashedFunds[token];
        mapSlashedFunds[token] = slashedFunds;
        success = true;
    }

    /// @dev Drains slashed funds to the drainer address.
    /// @param token Token address.
    /// @return amount Drained amount.
    function drain(address token) external returns (uint256 amount) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the drainer address
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for the zero address
        if (drainer == address(0)) {
            revert ZeroAddress();
        }

        // Drain the slashed funds
        amount = mapSlashedFunds[token];
        if (amount > 0) {
            mapSlashedFunds[token] = 0;
            // TODO Safe transfer
            // Send the refund
            bool success = IToken(token).transfer(drainer, amount);
            if (!success) {
                revert TransferFailed(token, address(this), msg.sender, amount);
            }
            emit TokenDrain(msg.sender, token, amount);
        }

        _locked = 1;
    }

    /// @dev Gets service token secured status.
    /// @param serviceId Service Id.
    /// @return True if the service Id is token secured.
    function isTokenSecuredService(uint256 serviceId) external view returns (bool) {
        return mapServiceIdTokenDeposit[serviceId].token != address(0);
    }

    /// @dev Gets the operator's balance in a specific service.
    /// @param operator Operator address.
    /// @param serviceId Service Id.
    /// @return balance The balance of the operator.
    function getOperatorBalance(address operator, uint256 serviceId) external view returns (uint256 balance) {
        uint256 operatorService = uint256(uint160(operator));
        operatorService |= serviceId << 160;
        balance = mapOperatorAndServiceIdOperatorBalances[operatorService];
    }
}



