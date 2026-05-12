# 智能合约规范

## 一、合约总览

| 合约 | 描述 | 代码行数 |
|------|------|---------|
| `MonadAgentHub.sol` | Agent 核心调度合约 | ~150 |
| `AgentRegistry.sol` | Agent 注册与生命周期管理 | ~80 |
| `WorkflowExecutor.sol` | 工作流执行引擎（抽象基类） | ~60 |
| `adapters/DeFiAdapter.sol` | DeFi 协议适配器接口 | ~40 |
| `adapters/CrossChainAdapter.sol` | 跨链桥适配器接口 | ~40 |

---

## 二、MonadAgentHub

### 2.1 合约说明

Agent 核心调度合约，是所有 Agent 交易的入口。通过 **agentId 索引的独立存储槽** 实现 Monad 并行 EVM 的原生并行执行。

### 2.2 状态变量

```solidity
// Agent 结构体 - 每个实例拥有独立存储槽
struct Agent {
    uint256 agentId;      // Agent 唯一标识
    address owner;        // Agent 拥有者地址
    bool isActive;        // 激活状态
    bytes32 workflowType; // 工作流类型标识
    uint256 nonce;        // 执行 nonce，单调递增，防重放
    // agentState 使用独立 mapping → 不同 agentId 无存储冲突
}

// agentId → Agent 映射（独立存储槽，Monad 并行安全）
mapping(uint256 => Agent) public agents;

// agentId 自增计数器（仅 registerAgent 时写入；链下应通过 Events 统计 Agent 总数，
// 链上不使用此值做业务逻辑判断，避免引入全局写冲突瓶颈）
uint256 private _nextAgentId;

// 合约版本号
string public constant VERSION = "1.0.0";

// 紧急暂停标志
bool public paused;
```

### 2.3 自定义错误

```solidity
error NotAgentOwner(uint256 agentId, address caller, address owner);
error AgentInactive(uint256 agentId);
error AgentNotFound(uint256 agentId);
error UnsupportedTaskVersion(uint8 version);
error TaskExpired(uint256 deadline, uint256 currentTime);
error BatchLengthMismatch(uint256 agents, uint256 tasks);
error InvalidNonce(uint256 agentId, uint256 expected, uint256 actual);
```

### 2.4 核心函数

#### registerAgent()

```solidity
function registerAgent(bytes32 workflowType) external returns (uint256 agentId)
```

- **描述**：注册新 Agent，分配独立 ID 和存储槽
- **访问控制**：公开调用
- **返回**：新分配的 agentId
- **事件**：`AgentRegistered(uint256 indexed agentId, address indexed owner, bytes32 workflowType)`

#### executeAgentTask()

```solidity
struct TaskData {
    uint8 version;       // 数据格式版本，初始为 1
    uint256 deadline;    // 任务有效期（unix timestamp），0 表示永不过期
    bytes payload;       // 工作流特定数据
}

function executeAgentTask(
    uint256 agentId,
    uint256 nonce,
    TaskData calldata taskData
) external returns (bool success)
```

- **描述**：执行单个 Agent 任务（**Monad 并行关键入口**）
- **访问控制**：仅 Agent Owner 可调用
- **参数**：
  - `agentId`：Agent 标识
  - `nonce`：必须 == agent.nonce + 1，防重放
  - `taskData`：结构化任务数据，含 version + deadline + payload
- **返回**：执行是否成功
- **事件**：`AgentExecuted(uint256 indexed agentId, uint8 indexed version, bytes32 indexed executionId, bytes taskData, uint256 nonce, uint256 timestamp, bool success)`
- **并行说明**：不同 agentId 的调用访问不同存储槽 → Monad 自动并行
- **校验逻辑**：
  ```solidity
  require(taskData.version == CURRENT_VERSION, "Unsupported task version");
  require(taskData.deadline == 0 || block.timestamp <= taskData.deadline, "Task expired");
  ```

#### batchExecuteTasks()

```solidity
function batchExecuteTasks(
    uint256[] calldata agentIds,
    uint256[] calldata nonces,
    TaskData[] calldata tasksData
) external returns (bool[] memory successes)
```

- **描述**：批量执行多个 Agent 任务
- **访问控制**：
  - 当前（Phase 1）：调用者必须同时是所有 agent 的 owner（定位为单用户多 Agent 批量优化）
  - Phase 2 / meta-transaction：支持 `executeAgentTaskBySig`，Relayer 可通过签名验证代多个 Agent Owner 提交
- **并行说明**：即使同一交易内，不同 agentId 仍访问独立存储 → 并行优化
- **错误**：`BatchLengthMismatch` 当数组长度不一致时触发

#### deactivateAgent()

```solidity
function deactivateAgent(uint256 agentId) external
```

- **描述**：停用 Agent
- **访问控制**：仅 Agent Owner

#### getAgentState()

```solidity
function getAgentState(uint256 agentId, bytes32 key) external view returns (uint256)
```

- **描述**：查询 Agent 内部状态

