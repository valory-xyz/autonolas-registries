// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

error WrongDataLength();
error ExecFailed(address target, uint256 value, bytes payload);

/// @title MockTimelock - Mock of the Timelock contract
/// @author Aleksandr Kuperman - <aleksandr.kuperman@valory.xyz>
/// @author AL
contract MockTimelock {

    receive() external payable {}

    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads
    ) external payable {
        if (targets.length != values.length || targets.length != payloads.length) {
            revert WrongDataLength();
        }

        for (uint256 i = 0; i < targets.length; ++i) {
            address target = targets[i];
            uint256 value = values[i];
            bytes calldata payload = payloads[i];
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = target.call{value: value}(payload);
            if (!success) {
                revert ExecFailed(target, value, payload);
            }
        }
    }

    function execute(address target, uint256 value, bytes calldata payload) external payable {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = target.call{value: value}(payload);
        if (!success) {
            revert ExecFailed(target, value, payload);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}