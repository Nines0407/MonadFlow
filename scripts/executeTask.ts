import { createWalletClient, http, parseAbi, defineChain } from "viem"
import { privateKeyToAccount } from "viem/accounts"

const monadTestnet = defineChain({
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "Monad", symbol: "MON", decimals: 18 },
  rpcUrls: {
    default: { http: [process.env.MONAD_RPC_URL!] },
  },
})

const AGENT_HUB = process.env.AGENT_HUB_ADDRESS!
const AGENT_ID = BigInt(process.env.AGENT_ID || "1")
const NONCE = BigInt(process.env.NONCE || "1")

const abi = parseAbi([
  "function executeAgentTask(uint256 agentId, uint256 nonce, (uint8 version, uint256 deadline, bytes payload) taskData) returns (bool)",
])

async function execute() {
  const account = privateKeyToAccount(process.env.PRIVATE_KEY! as `0x${string}`)
  const client = createWalletClient({
    chain: monadTestnet,
    account,
    transport: http(process.env.MONAD_RPC_URL),
  })

  const hash = await client.writeContract({
    address: AGENT_HUB as `0x${string}`,
    abi,
    functionName: "executeAgentTask",
    args: [
      AGENT_ID,
      NONCE,
      { version: 1, deadline: 0n, payload: "0x" as `0x${string}` },
    ],
  })
  console.log("Task executed:", hash)
}

execute().catch(console.error)
