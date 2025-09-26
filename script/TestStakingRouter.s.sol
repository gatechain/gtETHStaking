// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {StakingRouter} from "../src/StakingRouter.sol";

contract TestStakingRouter is Script {
    uint256 internal deployerPrivateKey;
    address internal stakingRouter = 0x1AFAD90D23676e5735d24052ECecD6BBbE507e8d;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");
        vm.startBroadcast(deployerPrivateKey);
        bytes32 withdrawalCredentials = StakingRouter(payable(stakingRouter)).getWithdrawalCredentials();
        bytes memory withdrawalCredentialsBytes = abi.encodePacked(withdrawalCredentials);
        console.logBytes(withdrawalCredentialsBytes);
        vm.stopBroadcast();
    }
}