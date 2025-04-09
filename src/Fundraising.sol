// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "v2-periphery/interfaces/IUniswapV2Router02.sol";
import "./FundraisingToken.sol";
contract Fundraising is UUPSUpgradeable, OwnableUpgradeable {
    address public creator;
    address public platform;
    address public token;
    address public USDC;
    address public uniswapRouter;
    uint256 public F;
    uint256 public S_max;
    uint256 public S;
    uint256 public R;
    bool public finalized;

    event TokensPurchased(address buyer, uint256 usdcAmount, uint256 tokenAmount);
    event FundraisingFinalized(uint256 totalRaised);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _creator,
        address _platform,
        address _token,
        address _USDC,
        address _uniswapRouter,
        uint256 _F
    ) external initializer {
        require(_creator != address(0), "Invalid creator");
        require(_platform != address(0), "Invalid platform");
        require(_token != address(0), "Invalid token");
        require(_USDC != address(0), "Invalid USDC");
        require(_uniswapRouter != address(0), "Invalid uniswapRouter");
        require(_F > 0, "Invalid funding goal");

        __UUPSUpgradeable_init();
        __Ownable_init(_platform);
        // Remove redundant _transferOwnership(_platform);

        creator = _creator;
        platform = _platform;
        token = _token;
        USDC = _USDC;
        uniswapRouter = _uniswapRouter;
        F = _F;
        S_max = 500_000_000 * 10**18;
        S = 0;
        R = 0;
        finalized = false;
    }

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

    function finalize() external {
        require(S >= S_max, "Fundraising not complete");
        require(!finalized, "Already finalized");
        finalized = true;
        _finalize();
    }
    
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

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}