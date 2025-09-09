import { useMemo } from 'react'
import { TOKEN_PRICES } from '../config/tokens'

export function useTokenPrice(fromToken: string, toToken: string, fromAmount: string) {
  return useMemo(() => {
    if (!fromAmount || !fromToken || !toToken || fromAmount === '0') {
      return {
        toAmount: '0',
        rate: '0',
        priceImpact: '0',
      }
    }

    const fromPrice = TOKEN_PRICES[fromToken] || 0
    const toPrice = TOKEN_PRICES[toToken] || 0

    if (fromPrice === 0 || toPrice === 0) {
      return {
        toAmount: '0',
        rate: '0',
        priceImpact: '0',
      }
    }

    const fromAmountNum = parseFloat(fromAmount)
    const fromValueUSD = fromAmountNum * fromPrice
    const toAmountNum = fromValueUSD / toPrice

    // Apply a small slippage/fee (0.3% for ShadowSwap)
    const feeRate = 0.003
    const toAmountWithFee = toAmountNum * (1 - feeRate)

    // Calculate price impact (simplified)
    const priceImpact = Math.min((fromAmountNum / 1000) * 0.1, 5) // Max 5% impact

    return {
      toAmount: toAmountWithFee.toFixed(6),
      rate: (toAmountNum / fromAmountNum).toFixed(6),
      priceImpact: priceImpact.toFixed(2),
    }
  }, [fromToken, toToken, fromAmount])
}