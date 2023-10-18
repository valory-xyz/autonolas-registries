// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @title MockAgentMech - Smart contract for mocking AgentMech partial functionality.
contract MockAgentMech {
    event requestsCountIncreased(address indexed account, uint256 requestsCount);

    // Map of requests counts for corresponding addresses
    mapping (address => uint256) public mapRequestsCounts;

    function increaseRequestsCount(address account) external {
        mapRequestsCounts[account]++;
        emit requestsCountIncreased(account, mapRequestsCounts[account]);
    }

    function getRequestsCount(address account) external view returns (uint256 requestsCount) {
        requestsCount = mapRequestsCounts[account];
    }

}
