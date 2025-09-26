// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IWithdrawalVault {
    function withdrawWithdrawals(uint256 _amount) external;
}