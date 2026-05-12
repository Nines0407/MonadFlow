// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MonadAgentHub} from "../contracts/MonadAgentHub.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {TaskData} from "../contracts/interfaces/IMonadAgentHub.sol";

contract ParallelTest is Test {
    MonadAgentHub public hub;
    AgentRegistry public registry;

    address[] public owners;
    uint256[] public agentIds;

    uint256 constant AGENT_COUNT = 100;

    event AgentExecuted(
        uint256 indexed agentId,
        uint8 indexed version,
        bytes32 indexed executionId,
        bytes taskData,
        uint256 nonce,
        uint256 timestamp,
        bool success
    );

    function setUp() public {
        vm.startPrank(address(this));
        registry = new AgentRegistry(address(this));
        hub = new MonadAgentHub(address(registry));
        registry.setHub(address(hub));
        vm.stopPrank();

        owners = new address[](AGENT_COUNT);
        agentIds = new uint256[](AGENT_COUNT);

        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            owners[i] = makeAddr(string(abi.encodePacked("agent_owner_", i)));
            vm.prank(owners[i]);
            agentIds[i] = hub.registerAgent(bytes32("TEST"));
        }
    }

    function _defaultTaskData() internal pure returns (TaskData memory) {
        return TaskData({version: 1, deadline: 0, payload: hex""});
    }

    function _taskDataWithId(uint256 id) internal pure returns (TaskData memory) {
        return TaskData({version: 1, deadline: 0, payload: abi.encode(id)});
    }

    function testMassiveParallelExecution() public {
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            vm.prank(owners[i]);
            bool success = hub.executeAgentTask(agentIds[i], 1, _taskDataWithId(i));
            assertTrue(success);
        }

        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            (,, bool isActive,, uint256 nonce) = hub.agents(agentIds[i]);
            assertTrue(isActive);
            assertEq(nonce, 1);
        }
    }

    function testParallelMultipleNonces() public {
        for (uint256 round = 0; round < 5; round++) {
            for (uint256 i = 0; i < AGENT_COUNT; i++) {
                vm.prank(owners[i]);
                uint256 expectedNonce = round + 1;
                bool success = hub.executeAgentTask(
                    agentIds[i],
                    expectedNonce,
                    _taskDataWithId(i * 100 + round)
                );
                assertTrue(success);
            }
        }

        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            (,,, , uint256 nonce) = hub.agents(agentIds[i]);
            assertEq(nonce, 5);
        }
    }

    function testParallelWithEmitterEvents() public {
        for (uint256 i = 0; i < AGENT_COUNT; i++) {
            vm.prank(owners[i]);
            bytes memory payload = abi.encode(i);
            bytes32 expectedExecutionId =
                keccak256(abi.encodePacked(agentIds[i], uint256(1), block.number));

            vm.expectEmit(true, true, true, true, address(hub));
            emit AgentExecuted(agentIds[i], 1, expectedExecutionId, payload, 1, block.timestamp, true);

            hub.executeAgentTask(agentIds[i], 1, TaskData({version: 1, deadline: 0, payload: payload}));
        }
    }

    function testParallelBatchExecution() public {
        uint256 batchSize = 10;
        uint256 batches = AGENT_COUNT / batchSize;

        for (uint256 b = 0; b < batches; b++) {
            uint256 startIdx = b * batchSize;

            uint256[] memory batchAgentIds = new uint256[](batchSize);
            uint256[] memory nonces = new uint256[](batchSize);
            TaskData[] memory tasks = new TaskData[](batchSize);

            for (uint256 i = 0; i < batchSize; i++) {
                uint256 idx = startIdx + i;
                batchAgentIds[i] = agentIds[idx];
                nonces[i] = 1;
                tasks[i] = _taskDataWithId(idx);
            }

            vm.expectRevert();
            hub.batchExecuteTasks(batchAgentIds, nonces, tasks);
        }
    }

    function testAgentStorageIsolation() public {
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(owners[i]);
            hub.executeAgentTask(agentIds[i], 1, _taskDataWithId(i));
        }

        vm.prank(owners[0]);
        hub.deactivateAgent(agentIds[0]);

        (,, bool a0Active,,) = hub.agents(agentIds[0]);
        assertFalse(a0Active);

        for (uint256 i = 1; i < 5; i++) {
            (,, bool active,,) = hub.agents(agentIds[i]);
            assertTrue(active);
        }
    }

    function testParallelAgentIndependence() public {
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(owners[i]);
            hub.executeAgentTask(agentIds[i], 1, _taskDataWithId(i));
        }

        vm.prank(owners[0]);
        hub.executeAgentTask(agentIds[0], 2, _taskDataWithId(100));

        (,,, , uint256 n0) = hub.agents(agentIds[0]);
        (,,, , uint256 n1) = hub.agents(agentIds[1]);
        (,,, , uint256 n2) = hub.agents(agentIds[2]);
        assertEq(n0, 2);
        assertEq(n1, 1);
        assertEq(n2, 1);
    }
}
