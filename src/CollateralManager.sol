// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Pool} from "src/Pool.sol";

contract CollateralManager is Pool {
    mapping(address => mapping(address => uint256)) lockedBalances;

    address priceFeed;
    AggregatorV3Interface internal ethUsdPriceFeed;
    AggregatorV3Interface internal btcUsdPriceFeed;

    constructor() {
        // ETH/USD Chainlink Oracle
        ethUsdPriceFeed = AggregatorV3Interface(priceFeed);

        // BTC/USD Chainlink Oracle
        btcUsdPriceFeed = AggregatorV3Interface(priceFeed);
    }

    function getPrice(AggregatorV3Interface datafeed) internal view returns (uint256) {
        // prettier-ignore
        (
            /* uint80 roundId */
            ,
            int256 price,
            /*uint256 startedAt*/
            ,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = datafeed.latestRoundData();
        return uint256(price);
    }

    //This function locks token as collateral
    function lockAsCollateral(uint256 amount, address user) external balanceMustBeSufficient(amount, user) {
        userTotalBalance[user] -= amount;
        lockedBalances[user][lockedPool] += amount;
    }
    //This function unlocks token as collateral

    function unlockCollateral() private {}

    function getCollateralPriceInUsd(address user) public view returns (uint256) {
        uint256 ethPrice = getPrice(ethUsdPriceFeed);
        uint256 btcPrice = getPrice(btcUsdPriceFeed);

        uint256 wethBalance = lockedBalances[user][eth]; // 18 decimals
        uint256 wbtcBalance = lockedBalances[user][btc]; // 8 decimals

        uint256 wethValue = (wethBalance * ethPrice) / 1e18;
        uint256 wbtcValue = (wbtcBalance * btcPrice) / 1e8;

        return wethValue + wbtcValue; // USD value in 8 decimals
    }
}
