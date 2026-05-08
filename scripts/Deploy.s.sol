// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {Pool} from "../src/core/Pool.sol";
import {MockERC20} from "../test/Mocks/MockERC20.sol";
import {PriceFeeds} from "../test/Mocks/MockAggregator.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Deploy is Script {
    uint256 constant RAY = 1e18;

    function run() external {
        address deployer = msg.sender;
        vm.startBroadcast();

        // 1. Deploy mock tokens
        MockERC20 usdt = new MockERC20("Mock USDT", "mUSDT");
        MockERC20 weth = new MockERC20("Mock WETH", "mWETH");
        MockERC20 wbtc = new MockERC20("Mock WBTC", "mWBTC");

        // 2. Deploy mock price feeds
        //    CRITICAL: Pool.getPrice() divides by RAY (1e18), so prices MUST be 1e18-scaled.
        //    PriceFeeds(price, decimals) — use 18 decimals and 1e18-scaled prices.
        PriceFeeds usdtFeed = new PriceFeeds(int256(1 * RAY), 18); // $1
        PriceFeeds wethFeed = new PriceFeeds(int256(3_000 * RAY), 18); // $3000
        PriceFeeds wbtcFeed = new PriceFeeds(int256(60_000 * RAY), 18); // $60000

        // 3. Deploy Pool
        Pool pool = new Pool();

        // 4. Mint tokens to deployer (for seeding deposits)
        usdt.mint(deployer, 1_000_000e18);
        weth.mint(deployer, 1_000e18);
        wbtc.mint(deployer, 100e18);

        // 5. Initialize reserves
        pool.instantiateNewReserveData(
            "mUSDT",
            address(usdtFeed),
            address(usdt),
            85 * RAY / 100, // liquidationThreshold 85%
            80 * RAY / 100, // ltv 80%
            4 * RAY / 100, // slope1 4%
            60 * RAY / 100, // slope2 60%
            2 * RAY / 100, // baseInterestRate 2%
            80 * RAY / 100, // optimalUtilization 80%
            5 * RAY / 100, // liquidationBonus 5%
            10 * RAY / 100, // reserveFactor 10%
            1_000_000e18, // borrowCap
            1_000_000e18, // supplyCap
            true, // isActive
            true // isBorrowable
        );

        pool.instantiateNewReserveData(
            "mWETH",
            address(wethFeed),
            address(weth),
            80 * RAY / 100,
            75 * RAY / 100,
            5 * RAY / 100,
            80 * RAY / 100,
            2 * RAY / 100,
            80 * RAY / 100,
            8 * RAY / 100,
            15 * RAY / 100,
            10_000e18,
            10_000e18,
            true,
            true
        );

        pool.instantiateNewReserveData(
            "mWBTC",
            address(wbtcFeed),
            address(wbtc),
            75 * RAY / 100,
            70 * RAY / 100,
            5 * RAY / 100,
            100 * RAY / 100,
            2 * RAY / 100,
            65 * RAY / 100,
            10 * RAY / 100,
            20 * RAY / 100,
            1_000e18,
            1_000e18,
            true,
            true
        );

        // 6. Seed initial liquidity via deposit() so totalDeposits is non-zero.
        //    This is required — minting directly to the pool address bypasses accounting.
        IERC20(address(usdt)).approve(address(pool), 500_000e18);
        IERC20(address(weth)).approve(address(pool), 500e18);
        IERC20(address(wbtc)).approve(address(pool), 50e18);

        pool.deposit("mUSDT", 500_000e18);
        pool.deposit("mWETH", 500e18);
        pool.deposit("mWBTC", 50e18);

        vm.stopBroadcast();

        // Log addresses for deploy.sh to parse
        console.log("Pool deployed at:", address(pool));
        console.log("mUSDT deployed at:", address(usdt));
        console.log("mWETH deployed at:", address(weth));
        console.log("mWBTC deployed at:", address(wbtc));
        console.log("USDT feed at:", address(usdtFeed));
        console.log("WETH feed at:", address(wethFeed));
        console.log("WBTC feed at:", address(wbtcFeed));
    }
}
