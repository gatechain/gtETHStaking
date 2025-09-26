// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {StakingRouter} from "../src/StakingRouter.sol";

/**
 * @title DeployStakingRouterUUPS
 * @notice 部署可升级的StakingRouter合约脚本
 * @dev 使用UUPS代理模式进行部署
 */
contract DeployStakingRouterUUPS is Script {
    
    /// @notice 部署可升级的StakingRouter合约
    /// @param _admin 管理员地址
    /// @param _gteth GTETH主合约地址
    /// @param _depositContract 信标链存款合约地址
    /// @param _withdrawalCredentials 初始提取凭证
    /// @return proxy 代理合约地址
    /// @return implementation 实现合约地址
    function deployStakingRouter(
        address _admin,
        address _gteth,
        address _depositContract,
        bytes32 _withdrawalCredentials,
        uint256 _deployerPrivateKey
    ) public returns (address proxy, address implementation) {
        vm.startBroadcast(_deployerPrivateKey);
        
        // 1. 部署实现合约
        implementation = address(new StakingRouter());
        console.log("StakingRouter implementation deployed at:", implementation);
        
        // 2. 编码初始化数据
        bytes memory initData = abi.encodeCall(
            StakingRouter.initialize,
            (_admin, _gteth, _depositContract, _withdrawalCredentials)
        );
        
        // 3. 部署ERC1967代理合约
        proxy = address(new ERC1967Proxy(implementation, initData));
        console.log("StakingRouter proxy deployed at:", proxy);
        console.log("Admin address:", _admin);
        console.log("GTETH address:", _gteth);
        console.log("Deposit contract:", _depositContract);
        console.log("Withdrawal credentials:", vm.toString(_withdrawalCredentials));
        
        vm.stopBroadcast();
    }

    /// @notice 升级StakingRouter合约
    /// @param _proxyAddress 代理合约地址
    /// @return newImplementation 新实现合约地址
    function upgradeStakingRouter(address _proxyAddress, uint256 _deployerPrivateKey) 
        public 
        returns (address newImplementation) 
    {
        vm.startBroadcast(_deployerPrivateKey);
        
        // 1. 部署新的实现合约
        newImplementation = address(new StakingRouter());
        console.log("New StakingRouter implementation deployed at:", newImplementation);
        
        // 2. 获取代理合约实例
        StakingRouter proxy = StakingRouter(payable(_proxyAddress));
        
        // 3. 执行升级（需要管理员权限）
        proxy.upgradeToAndCall(newImplementation, "");
        console.log("StakingRouter upgraded successfully");
        console.log("Proxy address:", _proxyAddress);
        console.log("New implementation:", newImplementation);
        
        vm.stopBroadcast();
    }
    
    /// @notice 主运行函数
    function run() external {
        // 从环境变量或者配置中获取参数
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY3");
        address admin = vm.addr(deployerPrivateKey);
        address gteth = 0xA5b68cE84F12c55ACAC70dEbB46A064624951554;
        address depositContract = 0x00000000219ab540356cBB839Cbe05303d7705Fa;
        bytes32 withdrawalCredentials = 0x01000000000000000000000080eceff963f04558893c232988d4d1f5d42f3633;
        
        deployStakingRouter(admin, gteth, depositContract, withdrawalCredentials, deployerPrivateKey);

        // address stakingRouterProxy = 0xc31118879d7322Df281e9680dA2f4D6B26FA2939;
        // upgradeStakingRouter(stakingRouterProxy, deployerPrivateKey);
    }
}
