# 生产级审查修改方案

> 基于 2026-05-12 架构审查报告，本文档定义各问题的具体修改方案与验收标准。

---

## 一、Critical 修改

### 1.1 统一代理升级策略

**现状矛盾**：

- `contracts.md`：不使用 `delegatecall`，无代理模式
- `deployment.md`：MonadAgentHub 标注 `(Proxy)`
- `architecture.md`：未提及升级机制

**决策**：采用 **Immutable + 注册新合约 + Agent 迁移** 模式，理由：
- 与独立存储槽的并行化哲学一致
- 消除 `delegatecall` 引入的存储冲突风险
- 安全审计成本更低
- Monad 并行 EVM 场景下代理模式的优势有限

**修改清单**：

| 文件 | 修改项 |
|------|--------|
| `architecture.md` | 新增"升级策略"章节，描述 Immutable + 迁移模式 |
| `contracts.md` | 移除 Proxy 相关描述，补充版本号字段到合约接口 |
| `deployment.md` | 移除 `(Proxy)` 标注，改为"版本迁移步骤"章节 |

**新增 `architecture.md` 章节内容**：

```markdown
## 八、升级策略

### 8.1 不可变核心 + 版本迁移

核心合约（MonadAgentHub）采用不可变部署，不引入代理模式。
升级通过部署新版本合约 + Agent 主动迁移实现：

1. 部署新版本 MonadAgentHub V2
2. 旧版合约进入 `deprecated` 状态（保留只读查询，禁止新任务）
3. Agent Owner 调用 `migrateAgent(oldAgentId)` → 新合约分配新 ID
4. 链下监听 `AgentMigrated` 事件，更新 Agent ID 映射

### 8.2 合约版本号

所有合约包含 `string public constant VERSION = "1.0.0"`，供链下索引。
事件中携带版本号以支持索引器兼容。
```

---

### 1.2 DeFi Adapter 重入防护补强

**现状问题**：独立存储槽设计仅防止 Agent 间直接写冲突，无法防止通过外部协议的回退攻击。

**修改方案**：

1. **`contracts.md` 新增安全分级表**：

```markdown
### 八、工作流安全分级

| 级别 | 条件 | 防护要求 | 示例工作流 |
|------|------|---------|-----------|
| L0 | 纯计算，无外部调用 | 独立存储槽 | SOCIAL_NOTIFY, CUSTOM |
| L1 | 外部只读调用 | 独立存储槽 + 调用结果校验 | GAME_NPC |
| L2 | 外部写调用（单一协议） | 独立存储槽 + ReentrancyGuard + CEI | DEFI_SWAP, DEFI_LEND |
| L3 | 外部写调用（多协议组合） | L2 全部 + 完整性检查 + 滑点保护 | 批量套利工作流 |

### 八之一、L2+ 工作流的 ReentrancyGuard 使用

仅包裹外部调用片段，不锁整个 execute 函数，以最小化对并行执行的影响：

\`\`\`solidity
function execute(uint256 agentId, bytes calldata taskData) external override returns (bool) {
    // 1. 校验 & 更新内部状态（独立存储槽，无冲突）
    _validateAndUpdateState(agentId, taskData);
    // 2. 外部调用（加锁）
    _executeExternal(agentId, taskData);
    return true;
}

function _executeExternal(uint256 agentId, bytes calldata taskData) internal nonReentrant {
    // 此处包含对 DEX/Lending 的外部调用
}
\`\`\`
```

2. **安全性分析补充**：每个 Workflow Executor 必须附带重入分析文档，明确：
   - 调用了哪些外部合约
   - 是否存在回调路径到本合约
   - 防护措施及验证方式

---

### 1.3 压测脚本修复

**修改 `testing.md` 4.1 节**：

1. 修复 `createBatchAccount` 类型错误：

```typescript
import { pad, toHex } from 'viem'

function createBatchAccount(index: number) {
  return privateKeyToAccount(pad(toHex(index + 1), { size: 32 }))
}
```

2. 增加连接池控制，避免压垮 RPC：

```typescript
import pLimit from 'p-limit'

async function runBenchmark(
  concurrency: number = 100,
  maxConcurrent: number = 50  // RPC 连接上限
): Promise<BenchmarkResult> {
  const limit = pLimit(maxConcurrent)
  const promises = clients.map((client, i) =>
    limit(() => executeOne(client, i))
  )
  const results = await Promise.all(promises)
  // ...
}
```

