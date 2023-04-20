// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @dev Provided zero address.
error ZeroAddress();

/// @dev Wrong length of two arrays.
/// @param numValues1 Number of values in a first array.
/// @param numValues2 Number of values in a second array.
error WrongArrayLength(uint256 numValues1, uint256 numValues2);

/// @title OperatorWhitelist - Smart contract for whitelisting operator addresses
/// @author AL
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
contract OperatorWhitelist {
    event OperatorsWhitelistUpdated(address indexed serviceOwner, address[] operators, bool[] statuses);
    event OperatorsWhitelistCheckSet(address indexed serviceOwner);

    // Mapping service owner address => need to check for the operator address whitelisting status
    mapping(address => bool) public mapServiceOwnerOperatorsCheck;
    // Mapping service owner address => whitelisting status
    mapping(address => mapping(address => bool)) public mapServiceOwnerOperators;

    /// @dev Controls the necessity of checking operator whitelisting statuses.
    /// @param status True if the whitelisting check is needed.
    function setOperatorsCheck(bool status) external {
        mapServiceOwnerOperatorsCheck[msg.sender] = status;
    }
    
    /// @dev Controls operators whitelisting statuses.
    /// @notice Operator is considered whitelisted if its status is set to true.
    /// @param operators Set of operator addresses.
    /// @param statuses Set of whitelisting statuses.
    function setOperatorsStatuses(address[] memory operators, bool[] memory statuses) external {
        // Check for the array length
        if (operators.length != statuses.length) {
            revert WrongArrayLength(operators.length, statuses.length);
        }

        // Check that the arrays are not empty
        if (operators.length == 0) {
            revert WrongArrayLength(0, 1);
        }

        bool atLeastOneOperatorWhitelisted;
        // Set operators whitelisting status
        for (uint256 i = 0; i < operators.length; ++i) {
            // Check for the zero address
            if (operators[i] == address(0)) {
                revert ZeroAddress();
            }
            // Set the operator whitelisting status
            mapServiceOwnerOperators[msg.sender][operators[i]] = statuses[i];

            // Check if at least one operator is whitelisted
            if (statuses[i]) {
                atLeastOneOperatorWhitelisted = true;
            }
        }
        emit OperatorsWhitelistUpdated(msg.sender, operators, statuses);

        // Set the operator whitelisting check, if at least one of the operators are whitelisted
        if (atLeastOneOperatorWhitelisted) {
            mapServiceOwnerOperatorsCheck[msg.sender] = true;
            emit OperatorsWhitelistCheckSet(msg.sender);
        }
    }

    /// @dev Gets operator whitelisting status.
    /// @param serviceOwner Service owner address.
    /// @param operator Operator address.
    /// @return status Whitelisting status.
    function isOperatorWhitelisted(address serviceOwner, address operator) external view returns (bool status) {
        status = true;
        // Check the operator whitelisting status, if applied by the service owner
        if (serviceOwner != operator && mapServiceOwnerOperatorsCheck[serviceOwner]) {
            status = mapServiceOwnerOperators[serviceOwner][operator];
        }
    }
}
