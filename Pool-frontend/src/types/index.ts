// ─── On-chain raw structs (bigint from contract) ───────────────────────────

export interface RawReserveData {
  totalDeposits: bigint
  totalBorrows: bigint
  supplyLiquidityIndex: bigint
  borrowLiquidityIndex: bigint
  lastUpdateTimestamp: bigint
  liquidationThreshold: bigint
  ltv: bigint
  slope1: bigint
  slope2: bigint
  baseInterestRate: bigint
  optimalUtilization: bigint
  liquidationBonus: bigint
  reserveFactor: bigint
  borrowCap: bigint
  supplyCap: bigint
  priceFeed: `0x${string}`
  tokenAddress: `0x${string}`
  isActive: boolean
  isBorrowable: boolean
  reserveName: string
}

export interface RawPosition {
  collateralAsset: string
  collateralAssetPriceFeed: `0x${string}`
  borrowAsset: string
  borrowAssetPriceFeed: `0x${string}`
  scaledDebt: bigint
  collateralLocked: bigint
  bufferPercent: bigint
}

// ─── Human-readable UI models ──────────────────────────────────────────────

export interface ReserveInfo {
  name: string
  tokenAddress: `0x${string}`
  priceFeed: `0x${string}`
  totalDeposits: number       // real value, human-readable
  totalBorrows: number        // real value, human-readable
  utilizationRate: number     // 0–1
  supplyAPY: number           // 0–1 (e.g. 0.05 = 5%)
  borrowAPY: number           // 0–1
  liquidationThreshold: number
  ltv: number
  liquidationBonus: number
  reserveFactor: number
  borrowCap: number
  supplyCap: number
  optimalUtilization: number
  isActive: boolean
  isBorrowable: boolean
}

export interface PositionInfo {
  id: number
  collateralAsset: string
  borrowAsset: string
  realDebt: number            // scaledDebt × borrowLiquidityIndex / RAY
  collateralLocked: number    // static, no transform
  bufferPercent: number
  // populated from reserve:
  borrowAPY: number
  // lazy-loaded:
  healthFactor?: number
}

export type RiskLevel = 'healthy' | 'warning' | 'danger'

export interface TransactionState {
  status: 'idle' | 'simulating' | 'pending' | 'confirming' | 'success' | 'error'
  message?: string
  txHash?: `0x${string}`
}