3. 增加预热阶段，排除冷启动影响：

```typescript
// 预热交易（不计入结果）
await runBenchmark(5)
await sleep(2000)
// 正式测试
const result = await runBenchmark(concurrency)
```

---

## 二、High 修改

### 2.1 taskData 结构化

**修改 `contracts.md` 2.3 节**：

在所有 `executeAgentTask` 相关描述中，将 `bytes calldata taskData` 替换为：

```solidity
struct TaskData {
    uint8 version;       // 数据格式版本，初始为 1
    uint256 deadline;    // 任务有效期（unix timestamp），0 表示永不过期
    bytes payload;       // 工作流特定数据
}

function executeAgentTask(
    uint256 agentId,
    TaskData calldata taskData
) external returns (bool success)
```

**基础校验逻辑**：

```solidity
// 版本检查
require(taskData.version == CURRENT_VERSION, "Unsupported task version");
// 有效期检查
require(taskData.deadline == 0 || block.timestamp <= taskData.deadline, "Task expired");
```

**修改 `contracts.md` 六、Gas 优化策略**，新增：

| 策略 | 实现 |
|------|------|
| 结构化 taskData 用 calldata 传递 | 避免 ABI decode 重复开销，struct 展开由编译器优化 |

---

### 2.2 CI/CD 流水线

**新增到 `development.md` 第七章后**：

```markdown
## 八、CI/CD 流水线

### 8.1 GitHub Actions

\`\`\`yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  solidity:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1

      - name: Run tests
        run: forge test -vvv

      - name: Check coverage
        run: forge coverage --report lcov

      - name: Static analysis
        run: |
          pip install slither-analyzer
          slither . --fail-high --fail-medium

      - name: Check contract sizes
        run: forge build --sizes
        # 断言所有合约 < 24576 bytes

      - name: Gas diff
        run: |
          git fetch origin main
          forge snapshot --diff .gas-snapshot

  typescript:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v2
      - run: pnpm install --frozen-lockfile
      - run: pnpm lint
      - run: pnpm typecheck
```

### 8.2 质量门禁

| 检查项 | 阻断条件 |
|--------|---------|
| 单元测试 | 任何失败 |
| 覆盖率 | < 90% 行覆盖 |
| Slither | High/Medium 告警 |
| 合约大小 | 超过 24KB |
| Gas 回归 | 单函数增加 > 10% 需评审说明 |
| ESLint | 任何 error |
| TypeScript | 类型错误 |
```

---

### 2.3 形式化验证

**新增到 `testing.md` 第六章后**：

```markdown
## 七、形式化验证

### 7.1 核心 Invariant

\`\`\`
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
\`\`\`

### 7.2 工具选型

| 工具 | 用途 | 阶段 |
|------|------|------|
| Halos / Control | 符号执行验证 invariant | CI 集成 |
| Certora Prover | 形式化规则核验 | 审计前 |
| Echidna | 模糊测试 invariant | 开发循环 |
| Medusa | 并行模糊测试 | 压测阶段 |
```

---

### 2.4 链下组件详细设计

**新增到 `architecture.md` 第二章后**：

```markdown
### 2.3 链下组件详细设计

#### Event Listener（事件监听器）

| 属性 | 设计 |
|------|------|
| 投递保证 | At-least-once，通过 executionId 去重实现幂等 |
| Reorg 处理 | 等待 N 个区块确认（可配置，> 测试网 1，主网 3-5） |
| 失败重试 | 指数退避，最大重试 3 次，超限进入 DLQ（死信队列） |
| 事件过滤 | 按 agentId + workflowType 双索引高效过滤 |
| 实现 | TypeScript + viem watchContractEvent，状态持久化至 PostgreSQL |

#### AI Agent Engine（AI 决策引擎）

| 属性 | 设计 |
|------|------|
| 输入 | 链上事件 + 链下数据（价格/预言机） |
| 输出 | 签名后的 TaskData，提交至 Strategy Engine |
| 验证方式 | Phase 1: 中心化签名验证（Agent 私钥）；Phase 3: TEE 证明 / zkML |
| 延迟预算 | 链上事件触发 → AI 决策 → 提交上链 < 500ms |
| 安全性 | AI 输出仅生成建议，最终执行由链上策略校验 |

#### Strategy Engine（策略引擎）

| 属性 | 设计 |
|------|------|
| 职责 | 接收 Agent 决策，编排工作流执行 |
| 去重 | 基于 agentId + nonce 的幂等提交 |
| 批量优化 | 多个独立 Agent 任务打包为 batchExecuteTasks |
| 失败处理 | 单 Agent 失败不影响批次其余 Agent |

#### Task Queue（任务队列）

\`\`\`
AI Agent → Strategy Engine → Task Queue (Redis Streams / BullMQ)
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              Worker 1        Worker 2        Worker N
              (批量提交至 Monad RPC)
\`\`\`

#### 状态持久化

| 数据 | 存储 | 说明 |
|------|------|------|
| Agent 元数据 | PostgreSQL | agentId, owner, workflowType, status |
| 执行历史 | PostgreSQL + TimescaleDB | 时序查询优化 |
| 任务队列 | Redis | 内存优先，TTL 自动清理 |
| 事件日志 | Clickhouse / The Graph | 大规模事件索引 |
```

