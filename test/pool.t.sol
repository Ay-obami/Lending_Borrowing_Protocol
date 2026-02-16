// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

// Import contracts
import {Pool} from "src/core/Pool.sol";
import {CollateralManager} from "src/core/CollateralManager.sol";
import {Vusdt} from "src/core/Vtokens/VUsdt.sol";
import {Vbtc} from "src/core/Vtokens/VBtc.sol";
import {Veth} from "src/core/Vtokens/VEth.sol";
import {Dusdt} from "src/core/Vtokens/DUsdt.sol";

//Mocks
import {MockERC20} from "test/Mocks/MockERC20.sol";
import {MockAggregator} from "test/Mocks/MockAggregator.sol";

contract PoolTest is Test {
    // Contracts under test
    Pool pool;
    CollateralManager manager;

    // Token contracts (either mocks locally or real token addresses on Sepolia)
    MockERC20 usdt;
    MockERC20 weth;
    MockERC20 wbtc;

    // Price feeds
    AggregatorV3Interface ethFeed;
    AggregatorV3Interface btcFeed;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address admin = address(this);

    // Sepolia chain id
    uint256 constant SEPOLIA_CHAINID = 11155111;

    // Chainlink Sepolia feed addresses (from Chainlink docs)
    // ETH/USD on Sepolia: 0x694AA1769357215DE4FAC081bf1f309aDC325306 (decimals 18)
    // BTC/USD on Sepolia: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43 (decimals 8)
    // Source: Chainlink Data Feeds docs.
    address constant SEPOLIA_ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address constant SEPOLIA_BTC_USD = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;

    function setUp() public {
        // If running on Sepolia, use the real Chainlink feeds and deploy real ERC20 test tokens if desired.
        if (block.chainid == SEPOLIA_CHAINID) {
            ethFeed = AggregatorV3Interface(SEPOLIA_ETH_USD);
            btcFeed = AggregatorV3Interface(SEPOLIA_BTC_USD);
            // For tokens on Sepolia you'll provide real token addresses when deploying in a script
            // For unit tests here we deploy simple mock ERC20s even on Sepolia (so we can mint)
            usdt = new MockERC20("Test USDT", "tUSDT");
            weth = new MockERC20("Test WETH", "tWETH");
            wbtc = new MockERC20("Test WBTC", "tWBTC");
        } else {
            // Local testing: deploy mocks
            MockAggregator ethMock = new MockAggregator(int256(3_000 * 1e18), 18); // ETH ~ $3,000 (18 decimals)
            MockAggregator btcMock = new MockAggregator(int256(40_000 * 1e8), 8); // BTC ~ $40,000 (8 decimals)
            ethFeed = AggregatorV3Interface(address(ethMock));
            btcFeed = AggregatorV3Interface(address(btcMock));
            usdt = new MockERC20("Test USDT", "tUSDT");
            weth = new MockERC20("Test WETH", "tWETH");
            wbtc = new MockERC20("Test WBTC", "tWBTC");
        }

        // Mint initial balances to test users
        usdt.mint(alice, 1000 ether);
        usdt.mint(bob, 1000 ether);
        weth.mint(bob, 1000 ether);
        weth.mint(alice, 1000 ether);
        wbtc.mint(bob, 1000 ether); // 10 WETH
        wbtc.mint(alice, 2 ether); // 2 WBTC (we'll interpret decimals later)

        // Deploy CollateralManager which extends Pool.
        // CollateralManager constructor: (address _btc, address _eth, address _usdt, address ethPriceFeed, address btcPriceFeed)
        manager = new CollateralManager(address(wbtc), address(weth), address(usdt), address(ethFeed), address(btcFeed));
        // Pool is inherited; pool state is in the same contract instance (manager).
        pool = Pool(address(manager));
    }

    /* ------------- Helpers ------------- */

    function _approveAll(address token, address ownerAddr, address spender, uint256 amt) internal {
        // For MockERC20 approve() exists as external; we need to vm.prank(ownerAddr)
        vm.prank(ownerAddr);
        MockERC20(token).approve(spender, amt);
    }

    /* ------------- Tests: Supply & V-token minting ------------- */

    function testSupplyUsdtMintsVusdtAndTransfersTokens() public {
        uint256 amt = 100 ether;

        // approve pool to take usdt from alice
        vm.prank(alice);
        usdt.approve(address(pool), amt);

        // alice supplies
        vm.prank(alice);
        pool.supplyUsdt(amt);

        // VUSDT token should have minted to alice
        Vusdt vusdt = pool.VUSDT();
        assertEq(vusdt.balanceOf(alice), amt, "VUSDT minted to supplier");

        // Pool should have USDT in its balance
        assertEq(usdt.balanceOf(address(pool)), amt, "Pool received USDT");
    }

    function testSupplyEthAndWithdraw() public {
        uint256 amt = 1 ether;

        // approve and supply ETH token
        vm.prank(alice);
        weth.approve(address(pool), amt);

        vm.prank(alice);
        pool.supplyEth(amt);

        Veth veth = pool.VETH();
        assertEq(veth.balanceOf(alice), amt, "VETH minted");

        // now withdraw
        vm.prank(alice);
        pool.withdrawEth(amt);

        assertEq(veth.balanceOf(alice), 0, "VETH burned on withdraw");
        // assertEq(weth.balanceOf(alice), 10 ether - 0, "WETH returned to alice (pool had transferred back)"); // pool initially had token balance before supply. This is a basic sanity check.
    }

    /* ------------- Tests: Borrow / Repay flows ------------- */

    function testBorrowRepayFlowHappyPath() public {
        uint256 supplyAmt = 200 ether;
        uint256 borrowAmt = 50 ether;
        uint256 repayAmt = borrowAmt;

        // Alice supplies USDT so pool has liquidity and VUSDT total supply is non-zero
        vm.prank(alice);
        usdt.approve(address(pool), supplyAmt);
        vm.prank(alice);
        pool.supplyUsdt(supplyAmt);

        // Now Bob will borrow. Bob must have some collateral locked; simulate by having alice supply ETH and then lock it for bob via manager (we'll act as bob)
        // For test, let bob supply ETH to the pool so he has balance to lock
        vm.prank(bob);
        weth.approve(address(pool), 200 ether);
        vm.prank(bob);
        pool.supplyEth(200 ether);
        uint256 healthfactor = pool.getHealthFactor(borrowAmt);
        console.log(healthfactor);
        // bob locks 150% collateral by calling manager.lockEthCollateral through manager (external)
        // Use vm.prank to indicate caller is bob
        vm.prank(bob);
        // manager.lockEthCollateral will move from balances[bob][ETH] -> lockedBalances[bob][ETH]
        manager.lockEthCollateral(100 ether, bob);

        // Now bob borrows USDT
        vm.prank(bob);
        pool.borrowUsdt(borrowAmt);

        // Pool should have transferred USDT to bob -> bob's usdt balance increased by borrowAmt
        assertEq(usdt.balanceOf(bob), borrowAmt + 1000 ether, "Borrower received usdt");

        // DUSDT should be minted to bob representing debt
        Dusdt dusdt = pool.DUSDT();
        assertEq(dusdt.balanceOf(bob), borrowAmt, "Dusdt minted as debt token");

        // Repay
        // First fund bob with enough USDT to repay (we minted borrowAmt earlier so bob already has borrowAmt)
        vm.prank(bob);
        usdt.approve(address(pool), repayAmt);
        vm.prank(bob);
        pool.payUsdt(repayAmt);

        // Loan balance should be reduced to 0
        assertEq(pool.getLoanBalance(bob), 0, "Loan balance cleared after repay");

        // DUSDT burned => dusdt balance for bob should be zero
        assertEq(dusdt.balanceOf(bob), 0, "DUSDT burned after repay");
    }

    /* ------------- Tests: Collateral manager values & price reads ------------- */

    function testGetEthPriceAndCollateralValue() public {
        // For local tests mock returns were set in setUp. Ensure getEthPrice returns something > 0
        uint256 ethPrice = manager.getEthPrice();
        assertGt(ethPrice, 0, "ETH feed gave a positive price");

        // Lock some ETH collateral for alice and confirm getEthCollateralValueInUsd reflects it
        uint256 supplyEthAmt = 1 ether;
        vm.prank(alice);
        weth.approve(address(pool), supplyEthAmt);
        vm.prank(alice);
        pool.supplyEth(supplyEthAmt);

        vm.prank(alice);
        manager.lockEthCollateral(supplyEthAmt, alice);

        uint256 valueUsd = manager.getEthCollateralValueInUsd(alice);
        assertGt(valueUsd, 0, "ETH collateral USD value positive");
    }

    /* ------------- Tests: V-token mint/burn permissions & Dusdt mint/burn ------------- */

    function testVTokensOnlyPoolCanMintBurn() public {
        // V tokens are owned by pool (constructor sets owner to pool). From test harness we are owner of mocks, but pool should still be owner.
        Vusdt vusdt = pool.VUSDT();
        Vbtc vbtc = pool.VBTC();
        Veth veth = pool.VETH();
        Dusdt dusdt = pool.DUSDT();

        // Try to mint VUSDT from non-owner should revert (we are not owner)
        vm.expectRevert(); // any revert is fine for permission check
        vusdt.mint(address(this), 1 ether);

        // But pool.supplyUsdt should mint correctly (pool is owner)
        vm.prank(alice);
        usdt.approve(address(pool), 10 ether);
        vm.prank(alice);
        pool.supplyUsdt(10 ether);
        assertEq(vusdt.balanceOf(alice), 10 ether, "VUSDT minted by pool on supply");

        // Try to call dusdt.mint directly from this test => revert
        vm.expectRevert();
        dusdt.mint(address(this), 1 ether);
    }

    /* ------------- Tests: Reverts & edge cases ------------- */

    function testRevertsOnZeroAmounts() public {
        vm.prank(alice);
        usdt.approve(address(pool), 0);

        // expecting revert due to mustBeGreaterThanZero
        vm.prank(alice);
        vm.expectRevert();
        pool.supplyUsdt(0);

        vm.prank(alice);
        vm.expectRevert();
        pool.borrowUsdt(0);

        vm.prank(alice);
        vm.expectRevert();
        pool.payUsdt(0);
    }

    function testWithdrawRequiresSufficientBalance() public {
        uint256 amt = 1 ether;

        // Bob never supplied ETH, so withdraw should revert due to balanceMustBeSufficient
        vm.prank(bob);
        vm.expectRevert();
        pool.withdrawEth(amt);
    }
}
