// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

// Conditional Tokens interface
interface IConditionalTokens {
    function mergePositions(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external returns (uint256);

    /// @notice Get the balance of multiple account/token pairs
    /// @param _owners The addresses of the token holders
    /// @param _ids    ID of the tokens
    /// @return The _owner's balance of the token types requested (i.e. balance for each (owner, id) pair)
    function balanceOfBatch(address[] calldata _owners, uint256[] calldata _ids) external view returns (uint256[] memory);
}

/// @dev Zero value when it has to be different from zero.
error ZeroValue();

/// @dev Call has failed.
/// @param retData Returned data.
error CallFailed(bytes retData);

/// @title ConditionalLib - Allows to get the required amount and call the mergePositions function.
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author Andrey Lebedev - <andrey.lebedev@valory.xyz>
contract ConditionalLib {
    /// @dev Calculate balances amount and call the mergePositions function.
    /// @param collateralToken Collateral token.
    /// @param owners The addresses of the token holders.
    /// @param ids Id of the tokens.
    /// @param conditionalTokens Conditional Tokens contract address.
    function execMergePositions(
        address collateralToken,
        address[] calldata owners,
        uint256[] calldata ids,
        address conditionalTokens,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition
    ) external {
        // Get the balances
        uint256[] memory balances = IConditionalTokens(conditionalTokens).balanceOfBatch(owners, ids);

        // Get the accumulated amount based on balances
        uint256 amount;
        for (uint256 i = 0; i < balances.length; ++i) {
            amount += balances[i];
        }

        // Check for the zero amount
        if (amount == 0) {
            revert ZeroValue();
        }

        // Form a call data for the mergePositions from the Conditional Tokens contract
        bytes memory data = abi.encodeWithSignature("mergePositions(address,bytes32,bytes32,uint256[],uint256)",
            collateralToken, parentCollectionId, conditionId, partition, amount);

        // Call the Conditional Tokens contract
        (bool success, bytes memory retData) = conditionalTokens.call(data);

        /// Check for the successful call
        if (!success) {
            revert CallFailed(retData);
        }
    }
}
