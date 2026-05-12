# MonadFlow

**Monad 高吞吐/高并发 Agent 工作流上链系统**

基于 Monad 并行 EVM 构建的链上自治 Agent 执行引擎，将 AI Agent 的"决策—执行—状态同步—跨 Agent 协作"全流程搬至链上，利用 Monad 10,000+ TPS 的并行执行能力释放极限性能。

---

## 核心价值

| 传统 EVM（以太坊/BSC） | MonadFlow |
|------------------------|-----------|
| 串行执行，Agent 并发请求拥堵 | 并行 EVM，无冲突交易自动并行 |
| TPS 15~25，多 Agent 同时触发大量失败 | TPS 10,000+，支撑数百个 Agent 同时运行 |
| 高延迟，跨合约调用阻塞严重 | 亚秒级区块确认，Agent 实时响应 |
| 完全不可用于工业化 Agent 集群 | 让链上高吞吐 Agent 集群成为现实 |

---

## 架构概览

```
链下 Agent 集群（AI 决策/事件驱动）
        │ 高并发 RPC 请求
        ▼
┌──────────────────────────────────────┐
│  Monad 链上                          │
│  ┌──────────┐  ┌──────────────────┐  │
│  │ Agent    │  │  并行执行池      │  │
│  │ 调度中心 │──│  (Parallel EVM)  │  │
│  └──────────┘  └──────────────────┘  │
│  ┌──────────────────────────────────┐ │
│  │  状态库 (独立存储槽)             │ │
│  └──────────────────────────────────┘ │
└──────────────────────────────────────┘
        │
        ▼
链上业务：DeFi 交互 / NFT / 数据协议 / 跨链桥
```

---

## 快速开始

### 环境要求

- Foundry >= 0.3.0
- Node.js >= 18
- pnpm >= 8 (可选，仅 TypeScript 脚本需要)

### 安装

```bash
git clone <repo-url> MonadFlow
cd MonadFlow

# 安装 Foundry 依赖
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
forge install foundry-rs/forge-std@v1.9.2

# 安装 Node.js 依赖（可选）
pnpm install
```

### 编译

```bash
forge build
```

### 测试

```bash
# 全部测试
forge test -vvv

# Gas 报告
forge test --gas-report

# 单文件测试
forge test --match-path test/AgentHub.t.sol -vvvv
```

### 测试结果

```
✅ AgentHub.t.sol        46 passed
✅ AgentRegistry.t.sol   18 passed
✅ ParallelTest.t.sol     6 passed
✅ FullWorkflow.t.sol     7 passed
✅ AgentFuzz.t.sol        1 passed (256 runs, 3840 calls)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Total:                78 passed, 0 failed
```

### 部署到 Monad 测试网

```bash
source .env
forge script script/Deploy.s.sol:DeployMonadFlow \
  --rpc-url $MONAD_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### 并发压测

```bash
AGENT_HUB_ADDRESS=<部署地址> npx tsx scripts/benchmark.ts
```

---

## 项目结构

```
MonadFlow/
├── contracts/
│   ├── MonadAgentHub.sol       # Agent 核心调度合约
│   ├── AgentRegistry.sol       # Agent 注册与管理
│   ├── WorkflowExecutor.sol    # 工作流执行抽象基类
│   ├── interfaces/
│   │   ├── IMonadAgentHub.sol  # Hub 接口 + TaskData/AgentInfo 结构体
│   │   └── IAgentRegistry.sol  # Registry 接口
│   └── adapters/
│       ├── DeFiAdapter.sol     # DeFi 适配器接口
│       └── CrossChainAdapter.sol # 跨链适配器接口
├── scripts/
│   ├── Deploy.s.sol            # Foundry 部署脚本 (含 TimelockController)
│   ├── benchmark.ts            # 并发压测脚本
│   ├── registerAgent.ts        # Agent 注册
│   ├── executeTask.ts          # 任务执行
│   └── listenEvents.ts         # 事件监听
├── test/
│   ├── AgentHub.t.sol          # MonadAgentHub 单元测试 (46 用例)
│   ├── AgentRegistry.t.sol     # AgentRegistry 单元测试 (18 用例)
│   ├── ParallelTest.t.sol      # 100 Agent 并行执行测试
│   ├── fuzz/AgentFuzz.t.sol    # Invariant 模糊测试 (nonce 单调性)
│   └── integration/FullWorkflow.t.sol # 完整生命周期集成测试
├── docs/                       # 完整设计文档
├── foundry.toml                # Foundry 配置 (solc 0.8.20)
├── remappings.txt              # 导入路径重映射
├── package.json                # Node.js 依赖
├── tsconfig.json               # TypeScript 配置
└── .env.example                # 环境变量模板
```

---

## Gas 报告

| 合约 | 部署 Gas | 字节码 |
|------|---------|--------|
| MonadAgentHub | 1,655,233 | 7,682 B |
| AgentRegistry | 739,304 | 3,366 B |

| 核心函数 | Gas (min) | Gas (avg) |
|---------|----------|----------|
| `registerAgent` | 23,774 | ~187k |
| `executeAgentTask` | 24,568 | ~47k |
| `batchExecuteTasks` | 26,388 | ~56k |
| `deactivateAgent` | 23,630 | ~32k |

---

## 支持的工作流类型

| 标识 | 描述 | 安全级别 |
|------|------|---------|
| `DEFI_SWAP` | DEX 兑换 | L2 |
| `DEFI_LEND` | 借贷 | L2 |
| `NFT_MINT` | NFT 铸造 | L1 |
| `NFT_TRADE` | NFT 交易 | L1 |
| `CROSS_CHAIN` | 跨链桥接 | L3 |
| `SOCIAL_NOTIFY` | 社交通知 | L0 |
| `GAME_NPC` | 游戏 NPC | L1 |
| `CUSTOM` | 自定义 | L0 |

---

## 性能指标

| 指标 | 目标值 | Monad 理论值 |
|------|--------|-------------|
| TPS | 1,000+ | 10,000+ |
| 并行率 | ≥90% | ≥95% |
| 确认延迟 | <1s | <1s |
| 并发失败率 | <1% | 0% |

---

## 文档

- [技术架构设计](./docs/architecture.md)
- [合约规范](./docs/contracts.md)
- [开发指南](./docs/development.md)
- [部署指南](./docs/deployment.md)
- [测试与压测指南](./docs/testing.md)
- [审查修改方案](./docs/review-fixes.md)
- [生产就绪性分析](./docs/production_readiness_analysis.md)

---

## License

UNLICENSED
