/**
 * gtETH 验证者退出判断逻辑
 * 
 * 包含ValidatorsExitBusOracle报告提交
 */

import { ethers } from 'ethers';
import axios from "axios";

// ===== 类型定义 =====

interface ValidatorInfo {
  index: number;
  pubkey: string;
  balance: bigint; // Gwei
  effectiveBalance: bigint; // Gwei
  status: string;
  activationEpoch: number;
  exitEpoch?: number;
  withdrawableEpoch?: number;
  slashed: boolean;
}

interface BlockStamp {
  slot: number;
  epoch: number;
  blockHash: string;
  blockTimestamp: number;
}

interface ValidatorExitOrder {
  validatorIndex: number;
  stakingModuleId: number;
  nodeOperatorId: number;
  score: number;
}

interface ExitJudgmentResult {
  shouldExit: boolean;
  validatorsToExit: ValidatorExitOrder[];
  deficit: bigint; // Wei
  availableBalance: bigint; // Wei
  unfinalizedWithdrawals: bigint; // Wei
  reasoning: string;
  dataSource: DataSourceInfo;
}

interface DataSourceInfo {
  beaconChainAPIs: string[];
  contractCalls: string[];
  calculations: string[];
}

interface ValidatorExitReport {
  refSlot: number;
  requestsCount: number;
  dataFormat: number;
  data: string;
}

interface OracleInstance {
  id: number;
  name: string;
  address: string;
  privateKey: string;
}

// ===== 核心退出判断逻辑类 =====

export class ValidatorExitJudgment {
  private beaconNodeUrl: string;
  private executionRpcUrl: string;
  private validatorsExitBusOracleAddress: string;
  private gtETHAddress: string;
  private withdrawalQueueERC721Address: string;
  private withdrawalVaultAddress: string;
  private executionLayerRewardsVaultAddress: string;
  private nodeOperatorsRegistryAddress: string;
  private provider: ethers.JsonRpcProvider;
  private oracles: OracleInstance[];

  constructor(
    beaconNodeUrl: string,
    executionRpcUrl: string,
    validatorsExitBusOracleAddress: string,
    gtETHAddress: string,
    withdrawalQueueERC721Address: string,
    withdrawalVaultAddress: string,
    executionLayerRewardsVaultAddress: string,
    nodeOperatorsRegistryAddress: string
  ) {
    this.beaconNodeUrl = beaconNodeUrl;
    this.executionRpcUrl = executionRpcUrl;
    this.validatorsExitBusOracleAddress = validatorsExitBusOracleAddress;
    this.gtETHAddress = gtETHAddress;
    this.withdrawalQueueERC721Address = withdrawalQueueERC721Address;
    this.withdrawalVaultAddress = withdrawalVaultAddress;
    this.executionLayerRewardsVaultAddress = executionLayerRewardsVaultAddress;
    this.nodeOperatorsRegistryAddress = nodeOperatorsRegistryAddress;
    this.provider = new ethers.JsonRpcProvider(executionRpcUrl);
    this.oracles = this.initializeOracles();
  }

  /**
   * 初始化Oracle实例
   */
  private initializeOracles(): OracleInstance[] {
    return [
      {
        id: 1,
        name: 'Oracle-1',
        address: '0x87704E6B466715b75e21A81d83B6FdB4AC7239a3',
        privateKey: 'b4a0b87f3aaa30cf8201ef57f8b4695255ca2f2096e558f3847f51141ad79c3f'
      }
    ];
  }

