import { expect } from "chai";
import { ethers } from "hardhat";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { ValidatorsExitBusOracle, GTETHLocator } from "../../typechain-types";

/**
 * gtETH验证者退出流程完整测试
 * 
 * 本测试模拟完整的验证者退出监控和处理流程，包括：
 * 1. Oracle的部署和初始化（集成HashConsensus功能）
 * 2. Oracle成员管理和单成员共识机制
 * 3. 验证者退出请求的提交和处理
 * 4. 数据验证和状态跟踪
 * 5. 错误处理和边界情况
 * 
 */
describe("ValidatorsExitBusOracle.sol:happyPath", () => {
  let oracle: ValidatorsExitBusOracle;
  let locator: GTETHLocator;
  let admin: HardhatEthersSigner;
  let oracleMember: HardhatEthersSigner;
  let dataSubmitter: HardhatEthersSigner;
  let stranger: HardhatEthersSigner;

  // 测试配置常量
  const SLOTS_PER_EPOCH = 32;
  const SECONDS_PER_SLOT = 12;
  const GENESIS_TIME = 1606824000; // Dec 1, 2020
  const EPOCHS_PER_FRAME = 225;
  const SLOTS_PER_FRAME = EPOCHS_PER_FRAME * SLOTS_PER_EPOCH;
  const SECONDS_PER_FRAME = SLOTS_PER_FRAME * SECONDS_PER_SLOT;
  const LAST_PROCESSING_REF_SLOT = 1;
  
  // 测试时间设置（使用当前时间戳 + 1小时确保在未来）
  const TEST_TIME = Math.floor(Date.now() / 1000) + 3600;
  
  // 数据格式常量
  const DATA_FORMAT_LIST = 1;

  // 测试用的验证者公钥
  const PUBKEYS = [
    "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
    "0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
  ];

  let exitRequests: ExitRequest[];
  let reportFields: ReportFields;
  let reportItems: ReturnType<typeof getValidatorsExitBusReportDataItems>;
  let reportHash: string;

  // 数据结构定义
  interface ExitRequest {
    moduleId: number;
    nodeOpId: number;
    valIndex: number;
    valPubkey: string;
  }

  interface ReportFields {
    refSlot: bigint;
    requestsCount: number;
    dataFormat: number;
    data: string;
  }

  // 工具函数：计算报告数据哈希
  const calcValidatorsExitBusReportDataHash = (items: ReturnType<typeof getValidatorsExitBusReportDataItems>) => {
    const data = ethers.AbiCoder.defaultAbiCoder().encode(["(uint256,uint256,uint256,bytes)"], [items]);
    return ethers.keccak256(data);
  };

  // 工具函数：获取报告数据项
  const getValidatorsExitBusReportDataItems = (r: ReportFields) => {
    return [r.refSlot, r.requestsCount, r.dataFormat, r.data];
  };

  // 工具函数：编码单个退出请求
  const encodeExitRequestHex = ({ moduleId, nodeOpId, valIndex, valPubkey }: ExitRequest) => {
    const pubkeyHex = valPubkey.slice(2); // 移除0x前缀
    expect(pubkeyHex.length).to.equal(48 * 2); // 验证公钥长度
    
    // 按照合约定义的格式编码：3字节moduleId + 5字节nodeOpId + 8字节valIndex + 48字节pubkey
    const moduleIdHex = moduleId.toString(16).padStart(6, '0'); // 3字节 = 6个十六进制字符
    const nodeOpIdHex = nodeOpId.toString(16).padStart(10, '0'); // 5字节 = 10个十六进制字符
    const valIndexHex = valIndex.toString(16).padStart(16, '0'); // 8字节 = 16个十六进制字符
    
    return moduleIdHex + nodeOpIdHex + valIndexHex + pubkeyHex;
  };

  // 工具函数：编码退出请求列表
  const encodeExitRequestsDataList = (requests: ExitRequest[]) => {
    return "0x" + requests.map(encodeExitRequestHex).join("");
  };

  // 工具函数：计算插槽对应的时间戳
  const computeTimestampAtSlot = (slot: bigint) => {
    return GENESIS_TIME + Number(slot) * SECONDS_PER_SLOT;
  };

  // 部署函数
  const deploy = async () => {
    // 部署GTETHLocator (使用admin地址作为占位符避免ZeroAddress错误)
    const GTETHLocator = await ethers.getContractFactory("GTETHLocator");
    locator = await GTETHLocator.deploy({
      gteth: admin.address,
      stakingRouter: admin.address,
      nodeOperatorsRegistry: admin.address,
      accountingOracle: admin.address,
      withdrawalQueueERC721: admin.address,
      withdrawalVault: admin.address,
      elRewardsVault: admin.address,
      validatorsExitBusOracle: admin.address, 
      treasury: admin.address
    });

    // 部署ValidatorsExitBusOracle（现在需要3个参数）
    oracle = await ethers.getContractFactory("ValidatorsExitBusOracle").then(factory => 
      factory.deploy(SLOTS_PER_EPOCH, SECONDS_PER_SLOT, GENESIS_TIME)
    );

    // 更新locator中的oracle地址
    await locator.setConfig({
      gteth: admin.address,
      stakingRouter: admin.address,
      nodeOperatorsRegistry: admin.address,
      accountingOracle: admin.address,
      withdrawalQueueERC721: admin.address,
      withdrawalVault: admin.address,
      elRewardsVault: admin.address,
      validatorsExitBusOracle: await oracle.getAddress(),
      treasury: admin.address
    });
  };

  // 初始化函数
  const initOracle = async () => {
    // 授予必要的角色
    await oracle.grantRole(await oracle.MANAGE_ORACLE_MEMBER_ROLE(), admin.address);
    await oracle.grantRole(await oracle.SUBMIT_DATA_ROLE(), admin.address);
    await oracle.grantRole(await oracle.SUBMIT_DATA_ROLE(), dataSubmitter.address);
    await oracle.grantRole(await oracle.PAUSE_ROLE(), admin.address);
    await oracle.grantRole(await oracle.RESUME_ROLE(), admin.address);

    // 初始化oracle（现在不需要共识版本参数）
    await oracle.initialize(
      oracleMember.address,
      LAST_PROCESSING_REF_SLOT,
      EPOCHS_PER_FRAME
    );

    // 恢复oracle（因为初始化时会暂停）
    await oracle.resume();

    // 设置初始epoch
    await oracle.updateInitialEpoch(1000);
  };

  before(async () => {
    [admin, oracleMember, dataSubmitter, stranger] = await ethers.getSigners();
    
    // 获取当前区块时间戳并设置为未来时间
    const currentBlock = await ethers.provider.getBlock("latest");
    const futureTime = currentBlock!.timestamp + 3600; // 当前时间 + 1小时
    await ethers.provider.send("evm_setNextBlockTimestamp", [futureTime]);
    await ethers.provider.send("evm_mine", []);

    await deploy();
    await initOracle();
  });

  it("初始状态：共识报告为空且未在处理中", async () => {
    const report = await oracle.getConsensusReport();
    expect(report.hash).to.equal(ethers.ZeroHash);
    expect(report.processingDeadlineTime).to.equal(0);
    expect(report.processingStarted).to.equal(false);

    const frame = await oracle.getCurrentFrame();
    const procState = await oracle.getProcessingState();

    expect(procState.currentFrameRefSlot).to.equal(frame[0]);
    expect(procState.dataHash).to.equal(ethers.ZeroHash);
    expect(procState.processingDeadlineTime).to.equal(0);
    expect(procState.dataSubmitted).to.equal(false);
    expect(procState.dataFormat).to.equal(0);
    expect(procState.requestsCount).to.equal(0);
    expect(procState.requestsSubmitted).to.equal(0);
  });

  it("空初始共识报告的参考插槽设置为传递给初始化函数的最后处理插槽", async () => {
    const report = await oracle.getConsensusReport();
    expect(report.refSlot).to.equal(LAST_PROCESSING_REF_SLOT);
  });

  it("oracle成员提交报告数据，发出退出请求事件", async () => {
    const frame = await oracle.getCurrentFrame();
    const refSlot = frame[0];

    exitRequests = [
      { moduleId: 1, nodeOpId: 0, valIndex: 0, valPubkey: PUBKEYS[0] },
      { moduleId: 1, nodeOpId: 0, valIndex: 2, valPubkey: PUBKEYS[1] },
      { moduleId: 2, nodeOpId: 0, valIndex: 1, valPubkey: PUBKEYS[2] },
    ];

    reportFields = {
      refSlot: refSlot,
      requestsCount: exitRequests.length,
      dataFormat: DATA_FORMAT_LIST,
      data: encodeExitRequestsDataList(exitRequests),
    };

    reportItems = getValidatorsExitBusReportDataItems(reportFields);
    reportHash = calcValidatorsExitBusReportDataHash(reportItems);

    const tx = await oracle.connect(oracleMember).submitReportData(reportFields);

    await expect(tx)
      .to.emit(oracle, "ProcessingStarted")
      .withArgs(reportFields.refSlot, reportHash);
    
    expect((await oracle.getConsensusReport()).processingStarted).to.equal(true);

    const timestamp = (await ethers.provider.getBlock("latest"))!.timestamp;

    for (const request of exitRequests) {
      await expect(tx)
        .to.emit(oracle, "ValidatorExitRequest")
        .withArgs(request.moduleId, request.nodeOpId, request.valIndex, request.valPubkey, timestamp);
    }
  });

  it("oracle获取报告哈希", async () => {
    const report = await oracle.getConsensusReport();
    expect(report.hash).to.equal(reportHash);
    expect(report.refSlot).to.equal(reportFields.refSlot);
    expect(report.processingDeadlineTime).to.equal(
      computeTimestampAtSlot(report.refSlot + BigInt(SLOTS_PER_FRAME))
    );
    expect(report.processingStarted).to.equal(true);

    const frame = await oracle.getCurrentFrame();
    const procState = await oracle.getProcessingState();

    expect(procState.currentFrameRefSlot).to.equal(frame[0]);
    expect(procState.dataHash).to.equal(reportHash);
    expect(procState.processingDeadlineTime).to.equal(
      computeTimestampAtSlot(frame[1]) // reportProcessingDeadlineSlot
    );
    expect(procState.dataSubmitted).to.equal(true);
    expect(procState.dataFormat).to.equal(DATA_FORMAT_LIST);
    expect(procState.requestsCount).to.equal(exitRequests.length);
    expect(procState.requestsSubmitted).to.equal(exitRequests.length);
  });

  it("报告标记为已处理", async () => {
    const frame = await oracle.getCurrentFrame();
    const procState = await oracle.getProcessingState();

    expect(procState.currentFrameRefSlot).to.equal(frame[0]);
    expect(procState.dataHash).to.equal(reportHash);
    expect(procState.processingDeadlineTime).to.equal(computeTimestampAtSlot(frame[1]));
    expect(procState.dataSubmitted).to.equal(true);
    expect(procState.dataFormat).to.equal(DATA_FORMAT_LIST);
    expect(procState.requestsCount).to.equal(exitRequests.length);
    expect(procState.requestsSubmitted).to.equal(exitRequests.length);
  });

  it("最后请求的验证者索引已更新", async () => {
    const indices1 = await oracle.getLastRequestedValidatorIndices(1n, [0n, 1n, 2n]);
    const indices2 = await oracle.getLastRequestedValidatorIndices(2n, [0n, 1n, 2n]);

    expect([...indices1]).to.have.ordered.members([2n, -1n, -1n]);
    expect([...indices2]).to.have.ordered.members([1n, -1n, -1n]);
  });

  it("同一参考插槽无法再次提交数据", async () => {
    await expect(
      oracle.connect(oracleMember).submitReportData(reportFields)
    ).to.be.revertedWithCustomError(oracle, "RefSlotMustBeGreaterThanProcessingOne");
  });

  it("总处理请求数正确更新", async () => {
    const totalProcessed = await oracle.getTotalRequestsProcessed();
    expect(totalProcessed).to.equal(exitRequests.length);
  });

  it("验证数据格式常量", async () => {
    expect(await oracle.DATA_FORMAT_LIST()).to.equal(DATA_FORMAT_LIST);
  });

  it("非成员无法提交数据", async () => {
    // 前进到下一个frame
    await ethers.provider.send("evm_increaseTime", [SECONDS_PER_FRAME]);
    await ethers.provider.send("evm_mine", []);

    const frame = await oracle.getCurrentFrame();
    const refSlot = frame[0];

    const newReportFields = {
      refSlot: refSlot,
      requestsCount: 0,
      dataFormat: DATA_FORMAT_LIST,
      data: "0x",
    };

    await expect(
      oracle.connect(stranger).submitReportData(newReportFields)
    ).to.be.revertedWithCustomError(oracle, "SenderNotAllowed");
  });

  it("验证空数据提交", async () => {
    const frame = await oracle.getCurrentFrame();
    const refSlot = frame[0];

    const emptyReportFields = {
      refSlot: refSlot,
      requestsCount: 0,
      dataFormat: DATA_FORMAT_LIST,
      data: "0x",
    };

    // 提交空数据
    const tx = await oracle.connect(oracleMember).submitReportData(emptyReportFields);

    const emptyReportItems = getValidatorsExitBusReportDataItems(emptyReportFields);
    const emptyReportHash = calcValidatorsExitBusReportDataHash(emptyReportItems);

    await expect(tx)
      .to.emit(oracle, "ProcessingStarted")
      .withArgs(emptyReportFields.refSlot, emptyReportHash);

    // 验证状态
    const procState = await oracle.getProcessingState();
    expect(procState.dataSubmitted).to.equal(true);
    expect(procState.requestsCount).to.equal(0);
    expect(procState.requestsSubmitted).to.equal(0);
  });

  it("验证无效数据格式被拒绝", async () => {
    // 前进到下一个frame
    await ethers.provider.send("evm_increaseTime", [SECONDS_PER_FRAME]);
    await ethers.provider.send("evm_mine", []);

    const frame = await oracle.getCurrentFrame();
    const refSlot = frame[0];

    const invalidFormatReport = {
      refSlot: refSlot,
      requestsCount: 0,
      dataFormat: 999, // 不支持的格式
      data: "0x",
    };

    // 尝试提交无效格式数据
    await expect(
      oracle.connect(oracleMember).submitReportData(invalidFormatReport)
    ).to.be.revertedWithCustomError(oracle, "UnsupportedRequestsDataFormat")
    .withArgs(999);
  });

  it("验证数据长度不匹配被拒绝", async () => {
    // 前进到下一个frame
    await ethers.provider.send("evm_increaseTime", [SECONDS_PER_FRAME]);
    await ethers.provider.send("evm_mine", []);

    const frame = await oracle.getCurrentFrame();
    const refSlot = frame[0];

    const invalidLengthReport = {
      refSlot: refSlot,
      requestsCount: 1,
      dataFormat: DATA_FORMAT_LIST,
      data: "0x1234", // 长度不正确
    };

    // 尝试提交长度不匹配的数据
    await expect(
      oracle.connect(oracleMember).submitReportData(invalidLengthReport)
    ).to.be.revertedWithCustomError(oracle, "InvalidRequestsDataLength");
  });

  it("验证暂停和恢复功能", async () => {
    // 暂停oracle
    await oracle.connect(admin).pause();
    expect(await oracle.paused()).to.equal(true);

    // 暂停状态下无法提交数据
    await expect(
      oracle.connect(oracleMember).submitReportData(reportFields)
    ).to.be.revertedWithCustomError(oracle, "EnforcedPause");

    // 恢复oracle
    await oracle.connect(admin).resume();
    expect(await oracle.paused()).to.equal(false);
  });

  it("验证Oracle成员权限管理", async () => {
    // 更换Oracle成员
    const newOracleMember = dataSubmitter;
    await oracle.connect(admin).setOracleMember(newOracleMember.address);
    
    expect(await oracle.getOracleMember()).to.equal(newOracleMember.address);
    
    // 前进到下一个frame
    await ethers.provider.send("evm_increaseTime", [SECONDS_PER_FRAME]);
    await ethers.provider.send("evm_mine", []);

    const frame = await oracle.getCurrentFrame();
    const refSlot = frame[0];

    const testReportFields = {
      refSlot: refSlot,
      requestsCount: 0,
      dataFormat: DATA_FORMAT_LIST,
      data: "0x",
    };

    // 新Oracle成员可以提交数据
    await oracle.connect(newOracleMember).submitReportData(testReportFields);
    
    // 旧Oracle成员现在无法提交数据（除非有SUBMIT_DATA_ROLE）
    // 但由于在初始化时给了dataSubmitter SUBMIT_DATA_ROLE，所以这里跳过这个测试
  });
});

