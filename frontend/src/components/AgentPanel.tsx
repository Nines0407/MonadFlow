interface AgentData {
  id: number
  owner: string
  active: boolean
  workflowType: string
  nonce: number
  lastExecution: number
  gasUsed: number
}

interface AgentPanelProps {
  agents: AgentData[]
}

export function AgentPanel({ agents }: AgentPanelProps) {
  const activeAgents = agents.filter(a => a.active)
  const inactiveAgents = agents.filter(a => !a.active)

  return (
    <div className="panel agent-panel">
      <div className="panel-header">
        <span style={{ display: 'flex', alignItems: 'center' }}>
          <span className="dot active" />
          AGENT REGISTRY
        </span>
        <span className="monospace" style={{ fontSize: 10, color: 'var(--text-dim)' }}>
          {activeAgents.length} / {agents.length} ACTIVE
        </span>
      </div>
      <div className="panel-body agent-body">
        <div className="agent-list">
          {agents.map(agent => (
            <div key={agent.id} className={`agent-row ${agent.active ? '' : 'inactive'}`}>
              <div className="agent-id-col">
                <span className="agent-dot-wrapper">
                  <span className={`dot ${agent.active ? 'active' : 'off'}`} />
                </span>
                <span className="agent-id">#{agent.id}</span>
              </div>
              <div className="agent-type-col">
                <span className="agent-type-badge">{agent.workflowType}</span>
              </div>
              <div className="agent-owner-col" title={agent.owner}>
                {agent.owner.slice(0, 6)}...{agent.owner.slice(-4)}
              </div>
              <div className="agent-nonce-col">
                <span className="agent-nonce-label">NONCE</span>
                <span className="agent-nonce-val">{agent.nonce}</span>
              </div>
              <div className="agent-gas-col">
                <span className="agent-gas-val">{agent.gasUsed.toLocaleString()}</span>
                <span className="agent-gas-label">GAS</span>
              </div>
              <div className="agent-latency-col">
                <span className={`agent-latency ${agent.lastExecution < 2 ? 'fast' : agent.lastExecution < 5 ? 'med' : 'slow'}`}>
                  {agent.lastExecution}s
                </span>
              </div>
            </div>
          ))}
        </div>
        {inactiveAgents.length > 0 && (
          <div className="agent-inactive-bar">
            {inactiveAgents.length} AGENTS INACTIVE
          </div>
        )}
      </div>
    </div>
  )
}
