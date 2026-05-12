# 部署指南

## 一、部署架构

```
┌──────────────────────────────────────────────────┐
│               Monad 主网                         │
│                                                  │
│  ┌────────────────┐   ┌───────────────────────┐  │
│  │ MonadAgentHub   │   │  Workflow Executors   │  │
│  │                │   │  ├── DeFiSwapExecutor │  │
│  │                │   │  ├── DeFiLendExecutor │  │
│  └────────────────┘   │  ├── NFTExecutor      │  │
│  ┌────────────────┐   │  └── CrossChainExec   │  │
│  │ AgentRegistry  │   └───────────────────────┘  │
│  └────────────────┘                              │
└──────────────────────────────────────────────────┘
```

---

## 二、主网部署前置条件

### 2.1 必要条件

| 条件 | 状态 | 检查方法 |
|------|------|---------|
| 测试网全部测试通过 | ⬜ | `forge test` 全绿 |
| 第三方安全审计报告 | ⬜ | 2+ 家审计公司 |
| 测试网压测 ≥ 1,000 TPS | ⬜ | 执行 benchmark 脚本 |
| 多签钱包准备完成 | ⬜ | Safe{Wallet} 设置 |
| Gas 资金充值 (≥ 10 MON) | ⬜ | 从交易所提币 |
| 合约代码已冻结（不可变部署） | ⬜ | 确认 Tag 版本 |

### 2.2 安全检查清单

- [ ] 无 `selfdestruct` / `delegatecall` 到外部地址
- [ ] 无 `tx.origin` 权限检查
- [ ] 所有外部调用做了返回值检查
- [ ] 整数溢出已防护 (Solidity 0.8+)
- [ ] 重入攻击路径已排除
- [ ] 存储冲突已排除
- [ ] Owner 权限最小化
- [ ] 紧急暂停功能可用
- [ ] TimelockController 已部署，暂停/恢复延迟 ≥ 24h
- [ ] 多签部署钱包已创建（3/5 门限，硬件钱包）

### 2.3 密钥仪式（Key Ceremony）

部署密钥不得使用开发者个人地址。主网部署前必须完成以下仪式：

1. **部署多签创建**：在 Safe{Wallet} 上创建 3/5 多签钱包，签名者使用硬件钱包（Ledger/Trezor）
2. **签名者身份验证**：5 位签名者各自提供 PGP 签名证明地址所有权
3. **DEPLOYER_KEY 生成**：
   ```bash
   # 在离线机器上生成一次性部署私钥
   openssl rand -hex 32 > deployer.key
   # 计算对应地址
   cast wallet address --private-key $(cat deployer.key)
   ```
4. **Gas 资金注入**：从多签钱包向部署地址转入 ≥ 15 MON（含合约部署 + 操作 Gas）
5. **部署后密钥销毁**：
   ```bash
   shred -u deployer.key       # 安全擦除
   # Owner 权限立即移交至多签钱包
   ```
6. **部署地址绝不持有长期权限**：`transferOwnership(multisig)` 必须在部署交易的同一区块内完成（通过 Foundry script 原子化）

---

## 三、部署流程

### 3.1 阶段一：预部署准备

```bash
# 1. 确认最新版本
git tag -l
git checkout v1.0.0

# 2. 完整测试
forge test -vvvv
forge test --gas-report

# 3. 编译优化
forge build --optimize --optimizer-runs 1000000

# 4. 检查合约大小
forge build --sizes
# 确保所有合约 < 24KB (EIP-170)
```

#### Gas 价格与费用策略

| 参数 | 配置 | 说明 |
|------|------|------|
| Gas Price 策略 | EIP-1559 (type 2 transactions) | Monad 支持 EIP-1559，使用 `maxFeePerGas` + `maxPriorityFeePerGas` |
| Max Fee Per Gas | `cast gas-price --rpc-url $RPC_URL` × 1.5 | 当前网络 gas price 的 1.5 倍缓冲 |
| Priority Fee | 1 gwei（默认）/ 竞价场景可提升 | Monad 测试网交易量大时适当提高以加速 inclusion |
| 部署 Gas 预算 | ≥ 15 MON | 含合约部署 (约 5-8 MON) + 操作 Gas，建议预留 2x 余量 |
| Gas 监控 | Grafana 面板监控合约 MON 余额 + Gas 消耗速率 | 余额低于 5 MON 触发告警并自动补充 |

