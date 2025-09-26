// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.30;

// import {Test} from "forge-std/Test.sol";
// import {StakingRouter} from "../src/StakingRouter.sol";
// import {NodeOperatorsRegistry} from "../src/NodeOperatorsRegistry.sol";
// import {INodeOperatorsRegistry} from "../src/interfaces/INodeOperatorsRegistry.sol";
// import {IGTETHLocator} from "../src/interfaces/IGTETHLocator.sol";
// import {IGTETH} from "../src/interfaces/IGTETH.sol";
// import {GTETH} from "../src/GTETH.sol";
// import {GTETHLocator} from "../src/GTETHLocator.sol";
// import {console} from "forge-std/console.sol";
// import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";


// // MOCK deposit contract
// contract MockDepositContract {
//     event DepositEvent(
//         bytes pubkey,
//         bytes withdrawal_credentials,
//         bytes signature,
//         bytes32 deposit_data_root
//     );

//     function deposit(
//         bytes calldata pubkey,
//         bytes calldata withdrawal_credentials,
//         bytes calldata signature,
//         bytes32 deposit_data_root
//     ) external payable {
//         emit DepositEvent(pubkey, withdrawal_credentials, signature, deposit_data_root);
//     }
// }

// contract StakingTest is Test {
//     StakingRouter public staking;
//     NodeOperatorsRegistry public nodeModule;
//     GTETH public gteth;
//     GTETHLocator public locator;
//     MockDepositContract public depositContract;
    
//     // 测试账户
//     address public admin = address(0x1);
//     address public stakingModuleManager = address(0x2);
//     address public reportsManager = address(0x3);
//     address public nodeOperator1 = address(0x4);
//     address public nodeOperator2 = address(0x5);
//     address public user = address(0x6);
    
//     // 常量
//     bytes32 constant MODULE_TYPE = keccak256("test_module");
//     uint256 constant STUCK_PENALTY_DELAY = 7 days;
//     bytes32 constant WITHDRAWAL_CREDENTIALS = 0x010000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266;
    
//     // 角色常量
//     bytes32 constant MANAGE_WITHDRAWAL_CREDENTIALS_ROLE = keccak256("MANAGE_WITHDRAWAL_CREDENTIALS_ROLE");
//     bytes32 constant STAKING_MODULE_MANAGE_ROLE = keccak256("STAKING_MODULE_MANAGE_ROLE");
//     bytes32 constant REPORT_EXITED_VALIDATORS_ROLE = keccak256("REPORT_EXITED_VALIDATORS_ROLE");
//     bytes32 constant REPORT_REWARDS_MINTED_ROLE = keccak256("REPORT_REWARDS_MINTED_ROLE");
//     bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
//     function setUp() public {
//         // 部署 GTETH 合约 (upgradeable)
//         vm.prank(admin);
//         GTETH implementation = new GTETH();
//         TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
//             address(implementation),
//             admin,
//             ""
//         );
//         gteth = GTETH(payable(address(proxy)));
//         gteth.initialize("Test GTETH", "tGTETH", admin);

//         depositContract = new MockDepositContract();
        
//         // 部署 Staking 合约
//         vm.prank(admin);
//         staking = new StakingRouter(
//             admin,
//             address(gteth),
//             address(depositContract),
//             WITHDRAWAL_CREDENTIALS
//         );
        
//         // 部署 Node 模块
//         vm.prank(admin);
//         nodeModule = new NodeOperatorsRegistry(MODULE_TYPE, STUCK_PENALTY_DELAY);

//         // 部署 GTETHLocator 合约
//         IGTETHLocator.Config memory config = IGTETHLocator.Config({
//             gteth: address(gteth),
//             stakingRouter: address(staking),
//             nodeOperatorsRegistry: address(nodeModule),
//             withdrawalQueueERC721: address(0x100),
//             withdrawalVault: address(0x200),
//             accountingOracle: address(0x300),
//             elRewardsVault: address(0x400),
//             validatorsExitBusOracle: address(0x500),
//             treasury: address(0x600)
//         });
        
//         locator = new GTETHLocator(config);
        
//         // 设置定位器地址
//         vm.prank(admin);
//         nodeModule.setLocator(locator);
        
