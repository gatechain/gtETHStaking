import { expect } from "chai";
import { ethers } from "hardhat";

describe("GTETH", function () {
  let gteth: any;
  let owner: any;
  let user1: any;
  let user2: any;
  let user3: any;

  const PRECISION = ethers.parseEther("1");
  const DEPOSIT_SIZE = ethers.parseEther("32");

  beforeEach(async function () {
    [owner, user1, user2, user3] = await ethers.getSigners();
    
    // Deploy GTETH
    const GTETH = await ethers.getContractFactory("GTETH");
    gteth = await GTETH.deploy("Gemini Staked ETH", "GTETH", owner.address);
    await gteth.waitForDeployment();
    
    // Grant necessary roles
    const DEPOSIT_SECURITY_MODULE_ROLE = await gteth.DEPOSIT_SECURITY_MODULE_ROLE();
    await gteth.grantRole(DEPOSIT_SECURITY_MODULE_ROLE, owner.address);
  });

  describe("Deployment", function () {
    it("Should set the correct name and symbol", async function () {
      expect(await gteth.name()).to.equal("Gemini Staked ETH");
      expect(await gteth.symbol()).to.equal("GTETH");
    });

    it("Should set the correct owner", async function () {
      expect(await gteth.owner()).to.equal(owner.address);
    });

    it("Should set the correct precision and deposit size", async function () {
      expect(await gteth.PRECISION()).to.equal(PRECISION);
      expect(await gteth.DEPOSIT_SIZE()).to.equal(DEPOSIT_SIZE);
    });

    it("Should grant DEPOSIT_SECURITY_MODULE_ROLE to owner", async function () {
      const DEPOSIT_SECURITY_MODULE_ROLE = await gteth.DEPOSIT_SECURITY_MODULE_ROLE();
      expect(await gteth.hasRole(DEPOSIT_SECURITY_MODULE_ROLE, owner.address)).to.be.true;
    });
  });

  describe("Staking (submit)", function () {
    it("Should allow users to stake ETH and receive GTETH tokens", async function () {
      const stakeAmount = ethers.parseEther("1");
      const initialBalance = await gteth.balanceOf(user1.address);
      
      // User stakes ETH using the submit function
      await gteth.connect(user1).submit({ value: stakeAmount });
      
      // Check user received GTETH tokens
      const finalBalance = await gteth.balanceOf(user1.address);
      expect(finalBalance).to.be.gt(initialBalance);
      expect(finalBalance).to.equal(stakeAmount); // 1:1 initial rate
    });

    it("Should update protocol state correctly after staking", async function () {
      const stakeAmount = ethers.parseEther("2");
      const initialState = await gteth.protocolState();
      const initialBufferedETH = initialState.bufferedETH;
      
      await gteth.connect(user1).submit({ value: stakeAmount });
      
      const finalState = await gteth.protocolState();
      const finalBufferedETH = finalState.bufferedETH;
      expect(finalBufferedETH).to.equal(initialBufferedETH + stakeAmount);
    });

    it("Should emit Submit event", async function () {
      const stakeAmount = ethers.parseEther("1");
      
      await expect(gteth.connect(user1).submit({ value: stakeAmount }))
        .to.emit(gteth, "Submit")
        .withArgs(user1.address, stakeAmount);
    });

    it("Should revert when trying to submit 0 ETH", async function () {
      await expect(gteth.connect(user1).submit({ value: 0 }))
        .to.be.revertedWithCustomError(gteth, "NoETHToSubmit");
    });

    it("Should work with explicit submit function", async function () {
      const stakeAmount = ethers.parseEther("1");
      
      await expect(gteth.connect(user1).submit({ value: stakeAmount }))
        .to.emit(gteth, "Submit")
        .withArgs(user1.address, stakeAmount);
    });
  });

  describe("Exchange Rate Calculations", function () {
    beforeEach(async function () {
      // Initial stake to establish exchange rate
      await gteth.connect(user1).submit({ value: ethers.parseEther("10") });
    });

    it("Should calculate correct ETH amounts for GTETH", async function () {
      const gtethAmount = ethers.parseEther("5");
      const ethAmount = await gteth.getETHAmount(gtethAmount);
      
      // Should be approximately equal (allowing for small precision differences)
      expect(ethAmount).to.be.closeTo(gtethAmount, ethers.parseEther("0.001"));
    });

    it("Should calculate correct GTETH amounts for ETH", async function () {
      const ethAmount = ethers.parseEther("3");
      const gtethAmount = await gteth.getGTETHAmount(ethAmount);
      
      // Should be approximately equal (allowing for small precision differences)
      expect(gtethAmount).to.be.closeTo(ethAmount, ethers.parseEther("0.001"));
    });

    it("Should maintain 1:1 rate when no rewards", async function () {
      const testAmount = ethers.parseEther("7");
      const gtethAmount = await gteth.getGTETHAmount(testAmount);
      const ethAmount = await gteth.getETHAmount(gtethAmount);
      
      expect(ethAmount).to.be.closeTo(testAmount, ethers.parseEther("0.001"));
    });
  });

  describe("Withdrawals", function () {
    beforeEach(async function () {
      // User stakes some ETH first
      await gteth.connect(user1).submit({ value: ethers.parseEther("10") });
    });

    it("Should revert when trying to withdraw 0 GTETH", async function () {
      await expect(gteth.connect(user1).withdraw(0))
        .to.be.revertedWith("Invalid amount");
    });

    it("Should revert when trying to withdraw more than balance", async function () {
      const gtethBalance = await gteth.balanceOf(user1.address);
      const withdrawAmount = gtethBalance + 1n;
      
      await expect(gteth.connect(user1).withdraw(withdrawAmount))
        .to.be.revertedWithCustomError(gteth, "ERC20InsufficientBalance");
    });

    it("Should revert withdrawal without locator setup", async function () {
      const gtethBalance = await gteth.balanceOf(user1.address);
      const withdrawAmount = gtethBalance / 2n;
      
      // This will revert because locator is not set
      await expect(gteth.connect(user1).withdraw(withdrawAmount))
        .to.be.reverted;
    });
  });

  describe("Deposits", function () {
    beforeEach(async function () {
      // Add some buffered ETH
      await gteth.connect(user1).submit({ value: ethers.parseEther("100") });
    });

    it("Should revert deposits without locator setup", async function () {
      const maxDepositsCount = 2;
      const stakingModuleId = 1;
      const depositCalldata = "0x";
      
      // This will revert because locator is not set
      await expect(gteth.deposit(maxDepositsCount, stakingModuleId, depositCalldata))
        .to.be.reverted;
    });

    it("Should revert when called without DEPOSIT_SECURITY_MODULE_ROLE", async function () {
      const maxDepositsCount = 2;
      const stakingModuleId = 1;
      const depositCalldata = "0x";
      
      await expect(gteth.connect(user1).deposit(maxDepositsCount, stakingModuleId, depositCalldata))
        .to.be.revertedWithCustomError(gteth, "AccessControlUnauthorizedAccount");
    });
  });

  describe("Oracle Reports", function () {
    beforeEach(async function () {
      // Initial setup
      await gteth.connect(user1).submit({ value: ethers.parseEther("32") });
    });

    it("Should revert oracle reports without locator setup", async function () {
      const reportTimestamp = await time() + 1000;
      const timeElapsed = 86400; // 1 day
      const clValidators = 1;
      const clBalance = ethers.parseEther("32.5"); // 32 ETH + 0.5 ETH rewards
      const withdrawalVaultBalance = 0;
      const elRewardsVaultBalance = ethers.parseEther("0.2");
      const gtETHAmountRequestedToBurn = 0;
      const withdrawalFinalizationBatches: any[] = [];
      const simulatedShareRate = 1;
      
      // This will revert because locator is not set
      await expect(gteth.handleOracleReport(
        reportTimestamp,
        timeElapsed,
        clValidators,
        clBalance,
        withdrawalVaultBalance,
        elRewardsVaultBalance,
        gtETHAmountRequestedToBurn,
        withdrawalFinalizationBatches,
        simulatedShareRate
      )).to.be.reverted;
    });

    it("Should revert when called by non-owner", async function () {
      const reportTimestamp = await time() + 1000;
      const timeElapsed = 86400;
      const clValidators = 1;
      const clBalance = ethers.parseEther("32");
      const withdrawalVaultBalance = 0;
      const elRewardsVaultBalance = 0;
      const gtETHAmountRequestedToBurn = 0;
      const withdrawalFinalizationBatches: any[] = [];
      const simulatedShareRate = 1;
      
      await expect(gteth.connect(user1).handleOracleReport(
        reportTimestamp,
        timeElapsed,
        clValidators,
        clBalance,
        withdrawalVaultBalance,
        elRewardsVaultBalance,
        gtETHAmountRequestedToBurn,
        withdrawalFinalizationBatches,
        simulatedShareRate
      )).to.be.revertedWithCustomError(gteth, "OwnableUnauthorizedAccount");
    });
  });

  describe("Rewards", function () {
    it("Should allow receiving EL rewards", async function () {
      const rewardAmount = ethers.parseEther("1");
      const initialState = await gteth.protocolState();
      const initialBufferedETH = initialState.bufferedETH;
      
      await expect(gteth.connect(user1).receiveELRewards({ value: rewardAmount }))
        .to.emit(gteth, "ReceiveELRewards")
        .withArgs(rewardAmount);
      
      const finalState = await gteth.protocolState();
      const finalBufferedETH = finalState.bufferedETH;
      expect(finalBufferedETH).to.equal(initialBufferedETH + rewardAmount);
    });

    it("Should allow receiving withdrawals", async function () {
      const withdrawalAmount = ethers.parseEther("2");
      const initialState = await gteth.protocolState();
      const initialBufferedETH = initialState.bufferedETH;
      
      await expect(gteth.connect(user1).receiveWithdrawals({ value: withdrawalAmount }))
        .to.emit(gteth, "ReceiveWithdrawals")
        .withArgs(withdrawalAmount);
      
      const finalState = await gteth.protocolState();
      const finalBufferedETH = finalState.bufferedETH;
      expect(finalBufferedETH).to.equal(initialBufferedETH + withdrawalAmount);
    });

    it("Should revert when receiving 0 EL rewards", async function () {
      await expect(gteth.connect(user1).receiveELRewards({ value: 0 }))
        .to.be.revertedWith("No rewards to receive");
    });

    it("Should revert when receiving 0 withdrawals", async function () {
      await expect(gteth.connect(user1).receiveWithdrawals({ value: 0 }))
        .to.be.revertedWith("No withdrawals to receive");
    });
  });

  describe("Access Control", function () {
    it("Should support interface for AccessControl", async function () {
      const accessControlInterfaceId = "0x7965db0b";
      expect(await gteth.supportsInterface(accessControlInterfaceId)).to.be.true;
    });

    it("Should not support random interface", async function () {
      const randomInterfaceId = "0x12345678";
      expect(await gteth.supportsInterface(randomInterfaceId)).to.be.false;
    });
  });

  describe("State Queries", function () {
    it("Should return correct total pooled ETH", async function () {
      const stakeAmount = ethers.parseEther("10");
      await gteth.connect(user1).submit({ value: stakeAmount });
      
      const totalPooledETH = await gteth.getTotalPooledETH();
      expect(totalPooledETH).to.be.gte(stakeAmount);
    });

    it("Should return correct available buffer", async function () {
      const stakeAmount = ethers.parseEther("20");
      await gteth.connect(user1).submit({ value: stakeAmount });
      
      const availableBuffer = await gteth.getAvailableBuffer();
      expect(availableBuffer).to.be.gte(stakeAmount);
    });

    it("Should return correct deposit buffer", async function () {
      const stakeAmount = ethers.parseEther("15");
      await gteth.connect(user1).submit({ value: stakeAmount });
      
      const state = await gteth.protocolState();
      expect(state.bufferedETH).to.equal(stakeAmount);
    });
  });

  describe("Governance", function () {
    it("Should allow owner to set GTETH locator", async function () {
      const newLocator = user2.address;
      await gteth.setGTETHLocator(newLocator);
      
      // Note: We can't directly test the locator getter as it's internal
      // But we can verify the transaction didn't revert
      expect(await gteth.owner()).to.equal(owner.address);
    });

    it("Should revert when non-owner tries to set GTETH locator", async function () {
      const newLocator = user2.address;
      await expect(gteth.connect(user1).setGTETHLocator(newLocator))
        .to.be.revertedWithCustomError(gteth, "OwnableUnauthorizedAccount");
    });
  });

  describe("Integration Tests", function () {
    it("Should handle complete staking flow", async function () {
      // 1. User stakes ETH
      const stakeAmount = ethers.parseEther("5");
      await gteth.connect(user1).submit({ value: stakeAmount });
      
      // 2. Check GTETH balance
      const gtethBalance = await gteth.balanceOf(user1.address);
      expect(gtethBalance).to.equal(stakeAmount);
      
      // 3. Check protocol state
      const state = await gteth.protocolState();
      expect(state.bufferedETH).to.equal(stakeAmount);
    });

    it("Should handle multiple users staking", async function () {
      // User 1 stakes
      await gteth.connect(user1).submit({ value: ethers.parseEther("10") });
      
      // User 2 stakes
      await gteth.connect(user2).submit({ value: ethers.parseEther("15") });
      
      // Check balances
      expect(await gteth.balanceOf(user1.address)).to.equal(ethers.parseEther("10"));
      expect(await gteth.balanceOf(user2.address)).to.equal(ethers.parseEther("15"));
      
      // Check total supply
      expect(await gteth.totalSupply()).to.equal(ethers.parseEther("25"));
      
      // Check buffered ETH
      const state = await gteth.protocolState();
      expect(state.bufferedETH).to.equal(ethers.parseEther("25"));
    });
  });
});

// Helper function to get current timestamp
async function time(): Promise<number> {
  const block = await ethers.provider.getBlock("latest");
  return block ? block.timestamp : Math.floor(Date.now() / 1000);
}