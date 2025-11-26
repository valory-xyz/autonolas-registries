// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Proxy initialization failed.
error InitializationFailed();

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero Value.
error ZeroValue();

/*
* This is a proxy contract for agent classification.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Special agent classification implementation address slot is produced by hashing the "PROXY_AGENT_CLASSIFICATION"
* string in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title AgentClassificationProxy - Smart contract for agent classification proxy
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract AgentClassificationProxy {
    // Agent Classification proxy address slot
    // keccak256("PROXY_AGENT_CLASSIFICATION") = "0x3156bf5f7008ff6ac7744ba73e3b52cb758b203026fe9cebdc25e74b8f5ff199"
    bytes32 public constant PROXY_AGENT_CLASSIFICATION = 0x3156bf5f7008ff6ac7744ba73e3b52cb758b203026fe9cebdc25e74b8f5ff199;

    /// @dev AgentClassificationProxy constructor.
    /// @param agentClassification Agent Classification implementation address.
    /// @param agentClassificationData Agent Classification initialization data.
    constructor(address agentClassification, bytes memory agentClassificationData) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (agentClassification == address(0)) {
            revert ZeroAddress();
        }

        // Check for the zero data
        if (agentClassificationData.length == 0) {
            revert ZeroValue();
        }

        assembly {
            sstore(PROXY_AGENT_CLASSIFICATION, agentClassification)
        }
        // Initialize proxy storage
        (bool success, ) = agentClassification.delegatecall(agentClassificationData);
        if (!success) {
            revert InitializationFailed();
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external {
        // solhint-disable-next-line avoid-low-level-calls
        assembly {
            let agentClassification := sload(PROXY_AGENT_CLASSIFICATION)
            // Otherwise continue with the delegatecall to implementation
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), agentClassification, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if eq(success, 0) {
                revert(0, returndatasize())
            }
            return(0, returndatasize())
        }
    }

    /// @dev Gets implementation address.
    /// @return implementation Implementation address.
    function getImplementation() external view returns (address implementation) {
        // solhint-disable-next-line avoid-low-level-calls
        assembly {
            implementation := sload(PROXY_AGENT_CLASSIFICATION)
        }
    }
}