  /**
   * 主要的退出判断逻辑 - 包含ValidatorsExitBusOracle发起退出验证者事件流程
   * 
   * 完整流程：
   * 1. 从信标链获取当前状态
   * 2. 从合约获取未完成提取金额  
   * 3. 计算可用余额
   * 4. 判断是否需要退出验证者
   * 5. 发起退出验证者事件
   */
  async judgeValidatorExit(): Promise<ExitJudgmentResult> {
    const dataSource: DataSourceInfo = {
      beaconChainAPIs: [],
      contractCalls: [],
      calculations: []
    };

    try {
      // 1. 获取当前区块状态
      console.log('🔍 Step 1: Getting current block state...');
      console.log('----------------------------------------------------------------------------');
      const blockStamp = await this.getCurrentBlockStamp();
      dataSource.beaconChainAPIs.push('GET /eth/v2/beacon/blocks/head');
      console.log('----------------------------------------------------------------------------');

      // 2. 获取未完成的提取金额 (ETH数量)
      console.log('🔍 Step 2: Getting unfinalized withdrawal amount...');
      console.log('----------------------------------------------------------------------------');
      const unfinalizedWithdrawals = await this.getUnfinalizedWithdrawalAmount();
      dataSource.contractCalls.push('WithdrawalQueueERC721.getWithdrawalRequest()');
      dataSource.contractCalls.push('WithdrawalQueueERC721.currentRequestId()');
      dataSource.contractCalls.push('WithdrawalQueueERC721.lastFinalizeId()');

      console.log(`💰 Unfinalized withdrawals: ${ethers.formatEther(unfinalizedWithdrawals)} ETH`);
      console.log('----------------------------------------------------------------------------');
      
      // 3. 如果没有未完成的提取，不需要退出验证者
      if (unfinalizedWithdrawals === 0n) {
        return {
          shouldExit: false,
          validatorsToExit: [],
          deficit: 0n,
          availableBalance: 0n,
          unfinalizedWithdrawals,
          reasoning: 'No unfinalized withdrawals, no need to exit validators',
          dataSource
        };
      }
      
      // 4. 计算当前可用余额 (ETH数量)
      console.log('🔍 Step 3: Calculating available balance...');
      console.log('----------------------------------------------------------------------------');
      const availableBalance = await this.getTotalAvailableBalance();
      dataSource.contractCalls.push('ExecutionLayerRewardsVault.balance');
      dataSource.contractCalls.push('WithdrawalVault.balance');
      dataSource.contractCalls.push('GTETH.getBufferedEther()');
      dataSource.beaconChainAPIs.push('GET /eth/v1/beacon/states/head/validators');
      dataSource.calculations.push('Predicted future rewards (225 epochs/1 days)');

      console.log(`💰 Available balance: ${ethers.formatEther(availableBalance)} ETH`);

      // 5. 判断余额是否足够 (都以ETH为单位比较)
      if (availableBalance >= unfinalizedWithdrawals) {
        return {
          shouldExit: false,
          validatorsToExit: [],
          deficit: 0n,
          availableBalance,
          unfinalizedWithdrawals,
          reasoning: 'Available balance sufficient, no need to exit validators',
          dataSource
        };
      }

      // 7. 计算余额不足 (ETH为单位)
      const deficit = unfinalizedWithdrawals - availableBalance;
      console.log(`⚠️  Balance deficit: ${ethers.formatEther(deficit)} ETH`);
      /* 
        这里需要判断deficit是否大于200000000000000000000n，大于这个值，则需要退出验证者，否则不需要退出验证者，直接调用submit补充池子（具体数值待确定）
        （是否在运行当前程序时间的两天后补充池子待确定）
      */
      // if (deficit < 200000000000000000000n) {
      //   // 直接调用GTETH的submit方法补充buffer池子
      //   const abi = [
      //     "function submit() external payable",
      //   ]
      //   const gtETH = new ethers.Contract(this.gtETHAddress, abi, this.provider);
      //   await gtETH.submit({ value: deficit });
      //   return {
      //     shouldExit: true,
      //     validatorsToExit: [],
      //     deficit: 0n,
      //     availableBalance: 0n,
      //     unfinalizedWithdrawals,
      //     reasoning: 'need to submit buffer',
      //     dataSource
      //   };
      // }

      // 8. 计算需要退出的验证者数量
      const validatorsNeeded = this.calculateValidatorsNeeded(deficit);
      console.log(`🎯 Validators needed: ~${validatorsNeeded}`);
      dataSource.calculations.push('Validators needed = (deficit / 32 ETH) + 1');
      console.log('----------------------------------------------------------------------------');

      // 9. 获取验证者退出顺序
      console.log('🔍 Step 4: Calculating validator exit order...');
      console.log('----------------------------------------------------------------------------');
      const validatorsToExit = await this.calculateValidatorExitOrder(validatorsNeeded);
      dataSource.beaconChainAPIs.push('GET /eth/v1/beacon/states/head/validators (filtered by gtETH)');
      console.log('----------------------------------------------------------------------------');

      // 10. 执行Oracle上报数据执行退出事件发起流程
      console.log('🔍 Step 5: Starting ValidatorsExitBusOracle process...');
      console.log('----------------------------------------------------------------------------');
      const validatorsExitBusOracleResult = await this.executeValidatorsExitBusOracleFlow(validatorsToExit, blockStamp);
      console.log('🔍 ValidatorsExitBusOracle process result:', validatorsExitBusOracleResult);
      dataSource.contractCalls.push('ValidatorsExitBusOracle.getCurrentFrame()');
      dataSource.contractCalls.push('ValidatorsExitBusOracle.submitReportData()');
      console.log('----------------------------------------------------------------------------');

      return {
        shouldExit: true,
        validatorsToExit,
        deficit,
        availableBalance,
        unfinalizedWithdrawals,
        reasoning: `Need to exit ${validatorsToExit.length} validators to cover ${ethers.formatEther(deficit)} ETH deficit.`,
        dataSource
      };

    } catch (error) {
      console.error('❌ Error in validator exit judgment:', error);
      throw error;
    }
  }

  /**
   * 获取当前区块状态
   * 
   * API调用:
   * - GET /eth/v2/beacon/blocks/head - 获取最新区块信息
   */
  private async getCurrentBlockStamp(): Promise<BlockStamp> {
    try {
      console.log('📋 Beacon API call: GET /eth/v2/beacon/blocks/head');

      // 获取最新区块信息
      const response = await axios.get(`${this.beaconNodeUrl}/eth/v2/beacon/blocks/head`);
      const block = response.data.data;
      const slot = Number(block.message.slot);
      const epoch = Math.floor(slot / 32);  // 每个 epoch 有 32 个 slot
      const blockHash = block.message.body.execution_payload.block_hash;
      const blockTimestamp = Number(block.message.body.execution_payload.timestamp);
      
      console.log(`📊 Current block: slot=${slot}, epoch=${epoch}`);
      console.log(`📊 Block hash: ${blockHash}`);
      console.log(`📊 Block timestamp: ${blockTimestamp}`);

      return {
        slot,
        epoch,
        blockHash,
        blockTimestamp
      };
    } catch (error) {
      console.error('Error getting current block stamp:', error);
      throw error;
    }
  }

