// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IServiceStaking{
    function rewardsPerSecond() external view returns (uint256);
}

/// @title ServiceStakingVerifier - Smart contract for service staking contracts verification
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingVerifier {
    uint256 public rewardsPerSecondLimit;

    constructor(uint256 _rewardsPerSecondLimit) {
        rewardsPerSecondLimit = _rewardsPerSecondLimit;
    }

    /// @notice This function can revert.
    function verifyImplementation(address implementation) external view returns (bool success){
        // Check for the ERC165 compatibility with ServiceStakingBase
        if ((IERC165(implementation).supportsInterface(0x01ffc9a7) && // ERC165 Interface ID for ERC165
            IERC165(implementation).supportsInterface(0xa694fc3a) && // bytes4(keccak256("stake(uint256)"))
            IERC165(implementation).supportsInterface(0x2e17de78) && // bytes4(keccak256("unstake(uint256)"))
            IERC165(implementation).supportsInterface(0xc2c4c5c1) && // bytes4(keccak256("checkpoint()"))
            IERC165(implementation).supportsInterface(0x78e06136) && // bytes4(keccak256("calculateServiceStakingReward(uint256)"))
            IERC165(implementation).supportsInterface(0x82a8ea58) // bytes4(keccak256("getServiceInfo(uint256)"))
            )) {
            success = true;
        }
    }

    // TODO try / catch? As it must not revert
    /// @notice This function must NOT revert.
    function verifyInstance(address instance) external view returns (bool success) {
        // Check for the staking parameters
        uint256 rewardsPerSecond = IServiceStaking(instance).rewardsPerSecond();
        if (rewardsPerSecondLimit >= rewardsPerSecond) {
            success = true;
        }
    }
}