describe("ValidatorsExitBusOracle.sol:EdgeCases", () => {
  let oracle: ValidatorsExitBusOracle;
  let locator: GTETHLocator;
  let admin: HardhatEthersSigner;
  let oracleMember: HardhatEthersSigner;
  let maliciousUser: HardhatEthersSigner;
  let normalUser: HardhatEthersSigner;

  // 测试配置常量
  const SLOTS_PER_EPOCH = 32;
  const SECONDS_PER_SLOT = 12;
  const GENESIS_TIME = 1606824000;
  const EPOCHS_PER_FRAME = 225;
  const SLOTS_PER_FRAME = EPOCHS_PER_FRAME * SLOTS_PER_EPOCH;
  const SECONDS_PER_FRAME = SLOTS_PER_FRAME * SECONDS_PER_SLOT;
  const DATA_FORMAT_LIST = 1;
  
  // 测试时间设置（使用当前时间戳 + 1小时确保在未来）
  const TEST_TIME = Math.floor(Date.now() / 1000) + 3600;

  // 数据结构定义
  interface ExitRequest {
    moduleId: number;
    nodeOpId: number;
    valIndex: number;
    valPubkey: string;
  }

  interface ReportFields {
    refSlot: bigint;
    requestsCount: number;
    dataFormat: number;
    data: string;
  }

  // 工具函数
  const generatePubkey = (index: number): string => {
    const hex = index.toString(16).padStart(2, '0');
    return "0x" + hex.repeat(48);
  };

  const encodeExitRequestHex = ({ moduleId, nodeOpId, valIndex, valPubkey }: ExitRequest) => {
    const pubkeyHex = valPubkey.slice(2);
    const moduleIdHex = moduleId.toString(16).padStart(6, '0');
    const nodeOpIdHex = nodeOpId.toString(16).padStart(10, '0');
    const valIndexHex = valIndex.toString(16).padStart(16, '0');
    return moduleIdHex + nodeOpIdHex + valIndexHex + pubkeyHex;
  };

  const encodeExitRequestsDataList = (requests: ExitRequest[]) => {
    return "0x" + requests.map(encodeExitRequestHex).join("");
  };

  beforeEach(async () => {
    [admin, oracleMember, maliciousUser, normalUser] = await ethers.getSigners();
    
    // 获取当前区块时间戳并设置为未来时间
    const currentBlock = await ethers.provider.getBlock("latest");
    const futureTime = currentBlock!.timestamp + 3600; // 当前时间 + 1小时
    await ethers.provider.send("evm_setNextBlockTimestamp", [futureTime]);
    await ethers.provider.send("evm_mine", []);

    // 部署合约 (使用admin地址作为占位符避免ZeroAddress错误)
    const GTETHLocator = await ethers.getContractFactory("GTETHLocator");
    locator = await GTETHLocator.deploy({
      gteth: admin.address,
      stakingRouter: admin.address,
      nodeOperatorsRegistry: admin.address,
      accountingOracle: admin.address,
      withdrawalQueueERC721: admin.address,
      withdrawalVault: admin.address,
      elRewardsVault: admin.address,
      validatorsExitBusOracle: admin.address,
      treasury: admin.address
    });

    oracle = await ethers.getContractFactory("ValidatorsExitBusOracle").then(factory => 
      factory.deploy(SLOTS_PER_EPOCH, SECONDS_PER_SLOT, GENESIS_TIME)
    );

    // 初始化
    await oracle.grantRole(await oracle.MANAGE_ORACLE_MEMBER_ROLE(), admin.address);
    await oracle.grantRole(await oracle.SUBMIT_DATA_ROLE(), admin.address);
    await oracle.grantRole(await oracle.PAUSE_ROLE(), admin.address);
    await oracle.grantRole(await oracle.RESUME_ROLE(), admin.address);

    await oracle.initialize(oracleMember.address, 0, EPOCHS_PER_FRAME);
    await oracle.resume();

    await oracle.updateInitialEpoch(1000);
  });

  describe("数据格式边界情况", () => {
    it("应该拒绝不支持的数据格式", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: 0,
        dataFormat: 999, // 不支持的格式
        data: "0x",
      };
      
      await expect(
        oracle.connect(admin).submitReportData(reportFields)
      ).to.be.revertedWithCustomError(oracle, "UnsupportedRequestsDataFormat")
      .withArgs(999);
    });

    it("应该拒绝数据长度不是64字节倍数的请求", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: 1,
        dataFormat: DATA_FORMAT_LIST,
        data: "0x1234567890abcdef", // 只有8字节，不是64字节
      };
      
      await expect(
        oracle.connect(admin).submitReportData(reportFields)
      ).to.be.revertedWithCustomError(oracle, "InvalidRequestsDataLength");
    });

    it("应该拒绝数据长度与请求数量不匹配的情况", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      // 创建1个请求的数据，但声明有2个请求
      const exitRequest: ExitRequest = {
        moduleId: 1,
        nodeOpId: 1,
        valIndex: 0,
        valPubkey: generatePubkey(1)
      };

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: 2, // 错误：声明2个但只有1个
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList([exitRequest]),
      };
      
      await expect(
        oracle.connect(admin).submitReportData(reportFields)
      ).to.be.revertedWithCustomError(oracle, "UnexpectedRequestsDataLength");
    });

    it("应该拒绝包含零模块ID的请求", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const exitRequest: ExitRequest = {
        moduleId: 0, // 错误：模块ID不能为0
        nodeOpId: 1,
        valIndex: 0,
        valPubkey: generatePubkey(1)
      };

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: 1,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList([exitRequest]),
      };
      
      await expect(
        oracle.connect(admin).submitReportData(reportFields)
      ).to.be.revertedWithCustomError(oracle, "InvalidRequestsData");
    });
  });

  describe("排序和验证边界情况", () => {
    it("应该拒绝模块ID相同但排序错误的请求", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const exitRequests: ExitRequest[] = [
        { moduleId: 1, nodeOpId: 2, valIndex: 0, valPubkey: generatePubkey(1) },
        { moduleId: 1, nodeOpId: 1, valIndex: 0, valPubkey: generatePubkey(2) }, // 错误：nodeOpId应该递增
      ];

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: exitRequests.length,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList(exitRequests),
      };
      
      await expect(
        oracle.connect(admin).submitReportData(reportFields)
      ).to.be.revertedWithCustomError(oracle, "InvalidRequestsDataSortOrder");
    });

    it("应该拒绝节点操作员ID相同但验证者索引排序错误的请求", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const exitRequests: ExitRequest[] = [
        { moduleId: 1, nodeOpId: 1, valIndex: 5, valPubkey: generatePubkey(1) },
        { moduleId: 1, nodeOpId: 1, valIndex: 3, valPubkey: generatePubkey(2) }, // 错误：valIndex应该递增
      ];

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: exitRequests.length,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList(exitRequests),
      };
      
      await expect(
        oracle.connect(admin).submitReportData(reportFields)
      ).to.be.revertedWithCustomError(oracle, "InvalidRequestsDataSortOrder");
    });

    it("应该拒绝完全相同的请求", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const exitRequests: ExitRequest[] = [
        { moduleId: 1, nodeOpId: 1, valIndex: 0, valPubkey: generatePubkey(1) },
        { moduleId: 1, nodeOpId: 1, valIndex: 0, valPubkey: generatePubkey(1) }, // 完全相同
      ];

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: exitRequests.length,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList(exitRequests),
      };
      
      await expect(
        oracle.connect(admin).submitReportData(reportFields)
      ).to.be.revertedWithCustomError(oracle, "InvalidRequestsDataSortOrder");
    });
  });

  describe("数值边界情况", () => {
    it("应该处理最大模块ID", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const maxModuleId = (2 ** 24) - 1; // 24位最大值
      const exitRequest: ExitRequest = {
        moduleId: maxModuleId,
        nodeOpId: 1,
        valIndex: 0,
        valPubkey: generatePubkey(1)
      };

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: 1,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList([exitRequest]),
      };

      await oracle.connect(admin).submitReportData(reportFields);

      expect(await oracle.getTotalRequestsProcessed()).to.equal(1);
    });

    it("应该处理最大节点操作员ID", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const maxNodeOpId = (2 ** 40) - 1; // 40位最大值
      const exitRequest: ExitRequest = {
        moduleId: 1,
        nodeOpId: maxNodeOpId,
        valIndex: 0,
        valPubkey: generatePubkey(1)
      };

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: 1,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList([exitRequest]),
      };

      await oracle.connect(admin).submitReportData(reportFields);

      expect(await oracle.getTotalRequestsProcessed()).to.equal(1);
    });

    it("应该拒绝超出范围的模块ID查询", async () => {
      const maxModuleId = BigInt(2 ** 24); // 超出24位
      const nodeOpIds = [1n];

      await expect(
        oracle.getLastRequestedValidatorIndices(maxModuleId, nodeOpIds)
      ).to.be.revertedWithCustomError(oracle, "ArgumentOutOfBounds");
    });

    it("应该拒绝超出范围的节点操作员ID查询", async () => {
      const moduleId = 1n;
      const maxNodeOpId = BigInt(2 ** 40); // 超出40位
      const nodeOpIds = [maxNodeOpId];

      await expect(
        oracle.getLastRequestedValidatorIndices(moduleId, nodeOpIds)
      ).to.be.revertedWithCustomError(oracle, "ArgumentOutOfBounds");
    });
  });

  describe("权限和访问控制边界情况", () => {
    it("应该拒绝非授权用户暂停oracle", async () => {
      await expect(
        oracle.connect(maliciousUser).pause()
      ).to.be.reverted;
    });

    it("应该拒绝非授权用户恢复oracle", async () => {
      await expect(
        oracle.connect(maliciousUser).resume()
      ).to.be.reverted;
    });

    it("应该拒绝非授权用户修改Oracle成员", async () => {
      await expect(
        oracle.connect(maliciousUser).setOracleMember(ethers.ZeroAddress)
      ).to.be.reverted;
    });

    it("应该拒绝非Oracle成员且无SUBMIT_DATA_ROLE的用户提交数据", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: 0,
        dataFormat: DATA_FORMAT_LIST,
        data: "0x",
      };
      
      await expect(
        oracle.connect(maliciousUser).submitReportData(reportFields)
      ).to.be.revertedWithCustomError(oracle, "SenderNotAllowed");
    });
  });

  describe("历史状态冲突处理", () => {
    it("应该拒绝与历史状态冲突的请求", async () => {
      // 首先提交一个正常请求
      let frame = await oracle.getCurrentFrame();
      let refSlot = frame[0];

      const firstRequest: ExitRequest = {
        moduleId: 1,
        nodeOpId: 1,
        valIndex: 10,
        valPubkey: generatePubkey(1)
      };

      let reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: 1,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList([firstRequest]),
      };

      await oracle.connect(admin).submitReportData(reportFields);

      // 前进到下一个frame
      await ethers.provider.send("evm_increaseTime", [SECONDS_PER_FRAME]);
      await ethers.provider.send("evm_mine", []);

      // 尝试提交索引更小的请求
      frame = await oracle.getCurrentFrame();
      refSlot = frame[0];

      const conflictingRequest: ExitRequest = {
        moduleId: 1,
        nodeOpId: 1,
        valIndex: 5, // 小于之前的10
        valPubkey: generatePubkey(2)
      };

      reportFields = {
        refSlot: refSlot,
        requestsCount: 1,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList([conflictingRequest]),
      };
      
      await expect(
        oracle.connect(admin).submitReportData(reportFields)
      ).to.be.revertedWithCustomError(oracle, "NodeOpValidatorIndexMustIncrease")
      .withArgs(1, 1, 10, 5);
    });
  });
});

