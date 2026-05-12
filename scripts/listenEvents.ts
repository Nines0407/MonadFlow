import { createPublicClient, http, parseAbi, defineChain } from "viem"

const monadTestnet = defineChain({
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "Monad", symbol: "MON", decimals: 18 },
  rpcUrls: {
    default: { http: [process.env.MONAD_RPC_URL!] },
  },
})

const AGENT_HUB = process.env.AGENT_HUB_ADDRESS!

const abi = parseAbi([
  "event AgentRegistered(uint256 indexed agentId, address indexed owner, bytes32 workflowType, uint8 version, uint256 timestamp)",
  "event AgentExecuted(uint256 indexed agentId, uint8 indexed version, bytes32 indexed executionId, bytes taskData, uint256 nonce, uint256 timestamp, bool success)",
  "event AgentDeactivated(uint256 indexed agentId, uint8 version, uint256 timestamp)",
  "event Paused(address indexed initiator, uint8 version, uint256 timestamp)",
  "event Unpaused(address indexed initiator, uint8 version, uint256 timestamp)",
])

async function watchAgentEvents() {
  const publicClient = createPublicClient({
    chain: monadTestnet,
    transport: http(process.env.MONAD_RPC_URL),
  })

  console.log(`Watching events on ${AGENT_HUB}...`)

  publicClient.watchContractEvent({
    address: AGENT_HUB as `0x${string}`,
    abi,
    eventName: "AgentExecuted",
    onLogs: (logs) => {
      for (const log of logs) {
        const agentId = log.args.agentId
        const nonce = log.args.nonce
        const success = log.args.success
        const timestamp = log.args.timestamp
        console.log(
          `[${new Date(Number(timestamp) * 1000).toISOString()}] Agent ${agentId} executed (nonce: ${nonce}, success: ${success})`,
        )
      }
    },
  })
}

watchAgentEvents().catch(console.error)
