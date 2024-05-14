// Sources flattened with hardhat v2.22.3 https://hardhat.org

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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


// File contracts/staking/StakingBase.sol
// Staking Activity Checker interface
interface IActivityChecker {
    /// @dev Gets service multisig nonces.
    /// @param multisig Service multisig address.
    /// @return nonces Set of a single service multisig nonce.
    function getMultisigNonces(address multisig) external view returns (uint256[] memory nonces);

    /// @dev Checks if the service multisig liveness ratio passes the defined liveness threshold.
    /// @notice The formula for calculating the ratio is the following:
    ///         currentNonce - service multisig nonce at time now (block.timestamp);
    ///         lastNonce - service multisig nonce at the previous checkpoint or staking time (tsStart);
    ///         ratio = (currentNonce - lastNonce) / (block.timestamp - tsStart).
    /// @param curNonces Current service multisig set of a single nonce.
    /// @param lastNonces Last service multisig set of a single nonce.
    /// @param ts Time difference between current and last timestamps.
    /// @return ratioPass True, if the liveness ratio passes the check.
    function isRatioPass(
        uint256[] memory curNonces,
        uint256[] memory lastNonces,
        uint256 ts
    ) external view returns (bool ratioPass);
}

// Service Registry interface
interface IService {
    enum ServiceState {
        NonExistent,
        PreRegistration,
        ActiveRegistration,
        FinishedRegistration,
        Deployed,
        TerminatedBonded
    }

    // Service agent params struct
    struct AgentParams {
        // Number of agent instances
        uint32 slots;
        // Bond per agent instance
        uint96 bond;
    }

    // Service parameters
    struct Service {
        // Registration activation deposit
        uint96 securityDeposit;
        // Multisig address for agent instances
        address multisig;
        // IPFS hashes pointing to the config metadata
        bytes32 configHash;
        // Agent instance signers threshold
        uint32 threshold;
        // Total number of agent instances
        uint32 maxNumAgentInstances;
        // Actual number of agent instances
        uint32 numAgentInstances;
        // Service state
        ServiceState state;
        // Canonical agent Ids for the service
        uint32[] agentIds;
    }

    /// @dev Transfers the service that was previously approved to this contract address.
    /// @param from Account address to transfer from.
    /// @param to Account address to transfer to.
    /// @param id Service Id.
    function safeTransferFrom(address from, address to, uint256 id) external;

    /// @dev Gets the service instance.
    /// @param serviceId Service Id.
    /// @return service Corresponding Service struct.
    function getService(uint256 serviceId) external view returns (Service memory service);

    /// @dev Gets service agent parameters: number of agent instances (slots) and a bond amount.
    /// @param serviceId Service Id.
    /// @return numAgentIds Number of canonical agent Ids in the service.
    /// @return agentParams Set of agent parameters for each canonical agent Id.
    function getAgentParams(uint256 serviceId) external view
        returns (uint256 numAgentIds, AgentParams[] memory agentParams);
}

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev The deployed activity checker must be a contract.
/// @param activityChecker Activity checker address.
error ContractOnly(address activityChecker);

/// @dev Agent Id is not correctly provided for the current routine.
/// @param agentId Component Id.
error WrongAgentId(uint256 agentId);

/// @dev Wrong state of a service.
/// @param state Service state.
/// @param serviceId Service Id.
error WrongServiceState(uint256 state, uint256 serviceId);

/// @dev Multisig is not whitelisted.
/// @param multisig Address of a multisig implementation.
error UnauthorizedMultisig(address multisig);

/// @dev The contract is already initialized.
error AlreadyInitialized();

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

/// @dev Service is not unstaked.
/// @param serviceId Service Id.
error ServiceNotUnstaked(uint256 serviceId);

/// @dev Service is not found.
/// @param serviceId Service Id.
error ServiceNotFound(uint256 serviceId);

/// @dev Service was not staked a minimum required time.
/// @param serviceId Service Id.
/// @param tsProvided Time the service is staked for.
/// @param tsExpected Minimum time the service needs to be staked for.
error NotEnoughTimeStaked(uint256 serviceId, uint256 tsProvided, uint256 tsExpected);

// Service Info struct
struct ServiceInfo {
    // Service multisig address
    address multisig;
    // Service owner
    address owner;
    // Service multisig nonces
    uint256[] nonces;
    // Staking start time
    uint256 tsStart;
    // Accumulated service staking reward
    uint256 reward;
    // Accumulated inactivity that might lead to the service eviction
    uint256 inactivity;
}