  /**
   * 获取未完成的提取金额 (返回 ETH 数量)
   * 
   * 合约调用:
   * - WithdrawalQueueERC721.getWithdrawalRequest() - 获取未完成的gtETH提取金额
   * - WithdrawalQueueERC721.currentRequestId() - 获取最后一个请求ID
   * - WithdrawalQueueERC721.lastFinalizeId() - 获取最后一个已完成的请求ID
   */
  protected async getUnfinalizedWithdrawalAmount(): Promise<bigint> {
    try {
      /*
        这里应该调用WithdrawalQueueERC721合约
        实际应该是如下代码
      */
      // const abi = [
      //   "function getWithdrawalRequest(uint256 _requestId) external view returns (uint256 amountOfETH, uint256 shares, uint256 timestamp)",
      //   "function currentRequestId() external view returns (uint256)",
      //   "function lastFinalizeId() external view returns (uint256)",
      // ]
      // const withdrawalQueueERC721 = new ethers.Contract(this.withdrawalQueueERC721Address, abi, this.provider);
      // const currentRequestId = await withdrawalQueueERC721.currentRequestId();
      // const lastFinalizeId = await withdrawalQueueERC721.lastFinalizeId();
      // const currentWithdrawalRequests = await withdrawalQueueERC721.getWithdrawalRequest(currentRequestId);
      // const lastFinalizedWithdrawalRequests = await withdrawalQueueERC721.getWithdrawalRequest(lastFinalizeId);

      // console.log('📋 Contract call: WithdrawalQueueERC721.getWithdrawalRequest()');
      // console.log('📋 Contract call: WithdrawalQueueERC721.currentRequestId()');
      // console.log('📋 Contract call: WithdrawalQueueERC721.lastFinalizeId()');
      // return BigInt(currentWithdrawalRequests.cumulativeETHAmount - lastFinalizedWithdrawalRequests.cumulativeETHAmount);
      
      // 模拟返回：假设有32 ETH的未完成提取
      return ethers.parseEther('32'); // 返回ETH数量
    } catch (error) {
      console.error('Error getting unfinalized withdrawal amount:', error);
      return 0n;
    }
  }

  /**
   * 获取总可用余额
   * 
   * 包括以下来源的余额：
   * 1. 执行层奖励库 (ExecutionLayerRewardsVault)
   * 2. 提取库 (WithdrawalVault)  
   * 3. 缓冲ETH (GTETH.getBufferedEther)
   * 4. 预测的未来奖励
   * 
   * 合约调用:
   * - ExecutionLayerRewardsVault.balance
   * - WithdrawalVault.balance
   * - GTETH.getBufferedEther()
   * 
   * 信标链API调用:
   * - GET /eth/v1/beacon/states/head/validators - 获取验证者信息用于奖励预测
   */
  protected async getTotalAvailableBalance(): Promise<bigint> {
    try {
      // 1. 执行层奖励库余额（单位：wei）(这里需要减掉运营商5%以及国库5%)
      const executionLayerRewardsVaultBalanceWei = await this.provider.getBalance(this.executionLayerRewardsVaultAddress);
      const elBalance = executionLayerRewardsVaultBalanceWei * 9n / 10n; // BigInt
      
      // 2. 提取库余额
      const withdrawalVaultBalanceWei = await this.provider.getBalance(this.withdrawalVaultAddress);
      const withdrawalBalance = withdrawalVaultBalanceWei; // BigInt
      
      // 3. 缓冲ETH余额
      const abi = [
        "function protocolState() external view returns (uint256 bufferedETH, uint256 depositedValidators, uint256 clValidators, uint256 clBalance, uint256 pendingWithdrawals)",
      ];
      const gtETH = new ethers.Contract(this.gtETHAddress, abi, this.provider);
      const protocolState = await gtETH.protocolState();
      const bufferBalance = BigInt(protocolState.bufferedETH); // 确保是 bigint
  
      // // 4. 预测未来奖励（这里根据预言机报告的周期来预测未来的奖励，225需要修改）
      // const futureRewards = await this.predictFutureRewards(blockStamp || await this.getCurrentBlockStamp(), 225);
      // console.log('futureRewards', ethers.formatEther(futureRewards));
  
      // 5. 全部相加
      const totalBalance = elBalance + withdrawalBalance + bufferBalance;
  
      console.log(`💰 Balance breakdown:`);
      console.log(`   - EL Rewards: ${ethers.formatEther(elBalance)} ETH`);
      console.log(`   - Withdrawal: ${ethers.formatEther(withdrawalBalance)} ETH`);
      console.log(`   - Buffer: ${ethers.formatEther(bufferBalance)} ETH`);
      // console.log(`   - Future Rewards: ${ethers.formatEther(futureRewards)} ETH`);
      console.log(`   - Total: ${ethers.formatEther(totalBalance)} ETH`);
  
      return totalBalance;
    } catch (error) {
      console.error('Error calculating total available balance:', error);
      return 0n;
    }
  }
  

