// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.30;

// import {Test} from "forge-std/Test.sol";
// import {NodeOperatorsRegistry} from "../src/NodeOperatorsRegistry.sol";
// import {INodeOperatorsRegistry} from "../src/interfaces/INodeOperatorsRegistry.sol";
// import {IGTETHLocator} from "../src/interfaces/IGTETHLocator.sol";
// import {IGTETH} from "../src/interfaces/IGTETH.sol";
// import {GTETH} from "../src/GTETH.sol";
// import {GTETHLocator} from "../src/GTETHLocator.sol";
// import {console} from "forge-std/console.sol";
// import {StakingRouter} from "../src/StakingRouter.sol";
// import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// contract NodeTest is Test {
//     NodeOperatorsRegistry public node;
//     GTETH public gteth;
//     GTETHLocator public locator;
    
//     // 测试账户
//     address public admin = address(0x1);
//     address public stakingRouter;
//     address public nodeOperator1 = address(0x3);
//     address public nodeOperator2 = address(0x4);
//     address public user = address(0x5);
    
//     // 常量
//     bytes32 constant MODULE_TYPE = keccak256("test_module");
//     uint256 constant STUCK_PENALTY_DELAY = 7 days;
    
//     // 角色常量
//     bytes32 constant MANAGE_SIGNING_KEYS = keccak256("MANAGE_SIGNING_KEYS");
//     bytes32 constant SET_NODE_OPERATOR_LIMIT_ROLE = keccak256("SET_NODE_OPERATOR_LIMIT_ROLE");
//     bytes32 constant MANAGE_NODE_OPERATOR_ROLE = keccak256("MANAGE_NODE_OPERATOR_ROLE");
//     bytes32 constant STAKING_ROUTER_ROLE = keccak256("STAKING_ROUTER_ROLE");
//     bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

//     address constant DEPOSIT_CONTRACT = 0x4242424242424242424242424242424242424242; //sepolia deposit contract
//     bytes32 constant WITHDRAWAL_CREDENTIALS = 0x010000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266;
    
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
        
//         // 部署Node合约
//         vm.prank(admin);
//         node = new NodeOperatorsRegistry(MODULE_TYPE, STUCK_PENALTY_DELAY);

//         // 部署StakingRouter合约
//         vm.prank(admin);
//         stakingRouter = address(new StakingRouter(
//             admin,
//             address(gteth),
//             DEPOSIT_CONTRACT,
//             WITHDRAWAL_CREDENTIALS
//         ));

//         // 部署 GTETHLocator 合约
//         IGTETHLocator.Config memory config = IGTETHLocator.Config({
//             gteth: address(gteth),
//             stakingRouter: stakingRouter,
//             nodeOperatorsRegistry: address(node), // 将在后面设置
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
//         node.setLocator(IGTETHLocator(address(locator)));
        
//         // 设置 GTETH 的定位器
//         vm.prank(admin);
//         gteth.setGTETHLocator(address(locator));
        
//         // 设置角色权限
//         vm.startPrank(admin);
//         node.grantRole(MANAGE_NODE_OPERATOR_ROLE, admin);
//         node.grantRole(SET_NODE_OPERATOR_LIMIT_ROLE, admin);
//         node.grantRole(STAKING_ROUTER_ROLE, stakingRouter);
//         node.grantRole(MANAGE_SIGNING_KEYS, admin);
//         vm.stopPrank();
//     }
    
//     //
//     // 测试节点运营商管理函数
//     //
    
//     function testAddNodeOperator() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         assertEq(operatorId, 0);
//         assertEq(node.getNodeOperatorsCount(), 1);
//         assertEq(node.getActiveNodeOperatorsCount(), 1);
//         assertTrue(node.getNodeOperatorIsActive(operatorId));
        
//         (bool active, string memory name, address rewardAddress,,,,) = node.getNodeOperator(operatorId, true);
//         assertTrue(active);
//         assertEq(name, "Test Operator");
//         assertEq(rewardAddress, nodeOperator1);
        
