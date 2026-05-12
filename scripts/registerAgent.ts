import { createWalletClient, http, parseAbi, toBytes, defineChain } from "viem"
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

const abi = parseAbi([
  "function registerAgent(bytes32 workflowType) returns (uint256)",
])

async function register() {
  const account = privateKeyToAccount(process.env.PRIVATE_KEY! as `0x${string}`)
  const client = createWalletClient({
    chain: monadTestnet,
    account,
    transport: http(process.env.MONAD_RPC_URL),
  })

  const hash = await client.writeContract({
    address: AGENT_HUB as `0x${string}`,
    abi,
    functionName: "registerAgent",
    args: [toBytes("DEFI_SWAP", { size: 32 })],
  })
  console.log("Agent registered:", hash)
}

register().catch(console.error)
