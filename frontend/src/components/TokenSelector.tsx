import React, { useState } from 'react'
import { ChevronDown } from 'lucide-react'
import { TOKEN_LIST } from '../config/tokens'
import type { Token } from '../config/tokens'

interface TokenSelectorProps {
  selectedToken: Token
  onTokenSelect: (token: Token) => void
  otherToken?: Token
}

const TokenSelector: React.FC<TokenSelectorProps> = ({ 
  selectedToken, 
  onTokenSelect, 
  otherToken 
}) => {
  const [isOpen, setIsOpen] = useState(false)

  const availableTokens = TOKEN_LIST.filter(token => 
    token.symbol !== otherToken?.symbol
  )

  return (
    <div className="relative">
      <button
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center space-x-2 bg-white/10 hover:bg-white/20 rounded-lg px-3 py-2 transition-colors"
      >
        <span className="text-lg">{selectedToken.logoURI}</span>
        <span className="font-medium text-white">{selectedToken.symbol}</span>
        <ChevronDown size={16} className="text-gray-400" />
      </button>

      {isOpen && (
        <>
          {/* Backdrop */}
          <div 
            className="fixed inset-0 z-10" 
            onClick={() => setIsOpen(false)}
          />
          
          {/* Dropdown */}
          <div className="absolute top-full left-0 right-0 mt-1 bg-gray-800 rounded-xl border border-white/10 shadow-2xl z-20 max-h-64 overflow-y-auto">
            {availableTokens.map((token) => (
              <button
                key={token.symbol}
                onClick={() => {
                  onTokenSelect(token)
                  setIsOpen(false)
                }}
                className="w-full flex items-center space-x-3 px-4 py-3 hover:bg-white/10 transition-colors first:rounded-t-xl last:rounded-b-xl"
              >
                <span className="text-lg">{token.logoURI}</span>
                <div className="text-left">
                  <div className="font-medium text-white">{token.symbol}</div>
                  <div className="text-xs text-gray-400">{token.name}</div>
                </div>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  )
}

export default TokenSelector