//         // 设置 GTETH 的定位器
//         vm.prank(admin);
//         gteth.setGTETHLocator(address(locator));
        
//         // 设置权限
//         vm.startPrank(admin);
//         staking.grantRole(STAKING_MODULE_MANAGE_ROLE, stakingModuleManager);
//         staking.grantRole(REPORT_EXITED_VALIDATORS_ROLE, reportsManager);
//         staking.grantRole(REPORT_REWARDS_MINTED_ROLE, reportsManager);
//         staking.grantRole(PAUSER_ROLE, admin);
        
//         // 为 Node 模块设置权限
//         nodeModule.grantRole(nodeModule.STAKING_ROUTER_ROLE(), address(staking));
//         nodeModule.grantRole(nodeModule.MANAGE_NODE_OPERATOR_ROLE(), admin);
//         nodeModule.grantRole(nodeModule.SET_NODE_OPERATOR_LIMIT_ROLE(), admin);
//         nodeModule.grantRole(nodeModule.MANAGE_SIGNING_KEYS(), admin);
//         vm.stopPrank();
        
//         // 给测试账户一些 ETH
//         vm.deal(address(gteth), 1000 ether);
//         vm.deal(admin, 1000 ether);
//         vm.deal(user, 1000 ether);
//     }
    
//     //
//     // 基础功能测试
//     //
    
//     function testGetGTETH() public view {
//         assertEq(staking.getGTETH(), address(gteth));
//     }
    
//     function testGetWithdrawalCredentials() public view {
//         assertEq(staking.getWithdrawalCredentials(), WITHDRAWAL_CREDENTIALS);
//     }
    
//     //
//     // 质押模块管理测试
//     //
    
//     function testAddStakingModule() public {
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, // 50% 份额限制
//             3000, // 30% 优先退出阈值
//             1000, // 10% 模块费用
//             500  // 5% 财库费用
//         );
        
//         assertEq(staking.stakingModulesCount(), 1);
//         assertEq(staking.lastStakingModuleId(), 1);
//         assertTrue(staking.hasStakingModule(1));
        
//         StakingRouter.StakingModule memory module = staking.getStakingModule(1);
//         assertEq(module.id, 1);
//         assertEq(module.name, "Test Module");
//         assertEq(module.stakingModuleAddress, address(nodeModule));
//         assertEq(module.stakeShareLimit, 5000);
//         assertEq(module.priorityExitShareThreshold, 3000);
//         assertEq(module.stakingModuleFee, 1000);
//         assertEq(module.treasuryFee, 500);
//         assertEq(uint256(module.status), uint256(StakingRouter.StakingModuleStatus.Active));
//     }
    
//     function testUpdateStakingModule() public {
//         // 先添加模块
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         // 更新模块参数
//         vm.prank(stakingModuleManager);
//         staking.updateStakingModule(
//             1,    // 模块ID
//             6000, // 新的份额限制
//             4000, // 新的优先退出阈值
//             1500, // 新的模块费用
//             800  // 新的财库费用
//         );
        
//         StakingRouter.StakingModule memory module = staking.getStakingModule(1);
//         assertEq(module.stakeShareLimit, 6000);
//         assertEq(module.priorityExitShareThreshold, 4000);
//         assertEq(module.stakingModuleFee, 1500);
//         assertEq(module.treasuryFee, 800);
//     }
    
//     function testSetStakingModuleStatus() public {
//         // 先添加模块
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         // 设置为暂停存款状态
//         vm.prank(stakingModuleManager);
//         staking.setStakingModuleStatus(1, StakingRouter.StakingModuleStatus.DepositsPaused);
        
//         assertEq(uint256(staking.getStakingModuleStatus(1)), uint256(StakingRouter.StakingModuleStatus.DepositsPaused));
//         assertTrue(staking.getStakingModuleIsDepositsPaused(1));
//         assertFalse(staking.getStakingModuleIsActive(1));
//         assertFalse(staking.getStakingModuleIsStopped(1));
        
//         // 设置为停止状态
//         vm.prank(stakingModuleManager);
//         staking.setStakingModuleStatus(1, StakingRouter.StakingModuleStatus.Stopped);
        
