//Spdx-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {
        _mint(msg.sender, 10_000_000 * 10**6); // 10M USDC with 6 decimals
    }

    function decimals() public view virtual override returns (uint8) {
        return 6; // USDC has 6 decimals
    }
}

