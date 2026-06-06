# Lending & Borrowing Protocol

Monorepo — Foundry contracts + React frontend as separate workspaces.

```
lending-protocol/
├── contracts/          ← Foundry project
│   ├── src/
│   │   ├── interfaces/         IPool, IInterestStrategy, IPriceOracle
│   │   ├── libraries/          DataTypes, MathLib, ReserveLib
│   │   ├── modules/            Pool (facade), SupplyModule, BorrowModule,
│   │   │                       LiquidationModule, PoolStorage,
│   │   │                       VariableInterestStrategy
│   │   └── oracle/             ChainlinkOracle
│   ├── test/
│   │   ├── mocks/              MockERC20, MockOracle
│   │   └── unit/               PoolTestBase, SupplyModule.t.sol,
│   │                           BorrowModule.t.sol, LiquidationModule.t.sol
│   └── scripts/
│       └── Deploy.s.sol
└── frontend/           ← Vite + React + wagmi
    └── src/
        ├── lib/
        │   ├── abi.ts          Updated ABI (bytes32 IDs, new struct shapes)
        │   ├── reserveId.ts    keccak256 helpers matching Pool.getReserveId()
        │   └── wagmi.ts
        ├── services/
        │   └── poolService.ts  All contract calls (bytes32-aware)
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
# Local node
anvil &
forge script scripts/Deploy.s.sol --rpc-url localhost --broadcast
```

### Frontend

```bash
cd frontend
cp .env.example .env   # fill in VITE_POOL_ADDRESS etc.
npm install
npm run dev
```

## Architecture

The monolithic `Pool.sol` has been split into focused modules:

| Module | Responsibility |
|---|---|
| `PoolStorage` | All storage slots + shared getters — no business logic |
| `SupplyModule` | `deposit` / `withdraw` |
| `BorrowModule` | `borrow` / `repay` |
| `LiquidationModule` | `liquidate` / `checkPositionHealth` |
| `Pool` | Thin facade — routes calls, owns `addReserve` and admin |
| `VariableInterestStrategy` | Two-slope interest model (swappable per reserve) |
| `ChainlinkOracle` | Production price oracle with decimal normalisation |

## Bug fixes from original

| Bug | Fix |
|---|---|
| `Pool.sol` imported oracle from `test/Mocks/` | Proper `ChainlinkOracle` in `src/oracle/` |
| Chainlink 8-decimal price used as RAY (1e18) | `MathLib.chainlinkToRay()` normalises correctly |
| `liquidationBonus` stored but never applied | `LiquidationModule` applies bonus to seized collateral |
| `getUserBorrowBalance` mutated state | Pure `view` — reads index without writing |
| Supply cap checked before index update | `updateIndexes()` called first in `deposit()` |
| Closed positions left empty slots in array | `getUserPositions` filters `isOpen == false` |
| String reserve keys on every call | `bytes32` IDs computed once with `keccak256` |
