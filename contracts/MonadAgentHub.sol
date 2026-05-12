// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TaskData} from "./interfaces/IMonadAgentHub.sol";
import {IAgentRegistry} from "./interfaces/IAgentRegistry.sol";

contract MonadAgentHub is Ownable2Step {
    string public constant VERSION = "1.0.0";

    uint8 public constant CURRENT_TASK_VERSION = 1;

    struct Agent {
        uint256 agentId;
        address owner;
        bool isActive;
        bytes32 workflowType;
        uint256 nonce;
    }

    mapping(uint256 => Agent) public agents;
    uint256 private _nextAgentId;
    bool public paused;
    bool public deprecated;
    IAgentRegistry public immutable registry;

    uint256[50] private __storageGap;

    error NotAgentOwner(uint256 agentId, address caller, address owner);
    error AgentInactive(uint256 agentId);
    error AgentNotFound(uint256 agentId);
    error UnsupportedTaskVersion(uint8 version);
    error TaskExpired(uint256 deadline, uint256 currentTime);
    error BatchLengthMismatch(uint256 agents, uint256 tasks);
    error InvalidNonce(uint256 agentId, uint256 expected, uint256 actual);
    error ContractIsDeprecated();
    error ContractIsPaused();
    error MigrationRequiresDeprecated();

    event AgentRegistered(
        uint256 indexed agentId,
        address indexed owner,
        bytes32 workflowType,
        uint8 version,
        uint256 timestamp
    );

    event AgentExecuted(
        uint256 indexed agentId,
        uint8 indexed version,
        bytes32 indexed executionId,
        bytes taskData,
        uint256 nonce,
        uint256 timestamp,
        bool success
    );

    event AgentDeactivated(
        uint256 indexed agentId,
        uint8 version,
        uint256 timestamp
    );

    event ContractDeprecated(
        string version,
        uint8 indexed versionMajor,
        uint256 timestamp
    );

    event AgentMigrated(
        uint256 indexed oldAgentId,
        uint256 indexed newAgentId,
        address indexed owner,
        uint8 version,
        uint256 timestamp
    );

    event Paused(address indexed initiator, uint8 version, uint256 timestamp);
    event Unpaused(address indexed initiator, uint8 version, uint256 timestamp);

    constructor(address _registry) Ownable(msg.sender) {
        registry = IAgentRegistry(_registry);
    }

    modifier whenNotPaused() {
        if (paused) revert ContractIsPaused();
        _;
    }

    modifier whenNotDeprecated() {
        if (deprecated) revert ContractIsDeprecated();
        _;
    }

    function registerAgent(
        bytes32 workflowType
    ) external whenNotPaused whenNotDeprecated returns (uint256 agentId) {
        agentId = ++_nextAgentId;
        agents[agentId] = Agent({
            agentId: agentId,
            owner: msg.sender,
            isActive: true,
            workflowType: workflowType,
            nonce: 0
        });

        if (address(registry) != address(0)) {
            registry.register(address(this), workflowType, msg.sender);
        }

        emit AgentRegistered(agentId, msg.sender, workflowType, 1, block.timestamp);
    }

    function executeAgentTask(
        uint256 agentId,
        uint256 nonce,
        TaskData calldata taskData
    ) external whenNotPaused whenNotDeprecated returns (bool success) {
        Agent storage agent = agents[agentId];
        if (agent.agentId == 0) revert AgentNotFound(agentId);
        if (agent.owner != msg.sender) revert NotAgentOwner(agentId, msg.sender, agent.owner);
        if (!agent.isActive) revert AgentInactive(agentId);
        if (taskData.version != CURRENT_TASK_VERSION) revert UnsupportedTaskVersion(taskData.version);
        if (taskData.deadline != 0 && block.timestamp > taskData.deadline) {
            revert TaskExpired(taskData.deadline, block.timestamp);
        }

        uint256 expectedNonce = agent.nonce + 1;
        if (nonce != expectedNonce) revert InvalidNonce(agentId, expectedNonce, nonce);

        agent.nonce = nonce;

        bytes32 executionId = keccak256(abi.encodePacked(agentId, nonce, block.number));

        success = true;
        emit AgentExecuted(agentId, 1, executionId, taskData.payload, nonce, block.timestamp, success);
    }

    function batchExecuteTasks(
        uint256[] calldata agentIds,
        uint256[] calldata nonces,
        TaskData[] calldata tasksData
    ) external whenNotPaused whenNotDeprecated returns (bool[] memory successes) {
        uint256 len = agentIds.length;
        if (len != nonces.length || len != tasksData.length) {
            revert BatchLengthMismatch(len, nonces.length);
        }

        successes = new bool[](len);
        for (uint256 i = 0; i < len; i++) {
            Agent storage agent = agents[agentIds[i]];
            if (agent.agentId == 0) revert AgentNotFound(agentIds[i]);
            if (agent.owner != msg.sender) {
                revert NotAgentOwner(agentIds[i], msg.sender, agent.owner);
            }
            if (!agent.isActive) revert AgentInactive(agentIds[i]);
            if (tasksData[i].version != CURRENT_TASK_VERSION) {
                revert UnsupportedTaskVersion(tasksData[i].version);
            }
            if (tasksData[i].deadline != 0 && block.timestamp > tasksData[i].deadline) {
                revert TaskExpired(tasksData[i].deadline, block.timestamp);
            }

            uint256 expectedNonce = agent.nonce + 1;
            if (nonces[i] != expectedNonce) {
                revert InvalidNonce(agentIds[i], expectedNonce, nonces[i]);
            }

            agent.nonce = nonces[i];

            bytes32 executionId = keccak256(
                abi.encodePacked(agentIds[i], nonces[i], block.number)
            );

            successes[i] = true;
            emit AgentExecuted(
                agentIds[i],
                1,
                executionId,
                tasksData[i].payload,
                nonces[i],
                block.timestamp,
                true
            );
        }
    }

    function deactivateAgent(uint256 agentId) external whenNotPaused {
        Agent storage agent = agents[agentId];
        if (agent.agentId == 0) revert AgentNotFound(agentId);
        if (agent.owner != msg.sender) revert NotAgentOwner(agentId, msg.sender, agent.owner);

        agent.isActive = false;
        emit AgentDeactivated(agentId, 1, block.timestamp);
    }

    function getAgentState(uint256 agentId, bytes32 key) external view returns (uint256) {
        Agent storage agent = agents[agentId];
        if (agent.agentId == 0) revert AgentNotFound(agentId);

        if (key == bytes32("nonce")) return agent.nonce;
        if (key == bytes32("isActive")) return agent.isActive ? 1 : 0;
        return 0;
    }

    function deprecate() external onlyOwner {
        deprecated = true;
        emit ContractDeprecated(VERSION, 1, block.timestamp);
    }

    function migrateAgent(uint256 oldAgentId) external returns (uint256 newAgentId) {
        if (!deprecated) revert MigrationRequiresDeprecated();

        Agent storage agent = agents[oldAgentId];
        if (agent.agentId == 0) revert AgentNotFound(oldAgentId);
        if (agent.owner != msg.sender) revert NotAgentOwner(oldAgentId, msg.sender, agent.owner);

        newAgentId = ++_nextAgentId;
        agents[newAgentId] = Agent({
            agentId: newAgentId,
            owner: msg.sender,
            isActive: agent.isActive,
            workflowType: agent.workflowType,
            nonce: agent.nonce
        });

        emit AgentMigrated(oldAgentId, newAgentId, msg.sender, 1, block.timestamp);
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender, 1, block.timestamp);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender, 1, block.timestamp);
    }
}
