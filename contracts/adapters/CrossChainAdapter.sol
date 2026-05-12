// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {AgentInfo, TaskData} from "../interfaces/IMonadAgentHub.sol";

interface ICrossChainAdapter {
    function bridge(
        uint256 agentId,
        uint256 dstChainId,
        address token,
        uint256 amount,
        address recipient,
        bytes calldata extraData
    ) external returns (bytes32 messageId);

    function estimateBridgeFee(
        uint256 dstChainId,
        address token,
        uint256 amount
    ) external view returns (uint256 fee);
}
