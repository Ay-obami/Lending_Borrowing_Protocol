// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {Pool} from "src/core/Pool.sol";

contract CollateralManager is Pool {
    mapping(address => mapping(address => uint256)) lockedBalances;

    AggregatorV3Interface internal ethUsdPriceFeed;
    AggregatorV3Interface internal btcUsdPriceFeed;

    constructor(address _btc, address _eth, address _usdt, address ethPriceFeed, address btcPriceFeed)
        Pool(_btc, _eth, _usdt)
    {
        // ETH/USD Chainlink Oracle
        ethUsdPriceFeed = AggregatorV3Interface(ethPriceFeed);

        // BTC/USD Chainlink Oracle
        btcUsdPriceFeed = AggregatorV3Interface(btcPriceFeed);
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
        balances[user][BTC] += amount;
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

    function getLockedBtcBalance(address user) public view returns (uint256) {
        uint256 presentCollateralBalance = lockedBalances[user][BTC];
        return presentCollateralBalance;
    }

    function getLockedEthBalance(address user) public view returns (uint256) {
        uint256 presentCollateralBalance = lockedBalances[user][ETH];
        return presentCollateralBalance;
    }
}

pragma solidity ^0.8.7;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CollateralManagerNew {
    using SafeERC20 for IERC20;

    IERC20 public collateralToken;
    mapping(address => uint256) public collateralBalances;
    mapping(address => uint256) public lockedCollateralBalances;

    constructor(address _collateralToken) {
        collateralToken = IERC20(_collateralToken);
    }

    function deposit(uint256 amount) external {
        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        collateralBalances[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        require(collateralBalances[msg.sender] >= amount, "Insufficient balance");
        collateralBalances[msg.sender] -= amount;
        collateralToken.safeTransfer(msg.sender, amount);
    }

    function forceWithdraw(uint256 amount) external {
        // Force withdraw collateral (used in liquidation)
        require(lockedCollateralBalances[msg.sender] >= amount, "Insufficient locked collateral");
        lockedCollateralBalances[msg.sender] -= amount;
        collateralToken.safeTransfer(msg.sender, amount);
    }

    function lockCollateral(uint256 amount) external {
        // Lock collateral in the pool
        collateralBalances[msg.sender] -= amount;
        lockedCollateralBalances[msg.sender] += amount;
    }

    function unlockCollateral(uint256 amount) external {
        // Unlock collateral in the pool
        require(lockedCollateralBalances[msg.sender] >= amount, "Insufficient locked collateral");
        lockedCollateralBalances[msg.sender] -= amount;
        collateralBalances[msg.sender] += amount;
    }
}

