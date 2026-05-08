import { useReadContract, useReadContracts } from 'wagmi'
import { POOL_ABI } from '../lib/abi'
import { POOL_ADDRESS } from '../lib/wagmi'
import { RAY } from '../lib/math'

export function useHealthFactor(
  user: `0x${string}` | undefined,
  positionId: number,
  enabled = false,
) {
  const { data: positions } = useReadContract({
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'getUserPositions',
    args: user ? [user] : undefined,
    query: {
      enabled: !!user && enabled,
      staleTime: 15_000,
    },
  })

  const position = (positions as Array<{
    collateralAsset: string
    borrowAsset: string
    scaledDebt: bigint
    collateralLocked: bigint
  }> | undefined)?.[positionId]

  const hasPosition = !!position && position.scaledDebt > 0n

  const { data: reserveResults } = useReadContracts({
    contracts: [
      {
        address: POOL_ADDRESS,
        abi: POOL_ABI,
        functionName: 'getReserveData',
        args: position ? [position.collateralAsset] : [''],
      },
      {
        address: POOL_ADDRESS,
        abi: POOL_ABI,
        functionName: 'getReserveData',
        args: position ? [position.borrowAsset] : [''],
      },
    ],
    query: {
      enabled: hasPosition && enabled,
      staleTime: 15_000,
    },
  })

  const collateralReserve = reserveResults?.[0]?.result as
    | { liquidationThreshold: bigint; supplyLiquidityIndex: bigint }
    | undefined

  const borrowReserve = reserveResults?.[1]?.result as
    | { borrowLiquidityIndex: bigint }
    | undefined

  const isLoading = enabled && !!user && hasPosition && (!collateralReserve || !borrowReserve)

  let healthFactor: number | undefined

  if (position && collateralReserve && borrowReserve) {
    if (position.scaledDebt === 0n) {
      healthFactor = Infinity
    } else {
      const adjustedCollateral =
        (position.collateralLocked * collateralReserve.liquidationThreshold) / RAY
      const realDebt = (position.scaledDebt * borrowReserve.borrowLiquidityIndex) / RAY
      if (realDebt === 0n) {
        healthFactor = Infinity
      } else {
        const hfRay = (adjustedCollateral * RAY) / realDebt
        healthFactor = Number(hfRay) / 1e18
      }
    }
  }

  return { data: healthFactor, isLoading }
}
