// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Math } from "../lib/Math.sol";
import { Error } from "../lib/Error.sol";

/**
 * @title BaseOracle
 * @notice gtETH项目的Oracle基础合约
 * @dev 提供单Oracle成员的共识功能，管理报告的提交和处理
 * 
 * 主要功能：
 * 1. 管理Oracle成员权限
 * 2. 处理报告的提交和验证
 * 3. 提供角色权限控制
 * 4. 存储和管理共识状态
 * 5. 提供暂停/恢复功能
 * 6. 集成时间和帧计算功能
 */
abstract contract BaseOracle is AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using SafeCast for uint256;

    // ================================ 事件定义 ================================
    
    event FrameConfigSet(uint256 newInitialEpoch, uint256 newEpochsPerFrame);
    event OracleMemberSet(address indexed addr, address indexed prevAddr);
    event ConsensusVersionSet(uint256 indexed version, uint256 indexed prevVersion);
    event ReportSubmitted(uint256 indexed refSlot, bytes32 hash, uint256 processingDeadlineTime);
    event ReportDiscarded(uint256 indexed refSlot, bytes32 hash);
    event ProcessingStarted(uint256 indexed refSlot, bytes32 hash);
    event WarnProcessingMissed(uint256 indexed refSlot);

    // ================================ 结构体定义 ================================
    
    /**
     * @notice 共识报告结构体
     * @param hash 报告哈希值
     * @param refSlot 参考插槽
     * @param processingDeadlineTime 处理截止时间
     */
    struct ConsensusReport {
        bytes32 hash;                    
        uint64 refSlot;                  
        uint64 processingDeadlineTime;   
    }

    /// @notice 帧配置结构体
    /// @dev 包含报告帧的时间相关配置
    struct FrameConfig {
        uint64 initialEpoch;  // 初始纪元
        uint64 epochsPerFrame;  // 每帧的纪元数
    }

    /// @notice 共识帧结构体
    /// @dev 描述单个报告帧的详细信息
    struct ConsensusFrame {
        uint256 index;  // 帧索引
        uint256 refSlot;  // 参考时隙
        uint256 reportProcessingDeadlineSlot;  // 报告处理截止时隙
    }

    /**
     * @notice 零哈希值
     */
    bytes32 internal constant ZERO_HASH = bytes32(0);
    
    /// @notice 处理截止时隙偏移量
    uint256 internal constant DEADLINE_SLOT_OFFSET = 0;

    // ================================ 角色定义 ================================
    
    /**
     * @notice 管理Oracle成员角色
     * @dev 授予设置Oracle成员权限的ACL角色
     */
    bytes32 public constant MANAGE_ORACLE_MEMBER_ROLE = keccak256("MANAGE_ORACLE_MEMBER_ROLE");

    /**
     * @notice 管理帧配置的角色
     */
    bytes32 public constant MANAGE_FRAME_CONFIG_ROLE = keccak256("MANAGE_FRAME_CONFIG_ROLE");

    /**
     * @notice 提交数据角色
     * @dev 授予提交报告数据权限的ACL角色
     */
    bytes32 public constant SUBMIT_DATA_ROLE = keccak256("SUBMIT_DATA_ROLE");

    /**
     * @notice 暂停角色
     * @dev 授予暂停接受数据提交权限的ACL角色
     */
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    /**
     * @notice 恢复角色
     * @dev 授予恢复接受数据提交权限的ACL角色
     */
    bytes32 public constant RESUME_ROLE = keccak256("RESUME_ROLE");

    /**
     * @notice 升级角色
     * @dev 授予升级合约权限的ACL角色
     */
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    // ================================ 存储变量 ================================
    
    /**
     * @notice Oracle成员地址
     */
    address internal _oracleMember;
    
    /**
     * @notice 最后处理的参考插槽
     */
    uint256 internal _lastProcessingRefSlot;
    
    /**
     * @notice 当前共识报告
     */
    ConsensusReport internal _consensusReport;
    
    /**
     * @notice 报告帧配置
     */
    FrameConfig internal _frameConfig;

    // ================================ 不可变变量 ================================
    
    /// @notice 每个纪元的时隙数
    uint64 internal SLOTS_PER_EPOCH;
    
    /**
     * @notice 每个插槽的秒数
     */
    uint64 public SECONDS_PER_SLOT;
    
    /**
     * @notice 创世时间
     */
    uint64 public GENESIS_TIME;

    // ================================ 构造函数 ================================
    
    /**
     * @notice 初始化函数
     * @param slotsPerEpoch 每个纪元的时隙数
     * @param secondsPerSlot 每个插槽的秒数
     * @param genesisTime 创世时间
     */
    function __BaseOracle_init(uint256 slotsPerEpoch, uint256 secondsPerSlot, uint256 genesisTime, address oracleMember, uint256 lastProcessingRefSlot, uint256 epochsPerFrame) internal onlyInitializing {
        // 验证链配置参数
        if (slotsPerEpoch == 0) revert Error.InvalidChainConfig();  // 每纪元时隙数不能为0
        if (secondsPerSlot == 0) revert Error.SecondsPerSlotCannotBeZero();
        if (genesisTime == 0) revert Error.GenesisTimeCannotBeZero();
        
        // 初始化父合约
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        // 设置不可变的链配置
        SLOTS_PER_EPOCH = slotsPerEpoch.toUint64();  // 安全转换为uint64
        SECONDS_PER_SLOT = secondsPerSlot.toUint64();  // 安全转换为uint64
        GENESIS_TIME = genesisTime.toUint64();  // 安全转换为uint64

        // 设置Oracle成员地址
        _setOracleMember(oracleMember);
        // 设置最后处理的参考插槽
        _lastProcessingRefSlot = lastProcessingRefSlot;
        // 初始化共识报告的参考插槽（防止意外的零值）
        _consensusReport.refSlot = lastProcessingRefSlot.toUint64();
        
        // 计算一个遥远的未来纪元作为初始配置，使用时调用updateInitialEpoch函数更新initialEpoch，再进行使用
        uint256 farFutureEpoch = _computeEpochAtTimestamp(type(uint64).max);
        
        // 设置帧配置，使用遥远的未来纪元作为初始值
        _setFrameConfig(farFutureEpoch, epochsPerFrame, FrameConfig(0, 0));
    }

    // ================================ 管理函数 ================================
    
    /**
     * @notice 恢复接受数据提交
     */
    function resume() external whenPaused onlyRole(RESUME_ROLE) {
        _unpause();
    }

    /**
     * @notice 暂停接受数据提交
     */
    function pause() external whenNotPaused onlyRole(PAUSE_ROLE) {
        _pause();
    }

    /**
     * @notice 获取Oracle成员地址
     * @return Oracle成员地址
     */
    function getOracleMember() external view returns (address) {
        return _oracleMember;
    }

    /**
     * @notice 设置Oracle成员地址
     * @param addr 新的Oracle成员地址
     */
    function setOracleMember(address addr) external onlyRole(MANAGE_ORACLE_MEMBER_ROLE) {
        _setOracleMember(addr);
    }

    /**
     * @notice 获取时间相关配置
     * @return initialEpoch 零索引帧的纪元
     * @return epochsPerFrame 帧的长度（以纪元为单位）
     */
    function getFrameConfig() external view returns (
        uint256 initialEpoch,
        uint256 epochsPerFrame
    ) {
        FrameConfig memory config = _frameConfig;
        return (config.initialEpoch, config.epochsPerFrame);
    }

    /**
     * @notice 获取当前报告帧
     * @return refSlot 帧的参考时隙
     * @return reportProcessingDeadlineSlot 报告处理截止时隙
     */
    function getCurrentFrame() external view returns (
        uint256 refSlot,
        uint256 reportProcessingDeadlineSlot
    ) {
        ConsensusFrame memory frame = _getCurrentFrame();
        return (frame.refSlot, frame.reportProcessingDeadlineSlot);
    }

    /**
     * @notice 获取链配置信息
     * @return slotsPerEpoch 每个纪元的时隙数
     * @return secondsPerSlot 每个时隙的秒数
     * @return genesisTime 创世时间
     */
    function getChainConfig() external view returns (
        uint256 slotsPerEpoch,
        uint256 secondsPerSlot,
        uint256 genesisTime
    ) {
        return (SLOTS_PER_EPOCH, SECONDS_PER_SLOT, GENESIS_TIME);
    }

    /**
     * @notice 获取最早可能的参考时隙
     * @return 零索引报告帧的参考时隙
     */
    function getInitialRefSlot() external view returns (uint256) {
        return _getInitialFrame().refSlot;
    }
    
    /**
     * @notice 更新初始纪元（仅当当前初始纪元在未来时）
     * @param initialEpoch 新的初始纪元
     */
    function updateInitialEpoch(uint256 initialEpoch) external onlyRole(DEFAULT_ADMIN_ROLE) {
        FrameConfig memory prevConfig = _frameConfig;

        if (_computeEpochAtTimestamp(_getTime()) >= prevConfig.initialEpoch) {
            revert Error.InitialEpochAlreadyArrived();
        }

        _setFrameConfig(initialEpoch, prevConfig.epochsPerFrame, prevConfig);

        if (_getInitialFrame().refSlot < _lastProcessingRefSlot) {
            revert Error.InitialEpochIsYetToArrive();
        }
    }

    /**
     * @notice 更新时间相关配置
     * @param epochsPerFrame 帧的长度（以纪元为单位）
     */
    function setFrameConfig(uint256 epochsPerFrame)
        external onlyRole(MANAGE_FRAME_CONFIG_ROLE)
    {
        uint256 timestamp = _getTime();
        uint256 currentFrameStartEpoch = _computeFrameStartEpoch(timestamp, _frameConfig);
        _setFrameConfig(currentFrameStartEpoch, epochsPerFrame, _frameConfig);
    }
    
    // ================================ 数据提供接口 ================================
    
    /**
     * @notice 获取最后的共识报告哈希和元数据
     * @return hash 报告哈希
     * @return refSlot 参考插槽
     * @return processingDeadlineTime 处理截止时间
     * @return processingStarted 是否已开始处理
     */
    function getConsensusReport() external view returns (
        bytes32 hash,                     // 报告哈希值
        uint256 refSlot,                  // 参考插槽
        uint256 processingDeadlineTime,   // 处理截止时间
        bool processingStarted            // 是否已开始处理
    ) {
        ConsensusReport memory report = _consensusReport;
        return (
            report.hash,                  // 报告哈希
            report.refSlot,              // 参考插槽
            report.processingDeadlineTime, // 处理截止时间
            // 处理已开始的条件：哈希不为零且参考插槽等于最后处理的插槽
            report.hash != bytes32(0) && report.refSlot == _lastProcessingRefSlot
        );
    }

    /**
     * @notice 获取最后一个开始处理报告的参考插槽
     * @return 最后处理的参考插槽
     */
    function getLastProcessingRefSlot() external view returns (uint256) {
        return _lastProcessingRefSlot;
    }

    // ================================ 子合约接口 ================================

    /**
     * @notice 检查给定地址是否为Oracle成员
     * @param addr 要检查的地址
     * @return 是否为成员
     */
    function _isOracleMember(address addr) internal view returns (bool) {
        return _oracleMember == addr;
    }

    /**
     * @notice 当oracle获得新的共识报告时调用
     * @param report 共识报告
     * @param prevSubmittedRefSlot 之前提交的参考插槽
     * @param prevProcessingRefSlot 之前处理的参考插槽
     */
    function _handleConsensusReport(
        ConsensusReport memory report,    // 新的共识报告
        uint256 prevSubmittedRefSlot,    // 之前提交的参考插槽
        uint256 prevProcessingRefSlot    // 之前处理的参考插槽
    ) internal virtual;

    /**
     * @notice 由子合约调用，标记当前共识报告为正在处理
     * @return 调用前最后一个开始处理的参考插槽
     * 
     * @dev 在调用此函数之前，oracle可以自由地提交新的报告。
     * 调用此函数后，当前帧的共识报告保证保持不变。
     */
    function _startProcessing() internal returns (uint256) {
        ConsensusReport memory report = _consensusReport;
        if (report.hash == bytes32(0)) {
            revert Error.NoConsensusReportToProcess();
        }

        _checkProcessingDeadline(report.processingDeadlineTime);

        uint256 prevProcessingRefSlot = _lastProcessingRefSlot;
        if (prevProcessingRefSlot == report.refSlot) {
            revert Error.RefSlotAlreadyProcessing();
        }

        _lastProcessingRefSlot = report.refSlot;

        emit ProcessingStarted(report.refSlot, report.hash);
        return prevProcessingRefSlot;
    }

    /**
     * @notice 检查当前共识报告的处理截止时间是否已过期
     * @dev 如果截止时间已过期则回滚
     */
    function _checkProcessingDeadline() internal view {
        _checkProcessingDeadline(_consensusReport.processingDeadlineTime);
    }

    /**
     * @notice 检查指定的处理截止时间是否已过期
     * @param deadlineTime 截止时间
     * @dev 如果截止时间已过期则回滚
     */
    function _checkProcessingDeadline(uint256 deadlineTime) internal view {
        if (_getTime() > deadlineTime) revert Error.ProcessingDeadlineMissed(deadlineTime);
    }

    /**
     * @notice 获取当前帧的参考时隙
     * @return 当前参考时隙
     */
    function _getCurrentRefSlot() internal view returns (uint256) {
        return _getCurrentFrame().refSlot;
    }

    // ================================ 内部实现函数 ================================
    /**
     * @notice 设置Oracle成员地址
     * @param addr 新的Oracle成员地址
     */
    function _setOracleMember(address addr) internal {
        if (addr == address(0)) revert Error.AddressCannotBeZero();
        
        address prevAddr = _oracleMember;
        _oracleMember = addr;
        emit OracleMemberSet(addr, prevAddr);
    }

    /**
     * @notice 设置帧配置
     * @param initialEpoch 初始纪元
     * @param epochsPerFrame 每帧纪元数
     * @param prevConfig 先前配置
     */
    function _setFrameConfig(
        uint256 initialEpoch,
        uint256 epochsPerFrame,
        FrameConfig memory prevConfig
    ) internal {
        if (epochsPerFrame == 0) revert Error.EpochsPerFrameCannotBeZero();

        _frameConfig = FrameConfig(
            initialEpoch.toUint64(),
            epochsPerFrame.toUint64()
        );

        if (initialEpoch != prevConfig.initialEpoch || epochsPerFrame != prevConfig.epochsPerFrame) {
            emit FrameConfigSet(initialEpoch, epochsPerFrame);
        }
    }

    // ============= 时间和帧计算函数 =============

    /**
     * @notice 获取当前帧
     * @return 当前共识帧
     */
    function _getCurrentFrame() internal view returns (ConsensusFrame memory) {
        return _getFrameAtTimestamp(_getTime(), _frameConfig);
    }

    /**
     * @notice 获取初始帧
     * @return 初始共识帧
     */
    function _getInitialFrame() internal view returns (ConsensusFrame memory) {
        return _getFrameAtIndex(0, _frameConfig);
    }

    /**
     * @notice 根据时间戳获取帧
     * @param timestamp 时间戳
     * @param config 帧配置
     * @return 对应的共识帧
     */
    function _getFrameAtTimestamp(uint256 timestamp, FrameConfig memory config)
        internal view returns (ConsensusFrame memory)
    {
        return _getFrameAtIndex(_computeFrameIndex(timestamp, config), config);
    }

    /**
     * @notice 根据索引获取帧
     * @param frameIndex 帧索引
     * @param config 帧配置
     * @return 对应的共识帧
     */
    function _getFrameAtIndex(uint256 frameIndex, FrameConfig memory config)
        internal view returns (ConsensusFrame memory)
    {
        uint256 frameStartEpoch = _computeStartEpochOfFrameWithIndex(frameIndex, config);
        uint256 frameStartSlot = _computeStartSlotAtEpoch(frameStartEpoch);
        uint256 nextFrameStartSlot = frameStartSlot + config.epochsPerFrame * SLOTS_PER_EPOCH;

        return ConsensusFrame({
            index: frameIndex,
            refSlot: uint64(frameStartSlot - 1),
            reportProcessingDeadlineSlot: uint64(nextFrameStartSlot - 1 - DEADLINE_SLOT_OFFSET)
        });
    }

    /**
     * @notice 计算指定索引帧的开始纪元
     * @param frameIndex 帧索引
     * @param config 帧配置
     * @return 开始纪元
     */
    function _computeStartEpochOfFrameWithIndex(uint256 frameIndex, FrameConfig memory config)
        internal pure returns (uint256)
    {
        return config.initialEpoch + frameIndex * config.epochsPerFrame;
    }

    /**
     * @notice 计算帧索引
     * @param timestamp 时间戳
     * @param config 帧配置
     * @return 帧索引
     */
    function _computeFrameIndex(uint256 timestamp, FrameConfig memory config)
        internal view returns (uint256)
    {
        uint256 epoch = _computeEpochAtTimestamp(timestamp);
        if (epoch < config.initialEpoch) {
            revert Error.InitialEpochIsYetToArrive();
        }
        return (epoch - config.initialEpoch) / config.epochsPerFrame;
    }

    /**
     * @notice 计算时间戳对应的纪元
     * @param timestamp 时间戳
     * @return 纪元
     */
    function _computeEpochAtTimestamp(uint256 timestamp) internal view returns (uint256) {
        return _computeEpochAtSlot(_computeSlotAtTimestamp(timestamp));
    }

    /**
     * @notice 计算时间戳对应的时隙
     * @param timestamp 时间戳
     * @return 时隙
     */
    function _computeSlotAtTimestamp(uint256 timestamp) internal view returns (uint256) {
        return (timestamp - GENESIS_TIME) / SECONDS_PER_SLOT;
    }

    /**
     * @notice 计算时隙对应的纪元
     * @param slot 时隙
     * @return 纪元
     */
    function _computeEpochAtSlot(uint256 slot) internal view returns (uint256) {
        return slot / SLOTS_PER_EPOCH;
    }

    /**
     * @notice 计算纪元的开始时隙
     * @param epoch 纪元
     * @return 开始时隙
     */
    function _computeStartSlotAtEpoch(uint256 epoch) internal view returns (uint256) {
        return epoch * SLOTS_PER_EPOCH;
    }

    /**
     * @notice 计算时隙对应的时间戳
     * @param slot 时隙
     * @return 时间戳
     */
    function computeTimestampAtSlot(uint256 slot) public view returns (uint256) {
        return GENESIS_TIME + slot * SECONDS_PER_SLOT;
    }

    /**
     * @notice 计算帧开始纪元
     * @param timestamp 时间戳
     * @param config 帧配置
     * @return 帧开始纪元
     */
    function _computeFrameStartEpoch(uint256 timestamp, FrameConfig memory config)
        internal view returns (uint256)
    {
        return _computeStartEpochOfFrameWithIndex(_computeFrameIndex(timestamp, config), config);
    }

    /**
     * @notice 获取当前时间
     * @return 当前区块时间戳
     * @dev 虚拟函数，子合约可以重写以用于测试
     */
    function _getTime() internal virtual view returns (uint256) {
        return block.timestamp;
    }

    // ============= 报告处理函数 =============

    /**
     * @notice 提交报告
     * @param slot 时隙
     * @param report 报告哈希
     */
    function _submitReport(uint256 slot, bytes32 report) internal {
        if (slot == 0) revert Error.InvalidSlot();
        if (slot > type(uint64).max) revert Error.NumericOverflow();
        if (report == ZERO_HASH) revert Error.EmptyReport();
        _checkReporter();
        uint256 timestamp = _getTime();
        uint256 currentSlot = _computeSlotAtTimestamp(timestamp);
        FrameConfig memory config = _frameConfig;
        ConsensusFrame memory frame = _getFrameAtTimestamp(timestamp, config);

        if (slot != frame.refSlot) revert Error.InvalidSlot();
        if (currentSlot > frame.reportProcessingDeadlineSlot) revert Error.StaleReport();

        // 对于单Oracle模式，直接提交共识报告
        uint256 deadline = computeTimestampAtSlot(frame.reportProcessingDeadlineSlot);
        _submitConsensusReport(report, slot, deadline);
    }

    function _checkReporter() internal view {
        // 检查发送者是否为Oracle成员或拥有提交数据权限
        address sender = msg.sender;
        if (!hasRole(SUBMIT_DATA_ROLE, sender) && !_isOracleMember(sender)) {
            revert Error.SenderNotAllowed();
        }
    }

    /**
     * @notice 内部提交共识报告
     * @param reportHash 报告哈希
     * @param refSlot 参考时隙
     * @param deadline 处理截止时间
     */
    function _submitConsensusReport(bytes32 reportHash, uint256 refSlot, uint256 deadline) internal {
        uint256 prevSubmittedRefSlot = _consensusReport.refSlot;
        
        if (refSlot < prevSubmittedRefSlot) {
            revert Error.RefSlotCannotDecrease(refSlot, prevSubmittedRefSlot);
        }

        if (refSlot <= _lastProcessingRefSlot) {
            revert Error.RefSlotMustBeGreaterThanProcessingOne(refSlot, _lastProcessingRefSlot);
        }

        if (_getTime() > deadline) {
            revert Error.ProcessingDeadlineMissed(deadline);
        }

        if (refSlot != prevSubmittedRefSlot && _lastProcessingRefSlot != prevSubmittedRefSlot) {
            emit WarnProcessingMissed(prevSubmittedRefSlot);
        }

        if (reportHash == bytes32(0)) {
            revert Error.HashCannotBeZero();
        }

        emit ReportSubmitted(refSlot, reportHash, deadline);

        ConsensusReport memory report = ConsensusReport({
            hash: reportHash,
            refSlot: refSlot.toUint64(),
            processingDeadlineTime: deadline.toUint64()
        });

        _consensusReport = report;
        _handleConsensusReport(report, prevSubmittedRefSlot, _lastProcessingRefSlot);
    }

    /**
     * @notice UUPS升级授权函数
     * @dev 只有具有UPGRADER_ROLE角色的地址可以升级合约
     * @param newImplementation 新的实现合约地址
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {
        // 可以在这里添加额外的升级验证逻辑
    }
}
