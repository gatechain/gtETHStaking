// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NodeOperatorsRegistry} from "../src/NodeOperatorsRegistry.sol";

/**
 * @title DeployNodeOperatorsRegistryUUPS
 * @notice 部署可升级的NodeOperatorsRegistry合约脚本
 * @dev 使用UUPS代理模式进行部署
 */
contract DeployNodeOperatorsRegistryUUPS is Script {
    
    /// @notice 部署可升级的NodeOperatorsRegistry合约
    /// @param _moduleType 质押模块类型
    /// @param _stuckPenaltyDelay 卡住验证者的惩罚延迟时间
    /// @param _admin 管理员地址
    /// @return proxy 代理合约地址
    /// @return implementation 实现合约地址
    function deployNodeOperatorsRegistry(
        bytes32 _moduleType,
        uint256 _stuckPenaltyDelay,
        address _admin,
        uint256 _deployerPrivateKey
    ) public returns (address proxy, address implementation) {
        vm.startBroadcast(_deployerPrivateKey);
        
        // 1. 部署实现合约
        implementation = address(new NodeOperatorsRegistry());
        console.log("NodeOperatorsRegistry implementation deployed at:", implementation);
        
        // 2. 编码初始化数据
        bytes memory initData = abi.encodeCall(
            NodeOperatorsRegistry.initialize,
            (_moduleType, _stuckPenaltyDelay, _admin)
        );
        
        // 3. 部署ERC1967代理合约
        proxy = address(new ERC1967Proxy(implementation, initData));
        console.log("NodeOperatorsRegistry proxy deployed at:", proxy);
        console.log("Admin address:", _admin);
        console.log("Module type:", vm.toString(_moduleType));
        console.log("Stuck penalty delay:", _stuckPenaltyDelay);
        
        vm.stopBroadcast();
    }

    /// @notice 升级NodeOperatorsRegistry合约
    /// @param _proxyAddress 代理合约地址
    /// @return newImplementation 新实现合约地址
    function upgradeNodeOperatorsRegistry(address _proxyAddress, uint256 _deployerPrivateKey) 
        public 
        returns (address newImplementation) 
    {
        vm.startBroadcast(_deployerPrivateKey);
        
        // 1. 部署新的实现合约
        newImplementation = address(new NodeOperatorsRegistry());
        console.log("New NodeOperatorsRegistry implementation deployed at:", newImplementation);
        
        // 2. 获取代理合约实例
        NodeOperatorsRegistry proxy = NodeOperatorsRegistry(_proxyAddress);
        
        // 3. 执行升级（需要管理员权限）
        proxy.upgradeToAndCall(newImplementation, "");
        console.log("NodeOperatorsRegistry upgraded successfully");
        console.log("Proxy address:", _proxyAddress);
        console.log("New implementation:", newImplementation);
        
        vm.stopBroadcast();
    }

    function run() external {
        // 从环境变量或者配置中获取参数
        bytes32 moduleType = bytes32("GTETH");
        uint256 stuckPenaltyDelay = 7 days; // 7天惩罚延迟
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY3");
        address admin = vm.addr(deployerPrivateKey); // 从环境变量获取管理员地址
        
        deployNodeOperatorsRegistry(moduleType, stuckPenaltyDelay, admin, deployerPrivateKey);
    }
}
