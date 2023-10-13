// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ServiceStakingNativeToken} from "./ServiceStakingNativeToken.sol";

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

/// @title ServiceStakingMechAgentNativeToken - Smart contract for staking a service with the service interacting wiht
///            AI agent mech and having a native network token as the deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingMechAgentNativeToken is ServiceStakingNativeToken {
    // AI agent mech contract address.
    address public immutable agentMech;

    /// @dev ServiceStakingNativeToken constructor.
    /// @param _stakingParams Service staking parameters.
    /// @param _serviceRegistry ServiceRegistry contract address.
    /// @param _proxyHash Approved multisig proxy hash.
    /// @param _agentMech AI agent mech contract address.
    constructor(StakingParams memory _stakingParams, address _serviceRegistry, bytes32 _proxyHash, address _agentMech)
        ServiceStakingNativeToken(_stakingParams, 2, _serviceRegistry, _proxyHash)
    {
        if (_agentMech == address(0)) {
            revert ZeroAddress();
        }
        agentMech = _agentMech;
    }

    /// @dev Gets service multisig nonces.
    /// @param multisig Service multisig address.
    /// @return nonces Set of one or more service multisig nonces depending on implementation.
    function _getMultisigNonces(address multisig) internal view override returns (uint256[] memory nonces) {
        nonces = new uint256[](numNonces);
        nonces[0] = IMultisig(multisig).nonce();
        nonces[1] = IAgentMech(agentMech).getRequestsCount(multisig);
    }

    /// @dev Checks if the service multisig liveness ratio passes the defined liveness threshold.
    /// @param curNonces Current service multisig nonces.
    /// @param lastNonces Last service multisig nonces.
    /// @param ts Time difference between current and last timestamps.
    /// @return ratioPass True, if the liveness ratio passes the check.
    function _isRatioPass(
        uint256[] memory curNonces,
        uint256[] memory lastNonces,
        uint256 ts
    ) internal view override returns (bool ratioPass)
    {
        uint256 diffNonces = curNonces[0] - lastNonces[0];
        uint256 diffRequestsCounts = curNonces[1] - lastNonces[1];

        // Sanity checks for requests counts difference to be at least half of the nonces difference
        if (diffRequestsCounts <= diffNonces / 2) {
            uint256 ratio = (diffRequestsCounts * 1e18) / ts;
            ratioPass = (ratio >= livenessRatio / 2);
        }
    }
}