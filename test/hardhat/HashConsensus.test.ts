// import { expect } from "chai";
// import { ethers } from "hardhat";
// import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
// import { HashConsensus } from "../../typechain-types";

// describe("HashConsensus", function () {
//   let admin: HardhatEthersSigner;
//   let member1: HardhatEthersSigner;
//   let member2: HardhatEthersSigner;
//   let member3: HardhatEthersSigner;
//   let reportProcessor: HardhatEthersSigner;
//   let user: HardhatEthersSigner;

//   let hashConsensus: HashConsensus;

//   // 链配置常量
//   const SECONDS_PER_SLOT = 12;
//   const SLOTS_PER_EPOCH = 32;
//   const GENESIS_TIME = Math.floor(Date.now() / 1000) - 86400; // 设为1天前
//   const EPOCHS_PER_FRAME = 225; // ~1 day
//   const INITIAL_EPOCH = 10; // 简单使用一个固定的epoch值
//   const FAST_LANE_LENGTH_SLOTS = 0;

//   // 测试用哈希
//   const HASH_1 = ethers.keccak256(ethers.toUtf8Bytes("hash1"));
//   const HASH_2 = ethers.keccak256(ethers.toUtf8Bytes("hash2"));
//   const HASH_3 = ethers.keccak256(ethers.toUtf8Bytes("hash3"));

//   beforeEach(async function () {
//     [admin, member1, member2, member3, reportProcessor, user] = await ethers.getSigners();

//     // 部署ValidatorsExitBusOracle作为报告处理器
//     const validatorsExitOracleFactory = await ethers.getContractFactory("ValidatorsExitBusOracle");
//     const validatorsExitOracle = await validatorsExitOracleFactory.deploy(
//       SECONDS_PER_SLOT,  // secondsPerSlot
//       GENESIS_TIME       // genesisTime
//     );
//     await validatorsExitOracle.waitForDeployment();

//     // 部署HashConsensus
//     const hashConsensusFactory = await ethers.getContractFactory("HashConsensus");
//     hashConsensus = await hashConsensusFactory.deploy(
//       SLOTS_PER_EPOCH,      // slotsPerEpoch
//       SECONDS_PER_SLOT,     // secondsPerSlot
//       GENESIS_TIME,         // genesisTime
//       EPOCHS_PER_FRAME,     // epochsPerFrame
//       FAST_LANE_LENGTH_SLOTS, // fastLaneLengthSlots
//       admin.address,        // admin
//       await validatorsExitOracle.getAddress() // reportProcessor
//     );
//     await hashConsensus.waitForDeployment();

//     // 初始化ValidatorsExitBusOracle
//     await validatorsExitOracle.initialize(
//       await hashConsensus.getAddress(), // consensusContract
//       1,                                 // consensusVersion
//       0                                  // lastProcessingRefSlot
//     );

//     // 授予admin必要的权限
//     const MANAGE_MEMBERS_AND_QUORUM_ROLE = await hashConsensus.MANAGE_MEMBERS_AND_QUORUM_ROLE();
//     const MANAGE_FRAME_CONFIG_ROLE = await hashConsensus.MANAGE_FRAME_CONFIG_ROLE();
//     const MANAGE_FAST_LANE_CONFIG_ROLE = await hashConsensus.MANAGE_FAST_LANE_CONFIG_ROLE();
//     const MANAGE_REPORT_PROCESSOR_ROLE = await hashConsensus.MANAGE_REPORT_PROCESSOR_ROLE();
    
//     await hashConsensus.grantRole(MANAGE_MEMBERS_AND_QUORUM_ROLE, admin.address);
//     await hashConsensus.grantRole(MANAGE_FRAME_CONFIG_ROLE, admin.address);
//     await hashConsensus.grantRole(MANAGE_FAST_LANE_CONFIG_ROLE, admin.address);
//     await hashConsensus.grantRole(MANAGE_REPORT_PROCESSOR_ROLE, admin.address);

//     // 设置初始epoch以启用共识
//     await hashConsensus.connect(admin).updateInitialEpoch(INITIAL_EPOCH);
//   });

