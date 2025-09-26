// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {GTETH} from "../src/GTETH.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
contract DeployGTETH is Script {
    uint256 internal deployerPrivateKey;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署实现合约
        GTETH implementation = new GTETH();
        console.log("GTETH implementation deployed at:", address(implementation));
        
        // 部署透明代理
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            vm.addr(deployerPrivateKey),
            ""
        );
        console.log("GTETH proxy deployed at:", address(proxy));
        
        // 初始化代理合约
        GTETH gteth = GTETH(payable(address(proxy)));
        gteth.initialize("GTETH", "GTETH", vm.addr(deployerPrivateKey));
        console.log("GTETH initialized");
        
        vm.stopBroadcast();
    }

    function setAll() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3"); 
        address payable gtethAddress = payable(0xA5b68cE84F12c55ACAC70dEbB46A064624951554);
        address gtethLocator = 0x42Aa599CD3db948f2d66F7dc14135804d0DBe1c7;
        
        
        address stakingModule = 0x03b2349fb8e6D6d13fa399880cE79750721E99D5;
        GTETH gteth = GTETH(payable(gtethAddress));
        vm.startBroadcast(deployerPrivateKey);

        gteth.grantRole(gteth.DEFAULT_ADMIN_ROLE(), 0xfAC592E1cd63A9423A2E769764335bb2f59E9B0a);
        gteth.grantRole(gteth.PAUSER_ROLE(), 0xfAC592E1cd63A9423A2E769764335bb2f59E9B0a);
        gteth.grantRole(gteth.DEPOSIT_SECURITY_MODULE_ROLE(), 0xfAC592E1cd63A9423A2E769764335bb2f59E9B0a);
        
        // gteth.grantRole(gteth.DEPOSIT_SECURITY_MODULE_ROLE(), stakingModule);
        // gteth.setGTETHLocator(gtethLocator);
        // gteth.grantRole(gteth.DEPOSIT_SECURITY_MODULE_ROLE(), stakingModule);
        vm.stopBroadcast();
    }

    function upgrade() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");
        address payable proxyAddress = payable(0xA5b68cE84F12c55ACAC70dEbB46A064624951554);
        
        GTETH gteth = GTETH(payable(proxyAddress));
        console.log("GTETH deployed at:", address(gteth));
        console.log("gteth.getYield()", gteth.getYield());

        ProxyAdmin proxyAdmin = ProxyAdmin(0xfF176A63b1f07e201763FFE76Cf6c38c41697af7);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));
        
        vm.startBroadcast(deployerPrivateKey);
        GTETH implementation = new GTETH();
        console.log("GTETH implementation deployed at:", address(implementation));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(proxyAddress),
            address(implementation),
            ""
        );
        vm.stopBroadcast();
    }
}