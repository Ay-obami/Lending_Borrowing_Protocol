// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Pool} from "../src/core/Pool.sol";
import {PriceFeeds} from "./Mocks/MockAggregator.sol";
import {MockERC20} from "./Mocks/MockERC20.sol";

contract PoolTest is Test {
    Pool pool;
    PriceFeeds mockEthAggregator;
    PriceFeeds mockUsdcAggregator;
    MockERC20 mockEth;
    MockERC20 mockUsdc;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // Reserve params
    uint256 constant LIQUIDATION_THRESHOLD = 0.9e18;
    uint256 constant LTV = 0.8e18;
    uint256 constant SLOPE1 = 0.2e18;
    uint256 constant SLOPE2 = 0.8e18;
    uint256 constant BASE_RATE = 0.1e18;
    uint256 constant OPTIMAL_UTIL = 0.85e18;
    uint256 constant LIQUIDATION_BONUS = 0.05e18;
    uint256 constant RESERVE_FACTOR = 0.1e18;
    uint256 constant BORROW_CAP = 900000;
    uint256 constant SUPPLY_CAP = 100000000;

    // Mirrors Pool's internal constants
    uint256 constant MIN_BUFFER = 0.05e18;
    uint256 constant MAX_BUFFER = 1e18;

    function setUp() public {
        pool = new Pool();
        mockEthAggregator = new PriceFeeds(2000e18, 18);
        mockUsdcAggregator = new PriceFeeds(1e18, 18);
        mockEth = new MockERC20("Ether", "ETH");
        mockUsdc = new MockERC20("USD Coin", "USDC");

        mockEth.mint(alice, 100 ether);
        mockEth.mint(bob, 100 ether);
        mockUsdc.mint(alice, 10000e6);
        mockUsdc.mint(bob, 10000e6);
    }

    // ================================================================
    // Helpers
    // ================================================================

    function _initEthReserve() internal {
        pool.instantiateNewReserveData(
            "Ether",
            address(mockEthAggregator),
            address(mockEth),
            LIQUIDATION_THRESHOLD,
            LTV,
            SLOPE1,
            SLOPE2,
            BASE_RATE,
            OPTIMAL_UTIL,
            LIQUIDATION_BONUS,
            RESERVE_FACTOR,
            BORROW_CAP,
            SUPPLY_CAP,
            true,
            true
        );
    }

    function _initUsdcReserve() internal {
        pool.instantiateNewReserveData(
            "USD Coin",
            address(mockUsdcAggregator),
            address(mockUsdc),
            LIQUIDATION_THRESHOLD,
            LTV,
            SLOPE1,
            SLOPE2,
            BASE_RATE,
            OPTIMAL_UTIL,
            LIQUIDATION_BONUS,
            RESERVE_FACTOR,
            BORROW_CAP,
            SUPPLY_CAP,
            true,
            true
        );
    }

    function _depositEth(address user, uint256 amount) internal {
        vm.startPrank(user);
        mockEth.approve(address(pool), type(uint256).max);
        pool.deposit("Ether", amount);
        vm.stopPrank();
    }

    function _depositUsdc(address user, uint256 amount) internal {
        vm.startPrank(user);
        mockUsdc.approve(address(pool), type(uint256).max);
        pool.deposit("USD Coin", amount);
        vm.stopPrank();
    }

    // ================================================================
    // instantiateNewReserveData
    // ================================================================

    function testInitializeReserve() public {
        _initEthReserve();
        Pool.ReserveData memory data = pool.getReserveData("Ether");

        assertEq(data.totalDeposits, 0);
        assertEq(data.totalBorrows, 0);
        assertEq(data.supplyLiquidityIndex, 1e18);
        assertEq(data.borrowLiquidityIndex, 1e18);
        assertEq(data.ltv, LTV);
        assertEq(data.liquidationThreshold, LIQUIDATION_THRESHOLD);
        assertEq(data.priceFeed, address(mockEthAggregator));
        assertEq(data.tokenAddress, address(mockEth));
        assertTrue(data.isActive);
        assertTrue(data.isBorrowable);
    }

    function testInitializeReserve_RevertsIfAlreadyExists() public {
        _initEthReserve();
        vm.expectRevert(abi.encodeWithSelector(Pool.ReserveAlreadyExists.selector, "Ether"));
        _initEthReserve();
    }

    function testInitializeReserve_RevertsIfOptimalUtilizationZero() public {
        vm.expectRevert(Pool.OptimalUtilizationCannotBeZero.selector);
        pool.instantiateNewReserveData(
            "Ether",
            address(mockEthAggregator),
            address(mockEth),
            LIQUIDATION_THRESHOLD,
            LTV,
            SLOPE1,
            SLOPE2,
            BASE_RATE,
            0,
            LIQUIDATION_BONUS,
            RESERVE_FACTOR,
            BORROW_CAP,
            SUPPLY_CAP,
            true,
            true
        );
    }

    function testInitializeReserve_RevertsIfOptimalUtilizationExceeds100() public {
        vm.expectRevert(Pool.OptimalUtilizationExceeds100.selector);
        pool.instantiateNewReserveData(
            "Ether",
            address(mockEthAggregator),
            address(mockEth),
            LIQUIDATION_THRESHOLD,
            LTV,
            SLOPE1,
            SLOPE2,
            BASE_RATE,
            1e18 + 1,
            LIQUIDATION_BONUS,
            RESERVE_FACTOR,
            BORROW_CAP,
            SUPPLY_CAP,
            true,
            true
        );
    }

    function testInitializeReserve_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        _initEthReserve();
    }

    // ================================================================
    // deposit
    // ================================================================

    function testDeposit() public {
        _initEthReserve();
        _depositEth(alice, 1000);

        assertEq(pool.getReserveData("Ether").totalDeposits, 1000);
        assertEq(pool.getUserDepositBalance("Ether", alice), 1000);
    }

    function testDeposit_ScaledBalanceCorrect() public {
        _initEthReserve();
        _depositEth(alice, 1000);

        assertEq(pool.getUserDepositBalance("Ether", alice), 1000);
    }

    function testDeposit_MultipleUsers() public {
        _initEthReserve();
        _depositEth(alice, 1000);
        _depositEth(bob, 2000);

        assertEq(pool.getReserveData("Ether").totalDeposits, 3000);
        assertEq(pool.getUserDepositBalance("Ether", alice), 1000);
        assertEq(pool.getUserDepositBalance("Ether", bob), 2000);
    }

    function testDeposit_RevertsIfNotActive() public {
        pool.instantiateNewReserveData(
            "Ether",
            address(mockEthAggregator),
            address(mockEth),
            LIQUIDATION_THRESHOLD,
            LTV,
            SLOPE1,
            SLOPE2,
            BASE_RATE,
            OPTIMAL_UTIL,
            LIQUIDATION_BONUS,
            RESERVE_FACTOR,
            BORROW_CAP,
            SUPPLY_CAP,
            false,
            true
        );
        vm.startPrank(alice);
        mockEth.approve(address(pool), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Pool.ReserveNotActive.selector, "Ether"));
        pool.deposit("Ether", 1000);
        vm.stopPrank();
    }

    function testDeposit_RevertsIfSupplyCapExceeded() public {
        _initEthReserve();
        vm.startPrank(alice);
        mockEth.approve(address(pool), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Pool.SupplyCapExceeded.selector, "Ether", SUPPLY_CAP));
        pool.deposit("Ether", SUPPLY_CAP + 1);
        vm.stopPrank();
    }

    // ================================================================
    // withdraw
    // ================================================================

    function testWithdraw() public {
        _initEthReserve();
        _depositEth(alice, 1000);

        vm.prank(alice);
        pool.withdraw("Ether", 500);

        assertEq(pool.getReserveData("Ether").totalDeposits, 500);
        assertEq(pool.getUserDepositBalance("Ether", alice), 500);
    }

    function testWithdraw_FullAmount() public {
        _initEthReserve();
        _depositEth(alice, 1000);

        vm.prank(alice);
        pool.withdraw("Ether", 1000);

        assertEq(pool.getReserveData("Ether").totalDeposits, 0);
        assertEq(pool.getUserDepositBalance("Ether", alice), 0);
    }

    function testWithdraw_RevertsIfInsufficientLiquidity() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100);
        _depositUsdc(bob, 100000);

        vm.prank(bob);
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Pool.InsufficientPoolLiquidity.selector, 90, 100));
        pool.withdraw("Ether", 100);
    }

    function testWithdraw_RevertsIfInsufficientUserBalance() public {
        _initEthReserve();
        _depositEth(alice, 1000);

        vm.prank(alice);
        vm.expectRevert();
        pool.withdraw("Ether", 2000);
    }

    function testWithdraw_TransfersTokensToUser() public {
        _initEthReserve();
        uint256 balanceBefore = mockEth.balanceOf(alice);
        _depositEth(alice, 1000);

        vm.prank(alice);
        pool.withdraw("Ether", 1000);

        assertEq(mockEth.balanceOf(alice), balanceBefore);
    }

    // ================================================================
    // borrow
    // ================================================================

    function testBorrow() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.prank(bob);
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);

        assertEq(pool.getReserveData("Ether").totalBorrows, 10);
    }

    function testBorrow_LocksCollateral() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        uint256 depositBefore = pool.getUserDepositBalance("USD Coin", bob);

        vm.prank(bob);
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);

        uint256 depositAfter = pool.getUserDepositBalance("USD Coin", bob);
        assertTrue(depositAfter < depositBefore);
    }

    function testBorrow_RevertsIfNotBorrowable() public {
        pool.instantiateNewReserveData(
            "Ether",
            address(mockEthAggregator),
            address(mockEth),
            LIQUIDATION_THRESHOLD,
            LTV,
            SLOPE1,
            SLOPE2,
            BASE_RATE,
            OPTIMAL_UTIL,
            LIQUIDATION_BONUS,
            RESERVE_FACTOR,
            BORROW_CAP,
            SUPPLY_CAP,
            true,
            false
        );
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Pool.AssetNotBorrowable.selector, "Ether"));
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);
    }

    function testBorrow_RevertsIfBufferTooLow() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Pool.BufferTooLow.selector, 0.01e18, MIN_BUFFER));
        pool.borrow("USD Coin", "Ether", 10, 0.01e18);
    }

    function testBorrow_RevertsIfBufferTooHigh() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Pool.BufferTooHigh.selector, 1.1e18, MAX_BUFFER));
        pool.borrow("USD Coin", "Ether", 10, 1.1e18);
    }

    function testBorrow_RevertsIfBorrowCapExceeded() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Pool.BorrowCapExceeded.selector, "Ether", BORROW_CAP));
        pool.borrow("USD Coin", "Ether", BORROW_CAP + 1, 0.5e18);
    }

    function testBorrow_RevertsIfInsufficientCollateral() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Pool.InsufficientFreeCollateral.selector, 100, uint256(37500)));
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);
    }

    function testBorrow_RevertsIfMaxUtilizationExceeded() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100);
        _depositUsdc(bob, 100000000);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Pool.MaxUtilizationExceeded.selector, "Ether"));
        pool.borrow("USD Coin", "Ether", 96, 0.5e18);
    }

    function testBorrow_CreatesPosition() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.prank(bob);
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);

        Pool.Position[] memory positions = pool.getUserPositions(bob);
        assertEq(positions.length, 1);
        assertTrue(positions[0].scaledDebt > 0);
        assertTrue(positions[0].collateralLocked > 0);
    }

    function testBorrow_MultiplePositions() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.startPrank(bob);
        pool.borrow("USD Coin", "Ether", 5, 0.5e18);
        pool.borrow("USD Coin", "Ether", 5, 0.5e18);
        vm.stopPrank();

        Pool.Position[] memory positions = pool.getUserPositions(bob);
        assertEq(positions.length, 2);
    }

    // ================================================================
    // repay
    // ================================================================

    function testRepay_FullRepay() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.startPrank(bob);
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);
        uint256 borrowsBefore = pool.getReserveData("Ether").totalBorrows;
        pool.repay("USD Coin", "Ether", 0, 10);
        vm.stopPrank();

        assertEq(pool.getReserveData("Ether").totalBorrows, borrowsBefore - 10);
    }

    function testRepay_ReleasesCollateral() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.startPrank(bob);
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);
        uint256 depositAfterBorrow = pool.getUserDepositBalance("USD Coin", bob);
        pool.repay("USD Coin", "Ether", 0, 10);
        uint256 depositAfterRepay = pool.getUserDepositBalance("USD Coin", bob);
        vm.stopPrank();

        assertTrue(depositAfterRepay > depositAfterBorrow);
    }

    function testRepay_PartialRepay() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.startPrank(bob);
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);
        pool.repay("USD Coin", "Ether", 0, 5);
        vm.stopPrank();

        assertEq(pool.getReserveData("Ether").totalBorrows, 5);
        Pool.Position[] memory positions = pool.getUserPositions(bob);
        assertTrue(positions[0].scaledDebt > 0);
    }

    function testRepay_ClosesPositionOnFullRepay() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.startPrank(bob);
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);
        pool.repay("USD Coin", "Ether", 0, 10);
        vm.stopPrank();

        Pool.Position[] memory positions = pool.getUserPositions(bob);
        assertEq(positions[0].scaledDebt, 0);
    }

    function testRepay_RevertsIfWrongBorrowAsset() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.startPrank(bob);
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);
        vm.expectRevert(abi.encodeWithSelector(Pool.WrongBorrowAsset.selector, "Ether", "USD Coin"));
        pool.repay("USD Coin", "USD Coin", 0, 10);
        vm.stopPrank();
    }

    function testRepay_RevertsIfWrongCollateralAsset() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.startPrank(bob);
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);
        vm.expectRevert(abi.encodeWithSelector(Pool.WrongCollateralAsset.selector, "USD Coin", "Ether"));
        pool.repay("Ether", "Ether", 0, 10);
        vm.stopPrank();
    }

    function testRepay_RevertsIfRepayExceedsDebt() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.startPrank(bob);
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);
        vm.expectRevert(abi.encodeWithSelector(Pool.RepayExceedsDebt.selector, uint256(10), uint256(20)));
        pool.repay("USD Coin", "Ether", 0, 20);
        vm.stopPrank();
    }

    // ================================================================
    // checkPositionHealth / getHealthFactor
    // ================================================================

    function testCheckPositionHealth_HealthyPosition() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.prank(bob);
        pool.borrow("USD Coin", "Ether", 10, 0.5e18);

        assertTrue(pool.checkPositionHealth(bob, 0));
    }

    function testCheckPositionHealth_UnhealthyAfterPriceDrop() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.prank(alice);
        pool.borrow("Ether", "USD Coin", 50000, 0.05e18);

        mockEthAggregator.setAnswer(1e18);

        assertFalse(pool.checkPositionHealth(alice, 0));
    }

    function testCheckPositionHealth_RevertsIfNoDebt() public {
        _initEthReserve();
        vm.expectRevert(abi.encodeWithSelector(Pool.NoActivePosition.selector, uint256(0)));
        pool.checkPositionHealth(alice, 0);
    }

    // ================================================================
    // getUtilizationRate
    // ================================================================

    function testUtilizationRate_ZeroWhenNoDeposits() public {
        _initEthReserve();
        assertEq(pool.getUtilizationRate("Ether"), 0);
    }

    function testUtilizationRate_CorrectAfterBorrow() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 10);
        _depositUsdc(bob, 100000);

        vm.prank(bob);
        pool.borrow("USD Coin", "Ether", 5, 0.5e18);

        assertEq(pool.getUtilizationRate("Ether"), 0.5e18);
    }

    // ================================================================
    // getUserPositions
    // ================================================================

    function testGetUserPositions_EmptyIfNoPositions() public {
        _initEthReserve();
        Pool.Position[] memory positions = pool.getUserPositions(alice);
        assertEq(positions.length, 0);
    }

    function testGetUserPositions_ReturnsCorrectCount() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.startPrank(bob);
        pool.borrow("USD Coin", "Ether", 5, 0.5e18);
        pool.borrow("USD Coin", "Ether", 5, 0.5e18);
        vm.stopPrank();

        Pool.Position[] memory positions = pool.getUserPositions(bob);
        assertEq(positions.length, 2);
    }

    // ================================================================
    // Index accrual over time
    // ================================================================

    function testIndexAccruesOverTime() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.prank(bob);
        pool.borrow("USD Coin", "Ether", 5, 0.5e18);

        uint256 indexBefore = pool.getReserveData("Ether").borrowLiquidityIndex;

        vm.warp(block.timestamp + 365 days);
        _depositEth(alice, 1);

        uint256 indexAfter = pool.getReserveData("Ether").borrowLiquidityIndex;
        assertTrue(indexAfter > indexBefore);
    }

    function testDebtGrowsWithInterest() public {
        _initEthReserve();
        _initUsdcReserve();
        _depositEth(alice, 100000);
        _depositUsdc(bob, 100000);

        vm.prank(alice);
        pool.borrow("Ether", "USD Coin", 50000, 0.5e18);

        uint256 debtBefore = pool.getUserBorrowBalance("USD Coin", alice);

        vm.warp(block.timestamp + 365 days);
        vm.prank(bob);
        pool.deposit("USD Coin", 1);

        uint256 debtAfter = pool.getUserBorrowBalance("USD Coin", alice);
        console.log(debtAfter);
        console.log(debtBefore);
        assertTrue(debtAfter > debtBefore);
    }
}
