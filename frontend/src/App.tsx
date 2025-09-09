import { useAccount, useConnect, useDisconnect } from 'wagmi'
import Header from './components/Header'
import TradingInterface from './components/TradingInterface'
import MEVProtectionPanel from './components/MEVProtectionPanel'
import StatsPanel from './components/StatsPanel'

function App() {
  const { isConnected } = useAccount()
  const { connect, connectors } = useConnect()
  const { disconnect } = useDisconnect()

  const handleConnect = () => {
    if (isConnected) {
      disconnect()
    } else {
      // Connect with the first available connector (usually MetaMask)
      connect({ connector: connectors[0] })
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-purple-900 to-blue-900">
      {/* Background Effects */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-40 -right-40 w-80 h-80 bg-purple-500/10 rounded-full blur-3xl"></div>
        <div className="absolute -bottom-40 -left-40 w-80 h-80 bg-blue-500/10 rounded-full blur-3xl"></div>
        <div className="absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-cyan-500/5 rounded-full blur-3xl"></div>
      </div>

      {/* Main Content */}
      <div className="relative z-10">
        <Header isConnected={isConnected} onConnect={handleConnect} />
        
        <main className="container mx-auto px-4 py-8">
          {/* Hero Section */}
          <div className="text-center mb-12">
            <h1 className="text-5xl md:text-6xl font-bold text-white mb-4">
              🌙 <span className="bg-gradient-to-r from-purple-400 to-cyan-400 bg-clip-text text-transparent">
                ShadowSwap
              </span>
            </h1>
            <p className="text-xl text-gray-300 mb-6 max-w-2xl mx-auto">
              The first privacy-preserving DEX with MEV protection, cross-chain coordination, and encrypted order matching
            </p>
            <div className="flex flex-wrap justify-center gap-4 text-sm">
              <span className="px-4 py-2 bg-purple-500/20 text-purple-200 rounded-full border border-purple-500/30">
                🦄 Uniswap v4 Hook
              </span>
              <span className="px-4 py-2 bg-blue-500/20 text-blue-200 rounded-full border border-blue-500/30">
                ⚡ EigenLayer AVS
              </span>
              <span className="px-4 py-2 bg-cyan-500/20 text-cyan-200 rounded-full border border-cyan-500/30">
                🔐 Fhenix FHE
              </span>
            </div>
          </div>

          {/* Main Trading Interface */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 mb-8">
            <div className="lg:col-span-2">
              <TradingInterface isConnected={isConnected} />
            </div>
            <div className="space-y-6">
              <MEVProtectionPanel />
              <StatsPanel />
            </div>
          </div>
        </main>
      </div>
    </div>
  )
}

export default App
