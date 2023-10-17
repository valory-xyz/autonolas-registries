// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {ServiceStakingToken} from "./ServiceStakingToken.sol";
import {MechAgentMod} from "./MechAgentMod.sol";
import "hardhat/console.sol";

/// @title ServiceStakingTokenMechUsage - Smart contract for staking a service with the service interacting with
///            AI agent mech and having a custom ERC20 token as the deposit
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceStakingTokenMechUsage is ServiceStakingToken, MechAgentMod {
    /// @dev ServiceStakingNativeToken constructor.
    /// @param _stakingParams Service staking parameters.
    /// @param _serviceRegistry ServiceRegistry contract address.
    /// @param _serviceRegistryTokenUtility ServiceRegistryTokenUtility contract address.
    /// @param _stakingToken Address of a service staking token.
    /// @param _proxyHash Approved multisig proxy hash.
    /// @param _agentMech AI agent mech contract address.
    constructor(
        StakingParams memory _stakingParams,
        address _serviceRegistry,
        address _serviceRegistryTokenUtility,
        address _stakingToken,
        bytes32 _proxyHash,
        address _agentMech
    )
        ServiceStakingToken(_stakingParams, _serviceRegistry, _serviceRegistryTokenUtility, _stakingToken, _proxyHash)
        MechAgentMod(_agentMech)
    {}

    /// @dev Gets service multisig nonces.
    /// @param multisig Service multisig address.
    /// @return nonces Set of a nonce and a requests count for the multisig.
    function _getMultisigNonces(address multisig) internal view override(ServiceStakingToken, MechAgentMod) returns (uint256[] memory nonces) {
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
    ///         Requests count difference must be at least two times smaller than the nonce difference:
    ///         (currentNonces[1] - lastNonces[1]) <= (currentNonces[0] - lastNonces[0]) / 2;
    ///         ratio = (currentNonces[1] - lastNonce[1]) / (block.timestamp - tsStart).
    ///         Liveness ratio for mech requests count:
    ///             ratio >= counterRequestsRatio, where counterRequestsRatio = livenessRatio / 2,
    ///         since there is at least one tx for sending a request to AgentMech, and another tx for its subsequent execution.
    /// @param curNonces Current service multisig set of nonce and requests count.
    /// @param lastNonces Last service multisig set of nonce and requests count.
    /// @param ts Time difference between current and last timestamps.
    /// @return ratioPass True, if the liveness ratio passes the check.
    function _isRatioPass(
        uint256[] memory curNonces,
        uint256[] memory lastNonces,
        uint256 ts
    ) internal view override(ServiceStakingToken, MechAgentMod) returns (bool ratioPass)
    {
        console.log("ServiceStakingTokenMechUsage._isRatioPass");
        ratioPass = super._isRatioPass(curNonces, lastNonces, ts);
    }
}