// ─── Constants ────────────────────────────────────────────────────────────
export const RAY = BigInt('1000000000000000000') // 1e18

// ─── BigInt → number helpers ──────────────────────────────────────────────
export function rayToNumber(value: bigint): number {
  // Convert a RAY (1e18-scaled) bigint to a floating-point ratio (0–1 range)
  return Number(value) / 1e18
}

export function toNumber(value: bigint, decimals = 18): number {
  return Number(value) / 10 ** decimals
}

// ─── Scaled balance → real balance ────────────────────────────────────────
export function scaledToReal(scaled: bigint, liquidityIndex: bigint): number {
  if (liquidityIndex === 0n) return 0
  // realBalance = scaled * liquidityIndex / RAY
  return toNumber((scaled * liquidityIndex) / RAY)
}

// ─── APY from rate model ───────────────────────────────────────────────────
/**
 * Computes the borrow APY from the two-slope interest rate model.
 * All inputs are RAY-scaled (1e18 = 100%).
 */
export function computeBorrowRate(
  utilizationRate: bigint,
  baseInterestRate: bigint,
  slope1: bigint,
  slope2: bigint,
  optimalUtilization: bigint,
): number {
  const U = utilizationRate
  const Uo = optimalUtilization

  let borrowRate: bigint
  if (U <= Uo) {
    // rate = base + slope1 * U / Uo
    borrowRate = baseInterestRate + (slope1 * U) / (Uo === 0n ? 1n : Uo)
  } else {
    // rate = base + slope1 + slope2 * (U - Uo) / (RAY - Uo)
    const excess = U - Uo
    const denom = RAY - Uo
    borrowRate = baseInterestRate + slope1 + (slope2 * excess) / (denom === 0n ? 1n : denom)
  }

  return rayToNumber(borrowRate)
}

/**
 * Computes the supply APY from the borrow rate.
 * supplyRate = borrowRate * utilizationRate * (1 - reserveFactor)
 */
export function computeSupplyRate(
  utilizationRate: bigint,
  baseInterestRate: bigint,
  slope1: bigint,
  slope2: bigint,
  optimalUtilization: bigint,
  reserveFactor: bigint,
): number {
  const U = utilizationRate
  const Uo = optimalUtilization

  let borrowRate: bigint
  if (U <= Uo) {
    borrowRate = baseInterestRate + (slope1 * U) / (Uo === 0n ? 1n : Uo)
  } else {
    const excess = U - Uo
    const denom = RAY - Uo
    borrowRate = baseInterestRate + slope1 + (slope2 * excess) / (denom === 0n ? 1n : denom)
  }

  const supplyRate = (borrowRate * U * (RAY - reserveFactor)) / RAY / RAY
  return rayToNumber(supplyRate)
}

// ─── Risk level from health factor ────────────────────────────────────────
export function getRiskLevel(healthFactor: number): 'healthy' | 'warning' | 'danger' {
  if (healthFactor >= 1.5) return 'healthy'
  if (healthFactor >= 1.1) return 'warning'
  return 'danger'
}

// ─── Formatting helpers ───────────────────────────────────────────────────
export function formatNumber(value: number, decimals = 2): string {
  if (value === 0) return '0'
  if (value < 0.01 && value > 0) return '<0.01'
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(2)}M`
  if (value >= 1_000) return `${(value / 1_000).toFixed(2)}K`
  return value.toFixed(decimals)
}

export function formatPercent(value: number, decimals = 2): string {
  return `${(value * 100).toFixed(decimals)}%`
}

export function formatHealthFactor(hf: number): string {
  if (hf >= 100) return '∞'
  return hf.toFixed(2)
}

export function shortenAddress(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`
}

// ─── Error decoding ───────────────────────────────────────────────────────
import { CUSTOM_ERRORS } from './abi'

export function decodeContractError(error: unknown): string {
  const errStr = String(error)

  // User rejection
  if (errStr.includes('User rejected') || errStr.includes('user rejected') || errStr.includes('4001')) {
    return 'Transaction cancelled by user.'
  }

  // Try to match custom error selector from the hex data
  const hexMatch = errStr.match(/0x[a-fA-F0-9]{8}/)
  if (hexMatch) {
    const selector = hexMatch[0].toLowerCase()
    if (CUSTOM_ERRORS[selector]) return CUSTOM_ERRORS[selector]
  }

  // Try to match error name patterns
  for (const [, msg] of Object.entries(CUSTOM_ERRORS)) {
    const nameMatch = errStr.match(/(\w+)\(/)
    if (nameMatch) {
      const name = nameMatch[1]
      if (errStr.includes(name)) return msg
    }
  }

  // Named error patterns
  if (errStr.includes('InsufficientFreeCollateral')) return 'Insufficient free collateral — deposit more first.'
  if (errStr.includes('BorrowCapExceeded')) return 'Borrow cap exceeded for this reserve.'
  if (errStr.includes('MaxUtilizationExceeded')) return 'Pool utilization limit reached — try a smaller amount.'
  if (errStr.includes('BufferTooLow')) return 'Buffer too low — minimum collateral buffer is 5%.'
  if (errStr.includes('RepayExceedsDebt')) return 'Repay amount exceeds your current debt.'
  if (errStr.includes('PositionIsHealthy')) return 'Position is healthy and cannot be liquidated.'
  if (errStr.includes('SupplyCapExceeded')) return 'Supply cap exceeded — pool is full.'
  if (errStr.includes('AssetNotBorrowable')) return 'This asset is not currently borrowable.'
  if (errStr.includes('InsufficientPoolLiquidity')) return 'Not enough liquidity in the pool for this withdrawal.'
  if (errStr.includes('NoDebtOnPosition')) return 'No active debt on this position.'
  if (errStr.includes('ZeroAmount')) return 'Amount cannot be zero.'

  return 'Transaction failed. Please try again.'
}
