// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MonadAgentHub} from "../contracts/MonadAgentHub.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract DeployMonadFlow is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address multisig = vm.envAddress("MULTISIG_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        AgentRegistry registry = new AgentRegistry(deployer);

        MonadAgentHub hub = new MonadAgentHub(address(registry));

        registry.setHub(address(hub));

        address[] memory proposers = new address[](1);
        proposers[0] = multisig;
        address[] memory executors = new address[](1);
        executors[0] = multisig;

        TimelockController timelock = new TimelockController(
            86400,
            proposers,
            executors,
            deployer
        );

        hub.transferOwnership(address(timelock));

        timelock.grantRole(timelock.DEFAULT_ADMIN_ROLE(), multisig);

        vm.stopBroadcast();

        console.log("Deployer:", deployer);
        console.log("AgentRegistry:", address(registry));
        console.log("MonadAgentHub:", address(hub));
        console.log("TimelockController:", address(timelock));
        console.log("Hub Owner (post-deploy):", hub.owner());
    }
}
