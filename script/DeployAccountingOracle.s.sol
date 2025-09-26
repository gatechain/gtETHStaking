// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {AccountingOracle} from "../src/oracle/AccountingOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployValidator is Script {
    uint256 internal deployerPrivateKey;
    address internal deployer;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");
        deployer = vm.addr(deployerPrivateKey);
        address oracleMember = 0x87704E6B466715b75e21A81d83B6FdB4AC7239a3;

        // deploy contract
        vm.startBroadcast(deployerPrivateKey);
        
        // 部署实现合约
        AccountingOracle implementation = new AccountingOracle();
        console.log("AccountingOracle implementation deployed at:", address(implementation));
        
        // 部署代理合约
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                AccountingOracle.initialize.selector,
                0x6067f5B8d6401544Ee70756A1427Cd204bE27cF7, // locator
                0xA5b68cE84F12c55ACAC70dEbB46A064624951554, // gteth
                32, // slotsPerEpoch
                12, // secondsPerSlot
                1742213400, // genesisTime
                0x87704E6B466715b75e21A81d83B6FdB4AC7239a3, // oracleMember
                0, // lastProcessingRefSlot
                10 // epochsPerFrame
            )
        );
        console.log("AccountingOracle proxy deployed at:", address(proxy));
        
        // 获取代理合约实例
        AccountingOracle accountingOracle = AccountingOracle(payable(address(proxy)));

        // 合约已通过代理初始化，现在恢复运行
        accountingOracle.grantRole(accountingOracle.RESUME_ROLE(), deployer);
        accountingOracle.resume();

        vm.stopBroadcast();
    }

    function setAll() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3"); 
        console.log("deployerPrivateKey", deployerPrivateKey);
        address payable oracleAddress = payable(0xAdd4D91Ca960032611D35D7a7d1Df4C3386838E5);
        address gtethLocator = 0x42Aa599CD3db948f2d66F7dc14135804d0DBe1c7;
        // address stakingModule = 0x03b2349fb8e6D6d13fa399880cE79750721E99D5;
        AccountingOracle oracle = AccountingOracle(payable(oracleAddress));
        vm.startBroadcast(deployerPrivateKey);
        // oracle.setLOCATOR(gtethLocator);
        // oracle.grantRole(oracle.SUBMIT_DATA_ROLE(), vm.addr(deployerPrivateKey));
        // gteth.grantRole(gteth.DEPOSIT_SECURITY_MODULE_ROLE(), stakingModule);
        // oracle.updateInitialEpoch(36710);
        (uint256 refSlot, uint256 reportProcessingDeadlineSlot) = oracle.getCurrentFrame();
        console.log("refSlot", refSlot);
        console.log("reportProcessingDeadlineSlot", reportProcessingDeadlineSlot);
        oracleAddress.call(hex"917dd91800000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000128a3f00000000000000000000000000000000000000000000000000000000000000070000000000000000000000000000000000000000000000000000003427b7b43300000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000009850369fd4d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000");
        vm.stopBroadcast();
    }
}