#### transferOwnership()

```solidity
function transferOwnership(address newOwner) external onlyOwner
```

- **描述**：发起所有权转移，使用 OpenZeppelin `Ownable2Step`

#### acceptOwnership()

```solidity
function acceptOwnership() external
```

- **描述**：新 owner 接受所有权转移，完成双步确认

#### deprecate()

```solidity
function deprecate() external
```

- **描述**：将合约标记为弃用状态（保留只读查询，拒绝新任务提交）
- **访问控制**：仅 Owner（TimelockController）
- **事件**：`ContractDeprecated(string version, uint256 timestamp)`

#### migrateAgent()

```solidity
function migrateAgent(uint256 oldAgentId) external returns (uint256 newAgentId)
```

- **描述**：Agent Owner 在新版合约上重新注册，迁移 Agent 状态（旧合约必须已 deprecate）
- **访问控制**：旧 Agent Owner
- **返回**：新分配的 agentId（与旧 ID 不同）
- **事件**：`AgentMigrated(uint256 indexed oldAgentId, uint256 indexed newAgentId, address indexed owner, uint256 timestamp)`

#### pause()

```solidity
function pause() external onlyOwner
```

- **描述**：紧急暂停所有 Agent 写操作；必须通过 TimelockController 调度执行
- **访问控制**：仅 Owner（TimelockController），延迟 ≥ 24h
- **事件**：`Paused(address indexed initiator, uint256 timestamp)`

#### unpause()

```solidity
function unpause() external onlyOwner
```

- **描述**：恢复所有 Agent 写操作；必须通过 TimelockController 调度执行
- **访问控制**：仅 Owner（TimelockController），延迟 ≥ 24h
- **事件**：`Unpaused(address indexed initiator, uint256 timestamp)`

> **注意**：`pause()`/`unpause()` 需配合 `whenNotPaused` modifier 使用。此 modifier 仅校验于 `executeAgentTask` 和 `batchExecuteTasks` 入口，不阻止只读查询。

---

## 三、AgentRegistry

### 3.1 合约说明

管理 Agent 的注册、权限、元数据。与 MonadAgentHub 解耦，支持独立升级。

### 3.2 函数

```solidity
function register(address hub, bytes32 workflowType) external returns (uint256)
function isOwner(uint256 agentId, address account) external view returns (bool)
function getAgentInfo(uint256 agentId) external view returns (AgentInfo memory)
function setHub(address hub) external
function transferOwnership(uint256 agentId, address newOwner) external
```

#### setHub()

```solidity
function setHub(address hub) external
```

- **描述**：设置关联的 MonadAgentHub 地址（部署时调用一次，不可重复设置）
- **访问控制**：仅 Registry Owner（部署后移交至 Timelock）

---

## 四、WorkflowExecutor（抽象合约）

### 4.1 合约说明

定义 Agent 工作流的执行接口，具体业务逻辑通过继承实现。

### 4.2 接口

```solidity
abstract contract WorkflowExecutor {
    function execute(
        uint256 agentId,
        bytes calldata taskData
    ) external virtual returns (bool);

    function validateTask(
        uint256 agentId,
        bytes calldata taskData
    ) external virtual view returns (bool);
}
```

### 4.3 内置工作流类型

| 类型标识 | 描述 | 实现合约 |
|---------|------|---------|
| `bytes32("DEFI_SWAP")` | DEX 兑换工作流 | `DeFiSwapExecutor` |
| `bytes32("DEFI_LEND")` | 借贷工作流 | `DeFiLendExecutor` |
| `bytes32("NFT_MINT")` | NFT 铸造工作流 | `NFTMintExecutor` |
| `bytes32("NFT_TRADE")` | NFT 交易工作流 | `NFTTradeExecutor` |
| `bytes32("CROSS_CHAIN")` | 跨链桥接工作流 | `CrossChainExecutor` |
| `bytes32("SOCIAL_NOTIFY")` | 社交通知工作流 | `SocialNotifyExecutor` |
| `bytes32("GAME_NPC")` | 游戏 NPC 工作流 | `GameNPCExecutor` |
| `bytes32("CUSTOM")` | 自定义工作流 | 用户自定义 |

---

## 五、事件规范

### 5.1 AgentRegistered

```solidity
event AgentRegistered(
    uint256 indexed agentId,
    address indexed owner,
    bytes32 workflowType,
    uint8 version,
    uint256 timestamp
);
```

### 5.2 AgentExecuted

```solidity
event AgentExecuted(
    uint256 indexed agentId,
    uint8 indexed version,
    bytes32 indexed executionId,  // keccak256(agentId, nonce, block.number)
    bytes taskData,
    uint256 nonce,
    uint256 timestamp,
    bool success
);
```

`executionId` 用于链下 Event Listener 的去重幂等处理。

### 5.3 AgentDeactivated

```solidity
event AgentDeactivated(
    uint256 indexed agentId,
    uint8 version,
    uint256 timestamp
);
```

### 5.4 WorkflowCompleted

