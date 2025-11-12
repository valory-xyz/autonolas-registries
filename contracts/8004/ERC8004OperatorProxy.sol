// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Proxy initialization failed.
    error InitializationFailed();

/// @dev Zero address.
    error ZeroAddress();

/// @dev Zero Value.
    error ZeroValue();

/*
* This is a proxy contract for ERC-8004 operator.
* Proxy implementation is created based on the Universal Upgradeable Proxy Standard (UUPS) EIP-1822.
* The implementation address must be located in a unique storage slot of the proxy contract.
* The upgrade logic must be located in the implementation contract.
* Special ERC-8004 operator implementation address slot is produced by hashing the "PROXY_ERC_8004_OPERATOR"
* string in order to make the slot unique.
* The fallback() implementation for all the delegatecall-s is inspired by the Gnosis Safe set of contracts.
*/

/// @title ERC8004OperatorProxy - Smart contract for ERC-8004 operator proxy
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
/// @author Mariapia Moscatiello - <mariapia.moscatiello@valory.xyz>
contract ERC8004OperatorProxy {
    // ERC-8004 Operator proxy address slot
    // keccak256("PROXY_ERC_8004_OPERATOR") = "0xa9f38cc44a40040970dc2e16fc2bd2246d1a0f51a63d37e96d48630d0ff81a38"
    bytes32 public constant PROXY_ERC_8004_OPERATOR = 0xa9f38cc44a40040970dc2e16fc2bd2246d1a0f51a63d37e96d48630d0ff81a38;

    /// @dev ERC8004OperatorProxy constructor.
    /// @param erc8004Operator ERC-8004 Operator implementation address.
    /// @param erc8004OperatorData ERC-8004 Operator initialization data.
    constructor(address erc8004Operator, bytes memory erc8004OperatorData) {
        // Check for the zero address, since the delegatecall works even with the zero one
        if (erc8004Operator == address(0)) {
            revert ZeroAddress();
        }

        // Check for the zero data
        if (erc8004OperatorData.length == 0) {
            revert ZeroValue();
        }

        assembly {
            sstore(PROXY_ERC_8004_OPERATOR, erc8004Operator)
        }
        // Initialize proxy storage
        (bool success, ) = erc8004Operator.delegatecall(erc8004OperatorData);
        if (!success) {
            revert InitializationFailed();
        }
    }

    /// @dev Delegatecall to all the incoming data.
    fallback() external {
        // solhint-disable-next-line avoid-low-level-calls
        assembly {
            let erc8004Operator := sload(PROXY_ERC_8004_OPERATOR)
            // Otherwise continue with the delegatecall to implementation
            calldatacopy(0, 0, calldatasize())
            let success := delegatecall(gas(), erc8004Operator, 0, calldatasize(), 0, 0)
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
            implementation := sload(PROXY_ERC_8004_OPERATOR)
        }
    }
}