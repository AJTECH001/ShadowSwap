import React, { useState, useEffect } from 'react'
import { ArrowDownUp, Lock, Shield, Zap, Loader2, CheckCircle, AlertCircle } from 'lucide-react'
import { TOKENS } from '../config/tokens'
import type { Token } from '../config/tokens'
import { useTokenBalance } from '../hooks/useTokenBalance'
import { useTokenPrice } from '../hooks/useTokenPrice'
import { useSwap, SwapStatus } from '../hooks/useSwap'
import TokenSelector from './TokenSelector'

interface TradingInterfaceProps {
  isConnected: boolean
}

const TradingInterface: React.FC<TradingInterfaceProps> = ({ isConnected }) => {
  const [fromAmount, setFromAmount] = useState('')
  const [fromToken, setFromToken] = useState<Token>(TOKENS.ETH)
  const [toToken, setToToken] = useState<Token>(TOKENS.USDC)
  const [isEncrypted] = useState(true)

  // Get token balances
  const fromBalance = useTokenBalance(fromToken)
  const toBalance = useTokenBalance(toToken)

  // Get price conversion
  const { toAmount, rate, priceImpact } = useTokenPrice(
    fromToken.symbol, 
    toToken.symbol, 
    fromAmount
  )

  // Swap functionality
  const { swap, status, error, txHash, isLoading } = useSwap()

  // Auto-update toAmount when fromAmount changes
  useEffect(() => {
    // toAmount is automatically calculated by useTokenPrice hook
  }, [fromAmount, fromToken, toToken])

  const handleSwap = async () => {
    if (!isConnected || !fromAmount || parseFloat(fromAmount) <= 0) return
    
    await swap(fromToken, toToken, fromAmount, isEncrypted)
  }

  const handleFlipTokens = () => {
    const tempToken = fromToken
    setFromToken(toToken)
    setToToken(tempToken)
    setFromAmount(toAmount)
  }

  const handleMaxClick = () => {
    if (fromBalance.formatted) {
      setFromAmount(fromBalance.formatted)
    }
  }

  return (
    <div className="bg-black/40 backdrop-blur-xl rounded-2xl border border-white/10 p-6">
      <div className="flex items-center justify-between mb-6">
        <h2 className="text-xl font-semibold text-white">Privacy Swap</h2>
        <div className="flex items-center space-x-2">
          <div className={`px-3 py-1 rounded-full text-xs flex items-center space-x-1 ${
            isEncrypted ? 'bg-green-500/20 text-green-200 border border-green-500/30' : 'bg-red-500/20 text-red-200 border border-red-500/30'
          }`}>
            <Lock size={12} />
            <span>{isEncrypted ? 'Encrypted' : 'Public'}</span>
          </div>
        </div>
      </div>

      <div className="space-y-4">
        {/* From Token */}
        <div className="bg-white/5 rounded-xl border border-white/10 p-4">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-gray-400">From</span>
            <div className="flex items-center space-x-2">
              <span className="text-sm text-gray-400">
                Balance: {fromBalance.isLoading ? '...' : fromBalance.formatted}
              </span>
              {isConnected && (
                <button
                  onClick={handleMaxClick}
                  className="text-xs text-purple-400 hover:text-purple-300 font-medium"
                >
                  MAX
                </button>
              )}
            </div>
          </div>
          <div className="flex items-center space-x-3">
            <input
              type="text"
              value={fromAmount}
              onChange={(e) => setFromAmount(e.target.value)}
              placeholder="0.0"
              className="flex-1 bg-transparent text-2xl text-white placeholder-gray-500 outline-none"
            />
            <TokenSelector
              selectedToken={fromToken}
              onTokenSelect={setFromToken}
              otherToken={toToken}
            />
          </div>
          {isEncrypted && (
            <div className="flex items-center space-x-1 mt-2 text-xs text-green-400">
              <Shield size={12} />
              <span>Amount encrypted via Fhenix FHE</span>
            </div>
          )}
        </div>

        {/* Swap Button */}
        <div className="flex justify-center">
          <button
            onClick={handleFlipTokens}
            className="bg-white/10 hover:bg-white/20 transition-colors rounded-full p-2 border border-white/10"
          >
            <ArrowDownUp size={16} className="text-white" />
          </button>
        </div>

        {/* To Token */}
        <div className="bg-white/5 rounded-xl border border-white/10 p-4">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm text-gray-400">To</span>
            <span className="text-sm text-gray-400">
              Balance: {toBalance.isLoading ? '...' : toBalance.formatted}
            </span>
          </div>
          <div className="flex items-center space-x-3">
            <input
              type="text"
              value={toAmount}
              readOnly
              placeholder="0.0"
              className="flex-1 bg-transparent text-2xl text-white placeholder-gray-500 outline-none"
            />
            <TokenSelector
              selectedToken={toToken}
              onTokenSelect={setToToken}
              otherToken={fromToken}
            />
          </div>
          {isEncrypted && (
            <div className="flex items-center space-x-1 mt-2 text-xs text-green-400">
              <Shield size={12} />
              <span>Expected output encrypted</span>
            </div>
          )}
        </div>

        {/* Trade Info */}
        <div className="bg-white/5 rounded-xl border border-white/10 p-4 space-y-3">
          <div className="flex items-center justify-between text-sm">
            <span className="text-gray-400">Rate</span>
            <span className="text-white">
              1 {fromToken.symbol} = {rate} {toToken.symbol}
            </span>
          </div>
          {parseFloat(priceImpact) > 0 && (
            <div className="flex items-center justify-between text-sm">
              <span className="text-gray-400">Price Impact</span>
              <span className={`${parseFloat(priceImpact) > 3 ? 'text-red-400' : parseFloat(priceImpact) > 1 ? 'text-yellow-400' : 'text-green-400'}`}>
                {priceImpact}%
              </span>
            </div>
          )}
          <div className="flex items-center justify-between text-sm">
            <span className="text-gray-400 flex items-center space-x-1">
              <Zap size={12} />
              <span>MEV Protection</span>
            </span>
            <span className="text-green-400">Active</span>
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-gray-400">Network Fee</span>
            <span className="text-white">~$8.43</span>
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-gray-400">ShadowSwap Fee</span>
            <span className="text-purple-400">0.3% (Dynamic)</span>
          </div>
        </div>

        {/* Privacy Features */}
        <div className="bg-gradient-to-r from-purple-500/10 to-blue-500/10 rounded-xl border border-purple-500/20 p-4">
          <h3 className="text-sm font-medium text-white mb-3">Privacy Features Active</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3 text-xs">
            <div className="flex items-center space-x-2">
              <div className="w-2 h-2 bg-green-400 rounded-full"></div>
              <span className="text-green-200">FHE Encryption</span>
            </div>
            <div className="flex items-center space-x-2">
              <div className="w-2 h-2 bg-green-400 rounded-full"></div>
              <span className="text-green-200">MEV Protection</span>
            </div>
            <div className="flex items-center space-x-2">
              <div className="w-2 h-2 bg-green-400 rounded-full"></div>
              <span className="text-green-200">Order Batching</span>
            </div>
          </div>
        </div>

        {/* Transaction Status */}
        {(status !== SwapStatus.IDLE || error) && (
          <div className="bg-white/5 rounded-xl border border-white/10 p-4">
            {status === SwapStatus.PENDING && (
              <div className="flex items-center space-x-2 text-yellow-400">
                <Loader2 size={16} className="animate-spin" />
                <span className="text-sm">Preparing transaction...</span>
              </div>
            )}
            {status === SwapStatus.CONFIRMING && (
              <div className="flex items-center space-x-2 text-blue-400">
                <Loader2 size={16} className="animate-spin" />
                <div className="flex-1">
                  <div className="text-sm">Confirming transaction...</div>
                  {txHash && (
                    <div className="text-xs text-gray-400 mt-1">
                      Hash: {txHash.slice(0, 10)}...{txHash.slice(-8)}
                    </div>
                  )}
                </div>
              </div>
            )}
            {status === SwapStatus.SUCCESS && (
              <div className="flex items-center space-x-2 text-green-400">
                <CheckCircle size={16} />
                <div className="flex-1">
                  <div className="text-sm">Swap completed successfully!</div>
                  {txHash && (
                    <a 
                      href={`https://sepolia.arbiscan.io/tx/${txHash}`}
                      target="_blank" 
                      rel="noopener noreferrer"
                      className="text-xs text-purple-400 hover:text-purple-300 mt-1 inline-block"
                    >
                      View on Arbiscan ↗
                    </a>
                  )}
                </div>
              </div>
            )}
            {error && (
              <div className="flex items-center space-x-2 text-red-400">
                <AlertCircle size={16} />
                <span className="text-sm">{error}</span>
              </div>
            )}
          </div>
        )}

        {/* Swap Button */}
        <button
          onClick={handleSwap}
          disabled={!isConnected || !fromAmount || parseFloat(fromAmount) === 0 || parseFloat(fromAmount) > parseFloat(fromBalance.formatted) || isLoading}
          className={`w-full py-4 rounded-xl font-medium text-lg transition-all flex items-center justify-center space-x-2 ${
            isConnected && fromAmount && parseFloat(fromAmount) > 0 && parseFloat(fromAmount) <= parseFloat(fromBalance.formatted) && !isLoading
              ? 'bg-gradient-to-r from-purple-600 to-blue-600 text-white hover:from-purple-500 hover:to-blue-500 shadow-lg hover:shadow-purple-500/25'
              : 'bg-gray-600 text-gray-400 cursor-not-allowed'
          }`}
        >
          {isLoading && <Loader2 size={20} className="animate-spin" />}
          <span>
            {!isConnected 
              ? 'Connect Wallet' 
              : !fromAmount || parseFloat(fromAmount) === 0
              ? 'Enter Amount'
              : parseFloat(fromAmount) > parseFloat(fromBalance.formatted)
              ? 'Insufficient Balance'
              : isLoading
              ? 'Processing...'
              : 'Swap Privately'
            }
          </span>
        </button>
      </div>
    </div>
  )
}

export default TradingInterface