```bash
# 部署前查询当前 gas 价格
cast gas-price --rpc-url $MONAD_MAINNET_RPC_URL
# 示例输出: 20000000000 (20 gwei)

# 部署时使用 EIP-1559
forge script script/Deploy.s.sol:DeployMonadFlow \
  --rpc-url $MONAD_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --with-gas-price $(cast gas-price --rpc-url $MONAD_MAINNET_RPC_URL) \
  --priority-gas-price 1000000000
```

### 3.2 阶段二：主网部署

```bash
# 1. 设置环境变量
export MONAD_MAINNET_RPC_URL="https://rpc.monad.xyz"
export PRIVATE_KEY=""          # 从 HSM/冷钱包加载
export ETHERSCAN_API_KEY=""    # Monad 区块浏览器 API Key

# 2. 模拟部署（不上链）
forge script script/Deploy.s.sol:DeployMonadFlow \
  --rpc-url $MONAD_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY

# 3. 正式部署
forge script script/Deploy.s.sol:DeployMonadFlow \
  --rpc-url $MONAD_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --slow

# 4. 记录部署结果
# - MonadAgentHub 地址: 0x...
# - AgentRegistry 地址: 0x...
# - 部署 Tx Hash: 0x...
# - 部署 Gas 消耗: ...
```

### 3.3 阶段三：部署后验证

```bash
# 1. 验证合约源码
forge verify-contract \
  --rpc-url $MONAD_MAINNET_RPC_URL \
  --verifier blockscout \
  --verifier-url "https://explorer.monad.xyz/api" \
  <CONTRACT_ADDRESS> \
  MonadAgentHub

# 2. 验证合约功能
# 发送测试交易
cast send <CONTRACT_ADDRESS> \
  "registerAgent(bytes32)" \
  "0x444546495f5357415000000000000000000000000000000000000000000000" \
  --rpc-url $MONAD_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY

# 3. 检查合约状态
cast call <CONTRACT_ADDRESS> "totalAgents()" --rpc-url $MONAD_MAINNET_RPC_URL
```

### 3.4 阶段四：权限移交

```bash
# 将 Owner 权限移交至 TimelockController（已在部署脚本中原子化完成）
cast call <CONTRACT_ADDRESS> "owner()" --rpc-url $MONAD_MAINNET_RPC_URL
# 预期: <TIMELOCK_ADDRESS>

# 多签钱包通过 Safe UI 接受 TimelockController 的 admin 角色
# 操作步骤:
#   1. 在 Safe{Wallet} UI 中创建 Transaction Builder 交易
#   2. 目标合约: <TIMELOCK_ADDRESS>
#   3. 函数: acceptRole(bytes32,address)
#       - roleId: keccak256("TIMELOCK_ADMIN_ROLE")
#       - address: <MULTISIG_ADDRESS>
#   4. 发起多签 → 达到 3/5 门限 → 执行
#   5. (可选) 多签发起 revokeRole 移除 deployer 的 admin 角色
```

> **注意**：多签钱包（Safe）没有私钥，不可使用 `cast send --private-key`。所有多签操作必须通过 Safe UI 或 Safe SDK (`@safe-global/protocol-kit`) 执行。

---

## 四、部署脚本

### 4.1 Deploy.s.sol

