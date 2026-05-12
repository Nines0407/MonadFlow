import {
  createWalletClient,
  createPublicClient,
  http,
  parseAbi,
  formatEther,
  parseEther,
  type WalletClient,
  type PublicClient,
} from "viem"
import { privateKeyToAccount, type PrivateKeyAccount } from "viem/accounts"
import { pad, toHex, keccak256 } from "viem"
import pLimit from "p-limit"

const AGENT_HUB = process.env.AGENT_HUB_ADDRESS!
const RPC_URL = process.env.MONAD_RPC_URL!
const FAUCET_KEY = process.env.FAUCET_PRIVATE_KEY!

if (!AGENT_HUB || !RPC_URL || !FAUCET_KEY) {
  console.error("Missing required env vars: AGENT_HUB_ADDRESS, MONAD_RPC_URL, FAUCET_PRIVATE_KEY")
  process.exit(1)
}

const abi = parseAbi([
  "function registerAgent(bytes32 workflowType) returns (uint256)",
  "function executeAgentTask(uint256 agentId, uint256 nonce, (uint8 version, uint256 deadline, bytes payload) taskData) returns (bool)",
  "function batchExecuteTasks(uint256[] agentIds, uint256[] nonces, (uint8 version, uint256 deadline, bytes payload)[] tasksData) returns (bool[])",
  "function agents(uint256) view returns (uint256 agentId, address owner, bool isActive, bytes32 workflowType, uint256 nonce)",
])

interface BenchmarkResult {
  totalTxs: number
  successTxs: number
  failedTxs: number
  totalDuration: number
  effectiveTPS: number
  avgLatency: number
  maxLatency: number
  minLatency: number
  gasUsed: bigint
}

function createBatchAccount(index: number): PrivateKeyAccount {
  const seed = keccak256(pad(toHex(index + 1), { size: 32 }))
  return privateKeyToAccount(seed)
}

async function fundAccounts(
  faucetClient: WalletClient,
  publicClient: PublicClient,
  accounts: PrivateKeyAccount[],
  amountPerAccount: bigint = parseEther("0.05"),
) {
  const nonce = await publicClient.getTransactionCount({
    address: (faucetClient as any).account.address,
  })

  const hashes: `0x${string}`[] = []
  for (let i = 0; i < accounts.length; i++) {
    const hash = await faucetClient.sendTransaction({
      to: accounts[i].address,
      value: amountPerAccount,
      nonce: nonce + i,
    })
    hashes.push(hash)
  }

  await Promise.all(hashes.map((h) => publicClient.waitForTransactionReceipt({ hash: h })))
  console.log(`  分发完成: ${accounts.length} 个账户各收到 ${formatEther(amountPerAccount)} MON`)
}

async function runBenchmark(
  accounts: PrivateKeyAccount[],
  concurrency: number = 100,
  maxConcurrent: number = 50,
): Promise<BenchmarkResult> {
  const clients = accounts.map((account) =>
    createWalletClient({ transport: http(RPC_URL), account }),
  )
  const publicClient = createPublicClient({ transport: http(RPC_URL) })

  const startTime = Date.now()
  const latencies: number[] = []
  let success = 0
  let failed = 0
  let gasUsed = 0n

  const limit = pLimit(maxConcurrent)

  const promises = clients.slice(0, concurrency).map(async (client, i) =>
    limit(async () => {
      try {
        const txStart = Date.now()
        const hash = await client.writeContract({
          address: AGENT_HUB as `0x${string}`,
          abi,
          functionName: "registerAgent",
          args: ["0x5445535400000000000000000000000000000000000000000000000000000000" as `0x${string}`],
        })

        const receipt = await publicClient.waitForTransactionReceipt({
          hash,
          timeout: 30_000,
        })

        const latency = Date.now() - txStart
        latencies.push(latency)
        success++
        gasUsed += receipt.gasUsed
        return { success: true, hash, latency }
      } catch (e) {
        failed++
        return { success: false, error: String(e) }
      }
    }),
  )

  const results = await Promise.all(promises)
  const totalDuration = (Date.now() - startTime) / 1000

  const registeredIds: bigint[] = []
  for (const r of results) {
    if (!("success" in r) || !r.success) continue
    const receipt = await publicClient.getTransactionReceipt({
      hash: (r as any).hash,
    })
    const registeredLog = receipt.logs.find(
      (log) =>
        log.topics[0] ===
        "0xe5a5a1d8b1705a9c4882a217e5c9a2c84c58efc38e7b5e38b0b7c1a3eddba90d",
    )
    if (registeredLog) {
      registeredIds.push(BigInt(registeredLog.topics[1]!))
    }
  }

  let stateValidCount = 0
  for (const id of registeredIds) {
    try {
      const agent = (await publicClient.readContract({
        address: AGENT_HUB as `0x${string}`,
        abi,
        functionName: "agents",
        args: [id],
      })) as [bigint, string, boolean, string, bigint]
      if (agent[2]) {
        stateValidCount++
      }
    } catch {
      // skip
    }
  }
  if (registeredIds.length > 0) {
    console.log(`  状态校验: ${stateValidCount}/${registeredIds.length} Agents 状态正确`)
  }

  return {
    totalTxs: concurrency,
    successTxs: success,
    failedTxs: failed,
    totalDuration,
    effectiveTPS: Math.round(success / totalDuration),
    avgLatency:
      latencies.length > 0
        ? Math.round(latencies.reduce((a, b) => a + b, 0) / latencies.length)
        : 0,
    maxLatency: latencies.length > 0 ? Math.max(...latencies) : 0,
    minLatency: latencies.length > 0 ? Math.min(...latencies) : 0,
    gasUsed,
  }
}

async function main() {
  const configs = [10, 50, 100, 500, 1000]

  console.log("═══════════════════════════════════════════════════")
  console.log("  MonadFlow 并发压力测试")
  console.log("═══════════════════════════════════════════════════\n")

  const faucetAccount = privateKeyToAccount(FAUCET_KEY as `0x${string}`)
  const faucetClient = createWalletClient({
    transport: http(RPC_URL),
    account: faucetAccount,
  })
  const publicClient = createPublicClient({ transport: http(RPC_URL) })

  const maxConcurrency = Math.max(...configs)
  const accounts = Array.from({ length: maxConcurrency }, (_, i) => createBatchAccount(i))

  console.log(">>> 资金分发 (funding)...")
  await fundAccounts(faucetClient, publicClient, accounts)
  await new Promise((resolve) => setTimeout(resolve, 3000))

  console.log(">>> 预热阶段 (warmup)...")
  await runBenchmark(accounts, 5)
  await new Promise((resolve) => setTimeout(resolve, 2000))

  for (const concurrency of configs) {
    console.log(`\n>>> 并发数: ${concurrency}`)
    const result = await runBenchmark(accounts, concurrency)

    console.log(`  总交易:     ${result.totalTxs}`)
    console.log(`  成功:       ${result.successTxs}`)
    console.log(`  失败:       ${result.failedTxs}`)
    console.log(`  耗时:       ${result.totalDuration.toFixed(2)}s`)
    console.log(`  有效 TPS:   ${result.effectiveTPS}`)
    console.log(`  平均延迟:   ${result.avgLatency}ms`)
    console.log(`  最大延迟:   ${result.maxLatency}ms`)
    console.log(`  最小延迟:   ${result.minLatency}ms`)
    console.log(`  总 Gas:     ${formatEther(result.gasUsed)} MON`)
  }
}

main().catch(console.error)