//         assertEq(uint256(staking.getStakingModuleStatus(1)), uint256(StakingRouter.StakingModuleStatus.Stopped));
//         assertTrue(staking.getStakingModuleIsStopped(1));
//         assertFalse(staking.getStakingModuleIsActive(1));
//         assertFalse(staking.getStakingModuleIsDepositsPaused(1));
//     }
    
//     function testGetStakingModules() public {
//         // 添加两个模块
//         vm.startPrank(stakingModuleManager);
//         staking.addStakingModule(
//             "Module 1",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         NodeOperatorsRegistry nodeModule2 = new NodeOperatorsRegistry(keccak256("module2"), STUCK_PENALTY_DELAY);
//         nodeModule2.setLocator(locator);
//         staking.addStakingModule(
//             "Module 2",
//             address(nodeModule2),
//             4000, 2000, 800, 400
//         );
//         vm.stopPrank();
        
//         StakingRouter.StakingModule[] memory modules = staking.getStakingModules();
//         assertEq(modules.length, 2);
//         assertEq(modules[0].name, "Module 1");
//         assertEq(modules[1].name, "Module 2");
//         assertEq(modules[0].id, 1);
//         assertEq(modules[1].id, 2);
//     }
    
//     //
//     // 存款功能测试
//     //
    
//     function testDeposit() public {
//         // 添加质押模块
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         // 在节点模块中添加运营商和密钥
//         vm.prank(admin);
//         uint256 operatorId = nodeModule.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 添加签名密钥
//         bytes memory pubkeys = new bytes(48);
//         bytes memory signatures = new bytes(96);
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId, 1, pubkeys, signatures);
        
//         // 设置质押限制
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId, 1);
        
//         // 执行存款
//         uint256 depositAmount = 32 ether;
//         vm.startPrank(address(gteth));
//         staking.deposit{value: depositAmount}(1, 1, "");
//         vm.stopPrank();
//     }
    
//     //
//     // 节点运营商管理测试
//     //
    
//     function testUpdateTargetValidatorsLimits() public {
//         // 添加质押模块
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         // 添加运营商
//         vm.prank(admin);
//         uint256 operatorId = nodeModule.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 更新目标验证者限制
//         vm.prank(stakingModuleManager);
//         staking.updateTargetValidatorsLimits(1, operatorId, 1, 10);
        
//         // 验证更新结果
//         StakingRouter.NodeOperatorSummary memory summary = staking.getNodeOperatorSummary(1, operatorId);
//         assertEq(summary.targetLimitMode, 1);
//         assertEq(summary.targetValidatorsCount, 10);
//     }
    
//     function testUpdateRefundedValidatorsCount() public {
//         // 添加质押模块
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         // 添加运营商并进行存款
//         vm.prank(admin);
//         uint256 operatorId = nodeModule.addNodeOperator("Test Operator", nodeOperator1);
        
//         bytes memory pubkeys = new bytes(48);
//         bytes memory signatures = new bytes(96);
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId, 1, pubkeys, signatures);
        
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId, 1);
        
//         vm.prank(address(staking));
//         nodeModule.obtainDepositData(1, "");
        
//         // 更新退款验证者数量
//         vm.prank(stakingModuleManager);
//         staking.updateRefundedValidatorsCount(1, operatorId, 1);
        
//         // 验证更新结果
//         StakingRouter.NodeOperatorSummary memory summary = staking.getNodeOperatorSummary(1, operatorId);
//         assertEq(summary.refundedValidatorsCount, 1);
//     }
    
//     //
//     // 验证者状态报告测试
//     //
    
//     function testUpdateExitedValidatorsCountByStakingModule() public {
//         // 添加质押模块
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         // 先添加运营商和验证者，并进行存款
//         vm.prank(admin);
//         uint256 operatorId = nodeModule.addNodeOperator("Test Operator", nodeOperator1);
        
//         bytes memory pubkeys = new bytes(240); // 5个48字节的公钥
//         bytes memory signatures = new bytes(480); // 5个96字节的签名
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId, 5, pubkeys, signatures);
        
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId, 5);
        
//         vm.prank(address(staking));
//         nodeModule.obtainDepositData(5, ""); // 存款5个验证者
        
