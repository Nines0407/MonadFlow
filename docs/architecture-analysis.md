# MonadFlow 架构解析

> 本文档面向新加入团队的开发者与架构评审者，旨在用一篇文章讲清楚 MonadFlow 的全部架构决策与系统全貌。阅读时间约 25 分钟。

---

## 目录

1. [一句话定位](#1-一句话定位)
2. [为什么需要 MonadFlow](#2-为什么需要-monadflow)
3. [核心洞察：并行执行的"银弹"](#3-核心洞察并行执行的银弹)
4. [系统全景图](#4-系统全景图)
5. [链上层：智能合约体系](#5-链上层智能合约体系)
6. [链下层：事件驱动的 Agent 引擎](#6-链下层事件驱动的-agent-引擎)
7. [数据层：持久化与一致性](#7-数据层持久化与一致性)
8. [安全纵深防御](#8-安全纵深防御)
9. [运维与可观测性](#9-运维与可观测性)
10. [部署与升级](#10-部署与升级)
11. [前端集成点](#11-前端集成点)
12. [风险与假设](#12-风险与假设)

---

## 1. 一句话定位

**MonadFlow 是运行在 Monad 并行 EVM 上的链上 Agent 工作流系统**——把 AI Agent 的"决策→执行→状态同步→跨 Agent 协作"全流程搬到链上，利用独立存储槽设计实现 Agent 级真正并行执行。

---

## 2. 为什么需要 MonadFlow

### 2.1 传统 EVM 的根本瓶颈

在以太坊/BSC 这类串行 EVM 链上，所有交易按顺序执行。当数十个 Agent 并发提交任务时：

```
Agent 1 提交 ─┐
Agent 2 提交 ─┤
Agent 3 提交 ─┼──→ 串行执行队列 ──→ TPS 天花板：15-25
  ...         │                      P99 延迟：数秒到数分钟
Agent N 提交 ─┘
```

结果是：**EVM 串行模型从根上就不适合工业化 Agent 集群**——这是物理瓶颈，不是工程优化能解决的。

### 2.2 Monad 的并行 EVM 提供了什么

Monad 是一个兼容 EVM 的 L1 链，核心特性是**乐观并行执行**：交易默认并行跑，仅在检测到存储冲突时才串行化冲突交易。

```
交易 A → storage slot 0xAA  ← 无冲突，并行
交易 B → storage slot 0xBB  ← 无冲突，并行
交易 C → storage slot 0xBB  ← 冲突！与 B 串行化
```

这个特性意味着：**如果你能把不同 Agent 的数据隔离到不同 storage slot，Monad 就能让它们完全并行执行**。

### 2.3 MonadFlow 的价值主张

```
传统 EVM                MonadFlow
────────────────────────────────────────────────
串行执行           →    并行执行（无冲突交易）
15-25 TPS           →    1,000+ TPS
跨合约调用阻塞      →    亚秒级确认
不适合 Agent 集群    →    Agent 工业化部署成为可能
```

---

## 3. 核心洞察：并行执行的"银弹"

这是整个架构中**最重要的一页**。

### 3.1 传统设计的死胡同

```solidity
// ❌ 传统设计：所有 Agent 共享一个 map，所有全局计数器
mapping(uint256 => GlobalState) states;   // 所有 Agent 往同一个 slot 写
uint256 globalCounter;                    // 每次操作都 +1 → 全局写冲突
```

在这个设计中，无论多少 Agent 并发执行，它们都在竞争同一个 `globalCounter` 和 `states` 的存储槽。Monad 即使再快，也会被强制串行化。

### 3.2 MonadFlow 的解法

```solidity
// ✅ MonadFlow 设计：每个 agentId 占据独立 storage slot
mapping(uint256 => Agent) agents;

// Agent A (id=1) → storage slot keccak(1, agentIdSlot)
// Agent B (id=2) → storage slot keccak(2, agentIdSlot)
//   ↑ 这是两个完全不同的 32 字节槽位，Monad 判定为 0 冲突
```

关键设计决策一览：

| 决策 | 理由 |
|------|------|
| 不使用全局计数器 | `totalAgents`、`totalExecutions` 等统计值由链下从 Events 聚合，避免引入全局写冲突 |
| 不使用代理模式 | `delegatecall` 的存储布局依赖与并行化哲学冲突，升级采用 Immutable + 迁移模式 |
| Agent 间无隐含依赖 | Agent A 不能修改 Agent B 的状态，消除跨 Agent 的存储冲突 |
| 批量交易使用不同 agentId | `batchExecuteTasks` 内每个 agent 操作独立 slot，即使同一交易内也并行 |

### 3.3 核心 Invariant

```
Invariant 1（Agent 隔离）:
  Agent A 的操作永远不会改变 Agent B 的内部状态

Invariant 2（权限一致性）:
  仅 agent.owner 可执行该 agent 的任务

Invariant 3（Nonce 单调）:
  每个 agent 的 nonce 只增不减，防重放

Invariant 4（ID 一致性）:
  注册 Agent 数 = 注册事件数 - 注销事件数（链下统计）
```

---

## 4. 系统全景图

```
┌──────────────────────────────────────────────────────────────┐
│                       链下层 (Off-Chain)                      │
│                                                               │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ AI Agent    │  │ Event        │  │ Strategy Engine    │  │
│  │ Engine      │  │ Listener     │  │ (任务编排 & 去重)   │  │
│  │ (决策生成)   │  │ (事件监听)    │  │                    │  │
│  └──────┬──────┘  └──────┬───────┘  └─────────┬──────────┘  │
│         │                │                     │              │
│         └────────┬───────┴─────────────────────┘              │
│                  │                                            │
│         ┌────────▼────────┐     ┌──────────────────┐         │
│         │  Task Queue     │     │  Monitor         │         │
│         │  (Redis Streams)│     │  Dashboard       │         │
│         └────────┬────────┘     │  (Grafana)       │         │
│                  │              └──────────────────┘         │
│         ┌────────▼────────┐                                  │
│         │  Worker Pool    │                                  │
│         │  (RPC 批量提交)  │                                  │
│         └────────┬────────┘                                  │
│                  │ RPC / WebSocket                            │
├──────────────────┼───────────────────────────────────────────┤
│                  │             链上层 (Monad Parallel EVM)     │
│  ┌───────────────▼─────────────────────────────────────────┐ │
│  │                  MonadAgentHub (调度中心)                 │ │
│  │  ┌──────────────────┐  ┌─────────────────────────────┐ │ │
│  │  │ AgentRegistry    │  │ Workflow Executors          │ │ │
│  │  │ (注册&生命周期)   │  │ ├── DeFiSwapExecutor        │ │ │
│  │  └──────────────────┘  │ ├── DeFiLendExecutor        │ │ │
│  │                         │ ├── NFTExecutor             │ │ │
│  │  ┌──────────────────┐  │ └── CrossChainExecutor      │ │ │
│  │  │ TimelockController│  └─────────────────────────────┘ │ │
│  │  │ (治理延迟 ≥ 24h)  │                                   │ │
│  │  └──────────────────┘                                    │ │
│  └──────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘

数据存储层
┌─────────────────────────────────────────────────────────────┐
│  PostgreSQL + TimescaleDB      Redis               ClickHouse│
│  (Agent 元数据 & 执行历史)      (任务队列 & 缓存)    (事件分析) │
└─────────────────────────────────────────────────────────────┘
```

### 4.1 数据流：一次完整的 Agent 任务执行

```
 1. 链上事件发生（DeFi 价格波动 / NFT 铸造 / 定时触发）
         │
 2. Event Listener 捕获事件，写入 PostgreSQL
         │
 3. AI Agent Engine 读取事件 + 链下数据 → 生成 TaskData
         │
 4. Strategy Engine 验证去重 → 写入 Task Queue (Redis)
         │
 5. Worker 从队列取任务 → 批量提交 RPC → MonadAgentHub.executeAgentTask()
         │
 6. Monad 并行 EVM 执行（独立 storage slot → 0 冲突）
         │
 7. 链上 emit AgentExecuted 事件
         │
 8. Event Listener 捕获 → 触发弱最终性回调（信息通知类）
         或等待 N 块 → 触发强最终性回调（资金决策类）
         │
 9. 闭环：AI Agent 读取执行结果，进入下一轮决策
```

---

## 5. 链上层：智能合约体系

### 5.1 合约总览

| 合约 | 职责 | 行数 |
|------|------|------|
| `MonadAgentHub` | Agent 调度中心：注册、执行、停用、迁移 | ~200 |
| `AgentRegistry` | Agent 生命周期管理 | ~100 |
| `WorkflowExecutor` | 抽象基类，定义工作流执行接口 | ~60 |
| `DeFiSwapExecutor` | DEX 兑换工作流 | ~80 |
| `DeFiLendExecutor` | 借贷工作流 | ~80 |
| `NFTExecutor` | NFT 铸造/交易工作流 | ~80 |
| `CrossChainExecutor` | 跨链桥接工作流 | ~80 |
| `TimelockController` | 治理延迟控制器（OpenZeppelin） | 复用 |

### 5.2 核心接口：MonadAgentHub

```
registerAgent(workflowType) → agentId
executeAgentTask(agentId, nonce, taskData) → success
batchExecuteTasks(agentIds[], nonces[], taskData[]) → successes[]
deactivateAgent(agentId)
deprecate()                              # 标记合约弃用
migrateAgent(oldAgentId) → newAgentId    # 跨版本迁移
pause() / unpause()                      # 紧急暂停（需 Timelock，延迟 ≥ 24h）
```

### 5.3 TaskData 结构

```solidity
struct TaskData {
    uint8  version;    // 数据格式版本（初始为 1），支持向前兼容
    uint256 deadline;  // 有效期（unix timestamp），0 = 永不过期
    bytes  payload;    // 工作流特定数据（ABI encoded）
}

// 校验逻辑
require(version == CURRENT_VERSION, "UnsupportedTaskVersion");
require(deadline == 0 || block.timestamp <= deadline, "TaskExpired");
```

### 5.4 自定义错误（替代 require string，节省 Gas）

```solidity
error NotAgentOwner(uint256 agentId, address caller, address owner);
error AgentInactive(uint256 agentId);
error AgentNotFound(uint256 agentId);
error UnsupportedTaskVersion(uint8 version);
error TaskExpired(uint256 deadline, uint256 currentTime);
error BatchLengthMismatch(uint256 agents, uint256 tasks);
error InvalidNonce(uint256 agentId, uint256 expected, uint256 actual);
```

### 5.5 事件体系

| 事件 | 触发时机 | 关键字段 |
|------|---------|---------|
| `AgentRegistered` | 新 Agent 注册 | agentId, owner, workflowType, version |
| `AgentExecuted` | 任务执行完成 | agentId, executionId, nonce, success |
| `AgentDeactivated` | Agent 停用 | agentId |
| `AgentMigrated` | Agent 跨版本迁移 | oldAgentId, newAgentId, owner |
| `WorkflowCompleted` | 工作流执行完成 | agentId, workflowType, gasUsed |
| `ContractDeprecated` | 合约标记弃用 | version |
| `Paused` / `Unpaused` | 合约暂停/恢复 | initiator |

所有关键事件包含 `version` 字段（`uint8`），支持索引器按版本过滤。

### 5.6 工作流安全分级

不是所有 Agent 都需要 ReentrancyGuard。MonadFlow 按外部调用风险分级：

| 级别 | 条件 | 防护 | 示例 |
|------|------|------|------|
| L0 | 纯计算，无外部调用 | 独立存储槽 | SOCIAL_NOTIFY, CUSTOM |
| L1 | 外部只读调用 | L0 + 调用结果校验 | GAME_NPC |
| L2 | 外部写调用（单一协议）| L1 + ReentrancyGuard + CEI | DEFI_SWAP, DEFI_LEND |
| L3 | 外部写调用（多协议组合）| L2 + 完整性检查 + 滑点保护 | 批量套利 |

L2+ 的 ReentrancyGuard 仅包裹外部调用片段，不锁整个 execute 函数，以最小化对并行执行的影响。

---

## 6. 链下层：事件驱动的 Agent 引擎

### 6.1 Event Listener（事件监听器）

```
┌─────────────────────────────────────────────────────┐
│                  Event Listener                       │
│                                                       │
│  Monad RPC ──→ parseLogs ──→ 去重检查 ──→ 分类器     │
│                                     │        │        │
│                              executeId 已存在?  大额资金?│
│                              ├─ YES: skip     ├─ YES: 等 3 块│
│                              └─ NO: 继续      └─ NO: 立即触发│
│                                         │                   │
│                              ┌──────────┴──────────┐        │
│                              ▼                      ▼        │
│                        弱最终性回调            强最终性回调    │
│                     (tx inclusion 即刻)    (N 块确认后)      │
└─────────────────────────────────────────────────────┘
```

| 属性 | 配置 |
|------|------|
| 投递保证 | At-least-once，用 `executionId = keccak256(agentId, nonce, blockNumber)` 去重 |
| Reorg 处理 | 测试网等 1 块，主网等 3 块（可配置 `REORG_CONFIRMATION_BLOCKS`） |
| 失败重试 | 指数退避 1s→2s→4s，最多 3 次 |
| Dead Letter Queue | 超限进入按 agentId+workflowType 分区的 DLQ，独立消费者处理 |

### 6.2 AI Agent Engine

输入链上事件 + 链下数据（预言机价格）→ 输出签名的 TaskData。

Phase 1 使用 Agent 私钥签名验证，Phase 3 引入 TEE 证明或 zkML。

**安全边界**：AI 输出仅生成建议，链上合约做最终策略校验——AI 建议买入但链上发现已超滑点保护上限，则 revert。

### 6.3 Strategy Engine（策略引擎）

```
                    ┌────────────────┐
多个 Agent 决策 ──→ │  Strategy Engine │
                    │                │
                    │  1. 去重 (nonce)│
                    │  2. 批量优化    │
                    │  3. 失败隔离    │
                    └───────┬────────┘
                            │
                    ┌───────▼────────┐
                    │  Redis Streams  │
                    └───────┬────────┘
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
          Worker 1      Worker 2      Worker N
          (提交 RPC)    (提交 RPC)    (提交 RPC)
```

### 6.4 优雅降级与熔断器

```
Level 0: 全功能 ───────── 所有组件健康
Level 1: RPC 降级 ─────── RPC 错误率 > 10% → 自动切换备用端点
Level 2: 协议熔断 ─────── 外部协议连续 5 次失败 → Adapter 进入熔断
Level 3: 只读模式 ─────── 合约 paused → 仅查询，暂停写操作
Level 4: 紧急停止 ─────── 合约漏洞/私钥泄露 → 全停

熔断器状态机:
CLOSED ──(5 次失败)──→ OPEN ──(60s)──→ HALF_OPEN ──(1 次成功)──→ 保持半开
                         ↑                              │
                         └──(1 次失败即回 OPEN)←────────┘
                                           └──(3 次成功)──→ CLOSED
```

---

## 7. 数据层：持久化与一致性

### 7.1 存储分工

| 数据 | 存储引擎 | 用途 |
|------|---------|------|
| Agent 元数据 | PostgreSQL | agentId, owner, workflowType, status |
| 执行历史 | PostgreSQL + TimescaleDB hypertable | 时序查询、90 天保留、7 天后自动压缩 |
| 任务队列 | Redis Streams | 内存优先、TTL 自动清理、AOF 持久化 |
| 事件日志 | ClickHouse | 大规模聚合分析（内部运维）；未来可选 The Graph 对外提供 GraphQL |
| 审计日志 | PostgreSQL `audit_logs` 表 | 不可变 INSERT，365 天保留 |
| 合约状态 | Monad 链上 | 天然去中心化备份 |

### 7.2 备份与恢复

| 数据层 | RPO | RTO |
|--------|-----|-----|
| PostgreSQL | < 1 分钟（WAL 持续归档） | < 30 分钟 |
| Redis | < 1 秒（AOF everysec） | < 5 分钟 |
| 合约状态 | 0（链上共识保证） | 依赖 Event Listener 追块速度 |

恢复流程：检测故障 → 评估影响 → DB 恢复（pg + redis）→ 按序重启服务 → backlog 处理 → 验证通过。

---

## 8. 安全纵深防御

### 8.1 威胁模型

| 威胁 | 缓解 | 层级 |
|------|------|------|
| 恶意 Agent 写入其他 Agent 状态 | 独立存储槽 + 仅 owner 可写 | 合约层 |
| 重入攻击 | L2+ 工作流使用 ReentrancyGuard（仅包裹外部调用） | 合约层 |
| 签名伪造 | agentId 绑定 owner + nonce 防重放 | 合约层 |
| DDoS / 批量垃圾交易 | Gas 经济天然限流 + Strategy Engine 速率限制 | 合约层 + 链下层 |
| 管理员私钥泄露 | Owner 是 TimelockController（合约地址），非 EOA | 治理层 |
| 紧急暂停被滥用 | Timelock 延迟 ≥ 24h，给社区反应窗口 | 治理层 |
| Frontrunning / MEV | deadline + minAmountOut + 批内顺序控制 | 应用层 |

### 8.2 密钥管理两分法

| 类别 | 存储 | 轮换周期 |
|------|------|---------|
| Agent 私钥 | AWS KMS / HashiCorp Vault（不可导出，仅签名接口） | 每 90 天 |
| Admin 密钥 | Ledger/Trezor 硬件钱包（必须） | 每 180 天 |

Phase 1（测试网）允许加密环境变量，Phase 2（主网）强制 KMS/HSM。

### 8.3 权限层级

```
Owner（TimelockController 合约）
  │
  ├── 可 pause/unpause（需 24h 延迟提案）
  ├── 可 deprecate 合约（需 24h 延迟提案）
  │
  └── Agent Owner（EOA 或 KMS 签名者）
        │
        ├── 可 executeAgentTask（仅自身 Agent）
        ├── 可 deactivateAgent（仅自身 Agent）
        └── 可 migrateAgent（仅自身 Agent）
```

---

## 9. 运维与可观测性

### 9.1 三大支柱

```
┌──────────────────────────────────────────────────┐
│  分布式追踪 (OpenTelemetry)                       │
│  Event Listener ─traceId─→ Strategy Engine        │
│       ─traceId─→ RPC Submit ─span─→ Monad Chain   │
│  每个 span 携带: agentId, workflowType, nonce      │
├──────────────────────────────────────────────────┤
│  结构化日志 (JSON)                                │
│  {"timestamp","traceId","agentId","event",        │
│   "latency_ms","txHash"}                          │
├──────────────────────────────────────────────────┤
│  指标 (Prometheus + Grafana)                      │
│  /healthz (K8s liveness)                          │
│  /readyz  (K8s readiness: rpc + db + redis)        │
│  /metrics (OpenMetrics: TPS, 延迟分布, 队列深度)   │
└──────────────────────────────────────────────────┘
```

### 9.2 Grafana 仪表盘

| 面板 | 核心指标 |
|------|---------|
| 系统概览 | TPS、成功率、P50/P95/P99 延迟、活跃 Agent 数 |
| 队列深度 | Redis 积压量、DLQ 堆积、消费速率 |
| RPC 健康 | 各端点延迟/错误率、当前活跃端点 |
| 熔断器 | 各 Adapter 状态（绿/黄/红） |
| Gas 消耗 | 合约 MON 余额、Gas 消耗速率 |
| 并行率 | 独立 Agent 并发 TPS ÷ 单 Agent 串行 TPS |

### 9.3 告警规则

| 指标 | 阈值 | 严重程度 |
|------|------|---------|
| TPS < 500 | 持续 5 分钟 | Warning |
| 失败率 > 5% | 任何窗口 | Critical |
| DLQ 堆积 > 100 | 任何时刻 | Critical |
| 合约 MON 余额 < 5 | 任何时刻 | Warning |
| 并行率 < 90% | 持续 10 分钟 | Warning |

---

## 10. 部署与升级

### 10.1 部署架构

```
Monad 主网
├── MonadAgentHub (不可变) ←── Owner = TimelockController (24h 延迟)
├── AgentRegistry            ←── 关联 MonadAgentHub
├── TimelockController       ←── admin → 3/5 多签 (Safe{Wallet})
├── Workflow Executors        ←── 各业务适配器
│   ├── DeFiSwapExecutor
│   ├── DeFiLendExecutor
│   ├── NFTExecutor
│   └── CrossChainExecutor
└── ContractRegistry (可选)   ←── 链上地址发现
```

### 10.2 部署流程

```
阶段 1: 预部署
  ├── forge test 全绿
  ├── 2+ 家第三方安全审计
  ├── 测试网压测 ≥ 1,000 TPS
  └── 密钥仪式（离线生成一次性部署私钥）

阶段 2: 主网部署
  ├── forge script Deploy.s.sol --broadcast
  ├── 合约验证（Blockscout / Monad Explorer）
  └── Owner 移交至 TimelockController（同一交易原子化）

阶段 3: 部署后验证
  ├── registerAgent() 测试交易
  ├── executeAgentTask() 测试交易
  └── 事件监听器确认事件正常 emit

阶段 4: 权限移交
  └── 多签通过 Safe UI 接管 Timelock admin
```

**灰度发布**：Phase 1 白名单 5-10 Agent (48h) → Phase 2 扩大至 100 Agent (1 周) → 公开无许可。

### 10.3 升级策略：不可变核心 + Agent 迁移

不使用 UUPS/Transparent 代理模式。升级流程：

```
1. 部署 MonadAgentHub V2（新地址）
2. 旧合约调用 deprecate()（禁止新任务，保留只读）
3. Agent Owner 逐个调用 migrateAgent(oldId) → 获得新 ID
4. 链下监听 AgentMigrated 事件 → 更新 ID 映射
5. deployments.json 更新至新地址
```

---

## 11. 前端集成点

虽然 MonadFlow 本身不包含前端页面，但架构已为前端预留了完备的集成接口：

### 11.1 合约读写

| 前端需求 | 合约接口 | 说明 |
|---------|---------|------|
| 注册 Agent | `registerAgent(workflowType)` → agentId | 新用户创建 Agent |
| 查看 Agent | `getAgentState(agentId, key)` | 只读查询 |
| 执行任务 | `executeAgentTask(agentId, nonce, taskData)` | 写操作，需签名 |
| 停用 Agent | `deactivateAgent(agentId)` | 仅 owner |
| 迁移 Agent | `migrateAgent(oldAgentId)` | 版本升级时 |

### 11.2 实时数据订阅

```typescript
// 通过 viem 订阅合约事件
publicClient.watchContractEvent({
  address: HUB_ADDRESS,
  event: parseAbiItem('event AgentExecuted(uint256 indexed agentId, ...'),
  onLogs: (logs) => updateDashboard(logs),
})
```

### 11.3 监控 API

| 端点 | 用途 | 返回 |
|------|------|------|
| `GET /healthz` | K8s liveness | `{"status":"ok"}` |
| `GET /readyz` | K8s readiness | `{"status":"ok","rpc":true,"db":true}` |
| `GET /metrics` | Prometheus scrape | TPS, 延迟分布, 队列深度 |
| `POST /api/v1/dql/replay` | 手动重放死信 | 需 HMAC 签名认证 |

### 11.4 建议的前端技术栈

```
Next.js 14+ (App Router)
  ├── wagmi + viem (合约交互)
  ├── shadcn/ui (组件库)
  ├── @tanstack/react-query (服务端状态)
  └── Recharts / Tremor (图表)

构建周期估算: 1-2 周（基础版）
```

### 11.5 建议的功能模块

```
Agent Dashboard
├── 概览页         TPS 实时、活跃 Agent 数、系统健康状态
├── Agent 管理      注册/停用/迁移、nonce 查看、执行历史
├── DLQ 管理        死信队列查看、手动重放、poison message 标记
├── 熔断器状态      各 Adapter 状态、手动熔断/恢复
├── 合约管理        pause/unpause（多签提案）、版本查询、Gas 余额
└── 性能监控        Grafana iframe 嵌入，P50/P95/P99 延迟图表
```

---

## 12. 风险与假设

### 12.1 核心假设

| 假设 | 验证方法 | 若假设不成立 |
|------|---------|-------------|
| Monad 调度器对无冲突交易自动并行 | 主网上线首周持续测量并行率 | 系统退化为传统串行 EVM 水平，TPS 下降但不影响正确性 |
| 主网调度器行为与测试网一致 | 灰度首阶段监测并行率 ≥ 90% | 调整 batch size 和并行策略以适应实际调度器 |
| 独立 storage slot 不会被编译器/优化器合并 | Solidity 编译器验证 + Echidna 模糊测试 invariant | 调整 struct 布局，使用 `uint256` 占位强制隔离 |

### 12.2 已知风险

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| Monad 主网延迟上线 | 中 | 高 | 合约与 Solidity/EVM 完全兼容，可迁移至其他并行 EVM |
| RPC 层成为并发瓶颈 | 高 | 中 | 3 个备用端点 + 连接池控制 + 批次聚合 |
| 第三方安全审计发现严重漏洞 | 中 | 高 | Phase 1 测试网充分验证 + 2+ 家审计公司独立审计 |
| 并行假设在主网上不成立 | 低 | 中 | 优雅降级设计——最差情况等同于传统串行 EVM |

---

## 附录

### A. 相关文档

| 文档 | 内容 |
|------|------|
| [architecture.md](./architecture.md) | 完整技术架构设计（SLO、模块、安全模型） |
| [contracts.md](./contracts.md) | 合约接口规范（每函数签名、事件、自定义错误） |
| [deployment.md](./deployment.md) | 部署流程、密钥仪式、灰度策略、回滚 |
| [development.md](./development.md) | 开发环境搭建、CI/CD、代码规范 |
| [testing.md](./testing.md) | 测试策略、压测脚本、形式化验证、混沌工程 |
| [review-fixes.md](./review-fixes.md) | 历次审查的修改方案与验收清单 |

### B. 技术栈速查

| 层级 | 技术 |
|------|------|
| 智能合约 | Solidity ^0.8.20 + Foundry |
| 链下脚本 | TypeScript + viem |
| 执行层 | Monad Parallel EVM |
| 数据存储 | PostgreSQL + TimescaleDB + Redis + ClickHouse |
| 可观测性 | OpenTelemetry + Prometheus + Grafana |
| 治理 | OpenZeppelin TimelockController + Safe{Wallet} 多签 |
| 安全 | Slither + Echidna + Certora Prover |
| CI/CD | GitHub Actions（Foundry test + coverage + slither + gas diff） |

---

*文档版本: 1.0.0 | 生成日期: 2026-05-12 | 基于 MonadFlow 全部 7 份设计文档综合编写*
