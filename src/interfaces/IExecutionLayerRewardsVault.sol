// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IExecutionLayerRewardsVault {
    function withdrawRewards(uint256 _maxAmount) external returns (uint256 amount);
}