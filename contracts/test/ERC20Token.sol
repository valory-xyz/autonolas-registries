// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";

/// @title ERC20Token - Smart contract for mocking the minimum OLAS token functionality
contract ERC20Token is ERC20 {

    constructor() ERC20("ERC20 generic token", "ERC20Token", 18) {
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}