# 开发指南

## 一、环境搭建

### 1.1 前置依赖

```bash
# Node.js >= 18
node -v

# pnpm
npm install -g pnpm

# Foundry (使用稳定版本)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 验证安装
forge --version   # >= 0.3.0
cast --version    # >= 0.3.0
```

> **编译器版本控制**：在 `foundry.toml` 中通过 `solc = "0.8.20"` 锁定 Solidity 编译器版本。Foundry 自身版本由 `foundryup` 管理，建议使用稳定版（stable）或锁定到特定已知可工作的 tag，而非 nightly commit hash，以保证 CI 可复现性。

### 1.2 项目初始化

```bash
# 克隆项目
git clone <repo-url> MonadFlow
cd MonadFlow

# 安装依赖
pnpm install

# 初始化 Foundry 依赖
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-commit
forge install foundry-rs/forge-std@v1.9.2 --no-commit

# 初始化 Git submodule（如果尚未初始化）
git submodule update --init --recursive
```

### 1.3 环境变量

```bash
# .env
MONAD_RPC_URL=https://testnet.monad.xyz
PRIVATE_KEY=your_private_key
ETHERSCAN_API_KEY=your_etherscan_key
```

---

## 二、合约开发

### 2.1 编译

```bash
# 编译合约
forge build

# 查看合约大小
forge build --sizes

# 生成 ABI
forge build --silent && cp out/MonadAgentHub.sol/MonadAgentHub.json ./abis/
```

### 2.2 编写新工作流

```solidity
// contracts/workflows/DeFiSwapExecutor.sol
pragma solidity ^0.8.20;

import {WorkflowExecutor} from "../WorkflowExecutor.sol";

contract DeFiSwapExecutor is WorkflowExecutor {
    function execute(
        uint256 agentId,
        bytes calldata taskData
    ) external override returns (bool) {
        _validateAndUpdateState(agentId, taskData);
        _executeExternal(agentId, taskData);
        return true;
    }

    function _executeExternal(
        uint256 agentId,
        bytes calldata taskData
    ) internal nonReentrant {
        // 解析任务数据
        // 执行 DEX swap
        // 返回结果
    }

    function validateTask(
        uint256 agentId,
        bytes calldata taskData
    ) external override view returns (bool) {
        // 验证逻辑
        return true;
    }
}
```

### 2.3 编译配置

```toml
# foundry.toml
[profile.default]
src = "contracts"
out = "out"
libs = ["lib"]
solc = "0.8.20"
evm_version = "shanghai"
optimizer = true
optimizer_runs = 1000000
remappings = [
    "@openzeppelin/=lib/openzeppelin-contracts/",
    "forge-std/=lib/forge-std/src/",
]

[rpc_endpoints]
monad_testnet = "${MONAD_RPC_URL}"
monad_mainnet = "https://rpc.monad.xyz"
```

---

## 三、测试

### 3.1 单元测试

```bash
# 运行所有测试
forge test

# 详细输出
forge test -vvvv

# 指定测试文件
forge test --match-path test/AgentHub.t.sol

# 指定测试函数
forge test --match-test testRegisterAgent

# Gas 报告
forge test --gas-report
```

### 3.2 测试文件结构

```
test/
├── AgentHub.t.sol           # MonadAgentHub 单元测试
├── AgentRegistry.t.sol      # AgentRegistry 单元测试
├── WorkflowExecutor.t.sol   # 工作流执行测试
├── ParallelTest.t.sol       # 并行执行验证测试
├── fuzz/                    # 模糊测试
│   └── AgentFuzz.t.sol
└── integration/             # 集成测试
    └── FullWorkflow.t.sol
```

### 3.3 Fork 测试

```bash
# 在 Monad 测试网 fork 上测试
forge test --fork-url $MONAD_RPC_URL --fork-block-number <BLOCK_NUMBER>
```

---

## 四、部署

### 4.1 本地部署

```bash
# 启动 Anvil (Monad 兼容模式)
anvil --fork-url $MONAD_RPC_URL

# 部署脚本
forge script script/Deploy.s.sol:DeployMonadFlow \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

### 4.2 测试网部署

```bash
# 部署到 Monad 测试网
source .env
forge script script/Deploy.s.sol:DeployMonadFlow \
  --rpc-url $MONAD_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

### 4.3 主网部署

详见 [部署指南](./deployment.md)。

---

## 五、链下交互脚本

### 5.1 注册 Agent

