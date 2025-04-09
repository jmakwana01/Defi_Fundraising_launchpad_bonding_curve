// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/FundraisingToken.sol";
import "../src/Fundraising.sol";
import "../src/LaunchpadFactory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IUUPSUpgradeable {
    function upgradeTo(address newImplementation) external;
}

contract MockUSDC is IERC20 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    uint256 public override totalSupply;

    constructor() {
        totalSupply = 1_000_000 * 10**6;
        balanceOf[msg.sender] = totalSupply;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockUniswapRouter {
    address public token;
    address public usdc;
    uint256 public tokenAmount;
    uint256 public usdcAmount;

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address,
        uint256
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        token = tokenA;
        usdc = tokenB;
        tokenAmount = amountADesired;
        usdcAmount = amountBDesired;
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBDesired);
        return (amountADesired, amountBDesired, 1e18);
    }
}

contract FundraisingTest is Test {
    LaunchpadFactory factory;
    Fundraising fundraising;
    FundraisingToken token;
    MockUSDC usdc;
    MockUniswapRouter uniswapRouter;

    address creator = address(0x1);
    address platform = address(0x2);
    address buyer1 = address(0x3);
    address buyer2 = address(0x4);

    uint256 F = 100_000 * 10**6;
    uint256 S_max = 500_000_000 * 10**18;

    function setUp() public {
        usdc = new MockUSDC();
        uniswapRouter = new MockUniswapRouter();
        Fundraising fundraisingImpl = new Fundraising();
        
        factory = new LaunchpadFactory(address(fundraisingImpl), address(usdc), address(uniswapRouter));
        
        vm.prank(platform);
        address proxyAddr = factory.createFundraising(creator, F, "Test Token", "TST");
        fundraising = Fundraising(proxyAddr);
        token = FundraisingToken(fundraising.token());

        vm.prank(address(this));
        usdc.transfer(buyer1, 60_000 * 10**6);
        usdc.transfer(buyer2, 40_000 * 10**6);

        assertEq(fundraising.creator(), creator, "Proxy not initialized");
        assertEq(OwnableUpgradeable(address(fundraising)).owner(), platform, "Platform should be owner");
        assertEq(token.owner(), address(fundraising), "Fundraising should own the token");
    }

    function testInitialSetup() public {
        assertEq(fundraising.creator(), creator);
        assertEq(fundraising.platform(), platform);
        assertEq(fundraising.token(), address(token));
        assertEq(fundraising.USDC(), address(usdc));
        assertEq(fundraising.uniswapRouter(), address(uniswapRouter));
        assertEq(fundraising.F(), F);
        assertEq(fundraising.S_max(), S_max);
        assertEq(fundraising.S(), 0);
        assertEq(fundraising.R(), 0);
    }

    function testBondingCurveEarlyIncentive() public {
        vm.startPrank(buyer1);
        usdc.approve(address(fundraising), 60_000 * 10**6);
        fundraising.buy(60_000 * 10**6);
        uint256 tokensBuyer1 = token.balanceOf(buyer1);
        console.log("Buyer1: Tokens=%d, Rate=%d tokens/USDC", tokensBuyer1 / 10**18, (tokensBuyer1 * 10**6) / (60_000 * 10**6));
        vm.stopPrank();

        vm.startPrank(buyer2);
        usdc.approve(address(fundraising), 40_000 * 10**6);
        fundraising.buy(40_000 * 10**6);
        uint256 tokensBuyer2 = token.balanceOf(buyer2);
        console.log("Buyer2: Tokens=%d, Rate=%d tokens/USDC", tokensBuyer2 / 10**18, (tokensBuyer2 * 10**6) / (40_000 * 10**6));
        vm.stopPrank();

        console.log("Total: S=%d tokens, R=%d USDC", fundraising.S() / 10**18, fundraising.R() / 10**6);
        assertEq(fundraising.S(), S_max, "Should sell 500M tokens");
        assertEq(fundraising.R(), F, "Should raise F USDC");

        uint256 rate1 = (tokensBuyer1 * 10**6) / (60_000 * 10**6);
        uint256 rate2 = (tokensBuyer2 * 10**6) / (40_000 * 10**6);
        assertGt(rate1, rate2, "Early buyer should get better rate");
    }

    function testFundingDistribution() public {
        vm.startPrank(buyer1);
        usdc.approve(address(fundraising), 60_000 * 10**6);
        fundraising.buy(60_000 * 10**6);
        vm.stopPrank();

        vm.startPrank(buyer2);
        usdc.approve(address(fundraising), 40_000 * 10**6);
        fundraising.buy(40_000 * 10**6);
        vm.stopPrank();

        // Check token distribution (should be automatically finalized)
        assertEq(token.totalSupply(), 1_000_000_000 * 10**18);
        assertEq(token.balanceOf(creator), 200_000_000 * 10**18);
        assertEq(usdc.balanceOf(creator), F / 2);
        assertEq(token.balanceOf(platform), 50_000_000 * 10**18);
        assertEq(token.balanceOf(address(uniswapRouter)), 250_000_000 * 10**18);
        assertEq(usdc.balanceOf(address(uniswapRouter)), F / 2);
        uint256 buyerTokens = token.balanceOf(buyer1) + token.balanceOf(buyer2);
        assertEq(buyerTokens, 500_000_000 * 10**18);
        assertEq(fundraising.R(), F);
    }

    function testUUPSUpgradeability() public {
    address currentOwner = OwnableUpgradeable(address(fundraising)).owner();
    console.log("Current owner: %s", currentOwner);
    assertEq(currentOwner, platform, "Platform should be owner before upgrade");

    // Create a new implementation
    Fundraising newImpl = new Fundraising();
    
    // Call upgradeToAndCall from the platform account (owner)
    vm.prank(platform);
    UUPSUpgradeable(address(fundraising)).upgradeToAndCall(address(newImpl), "");

    // Verify the upgrade worked by checking the implementation slot
    bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    address currentImpl = address(uint160(uint256(vm.load(address(fundraising), implSlot))));
    console.log("New implementation: %s", currentImpl);
    assertEq(currentImpl, address(newImpl), "Implementation not upgraded");
}

    function testCannotFinalizeEarly() public {
        vm.expectRevert("Fundraising not complete");
        fundraising.finalize();
    }

    function testCannotBuyAfterComplete() public {
        vm.startPrank(buyer1);
        usdc.approve(address(fundraising), 60_000 * 10**6);
        fundraising.buy(60_000 * 10**6);
        vm.stopPrank();

        vm.startPrank(buyer2);
        usdc.approve(address(fundraising), 40_000 * 10**6);
        fundraising.buy(40_000 * 10**6);
        vm.stopPrank();

        // Try to buy more after auto-finalization
        vm.startPrank(buyer1);
        usdc.approve(address(fundraising), 10_000 * 10**6);
        vm.expectRevert("Fundraising finalized");
        fundraising.buy(10_000 * 10**6);
        vm.stopPrank();
    }
}