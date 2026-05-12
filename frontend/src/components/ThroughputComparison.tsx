interface ThroughputComparisonProps {
  evmTPS: number
  monadTPS: number
}

export function ThroughputComparison({ evmTPS, monadTPS }: ThroughputComparisonProps) {
  const ratio = evmTPS > 0 ? (monadTPS / evmTPS).toFixed(0) : '∞'
  const totalMax = Math.max(evmTPS, monadTPS)
  const evmPct = totalMax > 0 ? (evmTPS / totalMax) * 100 : 0
  const monadPct = 100

  return (
    <div className="panel comparison-panel">
      <div className="panel-header">
        <span style={{ display: 'flex', alignItems: 'center' }}>
          <span className="dot active" />
          THROUGHPUT COMPARISON
        </span>
        <span className="comparison-ratio monospace">
          <span className="ratio-value">{ratio}x</span>
        </span>
      </div>
      <div className="panel-body comparison-body">
        <div className="comparison-left">
          <div className="comp-label-group">
            <span className="comp-chain-label">ETH</span>
            <span className="comp-tps">{evmTPS} TPS</span>
          </div>
          <div className="comp-bar-track">
            <div className="comp-bar-fill evm" style={{ height: `${Math.max(evmPct, 2)}%` }} />
          </div>
        </div>

        <div className="comparison-center">
          <div className="comp-ratio-display">
            <span className="ratio-big">{ratio}x</span>
            <span className="ratio-desc">THROUGHPUT</span>
          </div>
        </div>

        <div className="comparison-right">
          <div className="comp-label-group">
            <span className="comp-chain-label monad">MONAD</span>
            <span className="comp-tps monad">{monadTPS.toLocaleString()} TPS</span>
          </div>
          <div className="comp-bar-track">
            <div
              className="comp-bar-fill monad"
              style={{ height: '100%' }}
            />
            <div className="comp-particles">
              {Array.from({ length: 6 }, (_, i) => (
                <div
                  key={i}
                  className="comp-particle"
                  style={{
                    animationDelay: `${i * 0.5}s`,
                    left: `${10 + i * 15}%`,
                  }}
                />
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