```solidity
// scripts/Deploy.s.sol
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MonadAgentHub} from "../contracts/MonadAgentHub.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployMonadFlow is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address multisig = vm.envAddress("MULTISIG_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署 AgentRegistry
        AgentRegistry registry = new AgentRegistry();

        // 2. 部署 MonadAgentHub（owner 初始为 deployer）
        MonadAgentHub hub = new MonadAgentHub(address(registry));

        // 3. 设置 Hub → Registry 关联（一次写入，不可重复）
        registry.setHub(address(hub));

        // 4. 部署 TimelockController (24h 延迟, admin = deployer)
        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;
        TimelockController timelock = new TimelockController(
            86400,          // minDelay: 24 hours
            proposers,
            executors,
            deployer        // admin: deployer（EOA），部署后移交至多签
        );

        // 5. 移交 Hub Owner 至 Timelock
        hub.transferOwnership(address(timelock));

        // 6. 移交 Timelock admin 至多签（部署者保留 admin 直至多签完成 setup）
        timelock.grantRole(timelock.DEFAULT_ADMIN_ROLE(), multisig);
        //    ⚠️ 勿立即 revoke deployer 的 admin 角色。
        //    多签 wallet 在 Safe UI 中完成 accept + grantRole 后，
        //    由多签自行调用 revokeRole 移除 deployer admin。

        vm.stopBroadcast();

        console.log("Deployer:", deployer);
        console.log("AgentRegistry:", address(registry));
        console.log("MonadAgentHub:", address(hub));
        console.log("TimelockController:", address(timelock));
        console.log("Hub Owner (post-deploy):", hub.owner()); // 应为 timelock 地址
    }
}
}
```

### 4.2 多签钱包部署

如果使用 Gnosis Safe 多签部署：

```bash
# 1. 生成部署 calldata
forge script script/Deploy.s.sol:DeployMonadFlow \
  --rpc-url $MONAD_MAINNET_RPC_URL \
  --sig ""

# 2. 在 Safe UI 中创建交易，粘贴 calldata
# 3. 多签签名确认
# 4. 执行交易
```

---

## 五、部署地址记录表

| 合约 | 地址 | 部署 Tx | 部署时间 | 区块号 |
|------|------|---------|---------|--------|
| MonadAgentHub | `0x...` | `0x...` | `--` | `--` |
| AgentRegistry | `0x...` | `0x...` | `--` | `--` |
| DeFiSwapExecutor | `0x...` | `0x...` | `--` | `--` |
| DeFiLendExecutor | `0x...` | `0x...` | `--` | `--` |
| NFTExecutor | `0x...` | `0x...` | `--` | `--` |
| CrossChainExecutor | `0x...` | `0x...` | `--` | `--` |

---

## 六、灰度发布策略

### 6.1 分阶段上线

```
Phase 1: 白名单 Agent 接入
  ├── 仅允许 5-10 个已验证 Agent 注册
  ├── 监控 TPS、延迟、失败率
  └── 持续时间: 48小时

Phase 2: 扩大接入
  ├── 开放至 100 个 Agent
  ├── 压力测试高并发场景
  └── 持续时间: 1周

Phase 3: 公开访问
  ├── 移除白名单限制
  ├── 开放无许可 Agent 注册
  └── 持续运行
```

### 6.2 监控指标

| 指标 | 告警阈值 | 处理动作 |
|------|---------|---------|
| TPS < 500 | 警告 | 检查网络状态 |
| 失败率 > 5% | 紧急 | 暂停新 Agent，排查原因 |
| 确认延迟 > 3s | 警告 | 检查 RPC 节点 |
| 合约余额 < 1 MON | 通知 | 补充 Gas |

---

## 七、回滚与应急

### 7.1 紧急暂停（需配合 TimelockController）

```solidity
// MonadAgentHub.sol
bool public paused;
TimelockController public timelock;

modifier whenNotPaused() {
    require(!paused, "Paused");
    _;
}

function pause() external onlyOwner {
    paused = true;
    emit Paused(msg.sender);
}

function unpause() external onlyOwner {
    paused = false;
    emit Unpaused(msg.sender);
}
```