---

## 三、Medium 修改

### 3.1 Custom Error 替换 String Revert

**修改 `contracts.md`**：在 2.3 节核心函数描述前新增错误定义：

```solidity
// 自定义错误（替代 require string）
error NotAgentOwner(uint256 agentId, address caller, address owner);
error AgentInactive(uint256 agentId);
error AgentNotFound(uint256 agentId);
error UnsupportedTaskVersion(uint8 version);
error TaskExpired(uint256 deadline, uint256 currentTime);
error BatchLengthMismatch(uint256 agents, uint256 tasks);
```

同步更新 `development.md` 代码模板，将所有 `require(msg.sender == owner, "Not agent owner")` 改为 `if (owner != msg.sender) revert NotAgentOwner(agentId, msg.sender, owner)`。

### 3.2 存储 Gap 预留

**新增到 `contracts.md` 二、MonadAgentHub 2.2 状态变量后**：

```solidity
// 存储 gap 预留（为将来扩展保留空间）
// 当前合约版本末尾存储槽编号: N
// 预留槽位: N+1 ~ N+50
uint256[50] private __storageGap;
```

### 3.3 双步 Ownership Transfer

**修改 `contracts.md` MonadAgentHub 函数列表**，新增：

```solidity
function transferOwnership(address newOwner) external onlyOwner
function acceptOwnership() external
```

使用 OpenZeppelin `Ownable2Step` 替代 `Ownable`。

### 3.4 MEV/排序分析

**新增到 `architecture.md` 第五章后**：

```markdown
### 5.3 MEV 与交易排序

#### 影响场景

| 场景 | 风险 | 缓解 |
|------|------|------|
| 同池子竞争 swap | Frontrunning/Backrunning | 使用 deadline + minAmountOut |
| Agent 间依赖性 | 排序不确定 → 结果不一致 | 串行依赖的 Agent 应在同一交易内执行 |
| 跨区块原子性 | 无 | 跨 Agent 操作不应有原子性假设 |

#### 并行 EVM 排序特性

Monad 对无存储冲突的交易不保证顺序，系统设计须遵循：
- Agent 操作间不应有隐含的执行顺序依赖
- 如需顺序保证，应在单个 batchExecuteTasks 调用内组织
```

### 3.5 幂等性设计

**修改 `contracts.md` 2.2 节**，Agent 结构体增加：

```solidity
struct Agent {
    // ... 现有字段
    uint256 nonce;          // 执行 nonce，单调递增，防重放
}
```

`executeAgentTask` 接受额外参数：

```solidity
function executeAgentTask(
    uint256 agentId,
    uint256 nonce,      // 必须 == agent.nonce + 1
    TaskData calldata taskData
) external returns (bool success)
```

**修改 `testing.md` 2.2 节**，新增测试用例：

```solidity
function testNonceReplayProtection() public {
    vm.startPrank(owner);
    uint256 id = hub.registerAgent(bytes32("TEST"));
    hub.executeAgentTask(id, 1, taskData);
    vm.expectRevert(abi.encodeWithSelector(InvalidNonce.selector, id, 1, 2));
    hub.executeAgentTask(id, 1, taskData); // 重复 nonce 应失败
    vm.stopPrank();
}
```

### 3.6 性能基准可复现