```typescript
// scripts/registerAgent.ts
import { createWalletClient, http, parseAbi, defineChain, toBytes } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

// Monad 测试网自定义链定义（viem 未内置 Monad 链）
const monadTestnet = defineChain({
  id: 10143,
  name: 'Monad Testnet',
  nativeCurrency: { name: 'Monad', symbol: 'MON', decimals: 18 },
  rpcUrls: {
    default: { http: [process.env.MONAD_RPC_URL!] },
  },
})

const abi = parseAbi([
  'function registerAgent(bytes32 workflowType) returns (uint256)',
])

async function register() {
  const account = privateKeyToAccount(process.env.PRIVATE_KEY!)
  const client = createWalletClient({
    chain: monadTestnet,
    account,
    transport: http(process.env.MONAD_RPC_URL),
  })

  const hash = await client.writeContract({
    address: '0xYOUR_AGENT_HUB',
    abi,
    functionName: 'registerAgent',
    args: [toBytes('DEFI_SWAP')], // bytes32
  })
  console.log('Agent registered:', hash)
}

register()
```

### 5.2 执行 Agent 任务

```typescript
// scripts/executeTask.ts
async function execute(agentId: bigint) {
  const hash = await client.writeContract({
    address: '0xYOUR_AGENT_HUB',
    abi,
    functionName: 'executeAgentTask',
    args: [agentId, '0x'],
  })
  console.log('Task executed:', hash)
}
```

---

## 六、事件监听

```typescript
// scripts/listenEvents.ts
import { createPublicClient, http, parseAbi, defineChain } from 'viem'

const monadTestnet = defineChain({
  id: 10143,
  name: 'Monad Testnet',
  nativeCurrency: { name: 'Monad', symbol: 'MON', decimals: 18 },
  rpcUrls: {
    default: { http: [process.env.MONAD_RPC_URL!] },
  },
})

const publicClient = createPublicClient({
  chain: monadTestnet,
  transport: http(process.env.MONAD_RPC_URL),
})

async function watchAgentEvents() {
  publicClient.watchContractEvent({
    address: '0xYOUR_AGENT_HUB',
    abi,
    eventName: 'AgentExecuted',
    onLogs: (logs) => {
      for (const log of logs) {
        console.log(`Agent ${log.args.agentId} executed at ${log.args.timestamp}`)
      }
    },
  })
}

watchAgentEvents()
```

---

## 七、代码规范

### 7.1 Solidity

- 使用 Solidity ^0.8.20
- 遵循 Solidity Style Guide
- 函数命名：`camelCase`，事件：`PascalCase`
- 使用 NatSpec 注释 (@notice, @param, @return)

### 7.2 TypeScript

- 使用 TypeScript strict 模式
- 优先使用 viem (避免 ethers.js v5)
- 使用 ESLint + Prettier

### 7.3 提交规范

```
feat: 新功能
fix: 修复 bug
docs: 文档更新
test: 测试相关
refactor: 重构
deploy: 部署相关
perf: 性能优化
```

---

## 八、CI/CD 流水线

### 8.1 GitHub Actions

```yaml
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
        run: |
          forge coverage --report lcov
          # 解析 lcov 报告，检查覆盖率门禁
          # MonadAgentHub: 100%, AgentRegistry: 100%, WorkflowExecutor: ≥95%

      - name: Static analysis
        run: |
          forge build  # Slither 需要编译产物
          pip install slither-analyzer
          slither . --compile-force-framework foundry --fail-high --fail-medium

      - name: Check contract sizes
        run: forge build --sizes && forge build --sizes 2>&1 | tee /tmp/contract_sizes.txt
        # 断言：所有合约 < 24576 bytes (EIP-170)

      - name: Gas diff
        run: |
          git fetch origin main
          forge snapshot --diff .gas-snapshot

      - name: Invariant tests (optional)
        run: |
          # 运行 Echidna/Medusa 模糊测试（若配置）
          if [ -f echidna.yaml ]; then
            echidna . --contract MonadAgentHub --config echidna.yaml
          fi

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
| 覆盖率 | 整体行覆盖 < 95%，或任一核心合约（MonadAgentHub/AgentRegistry）< 100%，WorkflowExecutor < 95% |
| Slither | High/Medium 告警 |
| 合约大小 | 超过 24KB |
| Gas 回归 | 单函数增加 > 10% 需评审说明 |
| ESLint | 任何 error |
| TypeScript | 类型错误 |
