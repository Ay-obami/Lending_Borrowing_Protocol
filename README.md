# Modular Lending & Borrowing Protocol

Solidity lending core with supply, withdrawal, collateralized borrowing, repayment, full-debt liquidation, Chainlink pricing and a React/wagmi client.

This is the canonical shared-core repository. [Undertow](https://github.com/Ay-obami/Undertow) maintains the Flare/Coston2 integration and separate research experiments. Shared fixes are ported explicitly; both repositories remain public.

## Engineering evidence

- Native token precision (0–18 decimals), with debt, collateral, caps and transfers expressed in native units.
- Scaled deposit/debt aggregates, directional token-boundary rounding and full-precision nearest arithmetic.
- Exact incoming token receipts and one shared guard across all five user actions.
- Fixed locked collateral protected from other loans and withdrawals.
- Chainlink stale, incomplete, future, exponent and zero-normalization checks.
- Stable position IDs, live debt views and a frontend that verifies confirmed full repayment.
- Unit, fuzz, action-sequence invariant, varied-index lifecycle and opt-in real-token fork tests.
- CI gates contract formatting/build/tests and frontend tests/production build.

This is a tested engineering portfolio implementation, not an independently audited production lending market. See [policy and limitations](contracts/LENDING_POLICY.md), [rounding](contracts/DIRECTIONAL_ROUNDING.md), [oracle checks](contracts/ORACLE_VALIDATION.md) and [integration instructions](contracts/FORK_VALIDATION.md).

## Architecture

| Module | Responsibility |
|---|---|
| Pool | Guarded action facade, owner configuration, reserve and position views |
| PoolStorage | Scaled aggregate ledgers, fixed collateral custody, token precision |
| SupplyModule | Deposit credit and free-cash withdrawals |
| BorrowModule | Native valuation, collateral locks, debt issuance and repayment |
| LiquidationModule | Accrued health, full-debt collection and underlying collateral delivery |
| VariableInterestStrategy | Two-slope annualized rates with linear index accrual |
| ChainlinkOracle | Normalized prices and feed freshness checks |

Prices and indexes use this project's historical `RAY = 1e18`. Locked collateral does not earn supply interest. Deeply underwater liquidation can be uneconomic because the liquidator must pay the full debt; no insurance or loss waterfall is implemented.

## Reproduce

Install Foundry v1.8.3 and Node 24:

```bash
git submodule update --init --recursive
cd contracts
forge fmt --check
forge build --sizes
FOUNDRY_PROFILE=ci forge test -vvv
cd ../frontend
npm ci
npm test
npm run build
```

The CI profile runs 1,000 fuzz cases and 128 invariant runs at depth 128 with unexpected handler reverts treated as failures. Fork tests explicitly skip when `LENDING_FORK_RPC_URL` is absent; see the integration document for the pinned block and a separate invocation.

## Local development

Run Anvil, then simulate/broadcast `contracts/scripts/Deploy.s.sol` with an unlocked local account or your normal Foundry signer configuration. Its default is a mock-token/mock-price development deployment. Configure the resulting pool address and chain in `frontend/.env` using `.env.example`, then run `npm run dev`. The client stays disabled until a valid deployment is configured.

Use a fresh deployment for this revision. Existing addresses do not gain source changes, and populated-pool migration is not supplied. No public-network deployment is claimed. See [frontend setup](frontend/README.md).
