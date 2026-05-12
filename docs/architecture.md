# 技术架构设计

## 一、设计目标

构建一套**可工业化部署**的链上 Agent 工作流系统，核心目标：

1. **并行无阻塞**：充分利用 Monad 并行 EVM 特性，Agent 交易无写冲突时自动并行执行
2. **高吞吐**：支持 1,000+ TPS 的 Agent 任务并发提交与执行
3. **低延迟**：任务提交到链上包含 < 1 秒
4. **EVM 完全兼容**：标准 Solidity 合约，可无缝迁移至任意 EVM 链
5. **可扩展**：工作流模块化，支持 DeFi、NFT、游戏等任意业务场景
6. **可恢复**：具备完整的备份、灾难恢复与优雅降级能力

---

### 1.1 服务等级目标（SLO）

> 本系统区分两类延迟 SLO：**交易包含性**（tx inclusion，即弱最终性）和 **事件最终性**（reorg-safe confirmation，即强最终性）。二者分别服务于不同的业务路径。

#### 交易包含性 SLO（弱最终性路径）

适用于：信息通知、状态查询、非资金操作等不依赖 reorg 安全的场景。Agent 闭环在交易被区块包含时即刻触发。

| 指标 | SLI | SLO |
|------|-----|-----|
| 可用性 | 成功提交 / 总提交 | 99.9% |
| 交易包含延迟 P50 | 提交 → tx inclusion | < 500ms |
| 交易包含延迟 P95 | 提交 → tx inclusion | < 2s |
| 交易包含延迟 P99 | 提交 → tx inclusion | < 5s |
| 错误预算 | 1 - 可用性 | 月 0.1%（~43 分钟/月）|

#### 事件最终性 SLO（强最终性路径）

适用于：大额资金决策（单笔 >= $10,000）、跨链消息确认等必须等待 reorg 安全确认的场景。

| 指标 | SLI | SLO |
|------|-----|-----|
| 事件最终性延迟 P50 | tx inclusion → N 块确认 | < 3s（N=3，主网） |
| 事件最终性延迟 P95 | tx inclusion → N 块确认 | < 6s（N=6，主网） |
| 事件最终性一致性 | 确认事件数 / 链上实际事件数（最终确认后） | 100% |

> **N 块确认数配置**：测试网 N=1（~1s），主网 N=3（~3s）。N 值通过环境变量 `REORG_CONFIRMATION_BLOCKS` 可配置。仅强最终性路径等待 N 块，弱最终性路径在交易包含时立即触发。切换逻辑由 Event Listener 内的事件分类器控制，见 2.3 节。

---

## 二、整体架构

### 2.1 三层架构

```
┌─────────────────────────────────────────────────────────────┐
│  链下层 (Off-Chain Layer)                                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────────┐  │
│  │ AI Agent │ │ Event    │ │ Strategy │ │   Monitor     │  │
│  │ Engine   │ │ Listener │ │ Engine   │ │   Dashboard   │  │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └───────┬───────┘  │
│       └─────────────┴────────────┴───────────────┘          │
│                          │ RPC / WebSocket                    │
├──────────────────────────┼──────────────────────────────────┤
│  链上层 (On-Chain Layer) │   Monad Parallel EVM              │
│  ┌───────────────────────┴──────────────────────────────┐   │
│  │              Agent 调度中心 (MonadAgentHub)           │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │   │
│  │  │ Agent       │  │ 并行执行池  │  │ 状态存储    │  │   │
│  │  │ Registry    │  │ (Parallel   │  │ (独立槽位)  │  │   │
│  │  │             │  │  Executor)  │  │             │  │   │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  │   │
│  └──────────────────────────────────────────────────────┘   │
│                          │                                   │
│  ┌───────────────────────┴──────────────────────────────┐   │
│  │              业务集成层 (Integration Layer)           │   │
│  │  ┌──────┐ ┌────────┐ ┌────────┐ ┌──────────────────┐ │   │
│  │  │ DEX  │ │ Lending│ │  NFT   │ │ Cross-Chain      │ │   │
│  │  │ Adapter│ │Adapter │ │Adapter │ │ Bridge Adapter  │ │   │
│  │  └──────┘ └────────┘ └────────┘ └──────────────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 数据流

```
1. 事件触发 / AI决策
         │