  /**
   * 预测未来奖励
   * 
   * 信标链API调用:
   * - GET /eth/v1/beacon/states/head/validators - 获取所有gtETH验证者
   * 
   * 计算逻辑:
   * 1. 获取所有活跃的gtETH验证者
   * 2. 基于历史数据预测每个epoch的平均奖励
   * 3. 计算指定epoch数的总预测奖励
   */
  private async predictFutureRewards(blockStamp: BlockStamp, epochsAhead: number): Promise<bigint> {
    try {
      console.log('🔮 Predicting future rewards...');
      console.log('📋 Beacon API call: GET /eth/v1/beacon/states/head/validators (gtETH validators)');
      
      // 获取gtETH验证者数量 (通过api或者通过合约获取)
      const activeValidators = await this.getActiveGTETHValidatorCount();
      
      // 假设每个验证者每个epoch平均获得0.00002 ETH奖励
      const avgRewardPerValidatorPerEpoch = ethers.parseEther('0.00002');
      const totalRewardsPerEpoch = BigInt(activeValidators) * avgRewardPerValidatorPerEpoch;
      const futureRewards = totalRewardsPerEpoch * BigInt(epochsAhead);
      
      console.log(`🔮 Active validators: ${activeValidators}`);
      console.log(`🔮 Predicted rewards per epoch: ${ethers.formatEther(totalRewardsPerEpoch)} ETH`);
      console.log(`🔮 Future rewards (${epochsAhead} epochs): ${ethers.formatEther(futureRewards)} ETH`);
      
      return futureRewards;
    } catch (error) {
      console.error('Error predicting future rewards:', error);
      return 0n;
    }
  }

  /**
   * 获取活跃的gtETH验证者数量
   * 
   * 合约调用:
   * - NodeOperatorsRegistry.getStakingModuleSummary() - 获取质押模块摘要
   * 
   * 计算逻辑: 活跃验证者 = 总存款验证者 - 总退出验证者
   */
  private async getActiveGTETHValidatorCount(): Promise<number> {
    try {
      console.log('📋 Contract call: NodeOperatorsRegistry.getStakingModuleSummary()');
      
      // 获取准确的验证者数据
      const abi = [
        "function getStakingModuleSummary() external view returns (uint256 totalExitedValidators, uint256 totalDepositedValidators, uint256 depositableValidatorsCount)"
      ];
      const nodeOperatorsRegistry = new ethers.Contract(this.nodeOperatorsRegistryAddress, abi, this.provider);
      const summary = await nodeOperatorsRegistry.getStakingModuleSummary();
      const totalDepositedValidators = summary.totalDepositedValidators;
      const totalExitedValidators = summary.totalExitedValidators;
      const activeValidators = totalDepositedValidators - totalExitedValidators;
      
      console.log(`📊 Validator summary (from contract):`);
      console.log(`   - Total deposited: ${totalDepositedValidators}`);
      console.log(`   - Total exited: ${totalExitedValidators}`);
      console.log(`   - Active validators: ${activeValidators}`);
      
      return Number(activeValidators);
    } catch (error) {
      console.error('Error getting active gtETH validator count:', error);
      return 0;
    }
  }

  /**
   * 计算需要退出的验证者数量
   * 
   * 计算逻辑:
   * 1. 假设每个验证者平均可提取32 ETH
   * 2. 根据余额不足计算需要的验证者数量
   */
  private calculateValidatorsNeeded(deficit: bigint): number {
    const avgWithdrawablePerValidator = ethers.parseEther('32'); // 32 ETH
    const validatorsNeeded = Number(deficit / avgWithdrawablePerValidator) + 1;
    
    console.log(`🧮 Calculation: ${ethers.formatEther(deficit)} ETH / 32 ETH = ${validatorsNeeded} validators`);
    
    return validatorsNeeded;
  }

