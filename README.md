# Lending & Borrowing Protocol

**A modular DeFi lending protocol built with Solidity, Foundry, Chainlink pricing, and a React/wagmi frontend.**

The protocol supports supplying, withdrawing, collateralized borrowing, repayment, liquidation, reserve-level risk configuration, and variable interest-rate accounting. The original monolithic pool design was refactored into focused modules so accounting, risk, liquidation, storage, oracle logic, and frontend integration remain easier to reason about and test independently.

> **Supply liquidity. Borrow against collateral. Accrue interest. Liquidate unhealthy positions.**

## Project snapshot

- **Solidity + Foundry** smart-contract stack
- **Modular pool architecture** with separate supply, borrow/repay, liquidation and storage responsibilities
- **Chainlink oracle integration** with explicit decimal normalization
- **Two-slope variable interest-rate strategy** per reserve
- **Collateral and health checks** for borrow eligibility and liquidation
- **Liquidation bonus handling** for seized collateral
- **Reserve supply/borrow caps** and configurable risk parameters
- **`bytes32` reserve IDs** derived once with `keccak256`
- **Read-only balance getters** that do not mutate indexes
- **React + wagmi frontend** with contract calls centralized through a service layer
- **Foundry unit tests** across pool, supply, borrow, liquidation, math, and interest-rate behavior
- **GitHub Actions CI** for the contract test suite

## Why this project matters

Lending protocols concentrate risk in accounting, oracle normalization, collateral checks, interest indexes, and liquidation logic. Small mistakes in any of those areas can distort balances or create unsafe borrowing conditions.

This project focuses on those failure-prone boundaries rather than treating lending as a single `deposit()` / `borrow()` contract. The codebase is split into modules with shared storage and explicit interfaces, making state transitions and risk logic easier to test and review.

## Architecture

```text
                           React / wagmi frontend
                                   │
                                   ▼
                              Pool facade
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
              ▼                    ▼                    ▼
        SupplyModule          BorrowModule      LiquidationModule
      deposit / withdraw     borrow / repay     health / liquidate
              │                    │                    │
              └────────────────────┼────────────────────┘
                                   ▼
                              PoolStorage
                                   │
                  ┌────────────────┴────────────────┐
                  ▼                                 ▼
        VariableInterestStrategy              ChainlinkOracle
           utilization / rates              normalized prices
```

### Contract modules

| Module | Responsibility |
| --- | --- |
| `PoolStorage` | Shared reserve, position, balance and protocol state |
| `SupplyModule` | `deposit` / `withdraw` flows and supply accounting |
| `BorrowModule` | `borrow` / `repay`, debt accounting and collateral validation |
| `LiquidationModule` | Position health checks and collateral liquidation |
| `Pool` | Thin facade plus reserve/admin configuration |
| `VariableInterestStrategy` | Two-slope utilization-based interest model |
| `ChainlinkOracle` | Price-feed adapter with decimal normalization |

## Core DeFi flows

### Supply

```text
User deposit
    ↓
Update reserve indexes
    ↓
Check supply cap
    ↓
Transfer asset into pool
    ↓
Credit scaled deposit balance
```

### Borrow

```text
Borrow request
    ↓
Read normalized collateral / debt values
    ↓
Check LTV + reserve limits
    ↓
Create/update debt position
    ↓
Transfer borrowed asset
```

### Liquidation

```text
Position becomes unhealthy
    ↓
Liquidator repays eligible debt
    ↓
Oracle values collateral
    ↓
Liquidation bonus applied
    ↓
Collateral transferred to liquidator
    ↓
Position/accounting updated
```

## Security & correctness improvements

The refactor also addressed several concrete correctness issues from the earlier implementation:

| Issue | Improvement |
| --- | --- |
| Production pool imported an oracle from `test/Mocks/` | Added a production `ChainlinkOracle` under `src/oracle/` |
| Chainlink 8-decimal prices were consumed as 1e18 values | Added `MathLib.chainlinkToRay()` normalization |
| `liquidationBonus` existed but was not applied | Liquidation logic now applies the configured bonus to seized collateral |
| `getUserBorrowBalance` changed protocol state | Getter is read-only and derives the current balance without writing |
| Supply cap was checked before index synchronization | Reserve indexes are updated before cap enforcement |
| Closed positions remained as empty array entries | `getUserPositions` filters closed positions |
| Reserve names were passed as strings throughout hot paths | Reserves use deterministic `bytes32` IDs derived with `keccak256` |

## Testing

The Foundry unit suite is organized around the protocol's core risk and accounting surfaces:

```text
contracts/test/unit/
├── Pool.t.sol
├── SupplyModule.t.sol
├── BorrowModule.t.sol
├── LiquidationModule.t.sol
├── VariableInterestStrategy.t.sol
├── MathLib.t.sol
└── PoolTestBase.sol
```

Install Foundry v1.8.3 (the CI version), then initialize the pinned dependencies and run the suite:

```bash
git submodule update --init --recursive
cd contracts
forge fmt --check
forge build
forge test -vvv
```

GitHub Actions runs the contract test workflow from `.github/workflows/test.yml`.

## Repository layout

```text
lending-protocol/
├── contracts/
│   ├── src/
│   │   ├── interfaces/      IPool, IInterestStrategy, IPriceOracle
│   │   ├── libraries/       DataTypes, MathLib, ReserveLib
│   │   ├── modules/         Pool, PoolStorage, SupplyModule,
│   │   │                    BorrowModule, LiquidationModule,
│   │   │                    VariableInterestStrategy
│   │   └── oracle/          ChainlinkOracle
│   ├── test/
│   │   ├── mocks/
│   │   └── unit/
│   └── scripts/
│       └── Deploy.s.sol
└── frontend/
    └── src/
        ├── lib/
        │   ├── abi.ts
        │   ├── reserveId.ts
        │   └── wagmi.ts
        ├── services/
        │   └── poolService.ts
        ├── hooks/
        ├── pages/
        └── types/
```

## Quick start

### Contracts

```bash
cd contracts
forge build
forge test

# Local network
anvil

# In a second terminal
forge script scripts/Deploy.s.sol --rpc-url localhost --broadcast
```

### Frontend

```bash
cd frontend
cp .env.example .env
npm install
npm run dev
```

Populate the frontend environment with the deployed pool address and network configuration before starting the application.

## Frontend integration

The frontend keeps protocol calls behind `poolService.ts` and uses shared ABI/type helpers rather than scattering contract interaction logic across UI components.

Key integration details include:

- `wagmi` wallet and network configuration
- `bytes32` reserve-ID helpers that match `Pool.getReserveId()`
- centralized pool reads/writes
- reserve and user-position views
- supply, withdraw, borrow, repay and liquidation-facing contract flows

## Scope

This repository is a DeFi protocol engineering project and should not be interpreted as an audited production lending market. Mainnet deployment would require additional independent security review, broader fuzz/invariant coverage, governance design, oracle-failure handling, and production risk-parameter validation.
