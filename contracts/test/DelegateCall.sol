// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract DelegateCall {
    event SetValue(uint256 value);

    // keccak256("delegatecall.test.slot")
    bytes32 internal constant DELEGATE_CALL_SLOT = 0xa8636cd0c6eb2f8df5b1a59f8747fe760deace77ea3ee8215e95b2d8962a700e;

    function setSlotValue(uint256 value) external {
        bytes32 slot = DELEGATE_CALL_SLOT;
        // Write guard value into the guard slot
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, value)
        }
        emit SetValue(value);
    }
}