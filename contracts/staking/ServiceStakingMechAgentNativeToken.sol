// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ServiceStakingNativeToken} from "./ServiceStakingNativeToken.sol";
import {MechAgentMod} from "./MechAgentMod.sol";

/// @title ServiceStakingMechAgentNativeToken - Smart contract for staking a service with the service interacting with
///            AI agent mech and having a native network token as the deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingMechAgentNativeToken is ServiceStakingNativeToken, MechAgentMod {
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

    function _getLivenessRatio() internal view override returns (uint256) {
        return livenessRatio;
    }

    function _getAgentMech() internal view override returns (address) {
        return agentMech;
    }

    /// @dev Gets service multisig nonces.
    /// @param multisig Service multisig address.
    /// @return nonces Set of one or more service multisig nonces depending on implementation.
    function _getMultisigNonces(address multisig) internal view override(ServiceStakingNativeToken, MechAgentMod) returns (uint256[] memory nonces) {
        nonces = super._getMultisigNonces(multisig);
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
    ) internal view override(ServiceStakingNativeToken, MechAgentMod) returns (bool ratioPass)
    {
        ratioPass = super._isRatioPass(curNonces, lastNonces, ts);
    }
}