import { useAccount, useBalance, useReadContract } from 'wagmi'
import { formatUnits } from 'viem'
import type { Token } from '../config/tokens'
import { ERC20_ABI } from '../config/tokens'

export function useTokenBalance(token: Token | null) {
  const { address } = useAccount()

  // For native ETH
  const nativeBalance = useBalance({
    address: address,
    query: {
      enabled: !!address && !!token?.isNative,
    },
  })

  // For ERC20 tokens
  const erc20Balance = useReadContract({
    address: token?.address,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      enabled: !!address && !!token && !token.isNative,
    },
  })

  if (!token || !address) {
    return {
      balance: '0',
      formatted: '0.0000',
      isLoading: false,
      error: null,
    }
  }

  if (token.isNative) {
    return {
      balance: nativeBalance.data?.value?.toString() || '0',
      formatted: nativeBalance.data ? 
        parseFloat(formatUnits(nativeBalance.data.value, token.decimals)).toFixed(4) : 
        '0.0000',
      isLoading: nativeBalance.isLoading,
      error: nativeBalance.error,
    }
  }

  return {
    balance: erc20Balance.data?.toString() || '0',
    formatted: erc20Balance.data ? 
      parseFloat(formatUnits(erc20Balance.data as bigint, token.decimals)).toFixed(4) : 
      '0.0000',
    isLoading: erc20Balance.isLoading,
    error: erc20Balance.error,
  }
}