//         // 添加第二个运营商验证ID递增
//         vm.prank(admin);
//         uint256 operatorId2 = node.addNodeOperator("Test Operator 2", nodeOperator2);
//         assertEq(operatorId2, 1);
//         assertEq(node.getNodeOperatorsCount(), 2);
//         assertEq(node.getActiveNodeOperatorsCount(), 2);
//     }
    
//     function testAddNodeOperatorFailsWithInvalidName() public {
//         vm.prank(admin);
//         vm.expectRevert();
//         node.addNodeOperator("", nodeOperator1); // 空名称应该失败
//     }
    
//     function testAddNodeOperatorFailsWithZeroAddress() public {
//         vm.prank(admin);
//         vm.expectRevert();
//         node.addNodeOperator("Test Operator", address(0)); // 零地址应该失败
//     }
    
//     function testAddNodeOperatorFailsWithUnauthorized() public {
//         vm.prank(user);
//         vm.expectRevert();
//         node.addNodeOperator("Test Operator", nodeOperator1); // 无权限用户应该失败
//     }
    
//     function testActivateNodeOperator() public {
//         // 先添加一个运营商
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 停用运营商
//         vm.prank(admin);
//         node.deactivateNodeOperator(operatorId);
//         assertFalse(node.getNodeOperatorIsActive(operatorId));
        
//         // 重新激活运营商
//         vm.prank(admin);
//         node.activateNodeOperator(operatorId);
//         assertTrue(node.getNodeOperatorIsActive(operatorId));
//     }
    
//     function testActivateNodeOperatorFailsIfAlreadyActive() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         vm.prank(admin);
//         vm.expectRevert();
//         node.activateNodeOperator(operatorId); // 已经激活的运营商应该失败
//     }
    
//     function testDeactivateNodeOperator() public {
//         // 添加两个运营商
//         vm.prank(admin);
//         uint256 operatorId1 = node.addNodeOperator("Test Operator 1", nodeOperator1);
//         vm.prank(admin);
//         uint256 operatorId2 = node.addNodeOperator("Test Operator 2", nodeOperator2);
        
//         assertEq(node.getActiveNodeOperatorsCount(), 2);
        
//         vm.prank(admin);
//         node.deactivateNodeOperator(operatorId1);
//         assertFalse(node.getNodeOperatorIsActive(operatorId1));
//         assertTrue(node.getNodeOperatorIsActive(operatorId2)); // 第二个运营商仍然活跃
//         assertEq(node.getActiveNodeOperatorsCount(), 1); // 还有一个活跃运营商
//     }
    
//     function testDeactivateNodeOperatorFailsIfNotActive() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         vm.prank(admin);
//         node.deactivateNodeOperator(operatorId);
        
//         vm.prank(admin);
//         vm.expectRevert();
//         node.deactivateNodeOperator(operatorId); // 已停用的运营商应该失败
//     }
    
//     function testSetNodeOperatorName() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         vm.prank(admin);
//         node.setNodeOperatorName(operatorId, "New Name");
        
//         (,string memory name,,,,,) = node.getNodeOperator(operatorId, true);
//         assertEq(name, "New Name");
//     }
    
//     function testSetNodeOperatorNameFailsWithSameName() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         vm.prank(admin);
//         vm.expectRevert();
//         node.setNodeOperatorName(operatorId, "Test Operator"); // 相同名称应该失败
//     }
    
//     function testSetNodeOperatorRewardAddress() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         vm.prank(admin);
//         node.setNodeOperatorRewardAddress(operatorId, nodeOperator2);
        
//         (,,address rewardAddress,,,,) = node.getNodeOperator(operatorId, false);
//         assertEq(rewardAddress, nodeOperator2);
//     }
    
//     function testSetNodeOperatorRewardAddressFailsWithSameAddress() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         vm.prank(admin);
//         vm.expectRevert();
//         node.setNodeOperatorRewardAddress(operatorId, nodeOperator1); // 相同地址应该失败
//     }
    
//     function testSetNodeOperatorStakingLimit() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 先添加一些签名密钥
//         bytes memory pubkeys = new bytes(480); // 10个48字节的公钥
//         bytes memory signatures = new bytes(960); // 10个96字节的签名
        