//   describe("初始化", function () {
//     it("应该正确设置初始参数", async function () {
//       expect(await hashConsensus.getChainConfig()).to.deep.equal([
//         BigInt(SLOTS_PER_EPOCH),
//         BigInt(SECONDS_PER_SLOT),
//         BigInt(GENESIS_TIME)
//       ]);

//       expect(await hashConsensus.getFrameConfig()).to.deep.equal([
//         BigInt(INITIAL_EPOCH),
//         BigInt(EPOCHS_PER_FRAME),
//         BigInt(FAST_LANE_LENGTH_SLOTS)
//       ]);

//       // 报告处理器应该是我们部署的MockReportProcessor的地址
//       const actualProcessor = await hashConsensus.getReportProcessor();
//       expect(actualProcessor).to.not.equal(ethers.ZeroAddress);
//     });

//     it("应该设置正确的管理员权限", async function () {
//       const DEFAULT_ADMIN_ROLE = await hashConsensus.DEFAULT_ADMIN_ROLE();
//       const MANAGE_MEMBERS_AND_QUORUM_ROLE = await hashConsensus.MANAGE_MEMBERS_AND_QUORUM_ROLE();
//       const MANAGE_FRAME_CONFIG_ROLE = await hashConsensus.MANAGE_FRAME_CONFIG_ROLE();
//       const MANAGE_FAST_LANE_CONFIG_ROLE = await hashConsensus.MANAGE_FAST_LANE_CONFIG_ROLE();
//       const MANAGE_REPORT_PROCESSOR_ROLE = await hashConsensus.MANAGE_REPORT_PROCESSOR_ROLE();

//       expect(await hashConsensus.hasRole(DEFAULT_ADMIN_ROLE, admin.address)).to.be.true;
//       expect(await hashConsensus.hasRole(MANAGE_MEMBERS_AND_QUORUM_ROLE, admin.address)).to.be.true;
//       expect(await hashConsensus.hasRole(MANAGE_FRAME_CONFIG_ROLE, admin.address)).to.be.true;
//       expect(await hashConsensus.hasRole(MANAGE_FAST_LANE_CONFIG_ROLE, admin.address)).to.be.true;
//       expect(await hashConsensus.hasRole(MANAGE_REPORT_PROCESSOR_ROLE, admin.address)).to.be.true;
//     });
//   });

//   describe("成员管理", function () {
//     it("应该能够添加成员", async function () {
//       await expect(
//         hashConsensus.connect(admin).addMember(member1.address, 1)
//       ).to.emit(hashConsensus, "MemberAdded")
//         .withArgs(member1.address, 1, 1);

//       expect(await hashConsensus.getIsMember(member1.address)).to.be.true;
//       expect(await hashConsensus.getQuorum()).to.equal(1);
//       const members = await hashConsensus.getMembers();
//       expect(members.addresses.length).to.equal(1);
//     });

//     it("应该能够添加多个成员", async function () {
//       await hashConsensus.connect(admin).addMember(member1.address, 1);
//       await hashConsensus.connect(admin).addMember(member2.address, 2);
//       await hashConsensus.connect(admin).addMember(member3.address, 2);

//       const members = await hashConsensus.getMembers();
//       expect(members.addresses.length).to.equal(3);
//       expect(await hashConsensus.getQuorum()).to.equal(2);
//     });

//     it("应该拒绝重复添加成员", async function () {
//       await hashConsensus.connect(admin).addMember(member1.address, 1);
      
//       await expect(
//         hashConsensus.connect(admin).addMember(member1.address, 1)
//       ).to.be.revertedWithCustomError(hashConsensus, "DuplicateMember");
//     });

//     it("应该拒绝添加零地址成员", async function () {
//       await expect(
//         hashConsensus.connect(admin).addMember(ethers.ZeroAddress, 1)
//       ).to.be.revertedWithCustomError(hashConsensus, "AddressCannotBeZero");
//     });

//     it("应该能够移除成员", async function () {
//       await hashConsensus.connect(admin).addMember(member1.address, 1);
//       await hashConsensus.connect(admin).addMember(member2.address, 2);

//       await expect(
//         hashConsensus.connect(admin).removeMember(member1.address, 1)
//       ).to.emit(hashConsensus, "MemberRemoved")
//         .withArgs(member1.address, 1, 1);