> **生产要求**：Owner 必须是 TimelockController 合约地址，而非 EOA。
> `pause()` 和 `unpause()` 通过 Timelock 调度执行，延迟 ≥ 24 小时。
> 部署时按以下顺序原子化完成：
> 1. 部署 MonadAgentHub
> 2. 部署 TimelockController（minDelay=86400, proposers=[], executors=[multisig]）
> 3. `hub.transferOwnership(address(timelock))`
> 4. `timelock` 内部配置 proposer 为多签地址

### 7.2 回滚步骤

1. 调用 `pause()` 暂停合约
2. 排查问题根因
3. 修复合约或部署新版本
4. 灰度放开 `unpause()`

---

## 八、运维联系人

| 角色 | 联系方式 | 职责 |
|------|---------|------|
| 主网部署负责人 | {{PRIMARY_DEPLOYER}} | 执行部署流程 |
| 安全审计对接人 | {{AUDIT_LEAD}} | 审计报告跟进 |
| 7x24 值班 | {{ONCALL_CHANNEL}} | 监控紧急响应 |
| 开发团队 | {{DEV_TEAM_ALIAS}} | 问题修复 |

> 部署前必须全部替换为真实信息。

---

## 九、合约注册中心

### 9.1 主方案：链下配置（Phase 1）

所有已部署合约地址维护在 `deployments.json` 中，通过 CI 流水线自动更新：

```json
{
  "network": "monad-mainnet",
  "contracts": {
    "MonadAgentHub": {
      "address": "0x...",
      "deployTx": "0x...",
      "deployBlock": 1234567,
      "version": "1.0.0"
    },
    "AgentRegistry": {
      "address": "0x...",
      "deployTx": "0x...",
      "deployBlock": 1234567,
      "version": "1.0.0"
    }
  }
}
```

前端/Agent SDK 启动时加载此文件获取合约地址。在 CI 中：

```bash
forge script script/Deploy.s.sol --broadcast --json | jq '.returns' > deployments.json
git add deployments.json && git commit -m "deploy: update contract addresses"
```

### 9.2 备用方案：链上 ContractRegistry（可选）

如果下游服务需要去中心化地址发现，可部署轻量级链上注册合约：

```solidity
contract ContractRegistry {
    mapping(bytes32 => address) public registry;
    function set(string calldata name, address addr) external onlyOwner;
    function get(string calldata name) external view returns (address);
}
```

### 9.3 未来方案：ENS

Monad 主网上线后若 ENS 部署，可将合约地址注册到 ENS 子域名供自动发现：

| 合约 | ENS 域名 |
|------|---------|
| MonadAgentHub | `hub.monadflow.eth` |
| AgentRegistry | `registry.monadflow.eth` |

合约升级时更新 ENS 记录指向新地址，旧合约保留只读访问。

---

## 十、版本迁移步骤

当需要升级合约时，遵循 Immutable + 迁移模式：

```bash
# 1. 部署新版本 MonadAgentHub V2
forge script script/Deploy.s.sol:DeployMonadFlowV2 \
  --rpc-url $MONAD_MAINNET_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --verify

# 2. 旧版合约进入 deprecated 状态
cast send <OLD_HUB> "deprecate()" \
  --rpc-url $MONAD_MAINNET_RPC_URL \
  --private-key $OWNER_KEY

# 3. Agent Owner 迁移 Agent 到新合约
cast send <NEW_HUB> "migrateAgent(uint256)" <AGENT_ID> \
  --rpc-url $MONAD_MAINNET_RPC_URL \
  --private-key $AGENT_OWNER_KEY

# 4. 更新 ENS 记录
# hub.monadflow.eth → <NEW_HUB_ADDRESS>
```

### 迁移验证

| 检查项 | 方法 |
|--------|------|
| 新合约部署成功 | `cast codesize <NEW_HUB>` > 0 |
| 旧合约已弃用 | `cast call <OLD_HUB> "deprecated()"` → true |
| Agent 迁移成功 | 查询新合约中 agent 状态 |
| 链下索引更新 | 确认 Event Listener 接收到 `AgentMigrated` 事件 |
