import React from 'react'
import { useAccount } from 'wagmi'

interface HeaderProps {
  isConnected: boolean
  onConnect: () => void
}

const Header: React.FC<HeaderProps> = ({ isConnected, onConnect }) => {
  const { address } = useAccount()
  return (
    <header className="border-b border-white/10 bg-black/20 backdrop-blur-xl">
      <div className="container mx-auto px-4 py-4">
        <div className="flex items-center justify-between">
          {/* Logo */}
          <div className="flex items-center space-x-3">
            <div className="text-2xl">🌙</div>
            <div>
              <h1 className="text-xl font-bold text-white">ShadowSwap</h1>
              <p className="text-xs text-gray-400">Privacy-First DEX</p>
            </div>
          </div>

          {/* Navigation */}
          <nav className="hidden md:flex items-center space-x-8">
            <a href="#trade" className="text-gray-300 hover:text-white transition-colors">
              Trade
            </a>
            <a href="#pools" className="text-gray-300 hover:text-white transition-colors">
              Pools
            </a>
            <a href="#stats" className="text-gray-300 hover:text-white transition-colors">
              Stats
            </a>
            <a href="#docs" className="text-gray-300 hover:text-white transition-colors">
              Docs
            </a>
          </nav>

          {/* Connection Status & Wallet */}
          <div className="flex items-center space-x-4">
            {/* Network Status */}
            <div className="hidden lg:flex items-center space-x-2 px-3 py-2 bg-green-500/20 text-green-200 rounded-full border border-green-500/30">
              <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
              <span className="text-sm">Arbitrum Sepolia</span>
            </div>

            {/* Wallet Connect Button */}
            <button
              onClick={onConnect}
              className={`px-6 py-2 rounded-full font-medium transition-all ${
                isConnected
                  ? 'bg-purple-500/20 text-purple-200 border border-purple-500/30 hover:bg-purple-500/30'
                  : 'bg-gradient-to-r from-purple-600 to-blue-600 text-white hover:from-purple-500 hover:to-blue-500 shadow-lg hover:shadow-purple-500/25'
              }`}
            >
              {isConnected ? (
                <div className="flex items-center space-x-2">
                  <div className="w-2 h-2 bg-purple-400 rounded-full"></div>
                  <span>{address ? `${address.slice(0, 6)}...${address.slice(-4)}` : '0x0000...0000'}</span>
                </div>
              ) : (
                'Connect Wallet'
              )}
            </button>
          </div>
        </div>
      </div>
    </header>
  )
}

export default Header