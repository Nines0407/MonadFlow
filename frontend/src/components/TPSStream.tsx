import { useMemo } from 'react'

interface TPSStreamProps {
  data: number[]
  tps: number
}

export function TPSStream({ data, tps }: TPSStreamProps) {
  const maxVal = Math.max(...data, 1)
  const points = useMemo(() =>
    data.map((v, i) => `${(i / (data.length - 1)) * 100},${100 - (v / maxVal) * 100}`).join(' '),
    [data, maxVal],
  )

  const barData = data.slice(-60)
  const avgBar = barData.reduce((a, b) => a + b, 0) / barData.length
  const peakBar = maxVal

  return (
    <div className="panel tps-stream-panel">
      <div className="panel-header">
        <span style={{ display: 'flex', alignItems: 'center' }}>
          <span className="dot active" />
          PARALLEL STREAMS
        </span>
        <span className="tps-live-badge monospace">
          <span className="live-pulse" />
          LIVE
        </span>
      </div>
      <div className="panel-body tps-stream-body">
        <div className="tps-hero">
          <div className="tps-value-group">
            <div className="tps-value">
              <span className="metric-value purple">{tps.toLocaleString()}</span>
              <span className="tps-unit">TPS</span>
            </div>
            <div className="tps-secondary-stats">
              <div className="tps-stat-mini">
                <span className="metric-label">PEAK</span>
                <span className="monospace" style={{ fontSize: 12, color: 'var(--text-primary)', fontWeight: 500 }}>
                  {peakBar.toLocaleString()}
                </span>
              </div>
              <div className="tps-stat-mini">
                <span className="metric-label">AVG</span>
                <span className="monospace" style={{ fontSize: 12, color: 'var(--text-secondary)', fontWeight: 500 }}>
                  {Math.round(avgBar).toLocaleString()}
                </span>
              </div>
              <div className="tps-stat-mini">
                <span className="metric-label">CONFLICTS</span>
                <span className="monospace green" style={{ fontSize: 12, fontWeight: 600 }}>0</span>
              </div>
            </div>
          </div>
        </div>

        <div className="stream-canvas">
          <svg viewBox="0 0 100 100" preserveAspectRatio="none" className="stream-svg">
            <defs>
              <linearGradient id="streamGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="var(--monad-purple)" stopOpacity="0.7" />
                <stop offset="40%" stopColor="var(--monad-purple)" stopOpacity="0.3" />
                <stop offset="100%" stopColor="var(--monad-purple)" stopOpacity="0.02" />
              </linearGradient>
              <linearGradient id="streamLine" x1="0" y1="0" x2="1" y2="0">
                <stop offset="0%" stopColor="var(--monad-purple)" stopOpacity="0.1">
                  <animate attributeName="offset" values="0;1" dur="2s" repeatCount="indefinite" />
                </stop>
              </linearGradient>
              <filter id="streamGlow">
                <feGaussianBlur stdDeviation="0.3" result="blur" />
                <feMerge>
                  <feMergeNode in="blur" />
                  <feMergeNode in="SourceGraphic" />
                </feMerge>
              </filter>
            </defs>
            <polyline
              points={points}
              fill="url(#streamGrad)"
              stroke="var(--monad-purple)"
              strokeWidth="0.25"
              vectorEffect="non-scaling-stroke"
              filter="url(#streamGlow)"
            />
            <polyline
              points={points}
              fill="none"
              stroke="var(--perf-green)"
              strokeWidth="0.12"
              opacity="0.6"
              vectorEffect="non-scaling-stroke"
            />
          </svg>

          <div className="kinetic-stream-container">
            {Array.from({ length: 15 }, (_, i) => (
              <div
                key={`flow-${i}`}
                className="flow-stream-line"
                style={{
                  left: `${(i / 15) * 100}%`,
                  animationDelay: `${i * 0.8}s`,
                  animationDuration: `${1.8 + Math.random() * 2.5}s`,
                  width: `${1 + Math.random() * 2}px`,
                  opacity: 0.08 + Math.random() * 0.22,
                }}
              />
            ))}
          </div>

          <div className="packet-field">
            {Array.from({ length: 40 }, (_, i) => (
              <div
                key={`pkt-${i}`}
                className="flow-packet"
                style={{
                  left: `${Math.random() * 96}%`,
                  animationDelay: `${Math.random() * 4}s`,
                  animationDuration: `${0.6 + Math.random() * 2.2}s`,
                  width: `${2 + Math.random() * 5}px`,
                  height: `${1 + Math.random() * 2}px`,
                }}
              />
            ))}
          </div>

          <div className="stream-grid-overlay" />
        </div>

        <div className="tps-bars">
          {barData.map((v, i) => (
            <div
              key={`bar-${i}`}
              className="tps-bar"
              style={{
                height: `${(v / maxVal) * 100}%`,
                opacity: 0.3 + (v / maxVal) * 0.7,
              }}
            />
          ))}
        </div>
      </div>
    </div>
  )
}
