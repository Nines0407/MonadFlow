// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AgentInfo} from "./interfaces/IMonadAgentHub.sol";
import {IAgentRegistry} from "./interfaces/IAgentRegistry.sol";

contract AgentRegistry is IAgentRegistry, Ownable2Step {
    string public constant VERSION = "1.0.0";

    address public hub;
    bool private _hubSet;

    function owner() public view override(IAgentRegistry, Ownable) returns (address) {
        return Ownable.owner();
    }

    struct AgentRecord {
        uint256 agentId;
        address owner;
        bool isActive;
        bytes32 workflowType;
        uint256 nonce;
    }

    mapping(uint256 => AgentRecord) private _agents;
    uint256 private _registeredCount;

    uint256[50] private __storageGap;

    error HubAlreadySet(address currentHub);
    error HubNotSet();
    error AgentNotRegistered(uint256 agentId);
    error NotAgentOwner(uint256 agentId, address caller, address owner);
    error UnauthorizedHub(address caller, address expectedHub);

    event AgentRecorded(
        uint256 indexed agentId,
        address indexed owner,
        bytes32 workflowType,
        uint8 version,
        uint256 timestamp
    );

    event AgentOwnershipTransferred(
        uint256 indexed agentId,
        address indexed previousOwner,
        address indexed newOwner,
        uint8 version,
        uint256 timestamp
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setHub(address hubAddr) external onlyOwner {
        if (_hubSet) revert HubAlreadySet(hub);
        hub = hubAddr;
        _hubSet = true;
    }

    modifier onlyHub() {
        if (!_hubSet) revert HubNotSet();
        if (msg.sender != hub) revert UnauthorizedHub(msg.sender, hub);
        _;
    }

    function register(
        address, /* hubAddr */
        bytes32 workflowType,
        address agentOwner
    ) external onlyHub returns (uint256) {
        uint256 agentId = ++_registeredCount;
        _agents[agentId] = AgentRecord({
            agentId: agentId,
            owner: agentOwner,
            isActive: true,
            workflowType: workflowType,
            nonce: 0
        });

        emit AgentRecorded(agentId, agentOwner, workflowType, 1, block.timestamp);
        return agentId;
    }

    function isOwner(
        uint256 agentId,
        address account
    ) external view returns (bool) {
        AgentRecord storage record = _agents[agentId];
        if (record.agentId == 0) revert AgentNotRegistered(agentId);
        return record.owner == account;
    }

    function getAgentInfo(
        uint256 agentId
    ) external view returns (AgentInfo memory) {
        AgentRecord storage record = _agents[agentId];
        if (record.agentId == 0) revert AgentNotRegistered(agentId);

        return AgentInfo({
            agentId: record.agentId,
            owner: record.owner,
            isActive: record.isActive,
            workflowType: record.workflowType,
            nonce: record.nonce
        });
    }

    function transferOwnership(
        uint256 agentId,
        address newOwner
    ) external {
        AgentRecord storage record = _agents[agentId];
        if (record.agentId == 0) revert AgentNotRegistered(agentId);
        if (record.owner != msg.sender) revert NotAgentOwner(agentId, msg.sender, record.owner);

        address previousOwner = record.owner;
        record.owner = newOwner;

        emit AgentOwnershipTransferred(agentId, previousOwner, newOwner, 1, block.timestamp);
    }
}