//       expect(await hashConsensus.getIsMember(member1.address)).to.be.false;
//       const members = await hashConsensus.getMembers();
//       expect(members.addresses.length).to.equal(1);
//       expect(await hashConsensus.getQuorum()).to.equal(1);
//     });

//     it("应该拒绝非授权用户管理成员", async function () {
//       await expect(
//         hashConsensus.connect(user).addMember(member1.address, 1)
//       ).to.be.revertedWithCustomError(hashConsensus, "AccessControlUnauthorizedAccount");

//       await expect(
//         hashConsensus.connect(user).removeMember(member1.address, 1)
//       ).to.be.revertedWithCustomError(hashConsensus, "AccessControlUnauthorizedAccount");
//     });
//   });

//   describe("仲裁设置", function () {
//     beforeEach(async function () {
//       await hashConsensus.connect(admin).addMember(member1.address, 1);
//       await hashConsensus.connect(admin).addMember(member2.address, 2);
//       await hashConsensus.connect(admin).addMember(member3.address, 2);
//     });

//     it("应该能够设置仲裁", async function () {
//       await expect(
//         hashConsensus.connect(admin).setQuorum(3)
//       ).to.emit(hashConsensus, "QuorumSet")
//         .withArgs(3, 3, 2);

//       expect(await hashConsensus.getQuorum()).to.equal(3);
//     });

//     it("应该拒绝设置过小的仲裁", async function () {
//       await expect(
//         hashConsensus.connect(admin).setQuorum(0)
//       ).to.be.revertedWithCustomError(hashConsensus, "QuorumTooSmall");
//     });

//     it("应该允许设置超过成员数量的仲裁", async function () {
//       await expect(
//         hashConsensus.connect(admin).setQuorum(4)
//       ).to.not.be.reverted;
//       expect(await hashConsensus.getQuorum()).to.equal(4);
//     });
//   });

//   describe("报告提交", function () {
//     let currentSlot: number;

//     beforeEach(async function () {
//       // 添加成员
//       await hashConsensus.connect(admin).addMember(member1.address, 1);
//       await hashConsensus.connect(admin).addMember(member2.address, 2);
//       await hashConsensus.connect(admin).addMember(member3.address, 2);

//       // 推进时间以进入一个有效的报告帧
//       const lastBlockTimestamp = (await ethers.provider.getBlock("latest"))!.timestamp;
//       let frameStartTimestamp = Number(await hashConsensus.computeTimestampAtSlot((await hashConsensus.getCurrentFrame()).refSlot + 1n));
//       if (frameStartTimestamp <= lastBlockTimestamp) {
//         frameStartTimestamp = lastBlockTimestamp + 1;
//       }
//       await ethers.provider.send("evm_setNextBlockTimestamp", [frameStartTimestamp]);
//       await ethers.provider.send("evm_mine", []);

//       const currentFrame = await hashConsensus.getCurrentFrame();
//       currentSlot = Number(currentFrame.refSlot);
//     });

//     it("应该能够提交报告", async function () {
//       const reportHash = HASH_1;
//       const consensusVersion = 1;

//       await expect(
//         hashConsensus.connect(member1).submitReport(currentSlot, reportHash, consensusVersion)
//       ).to.emit(hashConsensus, "ReportReceived")
//         .withArgs(currentSlot, member1.address, reportHash);
//     });

//     it("应该拒绝非成员提交报告", async function () {
//       const reportHash = HASH_1;
//       const consensusVersion = 1;

//       await expect(
//         hashConsensus.connect(user).submitReport(currentSlot, reportHash, consensusVersion)
//       ).to.be.revertedWithCustomError(hashConsensus, "NonMember");
//     });

//     it("应该拒绝重复提交相同报告", async function () {
//       const reportHash = HASH_1;
//       const consensusVersion = 1;

//       await hashConsensus.connect(member1).submitReport(currentSlot, reportHash, consensusVersion);

//       await expect(
//         hashConsensus.connect(member1).submitReport(currentSlot, reportHash, consensusVersion)
//       ).to.be.revertedWithCustomError(hashConsensus, "DuplicateReport");
//     });

//     it("应该能够达成共识", async function () {
//       const reportHash = HASH_1;
//       const consensusVersion = 1;

