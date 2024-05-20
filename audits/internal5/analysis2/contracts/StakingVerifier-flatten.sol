// Sources flattened with hardhat v2.22.4 https://hardhat.org

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// Staking instance interface
interface IStaking {
    /// @dev Gets rewards per second.
    /// @return Rewards per second.
    function rewardsPerSecond() external view returns (uint256);

    /// @dev Gets maximum number of services.
    /// @return Maximum number of services.
    function maxNumServices() external view returns (uint256);

    /// @dev Gets service staking token.
    /// @return Service staking token address.
    function stakingToken() external view returns (address);
}

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Provided zero value.
error ZeroValue();

/// @dev Wrong length of two arrays.
/// @param numValues1 Number of values in a first array.
/// @param numValues2 Number of values in a second array.
error WrongArrayLength(uint256 numValues1, uint256 numValues2);

/// @dev Only `owner` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param owner Required sender address as an owner.
error OwnerOnly(address sender, address owner);

/// @title StakingVerifier - Smart contract for service staking contracts verification
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract StakingVerifier {
    event OwnerUpdated(address indexed owner);
    event SetImplementationsCheck(bool setCheck);
    event ImplementationsWhitelistUpdated(address[] implementations, bool[] statuses, bool setCheck);
    event StakingLimitsUpdated(uint256 rewardsPerSecondLimit, uint256 timeForEmissionsLimit, uint256 _numServicesLimit);

    // OLAS token address
    address public immutable olas;

    // Rewards per second limit
    uint256 public rewardsPerSecondLimit;
    // Time for emissions limit
    uint256 public timeForEmissionsLimit;
    // Limit for the number of services
    uint256 public numServicesLimit;
    // Emissions per service limit
    uint256 public emissionsLimit;
    // Contract owner address
    address public owner;
    // Flag to check for the implementation address whitelisting status
    bool public implementationsCheck;
    
    // Mapping implementation address => whitelisting status
    mapping(address => bool) public mapImplementations;

    /// @dev StakingVerifier constructor.
    /// @param _olas OLAS token address.
    /// @param _rewardsPerSecondLimit Rewards per second limit.
    /// @param _timeForEmissionsLimit Time for emissions limit.
    /// @param _numServicesLimit Limit for the number of services.
    constructor(address _olas, uint256 _rewardsPerSecondLimit, uint256 _timeForEmissionsLimit,
        uint256 _numServicesLimit) {
        // Zero address check
        if (_olas == address(0)) {
            revert ZeroAddress();
        }

        // Zero values check
        if (_rewardsPerSecondLimit == 0 || _timeForEmissionsLimit == 0 || _numServicesLimit == 0) {
            revert ZeroValue();
        }

        owner = msg.sender;
        olas = _olas;
        rewardsPerSecondLimit = _rewardsPerSecondLimit;
        timeForEmissionsLimit = _timeForEmissionsLimit;
        numServicesLimit = _numServicesLimit;
    }

    /// @dev Changes the owner address.
    /// @param newOwner Address of a new owner.
    function changeOwner(address newOwner) external {
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

    /// @dev Controls the necessity of checking implementation whitelisting statuses.
    /// @param setCheck True if the whitelisting check is needed, and false otherwise.
    function setImplementationsCheck(bool setCheck) external {
        // Check the contract ownership
        if (owner != msg.sender) {
            revert OwnerOnly(owner, msg.sender);
        }

        // Set the implementations check requirement
        implementationsCheck = setCheck;
        emit SetImplementationsCheck(setCheck);
    }

    /// @dev Controls implementations whitelisting statuses.
    /// @notice Implementation is considered whitelisted if the global status is set to true.
    /// @notice Implementations check could be set to false even though (some) implementations are set to true.
    ///         This is the owner responsibility how to manage the whitelisting logic.
    /// @param implementations Set of implementation addresses.
    /// @param statuses Set of whitelisting statuses.
    /// @param setCheck True if the whitelisting check is needed, and false otherwise.
    function setImplementationsStatuses(
        address[] memory implementations,
        bool[] memory statuses,
        bool setCheck
    ) external {
        // Check the contract ownership
        if (owner != msg.sender) {
            revert OwnerOnly(owner, msg.sender);
        }

        // Check for the array length and that they are not empty
        if (implementations.length == 0 || implementations.length != statuses.length) {
            revert WrongArrayLength(implementations.length, statuses.length);
        }

        // Set the implementations address check requirement
        implementationsCheck = setCheck;

        // Set implementations whitelisting status
        for (uint256 i = 0; i < implementations.length; ++i) {
            // Check for the zero address
            if (implementations[i] == address(0)) {
                revert ZeroAddress();
            }
            
            // Set the operator whitelisting status
            mapImplementations[implementations[i]] = statuses[i];
        }

        emit ImplementationsWhitelistUpdated(implementations, statuses, setCheck);
    }

    /// @dev Verifies a service staking implementation contract.
    /// @param implementation Service staking implementation contract address.
    /// @return True, if verification is successful.
    function verifyImplementation(address implementation) external view returns (bool){
        // Check the operator whitelisting status, if the whitelisting check is set
        if (implementationsCheck) {
            return mapImplementations[implementation];
        }

        return true;
    }

    /// @dev Verifies a service staking proxy instance.
    /// @param instance Service staking proxy instance.
    /// @param implementation Service staking implementation.
    /// @return True, if verification is successful.
    function verifyInstance(address instance, address implementation) external view returns (bool) {
        // If the implementations check is true, and the implementation is not whitelisted, the verification is failed
        if (implementationsCheck && !mapImplementations[implementation]) {
            return false;
        }

        // Check for the staking parameters
        // This is a must have parameter for all staking contracts
        uint256 rewardsPerSecond = IStaking(instance).rewardsPerSecond();
        if (rewardsPerSecond > rewardsPerSecondLimit) {
            return false;
        }

        // Check for the number of services
        // This is a must have parameter for all staking contracts
        uint256 numServices = IStaking(instance).maxNumServices();
        if (numServices > numServicesLimit) {
            return false;
        }

        // Check staking token
        // This is an optional check since there could be staking contracts with native tokens
        bytes memory tokenData = abi.encodeCall(IStaking.stakingToken, ());
        (bool success, bytes memory returnData) = instance.staticcall(tokenData);

        // Check the returnData is the call was successful
        if (success) {
            // The returned size must be 32 to fit one address
            if (returnData.length == 32) {
                address token = abi.decode(returnData, (address));
                if (token != olas) {
                    return false;
                }
            } else {
                return false;
            }
        }

        // Return min(maxTime * numServices * rewardsPerSecond, maxRewards)
        return true;
    }

    /// @dev Changes staking parameter limits.
    /// @param _rewardsPerSecondLimit Rewards per second limit.
    /// @param _timeForEmissionsLimit Time for emissions limit.
    /// @param _numServicesLimit Limit for the number of services.
    function changeStakingLimits(
        uint256 _rewardsPerSecondLimit,
        uint256 _timeForEmissionsLimit,
        uint256 _numServicesLimit
    ) external {
        // Check the contract ownership
        if (owner != msg.sender) {
            revert OwnerOnly(owner, msg.sender);
        }

        // Zero values check
        if (_rewardsPerSecondLimit == 0 || _timeForEmissionsLimit == 0 || _numServicesLimit == 0) {
            revert ZeroValue();
        }

        rewardsPerSecondLimit = _rewardsPerSecondLimit;
        timeForEmissionsLimit = _timeForEmissionsLimit;
        emissionsLimit = _rewardsPerSecondLimit * _timeForEmissionsLimit * _numServicesLimit;

        emit StakingLimitsUpdated(_rewardsPerSecondLimit, _timeForEmissionsLimit, _numServicesLimit);
    }

    /// @dev Gets emissions amount limit for a specific staking proxy instance.
    /// @notice The address field is reserved for the proxy instance, if needed in the next verifier version.
    /// @return Emissions amount limit.
    function getEmissionsAmountLimit(address) external view returns (uint256) {
            return emissionsLimit;
    }
}
