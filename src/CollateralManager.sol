// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Pool} from "src/Pool.sol";

contract CollateralManager is Pool {
    mapping(address => mapping(address => uint256)) lockedBalances;
    address priceFeed;
    AggregatorV3Interface internal ethUsdPriceFeed;
    AggregatorV3Interface internal btcUsdPriceFeed;

    constructor(address _btc, address _eth, address _usdt) Pool(_btc, _eth, _usdt) {
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
    function lockEthCollateral(uint256 amount, address user) external balanceMustBeSufficient(amount, user, ETH) {
        balances[user][ETH] -= amount;
        lockedBalances[user][ETH] += amount;
    }

    function lockBtcCollateral(uint256 amount, address user) external balanceMustBeSufficient(amount, user, BTC) {
        balances[user][BTC] -= amount;
        lockedBalances[user][BTC] += amount;
    }
    //This function unlocks token as collateral

   function unlockBtcCollateral(uint256 amount, address user) external balanceMustBeSufficient(amount, user, BTC) {
        balances[user][ETH] += amount;
        lockedBalances[user][BTC] -= amount;
    }
    function unlockEthCollateral(uint256 amount, address user) external balanceMustBeSufficient(amount, user, BTC) {
        balances[user][ETH] += amount;
        lockedBalances[user][ETH] -= amount;
    }

    function getBtcCollateralValueInUsd(address user) public view returns (uint256) {
        // uint256 ethPrice = getPrice(ethUsdPriceFeed);
        uint256 btcPrice = getPrice(btcUsdPriceFeed);

        // uint256 wethBalance = lockedBalances[user][ETH]; // 18 decimals
        uint256 wbtcBalance = lockedBalances[user][BTC]; // 8 decimals

        // uint256 wethValue = (wethBalance * ethPrice) / 1e18;
        uint256 wbtcValue = (wbtcBalance * btcPrice) / 1e8;

        return wbtcValue; // USD value in 8 decimals
    }

    function getEthCollateralValueInUsd(address user) public view returns (uint256) {
        uint256 ethPrice = getPrice(ethUsdPriceFeed);
        //uint256 btcPrice = getPrice(btcUsdPriceFeed);

        uint256 wethBalance = lockedBalances[user][ETH]; // 18 decimals
        // uint256 wbtcBalance = lockedBalances[user][BTC]; // 8 decimals

        uint256 wethValue = (wethBalance * ethPrice) / 1e18;
        //uint256 wbtcValue = (wbtcBalance * btcPrice) / 1e8;

        return wethValue; //+ wbtcValue; // USD value in 8 decimals
    }

    function getEthPrice() public view returns (uint256) {
        uint256 ethPrice = getPrice(ethUsdPriceFeed);
        return ethPrice;
    }

    function getBtcPrice() public view returns (uint256) {
        uint256 btcPrice = getPrice(btcUsdPriceFeed);
        return btcPrice;
    }
    function getLockedBtcBalance () public view returns (uint256) {
         uint256 presentCollateralBalance = lockedBalances[msg.sender][BTC]; 
         return presentCollateralBalance;

    }
     function getLockedEthBalance () public view returns (uint256) {
         uint256 presentCollateralBalance = lockedBalances[msg.sender][ETH]; 
         return presentCollateralBalance;

    }
}
