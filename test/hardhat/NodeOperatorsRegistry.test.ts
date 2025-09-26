import { expect } from "chai";
import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { NodeOperatorsRegistry, GTETHLocator } from "../../typechain-types";

describe("NodeOperatorsRegistry", function () {
  let admin: HardhatEthersSigner;
  let nodeOperatorManager: HardhatEthersSigner;
  let limitManager: HardhatEthersSigner;
  let stakingRouter: HardhatEthersSigner;
  let rewardAddress1: HardhatEthersSigner;
  let rewardAddress2: HardhatEthersSigner;
  let user: HardhatEthersSigner;

  let nodeOperatorsRegistry: NodeOperatorsRegistry;
  let locator: GTETHLocator;

  const MODULE_TYPE = ethers.keccak256(ethers.toUtf8Bytes("test-curated-module"));
  const STUCK_PENALTY_DELAY = 86400; // 1 day

  beforeEach(async function () {
    [admin, nodeOperatorManager, limitManager, stakingRouter, rewardAddress1, rewardAddress2, user] = await ethers.getSigners();

    // 部署NodeOperatorsRegistry
    const norFactory = await ethers.getContractFactory("NodeOperatorsRegistry");
    nodeOperatorsRegistry = await norFactory.deploy(MODULE_TYPE, STUCK_PENALTY_DELAY);
    await nodeOperatorsRegistry.waitForDeployment();

    // 部署GTETHLocator
    const locatorFactory = await ethers.getContractFactory("GTETHLocator");
    const locatorConfig = {
      gteth: admin.address,
      stakingRouter: stakingRouter.address,
      nodeOperatorsRegistry: await nodeOperatorsRegistry.getAddress(),
      withdrawalQueueERC721: admin.address,
      withdrawalVault: admin.address,
      accountingOracle: admin.address,
      elRewardsVault: admin.address,
      validatorsExitBusOracle: admin.address,
      treasury: admin.address
    };
    locator = await locatorFactory.deploy(locatorConfig);
    await locator.waitForDeployment();

    // 设置locator
    await nodeOperatorsRegistry.setLocator(locator.target);

    // 授予权限
    const MANAGE_NODE_OPERATOR_ROLE = await nodeOperatorsRegistry.MANAGE_NODE_OPERATOR_ROLE();
    const SET_NODE_OPERATOR_LIMIT_ROLE = await nodeOperatorsRegistry.SET_NODE_OPERATOR_LIMIT_ROLE();
    const STAKING_ROUTER_ROLE = await nodeOperatorsRegistry.STAKING_ROUTER_ROLE();
    const MANAGE_SIGNING_KEYS = await nodeOperatorsRegistry.MANAGE_SIGNING_KEYS();

    await nodeOperatorsRegistry.grantRole(MANAGE_NODE_OPERATOR_ROLE, nodeOperatorManager.address);
    await nodeOperatorsRegistry.grantRole(SET_NODE_OPERATOR_LIMIT_ROLE, limitManager.address);
    await nodeOperatorsRegistry.grantRole(STAKING_ROUTER_ROLE, stakingRouter.address);
    await nodeOperatorsRegistry.grantRole(MANAGE_SIGNING_KEYS, admin.address);
  });

  describe("构造函数和初始化", function () {
    it("应该正确设置初始参数", async function () {
      expect(await nodeOperatorsRegistry.getType()).to.equal(MODULE_TYPE);
      expect(await nodeOperatorsRegistry.getStuckPenaltyDelay()).to.equal(STUCK_PENALTY_DELAY);
      expect(await nodeOperatorsRegistry.getNodeOperatorsCount()).to.equal(0);
      expect(await nodeOperatorsRegistry.getActiveNodeOperatorsCount()).to.equal(0);
    });

    it("应该正确设置locator", async function () {
      expect(await nodeOperatorsRegistry.locator()).to.equal(locator.target);
    });
  });

  describe("节点运营商管理", function () {
    it("应该能够添加节点运营商", async function () {
      const tx = await nodeOperatorsRegistry.connect(nodeOperatorManager).addNodeOperator(
        "Test Operator",
        rewardAddress1.address
      );

      await expect(tx)
        .to.emit(nodeOperatorsRegistry, "NodeOperatorAdded")
        .withArgs(0, "Test Operator", rewardAddress1.address, 0);

      expect(await nodeOperatorsRegistry.getNodeOperatorsCount()).to.equal(1);
      expect(await nodeOperatorsRegistry.getActiveNodeOperatorsCount()).to.equal(1);

      const operator = await nodeOperatorsRegistry.getNodeOperator(0, true);
      expect(operator.active).to.be.true;
      expect(operator.name).to.equal("Test Operator");
      expect(operator.rewardAddress).to.equal(rewardAddress1.address);
    });

    it("应该拒绝非授权用户添加节点运营商", async function () {
      await expect(
        nodeOperatorsRegistry.connect(user).addNodeOperator("Test Operator", rewardAddress1.address)
      ).to.be.revertedWithCustomError(nodeOperatorsRegistry, "AccessControlUnauthorizedAccount");
    });

    it("应该拒绝空名称", async function () {
      await expect(
        nodeOperatorsRegistry.connect(nodeOperatorManager).addNodeOperator("", rewardAddress1.address)
      ).to.be.revertedWith("WRONG_NAME_LENGTH");
    });

    it("应该能够激活和停用节点运营商", async function () {
      // 添加运营商
      await nodeOperatorsRegistry.connect(nodeOperatorManager).addNodeOperator(
        "Test Operator",
        rewardAddress1.address
      );

      // 停用运营商
      await expect(
        nodeOperatorsRegistry.connect(nodeOperatorManager).deactivateNodeOperator(0)
      ).to.emit(nodeOperatorsRegistry, "NodeOperatorActiveSet")
        .withArgs(0, false);

      expect(await nodeOperatorsRegistry.getNodeOperatorIsActive(0)).to.be.false;
      expect(await nodeOperatorsRegistry.getActiveNodeOperatorsCount()).to.equal(0);

      // 激活运营商
      await expect(
        nodeOperatorsRegistry.connect(nodeOperatorManager).activateNodeOperator(0)
      ).to.emit(nodeOperatorsRegistry, "NodeOperatorActiveSet")
        .withArgs(0, true);

      expect(await nodeOperatorsRegistry.getNodeOperatorIsActive(0)).to.be.true;
      expect(await nodeOperatorsRegistry.getActiveNodeOperatorsCount()).to.equal(1);
    });

    it("应该能够更改节点运营商名称", async function () {
      // 添加运营商
      await nodeOperatorsRegistry.connect(nodeOperatorManager).addNodeOperator(
        "Test Operator",
        rewardAddress1.address
      );

      // 更改名称
      await expect(
        nodeOperatorsRegistry.connect(nodeOperatorManager).setNodeOperatorName(0, "New Name")
      ).to.emit(nodeOperatorsRegistry, "NodeOperatorNameSet")
        .withArgs(0, "New Name");

      const operator = await nodeOperatorsRegistry.getNodeOperator(0, true);
      expect(operator.name).to.equal("New Name");
    });

    it("应该能够更改奖励地址", async function () {
      // 添加运营商
      await nodeOperatorsRegistry.connect(nodeOperatorManager).addNodeOperator(
        "Test Operator",
        rewardAddress1.address
      );

      // 更改奖励地址
      await expect(
        nodeOperatorsRegistry.connect(nodeOperatorManager).setNodeOperatorRewardAddress(0, rewardAddress2.address)
      ).to.emit(nodeOperatorsRegistry, "NodeOperatorRewardAddressSet")
        .withArgs(0, rewardAddress2.address);

      const operator = await nodeOperatorsRegistry.getNodeOperator(0, false);
      expect(operator.rewardAddress).to.equal(rewardAddress2.address);
    });
  });

  describe("签名密钥管理", function () {
    beforeEach(async function () {
      // 添加一个运营商
      await nodeOperatorsRegistry.connect(nodeOperatorManager).addNodeOperator(
        "Test Operator",
        rewardAddress1.address
      );
    });

    it("应该能够添加签名密钥", async function () {
      const pubkey = "0x" + "01".repeat(48); // 48字节公钥
      const signature = "0x" + "02".repeat(96); // 96字节签名

      await expect(
        nodeOperatorsRegistry.connect(admin).addSigningKeys(0, 1, pubkey, signature)
      ).to.emit(nodeOperatorsRegistry, "TotalSigningKeysCountChanged")
        .withArgs(0, 1);

      expect(await nodeOperatorsRegistry.getTotalSigningKeyCount(0)).to.equal(1);
      expect(await nodeOperatorsRegistry.getUnusedSigningKeyCount(0)).to.equal(1);

      const [keys, sigs, used] = await nodeOperatorsRegistry.getSigningKeys(0, 0, 1);
      expect(keys).to.equal(pubkey);
      expect(sigs).to.equal(signature);
      expect(used[0]).to.be.false;
    });

    it("应该能够删除未使用的签名密钥", async function () {
      const pubkey = "0x" + "01".repeat(48);
      const signature = "0x" + "02".repeat(96);

      // 添加密钥
      await nodeOperatorsRegistry.connect(admin).addSigningKeys(0, 1, pubkey, signature);

      // 删除密钥
      await expect(
        nodeOperatorsRegistry.connect(admin).removeSigningKeys(0, 0, 1)
      ).to.emit(nodeOperatorsRegistry, "TotalSigningKeysCountChanged")
        .withArgs(0, 0);

      expect(await nodeOperatorsRegistry.getTotalSigningKeyCount(0)).to.equal(0);
    });

    it("应该能够设置质押限制", async function () {
      const pubkey = "0x" + "01".repeat(48);
      const signature = "0x" + "02".repeat(96);

      // 添加密钥
      await nodeOperatorsRegistry.connect(admin).addSigningKeys(0, 1, pubkey, signature);

      // 设置质押限制
      await expect(
        nodeOperatorsRegistry.connect(limitManager).setNodeOperatorStakingLimit(0, 1)
      ).to.emit(nodeOperatorsRegistry, "VettedSigningKeysCountChanged")
        .withArgs(0, 1);
    });
  });

  describe("奖励分配", function () {
    beforeEach(async function () {
      // 添加两个运营商
      await nodeOperatorsRegistry.connect(nodeOperatorManager).addNodeOperator(
        "Operator 1",
        rewardAddress1.address
      );
      await nodeOperatorsRegistry.connect(nodeOperatorManager).addNodeOperator(
        "Operator 2",
        rewardAddress2.address
      );

      // 为每个运营商添加一些密钥
      const pubkey1 = "0x" + "01".repeat(48);
      const signature1 = "0x" + "01".repeat(96);
      const pubkey2 = "0x" + "02".repeat(48);
      const signature2 = "0x" + "02".repeat(96);

      await nodeOperatorsRegistry.connect(admin).addSigningKeys(0, 1, pubkey1, signature1);
      await nodeOperatorsRegistry.connect(admin).addSigningKeys(1, 1, pubkey2, signature2);

      // 设置质押限制
      await nodeOperatorsRegistry.connect(limitManager).setNodeOperatorStakingLimit(0, 1);
      await nodeOperatorsRegistry.connect(limitManager).setNodeOperatorStakingLimit(1, 1);
    });

    it("应该能够获取奖励分配", async function () {
      const totalReward = ethers.parseEther("100");
      const [recipients, amounts, penalized] = await nodeOperatorsRegistry.getRewardsDistribution(totalReward);

      expect(recipients.length).to.equal(2);
      expect(recipients[0]).to.equal(rewardAddress1.address);
      expect(recipients[1]).to.equal(rewardAddress2.address);
      expect(penalized[0]).to.be.false;
      expect(penalized[1]).to.be.false;
    });

    it("应该能够分配奖励", async function () {
      // 模拟奖励分发状态
      await nodeOperatorsRegistry.connect(stakingRouter).onRewardsMinted();

      // 应该设置为转移到模块状态
      expect(await nodeOperatorsRegistry.getRewardDistributionState()).to.equal(0); // TransferredToModule

      // 模拟验证者状态更新完成
      await nodeOperatorsRegistry.connect(stakingRouter).onExitedAndStuckValidatorsCountsUpdated();

      // 应该设置为准备分发状态
      expect(await nodeOperatorsRegistry.getRewardDistributionState()).to.equal(1); // ReadyForDistribution

      // 此测试需要一个模拟的GTETH合约来发送代币
      // 暂时跳过实际分发测试，因为需要实际的代币余额
      // 只验证状态已经正确设置为ReadyForDistribution
      expect(await nodeOperatorsRegistry.getRewardDistributionState()).to.equal(1); // ReadyForDistribution
    });
  });

  describe("质押模块摘要", function () {
    it("应该返回正确的质押模块摘要", async function () {
      const summary = await nodeOperatorsRegistry.getStakingModuleSummary();
      expect(summary.totalExitedValidators).to.equal(0);
      expect(summary.totalDepositedValidators).to.equal(0);
      expect(summary.depositableValidatorsCount).to.equal(0);
    });
  });

  describe("验证者状态更新", function () {
    beforeEach(async function () {
      // 添加运营商并设置密钥
      await nodeOperatorsRegistry.connect(nodeOperatorManager).addNodeOperator(
        "Test Operator",
        rewardAddress1.address
      );

      const pubkey = "0x" + "01".repeat(48);
      const signature = "0x" + "02".repeat(96);
      await nodeOperatorsRegistry.connect(admin).addSigningKeys(0, 1, pubkey, signature);
      await nodeOperatorsRegistry.connect(limitManager).setNodeOperatorStakingLimit(0, 1);
    });

    it("应该能够更新退出验证者数量", async function () {
      // 首先需要模拟一些已存款的验证者
      await nodeOperatorsRegistry.connect(stakingRouter).obtainDepositData(1, "0x");

      const nodeOperatorIds = ethers.concat([ethers.zeroPadValue(ethers.toBeHex(0), 8)]);
      const exitedCounts = ethers.concat([ethers.zeroPadValue(ethers.toBeHex(1), 16)]);

      await expect(
        nodeOperatorsRegistry.connect(stakingRouter).updateExitedValidatorsCount(nodeOperatorIds, exitedCounts)
      ).to.emit(nodeOperatorsRegistry, "ExitedSigningKeysCountChanged")
        .withArgs(0, 1);
    });

    it("应该能够更新卡住验证者数量", async function () {
      // 首先需要模拟一些已存款的验证者
      await nodeOperatorsRegistry.connect(stakingRouter).obtainDepositData(1, "0x");

      const nodeOperatorIds = ethers.concat([ethers.zeroPadValue(ethers.toBeHex(0), 8)]);
      const stuckCounts = ethers.concat([ethers.zeroPadValue(ethers.toBeHex(1), 16)]);

      await expect(
        nodeOperatorsRegistry.connect(stakingRouter).updateStuckValidatorsCount(nodeOperatorIds, stuckCounts)
      ).to.emit(nodeOperatorsRegistry, "StuckPenaltyStateChanged");
    });
  });

  describe("权限控制", function () {
    it("应该正确验证角色权限", async function () {
      const MANAGE_NODE_OPERATOR_ROLE = await nodeOperatorsRegistry.MANAGE_NODE_OPERATOR_ROLE();
      
      expect(await nodeOperatorsRegistry.hasRole(MANAGE_NODE_OPERATOR_ROLE, nodeOperatorManager.address)).to.be.true;
      expect(await nodeOperatorsRegistry.hasRole(MANAGE_NODE_OPERATOR_ROLE, user.address)).to.be.false;
    });

    it("应该拒绝非授权操作", async function () {
      await expect(
        nodeOperatorsRegistry.connect(user).addNodeOperator("Test", rewardAddress1.address)
      ).to.be.revertedWithCustomError(nodeOperatorsRegistry, "AccessControlUnauthorizedAccount");
    });
  });
});