2. 链下 Agent 生成任务
         │
3. 高并发 RPC 批量提交 ─────────────┐
         │                          │
4. Monad 并行 EVM 执行 ←────────────┘
   ├── 交易 A (agentId=1) 写入 storage[1]
   ├── 交易 B (agentId=2) 写入 storage[2]   ← 0 冲突，完全并行
   ├── 交易 C (agentId=3) 写入 storage[3]
   └── ...
         │
5. 链上状态更新 / Event 发出
         │
6. 链下 Agent 读取结果 → 闭环
```

### 2.3 链下组件详细设计

#### Event Listener（事件监听器）

| 属性 | 设计 |
|------|------|
| 投递保证 | At-least-once，通过 `executionId = keccak256(agentId, nonce, blockNumber)` 去重实现幂等 |
| Reorg 处理 | 等待 N 个区块确认（可配置，测试网 1，主网 3-5）。仅强最终性路径（大额资金决策）等待确认，弱最终性路径（信息通知类）在交易包含时立即触发 |
| 失败重试 | 指数退避（1s → 2s → 4s），最大重试 3 次，超限进入 DLQ（死信队列）|
| DLQ 管理 | 按 agentId + workflowType 分区，独立消费者处理；单 Agent 故障不阻塞全局；堆积超过 100 条触发 PagerDuty 告警；Redis Streams 实现，消息 TTL 7 天 |
| DLQ 消费者 | 独立 Consumer Group 消费 DLQ Stream；消费失败指数退避重试（1s→2s→4s，最多 3 次），超限标记为 poison message 并归档至 PostgreSQL `dead_letters` 表；Poison message 堆积超过 10 条触发告警 |
| DLQ 重放 | REST API `POST /api/v1/dql/replay?agentId={id}&workflowType={type}&startTs={ts}&endTs={ts}`；支持按 agentId + workflowType + 时间窗口过滤重放；重放消息写入原始 task:queue 而非 DLQ |
| DLQ API 认证 | API Key + HMAC 签名认证；操作审计日志写入 `audit_logs` 表 |
| 事件过滤 | 按 agentId + workflowType 双索引高效过滤 |
| 健康检查 | `GET /healthz` 返回连接状态、lag 偏移量、最近事件时间戳 |
| 实现 | TypeScript + viem watchContractEvent，状态持久化至 PostgreSQL |

#### AI Agent Engine（AI 决策引擎）

| 属性 | 设计 |
|------|------|
| 输入 | 链上事件 + 链下数据（价格/预言机）|
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

```
AI Agent → Strategy Engine → Task Queue (Redis Streams / BullMQ)
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
              Worker 1        Worker 2        Worker N
              (批量提交至 Monad RPC)
