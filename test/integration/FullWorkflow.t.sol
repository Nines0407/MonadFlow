// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console, Vm} from "forge-std/Test.sol";
import {MonadAgentHub} from "../../contracts/MonadAgentHub.sol";
import {AgentRegistry} from "../../contracts/AgentRegistry.sol";
import {TaskData, AgentInfo} from "../../contracts/interfaces/IMonadAgentHub.sol";

contract MockWorkflowExecutor {
    MonadAgentHub public hub;
    bool public executed;
    bytes public lastTaskData;

    constructor(address _hub) {
        hub = MonadAgentHub(_hub);
    }
}

contract FullWorkflowTest is Test {
    MonadAgentHub public hub;
    AgentRegistry public registry;

    address public owner = makeAddr("owner");
    address public agentOwner1 = makeAddr("agentOwner1");
    address public agentOwner2 = makeAddr("agentOwner2");
    address public relayer = makeAddr("relayer");

    bytes32 public constant DEFI_SWAP = bytes32("DEFI_SWAP");
    bytes32 public constant NFT_MINT = bytes32("NFT_MINT");

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

    function _defaultTaskData() internal pure returns (TaskData memory) {
        return TaskData({version: 1, deadline: 0, payload: hex""});
    }

    function _taskDataWithPayload(bytes memory payload) internal pure returns (TaskData memory) {
        return TaskData({version: 1, deadline: 0, payload: payload});
    }

    // ============ Full lifecycle ============

    function testAgentFullLifecycle() public {
        vm.startPrank(agentOwner1);
        uint256 agentId = hub.registerAgent(DEFI_SWAP);
        assertEq(agentId, 1);

        (,, bool isActive,,) = hub.agents(agentId);
        assertTrue(isActive);

        hub.executeAgentTask(agentId, 1, _defaultTaskData());
        hub.executeAgentTask(agentId, 2, _defaultTaskData());

        (,,, , uint256 nonce) = hub.agents(agentId);
        assertEq(nonce, 2);

        hub.deactivateAgent(agentId);
        (,, bool active,,) = hub.agents(agentId);
        assertFalse(active);

        vm.expectRevert(abi.encodeWithSelector(MonadAgentHub.AgentInactive.selector, agentId));
        hub.executeAgentTask(agentId, 3, _defaultTaskData());
        vm.stopPrank();
    }

    // ============ Multi-agent scenario ============

    function testMultiAgentWorkflow() public {
        vm.prank(agentOwner1);
        uint256 swapAgent = hub.registerAgent(DEFI_SWAP);

        vm.prank(agentOwner2);
        uint256 nftAgent = hub.registerAgent(NFT_MINT);

        vm.prank(agentOwner1);
        hub.executeAgentTask(swapAgent, 1, _taskDataWithPayload(hex"DEADBEEF"));

        vm.prank(agentOwner2);
        hub.executeAgentTask(nftAgent, 1, _taskDataWithPayload(hex"CAFEBABE"));

        vm.prank(agentOwner1);
        hub.executeAgentTask(swapAgent, 2, _taskDataWithPayload(hex"010203"));

        (,,,, uint256 swapNonce) = hub.agents(swapAgent);
        (,,,, uint256 nftNonce) = hub.agents(nftAgent);
        assertEq(swapNonce, 2);
        assertEq(nftNonce, 1);
    }

    // ============ Batch in multi-owner context ============

    function testBatchOwnedBySingleUser() public {
        vm.startPrank(agentOwner1);
        uint256 id1 = hub.registerAgent(bytes32("WF1"));
        uint256 id2 = hub.registerAgent(bytes32("WF2"));
        uint256 id3 = hub.registerAgent(bytes32("WF3"));

        uint256[] memory agentIds = new uint256[](3);
        agentIds[0] = id1;
        agentIds[1] = id2;
        agentIds[2] = id3;

        uint256[] memory nonces = new uint256[](3);
        nonces[0] = 1;
        nonces[1] = 1;
        nonces[2] = 1;

        TaskData[] memory tasks = new TaskData[](3);
        tasks[0] = _taskDataWithPayload(hex"01");
        tasks[1] = _taskDataWithPayload(hex"02");
        tasks[2] = _taskDataWithPayload(hex"03");

        bool[] memory successes = hub.batchExecuteTasks(agentIds, nonces, tasks);
        assertEq(successes.length, 3);
        assertTrue(successes[0]);
        assertTrue(successes[1]);
        assertTrue(successes[2]);
        vm.stopPrank();
    }

    // ============ Pause + deprecate + migrate ============

    function testFullEmergencyWorkflow() public {
        vm.prank(agentOwner1);
        uint256 agentId = hub.registerAgent(DEFI_SWAP);

        vm.prank(agentOwner1);
        hub.executeAgentTask(agentId, 1, _defaultTaskData());

        vm.prank(owner);
        hub.pause();
        assertTrue(hub.paused());

        vm.prank(agentOwner1);
        vm.expectRevert(MonadAgentHub.ContractIsPaused.selector);
        hub.executeAgentTask(agentId, 2, _defaultTaskData());

        vm.prank(owner);
        hub.unpause();
        assertFalse(hub.paused());

        vm.prank(agentOwner1);
        hub.executeAgentTask(agentId, 2, _defaultTaskData());

        vm.prank(owner);
        hub.deprecate();
        assertTrue(hub.deprecated());

        vm.prank(agentOwner1);
        uint256 newId = hub.migrateAgent(agentId);
        assertGt(newId, agentId);

        vm.prank(agentOwner1);
        vm.expectRevert(MonadAgentHub.ContractIsDeprecated.selector);
        hub.executeAgentTask(newId, 3, _defaultTaskData());
    }

    // ============ Cross-contract verification ============

    function testHubRegisterUpdatesRegistry() public {
        vm.prank(agentOwner1);
        uint256 agentId = hub.registerAgent(DEFI_SWAP);

        assertTrue(registry.isOwner(agentId, agentOwner1));

        AgentInfo memory info = registry.getAgentInfo(agentId);
        assertEq(info.agentId, agentId);
        assertEq(info.owner, agentOwner1);
        assertEq(info.workflowType, DEFI_SWAP);
        assertTrue(info.isActive);
    }

    function testRegistryOwnershipTransferIndependent() public {
        vm.prank(agentOwner1);
        uint256 agentId = hub.registerAgent(DEFI_SWAP);

        vm.prank(agentOwner1);
        registry.transferOwnership(agentId, agentOwner2);

        assertTrue(registry.isOwner(agentId, agentOwner2));
        assertFalse(registry.isOwner(agentId, agentOwner1));

        vm.prank(agentOwner1);
        hub.executeAgentTask(agentId, 1, _defaultTaskData());
    }

    // ============ Event emission count ============

    function testEventEmissionCounts() public {
        vm.prank(agentOwner1);
        uint256 agentId = hub.registerAgent(DEFI_SWAP);

        vm.recordLogs();

        vm.prank(agentOwner1);
        hub.executeAgentTask(agentId, 1, _defaultTaskData());

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("AgentExecuted(uint256,uint8,bytes32,bytes,uint256,uint256,bool)"));
    }
}