//         uint256[] memory moduleIds = new uint256[](1);
//         moduleIds[0] = 1;
//         uint256[] memory exitedCounts = new uint256[](1);
//         exitedCounts[0] = 3; // 只退出3个验证者，不超过已存款数量
        
//         vm.prank(reportsManager);
//         uint256 newlyExited = staking.updateExitedValidatorsCountByStakingModule(moduleIds, exitedCounts);
        
//         assertEq(newlyExited, 3);
        
//         StakingRouter.StakingModule memory module = staking.getStakingModule(1);
//         assertEq(module.exitedValidatorsCount, 3);
//     }
    
//     function testReportStakingModuleExitedValidatorsCountByNodeOperator() public {
//         // 添加质押模块和运营商
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         vm.prank(admin);
//         uint256 operatorId = nodeModule.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 先添加验证者并进行存款
//         bytes memory pubkeys = new bytes(144); // 3个48字节的公钥
//         bytes memory signatures = new bytes(288); // 3个96字节的签名
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId, 3, pubkeys, signatures);
        
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId, 3);
        
//         vm.prank(address(staking));
//         nodeModule.obtainDepositData(3, ""); // 存款3个验证者
        
//         // 构造字节数据
//         bytes memory nodeOperatorIds = abi.encodePacked(uint64(operatorId));
//         bytes memory exitedValidatorsCounts = abi.encodePacked(uint128(2)); // 退出2个验证者
        
//         vm.prank(reportsManager);
//         staking.reportStakingModuleExitedValidatorsCountByNodeOperator(
//             1, 
//             nodeOperatorIds, 
//             exitedValidatorsCounts
//         );
        
//         // 验证通过节点运营商摘要可以看到更新
//         StakingRouter.NodeOperatorSummary memory summary = staking.getNodeOperatorSummary(1, operatorId);
//         assertEq(summary.totalExitedValidators, 2);
//     }
    
//     function testReportStakingModuleStuckValidatorsCountByNodeOperator() public {
//         // 添加质押模块和运营商
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         vm.prank(admin);
//         uint256 operatorId = nodeModule.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 先进行存款创建验证者
//         bytes memory pubkeys = new bytes(48);
//         bytes memory signatures = new bytes(96);
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId, 1, pubkeys, signatures);
        
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId, 1);
        
//         vm.prank(address(staking));
//         nodeModule.obtainDepositData(1, "");
        
//         // 构造字节数据
//         bytes memory nodeOperatorIds = abi.encodePacked(uint64(operatorId));
//         bytes memory stuckValidatorsCounts = abi.encodePacked(uint128(1));
        
//         vm.prank(reportsManager);
//         staking.reportStakingModuleStuckValidatorsCountByNodeOperator(
//             1, 
//             nodeOperatorIds, 
//             stuckValidatorsCounts
//         );
        
//         // 验证卡住验证者数量
//         StakingRouter.NodeOperatorSummary memory summary = staking.getNodeOperatorSummary(1, operatorId);
//         assertEq(summary.stuckValidatorsCount, 1);
//     }
    
//     function testOnValidatorsCountsByNodeOperatorReportingFinished() public {
//         // 添加质押模块
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         vm.prank(reportsManager);
//         staking.onValidatorsCountsByNodeOperatorReportingFinished();
        
//         // 验证没有错误发生
//         assertTrue(true);
//     }
    
//     function testDecreaseStakingModuleVettedKeysCountByNodeOperator() public {
//         // 添加质押模块和运营商
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         vm.prank(admin);
//         uint256 operatorId = nodeModule.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 添加签名密钥并设置限制
//         bytes memory pubkeys = new bytes(96); // 2个密钥
//         bytes memory signatures = new bytes(192);
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId, 2, pubkeys, signatures);
        
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId, 2);
        
//         // 减少审核密钥数量
//         bytes memory nodeOperatorIds = abi.encodePacked(uint64(operatorId));
//         bytes memory vettedSigningKeysCounts = abi.encodePacked(uint128(1));
        
//         vm.prank(stakingModuleManager);
//         staking.decreaseStakingModuleVettedKeysCountByNodeOperator(
//             1, 
//             nodeOperatorIds, 
//             vettedSigningKeysCounts
//         );
        
