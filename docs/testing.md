# 测试与压测指南

## 一、测试策略

```
单元测试 ──→ 集成测试 ──→ Fork 测试 ──→ 压力测试
  (Foundry)    (Foundry)    (Monad 测试网)   (并发脚本)
```

---

## 二、单元测试

### 2.1 覆盖目标

| 合约 | 行覆盖率 | 分支覆盖率 | 函数覆盖 |
|------|---------|-----------|---------|
| MonadAgentHub | 100% | 100% | 100% |
| AgentRegistry | 100% | 100% | 100% |
| WorkflowExecutor | ≥95% | ≥95% | 100% |

### 2.2 关键测试用例

```solidity
// test/AgentHub.t.sol
contract AgentHubTest is Test {
    MonadAgentHub public hub;
    address owner = address(0x1);

    function setUp() public {
        vm.prank(owner);
        hub = new MonadAgentHub(address(0));
    }

    function testRegisterAgent() public {
        vm.prank(owner);
        uint256 id = hub.registerAgent(bytes32("DEFI_SWAP"));
        assertEq(id, 1);
        (uint256 agentId, address owner_, bool active,) = hub.agents(id);
        assertEq(owner_, owner);
        assertTrue(active);
    }

    function testExecuteAgentTask() public {
        vm.startPrank(owner);
        uint256 id = hub.registerAgent(bytes32("DEFI_SWAP"));
        TaskData memory taskData = TaskData({
            version: 1,
            deadline: 0,
            payload: hex""
        });
        bool success = hub.executeAgentTask(id, 1, taskData);
        assertTrue(success);
        vm.stopPrank();
    }

    function testNonOwnerCannotExecute() public {
        vm.prank(owner);
        uint256 id = hub.registerAgent(bytes32("DEFI_SWAP"));
        vm.prank(address(0x2));
        vm.expectRevert(abi.encodeWithSelector(
            NotAgentOwner.selector, id, address(0x2), owner
        ));
        TaskData memory taskData = TaskData({
            version: 1,
            deadline: 0,
            payload: hex""
        });
        hub.executeAgentTask(id, 1, taskData);
    }

    function testDeactivateAgent() public {
        vm.startPrank(owner);
        uint256 id = hub.registerAgent(bytes32("DEFI_SWAP"));
        hub.deactivateAgent(id);
        vm.expectRevert(abi.encodeWithSelector(
            AgentInactive.selector, id
        ));
        TaskData memory taskData = TaskData({
            version: 1,
            deadline: 0,
            payload: hex""
        });
        hub.executeAgentTask(id, 1, taskData);
        vm.stopPrank();
    }

    function testNonceReplayProtection() public {
        vm.startPrank(owner);
        uint256 id = hub.registerAgent(bytes32("TEST"));
        hub.executeAgentTask(id, 1, taskData);
        vm.expectRevert(abi.encodeWithSelector(
            InvalidNonce.selector, id, 1, 2
        ));
        hub.executeAgentTask(id, 1, taskData);
        vm.stopPrank();
    }
}
```

### 2.3 并行场景测试

```solidity
// test/ParallelTest.t.sol
contract ParallelTest is Test {
    MonadAgentHub public hub;
    address[] owners;
    uint256[] agentIds;

    function setUp() public {
        hub = new MonadAgentHub(address(0));
        owners = new address[](100);

        for (uint256 i = 0; i < 100; i++) {
            owners[i] = address(uint160(uint256(keccak256(abi.encode(i)))));
            vm.prank(owners[i]);
            agentIds.push(hub.registerAgent(bytes32("TEST")));
        }
    }

    // 模拟 Monad 并行：100 个不同 Agent 同时执行 → 无冲突
    // ⚠️ 注意：Foundry 测试在单 EVM 实例中串行执行所有交易，
    // 因此本测试仅验证功能正确性（无 revert），不验证真正的并行执行行为。
    // 真正的并行性必须在 Monad 测试网/主网上通过并发 RPC 提交来验证。
    function testMassiveParallelExecution() public {
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(owners[i]);
            TaskData memory taskData = TaskData({
                version: 1,
                deadline: 0,
                payload: abi.encode(i)
            });
            bool success = hub.executeAgentTask(agentIds[i], 1, taskData);
            assertTrue(success);
        }
    }
}
```

---

## 三、Fork 测试

```bash
# 在 Monad 测试网 fork 上进行集成测试
forge test \
  --fork-url $MONAD_RPC_URL \
  --match-path test/fork/Integration.t.sol \
  -vvvv
```

---

## 四、并发压力测试

### 4.1 压测脚本（含资金分发）

