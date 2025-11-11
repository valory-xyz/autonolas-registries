// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Proxy initialization failed.
error InitializationFailed();

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero Value.
error ZeroValue();

/*
* This is a proxy contract for identity registry bridger.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Specialidentity registry bridger implementation address slot is produced by hashing the "PROXY_IDENTITY_REGISTRY_BRIDGER"
* string in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title IdentityRegistryBridgerProxy - Smart contract for identity registry bridger proxy
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract IdentityRegistryBridgerProxy {
    // Identity Registry Bridger proxy address slot
    // keccak256("PROXY_IDENTITY_REGISTRY_BRIDGER") = "0x03684189c8fb7a536ac4dbd4b7ad063c37db21bcd0f9c51fe45a4eb16359c165"
    bytes32 public constant PROXY_IDENTITY_REGISTRY_BRIDGER = 0x03684189c8fb7a536ac4dbd4b7ad063c37db21bcd0f9c51fe45a4eb16359c165;

    /// @dev IdentityRegistryBridgerProxy constructor.
    /// @param identityRegistryBridger Identity Registry Bridger implementation address.
    /// @param identityRegistryBridgerData Identity Registry Bridger initialization data.
    constructor(address identityRegistryBridger, bytes memory identityRegistryBridgerData) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (identityRegistryBridger == address(0)) {
            revert ZeroAddress();
        }

        // Check for the zero data
        if (identityRegistryBridgerData.length == 0) {
            revert ZeroValue();
        }

        assembly {
            sstore(PROXY_IDENTITY_REGISTRY_BRIDGER, identityRegistryBridger)
        }
        // Initialize proxy liquidity manager storage
        (bool success, ) = identityRegistryBridger.delegatecall(identityRegistryBridgerData);
        if (!success) {
            revert InitializationFailed();
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external {
        assembly {
            let identityRegistryBridger := sload(PROXY_IDENTITY_REGISTRY_BRIDGER)
            // Otherwise continue with the delegatecall to the liquidity manager implementation
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), identityRegistryBridger, 0, calldatasize(), 0, 0)
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
            implementation := sload(PROXY_IDENTITY_REGISTRY_BRIDGER)
        }
    }
}
