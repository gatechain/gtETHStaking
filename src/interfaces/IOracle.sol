// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IOracle {

    // ================ events ================
    event Report(uint256[] postRebaseAmounts);

    // ================ core functions ================
    function report(uint256[] memory postRebaseAmounts) external;

    // ================ view functions ================
    function getExchangeRate() external view returns (uint256);
}