```typescript
// scripts/benchmark.ts
import {
  createWalletClient,
  createPublicClient,
  http,
  parseAbi,
  formatEther,
  parseEther,
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { pad, toHex, keccak256 } from 'viem'
import pLimit from 'p-limit'

const AGENT_HUB = '0xYOUR_AGENT_HUB'
const RPC_URL = process.env.MONAD_RPC_URL!
const FAUCET_KEY = process.env.FAUCET_PRIVATE_KEY!  // 持有 MON 的主账户

const abi = parseAbi([
  'function registerAgent(bytes32 workflowType) returns (uint256)',
  'function executeAgentTask(uint256 agentId, bytes taskData) returns (bool)',
  'function batchExecuteTasks(uint256[] agentIds, uint256[] nonces, TaskData[] tasksData) returns (bool[])',
])

interface BenchmarkResult { /* ... same as before ... */ }

// 从主账户向批量地址分发资金
async function fundAccounts(
  faucetClient: ReturnType<typeof createWalletClient>,
  publicClient: ReturnType<typeof createPublicClient>,
  accounts: ReturnType<typeof privateKeyToAccount>[],
  amountPerAccount: bigint = parseEther('0.05')  // 0.05 MON per account
) {
  const nonce = await publicClient.getTransactionCount({
    address: faucetClient.account.address,
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

  await Promise.all(
    hashes.map((h) => publicClient.waitForTransactionReceipt({ hash: h }))
  )
  console.log(`  分发完成: ${accounts.length} 个账户各收到 ${formatEther(amountPerAccount)} MON`)
}

function createBatchAccount(index: number) {
  // 使用确定性种子生成，便于复现
  const seed = keccak256(pad(toHex(index + 1), { size: 32 }))
  return privateKeyToAccount(seed)
}

async function runBenchmark(
  accounts: ReturnType<typeof privateKeyToAccount>[],
  concurrency: number = 100,
  maxConcurrent: number = 50
): Promise<BenchmarkResult> {
  const clients = accounts.map((account) =>
    createWalletClient({ transport: http(RPC_URL), account })
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
          address: AGENT_HUB,
          abi,
          functionName: 'registerAgent',
          args: ['0x5445535400000000000000000000000000000000000000000000000000000000'],
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
    })
  )

  const results = await Promise.all(promises)
  const totalDuration = (Date.now() - startTime) / 1000

  // 状态正确性校验：从交易 receipt 解析 AgentRegistered 事件，验证 AgentID
  const registeredIds: bigint[] = []
  for (const r of results) {
    if (!r.success) continue
    // 从 receipt logs 中提取 AgentRegistered 事件的 agentId (topic[1])
    const receipt = await publicClient.getTransactionReceipt({ hash: r.hash })
    const registeredLog = receipt.logs.find(
      (log) => log.topics[0] === '0x...AGENT_REGISTERED_EVENT_SIG...' // AgentRegistered 事件签名
    )
    if (registeredLog) {
      registeredIds.push(BigInt(registeredLog.topics[1]!))
    }
  }

  // 验证每个已注册 Agent 在链上状态正确
  let stateValidCount = 0
  for (const id of registeredIds) {
    const agent = await publicClient.readContract({
      address: AGENT_HUB,
      abi,
      functionName: 'agents',
      args: [id],
    })
    if (agent && agent[2]) { // isActive === true
      stateValidCount++
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
    avgLatency: latencies.length > 0
      ? Math.round(latencies.reduce((a, b) => a + b, 0) / latencies.length)
      : 0,
    maxLatency: latencies.length > 0 ? Math.max(...latencies) : 0,
    minLatency: latencies.length > 0 ? Math.min(...latencies) : 0,
    gasUsed,
  }
}

async function main() {
  const configs = [10, 50, 100, 500, 1000]

  console.log('═══════════════════════════════════════════════════')
  console.log('  MonadFlow 并发压力测试')
  console.log('═══════════════════════════════════════════════════\n')

  // 准备资金分发账户
  const faucetAccount = privateKeyToAccount(process.env.FAUCET_PRIVATE_KEY!)
  const faucetClient = createWalletClient({
    transport: http(RPC_URL),
    account: faucetAccount,
  })
  const publicClient = createPublicClient({ transport: http(RPC_URL) })

  const maxConcurrency = Math.max(...configs)
  const accounts = Array.from({ length: maxConcurrency }, (_, i) =>
    createBatchAccount(i)
  )

  // 1. 分发测试资金
  console.log('>>> 资金分发 (funding)...')
  await fundAccounts(faucetClient, publicClient, accounts)
  await new Promise((resolve) => setTimeout(resolve, 3000))

  // 2. 预热交易（不计入结果）
  console.log('>>> 预热阶段 (warmup)...')
  await runBenchmark(accounts, 5)
  await new Promise((resolve) => setTimeout(resolve, 2000))

  for (const concurrency of configs) {
    console.log(`>>> 并发数: ${concurrency}`)
    const result = await runBenchmark(accounts, concurrency)
    // ... rest unchanged ...

    console.log(`  总交易:     ${result.totalTxs}`)
    console.log(`  成功:       ${result.successTxs}`)
    console.log(`  失败:       ${result.failedTxs}`)
    console.log(`  耗时:       ${result.totalDuration.toFixed(2)}s`)
    console.log(`  有效 TPS:   ${result.effectiveTPS}`)
    console.log(`  平均延迟:   ${result.avgLatency}ms`)
    console.log(`  最大延迟:   ${result.maxLatency}ms`)
    console.log(`  最小延迟:   ${result.minLatency}ms`)
    console.log(`  总 Gas:     ${formatEther(result.gasUsed)} MON`)
    console.log('')
  }
}

main()
```