//         // 验证减少后的结果
//         (bool active, string memory name, address rewardAddress, uint64 totalVettedValidators,,,) = 
//             nodeModule.getNodeOperator(operatorId, true);
//         assertEq(active, true);
//         assertEq(name, "Test Operator");
//         assertEq(rewardAddress, nodeOperator1);
//         assertEq(totalVettedValidators, 1);
//     }
    
//     function testReportRewardsMinted() public {
//         // 添加质押模块
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         uint256[] memory moduleIds = new uint256[](1);
//         moduleIds[0] = 1;
//         uint256[] memory totalRewards = new uint256[](1);
//         totalRewards[0] = 100 ether;
        
//         vm.prank(reportsManager);
//         staking.reportRewardsMinted(moduleIds, totalRewards);
        
//         // 验证奖励状态更新
//         assertEq(
//             uint256(nodeModule.getRewardDistributionState()), 
//             uint256(NodeOperatorsRegistry.RewardDistributionState.TransferredToModule)
//         );
//     }
    
//     //
//     // 提取凭证管理测试
//     //
    
//     function testSetWithdrawalCredentials() public {
//         bytes32 newCredentials = 0x0200000000000000000000000000000000000000000000000000000000000002;
        
//         vm.prank(admin);
//         staking.setWithdrawalCredentials(newCredentials);
        
//         assertEq(staking.getWithdrawalCredentials(), newCredentials);
//     }
    
//     //
//     // 紧急控制测试
//     //
    
//     function testPauseAndUnpause() public {
//         vm.prank(admin);
//         staking.pause();
//         assertTrue(staking.paused());
        
//         vm.prank(admin);
//         staking.unpause();
//         assertFalse(staking.paused());
//     }
    
//     //
//     // 视图函数测试
//     //
    
//     function testGetStakingModuleActiveValidatorsCount() public {
//         // 添加质押模块和运营商
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         vm.prank(admin);
//         uint256 operatorId = nodeModule.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 进行存款
//         bytes memory pubkeys = new bytes(96); // 2个密钥
//         bytes memory signatures = new bytes(192);
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId, 2, pubkeys, signatures);
        
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId, 2);
        
//         vm.prank(address(staking));
//         nodeModule.obtainDepositData(2, "");
        
//         uint256 activeCount = staking.getStakingModuleActiveValidatorsCount(1);
//         assertEq(activeCount, 2);
//     }
    
//     function testGetDepositsAllocation() public {
//         // 添加第一个质押模块，份额限制为30%
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module 1",
//             address(nodeModule),
//             3000, // 30%份额限制
//             2000, // 20%优先退出阈值
//             1000, // 10%模块费用
//             500  // 5%财库费用
//         );

//         // 为第一个模块添加运营商和验证者（权限已在setUp中设置）
//         vm.prank(admin);
//         uint256 operatorId1 = nodeModule.addNodeOperator("Operator 1", nodeOperator1);
        
//         bytes memory pubkeys1 = new bytes(240); // 5个验证者
//         bytes memory signatures1 = new bytes(480);
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId1, 5, pubkeys1, signatures1);
        
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId1, 5);

//         // 添加第二个质押模块
//         NodeOperatorsRegistry nodeModule2 = new NodeOperatorsRegistry(keccak256("module2"), STUCK_PENALTY_DELAY);
//         nodeModule2.setLocator(locator);
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module 2",
//             address(nodeModule2),
//             5000, // 50%份额限制
//             3000, // 30%优先退出阈值
//             1000, // 10%模块费用
//             500  // 5%财库费用
//         );

//         // 为第二个模块设置权限
//         // 首先为新模块给予admin DEFAULT_ADMIN_ROLE权限（测试合约是当前管理员）
//         nodeModule2.grantRole(0x00, admin);  // DEFAULT_ADMIN_ROLE
        
//         vm.startPrank(admin);
//         nodeModule2.grantRole(nodeModule2.STAKING_ROUTER_ROLE(), address(staking));
//         nodeModule2.grantRole(nodeModule2.MANAGE_NODE_OPERATOR_ROLE(), admin);
//         nodeModule2.grantRole(nodeModule2.SET_NODE_OPERATOR_LIMIT_ROLE(), admin);
//         nodeModule2.grantRole(nodeModule2.MANAGE_SIGNING_KEYS(), admin);
//         vm.stopPrank();
        
