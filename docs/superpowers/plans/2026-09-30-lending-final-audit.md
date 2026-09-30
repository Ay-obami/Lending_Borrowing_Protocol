# Lending Final Audit Implementation Plan

> **For agentic workers:** Use executing-plans for implementation and independent code review before merge. Track the checks below through completion.

**Goal:** Close the remaining scoped source, testing, integration and portfolio tasks for the two lending repositories in one run.

**Architecture:** Maintain the shared lending core in Lending_Borrowing_Protocol. Apply shared fixes to Undertow while retaining its Flare experiments behind an explicit research boundary. Use additive getters to keep existing tuples and action selectors stable.

**Tech Stack:** Solidity ^0.8.20, Foundry v1.8.3, pinned OpenZeppelin/Chainlink/account-abstraction dependencies, React, wagmi/viem and Vite.

**Spec:** User instruction to finish all remaining lending-protocol tasks; existing contracts/accounting policy documents and audit roadmap.

## Constraints

- Regression evidence before production fixes; full local suites and fresh-runner CI before merge.
- No deployment or existing-pool storage migration; new source requires a fresh deployment.
- Keep exact-receipt token assumptions; do not claim arbitrary token or economic solvency certification.
- Preserve original position slots and existing returned tuple layouts.
- Keep self-reported ZK and callback-only paymaster prototypes outside supported deployments.

## Review focus

- Mixed native token decimals must value debt and collateral consistently.
- Oracle freshness and normalization must fail closed, including zero-normalized prices.
- Filtered open positions must retain their original IDs in the client.
- Accounting checks must cover actual successful action sequences and index phases.
- Deeply underwater collateral must not be described as guaranteed liquidatable or insured.

## Tasks

- [x] Reproduce native-decimal valuation, stable-ID getter, configuration and overflow failures in FinalAuditRegressions.t.sol; run unchanged contracts.
- [x] Add token-decimal metadata/getter, native-unit valuation, full-precision nearest arithmetic, valid reserve risk bounds and unique-token registration.
- [x] Reproduce and fix adapter zero-normalization, timestamp and exponent boundaries in ChainlinkOracleSafety/FtsoOracleSafety.
- [x] Run stateful handler invariants with fail_on_revert enabled, verify successful action counters and rollback; add varied-index lifecycle fuzz tests.
- [x] Verify paused repayment/withdrawal behavior and full-debt liquidation economics; document unsupported insolvency/loss-waterfall scope explicitly.
- [x] Add stable getUserPositionIds getter; fix ABI, native parsing/formatting, receipt/network/address checks and restore missing Lending client modules.
- [x] Add production client builds/tests to CI; smoke-test local deployed lifecycle and an opt-in pinned-block integration without secrets.
- [x] Choose canonical repository, refresh architecture/claims/deployment docs, gate experimental account-layer deployment.
- [x] Independently review final changed source and tests; compare published blobs; pass full CI; merge and update final audit evidence (final merge checkpoint pending until recorded below).
