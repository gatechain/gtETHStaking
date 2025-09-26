// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IGTETHLocator} from "../interfaces/IGTETHLocator.sol";
import {IGTETH} from "../interfaces/IGTETH.sol";
import {IStakingRouter} from "../interfaces/IStakingRouter.sol";

import {BaseOracle} from "./BaseOracle.sol";
import { Error } from "../lib/Error.sol";


/**
 * @title AccountingOracle
 * @notice gtETH项目的会计Oracle合约
 * @dev 处理质押协议的状态报告，管理共识层和执行层的余额更新
 *
 * 主要功能：
 * 1. 接收和处理质押协议状态报告数据
 * 2. 验证报告数据的有效性和一致性
 * 3. 更新质押路由器和GTETH合约状态
 * 4. 处理额外的验证者退出和卡住验证者数据
 * 5. 提供暂停/恢复保护机制
 * 6. 权限控制和安全检查
 */

contract AccountingOracle is BaseOracle {
    using SafeCast for uint256;

    // ================================ 事件定义 ================================

    event ExtraDataSubmitted(
        uint256 indexed refSlot,
        uint256 itemsProcessed,
        uint256 itemsCount
    );

    event WarnExtraDataIncompleteProcessing(
        uint256 indexed refSlot,
        uint256 processedItemsCount,
        uint256 itemsCount
    );

    // ================================ 结构体定义 ================================

    /**
     * @notice 额外数据处理状态结构体
     * @param refSlot 参考插槽
     * @param dataFormat 数据格式
     * @param submitted 是否已提交
     * @param itemsCount 项目总数
     * @param itemsProcessed 已处理项目数
     * @param lastSortingKey 最后排序键
     * @param dataHash 数据哈希
     */
    struct ExtraDataProcessingState {
        uint64 refSlot;
        uint16 dataFormat;
        bool submitted;
        uint64 itemsCount;
        uint64 itemsProcessed;
        uint256 lastSortingKey;
        bytes32 dataHash;
    }

    /**
     * @notice 报告数据结构体
     */
    struct ReportData {
        /// @dev 计算报告的参考插槽。如果插槽包含区块，被报告的状态应包含该区块产生的所有状态变化。
        uint256 refSlot;
        /// @dev 在参考插槽处通过Lido质押的验证者总数。
        uint256 numValidators;
        /// @dev 在参考插槽处所有Lido验证者在共识层的累计余额。
        uint256 clBalanceGwei;
        /// @dev 在参考插槽处，退出验证者数量超过各自质押模块合约中存储数量的质押模块ID。
        uint256[] stakingModuleIdsWithNewlyExitedValidators;
        /// @dev 在参考插槽处，来自stakingModuleIdsWithNewlyExitedValidators数组的每个质押模块的累计退出验证者数量。
        uint256[] numExitedValidatorsByStakingModule;
        /**
         * @dev 执行层值
         */

        /// @dev 在参考插槽处Lido提款金库的ETH余额。
        uint256 withdrawalVaultBalance;
        /// @dev 在参考插槽处Lido执行层奖励金库的ETH余额。
        uint256 elRewardsVaultBalance;
        /**
         * @dev 决策
         */

        /// @dev 通过调用WithdrawalQueue.calculateFinalizationBatches获得的升序排列的提款请求ID数组。
        uint256[] withdrawalFinalizationBatches;
        /**
         * @dev 额外数据 — 允许在主要数据处理后异步分块处理的Oracle信息。
         * 详见下面的详细说明。
         */

        /// @dev 额外数据的格式。目前只支持EXTRA_DATA_FORMAT_EMPTY=0和EXTRA_DATA_FORMAT_LIST=1格式。
        uint256 extraDataFormat;
        /// @dev 额外数据的哈希值。如果Oracle报告不包含额外数据，则必须设置为零哈希。
        bytes32 extraDataHash;
        /// @dev 额外数据项目的数量。如果Oracle报告不包含额外数据，则必须设置为零。
        uint256 extraDataItemsCount;
    }

    /**
     * @notice 处理状态结构体
     */
    struct ProcessingState {
        /// @notice 当前报告帧的参考插槽
        uint256 currentFrameRefSlot;
        /// @notice 当前报告帧可提交数据的最后时间
        uint256 processingDeadlineTime;
        /// @notice 主要报告数据的哈希值。如果当前报告帧尚未达成共识则为零字节
        bytes32 mainDataHash;
        /// @notice 当前报告帧的主要报告数据是否已提交
        bool mainDataSubmitted;
        /// @notice 当前报告帧的额外报告数据哈希值
        bytes32 extraDataHash;
        /// @notice 当前报告帧的额外报告数据格式
        uint256 extraDataFormat;
        /// @notice 当前报告帧的额外报告数据是否已提交
        bool extraDataSubmitted;
        /// @notice 当前报告帧的额外报告数据项目总数
        uint256 extraDataItemsCount;
        /// @notice 当前报告帧已提交的额外报告数据项目数
        uint256 extraDataItemsSubmitted;
    }

    // ================================ 常量定义 ================================

    /// @notice 额外数据类型：卡住的验证者
    uint256 public constant EXTRA_DATA_TYPE_STUCK_VALIDATORS = 1;

    /// @notice 额外数据类型：退出的验证者
    uint256 public constant EXTRA_DATA_TYPE_EXITED_VALIDATORS = 2;

    /// @notice 表示Oracle报告不包含额外数据的额外数据格式
    uint256 public constant EXTRA_DATA_FORMAT_EMPTY = 0;

    /// @notice 额外数据数组的列表格式。当所有额外数据处理适合单个或多个交易时使用。
    uint256 public constant EXTRA_DATA_FORMAT_LIST = 1;

    // ================================ 存储变量 ================================

    /// @notice GTETH合约地址
    address public GTETH;

    /// @notice GTETH定位器合约
    IGTETHLocator public LOCATOR;

    /// @notice 额外数据处理状态
    ExtraDataProcessingState private _extraDataProcessingState;

    // ================================ 初始化函数 ================================

    /**
     * @notice 初始化函数
     * @param gtethLocator GTETH定位器地址
     * @param gteth GTETH合约地址
     * @param slotsPerEpoch 每个纪元的时隙数
     * @param secondsPerSlot 每个插槽的秒数
     * @param genesisTime 创世时间
     * @param oracleMember Oracle成员地址
     * @param lastProcessingRefSlot 最后处理的参考插槽
     * @param epochsPerFrame 每帧的纪元数
     */
    function initialize(
        address gtethLocator,
        address gteth,
        uint256 slotsPerEpoch,
        uint256 secondsPerSlot,
        uint256 genesisTime,
        address oracleMember,
        uint256 lastProcessingRefSlot,
        uint256 epochsPerFrame
    ) public initializer {
        if (gtethLocator == address(0)) revert Error.GTETHLocatorCannotBeZero();
        if (gteth == address(0)) revert Error.GTETHCannotBeZero();
        
        __BaseOracle_init(slotsPerEpoch, secondsPerSlot, genesisTime, oracleMember, lastProcessingRefSlot, epochsPerFrame);
        
        LOCATOR = IGTETHLocator(gtethLocator);
        GTETH = gteth;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
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
     * - 提供的共识版本与预期版本不同
     * - 提供的参考插槽与当前共识帧的不同
     * - 当前共识帧的处理截止时间已过
     * - 数据的keccak256哈希与哈希共识合约提供的最后哈希不同
     * - 提供的数据未通过安全检查
     */
    function submitReportData(ReportData calldata data) external whenNotPaused {
        _submitReport(data.refSlot, keccak256(abi.encode(data)));
        _startProcessing();
        _handleConsensusReportData(data);
    }

    /**
     * @notice 触发当报告中不存在额外数据时所需的处理，
     * 即当额外数据格式等于EXTRA_DATA_FORMAT_EMPTY时。
     */
    function submitReportExtraDataEmpty() external {
        _submitReportExtraDataEmpty();
    }

    /**
     * @notice 以EXTRA_DATA_FORMAT_LIST格式提交报告额外数据进行处理
     * @param data 包含项目列表的额外数据块。详见`EXTRA_DATA_FORMAT_LIST`常量的文档
     */
    function submitReportExtraDataList(bytes calldata data) external {
        _submitReportExtraDataList(data);
    }

    /**
     * @notice 返回当前报告帧的数据处理状态
     * @return result 详见`ProcessingState`结构体的文档
     */
    function getProcessingState()
        external
        view
        returns (ProcessingState memory result)
    {
        ConsensusReport memory report = _consensusReport;
        result.currentFrameRefSlot = _getCurrentRefSlot();

        if (
            report.hash == ZERO_HASH ||
            result.currentFrameRefSlot != report.refSlot
        ) {
            return result;
        }

        result.processingDeadlineTime = report.processingDeadlineTime;
        result.mainDataHash = report.hash;

        uint256 processingRefSlot = _lastProcessingRefSlot;
        result.mainDataSubmitted = report.refSlot == processingRefSlot;
        if (!result.mainDataSubmitted) {
            return result;
        }

        ExtraDataProcessingState memory extraState = _extraDataProcessingState;
        result.extraDataHash = extraState.dataHash;
        result.extraDataFormat = extraState.dataFormat;
        result.extraDataSubmitted = extraState.submitted;
        result.extraDataItemsCount = extraState.itemsCount;
        result.extraDataItemsSubmitted = extraState.itemsProcessed;
    }

    // ================================ 内部实现函数 ================================

    /**
     * @notice 处理共识报告
     * @param prevProcessingRefSlot 之前处理的参考插槽
     */
    function _handleConsensusReport(
        ConsensusReport memory /* report */, // 共识报告数据（未使用）
        uint256 /* prevSubmittedRefSlot */, // 之前提交的参考插槽（未使用）
        uint256 prevProcessingRefSlot // 之前处理的参考插槽
    ) internal override {
        ExtraDataProcessingState memory state = _extraDataProcessingState;
        if (
            state.refSlot == prevProcessingRefSlot &&
            (!state.submitted || state.itemsProcessed < state.itemsCount)
        ) {
            emit WarnExtraDataIncompleteProcessing(
                prevProcessingRefSlot,
                state.itemsProcessed,
                state.itemsCount
            );
        }
    }

    /**
     * @notice 处理共识报告数据
     * @param data 报告数据
     */
    function _handleConsensusReportData(ReportData calldata data) internal {
        if (data.extraDataFormat == EXTRA_DATA_FORMAT_EMPTY) {
            if (data.extraDataHash != ZERO_HASH) {
                revert Error.UnexpectedExtraDataHash(ZERO_HASH, data.extraDataHash);
            }
            if (data.extraDataItemsCount != 0) {
                revert Error.UnexpectedExtraDataItemsCount(
                    0,
                    data.extraDataItemsCount
                );
            }
        } else {
            if (data.extraDataFormat != EXTRA_DATA_FORMAT_LIST) {
                revert Error.UnsupportedExtraDataFormat(data.extraDataFormat);
            }
            if (data.extraDataItemsCount == 0) {
                revert Error.ExtraDataItemsCountCannotBeZeroForNonEmptyData();
            }
            if (data.extraDataHash == ZERO_HASH) {
                revert Error.ExtraDataHashCannotBeZeroForNonEmptyData();
            }
        }

        uint256 slotsElapsed = data.refSlot - _lastProcessingRefSlot;

        IStakingRouter stakingRouter = IStakingRouter(LOCATOR.stakingRouter());

        _processStakingRouterExitedValidatorsByModule(
            stakingRouter,
            data.stakingModuleIdsWithNewlyExitedValidators,
            data.numExitedValidatorsByStakingModule
        );

        IGTETH(GTETH).handleOracleReport(
            GENESIS_TIME + data.refSlot * SECONDS_PER_SLOT,
            slotsElapsed * SECONDS_PER_SLOT,
            data.numValidators,
            data.clBalanceGwei * 1e9,
            data.withdrawalVaultBalance,
            data.elRewardsVaultBalance,
            data.withdrawalFinalizationBatches
        );

        _extraDataProcessingState = ExtraDataProcessingState({
            refSlot: data.refSlot.toUint64(),
            dataFormat: data.extraDataFormat.toUint16(),
            submitted: false,
            dataHash: data.extraDataHash,
            itemsCount: data.extraDataItemsCount.toUint16(),
            itemsProcessed: 0,
            lastSortingKey: 0
        });
    }

    /**
     * @notice 处理质押路由器的退出验证者模块数据
     * @param stakingRouter 质押路由器合约
     * @param stakingModuleIds 质押模块ID数组
     * @param numExitedValidatorsByStakingModule 每个质押模块的退出验证者数量数组
     */
    function _processStakingRouterExitedValidatorsByModule(
        IStakingRouter stakingRouter,
        uint256[] calldata stakingModuleIds,
        uint256[] calldata numExitedValidatorsByStakingModule
    ) internal {
        if (
            stakingModuleIds.length != numExitedValidatorsByStakingModule.length
        ) {
            revert Error.InvalidExitedValidatorsData();
        }

        if (stakingModuleIds.length == 0) {
            return;
        }

        for (uint256 i = 1; i < stakingModuleIds.length; ) {
            if (stakingModuleIds[i] <= stakingModuleIds[i - 1]) {
                revert Error.InvalidExitedValidatorsData();
            }
            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < stakingModuleIds.length; ) {
            if (numExitedValidatorsByStakingModule[i] == 0) {
                revert Error.InvalidExitedValidatorsData();
            }
            unchecked {
                ++i;
            }
        }

        stakingRouter.updateExitedValidatorsCountByStakingModule(
            stakingModuleIds,
            numExitedValidatorsByStakingModule
        );
    }

    /**
     * @notice 提交空的额外数据报告
     */
    function _submitReportExtraDataEmpty() internal {
        ExtraDataProcessingState memory procState = _extraDataProcessingState;
        _checkCanSubmitExtraData(procState, EXTRA_DATA_FORMAT_EMPTY);
        if (procState.submitted) revert Error.ExtraDataAlreadyProcessed();

        IStakingRouter(LOCATOR.stakingRouter())
            .onValidatorsCountsByNodeOperatorReportingFinished();
        _extraDataProcessingState.submitted = true;
        emit ExtraDataSubmitted(procState.refSlot, 0, 0);
    }

    /**
     * @notice 检查是否可以提交额外数据
     * @param procState 处理状态
     * @param format 数据格式
     */
    function _checkCanSubmitExtraData(
        ExtraDataProcessingState memory procState,
        uint256 format
    ) internal view {
        _checkReporter();
        ConsensusReport memory report = _consensusReport;

        if (report.hash == ZERO_HASH || procState.refSlot != report.refSlot) {
            revert Error.CannotSubmitExtraDataBeforeMainData();
        }

        _checkProcessingDeadline();

        if (procState.dataFormat != format) {
            revert Error.UnexpectedExtraDataFormat(procState.dataFormat, format);
        }
    }

    /**
     * @notice 额外数据迭代状态结构体
     */
    struct ExtraDataIterState {
        uint256 index; // 当前索引
        uint256 itemType; // 项目类型
        uint256 dataOffset; // 数据偏移量
        uint256 lastSortingKey; // 最后排序键
        address stakingRouter; // 质押路由器地址
    }

    /**
     * @notice 提交列表格式的额外数据报告
     * @param data 额外数据
     */
    function _submitReportExtraDataList(bytes calldata data) internal {
        ExtraDataProcessingState memory procState = _extraDataProcessingState;
        _checkCanSubmitExtraData(procState, EXTRA_DATA_FORMAT_LIST);

        if (procState.itemsProcessed == procState.itemsCount) {
            revert Error.ExtraDataAlreadyProcessed();
        }

        bytes32 dataHash = keccak256(data);
        if (dataHash != procState.dataHash) {
            revert Error.UnexpectedExtraDataHash(procState.dataHash, dataHash);
        }

        // 加载下一个哈希值
        assembly {
            dataHash := calldataload(data.offset)
        }

        ExtraDataIterState memory iter = ExtraDataIterState({
            index: procState.itemsProcessed > 0
                ? procState.itemsProcessed - 1
                : 0,
            itemType: 0,
            dataOffset: 32, // 跳过下一个哈希字节
            lastSortingKey: procState.lastSortingKey,
            stakingRouter: LOCATOR.stakingRouter()
        });

        _processExtraDataItems(data, iter);
        uint256 itemsProcessed = iter.index + 1;

        if (dataHash == ZERO_HASH) {
            if (itemsProcessed != procState.itemsCount) {
                revert Error.UnexpectedExtraDataItemsCount(
                    procState.itemsCount,
                    itemsProcessed
                );
            }

            procState.submitted = true;
            procState.itemsProcessed = uint64(itemsProcessed);
            procState.lastSortingKey = iter.lastSortingKey;
            _extraDataProcessingState = procState;

            IStakingRouter(iter.stakingRouter)
                .onValidatorsCountsByNodeOperatorReportingFinished();
        } else {
            if (itemsProcessed >= procState.itemsCount) {
                revert Error.UnexpectedExtraDataItemsCount(
                    procState.itemsCount,
                    itemsProcessed
                );
            }

            // 保存下一个哈希值
            procState.dataHash = dataHash;
            procState.itemsProcessed = uint64(itemsProcessed);
            procState.lastSortingKey = iter.lastSortingKey;
            _extraDataProcessingState = procState;
        }

        emit ExtraDataSubmitted(
            procState.refSlot,
            procState.itemsProcessed,
            procState.itemsCount
        );
    }

    /**
     * @notice 处理额外数据项目
     * @param data 数据
     * @param iter 迭代状态
     */
    function _processExtraDataItems(
        bytes calldata data,
        ExtraDataIterState memory iter
    ) internal {
        uint256 dataOffset = iter.dataOffset;
        uint256 maxNodeOperatorsPerItem = 0;
        uint256 maxNodeOperatorItemIndex = 0;
        uint256 itemsCount;
        uint256 index;
        uint256 itemType;

        while (dataOffset < data.length) {
            /// @solidity memory-safe-assembly
            assembly {
                // 数据偏移量处的布局：
                // |  3 bytes  | 2 bytes  |   X bytes   |
                // | itemIndex | itemType | itemPayload |
                let header := calldataload(add(data.offset, dataOffset))
                index := shr(232, header)
                itemType := and(shr(216, header), 0xffff)
                dataOffset := add(dataOffset, 5)
            }

            if (iter.lastSortingKey == 0) {
                if (index != 0) {
                    revert Error.UnexpectedExtraDataIndex(0, index);
                }
            } else if (index != iter.index + 1) {
                revert Error.UnexpectedExtraDataIndex(iter.index + 1, index);
            }

            iter.index = index;
            iter.itemType = itemType;
            iter.dataOffset = dataOffset;

            if (
                itemType == EXTRA_DATA_TYPE_EXITED_VALIDATORS ||
                itemType == EXTRA_DATA_TYPE_STUCK_VALIDATORS
            ) {
                uint256 nodeOpsProcessed = _processExtraDataItem(data, iter);

                if (nodeOpsProcessed > maxNodeOperatorsPerItem) {
                    maxNodeOperatorsPerItem = nodeOpsProcessed;
                    maxNodeOperatorItemIndex = index;
                }
            } else {
                revert Error.UnsupportedExtraDataType(index, itemType);
            }

            assert(iter.dataOffset > dataOffset);
            dataOffset = iter.dataOffset;
            unchecked {
                // 这里不可能溢出
                ++itemsCount;
            }
        }

        assert(maxNodeOperatorsPerItem > 0);
    }

    /**
     * @notice 处理单个额外数据项目
     * @param data 数据
     * @param iter 迭代状态
     * @return 处理的节点操作员数量
     */
    function _processExtraDataItem(
        bytes calldata data,
        ExtraDataIterState memory iter
    ) internal returns (uint256) {
        uint256 dataOffset = iter.dataOffset;
        uint256 moduleId;
        uint256 nodeOpsCount;
        uint256 nodeOpId;
        bytes calldata nodeOpIds;
        bytes calldata valuesCounts;

        if (dataOffset + 35 > data.length) {
            // 必须至少适合moduleId（3字节）、nodeOpsCount（8字节）
            // 和一个节点操作员的数据（8 + 16字节），总共35字节
            revert Error.InvalidExtraDataItem(iter.index);
        }

        /// @solidity memory-safe-assembly
        assembly {
            // 数据偏移量处的布局：
            // | 3 bytes  |   8 bytes    |  nodeOpsCount * 8 bytes  |  nodeOpsCount * 16 bytes  |
            // | moduleId | nodeOpsCount |      nodeOperatorIds     |      validatorsCounts     |
            let header := calldataload(add(data.offset, dataOffset))
            moduleId := shr(232, header)
            nodeOpsCount := and(shr(168, header), 0xffffffffffffffff)
            nodeOpIds.offset := add(data.offset, add(dataOffset, 11))
            nodeOpIds.length := mul(nodeOpsCount, 8)
            // 读取第一个节点操作员ID以便稍后检查排序顺序
            nodeOpId := shr(192, calldataload(nodeOpIds.offset))
            valuesCounts.offset := add(nodeOpIds.offset, nodeOpIds.length)
            valuesCounts.length := mul(nodeOpsCount, 16)
            dataOffset := sub(
                add(valuesCounts.offset, valuesCounts.length),
                data.offset
            )
        }

        if (moduleId == 0) {
            revert Error.InvalidExtraDataItem(iter.index);
        }

        unchecked {
            // 首先，检查第一个项目的元素与上一个项目最后一个元素之间的排序顺序

            // | 2 bytes  | 19 bytes | 3 bytes  | 8 bytes  |
            // | itemType | 00000000 | moduleId | nodeOpId |
            uint256 sortingKey = (iter.itemType << 240) |
                (moduleId << 64) |
                nodeOpId;
            if (sortingKey <= iter.lastSortingKey) {
                revert Error.InvalidExtraDataSortOrder(iter.index);
            }

            // 其次，检查其余元素之间的排序顺序
            uint256 tmpNodeOpId;
            for (uint256 i = 1; i < nodeOpsCount; ) {
                /// @solidity memory-safe-assembly
                assembly {
                    tmpNodeOpId := shr(
                        192,
                        calldataload(add(nodeOpIds.offset, mul(i, 8)))
                    )
                    i := add(i, 1)
                }
                if (tmpNodeOpId <= nodeOpId) {
                    revert Error.InvalidExtraDataSortOrder(iter.index);
                }
                nodeOpId = tmpNodeOpId;
            }

            // 用最后一个项目的元素更新最后排序键
            iter.lastSortingKey = ((sortingKey >> 64) << 64) | nodeOpId;
        }

        if (dataOffset > data.length || nodeOpsCount == 0) {
            revert Error.InvalidExtraDataItem(iter.index);
        }

        if (iter.itemType == EXTRA_DATA_TYPE_STUCK_VALIDATORS) {
            IStakingRouter(iter.stakingRouter)
                .reportStakingModuleStuckValidatorsCountByNodeOperator(
                    moduleId,
                    nodeOpIds,
                    valuesCounts
                );
        } else {
            IStakingRouter(iter.stakingRouter)
                .reportStakingModuleExitedValidatorsCountByNodeOperator(
                    moduleId,
                    nodeOpIds,
                    valuesCounts
                );
        }

        iter.dataOffset = dataOffset;
        return nodeOpsCount;
    }


    // ================================ 管理员函数 ================================

    function setGTETH(address _gteth) external onlyRole(DEFAULT_ADMIN_ROLE) {
        GTETH = _gteth;
    }

    function setLOCATOR(address _gtethLocator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        LOCATOR = IGTETHLocator(_gtethLocator);
    }
}
