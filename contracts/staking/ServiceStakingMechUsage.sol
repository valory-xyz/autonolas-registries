// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ServiceStakingNativeToken} from "./ServiceStakingNativeToken.sol";
import {MechAgentMod} from "./MechAgentMod.sol";

/// @title ServiceStakingMechUsage - Smart contract for staking a service with the service interacting with
///            AI agent mech and having a native network token as the deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingMechUsage is ServiceStakingNativeToken, MechAgentMod {
    /// @dev ServiceStakingNativeToken constructor.
    /// @param _stakingParams Service staking parameters.
    /// @param _serviceRegistry ServiceRegistry contract address.
    /// @param _proxyHash Approved multisig proxy hash.
    /// @param _agentMech AI agent mech contract address.
    constructor(StakingParams memory _stakingParams, address _serviceRegistry, bytes32 _proxyHash, address _agentMech)
        ServiceStakingNativeToken(_stakingParams, _serviceRegistry, _proxyHash)
        MechAgentMod(_agentMech)
    {}

    /// @dev Gets service multisig nonces.
    /// @param multisig Service multisig address.
    /// @return nonces Set of a nonce and a requests count for the multisig.
    function _getMultisigNonces(address multisig) internal view override(ServiceStakingNativeToken, MechAgentMod) returns (uint256[] memory nonces) {
        nonces = super._getMultisigNonces(multisig);
    }

    /// @dev Gets the liveness ratio.
    /// @return Liveness ratio.
    function _getLivenessRatio() internal view override returns (uint256) {
        return livenessRatio;
    }

    /// @dev Checks if the service multisig liveness ratio passes the defined liveness threshold.
    /// @notice The formula for calculating the ratio is the following:
    ///         currentNonces - [service multisig nonce at time now (block.timestamp), requests count at time now];
    ///         lastNonces - [service multisig nonce at the previous checkpoint or staking time (tsStart), requests count at time tsStart];
    ///         Requests count difference must be smaller or equal to the nonce difference:
    ///         (currentNonces[1] - lastNonces[1]) <= (currentNonces[0] - lastNonces[0]);
    ///         ratio = (currentNonces[1] - lastNonce[1]) / (block.timestamp - tsStart),
    ///         where ratio >= livenessRatio.
    /// @param curNonces Current service multisig set of nonce and requests count.
    /// @param lastNonces Last service multisig set of nonce and requests count.
    /// @param ts Time difference between current and last timestamps.
    /// @return ratioPass True, if the liveness ratio passes the check.
    function _isRatioPass(
        uint256[] memory curNonces,
        uint256[] memory lastNonces,
        uint256 ts
    ) internal view override(ServiceStakingNativeToken, MechAgentMod) returns (bool ratioPass)
    {
        ratioPass = super._isRatioPass(curNonces, lastNonces, ts);
    }
}