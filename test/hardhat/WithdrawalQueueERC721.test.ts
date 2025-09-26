import { expect } from "chai";
import { ethers } from "hardhat";

describe("WithdrawalQueueERC721", function () {
  let withdrawalQueue: any;
  let owner: any;
  let user1: any;
  let user2: any;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();
    
    const WithdrawalQueueERC721 = await ethers.getContractFactory("WithdrawalQueueERC721");
    withdrawalQueue = await WithdrawalQueueERC721.deploy("GTETH Withdrawal NFT", "GTW");
    await withdrawalQueue.waitForDeployment();
  });

  it("Should allow users to request withdrawals", async function () {
    const gtethAmount = ethers.parseEther("1");
    const ethAmount = ethers.parseEther("1");
    
    // Grant withdrawal request role to user1
    await withdrawalQueue.connect(owner).grantRole(await withdrawalQueue.WITHDRAWAL_REQUEST_ROLE(), user1.address);
    
    // Get current request count before making request
    const currentRequestId = await withdrawalQueue.currentRequestId();
    
    // User requests withdrawal
    await withdrawalQueue.connect(user1).requestWithdrawal(gtethAmount, ethAmount, user1.address);
    
    // The new request should have ID = currentRequestId + 1
    const requestId = currentRequestId + 1n;
    
    // Check withdrawal request was created
    const request = await withdrawalQueue.getWithdrawalRequest(requestId);
    expect(request.cumulativeGTETHAmount).to.equal(gtethAmount);
    expect(request.cumulativeETHAmount).to.equal(ethAmount);
    expect(request.isClaimed).to.equal(false);
    expect(request.creator).to.equal(user1.address);
  });

  it("Should allow owner to finalize withdrawals", async function () {
    const gtethAmount = ethers.parseEther("1");
    const ethAmount = ethers.parseEther("1");
    
    // Grant roles
    await withdrawalQueue.connect(owner).grantRole(await withdrawalQueue.WITHDRAWAL_REQUEST_ROLE(), user1.address);
    await withdrawalQueue.connect(owner).grantRole(await withdrawalQueue.WITHDRAWAL_FINALIZE_ROLE(), owner.address);
    
    // Get current request count before making request
    const currentRequestId = await withdrawalQueue.currentRequestId();
    
    // User requests withdrawal
    await withdrawalQueue.connect(user1).requestWithdrawal(gtethAmount, ethAmount, user1.address);
    
    // The new request should have ID = currentRequestId + 1
    const requestId = currentRequestId + 1n;
    
    // Owner finalizes withdrawal
    await expect(withdrawalQueue.connect(owner).finalize(requestId, ethers.parseEther("1.1"), { value: ethAmount }))
      .to.emit(withdrawalQueue, "WithdrawalsFinalized");
    
    // Check request is now finalized
    const status = await withdrawalQueue.getWithdrawalRequestStatus(requestId);
    expect(status.isFinalized).to.equal(true);
  });

  it("Should allow users to claim finalized withdrawals", async function () {
    const gtethAmount = ethers.parseEther("1");
    const ethAmount = ethers.parseEther("1");
    
    // Grant roles
    await withdrawalQueue.connect(owner).grantRole(await withdrawalQueue.WITHDRAWAL_REQUEST_ROLE(), user1.address);
    await withdrawalQueue.connect(owner).grantRole(await withdrawalQueue.WITHDRAWAL_FINALIZE_ROLE(), owner.address);
    await withdrawalQueue.connect(owner).grantRole(await withdrawalQueue.WITHDRAWAL_CLAIM_ROLE(), user1.address);
    
    // Get current request count before making request
    const currentRequestId = await withdrawalQueue.currentRequestId();
    
    // User requests withdrawal
    await withdrawalQueue.connect(user1).requestWithdrawal(gtethAmount, ethAmount, user1.address);
    
    // The new request should have ID = currentRequestId + 1
    const requestId = currentRequestId + 1n;
    
    // Owner finalizes withdrawal
    await withdrawalQueue.connect(owner).finalize(requestId, ethers.parseEther("1.1"), { value: ethAmount });
    
    // Check user's balance before claiming
    const userBalanceBefore = await ethers.provider.getBalance(user1.address);
    
    // User claims withdrawal
    await expect(withdrawalQueue.connect(user1).claimWithdrawal(requestId, user1.address))
      .to.emit(withdrawalQueue, "WithdrawalClaimed")
      .withArgs(user1.address, requestId, ethAmount);
    
    // Check user's balance after claiming
    const userBalanceAfter = await ethers.provider.getBalance(user1.address);
    expect(userBalanceAfter - userBalanceBefore).to.be.closeTo(ethAmount, ethers.parseEther("0.01")); // Account for gas costs
    
    // Check request is now claimed
    const request = await withdrawalQueue.getWithdrawalRequest(requestId);
    expect(request.isClaimed).to.equal(true);
  });

  it("Should prevent claiming non-existent or non-finalized requests", async function () {
    const gtethAmount = ethers.parseEther("1");
    const ethAmount = ethers.parseEther("1");
    const fakeRequestId = 999;
    
    // Grant roles
    await withdrawalQueue.connect(owner).grantRole(await withdrawalQueue.WITHDRAWAL_REQUEST_ROLE(), user1.address);
    await withdrawalQueue.connect(owner).grantRole(await withdrawalQueue.WITHDRAWAL_CLAIM_ROLE(), user1.address);
    
    // Try to claim a non-existent request
    await expect(withdrawalQueue.connect(user1).claimWithdrawal(fakeRequestId, user1.address))
      .to.be.revertedWith("Request not finalized");
    
    // Get current request count before making request
    const currentRequestId = await withdrawalQueue.currentRequestId();
    
    // User requests withdrawal
    await withdrawalQueue.connect(user1).requestWithdrawal(gtethAmount, ethAmount, user1.address);
    
    // The new request should have ID = currentRequestId + 1
    const requestId = currentRequestId + 1n;
    
    // Try to claim a non-finalized request
    await expect(withdrawalQueue.connect(user1).claimWithdrawal(requestId, user1.address))
      .to.be.revertedWith("Request not finalized");
  });

  it("Should prevent double claiming", async function () {
    const gtethAmount = ethers.parseEther("1");
    const ethAmount = ethers.parseEther("1");
    
    // Grant roles
    await withdrawalQueue.connect(owner).grantRole(await withdrawalQueue.WITHDRAWAL_REQUEST_ROLE(), user1.address);
    await withdrawalQueue.connect(owner).grantRole(await withdrawalQueue.WITHDRAWAL_FINALIZE_ROLE(), owner.address);
    await withdrawalQueue.connect(owner).grantRole(await withdrawalQueue.WITHDRAWAL_CLAIM_ROLE(), user1.address);
    
    // Get current request count before making request
    const currentRequestId = await withdrawalQueue.currentRequestId();
    
    // User requests withdrawal
    await withdrawalQueue.connect(user1).requestWithdrawal(gtethAmount, ethAmount, user1.address);
    
    // The new request should have ID = currentRequestId + 1
    const requestId = currentRequestId + 1n;
    
    // Owner finalizes withdrawal
    await withdrawalQueue.connect(owner).finalize(requestId, ethers.parseEther("1.1"), { value: ethAmount });
    
    // User claims withdrawal
    await withdrawalQueue.connect(user1).claimWithdrawal(requestId, user1.address);
    
    // Try to claim again
    await expect(withdrawalQueue.connect(user1).claimWithdrawal(requestId, user1.address))
      .to.be.revertedWith("Request already claimed");
  });
});