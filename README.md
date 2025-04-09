# Fundraising Token Launchpad

## Deployed Contracts (Polygon Amoy Testnet)

- **LaunchpadFactory**: [0x18A5BCc213c58c72eF93730eF2Ee25b779A40Db7](https://amoy.polygonscan.com/address/0x18A5BCc213c58c72eF93730eF2Ee25b779A40Db7)
- **Fundraising Implementation**: [0x9451FA945329851425881bC0d76149540f2d6051](https://amoy.polygonscan.com/address/0x9451FA945329851425881bC0d76149540f2d6051)
- **MockUSDC**: [0xc15830ACcB49ab1B257c6904877579382D5F08Ac](https://amoy.polygonscan.com/address/0xc15830ACcB49ab1B257c6904877579382D5F08Ac)
- **MockUniswapRouter**: [0xbd70A963D09b6f45cED8B5779810d74aBC404028](https://amoy.polygonscan.com/address/0xbd70A963D09b6f45cED8B5779810d74aBC404028)

## Approach to Implementing the Fundraising Token Launchpad

### Bonding Curve Mathematics

For this fundraising platform, I implemented a  bonding curve to incentivize early buyers while ensuring a predictable funding target. Here's how the mathematics works:

<details>
<summary><strong> Bonding Curve Implementation</strong></summary>

The relationship between tokens sold (S) and funds raised (R) is defined by:

```
S = S_max * sqrt(R/F)
```

Where:
- S = Tokens sold at any point
- S_max = Maximum tokens to be sold (500 million)
- R = Total funds raised at any point
- F = Funding goal

Rearranging to solve for R:

```
R = F * (S/S_max)²
```

This creates a  relationship where:
- When no funds are raised (R = 0), no tokens are sold (S = 0)
- When the funding goal is reached (R = F), exactly S_max tokens are sold
- The price per token increases linearly as more tokens are sold

The price function P(S) is the derivative of the R(S) curve:

```
P(S) = dR/dS = 2 * F * S / (S_max)²
```

This means the price is directly proportional to the number of tokens already sold, creating a linear price increase.

```solidity
// Implementation in the buy() function
uint256 scaledR = (R_new * 10**18) / F; // Scale to avoid underflow
uint256 sqrtTerm = Math.sqrt(scaledR);
uint256 S_new = (S_max * sqrtTerm) / 10**9; // Adjust scaling
if (S_new > S_max) S_new = S_max; // Cap at S_max
uint256 dS = S_new - S;
```
</details>

### Numerical Example

<details>
<summary><strong>How the Bonding Curve Works in Practice</strong></summary>

With a funding goal of 100,000 USDC and S_max of 500 million tokens:

- At 25% of funding (25,000 USDC):
  S = 500,000,000 * sqrt(0.25) = 250,000,000 tokens (50% of total)

- At 50% of funding (50,000 USDC):
  S = 500,000,000 * sqrt(0.5) = 353,553,390 tokens (70.7% of total)

- At 75% of funding (75,000 USDC):
  S = 500,000,000 * sqrt(0.75) = 433,012,701 tokens (86.6% of total)

This demonstrates how early buyers get more tokens per USDC than later buyers.
</details>

## Contract Structure and Architecture

<details>
<summary><strong>Key Contracts and Their Roles</strong></summary>

1. **LaunchpadFactory**: Creates new fundraising campaigns with their associated tokens
   ```solidity
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
   ```

2. **Fundraising**: Manages a single fundraising campaign with bonding curve logic
   ```solidity
   function buy(uint256 maxUsdc) external {
       require(!finalized, "Fundraising finalized");
       require(S < S_max, "Fundraising completed");
       require(maxUsdc > 0, "Invalid USDC amount");

       uint256 remainingUsdc = F - R;
       uint256 usdcToUse = Math.min(maxUsdc, remainingUsdc);
       uint256 R_new = R + usdcToUse;

       uint256 scaledR = (R_new * 10**18) / F;
       uint256 sqrtTerm = Math.sqrt(scaledR);
       uint256 S_new = (S_max * sqrtTerm) / 10**9;
       if (S_new > S_max) S_new = S_max;
       uint256 dS = S_new - S;

       require(dS > 0, "No tokens to mint");
       FundraisingToken(token).mint(msg.sender, dS);
       S = S_new;
       R = R_new;

       require(IERC20(USDC).transferFrom(msg.sender, address(this), usdcToUse), "USDC transfer failed");
       emit TokensPurchased(msg.sender, usdcToUse, dS);

       if (S >= S_max) {
           finalized = true;
           _finalize();
       }
   }
   ```

3. **FundraisingToken**: ERC20 token with minting capability
   ```solidity
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
   ```
</details>

<details>
<summary><strong>UUPS Upgradeability Implementation</strong></summary>

The contract uses the Universal Upgradeable Proxy Standard (UUPS) pattern:

```solidity
contract Fundraising is UUPSUpgradeable, OwnableUpgradeable {
    // Contract state and logic...

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
```

Key aspects:
- Upgrade logic is in the implementation contract itself
- `_authorizeUpgrade` ensures only the owner can upgrade
- The `initializer` modifier prevents re-initialization
- State variables are preserved during upgrades
</details>

<details>
<summary><strong>Token Distribution Logic</strong></summary>

After fundraising is complete, tokens are distributed as follows:

```solidity
function _finalize() internal {
    FundraisingToken tokenContract = FundraisingToken(token);
    tokenContract.mint(creator, 200_000_000 * 10**18);
    tokenContract.mint(platform, 50_000_000 * 10**18);
    tokenContract.mint(address(this), 250_000_000 * 10**18);

    uint256 halfF = F / 2;
    require(IERC20(USDC).transfer(creator, halfF), "USDC transfer to creator failed");

    tokenContract.approve(uniswapRouter, 250_000_000 * 10**18);
    IERC20(USDC).approve(uniswapRouter, halfF);
    IUniswapV2Router02(uniswapRouter).addLiquidity(
        USDC,
        token,
        halfF,
        250_000_000 * 10**18,
        0,
        0,
        address(this),
        block.timestamp + 1 hours
    );

    emit FundraisingFinalized(R);
}
```

This ensures:
- Creator receives 200M tokens and half the raised USDC
- Platform gets 50M tokens as a fee
- 250M tokens and remaining USDC go to the liquidity pool
</details>

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

## Implementation Challenges and Solutions

<details>
<summary><strong>Numerical Precision</strong></summary>

Working with fixed-point math in Solidity presented challenges:

```solidity
// Solution: Scale values before division to prevent precision loss
uint256 scaledR = (R_new * 10**18) / F;
uint256 sqrtTerm = Math.sqrt(scaledR);
uint256 S_new = (S_max * sqrtTerm) / 10**9;
```

The scaling factors were chosen to:
- Prevent underflow in division operations
- Maintain precision through the square root calculation
- Handle the full range of possible funding amounts
</details>

<details>
<summary><strong>Gas Optimization</strong></summary>

Several optimizations were implemented to reduce gas costs:

1. Using the square root function instead of power functions
2. Caching state variables in memory when used multiple times
3. Implementing auto-finalization to save an additional transaction
4. Using efficient state variable packing
</details>

<details>
<summary><strong>Security Considerations</strong></summary>

Key security features implemented:

1. **Authorization Controls**
   ```solidity
   function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
   ```

2. **Check-Effects-Interactions Pattern**
   ```solidity
   // First modify state
   FundraisingToken(token).mint(msg.sender, dS);
   S = S_new;
   R = R_new;
   
   // Then perform external interactions
   require(IERC20(USDC).transferFrom(msg.sender, address(this), usdcToUse), "USDC transfer failed");
   ```

3. **Input Validation**
   ```solidity
   require(!finalized, "Fundraising finalized");
   require(S < S_max, "Fundraising completed");
   require(maxUsdc > 0, "Invalid USDC amount");
   require(dS > 0, "No tokens to mint");
   ```
</details>

## Usage Guide

<details>
<summary><strong>Creating a New Fundraising Campaign</strong></summary>

```solidity
// 1. Get the factory address
address factoryAddress = 0x18A5BCc213c58c72eF93730eF2Ee25b779A40Db7;

// 2. Create a new fundraising campaign
LaunchpadFactory factory = LaunchpadFactory(factoryAddress);
address newCampaign = factory.createFundraising(
    projectCreator, // Address that will receive funds and creator tokens
    1000000 * 10**6, // Funding goal in USDC (1M USDC with 6 decimals)
    "Project Token",  // Token name
    "PRJT"           // Token symbol
);
```
</details>

<details>
<summary><strong>Contributing to a Campaign</strong></summary>

```solidity
// 1. Get the fundraising contract address
address fundraisingAddress = 0x...;

// 2. Approve USDC spending
IERC20 usdc = IERC20(0xc15830ACcB49ab1B257c6904877579382D5F08Ac);
usdc.approve(fundraisingAddress, 10000 * 10**6); // Approve 10k USDC

// 3. Buy tokens
Fundraising fundraising = Fundraising(fundraisingAddress);
fundraising.buy(10000 * 10**6); // Buy using 10k USDC
```
</details>

<details>
<summary><strong>Checking Campaign Status</strong></summary>

```solidity
Fundraising fundraising = Fundraising(fundraisingAddress);

// Check progress
uint256 fundingGoal = fundraising.F();
uint256 currentFunding = fundraising.R();
uint256 percentComplete = (currentFunding * 100) / fundingGoal;

uint256 maxTokens = fundraising.S_max();
uint256 tokensSold = fundraising.S();
uint256 tokenPercentSold = (tokensSold * 100) / maxTokens;

bool isComplete = fundraising.finalized();
```
</details>

<details>
<summary><strong>Future Enhancements (V2)</strong></summary>
# Future Enhancements (V2)

If time permitted, I would enhance the fundraising platform with several additional features to improve security, usability, and flexibility. Here are the key improvements planned for a V2 version:

## Time-Based Campaign Management

The current implementation lacks time constraints, allowing campaigns to remain open indefinitely. Adding start and end times would create more structured fundraising events with clear deadlines. This would help create urgency for potential contributors and provide a defined timeline for project creators to plan around.

Campaign timeframes would allow for scheduled launches coordinated with marketing efforts and prevent indefinitely open campaigns that might never reach their goals.

## Refund Mechanism for Failed Campaigns

A critical improvement would be implementing a refund system for campaigns that don't reach their funding goals by their deadline. This would provide security for early contributors, knowing they could reclaim their USDC if the project doesn't gain enough traction.

The refund mechanism would track individual contributions and allow contributors to burn their tokens in exchange for their original USDC amount. This would make the platform more trustworthy and reduce the risk for early supporters.

## Customizable Bonding Curves

While the  bonding curve works well, different projects might benefit from different token distribution models. Allowing project creators to choose from various curve types (linear, exponential, logarithmic, or custom Bancor-style) would provide more flexibility.

Each curve type offers different incentive structures and price progression models, which could be better suited for specific project types or funding goals.

## Enhanced Security Features

Additional security measures would make the platform more robust:

1. **Rate Limiting**: Prevent whale manipulation by limiting the maximum purchase amount per transaction and implementing cooldown periods between purchases from the same address.

2. **Emergency Pause**: Add the ability for platform administrators to pause campaigns in case of detected exploits or other security concerns.

3. **Access Control Improvements**: More granular permission systems to separate platform administrative functions from creator privileges.

## Creator Token Vesting

Instead of immediately releasing all creator tokens upon fundraising completion, implementing a vesting schedule would encourage long-term commitment from project teams. Tokens could be released gradually over months or years, aligning creator incentives with long-term project success.

This would help prevent "rug pulls" and build more trust with the community by ensuring creators remain invested in the project's success.

## Improved Liquidity Management

The current implementation adds liquidity to Uniswap but doesn't manage what happens to the LP tokens afterward. Enhanced liquidity management would include:

1. **Configurable LP Token Recipient**: Allow specification of where LP tokens should be sent
2. **Liquidity Locking**: Built-in time locks for LP tokens to prevent immediate liquidity removal
3. **Gradual Liquidity Addition**: Options to add liquidity in stages rather than all at once

## Expanded Test Coverage

While the current test suite covers core functionality, a more comprehensive test suite would include:

1. **Edge Case Testing**: Extreme value tests (minimum and maximum contributions), boundary conditions, and rounding error detection 

2. **Temporal Testing**: Testing behavior at different points in a campaign timeline

3. **Stress Testing**: High volume transaction simulations to ensure the contract can handle peak demand

4. **Fuzz Testing**: Randomized inputs to find unexpected behavior patterns

5. **Gas Optimization Analysis**: Detailed measurements of gas consumption across different operations

## Event-Based Analytics

Adding more comprehensive event emissions would enable better off-chain analytics. Detailed events tracking contribution patterns, milestone achievements, and pricing changes would allow for the development of dashboards and analytics tools to monitor campaign progress.

## Multi-Token Support

Expanding beyond USDC to accept multiple tokens for contributions would increase accessibility. This would require implementing token value oracles or fixed exchange rates to properly calculate token allocations based on the bonding curve.

