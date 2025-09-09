import { useState } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { parseUnits } from 'viem'
import { SHADOWSWAP_ADDRESSES } from '../config/wagmi'
import type { Token } from '../config/tokens'

export const SwapStatus = {
  IDLE: 'idle',
  PENDING: 'pending',
  CONFIRMING: 'confirming',
  SUCCESS: 'success',
  ERROR: 'error'
} as const

export type SwapStatus = typeof SwapStatus[keyof typeof SwapStatus]

export function useSwap() {
  const { address } = useAccount()
  const [status, setStatus] = useState<SwapStatus>(SwapStatus.IDLE)
  const [error, setError] = useState<string | null>(null)

  const { writeContract, data: hash } = useWriteContract()
  
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  // Pool Manager ABI for swap function
  const POOL_MANAGER_ABI = [
    {
      name: 'swap',
      type: 'function',
      stateMutability: 'payable',
      inputs: [
        { name: 'key', type: 'tuple', components: [
          { name: 'currency0', type: 'address' },
          { name: 'currency1', type: 'address' },
          { name: 'fee', type: 'uint24' },
          { name: 'tickSpacing', type: 'int24' },
          { name: 'hooks', type: 'address' }
        ]},
        { name: 'params', type: 'tuple', components: [
          { name: 'zeroForOne', type: 'bool' },
          { name: 'amountSpecified', type: 'int256' },
          { name: 'sqrtPriceLimitX96', type: 'uint160' }
        ]},
        { name: 'hookData', type: 'bytes' }
      ],
      outputs: [
        { name: 'delta', type: 'tuple', components: [
          { name: 'amount0', type: 'int128' },
          { name: 'amount1', type: 'int128' }
        ]}
      ]
    }
  ] as const

  const swap = async (
    fromToken: Token,
    toToken: Token,
    fromAmount: string,
    isEncrypted: boolean = true
  ) => {
    if (!address || !fromAmount || parseFloat(fromAmount) <= 0) {
      setError('Invalid swap parameters')
      return
    }

    try {
      setStatus(SwapStatus.PENDING)
      setError(null)

      // Parse amount with token decimals
      const amountIn = parseUnits(fromAmount, fromToken.decimals)

      // Determine token order (zeroForOne)
      const token0Address = fromToken.address.toLowerCase()
      const token1Address = toToken.address.toLowerCase()
      const zeroForOne = token0Address < token1Address

      // Pool key structure
      const poolKey = {
        currency0: zeroForOne ? fromToken.address : toToken.address,
        currency1: zeroForOne ? toToken.address : fromToken.address,
        fee: 3000, // 0.3% fee
        tickSpacing: 60,
        hooks: SHADOWSWAP_ADDRESSES.HOOK
      }

      // Swap parameters
      const swapParams = {
        zeroForOne: zeroForOne,
        amountSpecified: zeroForOne ? amountIn : -amountIn,
        sqrtPriceLimitX96: zeroForOne ? 
          4295128740n : // MIN_SQRT_RATIO + 1
          1461446703485210103287273052203988822378723970341n // MAX_SQRT_RATIO - 1
      }

      // Hook data for privacy features
      const hookData = isEncrypted ? 
        '0x0001' : // Enable encryption flag
        '0x0000'   // No encryption

      console.log('Initiating swap with ShadowSwap Hook:', {
        poolKey,
        swapParams,
        hookData,
        fromToken: fromToken.symbol,
        toToken: toToken.symbol,
        amount: fromAmount,
        encrypted: isEncrypted
      })

      // Execute swap through Uniswap V4 Pool Manager
      await writeContract({
        address: SHADOWSWAP_ADDRESSES.POOL_MANAGER,
        abi: POOL_MANAGER_ABI,
        functionName: 'swap',
        args: [poolKey, swapParams, hookData],
        value: fromToken.isNative ? amountIn : 0n,
      })

      setStatus(SwapStatus.CONFIRMING)
      
    } catch (err: any) {
      console.error('Swap failed:', err)
      setError(err.message || 'Transaction failed')
      setStatus(SwapStatus.ERROR)
    }
  }

  // Update status based on transaction confirmation
  if (isConfirming && status !== SwapStatus.CONFIRMING) {
    setStatus(SwapStatus.CONFIRMING)
  }

  if (isSuccess && status !== SwapStatus.SUCCESS) {
    setStatus(SwapStatus.SUCCESS)
    setError(null)
  }

  return {
    swap,
    status,
    error,
    txHash: hash,
    isLoading: status === SwapStatus.PENDING || status === SwapStatus.CONFIRMING,
  }
}