// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

struct AgentInfo {
    uint256 agentId;
    address owner;
    bool isActive;
    bytes32 workflowType;
    uint256 nonce;
}

struct TaskData {
    uint8 version;
    uint256 deadline;
    bytes payload;
}

interface IMonadAgentHub {
    function VERSION() external view returns (string memory);
    function paused() external view returns (bool);
    function deprecated() external view returns (bool);
    function registerAgent(bytes32 workflowType) external returns (uint256);
    function executeAgentTask(uint256 agentId, uint256 nonce, TaskData calldata taskData) external returns (bool);
    function batchExecuteTasks(uint256[] calldata agentIds, uint256[] calldata nonces, TaskData[] calldata tasksData) external returns (bool[] memory);
    function deactivateAgent(uint256 agentId) external;
    function deprecate() external;
    function migrateAgent(uint256 oldAgentId) external returns (uint256 newAgentId);
    function pause() external;
    function unpause() external;
    function getAgentState(uint256 agentId, bytes32 key) external view returns (uint256);
    function transferOwnership(address newOwner) external;
    function acceptOwnership() external;
    function owner() external view returns (address);
}
