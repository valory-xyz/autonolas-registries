// Sources flattened with hardhat v2.22.3 https://hardhat.org

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// Staking instance interface
interface IStaking {
    /// @dev Gets rewards per second in a service staking contract.
    /// @return Rewards per second.
    function rewardsPerSecond() external view returns (uint256);

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

    // OLAS token address
    address public immutable olas;

    // Rewards per second limit
    uint256 public rewardsPerSecondLimit;
    // Contract owner address
    address public owner;
    // Flag to check for the implementation address whitelisting status
    bool public implementationsCheck;
    
    // Mapping implementation address => whitelisting status
    mapping(address => bool) public mapImplementations;

    /// @dev StakingVerifier constructor.
    /// @param _olas OLAS token address.
    /// @param _rewardsPerSecondLimit Rewards per second limit.
    constructor(address _olas, uint256 _rewardsPerSecondLimit) {
        // Zero address check
        if (_olas == address(0)) {
            revert ZeroAddress();
        }

        // Zero value check
        if (_rewardsPerSecondLimit == 0) {
            revert ZeroValue();
        }

        owner = msg.sender;
        olas = _olas;
        rewardsPerSecondLimit = _rewardsPerSecondLimit;
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
        uint256 rewardsPerSecond = IStaking(instance).rewardsPerSecond();
        if (rewardsPerSecond > rewardsPerSecondLimit) {
            return false;
        }

        address token = IStaking(instance).stakingToken();
        if (token != olas) {
            return false;
        }

        return true;
    }

    /// @dev Changes staking parameter limits.
    /// @param _rewardsPerSecondLimit Rewards per second limit.
    function changeStakingLimits(uint256 _rewardsPerSecondLimit) external {
        // Check the contract ownership
        if (owner != msg.sender) {
            revert OwnerOnly(owner, msg.sender);
        }

        // Zero value check
        if (_rewardsPerSecondLimit == 0) {
            revert ZeroValue();
        }

        rewardsPerSecondLimit = _rewardsPerSecondLimit;
    }
}
