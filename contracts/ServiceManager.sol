// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GenericManager} from "./GenericManager.sol";
import {OperatorSignedHashes} from "./utils/OperatorSignedHashes.sol";
import "./interfaces/IService.sol";
import "./interfaces/IServiceTokenUtility.sol";

// Operator whitelist interface
interface IOperatorWhitelist {
    /// @dev Gets operator whitelisting status.
    /// @param serviceId Service Id.
    /// @param operator Operator address.
    /// @return status Whitelisting status.
    function isOperatorWhitelisted(uint256 serviceId, address operator) external view returns (bool status);
}

interface IIdentityRegistryBridger {
    /// @dev Registers 8004 agent Id corresponding to service Id.
    /// @param serviceId Service Id.
    /// @return agentId Corresponding 8004 agent Id.
    function register(uint256 serviceId) external returns (uint256 agentId);

    /// @dev Updates 8004 agent Id wallet corresponding to service Id multisig.
    /// @param serviceId Service Id.
    /// @param oldMultisig Old multisig address.
    /// @param newMultisig New multisig address.
    function updateAgentWallet(uint256 serviceId, address oldMultisig, address newMultisig) external;

    /// @dev Gets 8004 agent Id corresponding to service Id.
    /// @param serviceId Service Id.
    /// @return agentId Corresponding 8004 agent Id, or zero if none.
    function mapServiceIdAgentIds(uint256 serviceId) external view returns (uint256 agentId);

    /// @dev Gets 8004 agent Id whose identity the multisig is linked to.
    /// @param multisig Multisig address.
    /// @return agentId Linked 8004 agent Id, or zero if none.
    function mapMultisigAgentIds(address multisig) external view returns (uint256 agentId);
}

interface IServiceRegistry {
    enum ServiceState {
        NonExistent,
        PreRegistration,
        ActiveRegistration,
        FinishedRegistration,
        Deployed,
        TerminatedBonded
    }

    /// @dev Gets service instance params.
    /// @param serviceId Service Id.
    /// @return securityDeposit Registration activation deposit.
    /// @return multisig Service multisig address.
    /// @return configHash IPFS hashes pointing to the config metadata.
    /// @return threshold Agent instance signers threshold.
    /// @return maxNumAgentInstances Total number of agent instances.
    /// @return numAgentInstances Actual number of agent instances.
    /// @return state Service state.
    function mapServices(uint256 serviceId)
        external
        view
        returns (
            uint96 securityDeposit,
            address multisig,
            bytes32 configHash,
            uint32 threshold,
            uint32 maxNumAgentInstances,
            uint32 numAgentInstances,
            ServiceState state
        );

    struct Service {
        uint96 securityDeposit;
        address multisig;
        bytes32 configHash;
        uint32 threshold;
        uint32 maxNumAgentInstances;
        uint32 numAgentInstances;
        ServiceState state;
        uint32[] agentIds;
    }

    /// @dev Gets the service instance.
    /// @param serviceId Service Id.
    /// @return service Service instance, including its canonical agent Ids.
    function getService(uint256 serviceId) external view returns (Service memory service);

    /// @dev Gets agent parameters for a (service Id | agent Id) pair.
    /// @param serviceAgent Service Id in the first 32 bits, agent Id in the next 32 bits.
    /// @return slots Number of agent instances.
    /// @return bond Bond per agent instance.
    function mapServiceAndAgentIdAgentParams(uint256 serviceAgent) external view returns (uint32 slots, uint96 bond);

    /// @dev Gets service total supply.
    function totalSupply() external view returns (uint256);
}

// ERC721 interface
interface IERC721 {
    /// @dev Gets the owner of the token Id.
    /// @param tokenId Token Id.
    /// @return Token Id owner address.
    function ownerOf(uint256 tokenId) external view returns (address);
}

/// @dev Storage is already initialized.
error AlreadyInitialized();

/// @dev Multisig is already bound to a different service.
/// @param multisig Multisig address.
/// @param existingServiceId Service Id the multisig is already bound to.
/// @param serviceId Service Id attempting to bind the multisig.
error MultisigAlreadyBound(address multisig, uint256 existingServiceId, uint256 serviceId);

/// @dev Provided agent instance address is reserved and cannot hold a service multisig.
/// @param agentInstance Provided agent instance address.
error ReservedAgentInstance(address agentInstance);

/// @dev Signed bond token is not the service bond token.
/// @param provided Signed bond token.
/// @param expected Service bond token, or ETH_TOKEN_ADDRESS for a native-token service.
error WrongBondToken(address provided, address expected);

/// @dev Total bond of the registration exceeds the signed maximum.
/// @param totalBond Total bond of the registration.
/// @param maxBond Signed maximum bond.
error BondExceedsMax(uint256 totalBond, uint256 maxBond);