### 4.2 批量 Agent 任务压测

```typescript
// scripts/benchmarkParallel.ts
async function runParallelTaskBenchmark(agentCount: number) {
  // 1. 预先注册 N 个 Agent
  const agentIds: bigint[] = []
  for (let i = 0; i < agentCount; i++) {
    const id = await registerAgent(createBatchAccount(i), bytes32('TEST'))
    agentIds.push(id)
  }

  // 2. 并发执行 Agent 任务
  const start = Date.now()
  const promises = agentIds.map((id, i) =>
    executeAgentTask(createBatchAccount(i), id, encodedTask(i))
  )
  const receipts = await Promise.all(promises)

  const duration = (Date.now() - start) / 1000
  const tps = Math.round(agentCount / duration)

  console.log(`${agentCount} Agent 并行执行: ${tps} TPS, ${duration}s`)
}
```

### 4.3 运行压测

```bash
# TypeScript 压测
npx tsx scripts/benchmark.ts

# 输出示例:
# ═══════════════════════════════════════════════════
#   MonadFlow 并发压力测试
# ═══════════════════════════════════════════════════
#
# >>> 并发数: 100
#   总交易:     100
#   成功:       100
#   失败:       0
#   耗时:        2.3s
#   有效 TPS:   43       ← RPC 限制
# >>> 并发数: 500
#   有效 TPS:   89
# >>> 并发数: 1000
#   有效 TPS:   142
```

---

## 五、性能基准

### 5.1 测试环境

| 参数 | 值 |
|------|-----|
| Monad 版本 | 测试网 v0.x |
| RPC 提供方 | Monad 官方公共 RPC |
| 压测客户端 | AWS t3.xlarge (4 vCPU, 16GB RAM) |
| 网络延迟 (P50) | <50ms |
| 并发连接数控制 | 单 IP 最大 200 并发 |
| 预热交易数 | 10 |

| 指标 | 目标 | Monad 测试网预期 | Monad 主网预期 |
|------|------|-----------------|---------------|
| 最大并发 Agent 数 | 1,000+ | 500 | 10,000+ |
| TPS (Agent 任务) | 1,000+ | 100-500 | 1,000-10,000 |
| 并行率 | ≥90% | ≥90% | ≥95% |
| 任务确认延迟 | <1s | 1-3s | <1s |
| 批量执行 Gas 节省 | ≥30% | 20-40% | 30-60% |

### 5.2 对比基线

> **注意**：以下数据为设计预期，非实测值。基线测试需在以下条件下执行并记录结果：
> - Monad 测试网：指定区块高度和测试日期
> - 以太坊 Sepolia 测试网：使用 `geth v1.14.x` 节点，`--syncmode snap`，相同合约逻辑部署
> - 所有结果附 Tx Hash 列表供第三方验证

| 场景 | 以太坊 Sepolia TPS | MonadFlow TPS | 提升倍数 | 验证状态 |
|------|-------------------|---------------|---------|---------|
| 100 Agent 并发 | TBD (实测后填入) | TBD | TBD | ⬜ 待验证 |
| 500 Agent 并发 | TBD | TBD | TBD | ⬜ 待验证 |
| 1000 Agent 并发 | TBD | TBD | TBD | ⬜ 待验证 |

> 基准测试结果填入本表后，附 Tx Hash 清单至 `benchmarks/results-YYYYMMDD.json`。

---

## 六、测试报告模板

```markdown
## 测试报告 vX.X.X

### 环境
- Monad 版本: v0.x
- 区块高度: xxxxx
- 合约地址: 0x...
- 测试时间: 2024-xx-xx

### 单元测试
- 总用例: xxx | 通过: xxx | 失败: 0
- 覆盖率: 行 xx% | 分支 xx% | 函数 xx%

### 压力测试
| 并发数 | 成功 | 失败 | TPS | 延迟(avg) |
|--------|------|------|-----|------------|
| 100 | 100 | 0 | 43 | 2.3s |
| 500 | 500 | 0 | 89 | 5.6s |
| 1000 | 998 | 2 | 142 | 7.0s |

### 结论
- ✅ TPS 达到目标
- ✅ 0% 逻辑失败
- ⚠️ RPC 层成为瓶颈，需要进一步的并发优化
```

