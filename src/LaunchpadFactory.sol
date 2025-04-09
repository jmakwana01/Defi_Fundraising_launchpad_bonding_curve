// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../src/Fundraising.sol";
import "../src/FundraisingToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LaunchpadFactory {
    address public implementation;
    address public usdc;
    address public uniswapRouter;

    constructor(address _implementation, address _usdc, address _uniswapRouter) {
        implementation = _implementation;
        usdc = _usdc;
        uniswapRouter = _uniswapRouter;
    }

    function createFundraising(
        address creator,
        uint256 F,
        string memory name,
        string memory symbol
    ) external returns (address) {
        // Deploy token with factory as temporary owner
        FundraisingToken token = new FundraisingToken(name, symbol, address(this));
        ERC1967Proxy proxy = new ERC1967Proxy(
            implementation,
            abi.encodeWithSelector(
                Fundraising.initialize.selector,
                creator,
                msg.sender, // platform
                address(token),
                usdc,
                uniswapRouter,
                F
            )
        );
        // Transfer token ownership to the proxy
        token.transferOwnership(address(proxy));
        return address(proxy);
    }
}