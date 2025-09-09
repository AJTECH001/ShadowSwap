import { http, createConfig } from 'wagmi'
import { arbitrumSepolia } from 'wagmi/chains'
import { injected, metaMask, walletConnect } from 'wagmi/connectors'

// ShadowSwap contract addresses on Arbitrum Sepolia
export const SHADOWSWAP_ADDRESSES = {
  HOOK: '0x742d35cc6471eb65c4f7c8c7c5b3de6c2e2c3af5',
  AVS: '0xa0e1cca4fe786118c0abb1fdf45c04e39dd1ad12',
  OPERATOR: '0x9312e3cfe5de10a3031a1b58f6e7e1e9d9e1e1e1',
  POOL_MANAGER: '0x64255ed21366db43d89736eeb3b1764dd33d2f9c'
} as const

export const config = createConfig({
  chains: [arbitrumSepolia],
  connectors: [
    injected(),
    metaMask(),
    walletConnect({
      projectId: 'shadowswap-project-id' // You can replace with actual project ID
    }),
  ],
  transports: {
    [arbitrumSepolia.id]: http('https://sepolia-rollup.arbitrum.io/rpc'),
  },
})

declare module 'wagmi' {
  interface Register {
    config: typeof config
  }
}