```solidity
event WorkflowCompleted(
    uint256 indexed agentId,
    bytes32 indexed workflowType,
    uint8 version,
    bytes result,
    uint256 gasUsed
);
```

### 5.5 ContractDeprecated

```solidity
event ContractDeprecated(
    string version,
    uint8 indexed versionMajor,
    uint256 timestamp
);
```

### 5.6 AgentMigrated

```solidity
event AgentMigrated(
    uint256 indexed oldAgentId,
    uint256 indexed newAgentId,
    address indexed owner,
    uint8 version,
    uint256 timestamp
);
```

### 5.7 Paused / Unpaused

```solidity
event Paused(address indexed initiator, uint8 version, uint256 timestamp);
event Unpaused(address indexed initiator, uint8 version, uint256 timestamp);
```

---

## 六、Gas 优化策略

| 策略 | 实现 |
|------|------|
| 结构化 taskData 用 calldata 传递 | 避免 ABI decode 重复开销，struct 展开由编译器优化 |
| 使用 `bytes calldata` 代替 `bytes memory` | 减少内存复制，节省 200-500 gas |
| `unchecked` 块计数累加 | 在安全的计数器中避免溢出检查 |
| 事件参数最小化 | 仅索引必要字段（agentId、timestamp） |
| 存储打包 | 将相关 `uint` 变量合并到同一存储槽 |
| 热/冷存储分离 | 频繁访问的数据优先存放在低索引槽位 |

---

## 七、安全注意事项

1. **仅 Owner 可执行**：`executeAgentTask` 通过 `require(agent.owner == msg.sender)` 控制
2. **无代理模式**：核心合约采用不可变部署，不使用 `delegatecall`，升级通过部署新版本 + Agent 迁移实现
3. **无全局重入锁**：依赖独立存储槽设计保证安全，不引入串行化开销
4. **整数溢出保护**：Solidity ^0.8.20 默认开启溢出检查
5. **事件索引**：关键字段使用 `indexed`，便于链下 Agent 高效过滤
6. **紧急暂停**：Owner 可调用 `pause()`/`unpause()`。生产环境必须配合 OpenZeppelin **TimelockController**，暂停/恢复操作延迟 24 小时生效，给社区反应窗口
7. **Meta-Transaction（Phase 2）**：`executeAgentTaskBySig` 支持签名者与 Gas 支付者分离，签名私钥可存放于 KMS 而无需持有 MON 余额。Phase 1 暂不实现，Phase 2 主网上线前必须完成

---

## 八、工作流安全分级

### 8.1 安全分级表

| 级别 | 条件 | 防护要求 | 示例工作流 |
|------|------|---------|-----------|
| L0 | 纯计算，无外部调用 | 独立存储槽 | SOCIAL_NOTIFY, CUSTOM |
| L1 | 外部只读调用 | 独立存储槽 + 调用结果校验 | GAME_NPC |
| L2 | 外部写调用（单一协议）| 独立存储槽 + ReentrancyGuard + CEI | DEFI_SWAP, DEFI_LEND |
| L3 | 外部写调用（多协议组合）| L2 全部 + 完整性检查 + 滑点保护 | 批量套利工作流 |

### 8.2 L2+ 工作流的 ReentrancyGuard 使用

仅包裹外部调用片段，不锁整个 execute 函数，以最小化对并行执行的影响：

```solidity
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
```

### 8.3 重入分析要求

每个 Workflow Executor 必须附带重入分析文档，明确：
- 调用了哪些外部合约
- 是否存在回调路径到本合约
- 防护措施及验证方式

---

## 九、接口 ID（ERC-165）

```solidity
interface IMonadAgentHub {
    function VERSION() external view returns (string memory);
    function paused() external view returns (bool);
    function registerAgent(bytes32 workflowType) external returns (uint256);
    function executeAgentTask(uint256 agentId, uint256 nonce, TaskData calldata taskData) external returns (bool);
    function batchExecuteTasks(uint256[] calldata agentIds, uint256[] calldata nonces, TaskData[] calldata tasksData) external returns (bool[] memory);
    function executeAgentTaskBySig(uint256 agentId, uint256 nonce, TaskData calldata taskData, bytes calldata signature) external returns (bool); // Phase 2
    function deactivateAgent(uint256 agentId) external;
    function deprecate() external;
    function migrateAgent(uint256 oldAgentId) external returns (uint256 newAgentId);
    function pause() external;
    function unpause() external;
    function getAgentState(uint256 agentId, bytes32 key) external view returns (uint256);
    function transferOwnership(address newOwner) external;
    function acceptOwnership() external;
}

interface IAgentRegistry {
    function VERSION() external view returns (string memory);
    function register(address hub, bytes32 workflowType) external returns (uint256);
    function isOwner(uint256 agentId, address account) external view returns (bool);
    function getAgentInfo(uint256 agentId) external view returns (AgentInfo memory);
    function setHub(address hub) external;
    function transferOwnership(uint256 agentId, address newOwner) external;
}
```