  /**
   * 计算验证者退出顺序
   * 
   * 信标链API调用:
   * - GET /eth/v1/beacon/states/head/validators - 获取所有验证者状态
   * 
   * 退出优先级算法:
   * 1. 低优先级：正常验证者，按激活时间排序
   */
  private async calculateValidatorExitOrder(
    validatorsNeeded: number
  ): Promise<ValidatorExitOrder[]> {
    try {
      console.log('🎯 Calculating validator exit order...');
      
      // 1. 获取所有gtETH验证者
      console.log('📋 Beacon API call: GET /eth/v1/beacon/states/head/validators (filtered by gtETH)');
      const validators = await this.getGTETHValidators();
      
      // 2. 生成候选验证者列表（按验证时长排序，验证越久的越优先退出）
      const exitCandidates: ValidatorExitOrder[] = [];
      
      for (const validator of validators) {
        if (validator.status !== 'active_ongoing') continue;
        
        // 按验证时长计算分数：激活epoch越小（验证越久），分数越高
        const score = this.calculateValidationDurationScore(validator);
        
        // 链下oracle需要维护一张表，是validator.index和stakingModuleId/nodeOperatorId的映射关系
        // 根据映射关系，获取stakingModuleId/nodeOperatorId填入exitCandidates
        exitCandidates.push({
            validatorIndex: validator.index,
            stakingModuleId: 1, // 测试时写死，实际应该从映射表获取
            nodeOperatorId: 0, // 测试时写死，从映射表获取
            score
          });
      }
      
      // 3. 获取每个运营商的最后请求验证者索引（合约约束检查）
      console.log('📋 Contract call: ValidatorsExitBusOracle.getLastRequestedValidatorIndices()');
      const lastRequestedIndexMap = await this.getLastRequestedValidatorIndices(exitCandidates);
      
      // 4. 应用合约约束：过滤出可行的候选者（index > lastRequestedIndex）
      const feasibleCandidates = exitCandidates.filter(candidate => {
        const key = `${candidate.stakingModuleId}-${candidate.nodeOperatorId}`;
        const lastRequestedIndex = lastRequestedIndexMap.get(key) ?? -1n;
        return BigInt(candidate.validatorIndex) > lastRequestedIndex;
      });
      
      console.log(`📋 Filtered ${feasibleCandidates.length} feasible candidates from ${exitCandidates.length} total`);
      
      // 5. 按验证时长排序
      feasibleCandidates.sort((a, b) => {
        // 验证时长越久的越优先（分数越高越优先）
        return b.score - a.score;
      });
      
      // 6. 应用递增约束：确保每个运营商内的验证者索引递增
      const constrainedCandidates = this.applyIncreasingIndexConstraint(
        feasibleCandidates, 
        lastRequestedIndexMap
      );
      
      // 7. 选择需要的数量并按合约要求排序
      const selectedCandidates = constrainedCandidates.slice(0, validatorsNeeded);
      
      // 最终排序：按(stakingModuleId, nodeOperatorId, validatorIndex)升序
      selectedCandidates.sort((a, b) => {
        if (a.stakingModuleId !== b.stakingModuleId) {
          return a.stakingModuleId - b.stakingModuleId;
        }
        if (a.nodeOperatorId !== b.nodeOperatorId) {
          return a.nodeOperatorId - b.nodeOperatorId;
        }
        return a.validatorIndex - b.validatorIndex;
      });
      
      console.log(`🎯 Selected ${selectedCandidates.length} validators for exit`);
      
      return selectedCandidates;
    } catch (error) {
      console.error('Error calculating validator exit order:', error);
      return [];
    }
  }

  /**
   * 获取gtETH验证者列表
   * 
   * 实际实现需要：
   * 1. 调用信标链API获取所有验证者
   * 2. 通过合约调用过滤出属于gtETH的验证者
   */
  protected async getGTETHValidators(): Promise<ValidatorInfo[]> {

    /*
      真实情况需要通过api获取(需要获取所有的Validators，这里只列举一个)
    */
    const pubkey = '0xaf886ed047db534cbc69ef945c8b138a9e0cc1ab5fe2f4a1b0004529f53954e47eb15028361a9dd186e7b95d5fa9a2f8';
    const response = await axios.get(`${this.beaconNodeUrl}/eth/v1/beacon/states/head/validators`, {
      params: {
        id: pubkey
      }
    });
    const validators = response.data.data.map((v: any) => {
      return {
        index: Number(v.index),
        pubkey: v.validator.pubkey,
        balance: BigInt(v.balance),
        effectiveBalance: BigInt(v.validator.effective_balance),
        status: v.status,
        activationEpoch: Number(v.validator.activation_epoch),
        slashed: v.validator.slashed
      };
    });

    console.log(validators);
    return validators;
  }

  /**
   * 计算基于验证时长的退出分数
   * 按验证时长计算分数，验证越久的验证者分数越高，优先退出
   */
  private calculateValidationDurationScore(validator: ValidatorInfo): number {
    // 激活epoch越小（验证越久），分数越高
    // 使用一个大数减去激活epoch，确保最早激活的验证者得分最高
    const maxEpoch = 1000000; // 足够大的数，确保分数为正数
    return maxEpoch - (validator.activationEpoch || 0);
  }

  // ============= ValidatorsExitBusOracle发起退出验证者事件流程 =============

  /**
   * 执行ValidatorsExitBusOracle发起退出验证者事件流程
   * 
   * 流程：
   * 1. 获取当前报告帧信息
   * 2. 构建退出报告数据
   * 3. 提交完整报告数据到ValidatorsExitBusOracle
   * 4. 链下oracle监听ValidatorExitRequest事件，根据退出事件发起退出验证者的动作
   */
  private async executeValidatorsExitBusOracleFlow(
    validatorsToExit: ValidatorExitOrder[],
    blockStamp: BlockStamp
  ): Promise<{ success: boolean; reportData?: ValidatorExitReport }> {
    try {
      console.log('🏛️ === ValidatorsExitBusOracle发起退出验证者事件流程 ===');
      
      // 1. 获取当前报告帧
      const currentFrame = await this.getCurrentFrame();
      console.log(`📋 Current frame: refSlot=${currentFrame.refSlot}, deadline=${currentFrame.reportProcessingDeadlineSlot}`);
      console.log(`📋 Block stamp: slot=${blockStamp.slot}`);
      if (currentFrame.refSlot < blockStamp.slot && currentFrame.reportProcessingDeadlineSlot > blockStamp.slot) {
        console.log('✅ Current frame is right');
      } else {
        console.log('❌ Current frame is not right');
        return { success: false };
      }
      
      // 2. 构建退出报告数据
      const reportData = await this.buildValidatorExitReport(validatorsToExit, currentFrame.refSlot);

      // 3. 提交完整报告数据到ValidatorsExitBusOracle
      console.log('📤 Submitting report data to ValidatorsExitBusOracle...');
      const submitResult = await this.submitReportToExitOracle(reportData);

      // 4. 链下oracle需要监听ValidatorExitRequest事件，根据退出事件发起退出验证者的动作
      
      return {
        success: submitResult.success,
        reportData: reportData
      };
      
    } catch (error) {
      console.error('❌ Error in ValidatorsExitBusOracle flow:', error);
      return { success: false };
    }
  }

