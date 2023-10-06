// Sources flattened with hardhat v2.17.1 https://hardhat.org

// SPDX-License-Identifier: MIT

// File contracts/interfaces/IErrorsRegistries.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.21;

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


// File lib/solmate/src/tokens/ERC721.sol
/// @notice Modern, minimalist, and gas efficient ERC-721 implementation.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event Approval(address indexed owner, address indexed spender, uint256 indexed id);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                         METADATA STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    function tokenURI(uint256 id) public view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                      ERC721 BALANCE/OWNER STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) internal _ownerOf;

    mapping(address => uint256) internal _balanceOf;

    function ownerOf(uint256 id) public view virtual returns (address owner) {
        require((owner = _ownerOf[id]) != address(0), "NOT_MINTED");
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        require(owner != address(0), "ZERO_ADDRESS");

        return _balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) public getApproved;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 id) public virtual {
        address owner = _ownerOf[id];

        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "NOT_AUTHORIZED");

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        require(from == _ownerOf[id], "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(
            msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[id],
            "NOT_AUTHORIZED"
        );

        // Underflow of the sender's balance is impossible because we check for
        // ownership above and the recipient's balance can't realistically overflow.
        unchecked {
            _balanceOf[from]--;

            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        delete getApproved[id];

        emit Transfer(from, to, id);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "") ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata data
    ) public virtual {
        transferFrom(from, to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data) ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 id) internal virtual {
        require(to != address(0), "INVALID_RECIPIENT");

        require(_ownerOf[id] == address(0), "ALREADY_MINTED");

        // Counter overflow is incredibly unrealistic.
        unchecked {
            _balanceOf[to]++;
        }

        _ownerOf[id] = to;

        emit Transfer(address(0), to, id);
    }

    function _burn(uint256 id) internal virtual {
        address owner = _ownerOf[id];

        require(owner != address(0), "NOT_MINTED");

        // Ownership check above ensures no underflow.
        unchecked {
            _balanceOf[owner]--;
        }

        delete _ownerOf[id];

        delete getApproved[id];

        emit Transfer(owner, address(0), id);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL SAFE MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _safeMint(address to, uint256 id) internal virtual {
        _mint(to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, "") ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }

    function _safeMint(
        address to,
        uint256 id,
        bytes memory data
    ) internal virtual {
        _mint(to, id);

        if (to.code.length != 0)
            require(
                ERC721TokenReceiver(to).onERC721Received(msg.sender, address(0), id, data) ==
                    ERC721TokenReceiver.onERC721Received.selector,
                "UNSAFE_RECIPIENT"
            );
    }
}

/// @notice A generic interface for a contract which properly accepts ERC721 tokens.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract ERC721TokenReceiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC721TokenReceiver.onERC721Received.selector;
    }
}


// File contracts/staking/ServiceStakingBase.sol
// Multisig interface
interface IMultisig {
    /// @dev Gets the multisig nonce.
    /// @return Multisig nonce.
    function nonce() external view returns (uint256);
}

// Service Registry interface
interface IService {
    enum UnitType {
        Component,
        Agent
    }

    /// @dev Transfers the service that was previously approved to this contract address.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param id Service Id.
    function safeTransferFrom(address from, address to, uint256 id) external;

    /// @dev Gets service parameters from the map of services.
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

    /// @dev Gets the full set of linearized components / canonical agent Ids for a specified service.
    /// @notice The service must be / have been deployed in order to get the actual data.
    /// @param serviceId Service Id.
    /// @return numUnitIds Number of component / agent Ids.
    /// @return unitIds Set of component / agent Ids.
    function getUnitIdsOfService(UnitType unitType, uint256 serviceId) external view
        returns (uint256 numUnitIds, uint32[] memory unitIds);
}

/// @dev No rewards are available in the contract.
error NoRewardsAvailable();

/// @dev Maximum number of staking services is reached.
/// @param maxNumServices Maximum number of staking services.
error MaxNumServicesReached(uint256 maxNumServices);

/// @dev Received lower value than the expected one.
/// @param provided Provided value is lower.
/// @param expected Expected value.
error LowerThan(uint256 provided, uint256 expected);

