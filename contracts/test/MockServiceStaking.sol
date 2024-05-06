// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title MockServiceStaking - Smart contract for mocking some of the staking service functionality
contract MockServiceStaking {
    uint256 public serviceId;
    uint256 public rewardsPerSecond;
    address public token;

    function initialize(address _token) external {
        serviceId = 2;
        rewardsPerSecond = 0.0001 ether;
        token = _token;
    }

    function stakingToken() external view returns (address) {
        return token;
    }

    function stake(uint256) external {}

    function unstake(uint256) external {}

    function checkpoint() external {}

    function calculateServiceStakingReward(uint256) external {}

    function getServiceInfo(uint256) external {}

    function getNextServiceId() external view returns (uint256) {
        return serviceId + 1;
    }

    function changeRewardsPerSecond() external {
        rewardsPerSecond = 1 ether;
    }

    /// @dev ERC165 support interface.
    /// @param interfaceId Function selector.
    function supportsInterface(bytes4 interfaceId) external virtual view returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0xa694fc3a || // bytes4(keccak256("stake(uint256)"))
            interfaceId == 0x2e17de78 || // bytes4(keccak256("unstake(uint256)"))
            interfaceId == 0xc2c4c5c1 || // bytes4(keccak256("checkpoint()"))
            interfaceId == 0x78e06136 || // bytes4(keccak256("calculateServiceStakingReward(uint256)"))
            interfaceId == 0x82a8ea58; // bytes4(keccak256("getServiceInfo(uint256)"))
    }
}
