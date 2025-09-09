import React from 'react'
import { TrendingUp, DollarSign, Activity, Globe, Wifi } from 'lucide-react'
import { useShadowSwapEvents } from '../hooks/useShadowSwapEvents'

const StatsPanel: React.FC = () => {
  const { recentSwaps, protocolStats, isLoading } = useShadowSwapEvents()

  // Debug logging
  console.log('📊 StatsPanel - Recent swaps:', recentSwaps)
  console.log('📊 StatsPanel - Protocol stats:', protocolStats)
  console.log('📊 StatsPanel - Is loading:', isLoading)

  const formatTimeAgo = (timestamp: number) => {
    const seconds = Math.floor((Date.now() - timestamp) / 1000)
    if (seconds < 60) return `${seconds}s ago`
    const minutes = Math.floor(seconds / 60)
    if (minutes < 60) return `${minutes}m ago`
    const hours = Math.floor(minutes / 60)
    return `${hours}h ago`
  }
  return (
    <div className="bg-black/40 backdrop-blur-xl rounded-2xl border border-white/10 p-6">
      <div className="flex items-center space-x-3 mb-6">
        <div className="p-2 bg-gradient-to-r from-cyan-500/20 to-blue-500/20 rounded-lg">
          <Activity className="text-cyan-400" size={20} />
        </div>
        <div>
          <h3 className="text-lg font-semibold text-white">Protocol Stats</h3>
          <div className="flex items-center space-x-2">
            <p className="text-sm text-gray-400">24h overview</p>
            <div className="flex items-center space-x-1">
              <Wifi size={10} className="text-green-400" />
              <span className="text-xs text-green-400">Live</span>
            </div>
          </div>
        </div>
      </div>

      <div className="space-y-4">
        {/* Key Metrics */}
        <div className="grid grid-cols-1 gap-4">
          <div className="bg-white/5 rounded-lg p-4 border border-white/5">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm text-gray-400 flex items-center space-x-1">
                <DollarSign size={12} />
                <span>24h Volume</span>
              </span>
              <span className="text-xs text-green-400">
                {isLoading ? '...' : '+12.4%'}
              </span>
            </div>
            <div className="text-2xl font-bold text-white">
              {isLoading ? '...' : `$${parseFloat(protocolStats.totalVolume24h).toLocaleString(undefined, { maximumFractionDigits: 0 })}`}
            </div>
          </div>

          <div className="bg-white/5 rounded-lg p-4 border border-white/5">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm text-gray-400 flex items-center space-x-1">
                <TrendingUp size={12} />
                <span>TVL</span>
              </span>
              <span className="text-xs text-green-400">
                {isLoading ? '...' : '+8.7%'}
              </span>
            </div>
            <div className="text-2xl font-bold text-white">
              {isLoading ? '...' : `$${parseFloat(protocolStats.totalValueLocked).toLocaleString(undefined, { maximumFractionDigits: 0 })}`}
            </div>
          </div>

          <div className="bg-white/5 rounded-lg p-4 border border-white/5">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm text-gray-400 flex items-center space-x-1">
                <Globe size={12} />
                <span>Active Users</span>
              </span>
              <span className="text-xs text-green-400">
                {isLoading ? '...' : '+15.2%'}
              </span>
            </div>
            <div className="text-2xl font-bold text-white">
              {isLoading ? '...' : protocolStats.activeUsers24h.toLocaleString()}
            </div>
          </div>
        </div>

        {/* Privacy Metrics */}
        <div className="bg-gradient-to-r from-purple-500/10 to-cyan-500/10 rounded-lg border border-purple-500/20 p-4">
          <h4 className="text-sm font-medium text-white mb-3">Privacy Metrics</h4>
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-300">Encrypted Transactions</span>
              <span className="text-xs text-purple-400">
                {isLoading ? '...' : `${protocolStats.encryptedTransactionRate.toFixed(1)}%`}
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-300">MEV Savings</span>
              <span className="text-xs text-green-400">
                {isLoading ? '...' : `$${parseFloat(protocolStats.mevSaved24h).toLocaleString(undefined, { maximumFractionDigits: 0 })}`}
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-300">Order Batching Rate</span>
              <span className="text-xs text-cyan-400">
                {isLoading ? '...' : `${protocolStats.orderBatchingRate.toFixed(1)}%`}
              </span>
            </div>
          </div>
        </div>

        {/* Network Status */}
        <div className="bg-gradient-to-r from-green-500/10 to-emerald-500/10 rounded-lg border border-green-500/20 p-4">
          <h4 className="text-sm font-medium text-white mb-3">Network Status</h4>
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-300">Arbitrum Gas</span>
              <span className="text-xs text-green-400">2.1 gwei</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-300">Hook Status</span>
              <div className="flex items-center space-x-1">
                <div className="w-1.5 h-1.5 bg-green-400 rounded-full"></div>
                <span className="text-xs text-green-400">Online</span>
              </div>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-300">AVS Operators</span>
              <span className="text-xs text-blue-400">12 Active</span>
            </div>
          </div>
        </div>

        {/* Recent Activity */}
        <div>
          <h4 className="text-sm font-medium text-white mb-3">Recent Swaps</h4>
          <div className="space-y-2">
            {recentSwaps.length === 0 ? (
              <div className="text-center p-4 text-gray-400 text-sm">
                {isLoading ? 'Loading recent swaps...' : 'No recent swaps'}
              </div>
            ) : (
              recentSwaps.slice(0, 3).map((swap) => (
                <div key={swap.id} className="flex items-center justify-between p-2 bg-white/5 rounded border border-white/5">
                  <div>
                    <div className="text-sm text-gray-300">
                      Swap {parseFloat(swap.amountIn).toFixed(2)} {swap.tokenIn.slice(-4).toUpperCase()}
                    </div>
                    <div className="text-xs text-gray-400">{formatTimeAgo(swap.timestamp)}</div>
                  </div>
                  <div className="text-right">
                    <div className="text-sm text-white">${(parseFloat(swap.amountIn) * 2450).toFixed(0)}</div>
                    <div className="text-xs text-green-400">+${parseFloat(swap.mevSaved).toFixed(2)} saved</div>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

export default StatsPanel