//         vm.prank(nodeOperator1);
//         node.addSigningKeys(operatorId, 10, pubkeys, signatures);
        
//         // 现在设置质押限制
//         vm.prank(admin);
//         node.setNodeOperatorStakingLimit(operatorId, 5);
        
//         // 验证限制已设置（通过获取运营商信息）
//         (,,,uint64 totalVettedValidators,,,) = node.getNodeOperator(operatorId, false);
//         assertEq(totalVettedValidators, 5);
//     }
    
//     function testSetNodeOperatorStakingLimitFailsIfNotActive() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         vm.prank(admin);
//         node.deactivateNodeOperator(operatorId);
        
//         vm.prank(admin);
//         vm.expectRevert();
//         node.setNodeOperatorStakingLimit(operatorId, 10); // 非活跃运营商应该失败
//     }
    
//     //
//     // 测试签名密钥管理函数
//     //
    
//     function testAddSigningKeys() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 生成测试密钥数据
//         bytes memory pubkeys = new bytes(48); // 1个48字节的公钥
//         bytes memory signatures = new bytes(96); // 1个96字节的签名
        
//         // 用运营商的奖励地址来调用addSigningKeys
//         vm.prank(nodeOperator1);
//         node.addSigningKeys(operatorId, 1, pubkeys, signatures);
        
//         (,,, uint64 totalVettedValidators,, uint64 totalAddedValidators,) = node.getNodeOperator(operatorId, false);
//         assertEq(totalAddedValidators, 1);
//         // 新添加的密钥默认未审核，直接设置质押限制使其被审核

//         vm.prank(admin);
//         node.setNodeOperatorStakingLimit(operatorId, 1); // 通过setNodeOperatorStakingLimit审核密钥

//         (,,, uint64 totalVettedValidators1,, uint64 totalAddedValidators1,) = node.getNodeOperator(operatorId, false);
//         assertEq(totalAddedValidators1, 1);
//         assertEq(totalVettedValidators1, 1); // 现在密钥被审核了
//     }
    
//     function testAddSigningKeysFailsWithInvalidData() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         bytes memory pubkeys = new bytes(47); // 错误的长度
//         bytes memory signatures = new bytes(96);
        
//         vm.prank(admin);
//         vm.expectRevert();
//         node.addSigningKeys(operatorId, 1, pubkeys, signatures); // 错误的密钥长度应该失败
//     }
    
//     function testGetSigningKey() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         bytes memory pubkeys = new bytes(48);
//         bytes memory signatures = new bytes(96);
        
//         vm.prank(admin);
//         node.addSigningKeys(operatorId, 1, pubkeys, signatures);
        
//         (bytes memory key, bytes memory sig, bool used) = node.getSigningKey(operatorId, 0);
//         assertEq(key.length, 48);
//         assertEq(sig.length, 96);
//         assertFalse(used); // 新添加的密钥未使用
//     }
    
//     function testGetSigningKeys() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         bytes memory pubkeys = new bytes(96); // 2个公钥
//         bytes memory signatures = new bytes(192); // 2个签名
        
//         vm.prank(admin);
//         node.addSigningKeys(operatorId, 2, pubkeys, signatures);
        
//         (bytes memory keys, bytes memory sigs, bool[] memory used) = node.getSigningKeys(operatorId, 0, 2);
//         assertEq(keys.length, 96);
//         assertEq(sigs.length, 192);
//         assertEq(used.length, 2);
//         assertFalse(used[0]);
//         assertFalse(used[1]);
//     }
    
//     //
//     // 测试验证者状态管理函数
//     //
    
//     function testOnRewardsMinted() public {
//         vm.prank(stakingRouter);
//         node.onRewardsMinted();
        
//         assertEq(uint256(node.getRewardDistributionState()), uint256(NodeOperatorsRegistry.RewardDistributionState.TransferredToModule));
//     }
    
//     function testOnRewardsMintedFailsWithUnauthorized() public {
//         vm.prank(user);
//         vm.expectRevert();
//         node.onRewardsMinted(); // 无权限用户应该失败
//     }
    
