// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {AccountingOracle} from "../src/oracle/AccountingOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployAccountingOracleUUPS is Script {
    uint256 internal deployerPrivateKey;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署实现合约
        AccountingOracle implementation = new AccountingOracle();
        console.log("AccountingOracle implementation deployed at:", address(implementation));
        
        // 部署代理合约
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                AccountingOracle.initialize.selector,
                0x42Aa599CD3db948f2d66F7dc14135804d0DBe1c7, // gtethLocator
                0xA5b68cE84F12c55ACAC70dEbB46A064624951554, // gteth
                32, // slotsPerEpoch
                12, // secondsPerSlot
                1742213400, // genesisTime
                0x94E4AF739Ec4793f50513AD9436Af809A0E7A4ef, // oracleMember
                0, // lastProcessingRefSlot
                10 // epochsPerFrame
            )
        );
        console.log("AccountingOracle proxy deployed at:", address(proxy));
        
        // 获取代理合约实例
        AccountingOracle accountingOracle = AccountingOracle(payable(address(proxy)));
        
        // 合约已通过代理初始化，现在恢复运行
        accountingOracle.grantRole(accountingOracle.RESUME_ROLE(), vm.addr(deployerPrivateKey));
        accountingOracle.resume();
        console.log("AccountingOracle initialized");
        
        vm.stopBroadcast();
    }

    function setAll() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");
        address payable oracleAddress = payable(0xAdd4D91Ca960032611D35D7a7d1Df4C3386838E5);
        vm.startBroadcast(deployerPrivateKey);
        AccountingOracle oracle = AccountingOracle(payable(oracleAddress));
        // oracle.setLOCATOR(0x42Aa599CD3db948f2d66F7dc14135804d0DBe1c7);
        // oracle.grantRole(oracle.SUBMIT_DATA_ROLE(), 0xfAC592E1cd63A9423A2E769764335bb2f59E9B0a);
        // oracle.grantRole(oracle.SUBMIT_DATA_ROLE(), 0x94E4AF739Ec4793f50513AD9436Af809A0E7A4ef);
        oracle.updateInitialEpoch(36710);
        vm.stopBroadcast();
    }

    function upgrade() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");
        address payable proxyAddress = payable(0x0000000000000000000000000000000000000000); // 替换为实际的代理地址
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署新的实现合约
        AccountingOracle newImplementation = new AccountingOracle();
        console.log("New AccountingOracle implementation deployed at:", address(newImplementation));
        
        // 升级代理合约
        AccountingOracle proxy = AccountingOracle(proxyAddress);
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("AccountingOracle upgraded");
        
        vm.stopBroadcast();
    }
}
