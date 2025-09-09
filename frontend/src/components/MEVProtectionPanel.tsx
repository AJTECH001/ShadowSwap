import React from 'react'
import { Shield, TrendingUp, Users, Zap, Activity } from 'lucide-react'
import { useShadowSwapEvents } from '../hooks/useShadowSwapEvents'

const MEVProtectionPanel: React.FC = () => {
  const { recentMEVEvents, protocolStats, isLoading } = useShadowSwapEvents()

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
        <div className="p-2 bg-gradient-to-r from-red-500/20 to-orange-500/20 rounded-lg">
          <Shield className="text-orange-400" size={20} />
        </div>
        <div>
          <h3 className="text-lg font-semibold text-white">MEV Protection</h3>
          <p className="text-sm text-gray-400">Real-time monitoring</p>
        </div>
      </div>

      <div className="space-y-4">
        {/* MEV Stats */}
        <div className="grid grid-cols-2 gap-4">
          <div className="bg-white/5 rounded-lg p-3 border border-white/5">
            <div className="text-2xl font-bold text-green-400">
              {isLoading ? '...' : `$${parseFloat(protocolStats.mevSaved24h).toLocaleString(undefined, { maximumFractionDigits: 0 })}`}
            </div>
            <div className="text-xs text-gray-400 flex items-center space-x-1">
              <TrendingUp size={12} />
              <span>MEV Saved Today</span>
            </div>
          </div>
          <div className="bg-white/5 rounded-lg p-3 border border-white/5">
            <div className="text-2xl font-bold text-purple-400">
              {isLoading ? '...' : protocolStats.totalSwaps.toLocaleString()}
            </div>
            <div className="text-xs text-gray-400 flex items-center space-x-1">
              <Zap size={12} />
              <span>Protected Swaps</span>
            </div>
          </div>
        </div>

        {/* Protection Status */}
        <div className="bg-gradient-to-r from-green-500/10 to-blue-500/10 rounded-lg border border-green-500/20 p-4">
          <div className="flex items-center justify-between mb-3">
            <span className="text-sm font-medium text-white">Protection Status</span>
            <div className="flex items-center space-x-1">
              <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse"></div>
              <span className="text-xs text-green-400">Active</span>
            </div>
          </div>
          <div className="space-y-2 text-xs">
            <div className="flex items-center justify-between">
              <span className="text-gray-300">Front-running Protection</span>
              <span className="text-green-400">✓ Enabled</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-gray-300">Sandwich Attack Defense</span>
              <span className="text-green-400">✓ Enabled</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-gray-300">MEV Redistribution</span>
              <span className="text-purple-400">✓ 80% to LPs</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-gray-300">Encrypted Orders</span>
              <span className="text-cyan-400">✓ {protocolStats.encryptedTransactionRate.toFixed(1)}%</span>
            </div>
          </div>
        </div>

        {/* Recent MEV Blocks */}
        <div>
          <div className="flex items-center justify-between mb-3">
            <h4 className="text-sm font-medium text-white">Recent MEV Events</h4>
            <div className="flex items-center space-x-1">
              <Activity size={12} className="text-green-400" />
              <span className="text-xs text-green-400">Live</span>
            </div>
          </div>
          <div className="space-y-2">
            {recentMEVEvents.length === 0 ? (
              <div className="text-center p-4 text-gray-400 text-sm">
                {isLoading ? 'Loading MEV events...' : 'No recent MEV events'}
              </div>
            ) : (
              recentMEVEvents.slice(0, 3).map((event) => (
                <div key={event.id} className="flex items-center justify-between p-2 bg-white/5 rounded border border-white/5">
                  <div className="flex items-center space-x-2">
                    <div className={`w-2 h-2 rounded-full ${
                      event.color === 'red' ? 'bg-red-400' : event.color === 'green' ? 'bg-green-400' : 'bg-blue-400'
                    }`}></div>
                    <span className="text-sm text-gray-300">
                      {event.type === 'sandwich_blocked' ? 'Sandwich Blocked' :
                       event.type === 'frontrun_blocked' ? 'Front-run Blocked' :
                       event.type === 'mev_redistributed' ? 'MEV Captured' : event.type}
                    </span>
                  </div>
                  <div className="text-right">
                    <div className="text-sm text-white">{event.amount}</div>
                    <div className="text-xs text-gray-400">{formatTimeAgo(event.timestamp)}</div>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>

        {/* LP Rewards */}
        <div className="bg-gradient-to-r from-purple-500/10 to-pink-500/10 rounded-lg border border-purple-500/20 p-4">
          <div className="flex items-center space-x-2 mb-2">
            <Users size={16} className="text-purple-400" />
            <span className="text-sm font-medium text-white">LP Rewards Pool</span>
          </div>
          <div className="text-lg font-bold text-purple-400">
            ${(parseFloat(protocolStats.mevSaved24h) * 0.8).toLocaleString(undefined, { maximumFractionDigits: 2 })}
          </div>
          <div className="text-xs text-gray-400">Available for distribution (80% of MEV saved)</div>
        </div>
      </div>
    </div>
  )
}

export default MEVProtectionPanel