//     function testOnExitedAndStuckValidatorsCountsUpdated() public {
//         vm.prank(stakingRouter);
//         node.onExitedAndStuckValidatorsCountsUpdated();
        
//         assertEq(uint256(node.getRewardDistributionState()), uint256(NodeOperatorsRegistry.RewardDistributionState.ReadyForDistribution));
//     }
    
//     function testDistributeReward() public {
//         // 设置奖励状态为准备分发
//         vm.prank(stakingRouter);
//         node.onExitedAndStuckValidatorsCountsUpdated();
        
//         // 给Node合约一些GTETH代币 - 通过 submit 获取代币然后转账
//         vm.deal(admin, 1000 ether);
//         vm.prank(admin);
//         gteth.submit{value: 1000 ether}();
        
//         // 获取实际余额并转账给node合约
//         uint256 balance = gteth.balanceOf(admin);
//         vm.prank(admin);
//         gteth.transfer(address(node), balance);
        
//         node.distributeReward();
        
//         assertEq(uint256(node.getRewardDistributionState()), uint256(NodeOperatorsRegistry.RewardDistributionState.Distributed));
//     }
    
//     function testDistributeRewardFailsIfNotReady() public {
//         vm.expectRevert();
//         node.distributeReward(); // 状态不正确应该失败
//     }
    
//     //
//     // 测试查询函数
//     //
    
//     function testGetType() public view {
//         assertEq(node.getType(), MODULE_TYPE);
//     }
    
//     function testGetNodeOperatorsCount() public {
//         // 先添加一个运营商
//         vm.prank(admin);
//         node.addNodeOperator("Test Operator 1", nodeOperator1);
//         assertEq(node.getNodeOperatorsCount(), 1);
        
//         vm.prank(admin);
//         node.addNodeOperator("Test Operator 2", nodeOperator2);
//         assertEq(node.getNodeOperatorsCount(), 2);
        
//         // 添加第三个运营商验证计数递增
//         vm.prank(admin);
//         node.addNodeOperator("Test Operator 3", address(0x7));
//         assertEq(node.getNodeOperatorsCount(), 3);
//     }
    
//     function testGetActiveNodeOperatorsCount() public {
//         // 先添加第一个运营商
//         vm.prank(admin);
//         uint256 operatorId1 = node.addNodeOperator("Test Operator 1", nodeOperator1);
//         assertEq(node.getActiveNodeOperatorsCount(), 1);
        
//         vm.prank(admin);
//         node.addNodeOperator("Test Operator 2", nodeOperator2);
//         assertEq(node.getActiveNodeOperatorsCount(), 2);
        
//         // 添加第三个运营商
//         vm.prank(admin);
//         node.addNodeOperator("Test Operator 3", address(0x7));
//         assertEq(node.getActiveNodeOperatorsCount(), 3);
        
//         vm.prank(admin);
//         node.deactivateNodeOperator(operatorId1);
//         assertEq(node.getActiveNodeOperatorsCount(), 2); // 还有两个活跃运营商
//     }
    
//     function testGetNodeOperatorIsActive() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         assertTrue(node.getNodeOperatorIsActive(operatorId));
        
//         vm.prank(admin);
//         node.deactivateNodeOperator(operatorId);
//         assertFalse(node.getNodeOperatorIsActive(operatorId));
//     }
    
//     function testIsOperatorPenalized() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         assertFalse(node.isOperatorPenalized(operatorId)); // 新运营商未被惩罚
//     }
    
//     function testIsOperatorPenaltyCleared() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         assertTrue(node.isOperatorPenaltyCleared(operatorId)); // 新运营商惩罚已清除
//     }
    
//     function testOperatorPenalizedRewardReduction() public {
//         // 添加运营商
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 添加一些签名密钥
//         bytes memory pubkeys = new bytes(48);
//         bytes memory signatures = new bytes(96);
//         vm.prank(nodeOperator1);
//         node.addSigningKeys(operatorId, 1, pubkeys, signatures);
        
//         // 设置质押限制，使运营商有可存款的验证者
//         vm.prank(admin);
//         node.setNodeOperatorStakingLimit(operatorId, 1);
        
