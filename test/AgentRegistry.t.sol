// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {AgentInfo} from "../contracts/interfaces/IMonadAgentHub.sol";

contract AgentRegistryTest is Test {
    AgentRegistry public registry;

    address public owner = makeAddr("owner");
    address public hub = makeAddr("hub");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public unauthorized = makeAddr("unauthorized");

    bytes32 public constant DEFI_SWAP = bytes32("DEFI_SWAP");

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

    function setUp() public {
        vm.prank(owner);
        registry = new AgentRegistry(owner);
        vm.prank(owner);
        registry.setHub(hub);
    }

    // ============ setHub ============

    function testSetHub() public {
        assertEq(registry.hub(), hub);
    }

    function testCannotSetHubTwice() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.HubAlreadySet.selector, hub));
        registry.setHub(makeAddr("anotherHub"));
    }

    function testNonOwnerCannotSetHub() public {
        AgentRegistry freshRegistry = new AgentRegistry(owner);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(0x118cdaa7, user1)
        );
        freshRegistry.setHub(hub);
    }

    function testRegisterBeforeHubSet() public {
        AgentRegistry freshRegistry = new AgentRegistry(owner);
        vm.expectRevert(AgentRegistry.HubNotSet.selector);
        freshRegistry.register(hub, DEFI_SWAP, user1);
    }

    // ============ register ============

    function testRegisterByHub() public {
        vm.prank(hub);
        uint256 agentId = registry.register(hub, DEFI_SWAP, user1);
        assertEq(agentId, 1);
        assertTrue(registry.isOwner(1, user1));
    }

    function testRegisterEmitsEvent() public {
        vm.prank(hub);
        vm.expectEmit(true, true, false, true, address(registry));
        emit AgentRecorded(1, user1, DEFI_SWAP, 1, block.timestamp);
        registry.register(hub, DEFI_SWAP, user1);
    }

    function testRegisterIncrementsId() public {
        vm.startPrank(hub);
        assertEq(registry.register(hub, DEFI_SWAP, user1), 1);
        assertEq(registry.register(hub, bytes32("TEST"), user2), 2);
        assertEq(registry.register(hub, bytes32("OTHER"), user1), 3);
        vm.stopPrank();
    }

    function testNonHubCannotRegister() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(AgentRegistry.UnauthorizedHub.selector, user1, hub)
        );
        registry.register(hub, DEFI_SWAP, user1);
    }

    // ============ isOwner ============

    function testIsOwner() public {
        vm.prank(hub);
        registry.register(hub, DEFI_SWAP, user1);

        assertTrue(registry.isOwner(1, user1));
        assertFalse(registry.isOwner(1, user2));
    }

    function testIsOwnerNonExistentAgent() public {
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentNotRegistered.selector, 999));
        registry.isOwner(999, user1);
    }

    // ============ getAgentInfo ============

    function testGetAgentInfo() public {
        vm.prank(hub);
        registry.register(hub, DEFI_SWAP, user1);

        AgentInfo memory info = registry.getAgentInfo(1);
        assertEq(info.agentId, 1);
        assertEq(info.owner, user1);
        assertTrue(info.isActive);
        assertEq(info.workflowType, DEFI_SWAP);
        assertEq(info.nonce, 0);
    }

    function testGetAgentInfoNonExistent() public {
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentNotRegistered.selector, 999));
        registry.getAgentInfo(999);
    }

    // ============ transferOwnership ============

    function testTransferAgentOwnership() public {
        vm.prank(hub);
        registry.register(hub, DEFI_SWAP, user1);

        vm.prank(user1);
        registry.transferOwnership(1, user2);

        assertFalse(registry.isOwner(1, user1));
        assertTrue(registry.isOwner(1, user2));
    }

    function testTransferAgentOwnershipEmitsEvent() public {
        vm.prank(hub);
        registry.register(hub, DEFI_SWAP, user1);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true, address(registry));
        emit AgentOwnershipTransferred(1, user1, user2, 1, block.timestamp);
        registry.transferOwnership(1, user2);
    }

    function testNonOwnerCannotTransferAgentOwnership() public {
        vm.prank(hub);
        registry.register(hub, DEFI_SWAP, user1);

        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(AgentRegistry.NotAgentOwner.selector, 1, user2, user1)
        );
        registry.transferOwnership(1, user1);
    }

    function testTransferOwnershipNonExistentAgent() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AgentRegistry.AgentNotRegistered.selector, 999));
        registry.transferOwnership(999, user2);
    }

    // ============ VERSION ============

    function testVersion() public view {
        assertEq(registry.VERSION(), "1.0.0");
    }

    // ============ ownership ============

    function testRegistryOwnership() public view {
        assertEq(registry.owner(), owner);
    }
}
