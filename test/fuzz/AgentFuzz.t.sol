// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MonadAgentHub} from "../../contracts/MonadAgentHub.sol";
import {AgentRegistry} from "../../contracts/AgentRegistry.sol";
import {TaskData} from "../../contracts/interfaces/IMonadAgentHub.sol";

contract AgentHubHandler is Test {
    MonadAgentHub public hub;
    AgentRegistry public registry;

    uint256[] public registeredAgentsList;
    mapping(uint256 => uint256) public agentNonces;
    mapping(uint256 => address) public agentOwners;

    constructor() {
        registry = new AgentRegistry(address(this));
        hub = new MonadAgentHub(address(registry));
        registry.setHub(address(hub));
    }

    function numRegisteredAgents() external view returns (uint256) {
        return registeredAgentsList.length;
    }

    function getRegisteredAgent(uint256 index) external view returns (uint256) {
        return registeredAgentsList[index];
    }

    function getAgentNonce(uint256 agentId) external view returns (uint256) {
        return agentNonces[agentId];
    }

    function registerAgent(uint256 userSeed) public returns (uint256) {
        address user = _addr(userSeed);
        vm.prank(user);
        uint256 agentId = hub.registerAgent(bytes32("FUZZ"));
        registeredAgentsList.push(agentId);
        agentOwners[agentId] = user;
        return agentId;
    }

    function executeAgentTask(uint256 agentId, bytes calldata payload) public {
        if (agentOwners[agentId] == address(0)) return;

        uint256 expectedNonce = agentNonces[agentId] + 1;
        address ownerAddr = agentOwners[agentId];

        vm.prank(ownerAddr);
        TaskData memory taskData = TaskData({version: 1, deadline: 0, payload: payload});

        try hub.executeAgentTask(agentId, expectedNonce, taskData) returns (bool success) {
            assertTrue(success);
            agentNonces[agentId] = expectedNonce;
        } catch {
            // Skip expected reverts
        }
    }

    function deactivateAgent(uint256 agentId) public {
        if (agentOwners[agentId] == address(0)) return;

        vm.prank(agentOwners[agentId]);
        try hub.deactivateAgent(agentId) {
            // Success
        } catch {
            // Agent may already be inactive
        }
    }

    function _addr(uint256 seed) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(seed)))));
    }
}

contract AgentFuzz is Test {
    AgentHubHandler public handler;

    function setUp() public {
        handler = new AgentHubHandler();
        excludeContract(address(handler.registry()));
        excludeContract(address(handler.hub()));
    }

    function invariantAgentNonceMonotonic() public view {
        uint256 count = handler.numRegisteredAgents();
        for (uint256 i = 0; i < count; i++) {
            uint256 agentId = handler.getRegisteredAgent(i);
            (,,,, uint256 chainNonce) = handler.hub().agents(agentId);
            assertEq(chainNonce, handler.getAgentNonce(agentId));
        }
    }
}