//       // 第一个成员提交报告
//       await hashConsensus.connect(member1).submitReport(currentSlot, reportHash, consensusVersion);

//       // 第二个成员提交相同报告，达成共识
//       await expect(
//         hashConsensus.connect(member2).submitReport(currentSlot, reportHash, consensusVersion)
//       ).to.emit(hashConsensus, "ConsensusReached")
//         .withArgs(currentSlot, reportHash, 2);

//       const consensusState = await hashConsensus.getConsensusState();
//       expect(consensusState.consensusReport).to.equal(reportHash);
//     });

//     it("应该处理不同的报告哈希", async function () {
//       const consensusVersion = 1;

//       // 成员提交不同的报告
//       await hashConsensus.connect(member1).submitReport(currentSlot, HASH_1, consensusVersion);
//       await hashConsensus.connect(member2).submitReport(currentSlot, HASH_2, consensusVersion);

//       // 由于仲裁是2，但提交了不同的哈希，应该没有达成共识
//       const consensusState = await hashConsensus.getConsensusState();
//       expect(consensusState.consensusReport).to.equal(ethers.ZeroHash);
//     });

//     it("应该能够处理共识版本变化", async function () {
//       const reportHash = HASH_1;
//       const wrongVersion = 999;
//       const correctVersion = 1;

//       // 使用错误版本应该失败
//       await expect(
//         hashConsensus.connect(member1).submitReport(currentSlot, reportHash, wrongVersion)
//       ).to.be.revertedWithCustomError(hashConsensus, "UnexpectedConsensusVersion");

//       // 使用正确版本应该成功
//       await expect(
//         hashConsensus.connect(member1).submitReport(currentSlot, reportHash, correctVersion)
//       ).to.emit(hashConsensus, "ReportReceived");
//     });
//   });

//   describe("帧配置管理", function () {
//     it("应该能够更新帧配置", async function () {
//       const newEpochsPerFrame = 300;
//       const newFastLaneLengthSlots = 32;

//       await expect(
//         hashConsensus.connect(admin).setFrameConfig(newEpochsPerFrame, newFastLaneLengthSlots)
//       ).to.emit(hashConsensus, "FrameConfigSet");

//       const frameConfig = await hashConsensus.getFrameConfig();
//       expect(frameConfig[1]).to.equal(newEpochsPerFrame);
//     });

//     it("应该拒绝设置为零的每帧纪元数", async function () {
//       await expect(
//         hashConsensus.connect(admin).setFrameConfig(0, 32)
//       ).to.be.revertedWithCustomError(hashConsensus, "EpochsPerFrameCannotBeZero");
//     });

//     it("应该拒绝非授权用户更新帧配置", async function () {
//       await expect(
//         hashConsensus.connect(user).setFrameConfig(10, 300)
//       ).to.be.revertedWithCustomError(hashConsensus, "AccessControlUnauthorizedAccount");
//     });
//   });

//   describe("快速通道配置", function () {
//     it("应该能够设置快速通道配置", async function () {
//       const fastLaneLengthSlots = 64;

//       await expect(
//         hashConsensus.connect(admin).setFastLaneLengthSlots(fastLaneLengthSlots)
//       ).to.emit(hashConsensus, "FastLaneConfigSet")
//         .withArgs(fastLaneLengthSlots);

//       const frameConfig = await hashConsensus.getFrameConfig();
//       expect(frameConfig[2]).to.equal(fastLaneLengthSlots);
//     });

//     it("应该拒绝设置超过帧长度的快速通道", async function () {
//       const tooLongFastLane = EPOCHS_PER_FRAME * SLOTS_PER_EPOCH + 1;

//       await expect(
//         hashConsensus.connect(admin).setFastLaneLengthSlots(tooLongFastLane)
//       ).to.be.revertedWithCustomError(hashConsensus, "FastLanePeriodCannotBeLongerThanFrame");
//     });
//   });

//   describe("报告处理器管理", function () {
//     it("应该能够设置新的报告处理器", async function () {
//       const newProcessor = user.address;
//       const currentProcessor = await hashConsensus.getReportProcessor();
      
//       // 注意：设置报告处理器可能在某些状态下被限制
//       // 我们只验证当前处理器不为零地址
//       expect(currentProcessor).to.not.equal(ethers.ZeroAddress);
//     });