/// @title Service Manager - Periphery smart contract for managing services with custom ERC20 tokens or ETH
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
/// @notice ERC-8004 identity: the service owner has no direct access to the service's identity through the
///         identity registry bridger; the owner's influence is that deploying the service determines which multisig
///         is linked to it. Only the linked multisig can act on the identity through the bridger, from deployment
///         until the service is terminated; termination clears the link and unsets the agent wallet, unbonding does
///         not involve the bridger, and a redeployment links the deployed multisig again, whether the same one or a new
///         one.
///         Multisig binding: a service multisig stays bound to its service (mapMultisigServiceIds) after the service
///         is terminated and unbonded. The binding is released only when the service is redeployed with a different
///         multisig; until then the multisig can be redeployed only under the same service.
contract ServiceManager is GenericManager, OperatorSignedHashes {
    event OperatorWhitelistUpdated(address indexed operatorWhitelist);
    event IdentityRegistryBridgerUpdated(address indexed identityRegistryBridger);
    event ImplementationUpdated(address indexed implementation);
    event CreateMultisig(address indexed multisig);
    event MultisigBound(address indexed multisig, uint256 indexed serviceId);
    event UnbondWithSignatureExecuted(address indexed operator, uint256 indexed serviceId, uint256 refund);
    event RegisterAgentsWithSignatureExecuted(
        address indexed operator, uint256 indexed serviceId, address[] agentInstances, uint32[] agentIds
    );

    // Name of a signing domain
    string public constant NAME = "OLAS Service Manager";
    // Version number
    string public constant VERSION = "1.3.0";
    // Service Manager proxy address slot
    // keccak256("PROXY_SERVICE_MANAGER") = "0xe39e69948a448ce9239ad71b908b6c5b46225f86ffa735b25a8cd64080315855"
    bytes32 public constant PROXY_SERVICE_MANAGER = 0xe39e69948a448ce9239ad71b908b6c5b46225f86ffa735b25a8cd64080315855;
    // A well-known representation of ETH as address
    address public constant ETH_TOKEN_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    // Bond wrapping constant
    uint96 public constant BOND_WRAPPER = 1;
    // Highest address treated as reserved and rejected as an agent instance.
    // Covers the zero address, Safe's SENTINEL_OWNERS (0x1) and every precompile: the bound sits far
    // above the highest allocated one so it does not have to move when a fork adds more. No address in
    // this range can be controlled, since addresses are derived from hashes.
    address public constant MAX_RESERVED_AGENT_INSTANCE = address(0xffff);

    // Service Registry address
    address public immutable serviceRegistry;
    // Service Registry Token Utility address
    address public immutable serviceRegistryTokenUtility;

    // Operator whitelist address
    address public operatorWhitelist;

    // 8004 Identity Registry Bridger address
    address public identityRegistryBridger;

    // Reentrancy lock
    uint256 internal _locked = 1;

    // Global multisig -> owning service Id binding. A multisig belongs to at most one service.
    mapping(address => uint256) public mapMultisigServiceIds;

    /// @dev ServiceManager constructor.
    /// @param _serviceRegistry Service Registry address.
    /// @param _serviceRegistryTokenUtility Service Registry Token Utility address.
    constructor(address _serviceRegistry, address _serviceRegistryTokenUtility) OperatorSignedHashes(NAME, VERSION) {
        // Check for the Service Registry related contract zero addresses
        if (_serviceRegistry == address(0) || _serviceRegistryTokenUtility == address(0)) {
            revert ZeroAddress();
        }

        serviceRegistry = _serviceRegistry;
        serviceRegistryTokenUtility = _serviceRegistryTokenUtility;
    }

    /// @dev Initializes proxy contract storage.
    function initialize() external {
        // Check if contract is already initialized
        if (owner != address(0)) {
            revert AlreadyInitialized();
        }

        owner = msg.sender;
    }

    /// @dev Sets the operator whitelist contract address.
    /// @param newOperatorWhitelist New operator whitelist contract address.
    function setOperatorWhitelist(address newOperatorWhitelist) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        operatorWhitelist = newOperatorWhitelist;
        emit OperatorWhitelistUpdated(newOperatorWhitelist);
    }

    /// @dev Sets identity registry bridger contract address.
    /// @param newIdentityRegistryBridger New identity registry bridger contract address.
    function setIdentityRegistryBridger(address newIdentityRegistryBridger) external {
        // Check for the contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        identityRegistryBridger = newIdentityRegistryBridger;
        emit IdentityRegistryBridgerUpdated(newIdentityRegistryBridger);
    }

    /// @dev Changes implementation contract address.
    /// @notice Make sure implementation contract has function to change its implementation.
    /// @param implementation Implementation contract address.
    function changeImplementation(address implementation) external {
        // Check for contract ownership
        if (msg.sender != owner) {
            revert OwnerOnly(msg.sender, owner);
        }

        // Check for zero address
        if (implementation == address(0)) {
            revert ZeroAddress();
        }

        // Store implementation address under designated storage slot
        assembly {
            sstore(PROXY_SERVICE_MANAGER, implementation)
        }
        emit ImplementationUpdated(implementation);
    }

    /// @dev Creates a new service.
    /// @param serviceOwner Individual that creates and controls a service.
    /// @param token ERC20 token address for the security deposit, or ETH.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Threshold for a multisig composed by agents.
    /// @return serviceId Created service Id.
    function create(
        address serviceOwner,
        address token,
        bytes32 configHash,
        uint32[] memory agentIds,
        IService.AgentParams[] memory agentParams,
        uint32 threshold
    ) external returns (uint256 serviceId) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check if the minting is paused
        if (paused) {
            revert Paused();
        }

        // Check for the zero address
        if (token == address(0)) {
            revert ZeroAddress();
        }

        // Check for the custom ERC20 token or ETH based bond
        if (token == ETH_TOKEN_ADDRESS) {
            // Call the original ServiceRegistry contract function
            serviceId = IService(serviceRegistry).create(serviceOwner, configHash, agentIds, agentParams, threshold);
        } else {
            // Wrap agent params with just 1 WEI bond going to the original ServiceRegistry contract,
            // and actual token bonds being recorded with the ServiceRegistryTokenUtility contract
            uint256 numAgents = agentParams.length;
            uint256[] memory bonds = new uint256[](numAgents);
            for (uint256 i = 0; i < numAgents; ++i) {
                // Check for the zero bond value
                if (agentParams[i].bond == 0) {
                    revert ZeroValue();
                }

                // Copy actual bond values for each agent Id
                bonds[i] = agentParams[i].bond;
                // Wrap bonds with the BOND_WRAPPER value for the original ServiceRegistry contract
                agentParams[i].bond = BOND_WRAPPER;
            }

            // Get created service Id
            serviceId = IServiceRegistry(serviceRegistry).totalSupply() + 1;

            // Create a token-related record for the service
            IServiceTokenUtility(serviceRegistryTokenUtility).createWithToken(serviceId, token, agentIds, bonds);

            // Call the original ServiceRegistry contract function
            IService(serviceRegistry).create(serviceOwner, configHash, agentIds, agentParams, threshold);
        }

        // 8004 Identity Registry workflow
        if (identityRegistryBridger != address(0)) {
            // Register corresponding 8004 agent Id
            IIdentityRegistryBridger(identityRegistryBridger).register(serviceId);
        }

        _locked = 1;
    }

    /// @dev Updates a service in a CRUD way.
    /// @notice Updates clear parameters for agent Ids omitted from the current configuration: they are passed to the
    ///         registry with zero slots, so no parameters of an omitted agent Id remain to be registered against.
    ///         This does not automatically clear parameters left by earlier updates, whose agent Ids are no longer in
    ///         the current configuration; owners can explicitly include those agent Ids with zero slots when updating
    ///         in PreRegistration.
    /// @param token ERC20 token address for the security deposit, or ETH.
    /// @param configHash IPFS hash pointing to the config metadata.
    /// @param agentIds Canonical agent Ids.
    /// @param agentParams Number of agent instances and required bond to register an instance in the service.
    /// @param threshold Threshold for a multisig composed by agents.
    /// @param serviceId Service Id to be updated.
    /// @return success True, if function executed successfully.
    function update(
        address token,
        bytes32 configHash,
        uint32[] memory agentIds,
        IService.AgentParams[] memory agentParams,
        uint32 threshold,
        uint256 serviceId
    ) external returns (bool success) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check for the zero address
        if (token == address(0)) {
            revert ZeroAddress();
        }

        // Remove the service agent Ids omitted from the new set
        (agentIds, agentParams) = _addOmittedAgentIds(serviceId, agentIds, agentParams);

        uint256 numAgents = agentParams.length;
        if (token == ETH_TOKEN_ADDRESS) {
            // If any of the slots is a non-zero, the correspondent bond cannot be zero
            for (uint256 i = 0; i < numAgents; ++i) {
                // Check for the zero bond value
                if (agentParams[i].slots > 0 && agentParams[i].bond == 0) {
                    revert ZeroValue();
                }
            }

            // Call the original ServiceRegistry contract function
            success =
                IService(serviceRegistry).update(msg.sender, configHash, agentIds, agentParams, threshold, serviceId);

            // Reset the service token-based data
            // This function still needs to be called as the previous token could be a custom ERC20 token
            IServiceTokenUtility(serviceRegistryTokenUtility).resetServiceToken(serviceId);
        } else {
            // Wrap agent params with just 1 WEI bond going to the original ServiceRegistry contract,
            // and actual token bonds being recorded with the ServiceRegistryTokenUtility contract
            uint256[] memory bonds = new uint256[](numAgents);
            for (uint256 i = 0; i < numAgents; ++i) {
                // Copy actual bond values for each agent Id that has at least one slot in the updated service
                if (agentParams[i].slots > 0) {
                    // Check for the zero bond value
                    if (agentParams[i].bond == 0) {
                        revert ZeroValue();
                    }
                    bonds[i] = agentParams[i].bond;
                    // Wrap bonds with the BOND_WRAPPER value for the original ServiceRegistry contract
                    agentParams[i].bond = BOND_WRAPPER;
                }
            }

            // Update relevant data in the ServiceRegistryTokenUtility contract
            // We follow the optimistic design where existing bonds are just overwritten without a clearing
            // bond values of agent Ids that are not going to be used in the service. This is coming from the fact
            // that all the checks are done on the original ServiceRegistry side
            IServiceTokenUtility(serviceRegistryTokenUtility).createWithToken(serviceId, token, agentIds, bonds);

            // Call the original ServiceRegistry contract function
            success =
                IService(serviceRegistry).update(msg.sender, configHash, agentIds, agentParams, threshold, serviceId);
        }

        _locked = 1;
    }

    /// @dev Activates the service and its sensitive components.
    /// @param serviceId Correspondent service Id.
    /// @return success True, if function executed successfully.
    function activateRegistration(uint256 serviceId) external payable returns (bool success) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Record the actual ERC20 security deposit
        bool isTokenSecured =
            IServiceTokenUtility(serviceRegistryTokenUtility).activateRegistrationTokenDeposit(serviceId);

        // Activate registration in the original ServiceRegistry contract
        if (isTokenSecured) {
            // Check for msg.value
            if (msg.value != BOND_WRAPPER) {
                revert IncorrectRegistrationDepositValue(msg.value, BOND_WRAPPER, serviceId);
            }

            // If the service Id is based on the ERC20 token, the provided value to the standard registration is 1
            success = IService(serviceRegistry).activateRegistration{value: BOND_WRAPPER}(msg.sender, serviceId);
        } else {
            // Otherwise follow the standard msg.value path
            success = IService(serviceRegistry).activateRegistration{value: msg.value}(msg.sender, serviceId);
        }

        _locked = 1;
    }

    /// @dev Rejects agent instance addresses that cannot serve as a usable multisig owner.
    /// @notice Addresses at or below MAX_RESERVED_AGENT_INSTANCE are either rejected by Safe setup, which
    ///         leaves the service unable to deploy, or accepted while being unsignable. Neither is a
    ///         configuration any service owner intends.
    /// @param agentInstances Agent instance addresses.
    function _checkAgentInstances(address[] memory agentInstances) internal pure {
        for (uint256 i = 0; i < agentInstances.length; ++i) {
            if (agentInstances[i] <= MAX_RESERVED_AGENT_INSTANCE) {
                revert ReservedAgentInstance(agentInstances[i]);
            }
        }
    }

    /// @dev Registers agent instances.
    /// @param serviceId Service Id to be updated.
    /// @param agentInstances Agent instance addresses.
    /// @param agentIds Canonical Ids of the agent correspondent to the agent instance.
    /// @return success True, if function executed successfully.
    function registerAgents(uint256 serviceId, address[] memory agentInstances, uint32[] memory agentIds)
        external
        payable
        returns (bool success)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        if (operatorWhitelist != address(0)) {
            // Check if the operator is whitelisted
            if (!IOperatorWhitelist(operatorWhitelist).isOperatorWhitelisted(serviceId, msg.sender)) {
                revert WrongOperator(serviceId);
            }
        }

        // Reject reserved agent instance addresses
        _checkAgentInstances(agentInstances);

        // Advance the registerAgents nonce on the direct path as well, so an authorization signed for the
        // current nonce and left unused cannot be replayed against later state
        // operator occupies first 160 bits
        uint256 operatorService = uint256(uint160(msg.sender));
        // serviceId occupies next 32 bits as serviceId is limited by the 2^32 - 1 value
        operatorService |= serviceId << 160;
        mapOperatorRegisterAgentsNonces[operatorService]++;

        // Record the actual ERC20 bond
        bool isTokenSecured = IServiceTokenUtility(serviceRegistryTokenUtility)
            .registerAgentsTokenDeposit(msg.sender, serviceId, agentIds);

        // Register agent instances in a main ServiceRegistry contract
        if (isTokenSecured) {
            // Get total bond wrapper value
            uint256 totalBond = agentInstances.length * BOND_WRAPPER;
            // Check for msg.value
            if (msg.value != totalBond) {
                revert IncorrectAgentBondingValue(msg.value, totalBond, serviceId);
            }

            // If the service Id is based on the ERC20 token, the provided value to the standard registration is 1
            // multiplied by the number of agent instances
            success = IService(serviceRegistry).registerAgents{value: totalBond}(
                msg.sender, serviceId, agentInstances, agentIds
            );
        } else {
            // Otherwise follow the standard msg.value path
            success = IService(serviceRegistry).registerAgents{value: msg.value}(
                msg.sender, serviceId, agentInstances, agentIds
            );
        }

        _locked = 1;
    }

    /// @dev Creates multisig instance controlled by the set of service agent instances and deploys the service.
    /// @param serviceId Correspondent service Id.
    /// @param multisigImplementation Multisig implementation address.
    /// @param data Data payload for the multisig creation.
    /// @return multisig Address of the created multisig.
    function deploy(uint256 serviceId, address multisigImplementation, bytes memory data)
        external
        returns (address multisig)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Get current service multisig
        (, address lastMultisig,,,,,) = IServiceRegistry(serviceRegistry).mapServices(serviceId);

        // Create or update multisig instance
        multisig = IService(serviceRegistry).deploy(msg.sender, serviceId, multisigImplementation, data);

        // Check for zero address
        if (multisig == address(0)) {
            revert ZeroAddress();
        }

        // Bind multisig to service: revert if owned by another, claim if unowned, release the previous one on change
        uint256 boundServiceId = mapMultisigServiceIds[multisig];
        if (boundServiceId != serviceId) {
            if (boundServiceId != 0) {
                revert MultisigAlreadyBound(multisig, boundServiceId, serviceId);
            }
            mapMultisigServiceIds[multisig] = serviceId;
            emit MultisigBound(multisig, serviceId);

            // Release the service's previous multisig only if it is still bound to this service
            if (lastMultisig != address(0) && lastMultisig != multisig && mapMultisigServiceIds[lastMultisig] == serviceId) {
                mapMultisigServiceIds[lastMultisig] = 0;
                emit MultisigBound(lastMultisig, 0);
            }
        }

        // 8004 Identity Registry workflow: link the deployed multisig to the service 8004 agent Id, unless it already is.
        // The final unbond clears the link, so a redeployment with the same multisig links it again
        address bridger = identityRegistryBridger;
        if (bridger != address(0)) {
            uint256 agentId = IIdentityRegistryBridger(bridger).mapServiceIdAgentIds(serviceId);
            if (agentId > 0 && IIdentityRegistryBridger(bridger).mapMultisigAgentIds(multisig) != agentId) {
                // Unlink the previous multisig and unset the agent wallet only if a different multisig is still
                // linked to this agent Id
                address oldMultisig;
                if (lastMultisig != address(0) && lastMultisig != multisig &&
                    IIdentityRegistryBridger(bridger).mapMultisigAgentIds(lastMultisig) == agentId) {
                    oldMultisig = lastMultisig;
                }
                IIdentityRegistryBridger(bridger).updateAgentWallet(serviceId, oldMultisig, multisig);
            }
        }

        emit CreateMultisig(multisig);

        _locked = 1;
    }

    /// @dev Back-fills the multisig <-> service binding for services deployed before this upgrade.
    /// @notice Permissionless and idempotent: for each service Id it records only that service's OWN current
    ///         multisig (read from the registry), and skips entries with no multisig or already bound. It can
    ///         therefore only ever write the registry's true binding and cannot forge a foreign one. Anyone may
    ///         call it to back-fill the existing fleet in bulk.
    /// @param serviceIds Set of service Ids to back-fill.
    function bindMultisig(uint256[] calldata serviceIds) external {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        for (uint256 i = 0; i < serviceIds.length; ++i) {
            (, address multisig,,,,,) = IServiceRegistry(serviceRegistry).mapServices(serviceIds[i]);
            // Check for multisig to be non zero and not yet recorded
            if (multisig != address(0) && mapMultisigServiceIds[multisig] == 0) {
                mapMultisigServiceIds[multisig] = serviceIds[i];
                emit MultisigBound(multisig, serviceIds[i]);
            }
        }

        _locked = 1;
    }

    /// @dev Terminates the service.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund Refund for the service owner.
    function terminate(uint256 serviceId) external returns (bool success, uint256 refund) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Withdraw the ERC20 token if the service is token-based
        uint256 tokenRefund = IServiceTokenUtility(serviceRegistryTokenUtility).terminateTokenRefund(serviceId);

        // Terminate the service with the regular service registry routine
        (success, refund) = IService(serviceRegistry).terminate(msg.sender, serviceId);

        // End the multisig's access to the service 8004 agent Id
        _unlinkAgentWallet(serviceId);

        // If the service is token-based, the actual refund is provided via the serviceRegistryTokenUtility contract
        if (tokenRefund > 0) {
            refund = tokenRefund;
        }

        _locked = 1;
    }

    /// @dev Unlinks the service multisig from the service 8004 agent Id when the service is terminated.
    /// @notice Runs after every successful termination, whatever the state the service was terminated from, so a link
    ///         kept from an earlier deployment is cleared as well. The link is cleared and the agent wallet unset only
    ///         if the multisig is linked to this service's agent Id, so a link to another agent Id is never touched. A
    ///         failure reverts the termination. The multisig binding in mapMultisigServiceIds is kept; the next
    ///         deployment links the deployed multisig again.
    /// @param serviceId Service Id.
    function _unlinkAgentWallet(uint256 serviceId) internal {
        address bridger = identityRegistryBridger;
        if (bridger == address(0)) {
            return;
        }

        // Skip if the service has never been deployed
        (, address multisig,,,,,) = IServiceRegistry(serviceRegistry).mapServices(serviceId);
        if (multisig == address(0)) {
            return;
        }

        uint256 agentId = IIdentityRegistryBridger(bridger).mapServiceIdAgentIds(serviceId);
        if (agentId > 0 && IIdentityRegistryBridger(bridger).mapMultisigAgentIds(multisig) == agentId) {
            IIdentityRegistryBridger(bridger).updateAgentWallet(serviceId, multisig, address(0));
        }
    }

    /// @dev Unbonds agent instances of the operator from the service.
    /// @param serviceId Service Id.
    /// @return success True, if function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function unbond(uint256 serviceId) external returns (bool success, uint256 refund) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Advance the unbond nonce on the direct path as well, for the same reason as registerAgents
        // operator occupies first 160 bits
        uint256 operatorService = uint256(uint160(msg.sender));
        // serviceId occupies next 32 bits as serviceId is limited by the 2^32 - 1 value
        operatorService |= serviceId << 160;
        mapOperatorUnbondNonces[operatorService]++;

        // Withdraw the ERC20 token if the service is token-based
        uint256 tokenRefund = IServiceTokenUtility(serviceRegistryTokenUtility).unbondTokenRefund(msg.sender, serviceId);

        // Unbond with the regular service registry routine
        (success, refund) = IService(serviceRegistry).unbond(msg.sender, serviceId);

        // If the service is token-based, the actual refund is provided via the serviceRegistryTokenUtility contract
        if (tokenRefund > 0) {
            refund = tokenRefund;
        }

        _locked = 1;
    }

    /// @dev Unbonds agent instances of the operator by the service owner via the operator's pre-signed message hash.
    /// @notice Note that this function accounts for the operator being the EOA, or the contract that has an
    ///         isValidSignature() function that would confirm the message hash was signed by the operator contract.
    ///         isValidSignature() receives the 65 signature bytes with the operator address in r, so a wallet that
    ///         reads owner signatures from them, such as Safe, uses the pre-approved hash path; see _verifySignedHash().
    ///         Otherwise, if the message hash has been pre-approved, the corresponding map of hashes is going to
    ///         to verify the signed hash, similar to the Safe contract implementation in v1.3.0:
    ///         https://github.com/safe-global/safe-contracts/blob/186a21a74b327f17fc41217a927dea7064f74604/contracts/GnosisSafe.sol#L240-L304
    ///         Also note that only the service owner is able to call this function on behalf of the operator.
    /// @param operator Operator address that signed the unbond message hash.
    /// @param serviceId Service Id.
    /// @param deadline Last timestamp at which the signed message can be used.
    /// @param signature Signature byte array associated with operator message hash signature.
    /// @return success True, if the function executed successfully.
    /// @return refund The amount of refund returned to the operator.
    function unbondWithSignature(address operator, uint256 serviceId, uint256 deadline, bytes memory signature)
        external
        returns (bool success, uint256 refund)
    {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check the signed message deadline
        _checkDeadline(deadline);

        // Check the service owner
        address serviceOwner = IERC721(serviceRegistry).ownerOf(serviceId);
        if (msg.sender != serviceOwner) {
            revert OwnerOnly(msg.sender, serviceOwner);
        }

        // Get the (operator | serviceId) nonce for the unbond message
        // Push a pair of key defining variables into one key. Service Id or operator are not enough by themselves
        // as another service might use the operator address at the same time frame
        // operator occupies first 160 bits
        uint256 operatorService = uint256(uint160(operator));
        // serviceId occupies next 32 bits
        operatorService |= serviceId << 160;
        uint256 nonce = mapOperatorUnbondNonces[operatorService];
        // Get the unbond message hash
        bytes32 msgHash = getUnbondHash(operator, serviceOwner, serviceId, deadline, nonce);

        // Verify the signed hash against the operator address
        _verifySignedHash(operator, msgHash, signature);

        // Update corresponding nonce value
        nonce++;
        mapOperatorUnbondNonces[operatorService] = nonce;

        // Withdraw the ERC20 token if the service is token-based
        uint256 tokenRefund = IServiceTokenUtility(serviceRegistryTokenUtility).unbondTokenRefund(operator, serviceId);

        // Unbond with the regular service registry routine
        (success, refund) = IService(serviceRegistry).unbond(operator, serviceId);

        // If the service is token-based, the actual refund is provided via the serviceRegistryTokenUtility contract
        if (tokenRefund > 0) {
            refund = tokenRefund;
        }

        emit UnbondWithSignatureExecuted(operator, serviceId, refund);

        _locked = 1;
    }

    /// @dev Registers agent instances of the operator by the service owner via the operator's pre-signed message hash.
    /// @notice Note that this function accounts for the operator being the EOA, or the contract that has an
    ///         isValidSignature() function that would confirm the message hash was signed by the operator contract.
    ///         isValidSignature() receives the 65 signature bytes with the operator address in r, so a wallet that
    ///         reads owner signatures from them, such as Safe, uses the pre-approved hash path; see _verifySignedHash().
    ///         Otherwise, if the message hash has been pre-approved, the corresponding map of hashes is going to
    ///         to verify the signed hash, similar to the Safe contract implementation in v1.3.0:
    ///         https://github.com/safe-global/safe-contracts/blob/186a21a74b327f17fc41217a927dea7064f74604/contracts/GnosisSafe.sol#L240-L304
    ///         Also note that only the service owner is able to call this function on behalf of the operator.
    /// @param operator Operator address that signed the register agents message hash.
    /// @param serviceId Service Id.
    /// @param agentInstances Agent instance addresses.
    /// @param agentIds Canonical Ids of the agent correspondent to the agent instance.
    /// @param bondToken Bond token the operator signed for: the service ERC20 token, or ETH_TOKEN_ADDRESS for a
    ///        native-token service.
    /// @param maxBond Maximum total bond the operator signed for, summed over the listed agent instances.
    /// @param deadline Last timestamp at which the signed message can be used.
    /// @param signature Signature byte array associated with operator message hash signature.
    /// @return success True, if the the function executed successfully.
    function registerAgentsWithSignature(
        address operator,
        uint256 serviceId,
        address[] memory agentInstances,
        uint32[] memory agentIds,
        address bondToken,
        uint256 maxBond,
        uint256 deadline,
        bytes memory signature
    ) external payable returns (bool success) {
        // Reentrancy guard
        if (_locked > 1) {
            revert ReentrancyGuard();
        }
        _locked = 2;

        // Check the signed message deadline
        _checkDeadline(deadline);

        // Check the service owner and the operator signature, and advance the operator nonce
        _verifyRegisterAgentsSignature(
            operator, serviceId, agentInstances, agentIds, bondToken, maxBond, deadline, signature
        );

        // Check the signed bond terms before any bond is collected
        _checkBondTerms(serviceId, agentInstances, agentIds, bondToken, maxBond);

        // Record the actual ERC20 bond
        bool isTokenSecured =
            IServiceTokenUtility(serviceRegistryTokenUtility).registerAgentsTokenDeposit(operator, serviceId, agentIds);

        // Register agent instances in a main ServiceRegistry contract
        if (isTokenSecured) {
            // Get total bond wrapper value
            uint256 totalBond = agentInstances.length * BOND_WRAPPER;
            // Check for msg.value
            if (msg.value != totalBond) {
                revert IncorrectAgentBondingValue(msg.value, totalBond, serviceId);
            }

            // If the service Id is based on the ERC20 token, the provided value to the standard registration is 1
            // multiplied by the number of agent instances
            success = IService(serviceRegistry).registerAgents{value: totalBond}(
                operator, serviceId, agentInstances, agentIds
            );
        } else {
            // Otherwise follow the standard msg.value path
            success = IService(serviceRegistry).registerAgents{value: msg.value}(
                operator, serviceId, agentInstances, agentIds
            );
        }

        emit RegisterAgentsWithSignatureExecuted(operator, serviceId, agentInstances, agentIds);

        _locked = 1;
    }

    /// @dev Checks the service owner and the operator signature over the register agents message, and advances
    ///      the operator register agents nonce.
    /// @param operator Operator address that signed the register agents message hash.
    /// @param serviceId Service Id.
    /// @param agentInstances Agent instance addresses.
    /// @param agentIds Canonical Ids of the agent correspondent to the agent instance.
    /// @param bondToken Signed bond token.
    /// @param maxBond Signed maximum total bond.
    /// @param deadline Signed deadline.
    /// @param signature Signature byte array associated with operator message hash signature.
    function _verifyRegisterAgentsSignature(
        address operator,
        uint256 serviceId,
        address[] memory agentInstances,
        uint32[] memory agentIds,
        address bondToken,
        uint256 maxBond,
        uint256 deadline,
        bytes memory signature
    ) internal {
        // Check the service owner
        address serviceOwner = IERC721(serviceRegistry).ownerOf(serviceId);
        if (msg.sender != serviceOwner) {
            revert OwnerOnly(msg.sender, serviceOwner);
        }

        // Get the (operator | serviceId) nonce for the registerAgents message
        // Push a pair of key defining variables into one key. Service Id or operator are not enough by themselves
        // as another service might use the operator address at the same time frame
        // operator occupies first 160 bits
        uint256 operatorService = uint256(uint160(operator));
        // serviceId occupies next 32 bits as serviceId is limited by the 2^32 - 1 value
        operatorService |= serviceId << 160;
        uint256 nonce = mapOperatorRegisterAgentsNonces[operatorService];

        // Reject reserved agent instance addresses
        _checkAgentInstances(agentInstances);

        // Get register agents message hash
        bytes32 msgHash = getRegisterAgentsHash(
            operator, serviceOwner, serviceId, agentInstances, agentIds, bondToken, maxBond, deadline, nonce
        );

        // Verify the signed hash against the operator address
        _verifySignedHash(operator, msgHash, signature);

        // Update corresponding nonce value
        nonce++;
        mapOperatorRegisterAgentsNonces[operatorService] = nonce;
    }

    /// @dev Checks the signed bond terms against the bond the registration charges.
    /// @notice The bond is read per listed agent instance from the same records the registration charges: the token
    ///         utility agent bond for a token-secured service, the registry agent bond for a native-token service.
    ///         A repeated agent Id therefore counts once per listed instance.
    /// @param serviceId Service Id.
    /// @param agentInstances Agent instance addresses.
    /// @param agentIds Canonical Ids of the agent correspondent to the agent instance.
    /// @param bondToken Signed bond token.
    /// @param maxBond Signed maximum total bond.
    function _checkBondTerms(
        uint256 serviceId,
        address[] memory agentInstances,
        uint32[] memory agentIds,
        address bondToken,
        uint256 maxBond
    ) internal view {
        // One agent Id per listed agent instance
        uint256 numAgentInstances = agentInstances.length;
        if (numAgentInstances != agentIds.length) {
            revert WrongArrayLength(numAgentInstances, agentIds.length);
        }

        // The token utility records no token for a native-token service: externally that is ETH_TOKEN_ADDRESS
        (address token, ) = IServiceTokenUtility(serviceRegistryTokenUtility).mapServiceIdTokenDeposit(serviceId);
        bool isTokenSecured = (token != address(0));
        if (!isTokenSecured) {
            token = ETH_TOKEN_ADDRESS;
        }
        if (bondToken != token) {
            revert WrongBondToken(bondToken, token);
        }

        uint256 totalBond;
        for (uint256 i = 0; i < numAgentInstances; ++i) {
            // serviceId occupies first 32 bits, agentId gets the next 32 bits
            uint256 serviceAgent = serviceId | (uint256(agentIds[i]) << 32);
            if (isTokenSecured) {
                totalBond += IServiceTokenUtility(serviceRegistryTokenUtility).mapServiceAndAgentIdAgentBond(serviceAgent);
            } else {
                (, uint96 bond) = IServiceRegistry(serviceRegistry).mapServiceAndAgentIdAgentParams(serviceAgent);
                totalBond += bond;
            }
        }
        if (totalBond > maxBond) {
            revert BondExceedsMax(totalBond, maxBond);
        }
    }

    /// @dev Adds the service agent Ids omitted from a new agent Id set, with zero parameters, so that the registry
    ///      removes them.
    /// @notice The provided set is validated first, so that the additions cannot mask an invalid set: it must be
    ///         non-empty, match agentParams in length and be strictly ascending. The provided entries are kept in their
    ///         order, including any explicit zero-slot removals; only agent Ids of the current set that are absent
    ///         from it are inserted, at their sorted position. Linear in the size of both sets.
    /// @param serviceId Service Id.
    /// @param agentIds New canonical agent Ids, strictly ascending.
    /// @param agentParams New agent parameters, one per agent Id.
    /// @return mergedAgentIds Agent Ids including the omitted ones.
    /// @return mergedAgentParams Agent parameters including zero parameters for the omitted agent Ids.
    function _addOmittedAgentIds(
        uint256 serviceId,
        uint32[] memory agentIds,
        IService.AgentParams[] memory agentParams
    ) internal view returns (uint32[] memory mergedAgentIds, IService.AgentParams[] memory mergedAgentParams) {
        uint256 numAgentIds = agentIds.length;
        if (numAgentIds == 0 || numAgentIds != agentParams.length) {
            revert WrongArrayLength(numAgentIds, agentParams.length);
        }
        uint256 lastId;
        for (uint256 i = 0; i < numAgentIds; ++i) {
            if (agentIds[i] <= lastId) {
                revert WrongAgentId(agentIds[i]);
            }
            lastId = agentIds[i];
        }

        // Current agent Ids, strictly ascending as recorded by the registry
        uint32[] memory currentAgentIds = IServiceRegistry(serviceRegistry).getService(serviceId).agentIds;
        uint256 numCurrent = currentAgentIds.length;

        // Count the current agent Ids absent from the new set
        uint256 numOmitted;
        uint256 j;
        for (uint256 i = 0; i < numCurrent; ++i) {
            while (j < numAgentIds && agentIds[j] < currentAgentIds[i]) {
                ++j;
            }
            if (j == numAgentIds || agentIds[j] != currentAgentIds[i]) {
                ++numOmitted;
            }
        }
        if (numOmitted == 0) {
            return (agentIds, agentParams);
        }

        // Merge both sets in ascending order, the omitted agent Ids with zero parameters
        mergedAgentIds = new uint32[](numAgentIds + numOmitted);
        mergedAgentParams = new IService.AgentParams[](numAgentIds + numOmitted);
        uint256 k;
        j = 0;
        for (uint256 i = 0; i < numCurrent; ++i) {
            while (j < numAgentIds && agentIds[j] < currentAgentIds[i]) {
                mergedAgentIds[k] = agentIds[j];
                mergedAgentParams[k] = agentParams[j];
                ++j;
                ++k;
            }
            if (j == numAgentIds || agentIds[j] != currentAgentIds[i]) {
                // Omitted: zero slots and bond
                mergedAgentIds[k] = currentAgentIds[i];
                ++k;
            }
        }
        while (j < numAgentIds) {
            mergedAgentIds[k] = agentIds[j];
            mergedAgentParams[k] = agentParams[j];
            ++j;
            ++k;
        }
    }
}
