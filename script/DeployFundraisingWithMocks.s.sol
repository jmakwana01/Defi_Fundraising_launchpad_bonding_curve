// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../src/Fundraising.sol";
import "../src/FundraisingToken.sol";
import "../src/LaunchpadFactory.sol";
import "../src/mocks/MockUSDC.sol";
import "../src/mocks/MockUniswapRouter.sol";

contract DeployFundraisingWithMocks is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock contracts
        MockUSDC usdc = new MockUSDC();
        MockUniswapRouter uniswapRouter = new MockUniswapRouter();
        
        // Deploy the implementation contract
        Fundraising fundraisingImpl = new Fundraising();
        
        // Deploy the factory
        LaunchpadFactory factory = new LaunchpadFactory(
            address(fundraisingImpl),
            address(usdc),
            address(uniswapRouter)
        );

        console.log("MockUSDC deployed at:", address(usdc));
        console.log("MockUniswapRouter deployed at:", address(uniswapRouter));
        console.log("Fundraising Implementation deployed at:", address(fundraisingImpl));
        console.log("LaunchpadFactory deployed at:", address(factory));

        vm.stopBroadcast();
    }
}