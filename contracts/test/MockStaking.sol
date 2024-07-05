// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @title MockStaking - Smart contract for mocking some of the staking service functionality
contract MockStaking {
    uint256 public serviceId;
    uint256 public rewardsPerSecond;
    uint256 public timeForEmissions;
    uint256 public maxNumServices;
    uint256 public emissionsAmount;
    address public token;
    address public serviceRegistry;
    address public serviceRegistryTokenUtility;
    bool public nativeToken;

    function initialize(address _token, address _serviceRegistry, address _serviceRegistryTokenUtility) external {
        serviceId = 2;
        rewardsPerSecond = 0.0001 ether;
        timeForEmissions = 100;
        maxNumServices = 10;
        emissionsAmount = rewardsPerSecond * maxNumServices * timeForEmissions;
        token = _token;
        serviceRegistry = _serviceRegistry;
        if (_serviceRegistryTokenUtility == address(0)) {
            nativeToken = true;
        } else {
            serviceRegistryTokenUtility = _serviceRegistryTokenUtility;
        }
    }

    function setNativeToken(bool isNative) external {
        nativeToken = isNative;
    }

    function stakingToken() external view returns (address) {
        if (nativeToken) {
            revert();
        }
        return token;
    }

    function setNumServices(uint256 numServices) external {
        maxNumServices = numServices;
        emissionsAmount = rewardsPerSecond * maxNumServices * timeForEmissions;
    }

    function setTimeForEmissions(uint256 time) external {
        timeForEmissions = time;
        emissionsAmount = rewardsPerSecond * maxNumServices * timeForEmissions;
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
