interface WorkflowData {
  type: string
  count: number
  avgGas: number
  safetyLevel: string
  color: string
}

interface WorkflowMatrixProps {
  data: WorkflowData[]
}

export function WorkflowMatrix({ data }: WorkflowMatrixProps) {
  const maxVal = Math.max(...data.map(d => d.count), 1)

  const safetyColors: Record<string, string> = {
    L0: 'var(--text-dim)',
    L1: 'var(--perf-green)',
    L2: 'var(--perf-amber)',
    L3: 'var(--perf-red)',
  }

  return (
    <div className="panel workflow-panel">
      <div className="panel-header">
        <span style={{ display: 'flex', alignItems: 'center' }}>
          <span className="dot active" />
          WORKFLOW MATRIX
        </span>
        <span className="monospace" style={{ fontSize: 10, color: 'var(--text-dim)' }}>
          {data.length} TYPES
        </span>
      </div>
      <div className="panel-body workflow-body">
        <div className="workflow-grid">
          {data.map(wf => (
            <div key={wf.type} className="workflow-item">
              <div className="workflow-item-header">
                <span className="workflow-type" style={{ color: wf.color || 'var(--monad-purple)' }}>
                  {wf.type}
                </span>
                <span className="workflow-safety" style={{ color: safetyColors[wf.safetyLevel] }}>
                  {wf.safetyLevel}
                </span>
              </div>
              <div className="workflow-bar-track">
                <div
                  className="workflow-bar"
                  style={{
                    width: `${(wf.count / maxVal) * 100}%`,
                    background: wf.color || 'var(--monad-purple)',
                  }}
                />
              </div>
              <div className="workflow-item-footer">
                <span className="monospace" style={{ fontSize: 10, color: 'var(--text-secondary)' }}>
                  {wf.count} TXS
                </span>
                <span className="monospace" style={{ fontSize: 10, color: 'var(--text-dim)' }}>
                  ~{wf.avgGas.toLocaleString()} GAS
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
