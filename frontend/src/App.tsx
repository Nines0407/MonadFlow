import './styles/app.css'
import { useSimulatedData } from './hooks/useSimulatedData'
import { TPSStream } from './components/TPSStream'
import { StorageHeatmap } from './components/StorageHeatmap'
import { AgentPanel } from './components/AgentPanel'
import { GasMetrics } from './components/GasMetrics'
import { WorkflowMatrix } from './components/WorkflowMatrix'
import { ThroughputComparison } from './components/ThroughputComparison'
import { NodeExplorer } from './components/NodeExplorer'
import { ScanLines } from './components/ScanLines'

export default function App() {
  const data = useSimulatedData()

  return (
    <div className="app-shell">
      <ScanLines />
      <Header />
      <div className="bento-grid">
        <div className="bento-area hero-stream">
          <TPSStream data={data.streamData} tps={data.tps} />
        </div>
        <div className="bento-area hero-heatmap">
          <StorageHeatmap data={data.slots} />
        </div>
        <div className="bento-area metrics-top">
          <GasMetrics data={data.gas} />
        </div>
        <div className="bento-area agents">
          <AgentPanel agents={data.agents} />
        </div>
        <div className="bento-area comparison">
          <ThroughputComparison evmTPS={data.evmTPS} monadTPS={data.tps} />
        </div>
        <div className="bento-area workflows">
          <WorkflowMatrix data={data.workflows} />
        </div>
        <div className="bento-area nodes">
          <NodeExplorer nodes={data.nodes} />
        </div>
      </div>
      <StatusBar data={data} />
    </div>
  )
}

function Header() {
  return (
    <header className="app-header">
      <div className="header-left">
        <span className="logo-icon">◈</span>
        <span className="logo-text">MONAD</span>
        <span className="logo-sub">FLOW</span>
        <span className="header-divider">|</span>
        <span className="header-label">PARALLEL EXECUTION ENGINE</span>
        <span className="header-badge">V1.0.0</span>
      </div>
      <div className="header-right">
        <span className="header-clock">
          {new Date().toLocaleTimeString('en-US', { hour12: false })} UTC
        </span>
        <span className="header-divider">|</span>
        <span className="header-status">
          <span className="dot active" />
          OPERATIONAL
        </span>
        <span className="header-divider">|</span>
        <span className="header-chain">CHAIN: MONAD TESTNET</span>
      </div>
    </header>
  )
}

function StatusBar({ data }: { data: ReturnType<typeof useSimulatedData> }) {
  const blockHeight = data.blockHeight.toLocaleString()
  const activeAgents = data.agents.filter(a => a.active).length
  const successRate = data.txStats.total > 0
    ? ((data.txStats.success / data.txStats.total) * 100).toFixed(1)
    : '100.0'

  return (
    <footer className="status-bar">
      <div className="status-item">
        <span className="status-key">BLOCK</span>
        <span className="status-value">#{blockHeight}</span>
      </div>
      <div className="status-item">
        <span className="status-key">TPS</span>
        <span className="status-value green">{data.tps.toLocaleString()}</span>
      </div>
      <div className="status-item">
        <span className="status-key">AGENTS</span>
        <span className="status-value">{activeAgents}/{data.agents.length}</span>
      </div>
      <div className="status-item">
        <span className="status-key">SUCCESS</span>
        <span className="status-value green">{successRate}%</span>
      </div>
      <div className="status-item">
        <span className="status-key">PARALLEL</span>
        <span className="status-value purple">{data.parallelRate}%</span>
      </div>
      <div className="status-item">
        <span className="status-key">LATENCY</span>
        <span className="status-value">{data.avgLatency}ms</span>
      </div>
      <div className="status-item">
        <span className="status-key">OCC</span>
        <span className="status-value green">{data.occSuccess}</span>
      </div>
      <div className="status-item status-right">
        <span className="status-key">NODE</span>
        <span className="status-value">eu.monad.xyz:443</span>
      </div>
    </footer>
  )
}
