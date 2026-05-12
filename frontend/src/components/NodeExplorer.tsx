interface NodeData {
  id: string
  name: string
  status: 'active' | 'syncing' | 'offline'
  blockNumber: number
  latency: number
  peers: number
}

interface NodeExplorerProps {
  nodes: NodeData[]
}

export function NodeExplorer({ nodes }: NodeExplorerProps) {
  const activeNodes = nodes.filter(n => n.status === 'active')

  return (
    <div className="panel node-panel">
      <div className="panel-header">
        <span style={{ display: 'flex', alignItems: 'center' }}>
          <span className="dot active" />
          NODE EXPLORER
        </span>
        <span className="monospace" style={{ fontSize: 10, color: 'var(--text-dim)' }}>
          {activeNodes.length} / {nodes.length} ONLINE
        </span>
      </div>
      <div className="panel-body node-body">
        <div className="node-list">
          {nodes.map(node => (
            <div key={node.id} className={`node-row node-${node.status}`}>
              <div className="node-status-col">
                <span className={`dot ${node.status === 'active' ? 'active' : node.status === 'syncing' ? 'idle' : 'off'}`} />
                <span className="node-name">{node.name}</span>
              </div>
              <div className="node-metrics">
                <div className="node-metric-item">
                  <span className="metric-label">BLOCK</span>
                  <span className="monospace" style={{ fontSize: 13, color: 'var(--text-primary)' }}>
                    #{node.blockNumber.toLocaleString()}
                  </span>
                </div>
                <div className="node-metric-item">
                  <span className="metric-label">LATENCY</span>
                  <span className="monospace" style={{
                    fontSize: 13,
                    color: node.latency < 100 ? 'var(--perf-green)' : node.latency < 500 ? 'var(--perf-amber)' : 'var(--perf-red)',
                  }}>
                    {node.latency}ms
                  </span>
                </div>
                <div className="node-metric-item">
                  <span className="metric-label">PEERS</span>
                  <span className="monospace" style={{ fontSize: 13, color: 'var(--text-primary)' }}>
                    {node.peers}
                  </span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