//         // 为第二个模块添加运营商和验证者
//         vm.prank(admin);
//         uint256 operatorId2 = nodeModule2.addNodeOperator("Operator 2", nodeOperator2);
        
//         bytes memory pubkeys2 = new bytes(240); // 5个验证者
//         bytes memory signatures2 = new bytes(480);
//         vm.prank(nodeOperator2);
//         nodeModule2.addSigningKeys(operatorId2, 5, pubkeys2, signatures2);
        
//         vm.prank(admin);
//         nodeModule2.setNodeOperatorStakingLimit(operatorId2, 5);

//         // 添加第三个质押模块，份额限制为20%
//         NodeOperatorsRegistry nodeModule3 = new NodeOperatorsRegistry(keccak256("module3"), STUCK_PENALTY_DELAY);
//         nodeModule3.setLocator(locator);
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module 3",
//             address(nodeModule3),
//             2000, // 20%份额限制
//             1000, // 10%优先退出阈值
//             1000, // 10%模块费用
//             500  // 5%财库费用
//         );

//         // 为第三个模块设置权限
//         // 首先为新模块给予admin DEFAULT_ADMIN_ROLE权限（测试合约是当前管理员）
//         nodeModule3.grantRole(0x00, admin);  // DEFAULT_ADMIN_ROLE
        
//         vm.startPrank(admin);
//         nodeModule3.grantRole(nodeModule3.STAKING_ROUTER_ROLE(), address(staking));
//         nodeModule3.grantRole(nodeModule3.MANAGE_NODE_OPERATOR_ROLE(), admin);
//         nodeModule3.grantRole(nodeModule3.SET_NODE_OPERATOR_LIMIT_ROLE(), admin);
//         nodeModule3.grantRole(nodeModule3.MANAGE_SIGNING_KEYS(), admin);
//         vm.stopPrank();
        
//         // 为第三个模块添加运营商和验证者
//         vm.prank(admin);
//         uint256 operatorId3 = nodeModule3.addNodeOperator("Operator 3", address(0x7));
        
//         bytes memory pubkeys3 = new bytes(144); // 3个验证者
//         bytes memory signatures3 = new bytes(288);
//         vm.prank(address(0x7));
//         nodeModule3.addSigningKeys(operatorId3, 3, pubkeys3, signatures3);
        
//         vm.prank(admin);
//         nodeModule3.setNodeOperatorStakingLimit(operatorId3, 3);
         
//         // 测试分配10个存款
//         (uint256 allocated, uint256[] memory allocations) = staking.getDepositsAllocation(10);
        
//         // 验证分配结果
//         assertEq(allocated, 10, unicode"应该分配所有10个存款");
//         assertEq(allocations.length, 3, unicode"应该有3个模块的分配结果");
        
//         // 验证分配总和等于请求的存款数
//         uint256 totalAllocated = allocations[0] + allocations[1] + allocations[2];
//         assertEq(totalAllocated, 10, unicode"分配总和应该等于请求的存款数");
        
//         // 验证每个模块都有非零分配（所有模块都有可用验证者）
//         assertGt(allocations[0], 0, unicode"模块1应该有分配");
//         assertGt(allocations[1], 0, unicode"模块2应该有分配"); 
//         assertGt(allocations[2], 0, unicode"模块3应该有分配");
        
//         // 验证分配不超过可用验证者数量
//         assertLe(allocations[0], 5, unicode"模块1分配不应超过可用验证者数量");
//         assertLe(allocations[1], 5, unicode"模块2分配不应超过可用验证者数量");
//         assertLe(allocations[2], 3, unicode"模块3分配不应超过可用验证者数量");
         
//         // 测试大量存款分配
//         (uint256 allocated2, uint256[] memory allocations2) = staking.getDepositsAllocation(20);
        
//         // 由于总可用验证者为13个（5+5+3），实际分配应该是13
//         assertEq(allocated2, 13, unicode"实际分配应该受限于可用验证者数量");
//         assertEq(allocations2[0] + allocations2[1] + allocations2[2], 13, unicode"总分配应该是13");
        