/// @title StakingBase - Base abstract smart contract for staking a service by its owner
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract StakingBase is ERC721TokenReceiver {
    enum StakingState {
        Unstaked,
        Staked,
        Evicted
    }

    // Input staking parameters
    struct StakingParams {
        // Metadata staking information
        bytes32 metadataHash;
        // Maximum number of staking services
        uint256 maxNumServices;
        // Rewards per second
        uint256 rewardsPerSecond;
        // Minimum service staking deposit value required for staking
        uint256 minStakingDeposit;
        // Min number of staking periods before the service can be unstaked
        uint256 minNumStakingPeriods;
        // Max number of accumulated inactivity periods after which the service is evicted
        uint256 maxNumInactivityPeriods;
        // Liveness period
        uint256 livenessPeriod;
        // Number of agent instances in the service
        uint256 numAgentInstances;
        // Optional agent Ids requirement
        uint256[] agentIds;
        // Optional service multisig threshold requirement
        uint256 threshold;
        // Optional service configuration hash requirement
        bytes32 configHash;
        // Approved multisig proxy hash
        bytes32 proxyHash;
        // ServiceRegistry contract address
        address serviceRegistry;
        // Service activity checker address
        address activityChecker;
    }

    event ServiceStaked(uint256 epoch, uint256 indexed serviceId, address indexed owner, address indexed multisig,
        uint256[] nonces);
    event Checkpoint(uint256 indexed epoch, uint256 availableRewards, uint256[] serviceIds, uint256[] rewards,
        uint256 epochLength);
    event ServiceUnstaked(uint256 epoch, uint256 indexed serviceId, address indexed owner, address indexed multisig,
        uint256[] nonces, uint256 reward);
    event RewardClaimed(uint256 epoch, uint256 indexed serviceId, address indexed owner, address indexed multisig,
        uint256[] nonces, uint256 reward);
    event ServiceInactivityWarning(uint256 epoch, uint256 indexed serviceId, uint256 serviceInactivity);
    event ServicesEvicted(uint256 indexed epoch, uint256[] serviceIds, address[] owners, address[] multisigs,
        uint256[] serviceInactivity);
    event Deposit(address indexed sender, uint256 amount, uint256 balance, uint256 availableRewards);
    event Withdraw(address indexed to, uint256 amount);

    // Contract version
    string public constant VERSION = "0.2.0";
    // Staking parameters for initialization
    // Metadata staking information
    bytes32 public metadataHash;
    // Maximum number of staking services
    uint256 public maxNumServices;
    // Rewards per second
    uint256 public rewardsPerSecond;
    // Minimum service staking deposit value required for staking
    // The staking deposit must be always greater than 1 in order to distinguish between native and ERC20 tokens
    uint256 public minStakingDeposit;
    // Max number of accumulated inactivity periods after which the service is evicted
    uint256 public maxNumInactivityPeriods;
    // Liveness period
    uint256 public livenessPeriod;
    // Number of agent instances in the service
    uint256 public numAgentInstances;
    // Optional service multisig threshold requirement
    uint256 public threshold;
    // Optional service configuration hash requirement
    bytes32 public configHash;
    // Approved multisig proxy hash
    bytes32 public proxyHash;
    // ServiceRegistry contract address
    address public serviceRegistry;
    // Service activity checker address
    address public activityChecker;

    // The rest of state variables
    // Min staking duration
    uint256 public minStakingDuration;
    // Max allowed inactivity period
    uint256 public maxInactivityDuration;
    // Epoch counter
    uint256 public epochCounter;
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

    /// @dev StakingBase initialization.
    /// @param _stakingParams Service staking parameters.
    function _initialize(
        StakingParams memory _stakingParams
    ) internal {
        // Double initialization check
        if (serviceRegistry != address(0)) {
            revert AlreadyInitialized();
        }
        
        // Initial checks
        if (_stakingParams.metadataHash == 0 || _stakingParams.maxNumServices == 0 ||
            _stakingParams.rewardsPerSecond == 0 || _stakingParams.livenessPeriod == 0 ||
            _stakingParams.numAgentInstances == 0 || _stakingParams.minNumStakingPeriods == 0 ||
            _stakingParams.maxNumInactivityPeriods == 0) {
            revert ZeroValue();
        }

        // Check that the min number of staking periods is not smaller than the max number of inactivity periods
        // This check is necessary to avoid an attack scenario when the service is going to stake and unstake without
        // any meaningful activity and just occupy the staking slot
        if (_stakingParams.minNumStakingPeriods < _stakingParams.maxNumInactivityPeriods) {
            revert LowerThan(_stakingParams.minNumStakingPeriods, _stakingParams.maxNumInactivityPeriods);
        }

        // Check the rest of parameters
        if (_stakingParams.minStakingDeposit < 2) {
            revert LowerThan(_stakingParams.minStakingDeposit, 2);
        }
        if (_stakingParams.serviceRegistry == address(0) || _stakingParams.activityChecker == address(0)) {
            revert ZeroAddress();
        }

        // Check for the Activity Checker to be the contract
        if (_stakingParams.activityChecker.code.length == 0) {
            revert ContractOnly(_stakingParams.activityChecker);
        }

        // Assign all the required parameters
        metadataHash = _stakingParams.metadataHash;
        maxNumServices = _stakingParams.maxNumServices;
        rewardsPerSecond = _stakingParams.rewardsPerSecond;
        minStakingDeposit = _stakingParams.minStakingDeposit;
        maxNumInactivityPeriods = _stakingParams.maxNumInactivityPeriods;
        livenessPeriod = _stakingParams.livenessPeriod;
        numAgentInstances = _stakingParams.numAgentInstances;
        serviceRegistry = _stakingParams.serviceRegistry;
        activityChecker = _stakingParams.activityChecker;

        // Assign optional parameters
        threshold = _stakingParams.threshold;
        configHash = _stakingParams.configHash;

        // Assign agent Ids, if applicable
        uint256 agentId;
        for (uint256 i = 0; i < _stakingParams.agentIds.length; ++i) {
            // Agent Ids must be unique and in ascending order
            if (_stakingParams.agentIds[i] <= agentId) {
                revert WrongAgentId(_stakingParams.agentIds[i]);
            }
            agentId = _stakingParams.agentIds[i];
            agentIds.push(agentId);
        }

        // Check for the multisig proxy bytecode hash value
        if (_stakingParams.proxyHash == 0) {
            revert ZeroValue();
        }

        // Record provided multisig proxy bytecode hash
        proxyHash = _stakingParams.proxyHash;

        // Calculate min staking duration
        minStakingDuration = _stakingParams.minNumStakingPeriods * livenessPeriod;

        // Calculate max allowed inactivity duration
        maxInactivityDuration = _stakingParams.maxNumInactivityPeriods * livenessPeriod;

        // Set the checkpoint timestamp to be the deployment one
        tsCheckpoint = block.timestamp;
    }

    /// @dev Checks token / ETH staking deposit.
    /// @param serviceId Service Id.
    /// @param stakingDeposit Staking deposit.
    function _checkTokenStakingDeposit(
        uint256 serviceId,
        uint256 stakingDeposit,
        uint32[] memory
    ) internal view virtual {
        uint256 minDeposit = minStakingDeposit;

        // The staking deposit derived from a security deposit value must be greater or equal to the minimum defined one
        if (stakingDeposit < minDeposit) {
            revert LowerThan(stakingDeposit, minDeposit);
        }

        // Check agent Id bonds to be not smaller than the minimum required deposit
        (uint256 numAgentIds, IService.AgentParams[] memory agentParams) = IService(serviceRegistry).getAgentParams(serviceId);
        for (uint256 i = 0; i < numAgentIds; ++i) {
            if (agentParams[i].bond < minDeposit) {
                revert LowerThan(agentParams[i].bond, minDeposit);
            }
        }
    }

    /// @dev Withdraws the reward amount to a service owner.
    /// @param to Address to.
    /// @param amount Amount to withdraw.
    function _withdraw(address to, uint256 amount) internal virtual;

    /// @dev Stakes the service.
    /// @notice Each service must be staked for a minimum of maxInactivityDuration time, or until the funds are not zero.
    ///         maxInactivityDuration = maxNumInactivityPeriods * livenessPeriod
    /// @param serviceId Service Id.
    function stake(uint256 serviceId) external {
        // Check if there available rewards
        if (availableRewards == 0) {
            revert NoRewardsAvailable();
        }

        // Check if the evicted service has not yet unstaked
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        // tsStart being greater than zero means that the service was not yet unstaked: still staking or evicted
        if (sInfo.tsStart > 0) {
            revert ServiceNotUnstaked(serviceId);
        }

        // Check for the maximum number of staking services
        uint256 numStakingServices = setServiceIds.length;
        if (numStakingServices == maxNumServices) {
            revert MaxNumServicesReached(maxNumServices);
        }

        // Check the service conditions for staking
        IService.Service memory service = IService(serviceRegistry).getService(serviceId);

        // Check the number of agent instances
        if (numAgentInstances != service.maxNumAgentInstances) {
            revert WrongServiceConfiguration(serviceId);
        }

        // Check the configuration hash, if applicable
        if (configHash != 0 && configHash != service.configHash) {
            revert WrongServiceConfiguration(serviceId);
        }
        // Check the threshold, if applicable
        if (threshold > 0 && threshold != service.threshold) {
            revert WrongServiceConfiguration(serviceId);
        }
        // The service must be deployed
        if (service.state != IService.ServiceState.Deployed) {
            revert WrongServiceState(uint256(service.state), serviceId);
        }

        // Check that the multisig address corresponds to the authorized multisig proxy bytecode hash
        bytes32 multisigProxyHash = keccak256(service.multisig.code);
        if (proxyHash != multisigProxyHash) {
            revert UnauthorizedMultisig(service.multisig);
        }

        // Check the agent Ids requirement, if applicable
        uint256 size = agentIds.length;
        if (size > 0) {
            uint256 numAgents = service.agentIds.length;

            if (size != numAgents) {
                revert WrongServiceConfiguration(serviceId);
            }
            for (uint256 i = 0; i < numAgents; ++i) {
                // Check that the agent Ids
                if (agentIds[i] != service.agentIds[i]) {
                    revert WrongAgentId(agentIds[i]);
                }
            }
        }

        // Check service staking deposit and token, if applicable
        _checkTokenStakingDeposit(serviceId, service.securityDeposit, service.agentIds);

        // ServiceInfo struct will be an empty one since otherwise the safeTransferFrom above would fail
        sInfo.multisig = service.multisig;
        sInfo.owner = msg.sender;
        // This function might revert if it's incorrectly implemented, however this is not a protocol's responsibility
        // It is safe to revert in this place
        uint256[] memory nonces = IActivityChecker(activityChecker).getMultisigNonces(service.multisig);
        sInfo.nonces = nonces;
        sInfo.tsStart = block.timestamp;

        // Add the service Id to the set of staked services
        setServiceIds.push(serviceId);

        // Transfer the service for staking
        IService(serviceRegistry).safeTransferFrom(msg.sender, address(this), serviceId);

        emit ServiceStaked(epochCounter, serviceId, msg.sender, service.multisig, nonces);
    }

    /// @dev Checks the ratio pass based on external activity checker implementation.
    /// @param multisig Multisig address.
    /// @param lastNonces Last checked service multisig nonces.
    /// @param ts Time difference between current and last timestamps.
    /// @return ratioPass True, if the defined nonce ratio passes the check.
    /// @return currentNonces Current multisig nonces.
    function _checkRatioPass(
        address multisig,
        uint256[] memory lastNonces,
        uint256 ts
    ) internal view returns (bool ratioPass, uint256[] memory currentNonces)
    {
        // Get current service multisig nonce
        // This is a low level call since it must never revert
        (bool success, bytes memory returnData) = activityChecker.staticcall(abi.encodeWithSelector(
            IActivityChecker.getMultisigNonces.selector, multisig));

        // If the function call was successful, check the return value
        // The return data length must be the exact number of full slots
        if (success && returnData.length > 63 && (returnData.length % 32 == 0)) {
            // Parse nonces
            currentNonces = abi.decode(returnData, (uint256[]));

            // Get the ratio pass activity check
            (success, returnData) = activityChecker.staticcall(abi.encodeWithSelector(
                IActivityChecker.isRatioPass.selector, currentNonces, lastNonces, ts));

            // The return data must match the size of bool
            if (success && returnData.length == 32) {
                ratioPass = abi.decode(returnData, (bool));
            }
        }
    }

    /// @dev Calculates staking rewards for all services at current timestamp.
    /// @param lastAvailableRewards Available amount of rewards.
    /// @param numServices Number of services eligible for the reward that passed the liveness check.
    /// @param totalRewards Total calculated rewards.
    /// @param eligibleServiceIds Service Ids eligible for rewards.
    /// @param eligibleServiceRewards Corresponding rewards for eligible service Ids.
    /// @param serviceIds All the staking service Ids.
    /// @param serviceNonces Current service nonces.
    /// @param serviceInactivity Service inactivity records.
    function _calculateStakingRewards() internal view returns (
        uint256 lastAvailableRewards,
        uint256 numServices,
        uint256 totalRewards,
        uint256[] memory eligibleServiceIds,
        uint256[] memory eligibleServiceRewards,
        uint256[] memory serviceIds,
        uint256[][] memory serviceNonces,
        uint256[] memory serviceInactivity
    )
    {
        // Check the last checkpoint timestamp and the liveness period, also check for available rewards to be not zero
        uint256 tsCheckpointLast = tsCheckpoint;
        lastAvailableRewards = availableRewards;
        if (block.timestamp - tsCheckpointLast >= livenessPeriod && lastAvailableRewards > 0) {
            // Get the service Ids set length
            uint256 size = setServiceIds.length;

            // Get necessary arrays
            serviceIds = new uint256[](size);
            eligibleServiceIds = new uint256[](size);
            eligibleServiceRewards = new uint256[](size);
            serviceNonces = new uint256[][](size);
            serviceInactivity = new uint256[](size);

            // Calculate each staked service reward eligibility
            for (uint256 i = 0; i < size; ++i) {
                // Get current service Id
                serviceIds[i] = setServiceIds[i];

                // TODO Check if storage is needed
                // Get the service info
                ServiceInfo storage sInfo = mapServiceInfo[serviceIds[i]];

                // Calculate the liveness nonce ratio
                // Get the last service checkpoint: staking start time or the global checkpoint timestamp
                uint256 serviceCheckpoint = tsCheckpointLast;
                uint256 ts = sInfo.tsStart;
                // Adjust the service checkpoint time if the service was staking less than the current staking period
                if (ts > serviceCheckpoint) {
                    serviceCheckpoint = ts;
                }

                // Calculate the liveness ratio in 1e18 value
                // This subtraction is always positive or zero, as the last checkpoint is at most block.timestamp
                ts = block.timestamp - serviceCheckpoint;

                bool ratioPass;
                (ratioPass, serviceNonces[i]) = _checkRatioPass(sInfo.multisig, sInfo.nonces, ts);

                // Record the reward for the service if it has provided enough transactions
                if (ratioPass) {
                    // Calculate the reward up until now and record its value for the corresponding service
                    eligibleServiceRewards[numServices] = rewardsPerSecond * ts;
                    totalRewards += eligibleServiceRewards[numServices];
                    eligibleServiceIds[numServices] = serviceIds[i];
                    ++numServices;
                } else {
                    serviceInactivity[i] = ts;
                }
            }
        }
    }

    /// @dev Evicts services due to their extended inactivity.
    /// @param evictServiceIds Service Ids to be evicted.
    /// @param serviceInactivity Corresponding service inactivity records.
    /// @param numEvictServices Number of services to evict.
    function _evict(
        uint256[] memory evictServiceIds,
        uint256[] memory serviceInactivity,
        uint256 numEvictServices
    ) internal
    {
        // Get the total number of staked services
        // All the passed arrays have the length of the number of staked services
        uint256 totalNumServices = evictServiceIds.length;

        // Get arrays of exact sizes
        uint256[] memory serviceIds = new uint256[](numEvictServices);
        address[] memory owners = new address[](numEvictServices);
        address[] memory multisigs = new address[](numEvictServices);
        uint256[] memory inactivity = new uint256[](numEvictServices);
        uint256[] memory serviceIndexes = new uint256[](numEvictServices);

        // Fill in arrays
        uint256 sCounter;
        uint256 serviceId;
        for (uint256 i = 0; i < totalNumServices; ++i) {
            if (evictServiceIds[i] > 0) {
                serviceId = evictServiceIds[i];
                serviceIds[sCounter] = serviceId;

                ServiceInfo storage sInfo = mapServiceInfo[serviceId];
                owners[sCounter] = sInfo.owner;
                multisigs[sCounter] = sInfo.multisig;
                inactivity[sCounter] = serviceInactivity[i];
                serviceIndexes[sCounter] = i;
                sCounter++;
            }
        }

        // Evict services from the global set of staked services
        for (uint256 i = numEvictServices; i > 0; --i) {
            // Decrease the number of services
            totalNumServices--;
            // Get the evicted service index
            uint256 idx = serviceIndexes[i - 1];
            // Assign last service Id to the index that points to the evicted service Id
            setServiceIds[idx] = setServiceIds[totalNumServices];
            // Pop the last element
            setServiceIds.pop();
        }

        emit ServicesEvicted(epochCounter, serviceIds, owners, multisigs, inactivity);
    }

    /// @dev Checkpoint to allocate rewards up until a current time.
    /// @return All staking service Ids (including evicted ones within a current epoch).
    /// @return All staking updated nonces (including evicted ones within a current epoch).
    /// @return Set of reward-eligible service Ids.
    /// @return Corresponding set of reward-eligible service rewards.
    /// @return evictServiceIds Evicted service Ids.
    function checkpoint() public returns (
        uint256[] memory,
        uint256[][] memory,
        uint256[] memory,
        uint256[] memory,
        uint256[] memory evictServiceIds
    )
    {
        // Calculate staking rewards
        (uint256 lastAvailableRewards, uint256 numServices, uint256 totalRewards,
            uint256[] memory eligibleServiceIds, uint256[] memory eligibleServiceRewards,
            uint256[] memory serviceIds, uint256[][] memory serviceNonces,
            uint256[] memory serviceInactivity) = _calculateStakingRewards();

        // Get arrays for eligible service Ids and rewards of exact size
        uint256[] memory finalEligibleServiceIds;
        uint256[] memory finalEligibleServiceRewards;
        evictServiceIds = new uint256[](serviceIds.length);
        uint256 curServiceId;

        // If there are eligible services, proceed with staking calculation and update rewards
        if (numServices > 0) {
            finalEligibleServiceIds = new uint256[](numServices);
            finalEligibleServiceRewards = new uint256[](numServices);
            // If total allocated rewards are not enough, adjust the reward value
            if (totalRewards > lastAvailableRewards) {
                // Traverse all the eligible services and adjust their rewards proportional to leftovers
                uint256 updatedReward;
                uint256 updatedTotalRewards;
                for (uint256 i = 1; i < numServices; ++i) {
                    // Calculate the updated reward
                    updatedReward = (eligibleServiceRewards[i] * lastAvailableRewards) / totalRewards;
                    // Add to the total updated reward
                    updatedTotalRewards += updatedReward;
                    // Add reward to the overall service reward
                    curServiceId = eligibleServiceIds[i];
                    finalEligibleServiceIds[i] = eligibleServiceIds[i];
                    finalEligibleServiceRewards[i] = updatedReward;
                    mapServiceInfo[curServiceId].reward += updatedReward;
                }

                // Process the first service in the set
                updatedReward = (eligibleServiceRewards[0] * lastAvailableRewards) / totalRewards;
                updatedTotalRewards += updatedReward;
                curServiceId = eligibleServiceIds[0];
                finalEligibleServiceIds[0] = eligibleServiceIds[0];
                // If the reward adjustment happened to have small leftovers, add it to the first service
                if (lastAvailableRewards > updatedTotalRewards) {
                    updatedReward += lastAvailableRewards - updatedTotalRewards;
                }
                finalEligibleServiceRewards[0] = updatedReward;
                // Add reward to the overall service reward
                mapServiceInfo[curServiceId].reward += updatedReward;
                // Set available rewards to zero
                lastAvailableRewards = 0;
            } else {
                // Traverse all the eligible services and add to their rewards
                for (uint256 i = 0; i < numServices; ++i) {
                    // Add reward to the service overall reward
                    curServiceId = eligibleServiceIds[i];
                    finalEligibleServiceIds[i] = eligibleServiceIds[i];
                    finalEligibleServiceRewards[i] = eligibleServiceRewards[i];
                    mapServiceInfo[curServiceId].reward += eligibleServiceRewards[i];
                }

                // Adjust available rewards
                lastAvailableRewards -= totalRewards;
            }

            // Update the storage value of available rewards
            availableRewards = lastAvailableRewards;
        }

        // If service Ids are returned, then the checkpoint takes place
        if (serviceIds.length > 0) {
            uint256 eCounter = epochCounter;
            numServices = 0;
            // Record service inactivities and updated current service nonces
            for (uint256 i = 0; i < serviceIds.length; ++i) {
                // Get the current service Id
                curServiceId = serviceIds[i];
                // Record service nonces
                mapServiceInfo[curServiceId].nonces = serviceNonces[i];

                // Increase service inactivity if it is greater than zero
                if (serviceInactivity[i] > 0) {
                    // Get the overall continuous service inactivity
                    serviceInactivity[i] = mapServiceInfo[curServiceId].inactivity + serviceInactivity[i];
                    mapServiceInfo[curServiceId].inactivity = serviceInactivity[i];
                    // Check for the maximum allowed inactivity time
                    if (serviceInactivity[i] > maxInactivityDuration) {
                        // Evict a service if it has been inactive for more than a maximum allowed inactivity time
                        evictServiceIds[i] = curServiceId;
                        // Increase number of evicted services
                        numServices++;
                    } else {
                        emit ServiceInactivityWarning(eCounter, curServiceId, serviceInactivity[i]);
                    }
                } else {
                    // Otherwise, set it back to zero
                    mapServiceInfo[curServiceId].inactivity = 0;
                }
            }

            // Evict inactive services
            if (numServices > 0) {
                _evict(evictServiceIds, serviceInactivity, numServices);
            }

            // Record the actual epoch length
            uint256 epochLength = block.timestamp - tsCheckpoint;
            // Record the current timestamp such that next calculations start from this point of time
            tsCheckpoint = block.timestamp;

            // Increase the epoch counter
            epochCounter = eCounter + 1;

            emit Checkpoint(eCounter, lastAvailableRewards, finalEligibleServiceIds, finalEligibleServiceRewards,
                epochLength);
        }

        return (serviceIds, serviceNonces, finalEligibleServiceIds, finalEligibleServiceRewards, evictServiceIds);
    }

    /// @dev Unstakes the service.
    /// @param serviceId Service Id.
    /// @return reward Staking reward.
    function unstake(uint256 serviceId) external returns (uint256 reward) {
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        // Check for the service ownership
        if (msg.sender != sInfo.owner) {
            revert OwnerOnly(msg.sender, sInfo.owner);
        }

        // Get the staking start time
        // Note that if the service info exists, the service is staked or evicted, and thus start time is always valid
        uint256 tsStart = sInfo.tsStart;

        // Check that the service has staked long enough, or if there are no rewards left
        uint256 ts = block.timestamp - tsStart;
        if (ts <= minStakingDuration && availableRewards > 0) {
            revert NotEnoughTimeStaked(serviceId, ts, minStakingDuration);
        }

        // Call the checkpoint
        (uint256[] memory serviceIds, , , , uint256[] memory evictServiceIds) = checkpoint();

        // If the checkpoint was not successful, the serviceIds set is not returned and needs to be allocated
        if (serviceIds.length == 0) {
            serviceIds = getServiceIds();
            evictServiceIds = new uint256[](serviceIds.length);
        }

        // Get the service index in the set of services
        // The index must always exist as the service is currently staked, otherwise it has no record in the map
        uint256 idx;
        bool inSet;
        for (; idx < serviceIds.length; ++idx) {
            // Service is still in a global staking set if it is found in the services set,
            // and is not present in the evicted set
            if (evictServiceIds[idx] == serviceId) {
                break;
            } else if (serviceIds[idx] == serviceId) {
                inSet = true;
                break;
            }
        }

        // Get the unstaked service data
        reward = sInfo.reward;
        uint256[] memory nonces = sInfo.nonces;
        address multisig = sInfo.multisig;

        // Clear all the data about the unstaked service
        // Delete the service info struct
        delete mapServiceInfo[serviceId];

        // Update the set of staked service Ids
        // If the index was not found, the service was evicted and is not part of staked services set
        if (inSet) {
            setServiceIds[idx] = setServiceIds[setServiceIds.length - 1];
            setServiceIds.pop();
        }

        // Transfer the service back to the owner
        IService(serviceRegistry).safeTransferFrom(address(this), msg.sender, serviceId);

        // Transfer accumulated rewards to the service multisig
        if (reward > 0) {
            _withdraw(multisig, reward);
        }

        emit ServiceUnstaked(epochCounter, serviceId, msg.sender, multisig, nonces, reward);
    }

    /// @dev Claims rewards for the service.
    /// @param serviceId Service Id.
    /// @return reward Staking reward.
    function claim(uint256 serviceId) external returns (uint256 reward) {
        ServiceInfo storage sInfo = mapServiceInfo[serviceId];
        // Check for the service ownership
        if (msg.sender != sInfo.owner) {
            revert OwnerOnly(msg.sender, sInfo.owner);
        }

        // Call the checkpoint
        checkpoint();

        // Get the claimed service data
        reward = sInfo.reward;

        // Check for the zero reward, or for the reentrancy attack
        if (reward == 0) {
            revert ZeroValue();
        }

        // Zero the reward field
        sInfo.reward = 0;

        // Transfer accumulated rewards to the service multisig
        address multisig = sInfo.multisig;
        _withdraw(multisig, reward);

        emit RewardClaimed(epochCounter, serviceId, msg.sender, multisig, sInfo.nonces, reward);
    }

    /// @dev Calculates service staking reward during the last checkpoint period.
    /// @param serviceId Service Id.
    /// @return reward Service reward.
    function calculateStakingLastReward(uint256 serviceId) public view returns (uint256 reward) {
        // Calculate overall staking rewards
        (uint256 lastAvailableRewards, uint256 numServices, uint256 totalRewards, uint256[] memory eligibleServiceIds,
            uint256[] memory eligibleServiceRewards, , , ) = _calculateStakingRewards();

        // If there are eligible services, proceed with staking calculation and update rewards for the service Id
        for (uint256 i = 0; i < numServices; ++i) {
            // Get the service index in the eligible service set and calculate its latest reward
            if (eligibleServiceIds[i] == serviceId) {
                // If total allocated rewards are not enough, adjust the reward value
                if (totalRewards > lastAvailableRewards) {
                    reward = (eligibleServiceRewards[i] * lastAvailableRewards) / totalRewards;
                } else {
                    reward = eligibleServiceRewards[i];
                }
                break;
            }
        }
    }

    /// @dev Calculates overall service staking reward at current timestamp.
    /// @param serviceId Service Id.
    /// @return reward Service reward.
    function calculateStakingReward(uint256 serviceId) external view returns (uint256 reward) {
        // Get current service reward
        ServiceInfo memory sInfo = mapServiceInfo[serviceId];
        reward = sInfo.reward;

        // Add pending reward
        reward += calculateStakingLastReward(serviceId);
    }

    /// @dev Gets the service staking state.
    /// @param serviceId.
    /// @return stakingState Staking state of the service.
    function getStakingState(uint256 serviceId) external view returns (StakingState stakingState) {
        ServiceInfo memory sInfo = mapServiceInfo[serviceId];
        if (sInfo.inactivity > maxInactivityDuration) {
            stakingState = StakingState.Evicted;
        } else if (sInfo.tsStart > 0) {
            stakingState = StakingState.Staked;
        }
    }

    /// @dev Gets the next reward checkpoint timestamp.
    /// @return tsNext Next reward checkpoint timestamp.
    function getNextRewardCheckpointTimestamp() external view returns (uint256 tsNext) {
        // Last checkpoint timestamp plus the liveness period
        tsNext = tsCheckpoint + livenessPeriod;
    }

    /// @dev Gets staked service info.
    /// @param serviceId Service Id.
    /// @return sInfo Struct object with the corresponding service info.
    function getServiceInfo(uint256 serviceId) external view returns (ServiceInfo memory sInfo) {
        sInfo = mapServiceInfo[serviceId];
    }

    /// @dev Gets staked service Ids.
    /// @return Staked service Ids.
    function getServiceIds() public view returns (uint256[] memory) {
        return setServiceIds;
    }

    /// @dev Gets canonical agent Ids from the service configuration.
    /// @return Agent Ids.
    function getAgentIds() external view returns (uint256[] memory) {
        return agentIds;
    }
}


// File contracts/staking/StakingNativeToken.sol
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

    /// @dev Withdraws the reward amount to a service owner.
    /// @notice The balance is always greater or equal the amount, as follows from the Base contract logic.
    /// @param to Address to.
    /// @param amount Amount to withdraw.
    function _withdraw(address to, uint256 amount) internal override {
        // Update the contract balance
        balance -= amount;

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
