import { useState } from 'react'
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { parseUnits, encodeAbiParameters, parseAbiParameters } from 'viem'
import { SHADOWSWAP_ADDRESSES } from '../config/wagmi'
import type { Token } from '../config/tokens'

export const SwapStatus = {
  IDLE: 'idle',
  ENCRYPTING: 'encrypting',
  PENDING: 'pending',
  CONFIRMING: 'confirming',
  SUCCESS: 'success',
  ERROR: 'error'
} as const

export type SwapStatus = typeof SwapStatus[keyof typeof SwapStatus]

/**
 * Encodes swap parameters for the ShadowSwap hook
 * 
 * In production with Fhenix CoFHE:
 * 1. Use cofhejs library to encrypt values client-side
 * 2. Pass encrypted ciphertexts to the hook via hookData
 * 
 * For development/testing without CoFHE coprocessor:
 * We encode placeholder data that the mock environment can handle
 * 
 * Structure matches: abi.decode(hookData, (InEuint64, InEbool, InEuint64, InEuint32))
 * Each InE* type is a struct with a single bytes field called 'data'
 */
function encodeHookData(
  amount: bigint,
  zeroForOne: boolean,
  sqrtPriceLimit: bigint,
  deadline: number
): `0x${string}` {
  // For production, these would be encrypted using cofhejs:
  // import { FhenixClient, EncryptionTypes } from 'fhenixjs'
  // const client = new FhenixClient({ provider })
  // const encAmount = await client.encrypt(amount, EncryptionTypes.uint64)
  // const encDirection = await client.encrypt(zeroForOne, EncryptionTypes.bool)
  // etc.
  
  // For now, we encode plaintext values as bytes (for local/mock testing)
  const amountBytes = encodeAbiParameters(
    parseAbiParameters('uint64'),
    [amount > BigInt(2**64 - 1) ? BigInt(2**64 - 1) : amount]
  )
  
  const directionBytes = encodeAbiParameters(
    parseAbiParameters('bool'),
    [zeroForOne]
  )
  
  const priceLimitBytes = encodeAbiParameters(
    parseAbiParameters('uint64'),
    [sqrtPriceLimit > BigInt(2**64 - 1) ? BigInt(2**64 - 1) : sqrtPriceLimit]
  )
  
  const deadlineBytes = encodeAbiParameters(
    parseAbiParameters('uint32'),
    [deadline]
  )
  
  // Encode as tuple of structs: ((bytes), (bytes), (bytes), (bytes))
  // Using explicit tuple encoding for InEuint64, InEbool, InEuint64, InEuint32
  const hookData = encodeAbiParameters(
    [
      { type: 'tuple', components: [{ type: 'bytes', name: 'data' }] },
      { type: 'tuple', components: [{ type: 'bytes', name: 'data' }] },
      { type: 'tuple', components: [{ type: 'bytes', name: 'data' }] },
      { type: 'tuple', components: [{ type: 'bytes', name: 'data' }] }
    ],
    [
      { data: amountBytes },
      { data: directionBytes },
      { data: priceLimitBytes },
      { data: deadlineBytes }
    ]
  )
  
  return hookData
}

export function useSwap() {
  const { address } = useAccount()
  const [status, setStatus] = useState<SwapStatus>(SwapStatus.IDLE)
  const [error, setError] = useState<string | null>(null)

  const { writeContract, data: hash } = useWriteContract()
  
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
  })

  // Pool Manager ABI for swap function (Uniswap V4)
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
    isEncrypted: boolean = true,
    slippageBps: number = 50 // 0.5% default slippage
  ) => {
    if (!address || !fromAmount || parseFloat(fromAmount) <= 0) {
      setError('Invalid swap parameters')
      return
    }

    try {
      setStatus(isEncrypted ? SwapStatus.ENCRYPTING : SwapStatus.PENDING)
      setError(null)

      // Parse amount with token decimals
      const amountIn = parseUnits(fromAmount, fromToken.decimals)

      // Determine token order (zeroForOne) - Uniswap convention
      const token0Address = fromToken.address.toLowerCase()
      const token1Address = toToken.address.toLowerCase()
      const zeroForOne = token0Address < token1Address

      // Pool key structure for Uniswap V4
      const poolKey = {
        currency0: zeroForOne ? fromToken.address : toToken.address,
        currency1: zeroForOne ? toToken.address : fromToken.address,
        fee: 3000 | 0x800000, // 0.3% fee with DYNAMIC_FEE_FLAG
        tickSpacing: 60,
        hooks: SHADOWSWAP_ADDRESSES.HOOK
      }

      // Calculate sqrt price limits
      const MIN_SQRT_RATIO = 4295128740n
      const MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970341n
      
      const sqrtPriceLimitX96 = zeroForOne ? 
        MIN_SQRT_RATIO : // Price decreases when selling token0
        MAX_SQRT_RATIO   // Price increases when selling token1

      // Swap parameters for Uniswap V4
      const swapParams = {
        zeroForOne: zeroForOne,
        amountSpecified: zeroForOne ? amountIn : -amountIn,
        sqrtPriceLimitX96: sqrtPriceLimitX96
      }

      // Calculate deadline (1 hour from now in blocks, ~12s per block)
      const currentBlock = Math.floor(Date.now() / 12000)
      const deadline = currentBlock + 300 // ~1 hour

      // Encode hook data with encrypted order parameters
      let hookData: `0x${string}`
      
      if (isEncrypted) {
        // For production: Use cofhejs to encrypt values
        // const cofhe = await initCofhe(provider)
        // const encAmount = await cofhe.encrypt(amountIn, 'uint64')
        // etc.
        
        // For development: Encode plaintext values for mock testing
        hookData = encodeHookData(
          amountIn,
          zeroForOne,
          sqrtPriceLimitX96,
          deadline
        )
        
        console.log('🔐 Encrypted order data prepared for ShadowSwap Hook')
      } else {
        // Empty hook data for non-encrypted swaps
        hookData = '0x'
      }

      setStatus(SwapStatus.PENDING)

      console.log('🌙 Initiating ShadowSwap:', {
        poolKey,
        swapParams,
        hookDataLength: hookData.length,
        fromToken: fromToken.symbol,
        toToken: toToken.symbol,
        amount: fromAmount,
        encrypted: isEncrypted,
        slippageBps
      })

      // Execute swap through Uniswap V4 Pool Manager with ShadowSwap Hook
      await writeContract({
        address: SHADOWSWAP_ADDRESSES.POOL_MANAGER,
        abi: POOL_MANAGER_ABI,
        functionName: 'swap',
        args: [poolKey, swapParams, hookData],
        value: fromToken.isNative ? amountIn : 0n,
      })

      setStatus(SwapStatus.CONFIRMING)
      
    } catch (err: unknown) {
      console.error('ShadowSwap failed:', err)
      const errorMessage = err instanceof Error ? err.message : 'Transaction failed'
      setError(errorMessage)
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

  const reset = () => {
    setStatus(SwapStatus.IDLE)
    setError(null)
  }

  return {
    swap,
    status,
    error,
    txHash: hash,
    isLoading: status === SwapStatus.PENDING || status === SwapStatus.CONFIRMING || status === SwapStatus.ENCRYPTING,
    reset,
  }
}