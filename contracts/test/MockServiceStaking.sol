// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title MockServiceStaking - Smart contract for mocking some of the staking service functionality
contract MockServiceStaking {
    uint256 public serviceId = 2;

    function getNextServiceId() external view returns (uint256) {
        return serviceId + 1;
    }
}
