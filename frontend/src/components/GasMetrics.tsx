interface GasData {
  avgGas: number
  totalGas: number
  gasPrice: number
  baseFee: number
  utilization: number
  history: number[]
}

interface GasMetricsProps {
  data: GasData
}

export function GasMetrics({ data }: GasMetricsProps) {
  const maxGas = Math.max(...data.history, 1)

  return (
    <div className="panel gas-panel">
      <div className="panel-header">
        <span style={{ display: 'flex', alignItems: 'center' }}>
          <span className="dot active" />
          GAS METRICS
        </span>
        <span className="monospace" style={{ fontSize: 10, color: 'var(--text-dim)' }}>
          MONAD
        </span>
      </div>
      <div className="panel-body gas-body">
        <div className="gas-main-metrics">
          <div className="gas-metric">
            <span className="metric-label">AVG GAS / TX</span>
            <span className="metric-value purple" style={{ fontSize: 22 }}>
              {data.avgGas.toLocaleString()}
            </span>
          </div>
          <div className="gas-metric">
            <span className="metric-label">GAS PRICE</span>
            <span className="metric-value green" style={{ fontSize: 22 }}>
              {data.gasPrice.toFixed(2)}
              <span style={{ fontSize: 12, color: 'var(--text-secondary)' }}> GWEI</span>
            </span>
          </div>
          <div className="gas-metric">
            <span className="metric-label">BASE FEE</span>
            <span className="metric-value" style={{ fontSize: 22, color: 'var(--text-primary)' }}>
              {data.baseFee.toFixed(4)}
              <span style={{ fontSize: 12, color: 'var(--text-secondary)' }}> MON</span>
            </span>
          </div>
        </div>

        <div className="gas-chart">
          <div className="gas-chart-header">
            <span className="monospace" style={{ fontSize: 10, color: 'var(--text-dim)' }}>GAS HISTORY (24H)</span>
            <span className="monospace" style={{ fontSize: 10, color: 'var(--text-dim)' }}>
              UTIL {data.utilization}%
            </span>
          </div>
          <div className="gas-bars-container">
            {data.history.map((v, i) => (
              <div
                key={i}
                className="gas-bar"
                style={{
                  height: `${(v / maxGas) * 100}%`,
                  background: v > maxGas * 0.8
                    ? 'var(--perf-red)'
                    : v > maxGas * 0.5
                      ? 'var(--perf-amber)'
                      : 'var(--perf-green)',
                  opacity: 0.4 + (v / maxGas) * 0.6,
                }}
              />
            ))}
          </div>
        </div>

        <div className="gas-total-row">
          <div className="gas-total-item">
            <span className="metric-label">TOTAL GAS</span>
            <span className="monospace" style={{ fontSize: 14, color: 'var(--text-primary)' }}>
              {data.totalGas.toLocaleString()}
            </span>
          </div>
          <div className="gas-total-item">
            <span className="metric-label">UTILIZATION</span>
            <span className="monospace" style={{
              fontSize: 14,
              color: data.utilization > 80 ? 'var(--perf-red)' : data.utilization > 50 ? 'var(--perf-amber)' : 'var(--perf-green)',
            }}>
              {data.utilization}%
            </span>
          </div>
        </div>
      </div>
    </div>
  )
}
