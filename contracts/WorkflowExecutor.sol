// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {TaskData} from "./interfaces/IMonadAgentHub.sol";

abstract contract WorkflowExecutor {
    string public constant VERSION = "1.0.0";

    uint256[50] private __storageGap;

    error UnsupportedWorkflow(bytes32 workflowType);

    function execute(
        uint256 agentId,
        bytes calldata taskData
    ) external virtual returns (bool);

    function validateTask(
        uint256 agentId,
        bytes calldata taskData
    ) external virtual view returns (bool);
}