/// @dev Required service configuration is wrong.
/// @param serviceId Service Id.
error WrongServiceConfiguration(uint256 serviceId);

/// @dev Service is not staked.
/// @param serviceId Service Id.
error ServiceNotStaked(uint256 serviceId);

// Service Info struct
struct ServiceInfo {
    // Service multisig address
    address multisig;
    // Service owner
    address owner;
    // Service multisig nonce
    uint256 nonce;
    // Staking start time
    uint256 tsStart;
    // Accumulated service staking reward
    uint256 reward;
}

/// @title ServiceStakingBase - Base abstract smart contract for staking a service by its owner
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract ServiceStakingBase is ERC721TokenReceiver, IErrorsRegistries {
    struct StakingParams {
        // Maximum number of staking services
        uint256 maxNumServices;
        // Rewards per second
        uint256 rewardsPerSecond;
        // Minimum service staking deposit value required for staking
        uint256 minStakingDeposit;
        // Liveness period
        uint256 livenessPeriod;
        // Liveness ratio in the format of 1e18
        uint256 livenessRatio;
        // Number of agent instances in the service
        uint256 numAgentInstances;
        // Optional agent Ids requirement
        uint256[] agentIds;
        // Optional service multisig threshold requirement
        uint256 threshold;
        // Optional service configuration hash requirement
        bytes32 configHash;
    }

    event ServiceStaked(uint256 indexed serviceId, address indexed owner, address indexed multisig, uint256 nonce);
    event Checkpoint(uint256 availableRewards, uint256 numServices);
    event ServiceUnstaked(uint256 indexed serviceId, address indexed owner, address indexed multisig, uint256 nonce,
        uint256 reward, uint256 tsStart);
    event Deposit(address indexed sender, uint256 amount, uint256 balance, uint256 availableRewards);
    event Withdraw(address indexed to, uint256 amount);

    // Contract version
    string public constant VERSION = "0.1.0";
    // Maximum number of staking services
    uint256 public immutable maxNumServices;
    // Rewards per second
    uint256 public immutable rewardsPerSecond;
    // Minimum service staking deposit value required for staking
    uint256 public immutable minStakingDeposit;
    // Liveness period
    uint256 public immutable livenessPeriod;
    // Liveness ratio in the format of 1e18
    uint256 public immutable livenessRatio;
    // Number of agent instances in the service
    uint256 public immutable numAgentInstances;
    // Optional service multisig threshold requirement
    uint256 public immutable threshold;
    // Optional service configuration hash requirement
    bytes32 public immutable configHash;
    // ServiceRegistry contract address
    address public immutable serviceRegistry;

    // Token / ETH balance
    uint256 public balance;
    // Token / ETH available rewards
    uint256 public availableRewards;
    // Timestamp of the last checkpoint
    uint256 public tsCheckpoint;
    // Optional agent Ids requirement
    uint256[] public agentIds;
    // Mapping of serviceId => staking service info
    mapping (uint256 => ServiceInfo) public mapServiceInfo;
    // Set of currently staking serviceIds
    uint256[] public setServiceIds;

    /// @dev ServiceStakingBase constructor.
    /// @param _stakingParams Service staking parameters.
    /// @param _serviceRegistry ServiceRegistry contract address.
    constructor(StakingParams memory _stakingParams, address _serviceRegistry) {
        // Initial checks
        if (_stakingParams.maxNumServices == 0 || _stakingParams.rewardsPerSecond == 0 ||
            _stakingParams.minStakingDeposit == 0 || _stakingParams.livenessPeriod == 0 ||
            _stakingParams.livenessRatio == 0 || _stakingParams.numAgentInstances == 0) {
            revert ZeroValue();
        }
        if (_serviceRegistry == address(0)) {
            revert ZeroAddress();
        }

        // Assign all the required parameters
        maxNumServices = _stakingParams.maxNumServices;
        rewardsPerSecond = _stakingParams.rewardsPerSecond;
        minStakingDeposit = _stakingParams.minStakingDeposit;
        livenessPeriod = _stakingParams.livenessPeriod;
        livenessRatio = _stakingParams.livenessRatio;
        numAgentInstances = _stakingParams.numAgentInstances;
        serviceRegistry = _serviceRegistry;

        // Assign optional parameters
        threshold = _stakingParams.threshold;
        configHash = _stakingParams.configHash;

        // Assign agent Ids, if applicable
        uint256 size = _stakingParams.agentIds.length;
        uint256 agentId;
        if (size > 0) {
            for (uint256 i = 0; i < size; ++i) {
                // Agent Ids must be unique and in ascending order
                if (_stakingParams.agentIds[i] <= agentId) {
                    revert WrongAgentId(_stakingParams.agentIds[i]);
                }
                agentId = _stakingParams.agentIds[i];
                agentIds.push(agentId);
            }
        }

        // Set the checkpoint timestamp to be the deployment one
        tsCheckpoint = block.timestamp;
    }

    /// @dev Checks token / ETH staking deposit.
    /// @param stakingDeposit Staking deposit.
    function _checkTokenStakingDeposit(uint256, uint256 stakingDeposit) internal view virtual {
        // The staking deposit derived from a security deposit value must be greater or equal to the minimum defined one
        if (stakingDeposit < minStakingDeposit) {
            revert LowerThan(stakingDeposit, minStakingDeposit);
        }
    }

    /// @dev Withdraws the reward amount to a service owner.
    /// @param to Address to.
    /// @param amount Amount to withdraw.
    function _withdraw(address to, uint256 amount) internal virtual;

    /// @dev Stakes the service.
    /// @param serviceId Service Id.
    function stake(uint256 serviceId) external {
        // Check if there available rewards
        if (availableRewards == 0) {
            revert NoRewardsAvailable();
        }

        // Check for the maximum number of staking services
        uint256 numStakingServices = setServiceIds.length;
        if (numStakingServices == maxNumServices) {
            revert MaxNumServicesReached(maxNumServices);
        }

        // Check the service conditions for staking
        (uint96 stakingDeposit, address multisig, bytes32 hash, uint256 agentThreshold, uint256 maxNumInstances, , uint8 state) =
            IService(serviceRegistry).mapServices(serviceId);

        // Check the number of agent instances
        if (numAgentInstances != maxNumInstances) {
            revert WrongServiceConfiguration(serviceId);
        }

        // Check the configuration hash, if applicable
        if (configHash != bytes32(0) && configHash != hash) {
            revert WrongServiceConfiguration(serviceId);
        }
        // Check the threshold, if applicable
        if (threshold > 0 && threshold != agentThreshold) {
            revert WrongServiceConfiguration(serviceId);
        }
        // The service must be deployed
        if (state != 4) {
            revert WrongServiceState(state, serviceId);
        }
        // Check the agent Ids requirement, if applicable
        uint256 size = agentIds.length;
        if (size > 0) {
            (uint256 numAgents, uint32[] memory agents) =
                IService(serviceRegistry).getUnitIdsOfService(IService.UnitType.Agent, serviceId);

            if (size != numAgents) {
                revert WrongServiceConfiguration(serviceId);
            }
            for (uint256 i = 0; i < numAgents; ++i) {
                if (agentIds[i] != agents[i]) {
                    revert WrongAgentId(agentIds[i]);
                }
            }
        }

        // Check service staking deposit and token, if applicable
        _checkTokenStakingDeposit(serviceId, stakingDeposit);

        // Transfer the service for staking
        IService(serviceRegistry).safeTransferFrom(msg.sender, address(this), serviceId);

        // ServiceInfo struct will be an empty one since otherwise the safeTransferFrom above would fail
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        sInfo.multisig = multisig;
        sInfo.owner = msg.sender;
        uint256 nonce = IMultisig(multisig).nonce();
        sInfo.nonce = nonce;
        sInfo.tsStart = block.timestamp;

        // Add the service Id to the set of staked services
        setServiceIds.push(serviceId);

        emit ServiceStaked(serviceId, msg.sender, multisig, nonce);
    }

    /// @dev Calculates staking rewards for all services at current timestamp.
    /// @param lastAvailableRewards Available amount of rewards.
    /// @param numServices Number of services eligible for the reward that passed the liveness check.
    /// @param totalRewards Total calculated rewards.
    /// @param eligibleServiceIds Service Ids eligible for rewards.
    /// @param eligibleServiceRewards Corresponding rewards for eligible service Ids.
    /// @param serviceIds All the staking service Ids.
    /// @param serviceNonces Current service nonces.
    function _calculateStakingRewards() internal view returns (
        uint256 lastAvailableRewards,
        uint256 numServices,
        uint256 totalRewards,
        uint256[] memory eligibleServiceIds,
        uint256[] memory eligibleServiceRewards,
        uint256[] memory serviceIds,
        uint256[] memory serviceNonces
    )
    {
        // Get the service Ids set length
        uint256 size = setServiceIds.length;
        serviceIds = new uint256[](size);

        // Record service Ids
        for (uint256 i = 0; i < size; ++i) {
            // Get current service Id
            serviceIds[i] = setServiceIds[i];
        }

        // Check the last checkpoint timestamp and the liveness period
        uint256 tsCheckpointLast = tsCheckpoint;
        if (block.timestamp - tsCheckpointLast >= livenessPeriod) {
            // Get available rewards and last checkpoint timestamp
            lastAvailableRewards = availableRewards;

            // If available rewards are not zero, proceed with staking calculation
            if (lastAvailableRewards > 0) {
                // Get necessary arrays
                eligibleServiceIds = new uint256[](size);
                eligibleServiceRewards = new uint256[](size);
                serviceNonces = new uint256[](size);

                // Calculate each staked service reward eligibility
                for (uint256 i = 0; i < size; ++i) {
                    // Get the service info
                    ServiceInfo storage curInfo = mapServiceInfo[serviceIds[i]];

                    // Get current service multisig nonce
                    serviceNonces[i] = IMultisig(curInfo.multisig).nonce();

                    // Calculate the liveness nonce ratio
                    // Get the last service checkpoint: staking start time or the global checkpoint timestamp
                    uint256 serviceCheckpoint = tsCheckpointLast;
                    uint256 ts = curInfo.tsStart;
                    // Adjust the service checkpoint time if the service was staking less than the current staking period
                    if (ts > serviceCheckpoint) {
                        serviceCheckpoint = ts;
                    }

                    // Calculate the liveness ratio in 1e18 value
                    // This subtraction is always positive or zero, as the last checkpoint can be at most block.timestamp
                    ts = block.timestamp - serviceCheckpoint;
                    uint256 ratio;
                    // If the checkpoint was called in the exact same block, the ratio is zero
                    if (ts > 0) {
                        ratio = ((serviceNonces[i] - curInfo.nonce) * 1e18) / ts;
                    }

                    // Record the reward for the service if it has provided enough transactions
                    if (ratio >= livenessRatio) {
                        // Calculate the reward up until now and record its value for the corresponding service
                        uint256 reward = rewardsPerSecond * ts;
                        totalRewards += reward;
                        eligibleServiceRewards[numServices] = reward;
                        eligibleServiceIds[numServices] = serviceIds[i];
                        ++numServices;
                    }
                }
            }
        }
    }

    /// @dev Checkpoint to allocate rewards up until a current time.
    /// @return All staking service Ids.
    /// @return All staking updated nonces.
    /// @return Number of reward-eligible staking services during current checkpoint period.
    /// @return Eligible service Ids.
    /// @return Eligible service rewards.
    /// @return success True, if the checkpoint was successful.
    function checkpoint() public returns (
        uint256[] memory,
        uint256[] memory,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bool success
    )
    {
        // Calculate staking rewards
        (uint256 lastAvailableRewards, uint256 numServices, uint256 totalRewards,
            uint256[] memory eligibleServiceIds, uint256[] memory eligibleServiceRewards,
            uint256[] memory serviceIds, uint256[] memory serviceNonces) = _calculateStakingRewards();

        // If there are eligible services, proceed with staking calculation and update rewards
        if (numServices > 0) {
            // If total allocated rewards are not enough, adjust the reward value
            if (totalRewards > lastAvailableRewards) {
                // Traverse all the eligible services and adjust their rewards proportional to leftovers
                uint256 updatedReward;
                uint256 updatedTotalRewards;
                uint256 curServiceId;
                for (uint256 i = 1; i < numServices; ++i) {
                    // Calculate the updated reward
                    updatedReward = (eligibleServiceRewards[i] * lastAvailableRewards) / totalRewards;
                    // Add to the total updated reward
                    updatedTotalRewards += updatedReward;
                    // Add reward to the overall service reward
                    curServiceId = eligibleServiceIds[i];
                    mapServiceInfo[curServiceId].reward += updatedReward;
                }

                // Process the first service in the set
                updatedReward = (eligibleServiceRewards[0] * lastAvailableRewards) / totalRewards;
                updatedTotalRewards += updatedReward;
                curServiceId = eligibleServiceIds[0];
                // If the reward adjustment happened to have small leftovers, add it to the first service
                if (lastAvailableRewards > updatedTotalRewards) {
                    updatedReward += lastAvailableRewards - updatedTotalRewards;
                }
                // Add reward to the overall service reward
                mapServiceInfo[curServiceId].reward += updatedReward;
                // Set available rewards to zero
                lastAvailableRewards = 0;
            } else {
                // Traverse all the eligible services and add to their rewards
                for (uint256 i = 0; i < numServices; ++i) {
                    // Add reward to the service overall reward
                    uint256 curServiceId = eligibleServiceIds[i];
                    mapServiceInfo[curServiceId].reward += eligibleServiceRewards[i];
                }

                // Adjust available rewards
                // TODO: Fuzz this such that totalRewards is never bigger than lastAvailableRewards
                lastAvailableRewards -= totalRewards;
            }

            // Update the storage value of available rewards
            availableRewards = lastAvailableRewards;
        }

        // If service nonces were updated, then the checkpoint takes place, otherwise only service Ids are returned
        if (serviceNonces.length > 0) {
            // Updated current service nonces
            for (uint256 i = 0; i < serviceIds.length; ++i) {
                // Get the current service Id
                uint256 curServiceId = serviceIds[i];
                mapServiceInfo[curServiceId].nonce = serviceNonces[i];
            }

            // Record the current timestamp such that next calculations start from this point of time
            tsCheckpoint = block.timestamp;

            success = true;

            emit Checkpoint(lastAvailableRewards, numServices);
        }

        return (serviceIds, serviceNonces, numServices, eligibleServiceIds, eligibleServiceRewards, success);
    }

    /// @dev Unstakes the service.
    /// @param serviceId Service Id.
    function unstake(uint256 serviceId) external {
        ServiceInfo memory sInfo = mapServiceInfo[serviceId];
        // Check for the service ownership
        if (msg.sender != sInfo.owner) {
            revert OwnerOnly(msg.sender, sInfo.owner);
        }

        // Call the checkpoint
        (uint256[] memory serviceIds, , , , , ) = checkpoint();

        // Get the service index in the set of services
        // The index must always exist as the service is currently staked, otherwise it has no record in the map
        uint256 idx;
        for (; idx < serviceIds.length; ++idx) {
            if (serviceIds[idx] == serviceId) {
                break;
            }
        }

        // Transfer the service back to the owner
        IService(serviceRegistry).safeTransferFrom(address(this), msg.sender, serviceId);

        // Transfer accumulated rewards to the service multisig
        if (sInfo.reward > 0) {
            _withdraw(sInfo.multisig, sInfo.reward);
        }

        // Clear all the data about the unstaked service
        // Delete the service info struct
        delete mapServiceInfo[serviceId];

        // Update the set of staked service Ids
        setServiceIds[idx] = setServiceIds[setServiceIds.length - 1];
        setServiceIds.pop();

        emit ServiceUnstaked(serviceId, msg.sender, sInfo.multisig, sInfo.nonce, sInfo.reward, sInfo.tsStart);
    }

    /// @dev Calculates service staking reward at current timestamp.
    /// @param serviceId Service Id.
    /// @return reward Service reward.
    function calculateServiceStakingReward(uint256 serviceId) external view returns (uint256 reward) {
        // Get current service reward
        ServiceInfo memory sInfo = mapServiceInfo[serviceId];
        reward = sInfo.reward;

        // Check if the service is staked
        if (sInfo.tsStart == 0) {
            revert ServiceNotStaked(serviceId);
        }

        // Calculate overall staking rewards
        (uint256 lastAvailableRewards, uint256 numServices, uint256 totalRewards, uint256[] memory eligibleServiceIds,
            uint256[] memory eligibleServiceRewards, , ) = _calculateStakingRewards();

        // If there are eligible services, proceed with staking calculation and update rewards for the service Id
        if (numServices > 0) {
            // Get the service index in the eligible service set and calculate its latest reward
            for (uint256 i = 0; i < eligibleServiceIds.length; ++i) {
                if (eligibleServiceIds[i] == serviceId) {
                    // If total allocated rewards are not enough, adjust the reward value
                    if (totalRewards > lastAvailableRewards) {
                        reward += (eligibleServiceRewards[i] * lastAvailableRewards) / totalRewards;
                    } else {
                        reward += eligibleServiceRewards[i];
                    }
                    break;
                }
            }
        }
    }
}


