import type { Address } from 'viem'

export interface Token {
  address: Address
  symbol: string
  name: string
  decimals: number
  logoURI: string
  isNative?: boolean
}

// Common tokens on Arbitrum Sepolia
export const TOKENS: Record<string, Token> = {
  ETH: {
    address: '0x0000000000000000000000000000000000000000' as Address,
    symbol: 'ETH',
    name: 'Ethereum',
    decimals: 18,
    logoURI: '🔷',
    isNative: true
  },
  WETH: {
    address: '0x980B62Da83eFf3D4576C647993b0c1D7faf17c73' as Address,
    symbol: 'WETH',
    name: 'Wrapped Ethereum',
    decimals: 18,
    logoURI: '🔷'
  },
  USDC: {
    address: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d' as Address,
    symbol: 'USDC',
    name: 'USD Coin',
    decimals: 6,
    logoURI: '💵'
  },
  USDT: {
    address: '0xf4C5e0f4590b6679B3030d29A84857ef4d5e54cE' as Address,
    symbol: 'USDT',
    name: 'Tether USD',
    decimals: 6,
    logoURI: '💰'
  },
  DAI: {
    address: '0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9' as Address,
    symbol: 'DAI',
    name: 'Dai Stablecoin',
    decimals: 18,
    logoURI: '🟡'
  },
  ARB: {
    address: '0x912CE59144191C1204E64559FE8253a0e49E6548' as Address,
    symbol: 'ARB',
    name: 'Arbitrum',
    decimals: 18,
    logoURI: '🔵'
  }
}

export const TOKEN_LIST = Object.values(TOKENS)

// Mock price data - in production, you'd fetch from Coingecko, CoinMarketCap, or DEX aggregators
export const TOKEN_PRICES: Record<string, number> = {
  ETH: 2450.32,
  WETH: 2450.32,
  USDC: 1.00,
  USDT: 0.999,
  DAI: 1.001,
  ARB: 0.85
}

// ERC20 ABI for balance and allowance checks
export const ERC20_ABI = [
  {
    constant: true,
    inputs: [{ name: "_owner", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "balance", type: "uint256" }],
    type: "function",
  },
  {
    constant: true,
    inputs: [],
    name: "decimals",
    outputs: [{ name: "", type: "uint8" }],
    type: "function",
  },
  {
    constant: true,
    inputs: [],
    name: "symbol",
    outputs: [{ name: "", type: "string" }],
    type: "function",
  },
  {
    constant: false,
    inputs: [
      { name: "_spender", type: "address" },
      { name: "_value", type: "uint256" },
    ],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    type: "function",
  },
] as const