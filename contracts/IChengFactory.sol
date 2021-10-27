// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IChengFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}