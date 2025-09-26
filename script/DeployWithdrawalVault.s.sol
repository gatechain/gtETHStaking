// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {WithdrawalVault} from "../src/WithdrawalVault.sol";
import {IGTETH} from "../src/interfaces/IGTETH.sol";

contract DeployWithdrawalVault is Script {
    uint256 internal deployerPrivateKey;
    address internal GTETH = 0xf89b4a70e1777D0ea5764FA7cE185410861Edfe8;
    address internal TREASURY = 0x03b2349fb8e6D6d13fa399880cE79750721E99D5;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");

        vm.startBroadcast(deployerPrivateKey);
        WithdrawalVault withdrawalVault = new WithdrawalVault(
            GTETH,
            TREASURY
        );
        console.log("WithdrawalVault deployed at:", address(withdrawalVault));
        vm.stopBroadcast();
    }
}