// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {NodeOperatorsRegistry} from "../src/NodeOperatorsRegistry.sol";
import {console} from "forge-std/console.sol";

contract TestNode is Script {
    uint256 internal deployerPrivateKey;
    address internal nodeOperatorsRegistry = 0xBe954d4D0dd4DCDF31842BfA4677C637b7b44f76;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");
        vm.startBroadcast(deployerPrivateKey);
        (bytes memory publicKeys, bytes memory depositSignatures) = NodeOperatorsRegistry(nodeOperatorsRegistry).obtainDepositData(1, "0x");
        console.logBytes(publicKeys);
        console.logBytes(depositSignatures);

        
        vm.stopBroadcast();
    }
}