// File contracts/interfaces/IToken.sol
/// @dev Generic token interface for IERC20 and IERC721 tokens.
interface IToken {
    /// @dev Gets the amount of tokens owned by a specified account.
    /// @param account Account address.
    /// @return Amount of tokens owned.
    function balanceOf(address account) external view returns (uint256);

    /// @dev Gets the owner of the token Id.
    /// @param tokenId Token Id.
    /// @return Token Id owner address.
    function ownerOf(uint256 tokenId) external view returns (address);

    /// @dev Gets the total amount of tokens stored by the contract.
    /// @return Amount of tokens.
    function totalSupply() external view returns (uint256);

    /// @dev Transfers the token amount.
    /// @param to Address to transfer to.
    /// @param amount The amount to transfer.
    /// @return True if the function execution is successful.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @dev Gets remaining number of tokens that the `spender` can transfer on behalf of `owner`.
    /// @param owner Token owner.
    /// @param spender Account address that is able to transfer tokens on behalf of the owner.
    /// @return Token amount allowed to be transferred.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
    /// @param spender Account address that will be able to transfer tokens on behalf of the caller.
    /// @param amount Token amount.
    /// @return True if the function execution is successful.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Transfers the token amount that was previously approved up until the maximum allowance.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param amount Amount to transfer to.
    /// @return True if the function execution is successful.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    /// @dev Gets the number of token decimals.
    /// @return Number of token decimals.
    function decimals() external view returns (uint8);
}