//         // 测试零存款情况
//         (uint256 allocated3, uint256[] memory allocations3) = staking.getDepositsAllocation(0);
//         assertEq(allocated3, 0, unicode"零存款应该返回零分配");
//         assertEq(allocations3[0] + allocations3[1] + allocations3[2], 0, unicode"所有模块分配都应该是零");
//     }
    
//     function testGetStakingModuleSummary() public {
//         // 添加质押模块和运营商
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         vm.prank(admin);
//         uint256 operatorId = nodeModule.addNodeOperator("Test Operator", nodeOperator1);
        
//         bytes memory pubkeys = new bytes(48);
//         bytes memory signatures = new bytes(96);
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId, 1, pubkeys, signatures);
        
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId, 1);
        
//         StakingRouter.StakingModuleSummary memory summary = staking.getStakingModuleSummary(1);
//         assertEq(summary.depositableValidatorsCount, 1);
//     }
    
//     function testGetStakingModuleNonce() public {
//         // 添加质押模块
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         // 先添加运营商并进行操作以增加nonce
//         vm.prank(admin);
//         uint256 operatorId = nodeModule.addNodeOperator("Test Operator", nodeOperator1);
        
//         bytes memory pubkeys = new bytes(48);
//         bytes memory signatures = new bytes(96);
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId, 1, pubkeys, signatures);
        
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId, 1);
        
//         uint256 nonce = staking.getStakingModuleNonce(1);
//         assertGt(nonce, 1); // nonce 应该大于 1，因为进行了操作
//     }
    
//     function testGetStakingModuleLastDepositBlock() public {
//         // 添加质押模块
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
//     }
    
//     function testGetStakingModuleMaxDepositsCount() public {
//         // 添加质押模块，100%份额限制以允许完全分配
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             10000, 5000, 1000, 500  // 100%份额限制
//         );
        
//         // 添加运营商和验证者以使模块有可用验证者
//         vm.prank(admin);
//         uint256 operatorId = nodeModule.addNodeOperator("Test Operator", nodeOperator1);
        
//         bytes memory pubkeys = new bytes(480); // 10个验证者
//         bytes memory signatures = new bytes(960);
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId, 10, pubkeys, signatures);
        
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId, 10);
        
//         uint256 maxCount = staking.getStakingModuleMaxDepositsCount(1, 320 ether); // 10个存款
//         assertEq(maxCount, 10);
//     }
    
//     function testGetStakingRewardsDistribution() public {
//         // 添加质押模块
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         // 添加运营商和活跃验证者
//         vm.prank(admin);
//         uint256 operatorId = nodeModule.addNodeOperator("Test Operator", nodeOperator1);
        
//         bytes memory pubkeys = new bytes(48);
//         bytes memory signatures = new bytes(96);
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId, 1, pubkeys, signatures);
        
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId, 1);
        
//         // 模拟存款以创建活跃验证者
//         vm.prank(address(staking));
//         nodeModule.obtainDepositData(1, "");
        
//         (
//             address[] memory recipients,
//             uint256[] memory stakingModuleIds,
//             uint96[] memory stakingModuleFees,
//             uint96 totalFee,
//             uint256 precisionPoints
//         ) = staking.getStakingRewardsDistribution();
        
//         assertEq(recipients.length, 1);
//         assertEq(recipients[0], address(nodeModule));
//         assertEq(stakingModuleIds[0], 1);
        
//         // 新实现基于验证者比例计算费用
//         // 单个验证者占100%，所以费用是 (1验证者 * 精度) * 模块费率 / 基点
//         uint256 expectedModuleFee = (1 * precisionPoints * 1000) / 10000;
//         uint256 expectedTotalFee = (1 * precisionPoints * (1000 + 500)) / 10000;
        
//         assertEq(stakingModuleFees[0], expectedModuleFee);
//         assertEq(totalFee, expectedTotalFee);
//         assertEq(precisionPoints, 10 ** 20);
//     }
    
//     //
//     // 错误情况测试
//     //
    
//     function testReceiveFails() public {
//         vm.expectRevert(StakingRouter.DirectETHTransfer.selector);
//         (bool success, ) = address(staking).call{value: 1 ether}("");
//         // 因为revert了，success应该是false，但这里我们不需要检查success
//         // 只需要验证revert确实发生了
//     }
    