  /**
   * 获取ValidatorsExitBusOracle当前帧信息
   * 
   * 合约调用: ValidatorsExitBusOracle.getCurrentFrame()
   */
  private async getCurrentFrame(): Promise<{ refSlot: number; reportProcessingDeadlineSlot: number }> {
    try {
      console.log('📋 Contract call: ValidatorsExitBusOracle.getCurrentFrame()');

      const abi = [
        "function getCurrentFrame() external view returns (uint256, uint256)",
      ];
      const validatorsExitBusOracle = new ethers.Contract(this.validatorsExitBusOracleAddress, abi, this.provider);
      const [refSlot, reportProcessingDeadlineSlot] = await validatorsExitBusOracle.getCurrentFrame();
      
      return {
        refSlot,
        reportProcessingDeadlineSlot
      };
    } catch (error) {
      console.error('Error getting current frame:', error);
      throw error;
    }
  }

  /**
   * 构建验证者退出报告
   * 
   * 包含需要退出的验证者详细信息
   */
  private async buildValidatorExitReport(
    validatorsToExit: ValidatorExitOrder[],
    refSlot: number
  ): Promise<ValidatorExitReport> {
    try {
      console.log('📝 Building validator exit report...');
      // 构建退出请求列表
      const exitRequests = await Promise.all(
        validatorsToExit.map(async (validator) => {
          const pubkey = await this.getValidatorPubkey(validator.validatorIndex); // hex string with 0x
          
          return {
            stakingModuleId: validator.stakingModuleId,
            nodeOperatorId: validator.nodeOperatorId,
            validatorIndex: validator.validatorIndex,
            validatorPubkey: pubkey // hex string, 48 bytes
          };
        })
      );
  
      // 确保请求按照合约要求的顺序排序：(moduleId, nodeOpId, validatorIndex) 升序
      exitRequests.sort((a, b) => {
        if (a.stakingModuleId !== b.stakingModuleId) {
          return a.stakingModuleId - b.stakingModuleId;
        }
        if (a.nodeOperatorId !== b.nodeOperatorId) {
          return a.nodeOperatorId - b.nodeOperatorId;
        }
        return a.validatorIndex - b.validatorIndex;
      });
  
      const dataFormat = 1;
  
      // 正确地将每个退出请求编码成 64 bytes，符合合约要求的二进制格式
      const encodeExitRequests = (requests: typeof exitRequests): string => {
        // 验证请求是否按照 (moduleId, nodeOpId, validatorIndex) 升序排序
        for (let i = 1; i < requests.length; i++) {
          const prev = requests[i - 1];
          const curr = requests[i];
          
          if (prev.stakingModuleId > curr.stakingModuleId ||
              (prev.stakingModuleId === curr.stakingModuleId && prev.nodeOperatorId > curr.nodeOperatorId) ||
              (prev.stakingModuleId === curr.stakingModuleId && prev.nodeOperatorId === curr.nodeOperatorId && prev.validatorIndex >= curr.validatorIndex)) {
            throw new Error(`Exit requests must be sorted by (moduleId, nodeOpId, validatorIndex). Found unsorted: ${JSON.stringify(prev)} >= ${JSON.stringify(curr)}`);
          }
        }
        
        const encoded = requests.map(req => {
          // 验证字段范围
          if (req.stakingModuleId === 0) {
            throw new Error('stakingModuleId cannot be 0');
          }
          if (req.stakingModuleId > 0xFFFFFF) { // 3 bytes max
            throw new Error(`stakingModuleId ${req.stakingModuleId} exceeds 3 bytes limit`);
          }
          if (req.nodeOperatorId > 0xFFFFFFFFFF) { // 5 bytes max  
            throw new Error(`nodeOperatorId ${req.nodeOperatorId} exceeds 5 bytes limit`);
          }
          if (req.validatorIndex > 0xFFFFFFFFFFFFFFFF) { // 8 bytes max
            throw new Error(`validatorIndex ${req.validatorIndex} exceeds 8 bytes limit`);
          }
          
          // 清理公钥格式
          const pubkeyHex = req.validatorPubkey.replace(/^0x/, '');
          if (pubkeyHex.length !== 96) { // 48 bytes = 96 hex chars
            throw new Error(`Invalid pubkey length: ${pubkeyHex.length}, expected 96 hex chars`);
          }
          
          // 按照合约期望的格式编码：
          // MSB <------------------------------------------------------- LSB  
          // |  3 bytes   |  5 bytes   |     8 bytes      |    48 bytes     |
          // |  moduleId  |  nodeOpId  |  validatorIndex  | validatorPubkey |
          
          const moduleIdHex = req.stakingModuleId.toString(16).padStart(6, '0');       // 3 bytes = 6 hex
          const nodeOpIdHex = req.nodeOperatorId.toString(16).padStart(10, '0');       // 5 bytes = 10 hex  
          const validatorIndexHex = req.validatorIndex.toString(16).padStart(16, '0'); // 8 bytes = 16 hex
          
          // 组合成64字节：前16字节是moduleId+nodeOpId+validatorIndex，后48字节是pubkey
          return moduleIdHex + nodeOpIdHex + validatorIndexHex + pubkeyHex;
        });
  
        /* 输出结果示例
          encoded = [
            "000001000000012c0000000000001388aabbcc...ff", // 第1个验证者
            "00000200000004560000000000002345ddeeff...11", // 第2个验证者
            ...
          ]
        */
        return '0x' + encoded.join('');
      };
  
      const reportData: ValidatorExitReport = {
        refSlot,
        requestsCount: exitRequests.length,
        dataFormat,
        data: encodeExitRequests(exitRequests)
      };
  
      console.log(`✅ Report built: ${exitRequests.length} exit requests for refSlot ${refSlot}`);
      console.log("📋 reportData:", reportData);
      
      return reportData;
    } catch (error) {
      console.error('❌ Error building validator exit report:', error);
      throw error;
    }
  }