// File contracts/utils/SafeTransferLib.sol
/// @dev Failure of a token transfer.
/// @param token Address of a token.
/// @param from Address `from`.
/// @param to Address `to`.
/// @param value Value.
error TokenTransferFailed(address token, address from, address to, uint256 value);

/// @dev The implementation is fully copied from the audited MIT-licensed solmate code repository:
///      https://github.com/transmissions11/solmate/blob/v7/src/utils/SafeTransferLib.sol
///      The original library imports the `ERC20` abstract token contract, and thus embeds all that contract
///      related code that is not needed. In this version, `ERC20` is swapped with the `address` representation.
///      Also, the final `require` statement is modified with this contract own `revert` statement.
library SafeTransferLib {
    /// @dev Safe token transferFrom implementation.
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
            revert TokenTransferFailed(token, from, to, amount);
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
            revert TokenTransferFailed(token, address(this), to, amount);
        }
    }
}


// File contracts/staking/ServiceStakingToken.sol
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


/// @title ServiceStakingToken - Smart contract for staking a service by its owner when the service has an ERC20 token as the deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingToken is ServiceStakingBase {
    // ServiceRegistryTokenUtility address
    address public immutable serviceRegistryTokenUtility;
    // Security token address for staking corresponding to the service deposit token
    address public immutable stakingToken;

    /// @dev ServiceStakingToken constructor.
    /// @param _stakingParams Service staking parameters.
    /// @param _serviceRegistry ServiceRegistry contract address.
    /// @param _serviceRegistryTokenUtility ServiceRegistryTokenUtility contract address.
    /// @param _stakingToken Address of a service staking token.
    constructor(
        StakingParams memory _stakingParams,
        address _serviceRegistry,
        address _serviceRegistryTokenUtility,
        address _stakingToken
    )
        ServiceStakingBase(_stakingParams, _serviceRegistry)
    {
        // Initial checks
        if (_stakingToken == address(0) || _serviceRegistryTokenUtility == address(0)) {
            revert ZeroAddress();
        }

        stakingToken = _stakingToken;
        serviceRegistryTokenUtility = _serviceRegistryTokenUtility;
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
