// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {WithdrawalQueueERC721} from "../src/WithdrawalQueueERC721.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployWithdrawalQueueERC721 is Script {
    uint256 internal deployerPrivateKey;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");

        vm.startBroadcast(deployerPrivateKey);
        
        // 部署实现合约
        WithdrawalQueueERC721 implementation = new WithdrawalQueueERC721();
        console.log("WithdrawalQueueERC721 implementation deployed at:", address(implementation));
        
        // 部署透明代理
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            vm.addr(deployerPrivateKey),
            ""
        );
        console.log("WithdrawalQueueERC721 proxy deployed at:", address(proxy));
        
        // 初始化代理合约
        WithdrawalQueueERC721 withdrawalQueueERC721 = WithdrawalQueueERC721(address(proxy));
        withdrawalQueueERC721.initialize("gtETH withdrawal", "gtETH withdrawal", vm.addr(deployerPrivateKey));
        console.log("WithdrawalQueueERC721 initialized");
        
        vm.stopBroadcast();
    }

    function setAll() public {
        address proxy = 0xc0675B6Cb094F395281B7deF89c26AEa6444F1F8;
        address gteth = 0xA5b68cE84F12c55ACAC70dEbB46A064624951554;
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");

        vm.startBroadcast(deployerPrivateKey);
        WithdrawalQueueERC721 withdrawalQueueERC721 = WithdrawalQueueERC721(address(proxy));
        withdrawalQueueERC721.grantRole(withdrawalQueueERC721.WITHDRAWAL_REQUEST_ROLE(), gteth);
        withdrawalQueueERC721.grantRole(withdrawalQueueERC721.WITHDRAWAL_FINALIZE_ROLE(), gteth);
        withdrawalQueueERC721.grantRole(withdrawalQueueERC721.WITHDRAWAL_CLAIM_ROLE(), gteth);
        vm.stopBroadcast();
    }
}