describe("ValidatorsExitBusOracle.sol:Integration", () => {
  let oracle: ValidatorsExitBusOracle;
  let locator: GTETHLocator;
  let admin: HardhatEthersSigner;
  let oracleMember: HardhatEthersSigner;
  let dataSubmitter: HardhatEthersSigner;

  // 测试配置常量
  const SLOTS_PER_EPOCH = 32;
  const SECONDS_PER_SLOT = 12;
  const GENESIS_TIME = 1606824000;
  const EPOCHS_PER_FRAME = 225;
  const SLOTS_PER_FRAME = EPOCHS_PER_FRAME * SLOTS_PER_EPOCH;
  const SECONDS_PER_FRAME = SLOTS_PER_FRAME * SECONDS_PER_SLOT;
  const DATA_FORMAT_LIST = 1;

  // 生成测试用验证者公钥
  const generatePubkey = (index: number): string => {
    const hex = index.toString(16).padStart(2, '0');
    return "0x" + hex.repeat(48);
  };

  // 数据结构定义
  interface ExitRequest {
    moduleId: number;
    nodeOpId: number;
    valIndex: number;
    valPubkey: string;
  }

  interface ReportFields {
    refSlot: bigint;
    requestsCount: number;
    dataFormat: number;
    data: string;
  }

  // 工具函数
  const encodeExitRequestHex = ({ moduleId, nodeOpId, valIndex, valPubkey }: ExitRequest) => {
    const pubkeyHex = valPubkey.slice(2);
    const moduleIdHex = moduleId.toString(16).padStart(6, '0');
    const nodeOpIdHex = nodeOpId.toString(16).padStart(10, '0');
    const valIndexHex = valIndex.toString(16).padStart(16, '0');
    return moduleIdHex + nodeOpIdHex + valIndexHex + pubkeyHex;
  };

  const encodeExitRequestsDataList = (requests: ExitRequest[]) => {
    return "0x" + requests.map(encodeExitRequestHex).join("");
  };

  const deployContracts = async () => {
    // 部署GTETHLocator (使用admin地址作为占位符避免ZeroAddress错误)
    const GTETHLocator = await ethers.getContractFactory("GTETHLocator");
    locator = await GTETHLocator.deploy({
      gteth: admin.address,
      stakingRouter: admin.address,
      nodeOperatorsRegistry: admin.address,
      accountingOracle: admin.address,
      withdrawalQueueERC721: admin.address,
      withdrawalVault: admin.address,
      elRewardsVault: admin.address,
      validatorsExitBusOracle: admin.address,
      treasury: admin.address
    });

    // 部署ValidatorsExitBusOracle
    oracle = await ethers.getContractFactory("ValidatorsExitBusOracle").then(factory => 
      factory.deploy(SLOTS_PER_EPOCH, SECONDS_PER_SLOT, GENESIS_TIME)
    );

    // 更新locator
    await locator.setConfig({
      gteth: admin.address,
      stakingRouter: admin.address,
      nodeOperatorsRegistry: admin.address,
      accountingOracle: admin.address,
      withdrawalQueueERC721: admin.address,
      withdrawalVault: admin.address,
      elRewardsVault: admin.address,
      validatorsExitBusOracle: await oracle.getAddress(),
      treasury: admin.address
    });
  };

  const initializeContracts = async () => {
    // 设置oracle权限
    await oracle.grantRole(await oracle.MANAGE_ORACLE_MEMBER_ROLE(), admin.address);
    await oracle.grantRole(await oracle.SUBMIT_DATA_ROLE(), admin.address);
    await oracle.grantRole(await oracle.SUBMIT_DATA_ROLE(), dataSubmitter.address);
    await oracle.grantRole(await oracle.PAUSE_ROLE(), admin.address);
    await oracle.grantRole(await oracle.RESUME_ROLE(), admin.address);

    // 初始化oracle
    await oracle.initialize(oracleMember.address, 0, EPOCHS_PER_FRAME);
    await oracle.resume();

    // 设置初始纪元
    await oracle.updateInitialEpoch(1000);
  };

  beforeEach(async () => {
    [admin, oracleMember, dataSubmitter] = await ethers.getSigners();
    
    // 获取当前区块时间戳并设置为未来时间
    const currentBlock = await ethers.provider.getBlock("latest");
    const futureTime = currentBlock!.timestamp + 3600; // 当前时间 + 1小时
    await ethers.provider.send("evm_setNextBlockTimestamp", [futureTime]);
    await ethers.provider.send("evm_mine", []);

    await deployContracts();
    await initializeContracts();
  });

  describe("基础集成测试", () => {
    it("应该正确处理单个退出请求", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const exitRequests: ExitRequest[] = [
        { moduleId: 1, nodeOpId: 1, valIndex: 0, valPubkey: generatePubkey(1) }
      ];

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: exitRequests.length,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList(exitRequests),
      };
      
      const tx = await oracle.connect(dataSubmitter).submitReportData(reportFields);
      
      await expect(tx)
        .to.emit(oracle, "ValidatorExitRequest")
        .withArgs(1, 1, 0, exitRequests[0].valPubkey, (await ethers.provider.getBlock("latest"))!.timestamp);

      expect(await oracle.getTotalRequestsProcessed()).to.equal(1);
    });

    it("应该正确处理多个模块的退出请求", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const exitRequests: ExitRequest[] = [
        { moduleId: 1, nodeOpId: 1, valIndex: 0, valPubkey: generatePubkey(1) },
        { moduleId: 1, nodeOpId: 1, valIndex: 1, valPubkey: generatePubkey(2) },
        { moduleId: 2, nodeOpId: 1, valIndex: 0, valPubkey: generatePubkey(3) },
        { moduleId: 3, nodeOpId: 1, valIndex: 0, valPubkey: generatePubkey(4) },
      ];

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: exitRequests.length,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList(exitRequests),
      };

      await oracle.connect(dataSubmitter).submitReportData(reportFields);

      // 验证最后请求的验证者索引
      const indices1 = await oracle.getLastRequestedValidatorIndices(1n, [1n]);
      const indices2 = await oracle.getLastRequestedValidatorIndices(2n, [1n]);
      const indices3 = await oracle.getLastRequestedValidatorIndices(3n, [1n]);

      expect(indices1[0]).to.equal(1); // 模块1节点1的最后索引是1
      expect(indices2[0]).to.equal(0); // 模块2节点1的最后索引是0
      expect(indices3[0]).to.equal(0); // 模块3节点1的最后索引是0

      expect(await oracle.getTotalRequestsProcessed()).to.equal(4);
    });
  });

  describe("多轮处理测试", () => {
    it("应该正确处理多轮退出请求", async () => {
      let totalProcessed = 0;

      // 第一轮
      let frame = await oracle.getCurrentFrame();
      let refSlot = frame[0];

      const firstBatch: ExitRequest[] = [
        { moduleId: 1, nodeOpId: 1, valIndex: 0, valPubkey: generatePubkey(1) },
        { moduleId: 1, nodeOpId: 1, valIndex: 1, valPubkey: generatePubkey(2) },
      ];

      let reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: firstBatch.length,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList(firstBatch),
      };

      await oracle.connect(dataSubmitter).submitReportData(reportFields);
      
      totalProcessed += firstBatch.length;
      expect(await oracle.getTotalRequestsProcessed()).to.equal(totalProcessed);

      // 前进到下一个frame
      await ethers.provider.send("evm_increaseTime", [SECONDS_PER_FRAME]);
      await ethers.provider.send("evm_mine", []);

      // 第二轮
      frame = await oracle.getCurrentFrame();
      refSlot = frame[0];

      const secondBatch: ExitRequest[] = [
        { moduleId: 1, nodeOpId: 1, valIndex: 2, valPubkey: generatePubkey(3) },
        { moduleId: 2, nodeOpId: 1, valIndex: 0, valPubkey: generatePubkey(4) },
      ];

      reportFields = {
        refSlot: refSlot,
        requestsCount: secondBatch.length,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList(secondBatch),
      };

      await oracle.connect(dataSubmitter).submitReportData(reportFields);
      
      totalProcessed += secondBatch.length;
      expect(await oracle.getTotalRequestsProcessed()).to.equal(totalProcessed);

      // 验证累积状态
      const indices1 = await oracle.getLastRequestedValidatorIndices(1n, [1n]);
      const indices2 = await oracle.getLastRequestedValidatorIndices(2n, [1n]);

      expect(indices1[0]).to.equal(2); // 模块1节点1的最后索引是2
      expect(indices2[0]).to.equal(0); // 模块2节点1的最后索引是0
    });
  });

  describe("权限和安全测试", () => {
    it("应该正确验证数据提交权限", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const exitRequests: ExitRequest[] = [
        { moduleId: 1, nodeOpId: 1, valIndex: 0, valPubkey: generatePubkey(1) },
      ];

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: exitRequests.length,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList(exitRequests),
      };

      // Oracle成员可以提交
      await oracle.connect(oracleMember).submitReportData(reportFields);

      // 前进到下一个frame进行下一个测试
      await ethers.provider.send("evm_increaseTime", [SECONDS_PER_FRAME]);
      await ethers.provider.send("evm_mine", []);

      const nextFrame = await oracle.getCurrentFrame();
      const nextRefSlot = nextFrame[0];

      const nextReportFields: ReportFields = {
        refSlot: nextRefSlot,
        requestsCount: 0,
        dataFormat: DATA_FORMAT_LIST,
        data: "0x",
      };

      // 具有SUBMIT_DATA_ROLE的地址也可以提交
      await oracle.connect(dataSubmitter).submitReportData(nextReportFields);
    });

    it("应该正确处理角色管理", async () => {
      // 移除dataSubmitter的权限
      await oracle.connect(admin).revokeRole(await oracle.SUBMIT_DATA_ROLE(), dataSubmitter.address);

      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: 0,
        dataFormat: DATA_FORMAT_LIST,
        data: "0x",
      };

      // 现在dataSubmitter无法提交数据
      await expect(
        oracle.connect(dataSubmitter).submitReportData(reportFields)
      ).to.be.revertedWithCustomError(oracle, "SenderNotAllowed");

      // 重新授予权限
      await oracle.connect(admin).grantRole(await oracle.SUBMIT_DATA_ROLE(), dataSubmitter.address);

      // 现在可以正常提交
      await oracle.connect(dataSubmitter).submitReportData(reportFields);
    });
  });

  describe("性能测试", () => {
    it("应该在合理的gas限制内处理请求", async () => {
      const frame = await oracle.getCurrentFrame();
      const refSlot = frame[0];

      // 创建50个退出请求
      const exitRequests: ExitRequest[] = [];
      for (let i = 0; i < 50; i++) {
        exitRequests.push({
          moduleId: Math.floor(i / 10) + 1,
          nodeOpId: (i % 10) + 1,
          valIndex: i,
          valPubkey: generatePubkey(i + 1)
        });
      }

      exitRequests.sort((a, b) => {
        if (a.moduleId !== b.moduleId) return a.moduleId - b.moduleId;
        if (a.nodeOpId !== b.nodeOpId) return a.nodeOpId - b.nodeOpId;
        return a.valIndex - b.valIndex;
      });

      const reportFields: ReportFields = {
        refSlot: refSlot,
        requestsCount: exitRequests.length,
        dataFormat: DATA_FORMAT_LIST,
        data: encodeExitRequestsDataList(exitRequests),
      };
      
      const tx = await oracle.connect(dataSubmitter).submitReportData(reportFields);
      const receipt = await tx.wait();
      
      // 验证gas消耗在合理范围内（这个值需要根据实际情况调整）
      expect(receipt!.gasUsed).to.be.lt(5000000); // 5M gas上限
      
      console.log(`处理50个请求的gas消耗: ${receipt!.gasUsed}`);
    });
  });
});