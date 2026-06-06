/**
 * Contract service layer — ALL contract interactions live here.
 * Components NEVER import from this file directly.
 * Hooks consume this service.
 */

import {
  readContract,
  simulateContract,
  writeContract,
  waitForTransactionReceipt,
} from '@wagmi/core'
import type { Config } from 'wagmi'
import { POOL_ABI, ERC20_ABI } from '../lib/abi'
import { POOL_ADDRESS } from '../lib/wagmi'
import type { RawReserveData, RawPosition } from '../types'

// ─── Read functions ────────────────────────────────────────────────────────

export async function fetchAllReserveData(config: Config): Promise<RawReserveData[]> {
  const data = await readContract(config, {
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'getAllReserveData',
  })
  return data as RawReserveData[]
}

export async function fetchReserveData(config: Config, reserveName: string): Promise<RawReserveData> {
  const data = await readContract(config, {
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'getReserveData',
    args: [reserveName],
  })
  return data as RawReserveData
}

export async function fetchUserPositions(config: Config, user: `0x${string}`): Promise<RawPosition[]> {
  const data = await readContract(config, {
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'getUserPositions',
    args: [user],
  })
  return data as RawPosition[]
}

export async function fetchUserDepositBalance(
  config: Config,
  reserveName: string,
  user: `0x${string}`,
): Promise<bigint> {
  const data = await readContract(config, {
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'getUserDepositBalance',
    args: [reserveName, user],
  })
  return data as bigint
}

export async function fetchTokenBalance(
  config: Config,
  tokenAddress: `0x${string}`,
  user: `0x${string}`,
): Promise<bigint> {
  return readContract(config, {
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: [user],
  }) as Promise<bigint>
}

export async function fetchAllowance(
  config: Config,
  tokenAddress: `0x${string}`,
  owner: `0x${string}`,
  spender: `0x${string}`,
): Promise<bigint> {
  return readContract(config, {
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: [owner, spender],
  }) as Promise<bigint>
}

// ─── Write helpers ─────────────────────────────────────────────────────────

/** Simulate → send → wait. Returns txHash on success, throws decoded error on failure. */
async function executeWrite(
  config: Config,
  args: Parameters<typeof simulateContract>[1],
): Promise<`0x${string}`> {
  // 1. Simulate
  const { request } = await simulateContract(config, args)
  // 2. Send
  const hash = await writeContract(config, request)
  // 3. Wait
  await waitForTransactionReceipt(config, { hash })
  return hash
}

export async function approveToken(
  config: Config,
  tokenAddress: `0x${string}`,
  amount: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
    address: tokenAddress,
    abi: ERC20_ABI,
    functionName: 'approve',
    args: [POOL_ADDRESS, amount],
  })
}

export async function depositToPool(
  config: Config,
  reserveName: string,
  amount: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'deposit',
    args: [reserveName, amount],
  })
}

export async function withdrawFromPool(
  config: Config,
  reserveName: string,
  amount: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'withdraw',
    args: [reserveName, amount],
  })
}

export async function borrowFromPool(
  config: Config,
  collateralName: string,
  borrowName: string,
  amount: bigint,
  bufferPercent: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'borrow',
    args: [collateralName, borrowName, amount, bufferPercent],
  })
}

export async function repayToPool(
  config: Config,
  collateralName: string,
  borrowName: string,
  positionId: bigint,
  repayAmount: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'repay',
    args: [collateralName, borrowName, positionId, repayAmount],
  })
}

export async function liquidatePosition(
  config: Config,
  user: `0x${string}`,
  positionId: bigint,
): Promise<`0x${string}`> {
  return executeWrite(config, {
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'liquidate',
    args: [user, positionId],
  })
}
