# Fundraising Token Launchpad


## Deployed Contracts (Polygon Amoy Testnet)

- **LaunchpadFactory**: [0x18A5BCc213c58c72eF93730eF2Ee25b779A40Db7](https://amoy.polygonscan.com/address/0x18A5BCc213c58c72eF93730eF2Ee25b779A40Db7)
- **Fundraising Implementation**: [0x9451FA945329851425881bC0d76149540f2d6051](https://amoy.polygonscan.com/address/0x9451FA945329851425881bC0d76149540f2d6051)
- **MockUSDC**: [0xc15830ACcB49ab1B257c6904877579382D5F08Ac](https://amoy.polygonscan.com/address/0xc15830ACcB49ab1B257c6904877579382D5F08Ac)
- **MockUniswapRouter**: [0xbd70A963D09b6f45cED8B5779810d74aBC404028](https://amoy.polygonscan.com/address/0xbd70A963D09b6f45cED8B5779810d74aBC404028)

## Overview
This Fundraising Token Launchpad enables creators to raise funds via a bonding curve, rewarding early buyers while ensuring a predictable funding target. Built under specific constraints, it uses a factory pattern, UUPS upgradeability, and a comprehensive test suite. Below is an outline of the approach, focusing on navigating the assignment’s limitations to deliver a functional solution.

---

## Key Constraints
- **Tight Timeline**: Prioritized core features—bonding curve, token distribution, and upgradeability—over additional enhancements.
- **Fixed Requirements**: 100,000 USDC goal, 500M tokens sold, and a distribution of 50% to buyers, 20% to creator, 5% to platform, and 25% to liquidity.
- **Solidity Integer Math**: No floating-point support required careful scaling to maintain precision in the bonding curve.

---

## Bonding Curve Implementation

### Approach
Implemented a square root bonding curve:  
`S = S_max * sqrt(R/F)`  
Where:
- `S`: Tokens sold
- `R`: Funds raised
- `F`: 100,000 USDC goal
- `S_max`: 500M tokens  

This incentivizes early buyers with a linearly increasing price:  
`P = 2 * F * S / (S_max)²`

```solidity
uint256 scaledR = (R_new * 10**18) / F;
uint256 sqrtTerm = Math.sqrt(scaledR);
uint256 S_new = (S_max * sqrtTerm) / 10**9;
if (S_new > S_max) S_new = S_max;
uint256 dS = S_new - S;
```

### Handling Constraints
- **Integer Math**: Scaled `R` by `10**18` before division and adjusted post-square root with `10**9`. Minor rounding occurs but meets the spec.
- **Time Pressure**: Focused on a single curve type (square root) to ensure delivery of the core mechanic.

### Example
- **25,000 USDC** → 250M tokens (~10,000 tokens/USDC)
- **50,000 USDC** → 353.55M tokens (7,071 tokens/USDC)
- **75,000 USDC** → 433.01M tokens (5,773 tokens/USDC)

This confirms early buyers get better rates, hitting 500M tokens at 100,000 USDC.

---

## Contract Architecture

### LaunchpadFactory
Deploys campaigns with tokens owned by the proxy:

```solidity
function createFundraising(address creator, uint256 F, string memory name, string memory symbol) external returns (address) {
    FundraisingToken token = new FundraisingToken(name, symbol, address(this));
    ERC1967Proxy proxy = new ERC1967Proxy(implementation, abi.encodeWithSelector(Fundraising.initialize.selector, ...));
    token.transferOwnership(address(proxy));
    return address(proxy);
}
```

**Constraint**: The token’s `Ownable` setup rejected `address(0)` as an initial owner. Used the factory as a temporary owner, then transferred it to the proxy.

---

### Fundraising
Manages buying and auto-finalizes when `S >= S_max`:

```solidity
function buy(uint256 maxUsdc) external {
    uint256 usdcToUse = Math.min(maxUsdc, F - R);
    uint256 R_new = R + usdcToUse;
    // Bonding curve calc...
    FundraisingToken(token).mint(msg.sender, dS);
    S = S_new;
    R = R_new;
    IERC20(USDC).transferFrom(msg.sender, address(this), usdcToUse);
    if (S >= S_max) finalized = true; // Auto-finalize
}
```

**Constraint**: Bundled `finalize()` into `buy()` to save gas and meet the deadline.

---

### UUPS Upgradeability
Ensures future-proofing:

```solidity
contract Fundraising is UUPSUpgradeable, OwnableUpgradeable {
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
```


---

## Testing Suite

<details>
<summary><strong>Test Coverage and Implementation</strong></summary>

The testing suite uses Foundry to verify all aspects of the system. Key tests include:

1. **Initialization Test**
   ```solidity
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
   ```

2. **Bonding Curve Incentive Test**
   ```solidity
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
   ```

3. **Funding Distribution Test**
   ```solidity
   function testFundingDistribution() public {
       vm.startPrank(buyer1);
       usdc.approve(address(fundraising), 60_000 * 10**6);
       fundraising.buy(60_000 * 10**6);
       vm.stopPrank();

       vm.startPrank(buyer2);
       usdc.approve(address(fundraising), 40_000 * 10**6);
       fundraising.buy(40_000 * 10**6);
       vm.stopPrank();

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
   ```

4. **UUPS Upgradeability Test**
   ```solidity
   function testUUPSUpgradeability() public {
       address currentOwner = OwnableUpgradeable(address(fundraising)).owner();
       console.log("Current owner: %s", currentOwner);
       assertEq(currentOwner, platform, "Platform should be owner before upgrade");

       Fundraising newImpl = new Fundraising();
       vm.prank(platform);
       UUPSUpgradeable(address(fundraising)).upgradeToAndCall(address(newImpl), "");

       bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
       address currentImpl = address(uint160(uint256(vm.load(address(fundraising), implSlot))));
       console.log("New implementation: %s", currentImpl);
       assertEq(currentImpl, address(newImpl), "Implementation not upgraded");
   }
   ```

5. **Edge Case Tests**
   ```solidity
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

       vm.startPrank(buyer1);
       usdc.approve(address(fundraising), 10_000 * 10**6);
       vm.expectRevert("Fundraising finalized");
       fundraising.buy(10_000 * 10**6);
       vm.stopPrank();
   }
   ```

The test results confirmed:
- The bonding curve correctly incentivizes early buyers
- Token distribution follows the specified requirements
- The UUPS upgradeability mechanism works correctly
- Edge cases are properly handled
</details>
**Constraint**: Focused on 6 core tests due to time limits, prioritizing the spec’s must-haves.

---

## Trade-Offs
- **Precision**: Scaling avoids major precision loss, but slight rounding was accepted to meet the deadline.
- **Features**: Skipped time limits or refunds to focus on bonding curve and distribution logic.
- **Gas**: Auto-finalization saves a transaction, though the math-heavy curve could be optimized further.

---

## Next Steps
With fewer constraints, I’d add:
- Campaign deadlines and refunds.
- Configurable bonding curves.
- Enhanced gas optimization.

---