  /**
   * 获取验证者公钥
   * 
   * 信标链API调用: GET /eth/v1/beacon/states/head/validators/{validator_index}
   */
  private async getValidatorPubkey(validatorIndex: number): Promise<string> {
    try {
      console.log(`📋 Beacon API call: GET /eth/v1/beacon/states/head/validators/${validatorIndex}`);
      
      const response = await fetch(`${this.beaconNodeUrl}/eth/v1/beacon/states/head/validators/${validatorIndex}`);
      const data = await response.json() as {
        data: {
          validator: {
            pubkey: string;
          };
        };
      };
      
      console.log("📋 pubkey is :", data.data.validator.pubkey);
      return data.data.validator.pubkey;
    } catch (error) {
      console.error(`Error getting validator pubkey for index ${validatorIndex}:`, error);
      return '0x' + validatorIndex.toString(16).padStart(96, '0'); // 返回模拟公钥
    }
  }

  /**
   * 获取每个运营商的最后请求验证者索引
   */
  private async getLastRequestedValidatorIndices(
    exitCandidates: ValidatorExitOrder[]
  ): Promise<Map<string, bigint>> {
    try {
      const resultMap = new Map<string, bigint>();
      
      // 按(moduleId, nodeOperatorId)分组
      const operatorGroups = new Map<string, number[]>();
      for (const candidate of exitCandidates) {
        const key = `${candidate.stakingModuleId}-${candidate.nodeOperatorId}`;
        if (!operatorGroups.has(key)) {
          operatorGroups.set(key, []);
        }
        operatorGroups.get(key)!.push(candidate.nodeOperatorId);
      }
      
      // 对每个模块分别查询
      for (const [key, nodeOpIds] of operatorGroups) {
        const moduleId = parseInt(key.split('-')[0]);
        const uniqueNodeOpIds = Array.from(new Set(nodeOpIds));
        
        const abi = [
          "function getLastRequestedValidatorIndices(uint256 moduleId, uint256[] nodeOpIds) external view returns (int256[])"
        ];
        const oracle = new ethers.Contract(this.validatorsExitBusOracleAddress, abi, this.provider);
        
        try {
          const lastIndices: bigint[] = await oracle.getLastRequestedValidatorIndices(moduleId, uniqueNodeOpIds);
          
          uniqueNodeOpIds.forEach((nodeOpId, index) => {
            const operatorKey = `${moduleId}-${nodeOpId}`;
            resultMap.set(operatorKey, lastIndices[index]);
          });
          
          console.log(`📋 Module ${moduleId} last requested indices:`, 
            uniqueNodeOpIds.map((id, i) => `op${id}:${lastIndices[i]}`).join(', '));
          
        } catch (error) {
          console.warn(`⚠️ Failed to get last indices for module ${moduleId}:`, error);
          // 失败时设置为-1，表示没有历史记录
          uniqueNodeOpIds.forEach(nodeOpId => {
            const operatorKey = `${moduleId}-${nodeOpId}`;
            resultMap.set(operatorKey, -1n);
          });
        }
      }
      
      return resultMap;
    } catch (error) {
      console.error('Error getting last requested validator indices:', error);
      return new Map<string, bigint>();
    }
  }

  /**
   * 应用递增索引约束：确保每个运营商内的验证者索引严格递增
   */
  private applyIncreasingIndexConstraint(
    candidates: ValidatorExitOrder[],
    lastRequestedIndexMap: Map<string, bigint>
  ): ValidatorExitOrder[] {
    const result: ValidatorExitOrder[] = [];
    const operatorCurrentIndex = new Map<string, bigint>();
    
    // 初始化每个运营商的当前索引为最后请求的索引
    for (const [key, lastIndex] of lastRequestedIndexMap) {
      operatorCurrentIndex.set(key, lastIndex);
    }
    
    // 遍历候选者，贪心选择满足递增约束的验证者
    for (const candidate of candidates) {
      const key = `${candidate.stakingModuleId}-${candidate.nodeOperatorId}`;
      const currentIndex = operatorCurrentIndex.get(key) ?? -1n;
      
      if (BigInt(candidate.validatorIndex) > currentIndex) {
        result.push(candidate);
        operatorCurrentIndex.set(key, BigInt(candidate.validatorIndex));
        
        console.log(`✅ Selected validator ${candidate.validatorIndex} for operator ${key} (prev: ${currentIndex})`);
      } else {
        console.log(`❌ Skipped validator ${candidate.validatorIndex} for operator ${key} (prev: ${currentIndex}, constraint violation)`);
      }
    }
    
    console.log(`📋 Applied increasing constraint: ${result.length}/${candidates.length} candidates selected`);
    return result;
  }

