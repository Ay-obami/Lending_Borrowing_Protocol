import { createConfig, http } from 'wagmi'
import { hardhat, localhost } from 'wagmi/chains'
import { injected, metaMask } from 'wagmi/connectors'

export const POOL_ADDRESS = (import.meta.env.VITE_POOL_ADDRESS || '0x0000000000000000000000000000000000000000') as `0x${string}`

export const TOKEN_ADDRESSES: Record<string, `0x${string}`> = {
  mUSDT: (import.meta.env.VITE_TOKEN_MUSDT || '0x0') as `0x${string}`,
  mWETH: (import.meta.env.VITE_TOKEN_MWETH || '0x0') as `0x${string}`,
  mWBTC: (import.meta.env.VITE_TOKEN_MWBTC || '0x0') as `0x${string}`,
}

export const wagmiConfig = createConfig({
  chains: [localhost, hardhat],
  connectors: [injected(), metaMask()],
  transports: {
    [localhost.id]: http('http://127.0.0.1:8545'),
    [hardhat.id]: http('http://127.0.0.1:8545'),
  },
})

declare module 'wagmi' {
  interface Register {
    config: typeof wagmiConfig
  }
}
