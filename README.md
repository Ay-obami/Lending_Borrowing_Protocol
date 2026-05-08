# Lending & Borrowing Protocol

A production-grade DeFi lending protocol built with Solidity and Foundry. The protocol supports multi-reserve collateralized borrowing, a kinked two-slope interest rate model, real-time liquidity index accrual, health factor-based liquidations, and a verifying paymaster for ERC-4337 gasless transactions.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Contract Breakdown](#contract-breakdown)
- [Core Concepts](#core-concepts)
  - [Scaled Balances & Liquidity Indexes](#scaled-balances--liquidity-indexes)
  - [Interest Rate Model](#interest-rate-model)
  - [Collateral & LTV](#collateral--ltv)
  - [Health Factor & Liquidation](#health-factor--liquidation)
  - [Buffer Percent](#buffer-percent)
- [Reserve Parameters](#reserve-parameters)
- [User Flows](#user-flows)
- [Events](#events)
- [Custom Errors](#custom-errors)
- [ERC-4337 Paymaster](#erc-4337-paymaster)
- [Getting Started](#getting-started)
- [Running Tests](#running-tests)
- [CI/CD](#cicd)
- [Known Limitations & Future Work](#known-limitations--future-work)

---

## Overview

The protocol operates around **reserves** — named pools of ERC-20 tokens, each with independently configured interest rate parameters, caps, and price feeds. Users can:

- **Deposit** tokens into a reserve to earn yield (interest accrues via a growing supply index)
- **Borrow** a different asset by locking collateral from a reserve they've deposited into
- **Repay** debt partially or fully, releasing collateral proportionally
- **Liquidate** undercollateralized positions by repaying their debt and receiving their locked collateral

Each borrow creates an isolated **Position** tracked by ID, making multi-position management straightforward.

---

## Architecture

```
src/
├── core/
│   ├── Pool.sol               ← Main entry point: deposit, withdraw, borrow, repay, liquidate
│   ├── InterestCalculator.sol ← Kinked two-slope rate model + liquidity index math
│   └── PriceFeeds.sol         ← Chainlink AggregatorV3 wrapper
├── AAHandler/
│   └── Paymaster.sol          ← ERC-4337 verifying paymaster for gasless transactions
└── CrosschainHandler/
    ├── CrosschainSender.sol    ← Chainlink CCIP outbound (in progress)
    └── CrosschainReciever.sol  ← Chainlink CCIP inbound (in progress)

test/
├── pool.t.sol                 ← Full Foundry test suite
└── Mocks/
    ├── MockAggregator.sol     ← Configurable mock price feed
    └── MockERC20.sol          ← Mintable test token
```

---

## Contract Breakdown

### `Pool.sol`

The core contract. Inherits `Ownable` and `ReentrancyGuard`. All user-facing and admin functions live here.

**Admin functions** (owner only):
| Function | Description |
|----------|-------------|
| `instantiateNewReserveData(...)` | Adds a new reserve with full parameter configuration |
| `setReserveActive(name, bool)` | Pauses or unpauses a reserve |
| `setReserveBorrowable(name, bool)` | Toggles whether an asset can be borrowed |

**User functions:**
| Function | Description |
|----------|-------------|
| `deposit(reserveName, amount)` | Deposits ERC-20 into a reserve; receives a scaled balance |
| `withdraw(reserveName, amount)` | Withdraws from a reserve, checking liquidity and user balance |
| `borrow(collateral, borrowAsset, amount, bufferPercent)` | Locks collateral and borrows an asset |
| `repay(collateral, borrowAsset, positionId, repayAmount)` | Repays debt and releases proportional collateral |
| `liquidate(user, positionId)` | Liquidates an unhealthy position |

**View functions:**
| Function | Description |
|----------|-------------|
| `getUserDepositBalance(reserve, user)` | Returns the current (index-adjusted) deposit balance |
| `getUserBorrowBalance(reserve, user)` | Returns the current (index-adjusted) borrow balance |
| `getUtilizationRate(reserve)` | Returns current utilization as a RAY-scaled value |
| `checkPositionHealth(user, positionId)` | Returns `true` if health factor ≥ 1 |
| `getUserPositions(user)` | Returns all positions for a user |
| `getReserveData(reserve)` | Returns full `ReserveData` struct |

---

### `InterestCalculator.sol`

Deployed twice by `Pool` — once for supply (with reserve factor applied) and once for borrowing.

```
getCurrentInterestRate(utilizationRate, slope1, slope2, baseRate, optimalUtil, reserveFactor)
computeUpdatedLiquidityIndex(currentIndex, utilizationRate, timeElapsed, ...)
```

The rate model is kinked at `optimalUtilization`:
- **Below optimal:** `rate = baseRate + (utilization / optimalUtil) × slope1`
- **Above optimal:** `rate = baseRate + slope1 + (excessUtil / remainingUtil) × slope2`

Supply rate additionally scales by utilization and nets out the reserve factor:
```
supplyRate = borrowRate × utilization × (1 − reserveFactor)
```

### `PriceFeeds.sol`

Thin wrapper around Chainlink's `AggregatorV3Interface`. Used by `Pool` to fetch asset prices via `latestRoundData()`.

### `Paymaster.sol`

An ERC-4337 verifying paymaster that sponsors user operations. It:
- Parses a `validUntil` / `validAfter` time window and a 65-byte ECDSA signature from `paymasterAndData`
- Recovers the signer and validates it against `verifyingSigner`
- Emits `UserOperationSponsored` on successful post-op
- Auto-deposits received ETH into the ERC-4337 EntryPoint
- Uses `Ownable2Step` for safe ownership transfer; `renounceOwnership` is permanently disabled

---

## Core Concepts

### Scaled Balances & Liquidity Indexes

Rather than storing raw token amounts, the protocol stores **scaled balances** — amounts divided by the current liquidity index at the time of deposit or borrow. This design means interest accrues passively: the index grows over time, and a user's actual balance is always `scaledBalance × currentIndex / RAY`.

Two separate indexes are maintained per reserve:
- **`supplyLiquidityIndex`** — grows at the supply interest rate (net of reserve factor)
- **`borrowLiquidityIndex`** — grows at the borrow interest rate

Both are updated at the start of every state-changing operation via `_updateLiquidityIndexes`.

```
actualBalance = scaledBalance × liquidityIndex / RAY
scaledAmount  = rawAmount × RAY / liquidityIndex
```

### Interest Rate Model

The protocol uses a **kinked two-slope model** inspired by Aave:

```
                slope2
               /
  slope1      /
  ───────────/
            ^
       optimalUtilization
```

Low utilization → low rates to attract capital. High utilization → rates spike sharply to incentivize repayments and new deposits.

All rates are RAY-scaled (1e18 = 100%).

### Collateral & LTV

Each reserve has two thresholds:
- **`ltv`** (Loan-to-Value) — the maximum borrow amount relative to collateral value. Used at borrow time to compute required collateral.
- **`liquidationThreshold`** — the threshold used to compute the health factor. Always > LTV, providing a safety buffer.

`ltv` must be strictly less than `liquidationThreshold` — enforced at reserve initialization.

### Health Factor & Liquidation

```
healthFactor = (collateralValue × liquidationThreshold) / debtValue
```

A position is **healthy** if `healthFactor ≥ 1 (RAY)`. When it drops below 1 due to price movement or interest accrual, any address can liquidate it by calling `liquidate(user, positionId)`.

The liquidator repays the full debt and receives all locked collateral in return.

### Buffer Percent

When borrowing, users specify a `bufferPercent` (between 5% and 100%). This extra collateral margin above the minimum required by LTV gives the user breathing room before their position becomes liquidatable.

```
collateralToLock = minimumCollateral × (1 + bufferPercent)
```

---

## Reserve Parameters

| Parameter | Description |
|-----------|-------------|
| `ltv` | Max borrow ratio (e.g. 0.8e18 = 80%) |
| `liquidationThreshold` | Health factor threshold (e.g. 0.9e18 = 90%) |
| `slope1` | Rate slope below optimal utilization |
| `slope2` | Rate slope above optimal utilization (steep) |
| `baseInterestRate` | Minimum rate at zero utilization |
| `optimalUtilization` | Target utilization kink point |
| `liquidationBonus` | Extra incentive paid to liquidators (stored, not yet applied) |
| `reserveFactor` | Protocol fee cut from supply interest |
| `borrowCap` | Maximum total borrows for the reserve |
| `supplyCap` | Maximum total deposits for the reserve |
| `isActive` | Whether the reserve accepts deposits/borrows |
| `isBorrowable` | Whether the asset can be borrowed (can be supply-only) |

Constants (protocol-wide):

| Constant | Value | Meaning |
|----------|-------|---------|
| `RAY` | `1e18` | Precision unit (100%) |
| `MIN_BUFFER` | `0.05e18` | Minimum user buffer (5%) |
| `MAX_BUFFER` | `1e18` | Maximum user buffer (100%) |
| `MAX_UTILIZATION` | `0.95e18` | Pool utilization hard cap (95%) |

---

## User Flows

### Deposit

```
User approves Pool to spend token
  → Pool.deposit(reserveName, amount)
    → _updateLiquidityIndexes
    → safeTransferFrom user → pool
    → scaledAmount = amount × RAY / supplyLiquidityIndex
    → userScaledDeposits[user][reserve] += scaledAmount
    → emit Deposit
```

### Borrow

```
User has deposited collateral
  → Pool.borrow(collateral, borrowAsset, amount, bufferPercent)
    → validate: isBorrowable, bufferPercent, borrowCap, maxUtilization
    → compute collateralToLock using oracle prices + LTV + bufferPercent
    → deduct collateral from user's scaled deposit balance
    → create Position with scaledDebt + collateralLocked
    → totalBorrows += amount
    → emit Borrow
```

### Repay

```
User calls Pool.repay(collateral, borrowAsset, positionId, repayAmount)
  → validate position exists and assets match
  → currentDebt = scaledDebt × borrowLiquidityIndex / RAY
  → collateralToRelease = collateralLocked × repayAmount / currentDebt
  → scaledRepay = repayAmount × RAY / borrowLiquidityIndex
  → update position, restore collateral to user's scaled deposits
  → totalBorrows -= repayAmount
  → delete position if fully repaid
  → emit Repay
```

### Liquidate

```
Any caller → Pool.liquidate(user, positionId)
  → checkPositionHealth → revert if healthy
  → _updateLiquidityIndexes for both reserves
  → liquidator sends rawDebt tokens to pool
  → pool transfers rawCollateral tokens to liquidator
  → position deleted, accounting updated
  → emit Liquidated
```

---

## Events

| Event | Trigger |
|-------|---------|
| `ReserveInitialized` | New reserve created |
| `ReserveStatusUpdated` | Reserve paused/unpaused |
| `ReserveBorrowStatusUpdated` | Borrow flag toggled |
| `Deposit` | User deposited |
| `Withdraw` | User withdrew |
| `Borrow` | Position opened |
| `Repay` | Debt repaid (partial or full) |
| `Liquidated` | Position liquidated |
| `LiquidityIndexUpdated` | Indexes updated (on every interaction) |

---

## Custom Errors

The protocol uses named custom errors throughout for gas efficiency and clear revert messages:

`ReserveAlreadyExists` · `ReserveDoesNotExist` · `ReserveNotActive` · `OptimalUtilizationCannotBeZero` · `OptimalUtilizationExceeds100` · `ReserveFactorExceeds100` · `BaseRateExceeds100` · `SupplyCapExceeded` · `BorrowCapExceeded` · `MaxUtilizationExceeded` · `AssetNotBorrowable` · `BufferTooLow` · `BufferTooHigh` · `InsufficientFreeCollateral` · `InsufficientPoolLiquidity` · `InsufficientUserBalance` · `WrongBorrowAsset` · `WrongCollateralAsset` · `NoDebtOnPosition` · `NoActivePosition` · `RepayExceedsDebt` · `PositionIsHealthy` · `InvalidPrice` · `ZeroAmount` · `ZeroAddress` · `InvalidLTV`

---

## ERC-4337 Paymaster

`Paymaster.sol` enables gasless onboarding by sponsoring user operations on behalf of the protocol. It implements ERC-4337's `BasePaymaster` interface.

**How it works:**
1. An off-chain signer (controlled by the protocol) signs a hash of the `UserOperation` plus a validity window (`validUntil`, `validAfter`)
2. This signature is packed into `paymasterAndData` alongside the time bounds
3. On-chain, `_validatePaymasterUserOp` recovers the signer and checks it matches `verifyingSigner`
4. If valid, the EntryPoint deducts gas from the paymaster's deposited ETH balance

**Key functions:**

| Function | Description |
|----------|-------------|
| `setVerifyingSigner(address)` | Updates the authorized signer (owner only) |
| `parsePaymasterData(bytes)` | Decodes validUntil, validAfter, and signature |
| `getHash(userOp, data)` | Returns the hash the signer must sign |
| `receive()` | Auto-deposits incoming ETH into the EntryPoint |

---

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Install

```bash
git clone https://github.com/Ay-obami/Lending_Borrowing_Protocol.git
cd Lending_Borrowing_Protocol
forge install
```

### Build

```bash
forge build --sizes
```

### Dependencies (via remappings)

- `@openzeppelin/contracts` — ReentrancyGuard, Ownable, SafeERC20, ECDSA
- `@chainlink/contracts` — AggregatorV3Interface
- `@account-abstraction` — BasePaymaster, IEntryPoint, PackedUserOperation

---

## Running Tests

```bash
forge test -vvv
```

The test suite (`test/pool.t.sol`) covers:

**Reserve initialization:**
- Correct state after initialization
- Reverts on duplicate reserve
- Reverts on zero / out-of-range optimal utilization
- Access control (non-owner cannot initialize)

**Deposit:**
- Basic deposit and scaled balance correctness
- Multi-user deposits
- Supply cap enforcement
- Inactive reserve revert

**Withdraw:**
- Partial and full withdrawals
- Token transfer verification
- Insufficient liquidity revert (when borrows reduce available liquidity)
- Insufficient user balance revert

**Borrow:**
- Basic borrow and collateral lock
- Position creation and multi-position tracking
- Reverts for non-borrowable asset, buffer too low/high, borrow cap, max utilization, insufficient collateral

**Repay:**
- Full and partial repayment
- Collateral release proportional to repayment
- Position closure on full repayment
- Reverts for wrong assets and repay exceeding debt

**Health factor & liquidation:**
- Healthy position check
- Position becomes unhealthy after oracle price drop (via `mockAggregator.setAnswer`)
- Revert on no active position

**Interest accrual:**
- Borrow liquidity index grows over time (`vm.warp`)
- User debt increases after time passes

### Utilities

```bash
forge snapshot        # gas benchmarks
forge fmt --check     # formatting lint
```

---

## CI/CD

GitHub Actions runs on every push and pull request:

1. Checkout with submodules
2. Install Foundry
3. `forge fmt --check`
4. `forge build --sizes`
5. `forge test -vvv`

---

## Known Limitations & Future Work

- **Crosschain handlers are stubs.** `CrosschainSender.sol` and `CrosschainReciever.sol` are empty contracts — Chainlink CCIP integration is planned but not yet implemented.
- **No partial liquidation.** The current implementation liquidates the entire position. Protocols like Aave allow partial liquidations to minimize borrower losses.
- **`PriceFeeds.sol` is imported from the test mock path** (`test/Mocks/MockAggregator.sol`) in `Pool.sol`. The production version should import from `src/core/PriceFeeds.sol` and use live Chainlink feeds.
- **`getUserBorrowBalance` is not `view`.** It calls `_updateLiquidityIndexes` which writes state. This is a correctness trade-off (returns the up-to-date balance) but prevents use in off-chain static calls without workarounds.
