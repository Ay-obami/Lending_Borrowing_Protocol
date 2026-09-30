import { http, createConfig } from 'wagmi'
import { foundry, sepolia } from 'viem/chains'
import { injected } from '@wagmi/connectors'
import { deploymentReady } from './frontendSafety'

const address = import.meta.env.VITE_POOL_ADDRESS ?? ''
const chainId = Number(import.meta.env.VITE_POOL_CHAIN_ID)
export const POOL_CONFIGURED = deploymentReady(address, chainId) && [11155111, 31337].includes(chainId)
export const POOL_CHAIN_ID: 11155111 | 31337 = chainId === 31337 ? 31337 : 11155111
export const POOL_ADDRESS = (POOL_CONFIGURED ? address : '0x0000000000000000000000000000000000000000') as `0x${string}`
export const wagmiConfig = createConfig({
  chains: [sepolia, foundry],
  connectors: [injected()],
  transports: { [sepolia.id]: http(), [foundry.id]: http() },
})
