// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {AgentInfo} from "./IMonadAgentHub.sol";

interface IAgentRegistry {
    function VERSION() external view returns (string memory);
    function hub() external view returns (address);
    function register(address hubAddr, bytes32 workflowType, address agentOwner) external returns (uint256);
    function isOwner(uint256 agentId, address account) external view returns (bool);
    function getAgentInfo(uint256 agentId) external view returns (AgentInfo memory);
    function setHub(address hubAddr) external;
    function transferOwnership(uint256 agentId, address newOwner) external;
    function owner() external view returns (address);
}
