// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CollateralManager {
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

