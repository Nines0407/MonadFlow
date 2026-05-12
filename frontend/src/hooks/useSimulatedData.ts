import { useState, useEffect, useCallback } from 'react'

interface AgentData {
  id: number
  owner: string
  active: boolean
  workflowType: string
  nonce: number
  lastExecution: number
  gasUsed: number
}

interface SlotData {
  id: string
  agentId: number
  x: number
  y: number
  active: boolean
  conflict: boolean
  intensity: number
}

interface WorkflowData {
  type: string
  count: number
  avgGas: number
  safetyLevel: string
  color: string
}

interface NodeData {
  id: string
  name: string
  status: 'active' | 'syncing' | 'offline'
  blockNumber: number
  latency: number
  peers: number
}

interface GasData {
  avgGas: number
  totalGas: number
  gasPrice: number
  baseFee: number
  utilization: number
  history: number[]
}

function rand(min: number, max: number) {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

function randFloat(min: number, max: number) {
  return Math.random() * (max - min) + min
}

const WORKFLOW_TYPES = [
  { type: 'DEFI_SWAP', safety: 'L2', color: '#836EFB' },
  { type: 'DEFI_LEND', safety: 'L2', color: '#7C6FF0' },
  { type: 'NFT_MINT', safety: 'L1', color: '#00FF41' },
  { type: 'NFT_TRADE', safety: 'L1', color: '#00E639' },
  { type: 'CROSS_CHAIN', safety: 'L3', color: '#FFB800' },
  { type: 'SOCIAL_NOTIFY', safety: 'L0', color: '#5C5C8A' },
  { type: 'GAME_NPC', safety: 'L1', color: '#00D4AA' },
  { type: 'CUSTOM', safety: 'L0', color: '#8888A0' },
]

const NODE_NAMES = ['eu-west-1', 'eu-west-2', 'us-east-1', 'us-east-2', 'ap-south-1', 'ap-northeast-1']

export function useSimulatedData() {
  const [tick, setTick] = useState(0)

  useEffect(() => {
    const interval = setInterval(() => setTick(t => t + 1), 1500)
    return () => clearInterval(interval)
  }, [])

  const tps = 10240 + rand(-200, 300)

  const streamData = Array.from({ length: 60 }, (_, i) =>
    9000 + Math.sin(i / 10 + tick * 0.3) * 2000 + rand(-500, 800)
  )

  const blockHeight = 1843200 + tick * rand(1, 3)

  const agents: AgentData[] = Array.from({ length: 12 }, (_, i) => {
    const wf = WORKFLOW_TYPES[i % WORKFLOW_TYPES.length]
    const active = Math.random() > 0.15
    return {
      id: i + 1,
      owner: `0x${Array.from({ length: 40 }, () => '0123456789abcdef'[rand(0, 15)]).join('')}`,
      active,
      workflowType: wf.type,
      nonce: active ? rand(10, 500) : rand(1, 10),
      lastExecution: active ? randFloat(0.1, 8) : rand(300, 3600),
      gasUsed: active ? rand(24000, 80000) : rand(20000, 80000),
    }
  })

  const slots: SlotData[] = agents.filter(a => a.active).map((a, i) => ({
    id: `slot-${a.id}`,
    agentId: a.id,
    x: (a.id - 1) % 10,
    y: Math.floor((a.id - 1) / 10),
    active: true,
    conflict: false,
    intensity: Math.random() * 0.8 + 0.2,
  }))
  // Add a couple more inactive slots
  slots.push(
    { id: 'slot-empty-1', agentId: 0, x: 8, y: 0, active: false, conflict: false, intensity: 0 },
    { id: 'slot-empty-2', agentId: 0, x: 9, y: 0, active: false, conflict: false, intensity: 0 },
    { id: 'slot-empty-3', agentId: 0, x: 0, y: 1, active: false, conflict: false, intensity: 0 },
    { id: 'slot-empty-4', agentId: 0, x: 1, y: 1, active: false, conflict: false, intensity: 0 },
    { id: 'slot-empty-5', agentId: 0, x: 2, y: 1, active: false, conflict: false, intensity: 0 },
    { id: 'slot-empty-6', agentId: 0, x: 3, y: 1, active: false, conflict: false, intensity: 0 },
    { id: 'slot-empty-7', agentId: 0, x: 4, y: 1, active: false, conflict: false, intensity: 0 },
    { id: 'slot-empty-8', agentId: 0, x: 5, y: 1, active: false, conflict: false, intensity: 0 },
  )

  const workflows: WorkflowData[] = WORKFLOW_TYPES.map(wf => ({
    type: wf.type,
    count: rand(50, 2000),
    avgGas: rand(24000, 60000),
    safetyLevel: wf.safety,
    color: wf.color,
  }))

  const nodes: NodeData[] = NODE_NAMES.map((name, i) => ({
    id: `node-${i}`,
    name,
    status: (['active', 'active', 'active', 'syncing', 'active', 'offline'] as const)[i],
    blockNumber: 1843200 + rand(-3, 0),
    latency: i === 5 ? 0 : rand(12, 450),
    peers: i === 5 ? 0 : rand(32, 128),
  }))

  const gasHistory = Array.from({ length: 48 }, () => rand(38000, 65000))
  const gas: GasData = {
    avgGas: Math.round(gasHistory.reduce((a, b) => a + b, 0) / gasHistory.length),
    totalGas: gasHistory.reduce((a, b) => a + b, 0) * tps,
    gasPrice: randFloat(0.5, 2.5),
    baseFee: randFloat(0.001, 0.005),
    utilization: rand(35, 72),
    history: gasHistory,
  }

  const evmTPS = 18 + rand(-3, 5)

  const parallelRate = 92 + rand(0, 5)
  const avgLatency = rand(200, 450)
  const occSuccess = tps - rand(0, 5)
  const txStats = {
    total: tps,
    success: tps - rand(0, 3),
    failed: rand(0, 3),
  }

  return {
    tps,
    streamData: streamData,
    blockHeight,
    agents,
    slots,
    workflows,
    nodes,
    gas,
    evmTPS,
    parallelRate,
    avgLatency,
    occSuccess,
    txStats,
  }
}