---

## 七、形式化验证

### 7.1 核心 Invariant

```
// Invariant 1: Agent 状态隔离
// Agent A 的操作永远不会改变 Agent B 的内部状态
invariant agentIsolation(uint256 a, uint256 b)
    a != b
    => stateAfter(agentA_operation) == stateBefore(for_agentB)

// Invariant 2: 权限一致性
// 仅 agent.owner 可执行该 agent 的任务
invariant ownerOnlyExecution(uint256 agentId, address caller)
    caller != agent[agentId].owner
    => revert(executeAgentTask(agentId, _))

// Invariant 3: Nonce 单调递增
// 每个 agent 的执行计数只增不减
invariant executionCounterMonotonic(uint256 agentId)
    afterExecution.counter >= beforeExecution.counter

// Invariant 4: totalAgents 一致性
// totalAgents == 注册成功次数 - 正确注销次数
invariant totalAgentsCorrect()
    totalAgents == registeredAgentCount - deactivatedAgentCount
```

### 7.2 工具选型

| 工具 | 用途 | 阶段 |
|------|------|------|
| Halmos / Control | 符号执行验证 invariant | CI 集成 |
| Certora Prover | 形式化规则核验 | 审计前 |
| Echidna | 模糊测试 invariant | 开发循环 |
| Medusa | 并行模糊测试 | 压测阶段 |

---

## 八、混沌工程测试

### 8.1 故障注入场景

| 场景 | 注入方式 | 预期行为 | 恢复验证 |
|------|---------|---------|---------|
| RPC 节点下线 | 防火墙阻断 RPC 端点 30s | 自动切换至备用 RPC，队列缓存未确认交易 | 恢复后批量重放，无数据丢失 |
| RPC 返回错误率高 | 代理层注入 50% 错误率，持续 60s | 错误率 > 10% 时自动切换至备用端点 | 切换后错误率恢复 < 1% |
| Monad 测试网 reorg | 在 fork 模式下模拟 5 个区块重组 (anvil `--auto-impersonate` + `evm_reorg`) | Event Listener 检测到 reorg，回退 block height，重新处理事件 | executionId 去重保证幂等 |
| Redis 进程崩溃 | `docker kill redis` 后等待 30s 重启 | 队列数据从 AOF 恢复，未持久化项从链上事件回放 | Agent 任务无丢失 |
| PostgreSQL 主库故障 | 模拟 Primary 宕机，手动/自动切换至 Standby | 写入暂停 < 30s，读取自动切换 | PITR 恢复至故障前最后已提交状态 |
| 单 Agent 私钥泄露模拟 | 调用 `deactivateAgent(id)` 后尝试用旧私钥签名提交 | 链上 `revert AgentInactive`，链下 DLQ 收到事件 | 受影响 Agent 停止执行，其余正常 |
| Monad 网络 Gas 飙升 | 压测环境注入高 Gas 竞争（提交 200 笔竞争交易） | 交易排队等待，优先级低的交易超时落入 DLQ | 重放后全部恢复 |

### 8.2 运行混沌测试

```bash
# 使用 local Monad fork 环境
anvil --fork-url $MONAD_RPC_URL --fork-block-number <BLOCK>

# 启动所有服务
docker compose -f docker-compose.chaos.yml up -d

# 运行故障注入
pytest tests/chaos/ -v --chaos-config chaos.yaml

# 预期: 所有场景 100% 通过，RTO < 标称值
```

### 8.3 混沌测试报告模板

```markdown
## 混沌测试报告 vX.X.X

| 场景 | 注入时间 | 检测时间 | 恢复时间 | RTO | 通过 |
|------|---------|---------|---------|-----|------|
| RPC 下线 | 2024-xx-xx 14:00 | +2s | +15s | 30s | ✅ |
| RPC 高错误率 | 2024-xx-xx 14:05 | +5s | +10s | 60s | ✅ |
| Reorg | 2024-xx-xx 14:10 | +3s | +8s | 30s | ✅ |
| Redis 崩溃 | 2024-xx-xx 14:15 | +1s | +20s | 5min | ✅ |
| PG 主库故障 | 2024-xx-xx 14:20 | +1s | +25s | 30min | ✅ |

### 结论
- ✅ 所有 RTO 达标
- ⚠️ PG 切换需手动触发，建议后续自动化
```
