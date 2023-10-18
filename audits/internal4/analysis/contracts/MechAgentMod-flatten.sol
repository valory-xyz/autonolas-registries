// Sources flattened with hardhat v2.17.1 https://hardhat.org

// SPDX-License-Identifier: MIT

// File contracts/staking/MechAgentMod.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.21;

// Multisig interface
interface IMultisig {
    /// @dev Gets the multisig nonce.
    /// @return Multisig nonce.
    function nonce() external view returns (uint256);
}

// AgentMech interface
interface IAgentMech {
    /// @dev Gets the requests count for a specific account.
    /// @param account Account address.
    /// @return requestsCount Requests count.
    function getRequestsCount(address account) external view returns (uint256 requestsCount);
}

/// @dev Provided zero mech agent address.
error ZeroMechAgentAddress();

/// @title MechAgentMod - Abstract smart contract for AI agent mech staking modification
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
abstract contract MechAgentMod {
    // AI agent mech contract address.
    address public immutable agentMech;

    /// @dev MechAgentMod constructor.
    /// @param _agentMech AI agent mech contract address.
    constructor(address _agentMech) {
        if (_agentMech == address(0)) {
            revert ZeroMechAgentAddress();
        }
        agentMech = _agentMech;
    }

    /// @dev Gets service multisig nonces.
    /// @param multisig Service multisig address.
    /// @return nonces Set of one or more service multisig nonces depending on implementation.
    function _getMultisigNonces(address multisig) internal view virtual returns (uint256[] memory nonces) {
        nonces = new uint256[](2);
        nonces[0] = IMultisig(multisig).nonce();
        nonces[1] = IAgentMech(agentMech).getRequestsCount(multisig);
    }

    /// @dev Gets the liveness ratio.
    /// @return Liveness ratio.
    function _getLivenessRatio() internal view virtual returns (uint256);

    /// @dev Checks if the service multisig liveness ratio passes the defined liveness threshold.
    /// @notice The formula for calculating the ratio is the following:
    ///         currentNonces - [service multisig nonce at time now (block.timestamp), requests count at time now];
    ///         lastNonces - [service multisig nonce at the previous checkpoint or staking time (tsStart), requests count at time tsStart];
    ///         Requests count difference must be at least two times smaller than the nonce difference:
    ///         (currentNonces[1] - lastNonces[1]) <= (currentNonces[0] - lastNonces[0]) / 2;
    ///         ratio = (currentNonces[1] - lastNonce[1]) / (block.timestamp - tsStart).
    ///         Liveness ratio for mech requests count:
    ///             ratio >= counterRequestsRatio, where counterRequestsRatio = livenessRatio / 2,
    ///         since there is at least one tx for sending a request to AgentMech, and another tx for its subsequent execution.
    /// @param curNonces Current service multisig nonces.
    /// @param lastNonces Last service multisig nonces.
    /// @param ts Time difference between current and last timestamps.
    /// @return ratioPass True, if the liveness ratio passes the check.
    function _isRatioPass(
        uint256[] memory curNonces,
        uint256[] memory lastNonces,
        uint256 ts
    ) internal view virtual returns (bool ratioPass)
    {
        uint256 diffNonces = curNonces[0] - lastNonces[0];
        uint256 diffRequestsCounts = curNonces[1] - lastNonces[1];

        // Sanity checks for requests counts difference to be at least half of the nonces difference
        if (diffRequestsCounts <= diffNonces / 2) {
            uint256 ratio = (diffRequestsCounts * 1e18) / ts;
            ratioPass = (ratio >= _getLivenessRatio() / 2);
        }
    }
}
