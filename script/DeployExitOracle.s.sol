// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {ValidatorsExitBusOracle} from "../src/oracle/ValidatorsExitBusOracle.sol";
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
        ValidatorsExitBusOracle implementation = new ValidatorsExitBusOracle();
        console.log("ValidatorsExitBusOracle implementation deployed at:", address(implementation));
        
        // 部署代理合约
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(
                ValidatorsExitBusOracle.initialize.selector,
                32, // slotsPerEpoch
                12, // secondsPerSlot
                1742213400, // genesisTime
                0x87704E6B466715b75e21A81d83B6FdB4AC7239a3, // oracleMember
                0, // lastProcessingRefSlot
                10 // epochsPerFrame
            )
        );
        console.log("ValidatorsExitBusOracle proxy deployed at:", address(proxy));
        
        // 获取代理合约实例
        ValidatorsExitBusOracle validatorsExitBusOracle = ValidatorsExitBusOracle(payable(address(proxy)));

        // 合约已通过代理初始化，现在恢复运行
        validatorsExitBusOracle.grantRole(validatorsExitBusOracle.RESUME_ROLE(), deployer);
        validatorsExitBusOracle.resume();

        vm.stopBroadcast();
    }
}