**修改 `testing.md` 5.1 节**，明确：

```markdown
### 5.1 测试环境

| 参数 | 值 |
|------|-----|
| Monad 版本 | 测试网 v0.x |
| RPC 提供方 | Monad 官方公共 RPC |
| 压测客户端 | AWS t3.xlarge (4 vCPU, 16GB RAM) |
| 网络延迟 (P50) | <50ms |
| 并发连接数控制 | 单 IP 最大 200 并发 |
| 预热交易数 | 10 |

### 5.2 对比基线

传统 EVM 对比使用完全相同的合约逻辑，部署在 Goerli 测试网上测试，
使用 `geth v1.13.x` 节点，`--syncmode full`。
```

---

## 四、Low 修改

### 4.1 SLO/SLI 定义

**新增到 `architecture.md` 第一章后**：

```markdown
### 1.1 服务等级目标（SLO）

| 指标 | SLI | SLO |
|------|-----|-----|
| 可用性 | 成功提交 / 总提交 | 99.9% |
| 任务延迟 P50 | 提交 → 链上确认 | < 500ms |
| 任务延迟 P95 | 提交 → 链上确认 | < 2s |
| 任务延迟 P99 | 提交 → 链上确认 | < 5s |
| 错误预算 | 1 - 可用性 | 月 0.1%（~43 分钟/月） |
| 数据一致性 | 链上写入成功数 / 事件接收数 | 100% |
```

### 4.2 运维联系人

修改 `deployment.md` 第八章，将 TBD 替换为占位符并标注填入要求：

```markdown
| 角色 | 联系方式 | 职责 |
|------|---------|------|
| 主网部署负责人 | {{PRIMARY_DEPLOYER}} | 执行部署流程 |
| 安全审计对接人 | {{AUDIT_LEAD}} | 审计报告跟进 |
| 7x24 值班 | {{ONCALL_CHANNEL}} | 监控紧急响应 |
| 开发团队 | {{DEV_TEAM_ALIAS}} | 问题修复 |

> 部署前必须全部替换为真实信息。
```

### 4.3 合约版本号 & 地址发现

**修改 `contracts.md`**，每个合约接口新增：

```solidity
string public constant VERSION = "1.0.0";
```

**新增到 `deployment.md`**：

```markdown
## 九、合约注册中心

所有已部署合约地址注册到 ENS 子域名，供下游服务自动发现：

| 合约 | ENS 域名 |
|------|---------|
| MonadAgentHub | `hub.monadflow.eth` |
| AgentRegistry | `registry.monadflow.eth` |

合约升级时更新 ENS 记录指向新地址，旧合约保留只读访问。
```

### 4.4 Event 版本化

**修改 `contracts.md` 5.2 节**，所有事件增加 `version` 字段：

```solidity
event AgentExecuted(
    uint256 indexed agentId,
    uint8 indexed version,    // 合约版本号主版本
    bytes taskData,
    uint256 timestamp,
    bool success
);
```

---

## 五、修改优先级与排期

```
Week 1-2  ████████████████  P0: 统一升级策略 + 重入分析 (阻塞全部后续)
Week 3    ████████          P1: taskData 结构化 + CI/CD 搭建
Week 4    ████████          P1: 形式化验证框架 + 压测脚本修复
Week 5    ████████          P2: 链下设计补全 + 幂等性
Week 6    ████████          P2: 双步 ownership + custom error
Week 7    ██                P3: Low 优先级项收尾
Week 8    ██                Review: 安全审计前全部文档冻结
```

---

## 六、验收清单

- [ ] `architecture.md` / `contracts.md` / `deployment.md` 升级策略一致
- [ ] 每个 L2+ 工作流附带重入分析文档
- [ ] `TaskData` 结构体定义出来，含 version + deadline
- [ ] CI 流水线运行通过（test + coverage + slither + gas diff）
- [ ] 关键 invariant 以代码形式定义并可验证
- [ ] 压测脚本跑出可复现的 TPS 数据
- [ ] 链下 Event Listener 含 reorg 处理代码
- [ ] 所有 `require("string")` 替换为 custom error
- [ ] `Ownable2Step` 替换 `Ownable`
- [ ] `nonce` 字段加入 Agent 结构体
- [ ] 所有事件含 `version` 字段
- [ ] 运维联系人已填写真实信息