//     function testAddStakingModuleFailsWithUnauthorized() public {
//         vm.prank(user);
//         vm.expectRevert();
//         staking.addStakingModule(
//             "Test Module",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
//     }
    
//     function testDepositFailsWithWrongCaller() public {
//         vm.prank(user);
//         vm.expectRevert();
//         staking.deposit{value: 32 ether}(1, 1, "");
//     }
    
//     function testPauseFailsWithUnauthorized() public {
//         vm.prank(user);
//         vm.expectRevert();
//         staking.pause();
//     }
    
//     //
//     // 边界情况测试
//     //
    
//     function testMultipleStakingModules() public {
//         // 添加多个质押模块
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Module 1",
//             address(nodeModule),
//             5000, 3000, 1000, 500
//         );
        
//         // 在prank之外创建第二个模块，以保持测试合约为管理员
//         NodeOperatorsRegistry nodeModule2 = new NodeOperatorsRegistry(keccak256("module2"), STUCK_PENALTY_DELAY);
//         nodeModule2.setLocator(locator);
//         vm.prank(stakingModuleManager);
//         staking.addStakingModule(
//             "Module 2",
//             address(nodeModule2),
//             4000, 2000, 800, 400
//         );
        
//         // 为第二个模块设置权限（第一个模块在setUp中已有权限）
//         // 为新模块给予admin DEFAULT_ADMIN_ROLE权限（测试合约是当前管理员）
//         nodeModule2.grantRole(0x00, admin);  // DEFAULT_ADMIN_ROLE
        
//         vm.startPrank(admin);
//         nodeModule2.grantRole(nodeModule2.STAKING_ROUTER_ROLE(), address(staking));
//         nodeModule2.grantRole(nodeModule2.MANAGE_NODE_OPERATOR_ROLE(), admin);
//         nodeModule2.grantRole(nodeModule2.SET_NODE_OPERATOR_LIMIT_ROLE(), admin);
//         nodeModule2.grantRole(nodeModule2.MANAGE_SIGNING_KEYS(), admin);
//         vm.stopPrank();
        
//         // 为两个模块添加运营商和验证者
//         vm.prank(admin);
//         uint256 operatorId1 = nodeModule.addNodeOperator("Operator 1", nodeOperator1);
        
//         bytes memory pubkeys1 = new bytes(480); // 10个验证者
//         bytes memory signatures1 = new bytes(960);
//         vm.prank(nodeOperator1);
//         nodeModule.addSigningKeys(operatorId1, 10, pubkeys1, signatures1);
        
//         vm.prank(admin);
//         nodeModule.setNodeOperatorStakingLimit(operatorId1, 10);
        
//         vm.prank(admin);
//         uint256 operatorId2 = nodeModule2.addNodeOperator("Operator 2", nodeOperator2);
        
//         bytes memory pubkeys2 = new bytes(480); // 10个验证者
//         bytes memory signatures2 = new bytes(960);
//         vm.prank(nodeOperator2);
//         nodeModule2.addSigningKeys(operatorId2, 10, pubkeys2, signatures2);
        
//         vm.prank(admin);
//         nodeModule2.setNodeOperatorStakingLimit(operatorId2, 10);
        
//         assertEq(staking.stakingModulesCount(), 2);
//         assertTrue(staking.hasStakingModule(1));
//         assertTrue(staking.hasStakingModule(2));
//         assertFalse(staking.hasStakingModule(3));
        
//         // 测试分配（总可用验证者：10+10=20个）
//         (uint256 allocated, uint256[] memory allocations) = staking.getDepositsAllocation(20);
        
//         // 在50%和40%的份额限制下，以及20个总可用验证者的情况下，
//         // 分配应该受份额限制而非可用验证者数量限制
//         uint256 totalAllocated = allocations[0] + allocations[1];
//         assertEq(allocated, totalAllocated);
//         assertEq(allocations.length, 2);
//         // 由于我们有足够的验证者，但份额限制可能会限制分配
//         assertLe(totalAllocated, 20, unicode"不应超过可用验证者数量");
//         assertGt(totalAllocated, 0, unicode"应该分配一些验证者");
//     }
// }
