// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {AgentInfo, TaskData} from "../interfaces/IMonadAgentHub.sol";

interface IDeFiAdapter {
    function swap(
        uint256 agentId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 deadline
    ) external returns (uint256 amountOut);

    function addLiquidity(
        uint256 agentId,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 minLiquidity,
        uint256 deadline
    ) external returns (uint256 liquidity);

    function removeLiquidity(
        uint256 agentId,
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 minAmountA,
        uint256 minAmountB,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}
