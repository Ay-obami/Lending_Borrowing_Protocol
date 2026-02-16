// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Vusdt} from "src/core/Vtokens/VUsdt.sol";
import {Vbtc} from "src/core/Vtokens/VBtc.sol";
import {Veth} from "src/core/Vtokens/VEth.sol";
import {Dusdt} from "src/core/Vtokens/DUsdt.sol";

contract Pool is ReentrancyGuard {
    using SafeERC20 for IERC20;

    Vusdt public immutable VUSDT;
    Vbtc public immutable VBTC;
    Veth public immutable VETH;
    Dusdt public immutable DUSDT;

    error amountShouldBeGreaterThanZero(string);
    error insufficientBalance(string);
    error unHealthyHealthFactor(string);

    address immutable BTC; // WETH Address
    address immutable ETH; // WBTC Address
    address immutable USDT;
    uint256 decimalPrecision = 1e18;
    uint256 healthyHealthFactor = (6 * decimalPrecision) / 5;
    mapping(address => mapping(address => uint256)) balances;
    mapping(address => uint256) poolTotalBalance;
    mapping(address => uint256) loanBalances;

    event transferSuccessful(address, uint256);
    event withdrawalSuccessful(address, uint256);

    modifier ensureHealthFactorIsHealthy(uint256 amount) {
        _ensureHealthFactorIsHealthy(amount);
        _;
    }

    modifier mustBeGreaterThanZero(uint256 amount) {
       _mustBeGreaterThanZero(amount);
        _;
    }

    modifier balanceMustBeSufficient(uint256 amount, address user, address token) {
        _balanceMustBeSufficient(amount, user, token);
        _;
    }

    constructor(address _btc, address _eth, address _usdt) {
        BTC = _btc;
        ETH = _eth;
        USDT = _usdt;

        // Deploy VTokens here
        VUSDT = new Vusdt();
        VBTC = new Vbtc();
        VETH = new Veth();
        DUSDT = new Dusdt();

        // Transfer ownership of each VToken to this Pool
        //VUSDT.transferOwnership(address(this));
        // VBTC.transferOwnership(address(this));
        //VETH.transferOwnership(address(this));
    }

    // Supply USDT for borrowing
    // Accumulates interests
    // Can be unavailable sometimes
    function supplyUsdt(uint256 amount) external mustBeGreaterThanZero(amount) nonReentrant {
        balances[msg.sender][USDT] += amount;
        poolTotalBalance[USDT] += amount;
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), amount);
        VUSDT.mint(msg.sender, amount);
        emit transferSuccessful(msg.sender, amount);
    }

    function borrowUsdt(uint256 amount)
        external
        mustBeGreaterThanZero(amount)
        nonReentrant
        ensureHealthFactorIsHealthy(amount)
    {
        //balances[msg.sender][USDT] += amount;
        loanBalances[msg.sender] += amount;
        poolTotalBalance[USDT] -= amount;
        DUSDT.mint(msg.sender, amount);
        IERC20(USDT).safeTransfer(msg.sender, amount);
        emit transferSuccessful(msg.sender, amount);
    }

    function payUsdt(uint256 amount) external mustBeGreaterThanZero(amount) nonReentrant {
        //balances[msg.sender][USDT] -= amount;
        loanBalances[msg.sender] -= amount;
        poolTotalBalance[USDT] += amount;
        DUSDT.burn(msg.sender, amount);
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), amount);
        emit transferSuccessful(msg.sender, amount);
    }

    //This function transfers tokens to the pool from the caller's address and mints a corresponding amount of virtual token to the caller's address
    function supplyEth(uint256 amount) external mustBeGreaterThanZero(amount) nonReentrant {
        balances[msg.sender][ETH] += amount;
        poolTotalBalance[ETH] += amount;
        IERC20(ETH).safeTransferFrom(msg.sender, address(this), amount);
        VETH.mint(msg.sender, amount);
        emit transferSuccessful(msg.sender, amount);
    }

    function supplyBtc(uint256 amount) external mustBeGreaterThanZero(amount) nonReentrant {
        balances[msg.sender][BTC] += amount;
        poolTotalBalance[BTC] += amount;
        IERC20(BTC).safeTransferFrom(msg.sender, address(this), amount);
        VBTC.mint(msg.sender, amount);
        emit transferSuccessful(msg.sender, amount);
    }
    // This function transfers tokens from the pool to the caller's address and burns a corresponding amount of virtual token from the caller's address
    // This can only be called by an address that has supplied tokens to the pool
    // Caller can't withdraw locked tokens i.e tokens that has been locked as collateral
    // Tokens locked as collateral accumulates interest

    function withdrawEth(uint256 amount)
        external
        mustBeGreaterThanZero(amount)
        balanceMustBeSufficient(amount, msg.sender, ETH)
        nonReentrant
    {
        balances[msg.sender][ETH] -= amount;
        poolTotalBalance[ETH] -= amount;
        VETH.burn(msg.sender, amount);
        IERC20(ETH).safeTransfer(msg.sender, amount);
        emit withdrawalSuccessful(msg.sender, amount);
    }

    function withdrawBtc(uint256 amount)
        external
        mustBeGreaterThanZero(amount)
        balanceMustBeSufficient(amount, msg.sender, BTC)
        nonReentrant
    {
        balances[msg.sender][BTC] -= amount;
        poolTotalBalance[BTC] -= amount;
        VBTC.burn(msg.sender, amount);
        IERC20(BTC).safeTransfer(msg.sender, amount);
        emit withdrawalSuccessful(msg.sender, amount);
    }

    function getHealthFactor(uint256 amount) public view returns (uint256) {
        uint256 healthfactor;
        uint256 usdtInPool = VUSDT.totalSupply();
        uint256 totalDebt = DUSDT.totalSupply();
        if (totalDebt == 0) {
            healthfactor = usdtInPool;
        } else if (amount == 0) {
            healthfactor = usdtInPool / totalDebt;
        } else {
            healthfactor = usdtInPool / (totalDebt + amount);
        }
        return healthfactor;
    }

    function getLoanBalance(address user) public view returns (uint256) {
        uint256 loanBalance = loanBalances[user];
        return loanBalance;
    }
    function _ensureHealthFactorIsHealthy(uint256 amount)internal view {
        uint256 healthFactor = getHealthFactor(amount);
        if (healthFactor <= healthyHealthFactor) {
            revert unHealthyHealthFactor("Insufficient Liquidity");
        }
        
    }
    function _mustBeGreaterThanZero(uint256 amount) internal pure{
        if (amount <= 0) {
            revert amountShouldBeGreaterThanZero("Amount should be more than zero");
        }
    }
    function _balanceMustBeSufficient(uint256 amount, address user, address token) internal view {
        require(balances[user][token] >= amount, "Insufficient Balance");
        
    }

}
