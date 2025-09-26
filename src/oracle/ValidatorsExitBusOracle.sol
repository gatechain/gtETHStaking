// SPDX-License-Identifier: MIT    
pragma solidity 0.8.30;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { BaseOracle } from "./BaseOracle.sol"; 
import { Error } from "../lib/Error.sol";

/**
 * @title ValidatorsExitBusOracle
 * @notice gtETH项目的验证者退出总线Oracle合约
 * @dev 处理验证者退出请求，管理退出流程，提供暂停/恢复功能
 * 
 * 主要功能：
 * 1. 接收和处理验证者退出请求数据
 * 2. 验证退出请求的有效性和排序
 * 3. 存储和跟踪退出请求状态
 * 4. 提供暂停/恢复保护机制
 * 5. 权限控制和安全检查
 */
// 声明合约继承BaseOracle和Pausable，获取Oracle基础功能和暂停功能
contract ValidatorsExitBusOracle is BaseOracle {
    using SafeCast for uint256;

    // ================================ 事件定义 ================================

    event ValidatorExitRequest(
        uint256 indexed stakingModuleId,
        uint256 indexed nodeOperatorId,
        uint256 indexed validatorIndex,
        bytes validatorPubkey,
        uint256 timestamp);

    event WarnDataIncompleteProcessing(
        uint256 indexed refSlot,      
        uint256 requestsProcessed,    
        uint256 requestsCount         
    );

    // ================================ 结构体定义 ================================
    
    /**
     * @notice 数据处理状态结构体
     * @param refSlot 参考插槽
     * @param requestsCount 请求总数
     * @param requestsProcessed 已处理请求数
     * @param dataFormat 数据格式
     */
    // 定义数据处理状态的结构体
    struct DataProcessingState {
        uint64 refSlot;             
        uint64 requestsCount;       
        uint64 requestsProcessed;   
        uint16 dataFormat;          
    }

    /**
     * @notice 请求的验证者结构体
     * @param requested 是否已请求
     * @param index 验证者索引
     */
    // 定义请求的验证者信息的结构体
    struct RequestedValidator {
        bool requested;    
        uint64 index;      
    }

    /**
     * @notice 报告数据结构体
     */
    // 定义Oracle报告数据的结构体
    struct ReportData {
        /**
         * @dev Oracle共识信息
         */    

        /// @dev 计算报告的参考插槽。如果插槽包含区块，被报告的状态应包含该区块产生的所有状态变化。
        uint256 refSlot;              

        /**
         * @dev 请求数据
         */
        
        /// @dev 此报告中验证者退出请求的总数。
        uint256 requestsCount;        

        /// @dev 验证者退出请求数据的格式。目前只支持DATA_FORMAT_LIST=1。
        uint256 dataFormat;           

        /// @dev 验证者退出请求数据。可根据数据格式不同而不同，详见下面定义特定数据格式的常量。
        bytes data;                   
    }

    /**
     * @notice 处理状态结构体
     */
    // 定义处理状态的结构体，用于跟踪当前报告帧的处理进度
    struct ProcessingState {
        /// @notice 当前报告帧的参考插槽
        uint256 currentFrameRefSlot;      

        /// @notice 当前报告帧可提交报告数据的最后时间
        uint256 processingDeadlineTime;   

        /// @notice 报告数据的哈希值。如果当前报告帧尚未达成共识则为零字节
        bytes32 dataHash;                 

        /// @notice 当前报告帧是否已提交报告数据
        bool dataSubmitted;               

        /// @notice 当前报告帧的报告数据格式
        uint256 dataFormat;               

        /// @notice 当前报告帧的验证者退出请求总数
        uint256 requestsCount;            

        /// @notice 当前报告帧已提交的验证者退出请求数
        uint256 requestsSubmitted;        
    }

    // ================================ 常量定义 ================================
    
    /**
     * @notice 验证者退出请求数据的列表格式。当所有请求都能放入单个交易时使用。
     * 
     * 每个验证者退出请求由以下64字节数组描述：
     * 
     * MSB <------------------------------------------------------- LSB
     * |  3 bytes   |  5 bytes   |     8 bytes      |    48 bytes     |
     * |  moduleId  |  nodeOpId  |  validatorIndex  | validatorPubkey |
     * 
     * 所有请求紧密打包到字节数组中，请求依次排列，无分隔符或填充，
     * 并传递到报告结构的`data`字段。
     * 
     * 请求必须按以下复合键的升序排序：(moduleId, nodeOpId, validatorIndex)。
     */
    // 定义数据格式常量，值为1，表示列表格式
    uint256 public constant DATA_FORMAT_LIST = 1;

    /// 打包请求的字节长度
    // 定义每个打包请求的固定字节长度为64字节
    uint256 internal constant PACKED_REQUEST_LENGTH = 64;

    // ================================ 存储变量 ================================
    
    /**
     * @notice 已处理的请求总数
     */
    // 私有状态变量，记录合约生命周期内处理的所有请求总数
    uint256 private _totalRequestsProcessed;

    /** 
     * @notice 最大请求数量
    */
    uint256 private _maxRequestsCount;
    
    /**
     * @notice 最后请求的验证者索引映射
     * @dev 从(moduleId, nodeOpId)打包键到最后请求的验证者索引的映射
     */
    // 私有映射，存储每个节点操作员最后请求退出的验证者信息
    mapping(uint256 => RequestedValidator) private _lastRequestedValidatorIndices;
    
    /**
     * @notice 数据处理状态
     */
    // 私有状态变量，存储当前的数据处理状态
    DataProcessingState private _dataProcessingState;

    // ================================ 构造函数 ================================
    
    /**
     * @notice 初始化函数
     * @param slotsPerEpoch 每个纪元的时隙数
     * @param secondsPerSlot 每个插槽的秒数
     * @param genesisTime 创世时间
     * @param oracleMember Oracle成员地址
     * @param lastProcessingRefSlot 最后处理的参考插槽
     * @param epochsPerFrame 每帧的纪元数
     */
    function initialize(
        uint256 slotsPerEpoch, 
        uint256 secondsPerSlot, 
        uint256 genesisTime,
        address oracleMember,
        uint256 lastProcessingRefSlot,
        uint256 epochsPerFrame
    ) public initializer {
        __BaseOracle_init(slotsPerEpoch, secondsPerSlot, genesisTime, oracleMember, lastProcessingRefSlot, epochsPerFrame);
        
        // 授予传入地址默认管理员角色
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // 默认设置最大请求数量为50
        _maxRequestsCount = 50;
        
        // 初始化时暂停合约，确保在配置完成前不接受请求
        _pause();
    }

    // ================================ 数据提供接口 ================================
    
    /**
     * @notice 提交报告数据进行处理
     * @param data 报告数据。详见`ReportData`结构体
     * 
     * 回滚条件：
     * - 调用者不是oracle委员会成员且不具有SUBMIT_DATA_ROLE角色
     */
    // 外部函数，接受并处理Oracle报告数据，只在合约未暂停时可调用
    function submitReportData(ReportData calldata data) external whenNotPaused {
        // 检查权限后提交报告数据
        _submitReport(data.refSlot, keccak256(abi.encode(data)));
        // 开始处理流程，将refslot设置为processingRefSlot
        _startProcessing();
        // 处理共识报告数据
        _handleConsensusReportData(data);
    }

    /**
     * @notice 返回所有接收报告中处理过的验证者退出请求总数
     * @return 已处理的请求总数
     */
    // 外部视图函数，返回合约生命周期内处理的总请求数
    function getTotalRequestsProcessed() external view returns (uint256) {
        // 返回私有变量_totalRequestsProcessed的值
        return _totalRequestsProcessed;
    }

    /**
     * @notice 返回给定`moduleId`中给定`nodeOpIds`被请求退出的最新验证者索引
     * @param moduleId 质押模块ID
     * @param nodeOpIds 质押模块的节点操作员ID数组
     * @return 验证者索引数组。对于从未被请求退出任何验证者的节点操作员，索引设为-1
     */
    // 外部视图函数，查询指定节点操作员的最后请求验证者索引
    function getLastRequestedValidatorIndices(uint256 moduleId, uint256[] calldata nodeOpIds)
        external view returns (int256[] memory)
    {
        // 检查模块ID是否在有效范围内（不超过24位）
        if (moduleId > type(uint24).max) revert Error.ArgumentOutOfBounds();

        // 创建与输入数组相同长度的结果数组
        int256[] memory indices = new int256[](nodeOpIds.length);

        // 遍历所有节点操作员ID
        for (uint256 i = 0; i < nodeOpIds.length; ++i) {
            // 获取当前节点操作员ID
            uint256 nodeOpId = nodeOpIds[i];
            // 检查节点操作员ID是否在有效范围内（不超过40位）
            if (nodeOpId > type(uint40).max) revert Error.ArgumentOutOfBounds();
            // 计算节点操作员的唯一键
            uint256 nodeOpKey = _computeNodeOpKey(moduleId, nodeOpId);
            // 从映射中获取请求的验证者信息
            RequestedValidator memory validator = _lastRequestedValidatorIndices[nodeOpKey];
            // 如果已请求过，返回验证者索引；否则返回-1
            indices[i] = validator.requested ? int256(uint256(validator.index)) : -1;
        }

        // 返回结果数组
        return indices;
    }

    /**
     * @notice 返回当前报告帧的数据处理状态
     * @return result 返回ProcessingState结构体
     */
    // 外部视图函数，返回当前的处理状态信息
    function getProcessingState() external view returns (ProcessingState memory result) {
        // 获取当前共识报告信息，包括哈希、参考插槽、截止时间和处理状态
        (bytes32 hash, uint256 refSlot, uint256 processingDeadlineTime,) = this.getConsensusReport();
        // 获取当前帧的参考插槽
        result.currentFrameRefSlot = _getCurrentRefSlot();

        // 如果没有共识哈希或参考插槽不匹配，返回空的处理状态
        if (hash == bytes32(0) || result.currentFrameRefSlot != refSlot) {
            return result;
        }

        // 设置处理截止时间和数据哈希
        result.processingDeadlineTime = processingDeadlineTime;
        result.dataHash = hash;

        // 获取当前的数据处理状态
        DataProcessingState memory procState = _dataProcessingState;

        // 检查是否已提交数据（通过比较参考插槽）
        result.dataSubmitted = procState.refSlot == result.currentFrameRefSlot;
        // 如果未提交数据，直接返回
        if (!result.dataSubmitted) {
            return result;
        }

        // 设置已提交的数据相关信息
        result.dataFormat = procState.dataFormat;          // 数据格式
        result.requestsCount = procState.requestsCount;     // 总请求数
        result.requestsSubmitted = procState.requestsProcessed; // 已处理请求数
    }

    /**
     * @notice 设置最大请求数量
     * @param maxRequestsCount 最大请求数量
     */
    // 外部函数，设置合约允许的最大请求数量
    function setMaxRequestsCount(uint256 maxRequestsCount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _maxRequestsCount = maxRequestsCount;
    }

    /**
     * @notice 返回最大请求数量
     * @return 最大请求数量
     */
    // 外部视图函数，返回合约允许的最大请求数量
    function getMaxRequestsCount() external view returns (uint256) {
        return _maxRequestsCount;
    }

    // ================================ 内部实现函数 ================================
    
    /**
     * @notice 处理共识报告
     * @param prevProcessingRefSlot 之前处理的参考插槽
     */
    // 内部函数重写，处理共识报告，检查数据处理的完整性
    function _handleConsensusReport(
        ConsensusReport memory /* report */,     // 共识报告数据（未使用）
        uint256 /* prevSubmittedRefSlot */,     // 之前提交的参考插槽（未使用）
        uint256 prevProcessingRefSlot           // 之前处理的参考插槽
    ) internal override {
        // 获取当前的数据处理状态
        DataProcessingState memory state = _dataProcessingState;
        // 如果之前的处理不完整（参考插槽匹配但处理数小于总数），发出警告事件
        if (state.refSlot == prevProcessingRefSlot && state.requestsProcessed < state.requestsCount) {
            emit WarnDataIncompleteProcessing(
                prevProcessingRefSlot,      // 参考插槽
                state.requestsProcessed,    // 已处理请求数
                state.requestsCount         // 总请求数
            );
        }
    }

    /**
     * @notice 处理共识报告数据
     * @param data 报告数据
     */
    // 内部函数，处理接收到的共识报告数据
    function _handleConsensusReportData(ReportData calldata data) internal {
        // 检查数据格式是否为支持的列表格式
        if (data.dataFormat != DATA_FORMAT_LIST) {
            revert Error.UnsupportedRequestsDataFormat(data.dataFormat);
        }

        // 检查数据长度是否为打包请求长度的整数倍
        if (data.data.length % PACKED_REQUEST_LENGTH != 0) {
            revert Error.InvalidRequestsDataLength();
        }

        // 验证数据长度与请求数量的一致性
        if (data.data.length / PACKED_REQUEST_LENGTH != data.requestsCount) {
            revert Error.UnexpectedRequestsDataLength();
        }

        // 验证退出的验证者数量是否大于最大请求数量
        if (data.requestsCount > _maxRequestsCount) {
            revert Error.InvalidRequestsData();
        }

        // 处理退出请求列表
        _processExitRequestsList(data.data);

        // 更新数据处理状态，记录本次处理的信息
        _dataProcessingState = DataProcessingState({
            refSlot: data.refSlot.toUint64(),           // 使用SafeCast安全转换为64位
            requestsCount: data.requestsCount.toUint64(), // 请求总数
            requestsProcessed: data.requestsCount.toUint64(), // 已处理请求数（全部处理完）
            dataFormat: uint16(DATA_FORMAT_LIST)        // 数据格式
        });

        // 如果没有请求需要处理，直接返回
        if (data.requestsCount == 0) {
            return;
        }

        // 累加到总处理请求数
        _totalRequestsProcessed += data.requestsCount;
    }

    /**
     * @notice 处理退出请求列表
     * @param data 请求数据
     */
    // 内部函数，解析和处理打包的退出请求数据
    function _processExitRequestsList(bytes calldata data) internal {
        // 定义偏移量变量，用于遍历字节数组
        uint256 offset;
        uint256 offsetPastEnd;
        // 使用内联汇编高效获取数据的起始位置和结束位置
        assembly {
            offset := data.offset              // 数据起始偏移
            offsetPastEnd := add(offset, data.length) // 数据结束位置
        }

        // 用于验证数据排序的变量
        uint256 lastDataWithoutPubkey = 0;    // 上一个请求的数据（不包含公钥）
        uint256 lastNodeOpKey = 0;            // 上一个节点操作员键
        RequestedValidator memory lastRequestedVal; // 上一个请求的验证者信息
        bytes calldata pubkey;                 // 公钥数据

        // 设置公钥长度为48字节（以太坊验证者公钥的标准长度）
        assembly {
            pubkey.length := 48
        }

        // 获取当前时间戳，用于事件记录
        uint256 timestamp = _getTime();

        // 遍历所有打包的请求数据
        while (offset < offsetPastEnd) {
            uint256 dataWithoutPubkey; // 当前请求的数据（不包含公钥）
            // 使用内联汇编高效解析请求数据
            assembly {
                // 16个最高位字节由模块ID、节点操作员ID和验证者索引组成
                dataWithoutPubkey := shr(128, calldataload(offset))
                // 接下来48字节是公钥
                pubkey.offset := add(offset, 16)
                // 总共64字节，移动到下一个请求
                offset := add(offset, 64)
            }
            //                              dataWithoutPubkey
            // MSB <---------------------------------------------------------------------- LSB
            // | 128 bits: zeros | 24 bits: moduleId | 40 bits: nodeOpId | 64 bits: valIndex |
            //
            // 检查请求是否按升序排列（确保数据完整性和一致性）
            if (dataWithoutPubkey <= lastDataWithoutPubkey) {
                revert Error.InvalidRequestsDataSortOrder();
            }

            // 从打包数据中提取各个字段
            uint64 valIndex = uint64(dataWithoutPubkey);           // 验证者索引（低64位）
            uint256 nodeOpId = uint40(dataWithoutPubkey >> 64);    // 节点操作员ID（中间40位）
            uint256 moduleId = uint24(dataWithoutPubkey >> (64 + 40)); // 模块ID（高24位）

            // 验证模块ID不能为0（0是无效值）
            if (moduleId == 0) {
                revert Error.InvalidRequestsData();
            }

            // 计算节点操作员的唯一键（这里的使用nodeOpkey的原因是因为如果每次都要加载数据到_lastRequestedValidatorIndices中，gas会非常昂贵，所以这里只有当nodeOpkey变化了再去加载最终的last值）
            uint256 nodeOpKey = _computeNodeOpKey(moduleId, nodeOpId);
            // 如果是新的节点操作员，更新状态
            if (nodeOpKey != lastNodeOpKey) {
                // 保存上一个节点操作员的最后请求状态
                if (lastNodeOpKey != 0) {
                    _lastRequestedValidatorIndices[lastNodeOpKey] = lastRequestedVal;
                }
                // 加载新节点操作员的当前状态
                lastRequestedVal = _lastRequestedValidatorIndices[nodeOpKey];
                lastNodeOpKey = nodeOpKey;
            }

            // 检查验证者索引的递增性（同一节点操作员的验证者索引必须递增）
            if (lastRequestedVal.requested && valIndex <= lastRequestedVal.index) {
                revert Error.NodeOpValidatorIndexMustIncrease(
                    moduleId,                   // 模块ID
                    nodeOpId,                  // 节点操作员ID
                    lastRequestedVal.index,    // 之前的验证者索引
                    valIndex                   // 当前验证者索引
                );
            }

            // 更新最后请求的验证者信息
            lastRequestedVal = RequestedValidator(true, valIndex);
            // 更新用于排序检查的变量
            lastDataWithoutPubkey = dataWithoutPubkey;

            // 发出验证者退出请求事件
            emit ValidatorExitRequest(moduleId, nodeOpId, valIndex, pubkey, timestamp);
        }

        // 保存最后一个节点操作员的状态
        if (lastNodeOpKey != 0) {
            _lastRequestedValidatorIndices[lastNodeOpKey] = lastRequestedVal;
        }
    }

    /**
     * @notice 计算节点操作员密钥
     * @param moduleId 模块ID
     * @param nodeOpId 节点操作员ID
     * @return 节点操作员密钥
     */
    // 内部纯函数，计算节点操作员的唯一键，用于映射存储
    function _computeNodeOpKey(uint256 moduleId, uint256 nodeOpId) internal pure returns (uint256) {
        // 将模块ID左移40位后与节点操作员ID进行或运算，生成唯一键
        // 格式：| 216 bits: zeros | 24 bits: moduleId | 40 bits: nodeOpId |
        return (moduleId << 40) | nodeOpId;
    }
}
