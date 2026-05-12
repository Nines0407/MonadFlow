import { useMemo } from 'react'

interface SlotData {
  id: string
  agentId: number
  x: number
  y: number
  active: boolean
  conflict: boolean
  intensity: number
}

interface StorageHeatmapProps {
  data: SlotData[]
}

export function StorageHeatmap({ data }: StorageHeatmapProps) {
  const gridSize = 10
  const activeCount = data.filter(d => d.active).length
  const conflictCount = data.filter(d => d.conflict).length

  const cells = useMemo(() => {
    const result: { row: number; col: number; slot: SlotData | null }[] = []
    for (let row = 0; row < gridSize; row++) {
      for (let col = 0; col < gridSize; col++) {
        const slot = data.find(d => d.x === col && d.y === row) || null
        result.push({ row, col, slot })
      }
    }
    return result
  }, [data])

  const parallelRate = activeCount > 0 ? Math.round((1 - conflictCount / activeCount) * 100) : 100

  return (
    <div className="panel heatmap-panel">
      <div className="panel-header">
        <span style={{ display: 'flex', alignItems: 'center' }}>
          <span className="dot active" />
          STORAGE SLOT HEATMAP
        </span>
        <span className="monospace" style={{ fontSize: 10, color: 'var(--text-dim)' }}>
          {gridSize}x{gridSize} — 0 CONFLICTS
        </span>
      </div>
      <div className="panel-body heatmap-body">
        <div className="heatmap-meta">
          <div className="heatmap-stat">
            <span className="metric-label">ACTIVE SLOTS</span>
            <span className="metric-value green" style={{ fontSize: 20 }}>{activeCount}</span>
          </div>
          <div className="heatmap-stat">
            <span className="metric-label">CONFLICTS</span>
            <span className="metric-value" style={{
              fontSize: 20,
              color: conflictCount > 0 ? 'var(--perf-red)' : 'var(--perf-green)',
            }}>
              {conflictCount}
            </span>
          </div>
          <div className="heatmap-stat">
            <span className="metric-label">PARALLEL RATE</span>
            <span className="metric-value purple" style={{ fontSize: 20 }}>
              {parallelRate}%
            </span>
          </div>
        </div>

        <div className="heatmap-grid">
          <div className="heatmap-scene">
            <div className="heatmap-base-plane" />
            <div className="heatmap-perspective-layer">
              {cells.map(({ row, col, slot }) => {
                const z = slot?.active ? (slot.conflict ? 8 : 12 + slot.intensity * 16) : 1
                const hue = slot?.conflict ? 0 : slot?.active ? 135 : 0
                const sat = slot?.active ? '80%' : '0%'
                const light = slot?.active ? '50%' : '8%'
                const alpha = slot?.active ? 0.7 + slot.intensity * 0.3 : 0.08

                return (
                  <div
                    key={`${row}-${col}`}
                    className="heatmap-cell-3d"
                    style={{
                      gridRow: row + 1,
                      gridColumn: col + 1,
                      transform: `translateZ(${z}px)`,
                      background: `hsl(${hue}, ${sat}, ${light})`,
                      opacity: alpha,
                      boxShadow: slot?.active
                        ? slot.conflict
                          ? `0 0 ${6 + slot.intensity * 8}px rgba(255,59,48,${0.25 + slot.intensity * 0.5})`
                          : `0 0 ${4 + slot.intensity * 6}px rgba(0,255,65,${0.2 + slot.intensity * 0.4})`
                        : 'none',
                      borderColor: slot?.active
                        ? slot.conflict
                          ? 'rgba(255,59,48,0.3)'
                          : 'rgba(0,255,65,0.2)'
                        : 'rgba(255,255,255,0.04)',
                    }}
                  >
                    {slot?.active && (
                      <span className="cell-label">{slot.agentId}</span>
                    )}
                  </div>
                )
              })}
            </div>
            <div className="heatmap-grid-lines">
              {Array.from({ length: gridSize + 1 }, (_, i) => (
                <div
                  key={`h-${i}`}
                  className="grid-line-h"
                  style={{ top: `${(i / gridSize) * 100}%` }}
                />
              ))}
              {Array.from({ length: gridSize + 1 }, (_, i) => (
                <div
                  key={`v-${i}`}
                  className="grid-line-v"
                  style={{ left: `${(i / gridSize) * 100}%` }}
                />
              ))}
            </div>
          </div>
        </div>

        <div className="heatmap-legend">
          <span><span className="legend-dot empty" /> EMPTY</span>
          <span><span className="legend-dot active" /> ACTIVE</span>
          <span><span className="legend-dot conflict" /> CONFLICT</span>
        </div>
      </div>
    </div>
  )
}
