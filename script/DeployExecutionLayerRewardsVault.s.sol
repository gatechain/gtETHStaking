// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {ExecutionLayerRewardsVault} from "../src/ExecutionLayerRewardsVault.sol";

contract DeployExecutionLayerRewardsVault is Script {
    uint256 internal deployerPrivateKey;
    address internal GTETH = 0xf89b4a70e1777D0ea5764FA7cE185410861Edfe8;
    address internal TREASURY = 0x03b2349fb8e6D6d13fa399880cE79750721E99D5;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");

        vm.startBroadcast(deployerPrivateKey);
        ExecutionLayerRewardsVault executionLayerRewardsVault = new ExecutionLayerRewardsVault(
            GTETH,
            TREASURY
        );
        console.log("ExecutionLayerRewardsVault deployed at:", address(executionLayerRewardsVault));
        vm.stopBroadcast();
    }
}