//         // 模拟存款：通过质押路由器获取存款数据来增加已存款验证者数量
//         vm.prank(stakingRouter);
//         node.obtainDepositData(1, "");
        
//         // 设置卡住验证者数量，使运营商处于惩罚状态
//         // 构造字节数据：operatorId (8 bytes) + stuckCount (16 bytes)  
//         bytes memory nodeOperatorIds = abi.encodePacked(uint64(operatorId));
//         bytes memory stuckValidatorsCounts = abi.encodePacked(uint128(1)); // 1个卡住验证者
        
//         vm.prank(stakingRouter);
//         node.updateStuckValidatorsCount(nodeOperatorIds, stuckValidatorsCounts);
        
//         // 验证运营商确实被惩罚了
//         assertTrue(node.isOperatorPenalized(operatorId)); // 运营商应该被惩罚
        
//         // 给Node合约一些GTETH代币进行奖励分配
//         uint256 totalReward = 1000 ether;
//         vm.deal(admin, totalReward);
//         vm.prank(admin);
//         gteth.submit{value: totalReward}();
        
//         // 获取实际余额并转账给node合约
//         uint256 balance = gteth.balanceOf(admin);
//         vm.prank(admin);
//         gteth.transfer(address(node), balance);
        
//         // 获取奖励分配方案
//         (address[] memory recipients, uint256[] memory amounts, bool[] memory penalized) = 
//             node.getRewardsDistribution(balance);
        
//         // 验证分配结果
//         assertEq(recipients.length, 1);
//         assertEq(recipients[0], nodeOperator1);
//         assertTrue(penalized[0]); // 运营商被标记为惩罚状态
        
//         // 计算期望的奖励：因为只有一个运营商且有1个活跃验证者，正常情况下应该获得全部奖励
//         // 但由于被惩罚，奖励应该减半
//         uint256 expectedReward = balance; // 基础奖励（未惩罚时）
//         uint256 expectedPenalizedReward = expectedReward / 2; // 惩罚后减半
        
//         assertEq(amounts[0], expectedReward); // getRewardsDistribution返回的是未处理的金额
        
//         // 设置奖励分发状态并进行实际分发
//         vm.prank(stakingRouter);
//         node.onExitedAndStuckValidatorsCountsUpdated();
        
//         // 记录分发前的余额
//         uint256 balanceBefore = gteth.balanceOf(nodeOperator1);
        
//         // 执行奖励分发
//         node.distributeReward();
        
//         // 验证运营商实际收到的奖励是减半的
//         uint256 balanceAfter = gteth.balanceOf(nodeOperator1);
//         uint256 actualReward = balanceAfter - balanceBefore;
        
//         assertEq(actualReward, expectedPenalizedReward); // 实际奖励应该是减半的
        
//         // 验证奖励分发状态
//         assertEq(uint256(node.getRewardDistributionState()), uint256(NodeOperatorsRegistry.RewardDistributionState.Distributed));
//     }

//     function testGetNonce() public {
//         uint256 initialNonce = node.getNonce();
        
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 设置质押限制会增加nonce
//         vm.prank(admin);
//         node.setNodeOperatorStakingLimit(operatorId, 5);
        
//         // 设置质押限制应该增加nonce
//         assertGt(node.getNonce(), initialNonce);
//     }
    
//     function testGetStuckPenaltyDelay() public view {
//         assertEq(node.getStuckPenaltyDelay(), STUCK_PENALTY_DELAY);
//     }
    
//     function testSetStuckPenaltyDelay() public {
//         uint256 newDelay = 14 days;
        
//         vm.prank(admin);
//         node.setStuckPenaltyDelay(newDelay);
        
//         assertEq(node.getStuckPenaltyDelay(), newDelay);
//     }
    
//     function testSetStuckPenaltyDelayFailsWithUnauthorized() public {
//         vm.prank(user);
//         vm.expectRevert();
//         node.setStuckPenaltyDelay(14 days); // 无权限用户应该失败
//     }
    
//     function testGetRewardDistributionState() public view {
//         assertEq(uint256(node.getRewardDistributionState()), uint256(NodeOperatorsRegistry.RewardDistributionState.Distributed));
//     }
    
