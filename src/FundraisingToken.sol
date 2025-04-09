// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FundraisingToken is ERC20, Ownable {
    constructor(string memory name, string memory symbol, address initialOwner) 
        ERC20(name, symbol) 
        Ownable(initialOwner) 
    {
        if (initialOwner == address(0)) revert("Invalid initial owner");
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}