  /**
   * 提交报告数据到ValidatorsExitBusOracle
   * 
   */
  private async submitReportToExitOracle(reportData: ValidatorExitReport): Promise<{ success: boolean }> {
    try {
      console.log(`📋 Contract call: ValidatorsExitBusOracle.submitReportData()`);
      
      // 选择当前oracle进行报告
      const submittingOracle = this.oracles[0];
      console.log(`🤖 ${submittingOracle.name} submitting report data...`);

      const abi = [
        "function submitReportData((uint256 refSlot, uint256 requestsCount, uint256 dataFormat, bytes data)) external"
      ];
      const wallet = new ethers.Wallet(submittingOracle.privateKey, this.provider);
      const validatorsExitBusOracle = new ethers.Contract(this.validatorsExitBusOracleAddress, abi, wallet);
      
      const tx = await validatorsExitBusOracle.submitReportData(
        reportData
      );
      const receipt = await tx.wait();
      // const receipt = { status: 1 };
      if (receipt.status === 1) {
        console.log('✅ Report data submitted successfully!');
      } else {
        console.error('❌ Failed to submit report data');
        return { success: false };
      }
  
      return { success: true };
    } catch (error) {
      console.error('Error submitting report to exit oracle:', error);
      return { success: false };
    }
  }
}

async function main() {
  console.log('🚀 Starting gtETH Validator Exit Judgment with ValidatorsExitBusOracle...');
  console.log('----------------------------------------------------------------------------');
  
  // 配置
  const beaconNodeUrl = 'https://ethereum-hoodi-beacon-api.publicnode.com';
  const executionRpcUrl = 'https://ethereum-hoodi-rpc.publicnode.com';
  const validatorsExitBusOracleAddress = '0x3245b7FC3633dFbd2EF05301da85C8447A6E8094';
  const gtETHAddress = '0xf89b4a70e1777D0ea5764FA7cE185410861Edfe8';
  const withdrawalQueueERC721Address = '0xC8822436A02E02F3Ee357331a71239DF5cd70186';
  const withdrawalVaultAddress = '0x20404236c205d8860De840779b71De2b58C755CD';
  const executionLayerRewardsVaultAddress = '0xa1eC55B761152CF9E6DFE952b6c815b502e0706b';
  const nodeOperatorsRegistryAddress = '0xBe954d4D0dd4DCDF31842BfA4677C637b7b44f76';

  console.log('📋 Configuration:');
  console.log(`   Beacon Node: ${beaconNodeUrl}`);
  console.log(`   Execution RPC: ${executionRpcUrl}`);
  console.log(`   ValidatorsExitBusOracle: ${validatorsExitBusOracleAddress}`);
  console.log(`   GTETH: ${gtETHAddress}`);
  console.log(`   WithdrawalQueueERC721: ${withdrawalQueueERC721Address}`);
  console.log(`   WithdrawalVault: ${withdrawalVaultAddress}`);
  console.log(`   ExecutionLayerRewardsVault: ${executionLayerRewardsVaultAddress}`);
  console.log(`   NodeOperatorsRegistry: ${nodeOperatorsRegistryAddress}\n`);
  
  // 创建判断器
  const judgment = new ValidatorExitJudgment(
    beaconNodeUrl,
    executionRpcUrl,
    validatorsExitBusOracleAddress,
    gtETHAddress,
    withdrawalQueueERC721Address,
    withdrawalVaultAddress,
    executionLayerRewardsVaultAddress,
    nodeOperatorsRegistryAddress
  );
  
  try {
    console.log('⏳ Starting validator exit judgment with ValidatorsExitBusOracle (demo mode)...');
    console.log('----------------------------------------------------------------------------');
    
    // 添加超时保护
    const timeoutPromise = new Promise((_, reject) => {
      setTimeout(() => reject(new Error('Execution timeout after 30 seconds')), 3000000);
    });
    
    // 执行退出判断（包含ValidatorsExitBusOracle发起退出验证者事件流程）
    const result = await Promise.race([
      judgment.judgeValidatorExit(),
      timeoutPromise
    ]) as any;
    
    console.log('\n🎯 === JUDGMENT RESULT ===');
    console.log(`Should exit validators: ${result.shouldExit}`);
    console.log(`Reasoning: ${result.reasoning}`);
    console.log(`Deficit: ${ethers.formatEther(result.deficit)} ETH`);
    console.log(`Available balance: ${ethers.formatEther(result.availableBalance)} ETH`);
    console.log(`Unfinalized withdrawals: ${ethers.formatEther(result.unfinalizedWithdrawals)} ETH`);
    console.log(`Validators to exit: ${result.validatorsToExit.length}`);
    
    if (result.validatorsToExit.length > 0) {
      console.log('\n📋 Validators to exit:');
      result.validatorsToExit.forEach((validator: any, index: number) => {
        console.log(`  ${index + 1}. Validator ${validator.validatorIndex}`);
      });
    }
  
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
  
  console.log('\n✅ Demo completed successfully!');
  process.exit(0);
}

// 如果直接运行此脚本
if (require.main === module) {
  main().catch((error) => {
    console.error('❌ Fatal error:', error);
    process.exit(1);
  });
}