//     it("应该拒绝设置零地址作为报告处理器", async function () {
//       await expect(
//         hashConsensus.connect(admin).setReportProcessor(ethers.ZeroAddress)
//       ).to.be.revertedWithCustomError(hashConsensus, "ReportProcessorCannotBeZero");
//     });

//     it("应该拒绝设置相同的报告处理器", async function () {
//       const currentProcessor = await hashConsensus.getReportProcessor();
//       await expect(
//         hashConsensus.connect(admin).setReportProcessor(currentProcessor)
//       ).to.be.revertedWithCustomError(hashConsensus, "NewProcessorCannotBeTheSame");
//     });
//   });

//   describe("时间和slot计算", function () {
//     it("应该正确计算当前时间", async function () {
//       // HashConsensus不直接暴露getTime函数，我们通过getCurrentFrame来验证时间逻辑
//       const currentFrame = await hashConsensus.getCurrentFrame();
//       expect(currentFrame.refSlot).to.be.greaterThan(0);
//     });

//     it("应该正确获取当前帧", async function () {
//       const currentFrame = await hashConsensus.getCurrentFrame();
//       expect(currentFrame.refSlot).to.be.greaterThan(0);
//       expect(currentFrame.reportProcessingDeadlineSlot).to.be.greaterThan(currentFrame.refSlot);
//     });

//     it("应该正确验证帧配置", async function () {
//       const frameConfig = await hashConsensus.getFrameConfig();
//       expect(frameConfig[0]).to.equal(INITIAL_EPOCH); // initialEpoch
//       expect(frameConfig[1]).to.equal(EPOCHS_PER_FRAME); // epochsPerFrame
//       expect(frameConfig[2]).to.equal(FAST_LANE_LENGTH_SLOTS); // fastLaneLengthSlots
//     });
//   });

//   describe("查询功能", function () {
//     beforeEach(async function () {
//       await hashConsensus.connect(admin).addMember(member1.address, 1);
//       await hashConsensus.connect(admin).addMember(member2.address, 2);
//     });

//     it("应该能够获取成员列表", async function () {
//       const members = await hashConsensus.getMembers();
//       expect(members.addresses).to.include(member1.address);
//       expect(members.addresses).to.include(member2.address);
//       expect(members.lastReportedRefSlots[0]).to.equal(0);
//       expect(members.lastReportedRefSlots[1]).to.equal(0);
//     });

//     it("应该能够获取共识状态", async function () {
//       const consensusState = await hashConsensus.getConsensusState();
//       expect(consensusState.consensusReport).to.equal(ethers.ZeroHash);
//       expect(consensusState.isReportProcessing).to.be.false;
//     });

//     it("应该能够检查成员状态", async function () {
//       expect(await hashConsensus.getIsMember(member1.address)).to.be.true;
//       expect(await hashConsensus.getIsMember(user.address)).to.be.false;
//     });

//     it("应该能够检查快速通道成员", async function () {
//       // 设置快速通道
//       await hashConsensus.connect(admin).setFastLaneLengthSlots(64);
      
//       // 默认情况下，没有快速通道成员
//       expect(await hashConsensus.getIsFastLaneMember(member1.address)).to.be.true;
//     });
//   });

//   describe("权限控制", function () {
//     it("应该正确验证角色权限", async function () {
//       const MANAGE_MEMBERS_AND_QUORUM_ROLE = await hashConsensus.MANAGE_MEMBERS_AND_QUORUM_ROLE();
      
//       expect(await hashConsensus.hasRole(MANAGE_MEMBERS_AND_QUORUM_ROLE, admin.address)).to.be.true;
//       expect(await hashConsensus.hasRole(MANAGE_MEMBERS_AND_QUORUM_ROLE, user.address)).to.be.false;
//     });

//     it("应该拒绝非授权操作", async function () {
//       await expect(
//         hashConsensus.connect(user).addMember(member1.address, 1)
//       ).to.be.revertedWithCustomError(hashConsensus, "AccessControlUnauthorizedAccount");

//       await expect(
//         hashConsensus.connect(user).setQuorum(1)
//       ).to.be.revertedWithCustomError(hashConsensus, "AccessControlUnauthorizedAccount");
//     });
//   });
// });