//     function testGetRewardsDistribution() public {
//         // 添加一个运营商并设置活跃验证者
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 添加签名密钥并进行存款以创建活跃验证者
//         bytes memory pubkeys = new bytes(96); // 2个48字节的公钥
//         bytes memory signatures = new bytes(192); // 2个96字节的签名
//         vm.prank(nodeOperator1);
//         node.addSigningKeys(operatorId, 2, pubkeys, signatures);
        
//         vm.prank(admin);
//         node.setNodeOperatorStakingLimit(operatorId, 2);
        
//         vm.prank(stakingRouter);
//         node.obtainDepositData(2, ""); // 创建2个活跃验证者
        
//         (address[] memory recipients, uint256[] memory amounts, bool[] memory penalized) = 
//             node.getRewardsDistribution(1000 ether);
        
//         assertEq(recipients.length, 1);
//         assertEq(amounts.length, 1);
//         assertEq(penalized.length, 1);
//         assertEq(recipients[0], nodeOperator1);
//         assertEq(amounts[0], 1000 ether); // 有活跃验证者时获得全部奖励
//         assertFalse(penalized[0]);
//     }
    
//     function testGetStakingModuleSummary() public {
//         // 添加运营商和验证者
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         bytes memory pubkeys = new bytes(144); // 3个48字节的公钥
//         bytes memory signatures = new bytes(288); // 3个96字节的签名
//         vm.prank(nodeOperator1);
//         node.addSigningKeys(operatorId, 3, pubkeys, signatures);
        
//         vm.prank(admin);
//         node.setNodeOperatorStakingLimit(operatorId, 2); // 只审核2个
        
//         (uint256 totalExitedValidators, uint256 totalDepositedValidators, uint256 depositableValidatorsCount) = 
//             node.getStakingModuleSummary();
        
//         // 验证结果
//         assertEq(totalExitedValidators, 0); // 暂时保留，因为没有退出的验证者
//         assertEq(totalDepositedValidators, 0); // 暂时保留，因为没有存款
//         assertEq(depositableValidatorsCount, 2); // 有2个可存款的验证者
//     }
    
//     function testGetNodeOperatorSummary() public {
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         // 添加验证者密钥
//         bytes memory pubkeys = new bytes(96); // 2个48字节的公钥
//         bytes memory signatures = new bytes(192); // 2个96字节的签名
//         vm.prank(nodeOperator1);
//         node.addSigningKeys(operatorId, 2, pubkeys, signatures);
        
//         vm.prank(admin);
//         node.setNodeOperatorStakingLimit(operatorId, 2);
        
//         (
//             uint256 targetLimitMode,
//             uint256 targetValidatorsCount,
//             uint256 stuckValidatorsCount,
//             uint256 refundedValidatorsCount,
//             uint256 stuckPenaltyEndTimestamp,
//             uint256 totalExitedValidators,
//             uint256 totalDepositedValidators,
//             uint256 depositableValidatorsCount
//         ) = node.getNodeOperatorSummary(operatorId);
        
//         // 验证基本状态
//         assertEq(targetLimitMode, 0); // 默认限制模式
//         assertEq(targetValidatorsCount, 0); // 默认目标数量
//         assertEq(stuckValidatorsCount, 0); // 没有卡住验证者
//         assertEq(refundedValidatorsCount, 0); // 没有退款验证者  
//         assertEq(stuckPenaltyEndTimestamp, 0); // 没有惩罚时间戳
//         assertEq(totalExitedValidators, 0); // 没有退出验证者
//         assertEq(totalDepositedValidators, 0); // 还没有存款
//         assertEq(depositableValidatorsCount, 2); // 有2个可存款验证者
//     }
    
//     function testObtainDepositData() public {
//         // 添加运营商和验证者密钥
//         vm.prank(admin);
//         uint256 operatorId = node.addNodeOperator("Test Operator", nodeOperator1);
        
//         bytes memory pubkeys = new bytes(96); // 2个48字节的公钥
//         bytes memory signatures = new bytes(192); // 2个96字节的签名
//         vm.prank(nodeOperator1);
//         node.addSigningKeys(operatorId, 2, pubkeys, signatures);
        
