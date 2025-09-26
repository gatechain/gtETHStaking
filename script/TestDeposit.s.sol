// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {StakingRouter} from "../src/StakingRouter.sol";
import {NodeOperatorsRegistry} from "../src/NodeOperatorsRegistry.sol";
import {IGTETH} from "../src/interfaces/IGTETH.sol";

contract TestDeposit is Script {

    uint256 internal deployerPrivateKey;
    address internal gteth = 0xA5b68cE84F12c55ACAC70dEbB46A064624951554;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");
        vm.startBroadcast(deployerPrivateKey);
        // IGTETH(gteth).submit{value: 128 ether}();
        IGTETH(gteth).deposit(4, 1, "");
        vm.stopBroadcast();
    }
} 