```

#### 状态持久化

| 数据 | 存储 | 说明 |
|------|------|------|
| Agent 元数据 | PostgreSQL | agentId, owner, workflowType, status |
| 执行历史 | PostgreSQL + TimescaleDB | 时序查询优化 |
| 任务队列 | Redis | 内存优先，TTL 自动清理 |
| 事件日志 | ClickHouse（链下分析）/ The Graph（链上 DApp 查询）| 二选一或互补：ClickHouse 适合内部运维分析、SQL 聚合查询；The Graph 适合对外 DApp 提供 GraphQL 查询接口。Phase 1 使用 ClickHouse，Phase 3 评估 The Graph 需求 |

### 2.4 状态持久化 Schema

#### PostgreSQL 核心表

```sql
CREATE TABLE agents (
    agent_id        BIGINT PRIMARY KEY,
    owner           BYTEA NOT NULL,              -- 20 bytes address
    workflow_type   BYTEA NOT NULL,              -- 32 bytes bytes32
    is_active       BOOLEAN NOT NULL DEFAULT true,
    nonce           BIGINT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_agents_owner ON agents(owner);
CREATE INDEX idx_agents_workflow ON agents(workflow_type);

CREATE TABLE executions (
    execution_id    BYTEA PRIMARY KEY,           -- keccak256(agentId, nonce, blockNumber)
    agent_id        BIGINT NOT NULL REFERENCES agents(agent_id),
    nonce           BIGINT NOT NULL,
    success         BOOLEAN NOT NULL,
    gas_used        BIGINT,
    block_number    BIGINT NOT NULL,
    block_hash      BYTEA NOT NULL,
    tx_hash         BYTEA NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_executions_agent_id ON executions(agent_id, nonce DESC);
CREATE UNIQUE INDEX idx_executions_dedup ON executions(agent_id, nonce);

-- TimescaleDB hypertable for execution time-series
SELECT create_hypertable('executions', 'created_at', chunk_time_interval => INTERVAL '1 day');

-- 数据保留：执行记录保留 90 天，按天自动压缩旧分区
SELECT add_retention_policy('executions', INTERVAL '90 days');
SELECT add_compression_policy('executions', INTERVAL '7 days');
```

#### Redis 任务队列 Schema

```
Key: task:queue:{agentId}         → Sorted Set (score = nonce)
Key: task:dedup:{executionId}     → String (TTL 86400s)
Key: dlq:{agentId}:{workflowType} → Stream
Key: health:listener              → Hash (lastBlock, lag, status)
```

#### Redis 持久化配置

| 配置项 | 生产环境 | 说明 |
|--------|---------|------|
| RDB (快照) | `save 900 1 300 10 60 10000` | 每 15 分钟至少 1 次变更时触发快照 |
| AOF (追加日志) | `appendonly yes`, `appendfsync everysec` | 每秒 fsync，至多丢失 1s 数据 |
| 混合持久化 | Redis ≥ 5.0 默认开启 | RDB 快照 + AOF 增量组合 |
| 数据丢失应对 | 未确认任务重新从链上事件回放；`task:dedup` 去重保证幂等 | 恢复流程见 2.6 灾难恢复 |

> **风险声明**：Redis 进程崩溃可能丢失最近 1s 内的 AOF 数据。受影响任务通过 Event Listener 的 at-least-once 机制 + executionId 去重自动恢复。Redis 集群部署（Sentinel/Cluster）方案见运维手册。

### 2.5 优雅降级与弹性设计

#### 降级层级

```
Level 0: 全功能（正常模式）
  ├── 所有 Agent 正常执行，并行调度
  └── 触发条件: 所有组件健康

Level 1: 降级 RPC（RPC 延迟/不可用）
  ├── 自动切换至备用 RPC 端点（最多 3 个 fallback）
  ├── 队列缓存未提交任务（Redis 持久化），RPC 恢复后批量重放
  └── 触发条件: RPC 错误率 > 10% 或 P99 延迟 > 10s

Level 2: 降级外部协议（DEX/借贷协议不可用）
  ├── 对应 Adapter 进入熔断状态（Circuit Breaker: 半开/全开/关闭）
  ├── 依赖该协议的 Agent 任务进入 DLQ，不阻塞其他 Agent
  └── 触发条件: 连续 5 次外部调用失败

Level 3: 降级为只读模式（合约 paused）
  ├── 仅允许查询操作，禁止所有 Agent 执行
  ├── Event Listener 继续运行，缓存事件供恢复后处理
  └── 触发条件: 安全事件 / 手动 pause()

Level 4: 紧急停止
  ├── 所有链下组件停止，仅保留监控
  └── 触发条件: 合约漏洞 / 私钥泄露
```

#### 熔断器配置

| 参数 | 值 |
|------|-----|
| 失败阈值 | 5 次连续失败 |
| 熔断时间 | 60s（半开状态等待） |
| 半开探测 | 每 30s 发送 1 个探测交易 |
| 恢复阈值 | 3 次连续成功则关闭熔断器 |

#### 熔断器状态转换

```
    连续 5 次失败              等待 60s
  CLOSED ──────────→ OPEN ──────────→ HALF_OPEN
    ↑                                    │
    └──────── 3 次连续成功 ←─────────────┘
                     │
                     └── 1 次失败 → 重新进入 OPEN（重置计时器）
```

- 单个 Adapter 熔断仅影响依赖该协议的 Agent（L2 级），不影响其他 Agent
- 同一 Adapter 连续 3 次 OPEN→HALF_OPEN→OPEN 循环（即持续无法恢复）→ 触发该 Adapter 永久降级通知
- 若超过 50% 的 Adapter 同时处于 OPEN 状态 → 建议手动触发 L3（只读模式）

### 2.6 数据备份与灾难恢复

#### 备份策略

| 数据层 | 备份方案 | RPO | RTO |
|--------|---------|-----|-----|
| PostgreSQL | 每日全量 pg_dump + WAL 持续归档至 S3；保留 30 天全量 + 7 天 WAL | < 1 分钟（PITR） | < 30 分钟 |
| Redis | RDB 快照每 15 分钟 + AOF 每秒 fsync；本机 + S3 双副本 | < 1 秒（AOF） | < 5 分钟 |
| 合约状态 | 链上数据天然备份于 Monad 共识；Events 通过 Event Listener 重放到 PostgreSQL | 0（链上不丢失） | 依赖 Event Listener 追块速度 |

#### 灾难恢复流程

```
1. 检测故障 → 自动触发 PagerDuty 告警
2. 评估影响范围（Agent 停机 / 数据丢失 / 合约异常）
3. 数据层恢复:
   ├── PostgreSQL: 从最新全量 + WAL 回放至目标时间点
   ├── Redis: 从最新 RDB 恢复，未持久化的队列项从链上 Events 回放补全
   └── 链上状态: 无需恢复（去中心化保证）
4. 服务重启顺序: PostgreSQL → Redis → Event Listener → Strategy Engine → AI Agent Engine
5. 验证: Event Listener 处理 backlog → 确认所有队列消费正常 → Agent 恢复执行
6. 复盘: 记录 RTO 达标情况 + 根因分析 + 改进措施
```

#### 跨可用区部署

| 层级 | 策略 |
|------|------|
| PostgreSQL | Primary-Standby 流复制，跨 AZ |
| Redis | Sentinel 哨兵模式，3 节点跨 AZ |
| 链下服务 | K8s 多副本，跨 AZ Pod 反亲和调度 |
| RPC 端点 | 主备 3 端点，跨不同 RPC 提供商 |

#### 数据一致性校验

```
每日定时任务:
  SELECT COUNT(*) FROM chain_events WHERE block_number >= :start
  对账: PostgreSQL 中事件数 == 链上合约 emit 事件数（指定区块范围）
  偏差 > 0 → 触发 Event Listener 增量回放 → 若仍不一致 → 人工介入
```

### 2.7 可观测性设计

#### 分布式追踪 (OpenTelemetry)

```
Event Listener ──traceId──→ Strategy Engine ──traceId──→ RPC Submit ──span──→ Monad Chain
       │                        │                          │
       └──span──→ PostgreSQL     └──span──→ Redis Queue      └──span──→ tx confirmation
```

每个 tracing span 携带属性：`agentId`, `workflowType`, `nonce`, `executionId`, `blockNumber`。

#### 结构化日志格式 (JSON)

```json
{
  "timestamp": "2026-05-12T10:30:00.000Z",
  "level": "INFO",
  "traceId": "abc123",
  "spanId": "def456",
  "component": "event-listener",
  "agentId": 42,
  "nonce": 5,
  "executionId": "0x...",
  "event": "agent_executed",
  "latency_ms": 340,
  "blockNumber": 1234567,
  "txHash": "0x..."
}
```

#### 健康检查端点

| 端点 | 用途 | 返回 |
|------|------|------|
| `GET /healthz` | K8s liveness probe | `{"status":"ok"}` 或 `503` |
| `GET /readyz` | K8s readiness probe | `{"status":"ok","rpc":true,"db":true,"redis":true}` |
| `GET /metrics` | Prometheus scrape | OpenMetrics 格式，含 TPS、延迟分布、队列深度、熔断器状态 |

#### 监控仪表盘 (Grafana)

| 面板 | 指标 |
|------|------|
| 系统概览 | TPS、成功率、P50/P95/P99 延迟、活跃 Agent 数 |
| 队列深度 | Redis 队列积压、DLQ 堆积量、消费速率 |
| RPC 健康 | 各 RPC 端点延迟/错误率、当前活跃端点 |
| 熔断器 | 各 Adapter 的熔断器状态（绿/黄/红） |
| Gas 消耗 | 合约余额、单交易 Gas 分布、Gas 消耗速率 |
| 并行率 | 独立 Agent 并发 TPS / 单 Agent 串行 TPS 比值 |

### 2.8 流量控制与限流

#### RPC 层限流

| 策略 | 实现 |
|------|------|
| 连接池上限 | 单客户端到同一 RPC 端点最大 200 并发连接（`p-limit` 控制） |
| 速率限制 | 单 IP 每秒最多 500 请求，超限返回 429 + `Retry-After` 头 |
| 退避策略 | 收到 429 或 RPC 错误时，指数退避重试（1s→2s→4s→8s，最大 3 次） |
| RPC 负载均衡 | 轮询 3 个 RPC 端点，错误率 > 10% 自动踢出，30s 后半开探测 |

#### 合约层限流

| 策略 | 实现 |
|------|------|
| Gas 经济限流 | 每次 Agent 任务消耗真实 Gas，天然抑制无意义批量请求 |
| Agent 级速率限制（可选）| 通过链下 Strategy Engine 控制单 Agent 每秒最大提交数（默认 50/s） |
| 合约级暂停 | `pause()` 全局停止所有写操作；恢复需通过 TimelockController 延迟 ≥ 24h |

#### API 网关

链下服务统一通过 API Gateway（如 Kong / NGINX）暴露：

```
                    ┌─────────────────┐
                    │  API Gateway     │
                    │  (Kong/NGINX)    │
                    └───────┬─────────┘
          ┌─────────────────┼─────────────────┐
          ▼                 ▼                  ▼
   Event Listener    Strategy Engine    Monitor Dashboard
   (WebSocket)        (REST/gRPC)        (REST)
```

| 功能 | 实现 |
|------|------|
| 认证 | API Key + HMAC 签名（服务间）；JWT（管理面板） |
| TLS 终止 | Let's Encrypt 自动续期 |
| 请求日志 | 结构化 JSON 日志，含 traceId |
| 健康检查 | 代理 `/healthz` 至各服务 |

---

## 三、Monad 并行 EVM 核心原理

### 3.1 并行执行条件

Monad 执行引擎会对所有待处理交易进行**乐观并行执行**。关键在于：

- **读读**：任意数量交易可同时读取相同存储位 → 并行
- **读写/写写**：存在存储位冲突时，Monad 自动串行化冲突交易，其他交易继续并行

### 3.2 MonadFlow 的并行化设计

```
传统设计（❌ 不可并行）:
  mapping(uint256 => GlobalState) states;  // 所有 Agent 共用一个 map
  uint256 globalCounter;                   // 全局计数器 → 写冲突

MonadFlow 设计（✅ 可并行）:
  mapping(uint256 => Agent) agents;   // 每个 agentId 独立存储槽
  // Agent A (id=1) → storage slot H(KECCAK(1))
  // Agent B (id=2) → storage slot H(KECCAK(2))  ← 完全不同的槽位

  // 关键设计决策：不使用全局计数器（totalAgents, totalExecutions 等）
  // 所有统计信息通过链下索引 Events 聚合，避免引入全局存储槽写冲突
  // 此设计的正确性依赖于 Event Listener 的 at-least-once 投递保证
```

### 3.3 并行化设计规则

| 规则 | 说明 | 实现方式 |
|------|------|---------|
| 独立存储槽 | 每个 Agent 使用独立存储空间 | `mapping(uint256 => Agent)` + agentId 索引 |
| 无写冲突 | Agent A 不修改 Agent B 状态 | Agent 内操作仅访问自身存储 |
| 批量独立 ID | 并发请求使用不同 agentId | 链下预分配 ID，批量调用 |
| 避免全局锁 | 不使用 ReentrancyGuard 等串行化工具 | 依赖独立存储槽保证安全 |

---

## 四、核心模块设计

### 4.1 MonadAgentHub（Agent 调度中心）

**职责**：Agent 注册、任务执行、状态管理、事件发送

```
MonadAgentHub
├── registerAgent()         # 注册新 Agent，分配独立 ID
├── executeAgentTask()      # 执行 Agent 工作流（并行安全入口）
├── batchExecuteTask()      # 批量执行多个 Agent 任务
├── deactivateAgent()       # 停用 Agent
├── getAgentState()         # 查询 Agent 状态
└── events:
    ├── AgentRegistered
    ├── AgentExecuted
    ├── AgentDeactivated
    └── WorkflowCompleted
```

### 4.2 AgentRegistry（Agent 注册中心）

**职责**：Agent 生命周期管理、权限控制

### 4.3 WorkflowExecutor（工作流执行引擎）

**职责**：可拔插的工作流模块，支持 DeFi/NFT/游戏等业务

### 4.4 Integration Adapters（业务适配器）

**职责**：对接外部协议（Uniswap、Aave、OpenSea 等）

---

## 五、安全模型

### 5.1 威胁模型

| 威胁 | 缓解措施 |
|------|---------|
| 恶意 Agent 写入其他 Agent 状态 | 独立存储槽 + 仅 owner 可写 |
| 重入攻击 | 独立存储槽天然隔离 |
| 签名伪造 | agentId 绑定 owner，仅 owner 可执行 |
| 批量 DDoS | Gas 计量 + 调用频率限制（可选） |

### 5.2 权限设计

```
Owner ──────────── 合约管理员（可升级、暂停）
  │
  └── Agent Owner ── 单个 Agent 管理员（执行自身 Agent 任务）
```

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

#### Monad 并行 EVM 假设风险

本系统架构的核心前提是 Monad 并行 EVM 对无存储冲突交易的真实并行调度。以下假设若在主网上不成立，系统性能将退化至传统串行 EVM 水平：

| 假设 | 风险 | 缓解 |
|------|------|------|
| 独立 storage slot → 自动并行 | 调度器可能存在 bug 或调度粒度不足 | 压测过程中持续测量并行率（独立 Agent 并发 vs 单 Agent 串行的延迟比） |
| 主网调度器与测试网一致 | 主网可能采用不同的调度参数 | 主网上线首周持续监测并行率指标，低于 90% 触发告警 |
| 无冲突交易不触发串行化 | 区块内的 Gas 竞争/优先级可能导致部分串行化 | 设计为「并行友好」而非「强制并行」，接受部分退化 |

若 Monad 并行调度未达预期，系统仍可在传统 EVM 串行模式下正常运行，仅 TPS 下降。

### 5.4 ECDSA 密钥管理

Agent 私钥是系统安全的核心边界。其生命周期管理必须满足生产级标准：

| 阶段 | 要求 |
|------|------|
| 密钥生成 | 使用 BIP-32 HD 钱包派生，m/44'/60'/0'/0/{agentId}，根种子由硬件安全模块（HSM）保管 |
| 密钥存储 | 生产环境：AWS KMS / Google Cloud KMS / HashiCorp Vault（不可导出私钥，仅签名接口）。开发环境：加密的 `.env` 文件 + `.gitignore`，严禁明文私钥提交 |
| 签名与提交分离 | 签名者私钥（KMS 内）仅用于签名 TaskData，不持有 MON 余额；提交者地址（Relayer）持有 Gas 费用，通过 `executeAgentTask` 的 `msg.sender` 校验与 Agent owner 解耦（待 Phase 2 实现 meta-transaction） |
| 密钥轮换 | 每 90 天轮换一次。Agent 注册新的 owner 地址 → 旧地址撤销 → 链下更新签名者映射 |
| 密钥泄露响应 | 1) 立即调用 `deactivateAgent()` 停用受影响 Agent；2) 轮换 KMS 密钥；3) 使用新密钥重新注册 Agent；4) 审计泄露期间的异常交易 |
| 审计日志 | 所有签名操作记录到不可篡改的审计日志（AWS CloudTrail / KMS audit log），包含时间戳、agentId、签名哈希 |

#### 审计日志 Schema

链下服务统一的审计日志格式，写入 PostgreSQL `audit_logs` 表（不可变，仅 INSERT）：

```sql
CREATE TABLE audit_logs (
    id              BIGSERIAL PRIMARY KEY,
    event_type      TEXT NOT NULL,              -- 'key_sign', 'dlq_replay', 'agent_deactivate', 'pause_contract'
    actor           TEXT NOT NULL,              -- 操作者标识 (email / service account)
    resource_type   TEXT NOT NULL,              -- 'agent', 'key', 'contract', 'dlq'
    resource_id     TEXT NOT NULL,              -- agentId / keyId / contract address
    details         JSONB NOT NULL DEFAULT '{}',-- 操作详情 (签名哈希、参数等)
    source_ip       INET,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_resource ON audit_logs(resource_type, resource_id, created_at DESC);
CREATE INDEX idx_audit_actor ON audit_logs(actor, created_at DESC);

-- 保留 365 天
SELECT create_hypertable('audit_logs', 'created_at', chunk_time_interval => INTERVAL '1 day');
SELECT add_retention_policy('audit_logs', INTERVAL '365 days');
```

#### Admin 密钥管理

合约管理员（Owner/Timelock 签名者）的密钥管理独立于 Agent 密钥体系：

| 阶段 | 要求 |
|------|------|
| 密钥存储 | 必须使用硬件钱包（Ledger/Trezor/GridPlus），禁止使用热钱包私钥 |
| 权限分离 | 每个多签签名者使用独立硬件钱包；Timelock executor 与 proposer 可按需分离为不同多签组 |
| 密钥轮换 | 管理员密钥每 180 天轮换；轮换前在新 Safe 上创建新多签，通过 Timelock 执行 ownership 转移 |
| 紧急覆盖 | 核心团队保留一个基于 KMS 的紧急 Admin 密钥（操作需 2/3 高管审批 + 完整审计日志） |

> Phase 1（测试网）：允许使用加密环境变量存储私钥。
> Phase 2（主网灰度）：必须迁移至 KMS/HSM，禁止明文私钥接触生产服务器。

---

## 六、技术栈

| 层级 | 技术 | 用途 |
|------|------|------|
| 智能合约 | Solidity ^0.8.20 | 核心合约开发 |
| 合约框架 | Foundry | 编译、测试、部署 |
| 链下脚本 | TypeScript + viem | RPC 交互、压测 |
| 链 | Monad | 并行 EVM 执行层 |
| 监控 | Grafana + Prometheus | 性能监控面板 |
| 数据索引 | The Graph / Envio | 事件索引与查询 |

---

## 七、升级路径

```
Phase 1: Monad 测试网验证
  └── 部署合约 → 并发测试 → 性能基准

Phase 2: Monad 主网上线
  └── 安全审计 → 主网部署 → 灰度接入真实 Agent

Phase 3: 生态集成
  └── DeFi 适配器 → 跨链桥 → 开发者 SDK

Phase 4: 去中心化 Agent 网络
  └── Agent 注册经济模型 → DAO 治理 → 无许可 Agent 接入
```

---

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
