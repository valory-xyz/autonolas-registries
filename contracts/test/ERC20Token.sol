// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../lib/solmate/src/tokens/ERC20.sol";

/// @dev Only `manager` has a privilege, but the `sender` was provided.
/// @param sender Sender address.
/// @param manager Required sender address as a manager.
error ManagerOnly(address sender, address manager);

/// @dev Provided zero address.
error ZeroAddress();

/// @title ERC20Token - Smart contract for mocking the minimum OLAS token functionality
contract ERC20Token is ERC20 {

    constructor() ERC20("ERC20 generic token", "ERC20Token", 18) {
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}