//         vm.prank(admin);
//         node.setNodeOperatorStakingLimit(operatorId, 2);
        
//         // 获取1个验证者的存款数据
//         vm.prank(stakingRouter);
//         (bytes memory publicKeys, bytes memory depositSignatures) = node.obtainDepositData(1, "");
        
//         assertEq(publicKeys.length, 48); // 1个验证者的公钥
//         assertEq(depositSignatures.length, 96); // 1个验证者的签名
//     }
    
//     function testObtainDepositDataFailsWithUnauthorized() public {
//         vm.prank(user);
//         vm.expectRevert();
//         node.obtainDepositData(0, ""); // 无权限用户应该失败
//     }
    
//     function testHasRole() public view {
//         assertTrue(node.hasRole(DEFAULT_ADMIN_ROLE, admin));
//         assertTrue(node.hasRole(MANAGE_NODE_OPERATOR_ROLE, admin));
//         assertFalse(node.hasRole(MANAGE_NODE_OPERATOR_ROLE, user));
//     }
    
//     //
//     // 测试边界情况和错误处理
//     //
    
//     function testMaxNodeOperatorsCount() public {
//         // 测试最大运营商数量限制 - 注意这会很慢，在实际测试中可能需要降低数量
//         vm.startPrank(admin);
//         for (uint256 i = 0; i < 5; i++) { // 测试前5个
//             node.addNodeOperator(
//                 string(abi.encodePacked("Operator ", vm.toString(i))), 
//                 address(uint160(1000 + i))
//             );
//         }
//         vm.stopPrank();
        
//         assertEq(node.getNodeOperatorsCount(), 5);
//     }
    
//     function testNonExistentNodeOperator() public {
//         vm.expectRevert();
//         node.getNodeOperator(999, false); // 不存在的运营商应该失败
//     }
    
//     function testZeroAddressValidation() public {
//         vm.prank(admin);
//         vm.expectRevert();
//         node.addNodeOperator("Test", address(0)); // 零地址应该失败
//     }
    
//     function testEmptyNameValidation() public {
//         vm.prank(admin);
//         vm.expectRevert();
//         node.addNodeOperator("", nodeOperator1); // 空名称应该失败
//     }
    
//     //
//     // 测试setLocator函数
//     //
    
//     function testSetLocator() public {
//         // 创建新的定位器合约
//         IGTETHLocator newLocator = new GTETHLocator(IGTETHLocator.Config({
//             gteth: address(gteth),
//             stakingRouter: stakingRouter,
//             nodeOperatorsRegistry: address(node),
//             withdrawalQueueERC721: address(0x100),
//             withdrawalVault: address(0x200),
//             accountingOracle: address(0x300),
//             elRewardsVault: address(0x400),
//             validatorsExitBusOracle: address(0x500),
//             treasury: address(0x600)
//         }));
        
//         // 只有管理员可以设置新的定位器
//         vm.prank(admin);
//         node.setLocator(IGTETHLocator(address(newLocator)));
        
//         // 验证定位器已更新
//         assertEq(address(node.locator()), address(newLocator));
//     }
    
//     function testSetLocatorFailsWithUnauthorized() public {
//         IGTETHLocator newLocator = new GTETHLocator(IGTETHLocator.Config({
//             gteth: address(gteth),
//             stakingRouter: stakingRouter,
//             nodeOperatorsRegistry: address(node),
//             withdrawalQueueERC721: address(0x100),
//             withdrawalVault: address(0x200),
//             accountingOracle: address(0x300),
//             elRewardsVault: address(0x400),
//             validatorsExitBusOracle: address(0x500),
//             treasury: address(0x600)
//         }));
        
//         vm.prank(user);
//         vm.expectRevert();
//         node.setLocator(IGTETHLocator(address(newLocator))); // 无权限用户应该失败
//     }
    
//     function testSetLocatorFailsWithZeroAddress() public {
//         vm.prank(admin);
//         vm.expectRevert();
//         node.setLocator(IGTETHLocator(address(0))); // 零地址应该失败
//     }
// } 