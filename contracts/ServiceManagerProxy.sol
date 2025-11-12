// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Proxy initialization failed.
error InitializationFailed();

/// @dev Zero address.
error ZeroAddress();

/// @dev Zero Value.
error ZeroValue();

/*
* This is a proxy contract for service manager.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Special service manager implementation address slot is produced by hashing the "PROXY_SERVICE_MANAGER"
* string in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title ServiceManagerProxy - Smart contract for service manager proxy
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ServiceManagerProxy {
    // Service Manager proxy address slot
    // keccak256("PROXY_SERVICE_MANAGER") = "0xe39e69948a448ce9239ad71b908b6c5b46225f86ffa735b25a8cd64080315855"
    bytes32 public constant PROXY_SERVICE_MANAGER = 0xe39e69948a448ce9239ad71b908b6c5b46225f86ffa735b25a8cd64080315855;

    /// @dev ServiceManagerProxy constructor.
    /// @param serviceManager Service Manager implementation address.
    /// @param serviceManagerData Service Manager initialization data.
    constructor(address serviceManager, bytes memory serviceManagerData) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (serviceManager == address(0)) {
            revert ZeroAddress();
        }

        // Check for the zero data
        if (serviceManagerData.length == 0) {
            revert ZeroValue();
        }

        assembly {
            sstore(PROXY_SERVICE_MANAGER, serviceManager)
        }
        // Initialize proxy storage
        (bool success, ) = serviceManager.delegatecall(serviceManagerData);
        if (!success) {
            revert InitializationFailed();
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external {
        // solhint-disable-next-line avoid-low-level-calls
        assembly {
            let serviceManager := sload(PROXY_SERVICE_MANAGER)
            // Otherwise continue with the delegatecall to implementation
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), serviceManager, 0, calldatasize(), 0, 0)
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
            implementation := sload(PROXY_SERVICE_MANAGER)
        }
    }
}