// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MonadAgentHub} from "../contracts/MonadAgentHub.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {TaskData} from "../contracts/interfaces/IMonadAgentHub.sol";

contract AgentHubTest is Test {
    MonadAgentHub public hub;
    AgentRegistry public registry;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");

    bytes32 public constant DEFI_SWAP = bytes32("DEFI_SWAP");
    bytes32 public constant DEFI_LEND = bytes32("DEFI_LEND");
    bytes32 public constant NFT_MINT = bytes32("NFT_MINT");
    bytes32 public constant GAME_NPC = bytes32("GAME_NPC");

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

    event Paused(address indexed initiator, uint8 version, uint256 timestamp);
    event Unpaused(address indexed initiator, uint8 version, uint256 timestamp);

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

    function setUp() public {
        vm.startPrank(owner);
        registry = new AgentRegistry(owner);
        hub = new MonadAgentHub(address(registry));
        registry.setHub(address(hub));
        vm.stopPrank();
    }

    function _taskData(uint8 version, uint256 deadline, bytes memory payload)
        internal
        pure
        returns (TaskData memory)
    {
        return TaskData({version: version, deadline: deadline, payload: payload});
    }

    function _defaultTaskData() internal pure returns (TaskData memory) {
        return _taskData(1, 0, hex"");
    }

    function _taskDataWithPayload(bytes memory payload) internal pure returns (TaskData memory) {
        return _taskData(1, 0, payload);
    }

    // ============ registerAgent ============

    function testRegisterAgent() public {
        vm.prank(user1);
        uint256 id = hub.registerAgent(DEFI_SWAP);
        assertEq(id, 1);

        (uint256 agentId, address agentOwner, bool isActive, bytes32 wfType, uint256 nonce) =
            hub.agents(id);
        assertEq(agentId, 1);
        assertEq(agentOwner, user1);
        assertTrue(isActive);
        assertEq(wfType, DEFI_SWAP);
        assertEq(nonce, 0);
    }

    function testRegisterAgentEmitsEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, true, false, true, address(hub));
        emit AgentRegistered(1, user1, DEFI_SWAP, 1, block.timestamp);
        hub.registerAgent(DEFI_SWAP);
    }

    function testRegisterMultipleAgents() public {
        vm.prank(user1);
        uint256 id1 = hub.registerAgent(DEFI_SWAP);

        vm.prank(user2);
        uint256 id2 = hub.registerAgent(DEFI_LEND);

        assertEq(id1, 1);
        assertEq(id2, 2);

        (,,, bytes32 wf1,) = hub.agents(1);
        (,,, bytes32 wf2,) = hub.agents(2);
        assertEq(wf1, DEFI_SWAP);
        assertEq(wf2, DEFI_LEND);
    }

    function testRegisterSameUserMultipleAgents() public {
        vm.startPrank(user1);
        uint256 id1 = hub.registerAgent(DEFI_SWAP);
        uint256 id2 = hub.registerAgent(NFT_MINT);
        uint256 id3 = hub.registerAgent(GAME_NPC);
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(id3, 3);

        (,,, bytes32 wf1,) = hub.agents(1);
        (,,, bytes32 wf2,) = hub.agents(2);
        (,,, bytes32 wf3,) = hub.agents(3);
        assertEq(wf1, DEFI_SWAP);
        assertEq(wf2, NFT_MINT);
        assertEq(wf3, GAME_NPC);
    }

    // ============ executeAgentTask ============

    function testExecuteAgentTask() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(DEFI_SWAP);

        TaskData memory taskData = _taskDataWithPayload(hex"010203");
        bool success = hub.executeAgentTask(id, 1, taskData);
        assertTrue(success);

        (,,, , uint256 nonce) = hub.agents(id);
        assertEq(nonce, 1);
        vm.stopPrank();
    }

    function testExecuteAgentTaskEmitsEvent() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(DEFI_SWAP);

        bytes memory payload = hex"010203";
        TaskData memory taskData = _taskDataWithPayload(payload);

        bytes32 expectedExecutionId = keccak256(abi.encodePacked(id, uint256(1), block.number));

        vm.expectEmit(true, true, true, true, address(hub));
        emit AgentExecuted(id, 1, expectedExecutionId, payload, 1, block.timestamp, true);

        hub.executeAgentTask(id, 1, taskData);
        vm.stopPrank();
    }

    function testExecuteAgentTaskIncrementsNonce() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(DEFI_SWAP);

        hub.executeAgentTask(id, 1, _defaultTaskData());
        (,,, , uint256 nonce1) = hub.agents(id);
        assertEq(nonce1, 1);

        hub.executeAgentTask(id, 2, _defaultTaskData());
        (,,, , uint256 nonce2) = hub.agents(id);
        assertEq(nonce2, 2);

        hub.executeAgentTask(id, 3, _defaultTaskData());
        (,,, , uint256 nonce3) = hub.agents(id);
        assertEq(nonce3, 3);
        vm.stopPrank();
    }

    // ============ access control ============

    function testNonOwnerCannotExecute() public {
        vm.prank(user1);
        uint256 id = hub.registerAgent(DEFI_SWAP);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(MonadAgentHub.NotAgentOwner.selector, id, attacker, user1)
        );
        hub.executeAgentTask(id, 1, _defaultTaskData());
    }

    function testNonOwnerCannotDeactivate() public {
        vm.prank(user1);
        uint256 id = hub.registerAgent(DEFI_SWAP);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(MonadAgentHub.NotAgentOwner.selector, id, attacker, user1)
        );
        hub.deactivateAgent(id);
    }

    // ============ deactivateAgent ============

    function testDeactivateAgent() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(DEFI_SWAP);

        hub.deactivateAgent(id);

        (,, bool isActive,,) = hub.agents(id);
        assertFalse(isActive);
        vm.stopPrank();
    }

    function testDeactivateAgentEmitsEvent() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(DEFI_SWAP);

        vm.expectEmit(true, false, false, true, address(hub));
        emit AgentDeactivated(id, 1, block.timestamp);

        hub.deactivateAgent(id);
        vm.stopPrank();
    }

    function testCannotExecuteOnDeactivatedAgent() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(DEFI_SWAP);

        hub.executeAgentTask(id, 1, _defaultTaskData());
        hub.deactivateAgent(id);

        vm.expectRevert(abi.encodeWithSelector(MonadAgentHub.AgentInactive.selector, id));
        hub.executeAgentTask(id, 2, _defaultTaskData());
        vm.stopPrank();
    }

    // ============ nonce replay protection ============

    function testNonceReplayProtection() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(bytes32("TEST"));

        hub.executeAgentTask(id, 1, _defaultTaskData());

        vm.expectRevert(
            abi.encodeWithSelector(MonadAgentHub.InvalidNonce.selector, id, 2, 1)
        );
        hub.executeAgentTask(id, 1, _defaultTaskData());
        vm.stopPrank();
    }

    function testNonceSkipsCheck() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(bytes32("TEST"));

        vm.expectRevert(
            abi.encodeWithSelector(MonadAgentHub.InvalidNonce.selector, id, 1, 5)
        );
        hub.executeAgentTask(id, 5, _defaultTaskData());
        vm.stopPrank();
    }

    // ============ taskData validation ============

    function testUnsupportedTaskVersion() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(bytes32("TEST"));

        TaskData memory taskData = _taskData(99, 0, hex"");
        vm.expectRevert(
            abi.encodeWithSelector(MonadAgentHub.UnsupportedTaskVersion.selector, 99)
        );
        hub.executeAgentTask(id, 1, taskData);
        vm.stopPrank();
    }

    function testTaskExpired() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(bytes32("TEST"));

        uint256 pastDeadline = 1;
        uint256 futureTime = pastDeadline + 1;
        vm.warp(futureTime);

        TaskData memory taskData = _taskData(1, pastDeadline, hex"");

        vm.expectRevert(
            abi.encodeWithSelector(MonadAgentHub.TaskExpired.selector, pastDeadline, futureTime)
        );
        hub.executeAgentTask(id, 1, taskData);
        vm.stopPrank();
    }

    function testTaskDeadlineInFuture() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(bytes32("TEST"));

        uint256 futureDeadline = block.timestamp + 3600;
        TaskData memory taskData = _taskData(1, futureDeadline, hex"");
        bool success = hub.executeAgentTask(id, 1, taskData);
        assertTrue(success);
        vm.stopPrank();
    }

    function testTaskNoDeadline() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(bytes32("TEST"));

        TaskData memory taskData = _taskData(1, 0, hex"");
        bool success = hub.executeAgentTask(id, 1, taskData);
        assertTrue(success);
        vm.stopPrank();
    }

    // ============ agent not found ============

    function testExecuteNonExistentAgent() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(MonadAgentHub.AgentNotFound.selector, 999));
        hub.executeAgentTask(999, 1, _defaultTaskData());
    }

    function testDeactivateNonExistentAgent() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(MonadAgentHub.AgentNotFound.selector, 999));
        hub.deactivateAgent(999);
    }

    // ============ batchExecuteTasks ============

    function testBatchExecuteTasks() public {
        vm.startPrank(user1);
        uint256 id1 = hub.registerAgent(bytes32("TEST1"));
        uint256 id2 = hub.registerAgent(bytes32("TEST2"));
        uint256 id3 = hub.registerAgent(bytes32("TEST3"));

        uint256[] memory agentIds = new uint256[](3);
        agentIds[0] = id1;
        agentIds[1] = id2;
        agentIds[2] = id3;

        uint256[] memory nonces = new uint256[](3);
        nonces[0] = 1;
        nonces[1] = 1;
        nonces[2] = 1;

        TaskData[] memory tasks = new TaskData[](3);
        tasks[0] = _taskDataWithPayload(hex"AA");
        tasks[1] = _taskDataWithPayload(hex"BB");
        tasks[2] = _taskDataWithPayload(hex"CC");

        bool[] memory successes = hub.batchExecuteTasks(agentIds, nonces, tasks);
        assertEq(successes.length, 3);
        assertTrue(successes[0]);
        assertTrue(successes[1]);
        assertTrue(successes[2]);

        (,,, , uint256 n1) = hub.agents(id1);
        (,,, , uint256 n2) = hub.agents(id2);
        (,,, , uint256 n3) = hub.agents(id3);
        assertEq(n1, 1);
        assertEq(n2, 1);
        assertEq(n3, 1);
        vm.stopPrank();
    }

    function testBatchExecuteIncrementsNonces() public {
        vm.startPrank(user1);
        uint256 id1 = hub.registerAgent(bytes32("T1"));
        uint256 id2 = hub.registerAgent(bytes32("T2"));

        uint256[] memory agentIds1 = new uint256[](2);
        agentIds1[0] = id1;
        agentIds1[1] = id2;
        uint256[] memory nonces1 = new uint256[](2);
        nonces1[0] = 1;
        nonces1[1] = 1;
        TaskData[] memory tasks1 = new TaskData[](2);
        tasks1[0] = _defaultTaskData();
        tasks1[1] = _defaultTaskData();

        hub.batchExecuteTasks(agentIds1, nonces1, tasks1);

        uint256[] memory agentIds2 = new uint256[](2);
        agentIds2[0] = id1;
        agentIds2[1] = id2;
        uint256[] memory nonces2 = new uint256[](2);
        nonces2[0] = 2;
        nonces2[1] = 2;
        TaskData[] memory tasks2 = new TaskData[](2);
        tasks2[0] = _defaultTaskData();
        tasks2[1] = _defaultTaskData();

        hub.batchExecuteTasks(agentIds2, nonces2, tasks2);

        (,,, , uint256 n1) = hub.agents(id1);
        (,,, , uint256 n2) = hub.agents(id2);
        assertEq(n1, 2);
        assertEq(n2, 2);
        vm.stopPrank();
    }

    function testBatchLengthMismatch() public {
        vm.startPrank(user1);
        hub.registerAgent(bytes32("T1"));

        uint256[] memory agentIds = new uint256[](2);
        agentIds[0] = 1;
        agentIds[1] = 1;

        uint256[] memory nonces = new uint256[](1);
        nonces[0] = 1;

        TaskData[] memory tasks = new TaskData[](1);
        tasks[0] = _defaultTaskData();

        vm.expectRevert(
            abi.encodeWithSelector(MonadAgentHub.BatchLengthMismatch.selector, 2, 1)
        );
        hub.batchExecuteTasks(agentIds, nonces, tasks);
        vm.stopPrank();
    }

    function testBatchOtherOwnerCannotExecute() public {
        vm.prank(user1);
        uint256 id1 = hub.registerAgent(bytes32("T1"));
        vm.prank(user2);
        uint256 id2 = hub.registerAgent(bytes32("T2"));

        vm.prank(user1);
        uint256[] memory agentIds = new uint256[](2);
        agentIds[0] = id1;
        agentIds[1] = id2;

        uint256[] memory nonces = new uint256[](2);
        nonces[0] = 1;
        nonces[1] = 1;

        TaskData[] memory tasks = new TaskData[](2);
        tasks[0] = _defaultTaskData();
        tasks[1] = _defaultTaskData();

        vm.expectRevert(
            abi.encodeWithSelector(MonadAgentHub.NotAgentOwner.selector, id2, user1, user2)
        );
        hub.batchExecuteTasks(agentIds, nonces, tasks);
    }

    // ============ pause/unpause ============

    function testPauseAndUnpause() public {
        assertFalse(hub.paused());

        vm.prank(owner);
        hub.pause();
        assertTrue(hub.paused());

        vm.prank(owner);
        hub.unpause();
        assertFalse(hub.paused());
    }

    function testPauseEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(hub));
        emit Paused(owner, 1, block.timestamp);
        hub.pause();
    }

    function testUnpauseEmitsEvent() public {
        vm.startPrank(owner);
        hub.pause();

        vm.expectEmit(true, false, false, true, address(hub));
        emit Unpaused(owner, 1, block.timestamp);
        hub.unpause();
        vm.stopPrank();
    }

    function testCannotRegisterWhenPaused() public {
        vm.prank(owner);
        hub.pause();

        vm.prank(user1);
        vm.expectRevert(MonadAgentHub.ContractIsPaused.selector);
        hub.registerAgent(DEFI_SWAP);
    }

    function testCannotExecuteWhenPaused() public {
        vm.prank(user1);
        uint256 id = hub.registerAgent(DEFI_SWAP);

        vm.prank(owner);
        hub.pause();

        vm.prank(user1);
        vm.expectRevert(MonadAgentHub.ContractIsPaused.selector);
        hub.executeAgentTask(id, 1, _defaultTaskData());
    }

    function testCannotDeactivateWhenPaused() public {
        vm.prank(user1);
        uint256 id = hub.registerAgent(DEFI_SWAP);

        vm.prank(owner);
        hub.pause();

        vm.prank(user1);
        vm.expectRevert(MonadAgentHub.ContractIsPaused.selector);
        hub.deactivateAgent(id);
    }

    function testNonOwnerCannotPause() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(0x118cdaa7, user1)
        );
        hub.pause();
    }

    // ============ ownership transfer ============

    function testTransferOwnership() public {
        vm.prank(owner);
        hub.transferOwnership(user1);
        assertEq(hub.owner(), owner); // Not yet accepted

        vm.prank(user1);
        hub.acceptOwnership();
        assertEq(hub.owner(), user1);
    }

    function testOnlyOwnerCanTransfer() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(0x118cdaa7, user1)
        );
        hub.transferOwnership(user2);
    }

    // ============ deprecate/migrate ============

    function testDeprecate() public {
        vm.prank(owner);
        hub.deprecate();
        assertTrue(hub.deprecated());
    }

    function testDeprecateEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true, address(hub));
        emit ContractDeprecated("1.0.0", 1, block.timestamp);
        hub.deprecate();
    }

    function testCannotRegisterWhenDeprecated() public {
        vm.prank(owner);
        hub.deprecate();

        vm.prank(user1);
        vm.expectRevert(MonadAgentHub.ContractIsDeprecated.selector);
        hub.registerAgent(DEFI_SWAP);
    }

    function testCannotExecuteWhenDeprecated() public {
        vm.prank(user1);
        uint256 id = hub.registerAgent(DEFI_SWAP);

        vm.prank(owner);
        hub.deprecate();

        vm.prank(user1);
        vm.expectRevert(MonadAgentHub.ContractIsDeprecated.selector);
        hub.executeAgentTask(id, 1, _defaultTaskData());
    }

    function testMigrateAgent() public {
        vm.startPrank(user1);
        uint256 oldId = hub.registerAgent(DEFI_SWAP);
        vm.stopPrank();

        vm.prank(owner);
        hub.deprecate();

        vm.prank(user1);
        uint256 newId = hub.migrateAgent(oldId);
        assertGt(newId, oldId);

        (uint256 agentId, address ownerAddr, bool isActive, bytes32 wfType, uint256 nonce) =
            hub.agents(newId);
        assertEq(agentId, newId);
        assertEq(ownerAddr, user1);
        assertTrue(isActive);
        assertEq(wfType, DEFI_SWAP);
        assertEq(nonce, 0);
    }

    function testMigrateAgentEmitsEvent() public {
        vm.startPrank(user1);
        uint256 oldId = hub.registerAgent(DEFI_SWAP);
        vm.stopPrank();

        vm.prank(owner);
        hub.deprecate();

        vm.prank(user1);
        vm.expectEmit(true, true, true, true, address(hub));
        emit AgentMigrated(oldId, 2, user1, 1, block.timestamp);

        hub.migrateAgent(oldId);
    }

    function testCannotMigrateWhenNotDeprecated() public {
        vm.startPrank(user1);
        uint256 oldId = hub.registerAgent(DEFI_SWAP);

        vm.expectRevert(MonadAgentHub.MigrationRequiresDeprecated.selector);
        hub.migrateAgent(oldId);
        vm.stopPrank();
    }

    function testNonOwnerCannotMigrate() public {
        vm.prank(user1);
        uint256 oldId = hub.registerAgent(DEFI_SWAP);

        vm.prank(owner);
        hub.deprecate();

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(MonadAgentHub.NotAgentOwner.selector, oldId, attacker, user1)
        );
        hub.migrateAgent(oldId);
    }

    // ============ getAgentState ============

    function testGetAgentStateNonce() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(bytes32("TEST"));

        uint256 state = hub.getAgentState(id, bytes32("nonce"));
        assertEq(state, 0);

        hub.executeAgentTask(id, 1, _defaultTaskData());
        state = hub.getAgentState(id, bytes32("nonce"));
        assertEq(state, 1);
        vm.stopPrank();
    }

    function testGetAgentStateIsActive() public {
        vm.startPrank(user1);
        uint256 id = hub.registerAgent(bytes32("TEST"));

        uint256 state = hub.getAgentState(id, bytes32("isActive"));
        assertEq(state, 1);

        hub.deactivateAgent(id);
        state = hub.getAgentState(id, bytes32("isActive"));
        assertEq(state, 0);
        vm.stopPrank();
    }

    function testGetAgentStateNonExistentAgent() public {
        vm.expectRevert(abi.encodeWithSelector(MonadAgentHub.AgentNotFound.selector, 999));
        hub.getAgentState(999, bytes32("nonce"));
    }

    // ============ VERSION ============

    function testVersion() public view {
        assertEq(hub.VERSION(), "1.0.0");
    }

    function testCurrentTaskVersion() public view {
        assertEq(hub.CURRENT_TASK_VERSION(), 1);
    }
}
