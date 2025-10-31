// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IGTETHLocator} from "./interfaces/IGTETHLocator.sol";  
import {IGTETH} from "./interfaces/IGTETH.sol";               
import {INodeOperatorsRegistry} from "./interfaces/INodeOperatorsRegistry.sol";                 
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol"; 
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Math} from "./lib/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title NodeOperatorsRegistry
 * @notice 节点运营商注册表合约 - 管理单个节点运营商的签名密钥和其他数据
 * @dev 同时负责向节点运营商分发奖励
 *      
 * 注意: 下面的代码假设适量的节点运营商数量，即最多 `MAX_NODE_OPERATORS_COUNT` 个
 */
contract NodeOperatorsRegistry is AccessControlUpgradeable, UUPSUpgradeable {
    
    using Math for uint256;
    using SafeERC20 for IERC20;
    
    event NodeOperatorAdded(uint256 nodeOperatorId, string name, address rewardAddress, uint64 stakingLimit);
    event NodeOperatorActiveSet(uint256 indexed nodeOperatorId, bool active);
    event NodeOperatorNameSet(uint256 indexed nodeOperatorId, string name);
    event NodeOperatorRewardAddressSet(uint256 indexed nodeOperatorId, address rewardAddress);
    event NodeOperatorTotalKeysTrimmed(uint256 indexed nodeOperatorId, uint64 totalKeysTrimmed);
    event KeysOpIndexSet(uint256 keysOpIndex);
    event StakingModuleTypeSet(bytes32 moduleType);
    event RewardsDistributed(address indexed rewardAddress, uint256 rewardAmount);
    event RewardDistributionStateChanged(RewardDistributionState state);
    event LocatorContractSet(address locatorAddress);
    event VettedSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 approvedValidatorsCount);
    event DepositedSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 depositedValidatorsCount);
    event ExitedSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 exitedValidatorsCount);
    event TotalSigningKeysCountChanged(uint256 indexed nodeOperatorId, uint256 totalValidatorsCount);
    event NonceChanged(uint256 nonce);
    event StuckPenaltyDelayChanged(uint256 stuckPenaltyDelay);
    event StuckPenaltyStateChanged(
        uint256 indexed nodeOperatorId,
        uint256 stuckValidatorsCount,
        uint256 refundedValidatorsCount,
        uint256 stuckPenaltyEndTimestamp
    );
    event TargetValidatorsCountChanged(uint256 indexed nodeOperatorId, uint256 targetValidatorsCount, uint256 targetLimitMode);
    event NodeOperatorPenalized(address indexed recipientAddress, uint256 penalizedAmount);
    event NodeOperatorPenaltyCleared(uint256 indexed nodeOperatorId);

    //
    // 访问控制角色定义 - 使用keccak256哈希定义不同的权限角色
    //
    bytes32 public constant MANAGE_SIGNING_KEYS = keccak256("MANAGE_SIGNING_KEYS");
    // 管理签名密钥的角色权限，允许添加/删除验证者密钥
    bytes32 public constant SET_NODE_OPERATOR_LIMIT_ROLE = keccak256("SET_NODE_OPERATOR_LIMIT_ROLE");
    // 设置节点运营商限制的角色权限，允许修改质押限制
    bytes32 public constant MANAGE_NODE_OPERATOR_ROLE = keccak256("MANAGE_NODE_OPERATOR_ROLE");
    // 管理节点运营商的角色权限，允许添加/激活/停用运营商
    bytes32 public constant STAKING_ROUTER_ROLE = keccak256("STAKING_ROUTER_ROLE");
    // 质押路由器角色权限，允许执行存款和状态更新操作

    //
    // 常量定义 - 定义合约中使用的不可变常量
    //
    uint256 public constant MAX_NODE_OPERATORS_COUNT = 200;
    // 最大节点运营商数量限制，防止gas消耗过高
    uint256 public constant MAX_NODE_OPERATOR_NAME_LENGTH = 255;
    // 节点运营商名称的最大长度限制
    uint256 public constant MAX_STUCK_PENALTY_DELAY = 365 days;
    // 卡住惩罚的最大延迟时间，设为1年
    uint256 internal constant UINT64_MAX = 0xFFFFFFFFFFFFFFFF;
    // uint64类型的最大值，用于范围检查

    // SigningKeysStats 偏移量 - 用于在打包的uint256中存储多个uint64值的位偏移
    uint8 internal constant TOTAL_VETTED_KEYS_COUNT_OFFSET = 0;      // 运营商的最大验证者密钥数量，由管理员批准用于存款
    uint8 internal constant TOTAL_EXITED_KEYS_COUNT_OFFSET = 1;      // 此运营商所有时间内处于EXITED状态的密钥数量
    uint8 internal constant TOTAL_KEYS_COUNT_OFFSET = 2;             // 此运营商所有时间内的密钥总数
    uint8 internal constant TOTAL_DEPOSITED_KEYS_COUNT_OFFSET = 3;   // 此运营商所有时间内处于DEPOSITED状态的密钥数量

    // TargetValidatorsStats 偏移量 - 用于目标验证者统计信息的位偏移
    uint8 internal constant TARGET_LIMIT_MODE_OFFSET = 0;            // 目标限制模式，允许限制运营商的目标活跃验证者数量 (0 = 禁用, 1 = 软模式, 2 = 强制模式)
    uint8 internal constant TARGET_VALIDATORS_COUNT_OFFSET = 1;       // 运营商的相对目标活跃验证者限制，由管理员设置
    uint8 internal constant MAX_VALIDATORS_COUNT_OFFSET = 2;          // 运营商实际可以存款的密钥数量

    // StuckPenaltyStats 偏移量 - 用于卡住惩罚统计信息的位偏移
    uint8 internal constant STUCK_VALIDATORS_COUNT_OFFSET = 0;        // 来自预言机报告的卡住密钥数量
    uint8 internal constant REFUNDED_VALIDATORS_COUNT_OFFSET = 1;     // 来自管理员的退款密钥数量
    uint8 internal constant STUCK_PENALTY_END_TIMESTAMP_OFFSET = 2;   // 卡住密钥解决后的额外惩罚时间

    // 摘要 SigningKeysStats 偏移量 - 用于所有运营商汇总统计的位偏移
    uint8 internal constant SUMMARY_MAX_VALIDATORS_COUNT_OFFSET = 0;   // 所有运营商的最大验证者数量
    uint8 internal constant SUMMARY_EXITED_KEYS_COUNT_OFFSET = 1;      // 所有运营商所有时间内处于EXITED状态的密钥数量
    uint8 internal constant SUMMARY_DEPOSITED_KEYS_COUNT_OFFSET = 2;   // 所有运营商所有时间内处于DEPOSITED状态的密钥数量

    error APP_AUTH_FAILED();
    error VALUE_IS_THE_SAME();
    error OUT_OF_RANGE();
    error WRONG_OPERATOR_ACTIVE_STATE();
    error MAX_OPERATORS_COUNT_EXCEEDED();
    error INVALID_ALLOCATED_KEYS_COUNT();
    error VETTED_KEYS_COUNT_INCREASED();
    error EXITED_VALIDATORS_COUNT_DECREASED();
    error DISTRIBUTION_NOT_READY();
    error INVALID_REPORT_DATA();
    error CANT_CLEAR_PENALTY();
    error WRONG_NAME_LENGTH();
    error LIDO_REWARD_ADDRESS();
    error ZERO_ADDRESS();

    //
    // 数据结构定义
    //

    /// @dev 节点运营商参数和内部状态
    struct NodeOperator {
        bool active;                                   
        address rewardAddress;                         
        string name;                                   
        // 签名密钥统计：打包存储已审核、已退出、总数、已存款四个uint64值，节省存储空间
        Packed64x4 signingKeysStats;                  
        // 卡住惩罚统计：打包存储卡住验证者数量、退款验证者数量、惩罚结束时间戳
        Packed64x4 stuckPenaltyStats;                 
        // 目标验证者统计：打包存储目标限制模式、目标验证者数量、最大验证者数量
        Packed64x4 targetValidatorsStats;             
    }

    struct NodeOperatorSummary {
        Packed64x4 summarySigningKeysStats;            
        // 全局汇总统计：所有运营商的密钥统计信息汇总，用于快速获取全局状态
    }

    // 用于打包4个uint64值的结构体
    struct Packed64x4 {
        uint256 packed;
        // 打包存储：将4个uint64值（每个64位）打包到一个uint256（256位）中，优化存储成本
        // 通过位运算可以从packed中提取或设置特定位置的uint64值
    }

    // 奖励分配状态枚举// 奖励分配状态枚举
    enum RewardDistributionState {
        TransferredToModule,      // 新的奖励部分已铸造并转移到模块
        ReadyForDistribution,     // 运营商统计已更新，奖励准备分配
        Distributed               // 奖励已在运营商之间分配
    }

    //
    // 存储变量
    //

    // 所有节点运营商的映射。使用映射以便能够扩展结构体
    mapping(uint256 => NodeOperator) internal _nodeOperators;
    // 节点运营商映射：运营商ID -> NodeOperator结构体，存储所有运营商的详细信息
    NodeOperatorSummary internal _nodeOperatorSummary;
    // 节点运营商汇总：存储所有运营商的统计汇总信息，避免每次都重新计算

    IGTETHLocator public locator;
    // 定位器合约引用：用于获取GTETH系统中其他合约的地址，通过initialize函数设置
    bytes32 internal moduleType;
    // 模块类型：标识此质押模块的类型，用于区分不同的质押模块实现
    uint256 internal totalOperatorsCount;
    // 总运营商数量：记录当前已注册的节点运营商总数，包括活跃和非活跃的
    uint256 internal activeOperatorsCount;
    // 活跃运营商数量：记录当前处于活跃状态的节点运营商数量
    uint256 internal keysOpIndex;
    // 密钥操作索引：每次密钥相关操作时递增，用作nonce防止重放攻击和追踪变化
    uint256 internal stuckPenaltyDelay;
    // 卡住惩罚延迟：验证者解除卡住状态后的额外惩罚时间，单位为秒
    RewardDistributionState internal rewardDistributionState;
    // 奖励分发状态：跟踪当前奖励分发流程的状态（已分发、转移到模块、准备分发等）

    mapping(uint256 => mapping(uint256 => bytes)) internal signingKeys;    
    // 签名密钥存储：运营商ID -> 密钥索引 -> 密钥数据（48字节的BLS公钥）
    mapping(uint256 => mapping(uint256 => bytes)) internal signatures;   
    // 签名数据存储：运营商ID -> 密钥索引 -> 签名数据（96字节的BLS签名，用于存款合约）
    mapping(bytes32 => bool) internal pubkeyUsed;
    // 公钥使用状态：记录公钥是否已被使用

    modifier onlyExistedNodeOperator(uint256 _nodeOperatorId) {
        // 检查节点运营商是否存在的修饰符
        _requireValidRange(_nodeOperatorId < getNodeOperatorsCount());
        _;
    }

    modifier onlyValidNodeOperatorName(string memory _name) {
        // 检查节点运营商名称是否有效的修饰符
        // 名称不能为空字符串，且长度不能超过最大限制
        require(bytes(_name).length > 0 && bytes(_name).length <= MAX_NODE_OPERATOR_NAME_LENGTH, "WRONG_NAME_LENGTH");
        _;
    }

    modifier onlyValidRewardAddress(address _rewardAddress) {
        // 检查奖励地址是否有效的修饰符
        _onlyNonZeroAddress(_rewardAddress);
        require(_rewardAddress != locator.gteth(), "LIDO_REWARD_ADDRESS");
        _;
    }

    /// @notice 初始化合约
    /// @param _type 质押模块类型
    /// @param _stuckPenaltyDelay 卡住验证者的惩罚延迟时间
    /// @param _admin 默认管理员地址
    function initialize(bytes32 _type, uint256 _stuckPenaltyDelay, address _admin) 
        external 
        initializer 
    {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        
        moduleType = _type;  // 设置质押模块的类型标识
        stuckPenaltyDelay = _stuckPenaltyDelay;  // 设置卡住验证者的惩罚延迟时间
        rewardDistributionState = RewardDistributionState.Distributed;  // 初始化奖励分发状态为已分发
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);  // 授予指定地址默认管理员角色
        
        emit StakingModuleTypeSet(_type);  // 记录质押模块类型设置
    }

    /// @notice 授权升级函数 - 仅允许默认管理员升级合约
    /// @param newImplementation 新的实现合约地址
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        // 空实现，权限检查在 onlyRole 修饰符中完成
    }

    /// @notice 设置定位器合约地址
    /// @param _locator GTETH定位器合约地址
    function setLocator(IGTETHLocator _locator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _onlyNonZeroAddress(address(_locator));  // 确保定位器地址不为零地址
        
        locator = _locator;  // 设置定位器合约地址
        
        emit LocatorContractSet(address(_locator)); 
    }

    //
    // 节点运营商管理函数
    //

    /// @notice 添加名为 `name`，奖励地址为 `rewardAddress`，质押限制为0个验证者的节点运营商
    /// @param _name 名称
    /// @param _rewardAddress 接收此运营商GTETH奖励的以太坊地址
    /// @return id 添加的运营商的唯一键
    function addNodeOperator(string memory _name, address _rewardAddress) 
        external
        onlyValidNodeOperatorName(_name)      
        onlyValidRewardAddress(_rewardAddress) 
        onlyRole(MANAGE_NODE_OPERATOR_ROLE)   
        returns (uint256 id) 
    {
        id = getNodeOperatorsCount();  // 获取当前运营商总数作为新运营商的ID
        require(id < MAX_NODE_OPERATORS_COUNT, "MAX_OPERATORS_COUNT_EXCEEDED");  // 检查是否超过最大数量限制

        totalOperatorsCount = id + 1;  // 增加总运营商数量
        NodeOperator storage operator = _nodeOperators[id];  // 获取新运营商的存储引用
        activeOperatorsCount += 1;  // 增加活跃运营商数量（新添加的运营商默认为活跃状态）

        operator.active = true;  // 设置运营商为活跃状态
        operator.name = _name;   // 设置运营商名称
        operator.rewardAddress = _rewardAddress;  // 设置奖励接收地址

        emit NodeOperatorAdded(id, _name, _rewardAddress, 0); 
    }

    /// @notice 激活给定id的已停用节点运营商
    /// @param _nodeOperatorId 要激活的节点运营商id
    function activateNodeOperator(uint256 _nodeOperatorId) 
        external 
        onlyExistedNodeOperator(_nodeOperatorId)  
        onlyRole(MANAGE_NODE_OPERATOR_ROLE)      
    {
        require(!getNodeOperatorIsActive(_nodeOperatorId), "WRONG_OPERATOR_ACTIVE_STATE");  // 确保运营商当前为非活跃状态
        
        activeOperatorsCount += 1;
        _nodeOperators[_nodeOperatorId].active = true;  

        emit NodeOperatorActiveSet(_nodeOperatorId, true);
        _increaseValidatorsKeysNonce();
    }

    /// @notice 停用给定id的活跃节点运营商
    /// @param _nodeOperatorId 要停用的节点运营商id
    function deactivateNodeOperator(uint256 _nodeOperatorId) 
        external 
        onlyExistedNodeOperator(_nodeOperatorId)  
        onlyRole(MANAGE_NODE_OPERATOR_ROLE)       
    {
        require(getNodeOperatorIsActive(_nodeOperatorId), "WRONG_OPERATOR_ACTIVE_STATE");  // 确保运营商当前为活跃状态
        
        activeOperatorsCount -= 1;
        _nodeOperators[_nodeOperatorId].active = false;  

        emit NodeOperatorActiveSet(_nodeOperatorId, false);

        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);  
        uint256 vettedSigningKeysCount = _get(signingKeysStats, TOTAL_VETTED_KEYS_COUNT_OFFSET);  
        uint256 depositedSigningKeysCount = _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET);  

        // 将审核密钥数量重置为已存款验证者数量
        if (vettedSigningKeysCount > depositedSigningKeysCount) {
            // 如果已审核密钥数量大于已存款数量，需要减少审核数量防止新的存款
            _set(signingKeysStats, TOTAL_VETTED_KEYS_COUNT_OFFSET, depositedSigningKeysCount);  // 设置审核密钥数为已存款数
            _saveOperatorSigningKeysStats(_nodeOperatorId, signingKeysStats);  // 保存更新后的统计信息

            emit VettedSigningKeysCountChanged(_nodeOperatorId, depositedSigningKeysCount);  
            _updateSummaryMaxValidatorsCount(_nodeOperatorId);  // 更新全局最大验证者数量统计
        }
        _increaseValidatorsKeysNonce();  
    }

    /// @notice 更改给定id节点运营商的名称
    /// @param _nodeOperatorId 要设置名称的节点运营商id
    /// @param _name 节点运营商的新名称
    function setNodeOperatorName(uint256 _nodeOperatorId, string memory _name) 
        external
        onlyValidNodeOperatorName(_name)         
        onlyExistedNodeOperator(_nodeOperatorId)
        onlyRole(MANAGE_NODE_OPERATOR_ROLE)  
    {
        // 防止重复设置名称
        _requireNotSameValue(keccak256(bytes(_nodeOperators[_nodeOperatorId].name)) != keccak256(bytes(_name)));
        _nodeOperators[_nodeOperatorId].name = _name;
        emit NodeOperatorNameSet(_nodeOperatorId, _name);
    }

    /// @notice 更改给定id节点运营商的奖励地址
    /// @param _nodeOperatorId 要设置奖励地址的节点运营商id
    /// @param _rewardAddress 要设置为奖励地址的执行层以太坊地址
    function setNodeOperatorRewardAddress(uint256 _nodeOperatorId, address _rewardAddress) 
        external 
        onlyValidRewardAddress(_rewardAddress)    
        onlyExistedNodeOperator(_nodeOperatorId) 
        onlyRole(MANAGE_NODE_OPERATOR_ROLE)     
    {
        // 检查新地址是否与当前地址不同
        _requireNotSameValue(_nodeOperators[_nodeOperatorId].rewardAddress != _rewardAddress);
        _nodeOperators[_nodeOperatorId].rewardAddress = _rewardAddress;
        emit NodeOperatorRewardAddressSet(_nodeOperatorId, _rewardAddress);
    }

    /// @notice 为给定id的节点运营商设置要质押的验证者最大数量
    /// @param _nodeOperatorId 要设置质押限制的节点运营商id
    /// @param _vettedSigningKeysCount 节点运营商的新质押限制
    function setNodeOperatorStakingLimit(uint256 _nodeOperatorId, uint64 _vettedSigningKeysCount) 
        external
        onlyExistedNodeOperator(_nodeOperatorId)  
        onlyRole(SET_NODE_OPERATOR_LIMIT_ROLE)    
    {
        require(getNodeOperatorIsActive(_nodeOperatorId), "WRONG_OPERATOR_ACTIVE_STATE");  
        _updateVettedSigningKeysCount(_nodeOperatorId, _vettedSigningKeysCount, true);  // 更新审核密钥数量，允许增加
        _increaseValidatorsKeysNonce();  
    }

    //
    // 签名密钥管理函数
    //

    /// @notice 向节点运营商#`_nodeOperatorId`的密钥中添加`_quantity`个验证者签名密钥。连接的密钥为：`_pubkeys`
    /// @param _nodeOperatorId 节点运营商id
    /// @param _keysCount 提供的签名密钥数量
    /// @param _publicKeys 几个连接的验证者签名密钥
    /// @param _signatures 几个连接的(pubkey, withdrawal_credentials, 32000000000)消息的签名
    function addSigningKeys(
        uint256 _nodeOperatorId, 
        uint256 _keysCount, 
        bytes calldata _publicKeys, 
        bytes calldata _signatures
    ) external {
        // 调用内部函数添加签名密钥，包含权限检查和数据验证
        _addSigningKeys(_nodeOperatorId, _keysCount, _publicKeys, _signatures);
    }

    /// @notice 从节点运营商#`_nodeOperatorId`的密钥中删除验证者签名密钥#`_index`
    /// @param _nodeOperatorId 节点运营商id
    /// @param _fromIndex 密钥的索引，从0开始
    /// @param _keysCount 要删除的密钥数量
    function removeSigningKeys(uint256 _nodeOperatorId, uint256 _fromIndex, uint256 _keysCount) external {
        // 调用内部函数删除未使用的签名密钥，包含权限检查和状态验证
        _removeUnusedSigningKeys(_nodeOperatorId, _fromIndex, _keysCount);
    }

    /// @notice 返回节点运营商#`_nodeOperatorId`的第n个签名密钥
    /// @param _nodeOperatorId 节点运营商id
    /// @param _index 密钥的索引，从0开始
    /// @return key 密钥
    /// @return depositSignature deposit_contract.deposit调用所需的签名
    /// @return used 指示密钥是否在质押中使用的标志
    function getSigningKey(uint256 _nodeOperatorId, uint256 _index)
        external
        view
        returns (bytes memory key, bytes memory depositSignature, bool used)
    {
        bool[] memory keyUses;  // 声明密钥使用状态数组
        // 调用getSigningKeys函数获取单个密钥信息（从_index开始获取1个密钥）
        (key, depositSignature, keyUses) = getSigningKeys(_nodeOperatorId, _index, 1);
        used = keyUses[0];  // 获取第一个（也是唯一一个）密钥的使用状态
    }

    /// @notice 返回节点运营商#`_nodeOperatorId`的n个签名密钥
    /// @param _nodeOperatorId 节点运营商id
    /// @param _offset 密钥的偏移量，从0开始
    /// @param _limit 要返回的密钥数量
    /// @return pubkeys 连接到字节批次的密钥
    /// @return depositSignatures 连接到字节批次的签名，用于deposit_contract.deposit调用
    /// @return used 指示密钥是否在质押中使用的标志数组
    function getSigningKeys(uint256 _nodeOperatorId, uint256 _offset, uint256 _limit)
        public
        view
        onlyExistedNodeOperator(_nodeOperatorId)  
        returns (bytes memory pubkeys, bytes memory depositSignatures, bool[] memory used)
    {

        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);  // 加载运营商密钥统计信息
        // 验证请求的密钥范围不超过运营商的总密钥数量
        _requireValidRange(_offset + _limit <= _get(signingKeysStats, TOTAL_KEYS_COUNT_OFFSET));

        uint256 depositedSigningKeysCount = _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET);  // 获取已存款密钥数量
        (pubkeys, depositSignatures) = _initKeysSigsBuf(_limit);  // 初始化密钥和签名数据缓冲区
        used = new bool[](_limit);  // 初始化使用状态数组

        // 从存储中加载指定范围的密钥和签名数据到缓冲区
        _loadKeysSigs(_nodeOperatorId, _offset, _limit, pubkeys, depositSignatures, 0);
        for (uint256 i; i < _limit; ++i) {
            // 如果密钥索引小于已存款密钥数量，则该密钥已被使用
            used[i] = (_offset + i) < depositedSigningKeysCount;
        }
    }

    //
    // 验证者状态管理函数
    //

    /// @notice 由StakingRouter调用，以减少给定id节点运营商的审核密钥数量
    /// @param _nodeOperatorIds 字节打包的节点运营商id数组
    /// @param _vettedSigningKeysCounts 字节打包的节点运营商新审核密钥数量数组
    /// @dev 减少审核密钥数量，用于减少运营商的审核密钥数量（当运营商出现风险状况时进行调用）
    function decreaseVettedSigningKeysCount(
        bytes calldata _nodeOperatorIds,
        bytes calldata _vettedSigningKeysCounts
    ) external onlyRole(STAKING_ROUTER_ROLE) { 
        // 检查报告数据的有效性，返回运营商数量
        uint256 nodeOperatorsCount = _checkReportPayload(_nodeOperatorIds.length, _vettedSigningKeysCounts.length);
        uint256 totalNodeOperatorsCount = getNodeOperatorsCount();  // 获取总运营商数量用于验证

        uint256 nodeOperatorId;  
        uint256 vettedKeysCount; 
        
        for (uint256 i; i < nodeOperatorsCount; ++i) {
            nodeOperatorId = _extractNodeOperatorId(_nodeOperatorIds, i);      // 从字节数据中提取运营商ID
            vettedKeysCount = _extractVettedKeysCount(_vettedSigningKeysCounts, i);  // 从字节数据中提取审核密钥数量
            
            _requireValidRange(nodeOperatorId < totalNodeOperatorsCount);  // 验证运营商ID有效性
            _updateVettedSigningKeysCount(nodeOperatorId, vettedKeysCount, false);  // 更新审核密钥数量，不允许增加
        }
        _increaseValidatorsKeysNonce(); 
    }

    /// @notice 由StakingRouter调用，以发出GTETH奖励已为此模块铸造的信号
    function onRewardsMinted() external onlyRole(STAKING_ROUTER_ROLE) { 
        // 更新奖励分发状态为"已转移到模块"，表示奖励已经铸造并转移到此模块
        _updateRewardDistributionState(RewardDistributionState.TransferredToModule);
    }

    /// @notice 由StakingRouter调用，以更新给定节点运营商被请求退出但在最大允许时间内未能退出的验证者数量
    /// @param _nodeOperatorIds 字节打包的节点运营商id数组
    /// @param _stuckValidatorsCounts 字节打包的节点运营商新卡住验证者数量数组
    /// @dev 更新卡住验证者数量，用于更新运营商的卡住验证者数量（这些是已被请求退出但在预期时间内未能成功退出的验证者）
    function updateStuckValidatorsCount(bytes calldata _nodeOperatorIds, bytes calldata _stuckValidatorsCounts) 
        external onlyRole(STAKING_ROUTER_ROLE) 
    {
        // 检查报告数据的有效性，返回运营商数量
        uint256 nodeOperatorsCount = _checkReportPayload(_nodeOperatorIds.length, _stuckValidatorsCounts.length);
        uint256 totalNodeOperatorsCount = getNodeOperatorsCount();  // 获取总运营商数量用于验证

        uint256 nodeOperatorId;    
        uint256 validatorsCount;  
        
        for (uint256 i; i < nodeOperatorsCount; ++i) {
            nodeOperatorId = _extractNodeOperatorId(_nodeOperatorIds, i);           // 从字节数据中提取运营商ID
            validatorsCount = _extractStuckValidatorsCount(_stuckValidatorsCounts, i);  // 从字节数据中提取卡住验证者数量
            
            _requireValidRange(nodeOperatorId < totalNodeOperatorsCount);  // 验证运营商ID有效性
            _updateStuckValidatorsCount(nodeOperatorId, validatorsCount);  // 更新卡住验证者数量
        }
        _increaseValidatorsKeysNonce();  
    }

    /// @notice 由StakingRouter调用，以更新给定id节点运营商处于EXITED状态的验证者数量
    /// @param _nodeOperatorIds 字节打包的节点运营商id数组
    /// @param _exitedValidatorsCounts 字节打包的节点运营商新EXITED验证者数量数组
    function updateExitedValidatorsCount(
        bytes calldata _nodeOperatorIds,
        bytes calldata _exitedValidatorsCounts
    ) external onlyRole(STAKING_ROUTER_ROLE) {
        // 检查报告数据的有效性，返回运营商数量
        uint256 nodeOperatorsCount = _checkReportPayload(_nodeOperatorIds.length, _exitedValidatorsCounts.length);
        uint256 totalNodeOperatorsCount = getNodeOperatorsCount();  // 获取总运营商数量用于验证

        uint256 nodeOperatorId; 
        uint256 validatorsCount;  
        
        for (uint256 i; i < nodeOperatorsCount; ++i) {
            nodeOperatorId = _extractNodeOperatorId(_nodeOperatorIds, i);             // 从字节数据中提取运营商ID
            validatorsCount = _extractExitedValidatorsCount(_exitedValidatorsCounts, i);  // 从字节数据中提取已退出验证者数量
            
            _requireValidRange(nodeOperatorId < totalNodeOperatorsCount);  // 验证运营商ID有效性
            _updateExitedValidatorsCount(nodeOperatorId, validatorsCount, false);  // 更新已退出验证者数量，不允许减少
        }
        _increaseValidatorsKeysNonce();  
    }

    /// @notice 更新给定id节点运营商的退款验证者数量
    /// @param _nodeOperatorId 节点运营商的Id
    /// @param _refundedValidatorsCount 节点运营商的新退款验证者数量
    function updateRefundedValidatorsCount(uint256 _nodeOperatorId, uint256 _refundedValidatorsCount) 
        external
        onlyExistedNodeOperator(_nodeOperatorId) 
        onlyRole(STAKING_ROUTER_ROLE)            
    {
        _updateRefundValidatorsKeysCount(_nodeOperatorId, _refundedValidatorsCount);  // 更新退款验证者密钥数量
        _increaseValidatorsKeysNonce(); 
    }

    /// @notice 更新节点运营商的目标验证者限制
    /// @param _nodeOperatorId 节点运营商ID
    /// @param _targetLimitMode 目标限制模式
    /// @param _targetLimit 目标验证者数量限制
    function updateTargetValidatorsLimits(
        uint256 _nodeOperatorId,
        uint256 _targetLimitMode,
        uint256 _targetLimit
    ) external
        onlyExistedNodeOperator(_nodeOperatorId) 
        onlyRole(STAKING_ROUTER_ROLE)            
    {
        require(_targetLimitMode <= 2, "INVALID_TARGET_LIMIT_MODE");  // 验证限制模式有效性
        require(_targetLimit <= UINT64_MAX, "INVALID_TARGET_LIMIT");  // 验证目标限制值不超过uint64最大值

        Packed64x4 memory operatorTargetStats = _loadOperatorTargetValidatorsStats(_nodeOperatorId);  // 加载目标验证者统计

        // 如果新值与当前值相同，直接返回避免不必要的存储操作
        if (_get(operatorTargetStats, TARGET_LIMIT_MODE_OFFSET) == _targetLimitMode &&
            _get(operatorTargetStats, TARGET_VALIDATORS_COUNT_OFFSET) == _targetLimit) {
            return;
        }

        // 更新目标限制模式和目标验证者数量
        _set(operatorTargetStats, TARGET_LIMIT_MODE_OFFSET, _targetLimitMode);
        _set(operatorTargetStats, TARGET_VALIDATORS_COUNT_OFFSET, _targetLimit);
        _saveOperatorTargetValidatorsStats(_nodeOperatorId, operatorTargetStats);

        // 更新全局最大验证者数量统计，因为目标限制影响可分配的验证者数量
        _updateSummaryMaxValidatorsCount(_nodeOperatorId);

        _increaseValidatorsKeysNonce();
        emit TargetValidatorsCountChanged(_nodeOperatorId, _targetLimit, _targetLimitMode);
    }

    /// @notice 不安全地更新给定id节点运营商的EXITED/STUCK状态验证者数量
    /// @dev '不安全'意味着此方法可以同时增加和减少退出和卡住计数器
    /// @param _nodeOperatorId 节点运营商id
    /// @param _exitedValidatorsCount 节点运营商的新EXITED验证者数量
    /// @param _stuckValidatorsCount 节点运营商的新STUCK验证者数量
    function unsafeUpdateValidatorsCount(
        uint256 _nodeOperatorId,
        uint256 _exitedValidatorsCount,
        uint256 _stuckValidatorsCount
    ) external 
        onlyExistedNodeOperator(_nodeOperatorId)  
        onlyRole(STAKING_ROUTER_ROLE)            
    {
        _updateStuckValidatorsCount(_nodeOperatorId, _stuckValidatorsCount);     // 更新卡住验证者数量
        _updateExitedValidatorsCount(_nodeOperatorId, _exitedValidatorsCount, true);  // 更新退出验证者数量，允许减少
        _increaseValidatorsKeysNonce();  
    }

    //
    // 奖励分配函数
    //
    /// @notice 无权限方法，用于根据最新会计报告在节点运营商之间分配所有累积的模块奖励
    function distributeReward() external {
        require(getRewardDistributionState() == RewardDistributionState.ReadyForDistribution, "DISTRIBUTION_NOT_READY");
        _updateRewardDistributionState(RewardDistributionState.Distributed);
        // 执行实际的奖励分发逻辑
        _distributeRewards();
    }

    /// @notice 由StakingRouter在完成更新此模块节点运营商的退出和卡住验证者计数后调用
    function onExitedAndStuckValidatorsCountsUpdated() external onlyRole(STAKING_ROUTER_ROLE) { 
        _updateRewardDistributionState(RewardDistributionState.ReadyForDistribution);
    }

    /// @notice 由StakingRouter调用，以通知提款凭证已更改
    /// @dev 当系统的提款凭证发生变更时，StakingRouter会调用此函数通知所有质押模块
    ///      此函数会无效化所有未使用的签名密钥，因为它们使用了旧的提款凭证
    function onWithdrawalCredentialsChanged() external onlyRole(STAKING_ROUTER_ROLE) {  
        // 无效化所有运营商的未使用存款密钥
        uint256 operatorsCount = getNodeOperatorsCount();  // 获取运营商总数
        if (operatorsCount > 0) {
            // 对所有运营商进行密钥无效化处理
            _invalidateReadyToDepositKeysRange(0, operatorsCount - 1);
        }
    }

    /// @notice 无效化指定范围内运营商的所有未使用验证者密钥
    /// @param _indexFrom 第一个运营商的索引（包含）
    /// @param _indexTo 最后一个运营商的索引（包含）
    function invalidateReadyToDepositKeysRange(uint256 _indexFrom, uint256 _indexTo) external onlyRole(MANAGE_NODE_OPERATOR_ROLE) {  
        _invalidateReadyToDepositKeysRange(_indexFrom, _indexTo); 
    }

    /// @notice 内部函数：无效化指定范围内运营商的未使用密钥
    /// @param _indexFrom 起始运营商索引（包含）
    /// @param _indexTo 结束运营商索引（包含）
    function _invalidateReadyToDepositKeysRange(uint256 _indexFrom, uint256 _indexTo) internal {
        // 验证索引范围的有效性：起始索引不能大于结束索引，且结束索引不能超出运营商总数
        _requireValidRange(_indexFrom <= _indexTo && _indexTo < getNodeOperatorsCount());

        uint256 trimmedKeysCount;         // 单个运营商被修剪的密钥数量
        uint256 totalTrimmedKeysCount;    // 所有运营商被修剪的密钥总数
        uint256 totalSigningKeysCount;    // 运营商的总密钥数量
        uint256 depositedSigningKeysCount; // 运营商已存款密钥数量
        Packed64x4 memory signingKeysStats; // 运营商签名密钥统计信息

        // 遍历指定范围内的所有运营商
        for (uint256 nodeOperatorId = _indexFrom; nodeOperatorId <= _indexTo; ++nodeOperatorId) {
            signingKeysStats = _loadOperatorSigningKeysStats(nodeOperatorId);  // 加载运营商密钥统计

            totalSigningKeysCount = _get(signingKeysStats, TOTAL_KEYS_COUNT_OFFSET);           // 获取总密钥数量
            depositedSigningKeysCount = _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET); // 获取已存款密钥数量

            // 如果总密钥数量等于已存款数量，说明没有未使用的密钥，跳过此运营商
            if (totalSigningKeysCount == depositedSigningKeysCount) continue;
            // 断言确保总密钥数量大于已存款数量（数据完整性检查）
            assert(totalSigningKeysCount > depositedSigningKeysCount);

            // 计算需要修剪的密钥数量（未使用的密钥数量）
            trimmedKeysCount = totalSigningKeysCount - depositedSigningKeysCount;
            totalTrimmedKeysCount += trimmedKeysCount;  // 累加到总修剪数量

            // 更新运营商密钥统计：将总密钥数量和已审核密钥数量都设为已存款数量
            // 这样做的效果是删除所有未使用的密钥
            _set(signingKeysStats, TOTAL_KEYS_COUNT_OFFSET, depositedSigningKeysCount);        // 设置总密钥数为已存款数
            _set(signingKeysStats, TOTAL_VETTED_KEYS_COUNT_OFFSET, depositedSigningKeysCount); // 设置已审核密钥数为已存款数
            _saveOperatorSigningKeysStats(nodeOperatorId, signingKeysStats);                   // 保存更新后的统计信息

            // 更新全局汇总统计中的最大验证者数量
            _updateSummaryMaxValidatorsCount(nodeOperatorId);

            emit TotalSigningKeysCountChanged(nodeOperatorId, depositedSigningKeysCount);      
            emit VettedSigningKeysCountChanged(nodeOperatorId, depositedSigningKeysCount);     
            emit NodeOperatorTotalKeysTrimmed(nodeOperatorId, uint64(trimmedKeysCount));      
        }

        if (totalTrimmedKeysCount > 0) {
            _increaseValidatorsKeysNonce(); 
        }
    }

    //
    // 查询函数
    //

    /// @notice 按id返回节点运营商
    /// @param _nodeOperatorId 节点运营商id
    /// @param _fullInfo 如果为true，还将返回名称
    function getNodeOperator(uint256 _nodeOperatorId, bool _fullInfo)
        external
        view
        onlyExistedNodeOperator(_nodeOperatorId)  
        returns (
            bool active,
            string memory name,
            address rewardAddress,
            uint64 totalVettedValidators,
            uint64 totalExitedValidators,
            uint64 totalAddedValidators,
            uint64 totalDepositedValidators
        )
    {
        NodeOperator storage nodeOperator = _nodeOperators[_nodeOperatorId];  // 获取运营商存储引用
        active = nodeOperator.active;              // 获取活跃状态
        rewardAddress = nodeOperator.rewardAddress; // 获取奖励地址
        name = _fullInfo ? nodeOperator.name : ""; // 根据_fullInfo参数决定是否返回名称

        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);  // 加载签名密钥统计信息
        totalVettedValidators = uint64(_get(signingKeysStats, TOTAL_VETTED_KEYS_COUNT_OFFSET));      // 获取已审核验证者数量
        totalExitedValidators = uint64(_get(signingKeysStats, TOTAL_EXITED_KEYS_COUNT_OFFSET));      // 获取已退出验证者数量
        totalAddedValidators = uint64(_get(signingKeysStats, TOTAL_KEYS_COUNT_OFFSET));              // 获取总添加验证者数量
        totalDepositedValidators = uint64(_get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET)); // 获取已存款验证者数量
    }

    /// @notice 返回每个节点运营商的有效质押比例奖励分配
    /// @param _totalRewardAmount 要分配的GTETH代币总量
    function getRewardsDistribution(uint256 _totalRewardAmount)
        public
        view
        returns (address[] memory recipients, uint256[] memory amounts, bool[] memory penalized)
    {
        uint256 nodeOperatorCount = getNodeOperatorsCount();    // 获取节点运营商总数
        uint256 activeCount = getActiveNodeOperatorsCount();    // 获取活跃节点运营商数量
        
        recipients = new address[](activeCount);  // 初始化奖励接收者地址数组
        amounts = new uint256[](activeCount);     // 初始化奖励代币数量数组
        penalized = new bool[](activeCount);      // 初始化惩罚状态数组
        uint256 idx = 0;  // 数组索引计数器

        uint256 totalActiveValidatorsCount = 0;  // 总活跃验证者数量
        
        // 第一轮循环：计算每个活跃运营商的活跃验证者数量
        for (uint256 operatorId; operatorId < nodeOperatorCount; ++operatorId) {
            if (!getNodeOperatorIsActive(operatorId)) continue;  // 跳过非活跃运营商

            Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(operatorId);  // 加载签名密钥统计
            uint256 totalExitedValidators = _get(signingKeysStats, TOTAL_EXITED_KEYS_COUNT_OFFSET);   // 获取已退出验证者数量
            uint256 totalDepositedValidators = _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET); // 获取已存款验证者数量

            uint256 activeValidatorsCount = totalDepositedValidators - totalExitedValidators;  // 计算活跃验证者数量
            totalActiveValidatorsCount += activeValidatorsCount;  // 累加到总活跃验证者数量

            recipients[idx] = _nodeOperators[operatorId].rewardAddress;  // 设置奖励接收地址
            amounts[idx] = activeValidatorsCount;        // 暂时将活跃验证者数量存储在代币数量中
            penalized[idx] = isOperatorPenalized(operatorId);  // 检查运营商是否被惩罚
            ++idx;  // 增加数组索引
        }

        if (totalActiveValidatorsCount == 0) return (recipients, amounts, penalized);  // 如果没有活跃验证者，直接返回

        // 第二轮循环：根据活跃验证者比例计算实际奖励代币数量
        for (idx = 0; idx < activeCount; ++idx) {
            // 按比例分配奖励：(运营商活跃验证者数量 / 总活跃验证者数量) * 总奖励代币数量
            amounts[idx] = (amounts[idx] * _totalRewardAmount) / totalActiveValidatorsCount;
        }

        return (recipients, amounts, penalized);  // 返回奖励分配结果
    }

    /// @notice 获取存款数据，供StakingRouter用于向以太坊存款合约存款
    /// @param _depositsCount 要进行的存款数量
    /// @return publicKeys 连接的公钥验证者密钥批次
    /// @return depositSignatures 返回公钥的连接存款签名批次
    function obtainDepositData(
        uint256 _depositsCount,
        bytes calldata /* _depositCalldata */
    ) external onlyRole(STAKING_ROUTER_ROLE) returns (bytes memory publicKeys, bytes memory depositSignatures) { 
        if (_depositsCount == 0) return (new bytes(0), new bytes(0));  // 如果存款数量为0，返回空字节数组

        // 获取签名密钥分配数据，包括分配的密钥数量和运营商分配信息
        (
            uint256 allocatedKeysCount,              // 实际分配的密钥数量
            uint256[] memory nodeOperatorIds,        // 参与分配的运营商ID数组
            uint256[] memory activeKeysCountAfterAllocation  // 分配后各运营商的活跃密钥数量
        ) = _getSigningKeysAllocationData(_depositsCount);

        // 验证分配的密钥数量是否等于请求的存款数量
        require(allocatedKeysCount == _depositsCount, "INVALID_ALLOCATED_KEYS_COUNT");

        // 加载分配的签名密钥数据
        (publicKeys, depositSignatures) = _loadAllocatedSigningKeys(
            allocatedKeysCount,
            nodeOperatorIds,
            activeKeysCountAfterAllocation
        );
        _increaseValidatorsKeysNonce();
    }

    /// @notice 返回质押模块的类型
    function getType() external view returns (bytes32) {
        return moduleType;  
    }

    /// @notice 获取质押模块摘要
    function getStakingModuleSummary()
        external
        view
        returns (uint256 totalExitedValidators, uint256 totalDepositedValidators, uint256 depositableValidatorsCount)
    {
        Packed64x4 memory summarySigningKeysStats = _loadSummarySigningKeysStats();  // 加载汇总签名密钥统计信息
        totalExitedValidators = _get(summarySigningKeysStats, SUMMARY_EXITED_KEYS_COUNT_OFFSET);      // 获取总已退出验证者数量
        totalDepositedValidators = _get(summarySigningKeysStats, SUMMARY_DEPOSITED_KEYS_COUNT_OFFSET); // 获取总已存款验证者数量
        // 可存款验证者数量 = 最大验证者数量 - 已存款验证者数量
        depositableValidatorsCount = _get(summarySigningKeysStats, SUMMARY_MAX_VALIDATORS_COUNT_OFFSET) - totalDepositedValidators;
    }

    /// @notice 获取节点运营商摘要
    function getNodeOperatorSummary(uint256 _nodeOperatorId)
        external
        view
        onlyExistedNodeOperator(_nodeOperatorId)
        returns (
            uint256 targetLimitMode,
            uint256 targetValidatorsCount,
            uint256 stuckValidatorsCount,
            uint256 refundedValidatorsCount,
            uint256 stuckPenaltyEndTimestamp,
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            uint256 depositableValidatorsCount
        )
    {

        Packed64x4 memory operatorTargetStats = _loadOperatorTargetValidatorsStats(_nodeOperatorId);   // 加载运营商目标验证者统计
        Packed64x4 memory stuckPenaltyStats = _loadOperatorStuckPenaltyStats(_nodeOperatorId);        // 加载运营商卡住惩罚统计

        targetLimitMode = _get(operatorTargetStats, TARGET_LIMIT_MODE_OFFSET);            // 获取目标限制模式
        targetValidatorsCount = _get(operatorTargetStats, TARGET_VALIDATORS_COUNT_OFFSET); // 获取目标验证者数量
        stuckValidatorsCount = _get(stuckPenaltyStats, STUCK_VALIDATORS_COUNT_OFFSET);     // 获取卡住验证者数量
        refundedValidatorsCount = _get(stuckPenaltyStats, REFUNDED_VALIDATORS_COUNT_OFFSET); // 获取退款验证者数量
        stuckPenaltyEndTimestamp = _get(stuckPenaltyStats, STUCK_PENALTY_END_TIMESTAMP_OFFSET); // 获取卡住惩罚结束时间戳

        // 获取运营商验证者摘要信息
        (totalExitedValidators, totalDepositedValidators, depositableValidatorsCount) =
            _getNodeOperatorValidatorsSummary(_nodeOperatorId);
    }

    /// @notice 返回节点运营商总数
    function getNodeOperatorsCount() public view returns (uint256) {
        return totalOperatorsCount;  // 返回存储的总运营商数量
    }

    /// @notice 返回活跃节点运营商数量
    function getActiveNodeOperatorsCount() public view returns (uint256) {
        return activeOperatorsCount;  // 返回存储的活跃运营商数量
    }

    /// @notice 返回给定id的节点运营商是否活跃
    function getNodeOperatorIsActive(uint256 _nodeOperatorId) public view returns (bool) {
        return _nodeOperators[_nodeOperatorId].active;  // 返回运营商的活跃状态
    }

    /// @notice 检查运营商是否被惩罚
    function isOperatorPenalized(uint256 _nodeOperatorId) public view returns (bool) {
        Packed64x4 memory stuckPenaltyStats = _loadOperatorStuckPenaltyStats(_nodeOperatorId);  // 加载惩罚统计信息
        return _isOperatorPenalized(stuckPenaltyStats);  // 调用内部函数检查惩罚状态
    }

    /// @notice 检查运营商惩罚是否已清除
    function isOperatorPenaltyCleared(uint256 _nodeOperatorId) public view returns (bool) {
        Packed64x4 memory stuckPenaltyStats = _loadOperatorStuckPenaltyStats(_nodeOperatorId);  // 加载惩罚统计信息
        // 如果运营商未被惩罚且惩罚结束时间戳为0，则惩罚已清除
        return !_isOperatorPenalized(stuckPenaltyStats) && _get(stuckPenaltyStats, STUCK_PENALTY_END_TIMESTAMP_OFFSET) == 0;
    }

    /// @notice 清除节点运营商惩罚
    // 此方法一般时运营商自己的去调用解除自身的惩罚
    function clearNodeOperatorPenalty(uint256 _nodeOperatorId) external returns (bool) {
        Packed64x4 memory stuckPenaltyStats = _loadOperatorStuckPenaltyStats(_nodeOperatorId);  // 加载惩罚统计信息
        // 确保运营商未被惩罚但惩罚结束时间戳不为0（即惩罚期已结束但未清除）
        require(
            !_isOperatorPenalized(stuckPenaltyStats) && _get(stuckPenaltyStats, STUCK_PENALTY_END_TIMESTAMP_OFFSET) != 0,
            "CANT_CLEAR_PENALTY"
        );
        _set(stuckPenaltyStats, STUCK_PENALTY_END_TIMESTAMP_OFFSET, 0);  // 将惩罚结束时间戳设为0，清除惩罚记录
        _saveOperatorStuckPenaltyStats(_nodeOperatorId, stuckPenaltyStats);  // 保存更新后的惩罚统计
        _updateSummaryMaxValidatorsCount(_nodeOperatorId);  // 更新全局最大验证者数量统计
        _increaseValidatorsKeysNonce();  

        emit NodeOperatorPenaltyCleared(_nodeOperatorId); 
        return true; 
    }

    /// @notice 返回计数器，当发生以下任何情况时必须更改其值
    function getNonce() external view returns (uint256) {
        return keysOpIndex;  // 返回密钥操作索引，用于跟踪密钥相关变化
    }

    /// @notice 获取卡住惩罚延迟
    function getStuckPenaltyDelay() public view returns (uint256) {
        return stuckPenaltyDelay;  // 返回存储的卡住惩罚延迟时间
    }

    /// @notice 设置卡住惩罚延迟
    function setStuckPenaltyDelay(uint256 _delay) external onlyRole(MANAGE_NODE_OPERATOR_ROLE) {  // 只有管理员可以调用
        _setStuckPenaltyDelay(_delay);  // 调用内部函数设置延迟时间
    }

    /// @notice 获取当前奖励分发状态
    function getRewardDistributionState() public view returns (RewardDistributionState) {
        return rewardDistributionState;  // 返回当前的奖励分发状态
    }

    /// @notice 返回节点运营商的总签名密钥数量
    /// @param _nodeOperatorId 节点运营商ID
    /// @return 总签名密钥数量
    function getTotalSigningKeyCount(uint256 _nodeOperatorId) 
        external 
        view 
        onlyExistedNodeOperator(_nodeOperatorId)  
        returns (uint256) 
    {
        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);  // 加载签名密钥统计
        return _get(signingKeysStats, TOTAL_KEYS_COUNT_OFFSET);  // 返回总密钥数量
    }

    /// @notice 返回节点运营商的可用签名密钥数量
    /// @param _nodeOperatorId 节点运营商ID
    /// @return 可用签名密钥数量（总数量 - 已存款数量）
    function getUnusedSigningKeyCount(uint256 _nodeOperatorId) 
        external 
        view 
        onlyExistedNodeOperator(_nodeOperatorId) 
        returns (uint256) 
    {
        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);  // 加载签名密钥统计
        uint256 totalKeys = _get(signingKeysStats, TOTAL_KEYS_COUNT_OFFSET);           // 获取总密钥数量
        uint256 depositedKeys = _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET);  // 获取已存款密钥数量
        return totalKeys - depositedKeys;  // 返回未使用的密钥数量
    }

    /// @notice 返回从`_offset`开始的最多`_limit`个节点运营商ID
    /// @param _offset 起始偏移量
    /// @param _limit 返回的最大数量
    /// @return nodeOperatorIds 节点运营商ID数组
    function getNodeOperatorIds(uint256 _offset, uint256 _limit)
        external
        view
        returns (uint256[] memory nodeOperatorIds)
    {
        uint256 nodeOperatorsCount = getNodeOperatorsCount();  // 获取总运营商数量
        
        // 如果偏移量超出范围或限制为0，返回空数组
        if (_offset >= nodeOperatorsCount || _limit == 0) {
            return new uint256[](0);
        }
        
        // 计算实际返回的数量：限制值和剩余可用数量的较小值
        uint256 actualLimit = Math.min(_limit, nodeOperatorsCount - _offset);
        nodeOperatorIds = new uint256[](actualLimit);
        
        // 填充ID数组
        for (uint256 i = 0; i < actualLimit; ++i) {
            nodeOperatorIds[i] = _offset + i;
        }
    }

    //
    // 内部函数
    //
    function _addSigningKeys(uint256 _nodeOperatorId, uint256 _keysCount, bytes calldata _publicKeys, bytes calldata _signatures) internal 
        onlyExistedNodeOperator(_nodeOperatorId) 
    {
        _onlyNodeOperatorManager(msg.sender, _nodeOperatorId);  // 验证调用者权限（管理员或运营商rewardAddress地址）
        _requireValidRange(_keysCount != 0 && _keysCount <= UINT64_MAX);  // 验证密钥数量有效性

        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);  // 加载运营商签名密钥统计
        uint256 totalSigningKeysCount = _get(signingKeysStats, TOTAL_KEYS_COUNT_OFFSET);      // 获取当前总密钥数量
        
        // 验证添加新密钥后不会超过uint64最大值
        _requireValidRange(totalSigningKeysCount + _keysCount <= UINT64_MAX);
        
        // 保存新的密钥和签名数据，返回更新后的总密钥数量
        totalSigningKeysCount = _saveKeysSigs(_nodeOperatorId, totalSigningKeysCount, _keysCount, _publicKeys, _signatures);

        emit TotalSigningKeysCountChanged(_nodeOperatorId, totalSigningKeysCount);  // 触发总密钥数量变更事件

        _set(signingKeysStats, TOTAL_KEYS_COUNT_OFFSET, totalSigningKeysCount);  // 更新统计中的总密钥数量
        _saveOperatorSigningKeysStats(_nodeOperatorId, signingKeysStats);        // 保存更新后的统计信息

        _increaseValidatorsKeysNonce();  // 增加密钥操作计数器
    }

    function _removeUnusedSigningKeys(uint256 _nodeOperatorId, uint256 _fromIndex, uint256 _keysCount) internal
        onlyExistedNodeOperator(_nodeOperatorId)  
    {
        _onlyNodeOperatorManager(msg.sender, _nodeOperatorId);  // 验证调用者权限

        if (_keysCount == 0) return;  // 如果删除数量为0，直接返回

        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);  // 加载签名密钥统计
        uint256 totalSigningKeysCount = _get(signingKeysStats, TOTAL_KEYS_COUNT_OFFSET);      // 获取总密钥数量
        
        // 验证删除范围的有效性：
        // 1. 起始索引必须大于等于已存款密钥数量（不能删除已使用的密钥）
        // 2. 删除范围不能超过总密钥数量
        _requireValidRange(
            _fromIndex >= _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET) &&
            _fromIndex + _keysCount <= totalSigningKeysCount
        );

        // 删除指定范围的密钥和签名，返回更新后的总密钥数量
        totalSigningKeysCount = _removeKeysSigs(_nodeOperatorId, _fromIndex, _keysCount, totalSigningKeysCount);
        _set(signingKeysStats, TOTAL_KEYS_COUNT_OFFSET, totalSigningKeysCount);           // 更新总密钥数量
        emit TotalSigningKeysCountChanged(_nodeOperatorId, totalSigningKeysCount);       // 触发总密钥数量变更事件

        uint256 vettedSigningKeysCount = _get(signingKeysStats, TOTAL_VETTED_KEYS_COUNT_OFFSET);  // 获取已审核密钥数量
        if (_fromIndex < vettedSigningKeysCount) {
            // 如果删除的密钥包含已审核的密钥，需要调整已审核密钥数量
            _set(signingKeysStats, TOTAL_VETTED_KEYS_COUNT_OFFSET, _fromIndex);  // 将审核数量设为删除起始索引
            emit VettedSigningKeysCountChanged(_nodeOperatorId, _fromIndex);     // 触发审核密钥数量变更事件
        }
        _saveOperatorSigningKeysStats(_nodeOperatorId, signingKeysStats);  // 保存更新后的统计信息

        _updateSummaryMaxValidatorsCount(_nodeOperatorId);  // 更新全局最大验证者数量统计
        _increaseValidatorsKeysNonce();                     // 增加密钥操作计数器
    }

    function _updateVettedSigningKeysCount(
        uint256 _nodeOperatorId,
        uint256 _vettedSigningKeysCount,
        bool _allowIncrease
    ) internal {
        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);       // 加载签名密钥统计
        uint256 vettedSigningKeysCountBefore = _get(signingKeysStats, TOTAL_VETTED_KEYS_COUNT_OFFSET);  // 获取更新前的审核密钥数量
        uint256 depositedSigningKeysCount = _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET);   // 获取已存款密钥数量
        uint256 totalSigningKeysCount = _get(signingKeysStats, TOTAL_KEYS_COUNT_OFFSET);                 // 获取总密钥数量

        // 计算实际的审核密钥数量：
        // 1. 不能超过总密钥数量
        // 2. 不能小于已存款密钥数量（已存款的密钥必须是已审核的）
        uint256 vettedSigningKeysCountAfter = Math.min(
            totalSigningKeysCount, Math.max(_vettedSigningKeysCount, depositedSigningKeysCount)
        );

        if (vettedSigningKeysCountAfter == vettedSigningKeysCountBefore) return;  // 如果数量没有变化，直接返回

        // 验证是否允许增加审核密钥数量
        // 考虑安全，这里被审查的密钥数量必须比之前小。实现需要增加必须显示传入_allowIncrease=true
        require(
            _allowIncrease || vettedSigningKeysCountAfter < vettedSigningKeysCountBefore,
            "VETTED_KEYS_COUNT_INCREASED"
        );

        _set(signingKeysStats, TOTAL_VETTED_KEYS_COUNT_OFFSET, vettedSigningKeysCountAfter);  // 更新审核密钥数量
        _saveOperatorSigningKeysStats(_nodeOperatorId, signingKeysStats);                    // 保存更新后的统计

        emit VettedSigningKeysCountChanged(_nodeOperatorId, vettedSigningKeysCountAfter);   
        // 由于审核数减少，总的可存款的验证者减少，所以需要调用
        _updateSummaryMaxValidatorsCount(_nodeOperatorId);                                  // 更新全局最大验证者数量统计
    }

    function _updateStuckValidatorsCount(uint256 _nodeOperatorId, uint256 _stuckValidatorsCount) internal {
        Packed64x4 memory stuckPenaltyStats = _loadOperatorStuckPenaltyStats(_nodeOperatorId);  // 加载卡住惩罚统计信息
        uint256 curStuckValidatorsCount = _get(stuckPenaltyStats, STUCK_VALIDATORS_COUNT_OFFSET);  // 获取当前卡住验证者数量
        if (_stuckValidatorsCount == curStuckValidatorsCount) return;  // 如果数量没有变化，直接返回

        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);     // 加载签名密钥统计信息
        uint256 exitedValidatorsCount = _get(signingKeysStats, TOTAL_EXITED_KEYS_COUNT_OFFSET);   // 获取已退出验证者数量
        uint256 depositedValidatorsCount = _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET);  // 获取已存款验证者数量

        // 验证卡住验证者数量不能超过活跃验证者数量（已存款 - 已退出）
        _requireValidRange(_stuckValidatorsCount <= depositedValidatorsCount - exitedValidatorsCount);

        uint256 curRefundedValidatorsCount = _get(stuckPenaltyStats, REFUNDED_VALIDATORS_COUNT_OFFSET);  // 获取当前退款验证者数量
        // 如果新的卡住数量小于等于退款数量，且之前卡住数量大于退款数量，则设置惩罚结束时间
        // 说明运营商情况在变好，开启运营商的惩罚倒计时，否则一直处于惩罚状态，没有倒计时
        if (_stuckValidatorsCount <= curRefundedValidatorsCount && curStuckValidatorsCount > curRefundedValidatorsCount) {
            _set(stuckPenaltyStats, STUCK_PENALTY_END_TIMESTAMP_OFFSET, block.timestamp + getStuckPenaltyDelay());  // 设置惩罚结束时间戳
        }

        _set(stuckPenaltyStats, STUCK_VALIDATORS_COUNT_OFFSET, _stuckValidatorsCount);  // 更新卡住验证者数量
        _saveOperatorStuckPenaltyStats(_nodeOperatorId, stuckPenaltyStats);            // 保存更新后的惩罚统计
        emit StuckPenaltyStateChanged(
            _nodeOperatorId,
            _stuckValidatorsCount,
            curRefundedValidatorsCount,
            _get(stuckPenaltyStats, STUCK_PENALTY_END_TIMESTAMP_OFFSET)
        );  

        // 由于预言机报告strucKeys > refundedKeys，运营商被惩罚，新的maxValidators降级，所以需要调用
        _updateSummaryMaxValidatorsCount(_nodeOperatorId);  // 更新全局最大验证者数量统计
    }

    function _updateExitedValidatorsCount(uint256 _nodeOperatorId, uint256 _exitedValidatorsCount, bool _allowDecrease) internal {
        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);  // 加载签名密钥统计信息
        uint256 oldExitedValidatorsCount = _get(signingKeysStats, TOTAL_EXITED_KEYS_COUNT_OFFSET);  // 获取原有已退出验证者数量
        if (_exitedValidatorsCount == oldExitedValidatorsCount) return;  // 如果数量没有变化，直接返回
        
        // 验证是否允许减少已退出验证者数量（通常不允许，因为已退出状态是不可逆的）
        require(
            _allowDecrease || _exitedValidatorsCount > oldExitedValidatorsCount,
            "EXITED_VALIDATORS_COUNT_DECREASED"
        );
        
        uint256 depositedValidatorsCount = _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET);  // 获取已存款验证者数量
        uint256 stuckValidatorsCount = _get(_loadOperatorStuckPenaltyStats(_nodeOperatorId), STUCK_VALIDATORS_COUNT_OFFSET);  // 获取卡住验证者数量

        // 验证已退出验证者数量不能超过（已存款数量 - 卡住数量）
        _requireValidRange(_exitedValidatorsCount <= depositedValidatorsCount - stuckValidatorsCount);

        _set(signingKeysStats, TOTAL_EXITED_KEYS_COUNT_OFFSET, _exitedValidatorsCount);  // 更新已退出验证者数量
        _saveOperatorSigningKeysStats(_nodeOperatorId, signingKeysStats);               // 保存更新后的统计
        emit ExitedSigningKeysCountChanged(_nodeOperatorId, _exitedValidatorsCount);  

        Packed64x4 memory summarySigningKeysStats = _loadSummarySigningKeysStats();     // 加载汇总统计信息
        uint256 exitedValidatorsAbsDiff = Math.absDiff(_exitedValidatorsCount, oldExitedValidatorsCount);  // 计算变化的绝对值
        if (_exitedValidatorsCount > oldExitedValidatorsCount) {
            // 如果已退出数量增加，增加汇总统计
            _add(summarySigningKeysStats, SUMMARY_EXITED_KEYS_COUNT_OFFSET, exitedValidatorsAbsDiff);
        } else {
            // 如果已退出数量减少，减少汇总统计
            _sub(summarySigningKeysStats, SUMMARY_EXITED_KEYS_COUNT_OFFSET, exitedValidatorsAbsDiff);
        }
        _saveSummarySigningKeysStats(summarySigningKeysStats);  // 保存更新后的汇总统计
        // 有新的验证者退出，由于退出的验证者也会被保存，所以maxValidators需要增加，因此需要调用
        _updateSummaryMaxValidatorsCount(_nodeOperatorId);      // 更新全局最大验证者数量统计
    }

    function _updateRefundValidatorsKeysCount(uint256 _nodeOperatorId, uint256 _refundedValidatorsCount) internal {
        Packed64x4 memory stuckPenaltyStats = _loadOperatorStuckPenaltyStats(_nodeOperatorId);  // 加载卡住惩罚统计信息
        uint256 curRefundedValidatorsCount = _get(stuckPenaltyStats, REFUNDED_VALIDATORS_COUNT_OFFSET);  // 获取当前退款验证者数量
        if (_refundedValidatorsCount == curRefundedValidatorsCount) return;  // 如果数量没有变化，直接返回

        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);  // 加载签名密钥统计信息
        // 验证退款验证者数量不能超过已存款验证者数量
        _requireValidRange(_refundedValidatorsCount <= _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET));

        uint256 curStuckValidatorsCount = _get(stuckPenaltyStats, STUCK_VALIDATORS_COUNT_OFFSET);  // 获取当前卡住验证者数量
        // 如果退款数量大于等于卡住数量，且之前退款数量小于卡住数量，则设置惩罚结束时间
        // 说明运营商情况变好
        if (_refundedValidatorsCount >= curStuckValidatorsCount && curRefundedValidatorsCount < curStuckValidatorsCount) {
            _set(stuckPenaltyStats, STUCK_PENALTY_END_TIMESTAMP_OFFSET, block.timestamp + getStuckPenaltyDelay());  // 设置惩罚结束时间戳
        }

        _set(stuckPenaltyStats, REFUNDED_VALIDATORS_COUNT_OFFSET, _refundedValidatorsCount);  // 更新退款验证者数量
        _saveOperatorStuckPenaltyStats(_nodeOperatorId, stuckPenaltyStats);                  // 保存更新后的惩罚统计
        emit StuckPenaltyStateChanged(
            _nodeOperatorId,
            curStuckValidatorsCount,
            _refundedValidatorsCount,
            _get(stuckPenaltyStats, STUCK_PENALTY_END_TIMESTAMP_OFFSET)
        );  
        
        // 由于refund数量增加，进行惩罚倒计时，惩罚期结束需要增加验证者，所以需要调用
        _updateSummaryMaxValidatorsCount(_nodeOperatorId);  // 更新全局最大验证者数量统计
    }

    function _updateSummaryMaxValidatorsCount(uint256 _nodeOperatorId) internal {
        // 应用节点运营商限制并获取新旧最大密钥数量
        (uint256 oldMaxSigningKeysCount, uint256 newMaxSigningKeysCount) = _applyNodeOperatorLimits(_nodeOperatorId);

        if (newMaxSigningKeysCount == oldMaxSigningKeysCount) return;  // 如果数量没有变化，直接返回

        Packed64x4 memory summarySigningKeysStats = _loadSummarySigningKeysStats();  // 加载汇总签名密钥统计
        uint256 maxSigningKeysCountAbsDiff = Math.absDiff(newMaxSigningKeysCount, oldMaxSigningKeysCount);  // 计算变化的绝对值
        
        if (newMaxSigningKeysCount > oldMaxSigningKeysCount) {
            // 如果最大密钥数量增加，增加汇总统计
            _add(summarySigningKeysStats, SUMMARY_MAX_VALIDATORS_COUNT_OFFSET, maxSigningKeysCountAbsDiff);
        } else {
            // 如果最大密钥数量减少，减少汇总统计
            _sub(summarySigningKeysStats, SUMMARY_MAX_VALIDATORS_COUNT_OFFSET, maxSigningKeysCountAbsDiff);
        }
        _saveSummarySigningKeysStats(summarySigningKeysStats);  // 保存更新后的汇总统计
    }

    function _distributeRewards() internal returns (uint256 distributed) {
        IERC20 gteth = IERC20(locator.gteth());                   // 获取GTETH代币合约实例
        uint256 rewardsToDistribute = gteth.balanceOf(address(this));  // 获取本合约持有的GTETH代币余额
        if (rewardsToDistribute == 0) return 0;                  // 如果没有可分发的代币，直接返回0

        // 获取奖励分配方案：接收者地址、代币数量、惩罚状态
        (address[] memory recipients, uint256[] memory amounts, bool[] memory penalized) =
            getRewardsDistribution(rewardsToDistribute);

        uint256 toBurn;  // 需要燃烧的惩罚代币总量
        for (uint256 idx; idx < recipients.length; ++idx) {
            if (amounts[idx] < 2) continue;  // 如果代币数量小于2，跳过（避免过小的转账）
            if (penalized[idx]) {
                // 如果运营商被惩罚，减半其奖励代币数量
                amounts[idx] >>= 1;  // 右移1位相当于除以2
                toBurn += amounts[idx];  // 累加需要燃烧的代币数量
                emit NodeOperatorPenalized(recipients[idx], amounts[idx]);
            }
            gteth.safeTransfer(recipients[idx], amounts[idx]);         // 转账奖励代币给运营商
            distributed += amounts[idx];                           // 累加已分发的代币数量
            emit RewardsDistributed(recipients[idx], amounts[idx]); 
        }
        
        if (toBurn > 0) {
            // 燃烧惩罚代币
            gteth.safeTransfer(IGTETHLocator(locator).treasury(), toBurn);
        }
    }

    // Packed64x4 工具函数 - 用于操作打包的uint64值
    function _get(Packed64x4 memory _packed, uint8 _offset) internal pure returns (uint256) {
        // 从打包的uint256中提取指定偏移位置的uint64值
        // 右移(_offset * 64)位，然后与UINT64_MAX按位与，提取64位值
        return (_packed.packed >> (_offset * 64)) & UINT64_MAX;
    }

    function _set(Packed64x4 memory _packed, uint8 _offset, uint256 _value) internal pure {
        require(_value <= UINT64_MAX, "OUT_OF_RANGE");  // 确保值不超过uint64最大值
        // 创建掩码：在指定偏移位置清零64位
        uint256 mask = ~(UINT64_MAX << (_offset * 64));
        // 清除原值并设置新值：(原值 & 掩码) | (新值 << 偏移位置)
        _packed.packed = (_packed.packed & mask) | (_value << (_offset * 64));
    }

    function _add(Packed64x4 memory _packed, uint8 _offset, uint256 _value) internal pure {
        uint256 current = _get(_packed, _offset);  // 获取当前值
        _set(_packed, _offset, current + _value);  // 设置为当前值加上增量
    }

    function _sub(Packed64x4 memory _packed, uint8 _offset, uint256 _value) internal pure {
        uint256 current = _get(_packed, _offset);   // 获取当前值
        require(current >= _value, "OUT_OF_RANGE"); // 确保当前值大于等于要减去的值
        _set(_packed, _offset, current - _value);   // 设置为当前值减去减量
    }

    // 状态加载和保存函数 - 提供统一的状态访问接口
    function _loadOperatorSigningKeysStats(uint256 _nodeOperatorId) internal view returns (Packed64x4 memory) {
        return _nodeOperators[_nodeOperatorId].signingKeysStats;  // 加载运营商签名密钥统计信息
    }

    function _saveOperatorSigningKeysStats(uint256 _nodeOperatorId, Packed64x4 memory _val) internal {
        _nodeOperators[_nodeOperatorId].signingKeysStats = _val;  // 保存运营商签名密钥统计信息
    }

    function _loadOperatorTargetValidatorsStats(uint256 _nodeOperatorId) internal view returns (Packed64x4 memory) {
        return _nodeOperators[_nodeOperatorId].targetValidatorsStats;  // 加载运营商目标验证者统计信息
    }

    function _saveOperatorTargetValidatorsStats(uint256 _nodeOperatorId, Packed64x4 memory _val) internal {
        _nodeOperators[_nodeOperatorId].targetValidatorsStats = _val;  // 保存运营商目标验证者统计信息
    }

    function _loadOperatorStuckPenaltyStats(uint256 _nodeOperatorId) internal view returns (Packed64x4 memory) {
        return _nodeOperators[_nodeOperatorId].stuckPenaltyStats;  // 加载运营商卡住惩罚统计信息
    }

    function _saveOperatorStuckPenaltyStats(uint256 _nodeOperatorId, Packed64x4 memory _val) internal {
        _nodeOperators[_nodeOperatorId].stuckPenaltyStats = _val;  // 保存运营商卡住惩罚统计信息
    }

    function _loadSummarySigningKeysStats() internal view returns (Packed64x4 memory) {
        return _nodeOperatorSummary.summarySigningKeysStats;  // 加载全局汇总签名密钥统计信息
    }

    function _saveSummarySigningKeysStats(Packed64x4 memory _val) internal {
        _nodeOperatorSummary.summarySigningKeysStats = _val;  // 保存全局汇总签名密钥统计信息
    }

    function _setStuckPenaltyDelay(uint256 _delay) internal {
        _requireValidRange(_delay <= MAX_STUCK_PENALTY_DELAY);  // 验证延迟时间不超过最大限制
        stuckPenaltyDelay = _delay;                             // 设置卡住惩罚延迟时间
        emit StuckPenaltyDelayChanged(_delay);                  // 触发卡住惩罚延迟变更事件
    }

    function _applyNodeOperatorLimits(uint256 _nodeOperatorId) internal returns (uint256 oldMaxSigningKeysCount, uint256 newMaxSigningKeysCount) {
        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);      // 加载签名密钥统计
        Packed64x4 memory operatorTargetStats = _loadOperatorTargetValidatorsStats(_nodeOperatorId); // 加载目标验证者统计

        uint256 depositedSigningKeysCount = _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET); // 获取已存款密钥数量

        // 乐观地设置最大验证者数量等于已审核验证者数量，因为大多数时候验证者不会受到惩罚
        newMaxSigningKeysCount = _get(signingKeysStats, TOTAL_VETTED_KEYS_COUNT_OFFSET);

        if (!isOperatorPenaltyCleared(_nodeOperatorId)) {
            // 当节点运营商被惩罚时，将其可存款验证者数量设为已存款数量
            newMaxSigningKeysCount = depositedSigningKeysCount;
        } else if (_get(operatorTargetStats, TARGET_LIMIT_MODE_OFFSET) != 0) {
            // 当目标限制激活且节点运营商未被惩罚时应用目标限制
            newMaxSigningKeysCount = Math.max(
                // 最大验证者数量不能少于已存款验证者数量
                // 即使目标限制少于当前活跃验证者数量
                depositedSigningKeysCount,
                Math.min(
                    // 最大验证者数量不能大于已审核验证者数量
                    newMaxSigningKeysCount,
                    // 已退出验证者数量 + 目标验证者数量（这样计算的原因是退出的验证者密钥也是会被合约保存下来的，所以让最大的验证者需要进行相加计算）
                    _get(signingKeysStats, TOTAL_EXITED_KEYS_COUNT_OFFSET)
                        + _get(operatorTargetStats, TARGET_VALIDATORS_COUNT_OFFSET)
                )
            );
        }

        oldMaxSigningKeysCount = _get(operatorTargetStats, MAX_VALIDATORS_COUNT_OFFSET); // 获取旧的最大密钥数量
        if (oldMaxSigningKeysCount != newMaxSigningKeysCount) {
            // 如果数量发生变化，更新并保存新的最大验证者数量
            _set(operatorTargetStats, MAX_VALIDATORS_COUNT_OFFSET, newMaxSigningKeysCount);
            _saveOperatorTargetValidatorsStats(_nodeOperatorId, operatorTargetStats);
        }
    }

    function _getNodeOperatorValidatorsSummary(uint256 _nodeOperatorId) internal view returns (
        uint256 totalExitedValidators,
        uint256 totalDepositedValidators,
        uint256 depositableValidatorsCount
    ) {
        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);
        Packed64x4 memory operatorTargetStats = _loadOperatorTargetValidatorsStats(_nodeOperatorId);
        
        totalExitedValidators = _get(signingKeysStats, TOTAL_EXITED_KEYS_COUNT_OFFSET);
        totalDepositedValidators = _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET);
        depositableValidatorsCount = _get(operatorTargetStats, MAX_VALIDATORS_COUNT_OFFSET) - totalDepositedValidators;
    }

    // 权限检查函数
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return super.hasRole(role, account);
    }

    // 签名密钥存储函数 - 验证并存储密钥和签名数据
    function _saveKeysSigs(uint256 _nodeOperatorId, uint256 _startIndex, uint256 _keysCount, bytes calldata _publicKeys, bytes calldata _signatures) internal returns (uint256) {
        // 验证公钥数据长度：每个公钥48字节
        require(_publicKeys.length == _keysCount * 48, "INVALID_PUBKEY_LENGTH");
        // 验证签名数据长度：每个签名96字节
        require(_signatures.length == _keysCount * 96, "INVALID_SIG_LENGTH");

        // 逐个存储密钥和签名
        for (uint256 i = 0; i < _keysCount; i++) {
            uint256 keyIndex = _startIndex + i;  // 计算密钥在运营商中的索引
            
            // 提取单个公钥数据（48字节）
            bytes memory pubkey = _publicKeys[i*48:(i+1)*48];
            // 提取单个签名数据（96字节）
            bytes memory signature = _signatures[i*96:(i+1)*96];
            
            // 验证公钥不为空
            require(pubkey.length == 48, "INVALID_PUBKEY_SIZE");
            // 验证签名不为空
            require(signature.length == 96, "INVALID_SIG_SIZE");
            // 验证公钥是否已被使用
            require(pubkeyUsed[keccak256(pubkey)] == false, "PUBKEY_ALREADY_USED");
            
            // 存储公钥和签名到映射中
            signingKeys[_nodeOperatorId][keyIndex] = pubkey;
            signatures[_nodeOperatorId][keyIndex] = signature;
            // 记录公钥使用状态
            pubkeyUsed[keccak256(pubkey)] = true;
        }
        
        // 返回更新后的总密钥数量
        return _startIndex + _keysCount;
    }

    function _removeKeysSigs(uint256 _nodeOperatorId, uint256 _fromIndex, uint256 _keysCount, uint256 _totalKeys) internal returns (uint256) {
        // 验证删除范围的有效性
        require(_fromIndex + _keysCount <= _totalKeys, "INVALID_REMOVE_RANGE");
        
        // 如果要删除的是末尾的密钥，直接删除即可，无需移动
        if (_fromIndex + _keysCount == _totalKeys) {
            // 删除末尾的密钥：直接清空存储
            for (uint256 i = _fromIndex; i < _totalKeys; i++) {
                delete signingKeys[_nodeOperatorId][i];
                delete signatures[_nodeOperatorId][i];
            }
        } else {
            // 删除中间的密钥：需要将后面的密钥向前移动填补空隙
            uint256 moveCount = _totalKeys - _fromIndex - _keysCount;  // 需要移动的密钥数量
            
            // 将后续密钥向前移动
            for (uint256 i = 0; i < moveCount; i++) {
                signingKeys[_nodeOperatorId][_fromIndex + i] = signingKeys[_nodeOperatorId][_fromIndex + _keysCount + i];
                signatures[_nodeOperatorId][_fromIndex + i] = signatures[_nodeOperatorId][_fromIndex + _keysCount + i];
            }
            
            // 清空末尾被移动的密钥位置
            for (uint256 i = _totalKeys - _keysCount; i < _totalKeys; i++) {
                delete signingKeys[_nodeOperatorId][i];
                delete signatures[_nodeOperatorId][i];
            }
        }
        
        // 返回删除后的总密钥数量
        return _totalKeys - _keysCount;
    }

    function _initKeysSigsBuf(uint256 _count) internal pure returns (bytes memory, bytes memory) {
        return (new bytes(_count * 48), new bytes(_count * 96));
    }

    function _loadKeysSigs(uint256 _nodeOperatorId, uint256 _offset, uint256 _limit, bytes memory _pubkeys, bytes memory _signatures, uint256 _bufferOffset) internal view {
        // 验证缓冲区大小是否足够
        require(_pubkeys.length >= (_bufferOffset + _limit) * 48, "PUBKEYS_BUFFER_TOO_SMALL");
        require(_signatures.length >= (_bufferOffset + _limit) * 96, "SIGNATURES_BUFFER_TOO_SMALL");
        
        // 逐个加载密钥和签名数据到缓冲区
        for (uint256 i = 0; i < _limit; i++) {
            bytes memory key = signingKeys[_nodeOperatorId][_offset + i];    // 从存储中读取公钥
            bytes memory sig = signatures[_nodeOperatorId][_offset + i];     // 从存储中读取签名
            
            // 验证密钥数据存在且长度正确
            require(key.length == 48, "INVALID_STORED_KEY_LENGTH");
            require(sig.length == 96, "INVALID_STORED_SIG_LENGTH");
            
            // 计算在缓冲区中的位置
            uint256 keyBufferIndex = (_bufferOffset + i) * 48;
            uint256 sigBufferIndex = (_bufferOffset + i) * 96;
            
            //Solidity 从 0.8 开始对 bytes 的这种用法有限制，只有在 memory 中，并且字节数组长度已经初始化的前提下，才可以对其进行类似数组的赋值。
            // 将密钥数据复制到公钥缓冲区
            for (uint256 j = 0; j < 48; j++) {
                _pubkeys[keyBufferIndex + j] = key[j];
            }
            
            // 将签名数据复制到签名缓冲区
            for (uint256 j = 0; j < 96; j++) {
                _signatures[sigBufferIndex + j] = sig[j];
            }
        }
    }

    function _loadAllocatedSigningKeys(uint256 _allocatedKeysCount, uint256[] memory _nodeOperatorIds, uint256[] memory _activeKeysCountAfterAllocation) internal returns (bytes memory pubkeys, bytes memory depositSignatures) {
        // 初始化返回的公钥和签名数据缓冲区
        (pubkeys, depositSignatures) = _initKeysSigsBuf(_allocatedKeysCount);

        uint256 loadedKeysCount = 0;                    // 已加载的密钥数量计数器
        uint256 depositedSigningKeysCountBefore;        // 分配前的已存款密钥数量
        uint256 depositedSigningKeysCountAfter;         // 分配后的已存款密钥数量
        uint256 keysCount;                              // 当前运营商需要加载的密钥数量
        Packed64x4 memory signingKeysStats;             // 签名密钥统计信息

        // 遍历所有参与分配的运营商
        for (uint256 i; i < _nodeOperatorIds.length; ++i) {
            signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorIds[i]); // 加载运营商统计信息
            depositedSigningKeysCountBefore = _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET); // 获取分配前已存款数量
            
            // 计算分配后的已存款密钥数量：已退出数量 + 分配后活跃数量
            depositedSigningKeysCountAfter = _get(signingKeysStats, TOTAL_EXITED_KEYS_COUNT_OFFSET) + _activeKeysCountAfterAllocation[i];

            // 如果分配后数量与分配前数量相同，跳过该运营商
            if (depositedSigningKeysCountAfter == depositedSigningKeysCountBefore) continue;

            // 验证分配后数量大于分配前数量（防止溢出）
            require(depositedSigningKeysCountAfter > depositedSigningKeysCountBefore, "INVALID_ALLOCATION_RESULT");

            // 计算该运营商需要加载的密钥数量
            keysCount = depositedSigningKeysCountAfter - depositedSigningKeysCountBefore;
            
            // 从存储中加载密钥和签名到缓冲区
            _loadKeysSigs(_nodeOperatorIds[i], depositedSigningKeysCountBefore, keysCount, pubkeys, depositSignatures, loadedKeysCount);
            loadedKeysCount += keysCount; // 更新已加载数量

            // 触发已存款密钥数量变更事件
            emit DepositedSigningKeysCountChanged(_nodeOperatorIds[i], depositedSigningKeysCountAfter);
            
            // 更新运营商的已存款密钥数量统计
            _set(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET, depositedSigningKeysCountAfter);
            _saveOperatorSigningKeysStats(_nodeOperatorIds[i], signingKeysStats);
            
            // 更新运营商的最大验证者数量限制
            _updateSummaryMaxValidatorsCount(_nodeOperatorIds[i]);
        }

        // 验证实际加载的密钥数量与预期相符
        require(loadedKeysCount == _allocatedKeysCount, "KEYS_COUNT_MISMATCH");

        // 更新全局汇总统计：增加已存款密钥数量
        Packed64x4 memory summarySigningKeysStats = _loadSummarySigningKeysStats();
        _add(summarySigningKeysStats, SUMMARY_DEPOSITED_KEYS_COUNT_OFFSET, loadedKeysCount);
        _saveSummarySigningKeysStats(summarySigningKeysStats);
    }

    function _getSigningKeysAllocationData(uint256 _keysCount) internal view returns (uint256 allocatedKeysCount, uint256[] memory nodeOperatorIds, uint256[] memory activeKeyCountsAfterAllocation) {
        uint256 activeNodeOperatorsCount = getActiveNodeOperatorsCount();  // 获取活跃运营商数量
        nodeOperatorIds = new uint256[](activeNodeOperatorsCount);         // 初始化运营商ID数组
        activeKeyCountsAfterAllocation = new uint256[](activeNodeOperatorsCount); // 初始化分配后活跃密钥数组
        uint256[] memory activeKeysCapacities = new uint256[](activeNodeOperatorsCount); // 运营商容量数组

        uint256 activeNodeOperatorIndex;           // 活跃运营商索引计数器
        uint256 nodeOperatorsCount = getNodeOperatorsCount(); // 总运营商数量
        uint256 maxSigningKeysCount;               // 运营商最大密钥数量
        uint256 depositedSigningKeysCount;         // 运营商已存款密钥数量
        uint256 exitedSigningKeysCount;            // 运营商已退出密钥数量

        // 遍历所有节点运营商，收集活跃运营商的信息
        for (uint256 nodeOperatorId; nodeOperatorId < nodeOperatorsCount; ++nodeOperatorId) {
            // 获取运营商的验证者统计信息
            (exitedSigningKeysCount, depositedSigningKeysCount, maxSigningKeysCount) = _getNodeOperator(nodeOperatorId);

            // 跳过没有可用签名密钥的节点运营商（已达到最大限制）
            if (depositedSigningKeysCount == maxSigningKeysCount) continue;

            // 记录活跃运营商信息
            nodeOperatorIds[activeNodeOperatorIndex] = nodeOperatorId;
            // 当前活跃验证者数量 = 已存款数量 - 已退出数量
            activeKeyCountsAfterAllocation[activeNodeOperatorIndex] = depositedSigningKeysCount - exitedSigningKeysCount;
            // 运营商容量 = 最大数量 - 已退出数量
            activeKeysCapacities[activeNodeOperatorIndex] = maxSigningKeysCount - exitedSigningKeysCount;
            ++activeNodeOperatorIndex;
        }

        // 如果没有活跃的运营商，返回空结果
        if (activeNodeOperatorIndex == 0) return (0, new uint256[](0), new uint256[](0));

        // 如果活跃运营商数量少于初始化的数组大小，需要缩减数组长度
        if (activeNodeOperatorIndex < activeNodeOperatorsCount) {
            assembly {
                mstore(nodeOperatorIds, activeNodeOperatorIndex)
                mstore(activeKeyCountsAfterAllocation, activeNodeOperatorIndex)
                mstore(activeKeysCapacities, activeNodeOperatorIndex)
            }
        }

        // 使用最小优先分配策略分配密钥
        (allocatedKeysCount, activeKeyCountsAfterAllocation) = _allocateKeys(
            activeKeyCountsAfterAllocation, 
            activeKeysCapacities, 
            _keysCount
        );

        // 方法不会分配超过请求数量的密钥
        require(_keysCount >= allocatedKeysCount, "OVER_ALLOCATED");
    }

    function _checkReportPayload(uint256 idsLength, uint256 countsLength) internal pure returns (uint256 count) {
        count = idsLength / 8;
        require(countsLength / 16 == count && idsLength % 8 == 0 && countsLength % 16 == 0, "INVALID_REPORT_DATA");
    }

    function _extractNodeOperatorId(bytes calldata _data, uint256 _index) internal pure returns (uint256) {
        return uint256(bytes32(_data[_index*8:(_index+1)*8]) >> 192);
    }

    function _extractVettedKeysCount(bytes calldata _data, uint256 _index) internal pure returns (uint256) {
        return uint256(bytes32(_data[_index*16:(_index+1)*16]) >> 128);
    }

    function _extractStuckValidatorsCount(bytes calldata _data, uint256 _index) internal pure returns (uint256) {
        return uint256(bytes32(_data[_index*16:(_index+1)*16]) >> 128);
    }

    function _extractExitedValidatorsCount(bytes calldata _data, uint256 _index) internal pure returns (uint256) {
        return uint256(bytes32(_data[_index*16:(_index+1)*16]) >> 128);
    }

    // 工具函数 - 提供通用的验证和检查功能
    function _requireAuth(bool _pass) internal pure {
        require(_pass, "APP_AUTH_FAILED");  // 验证权限检查，失败时抛出授权失败错误
    }

    function _requireNotSameValue(bool _pass) internal pure {
        require(_pass, "VALUE_IS_THE_SAME");  // 验证值是否不同，相同时抛出错误
    }

    function _requireValidRange(bool _pass) internal pure {
        require(_pass, "OUT_OF_RANGE");  // 验证数值范围，超出范围时抛出错误
    }

    function _onlyNonZeroAddress(address _a) internal pure {
        require(_a != address(0), "ZERO_ADDRESS");  // 验证地址不是零地址
    }

    function _isOperatorPenalized(Packed64x4 memory stuckPenaltyStats) internal view returns (bool) {
        // 检查运营商是否被惩罚的逻辑：
        // 1. 退款验证者数量小于卡住验证者数量，或者
        // 2. 当前时间仍在惩罚结束时间戳之前
        return _get(stuckPenaltyStats, REFUNDED_VALIDATORS_COUNT_OFFSET) < _get(stuckPenaltyStats, STUCK_VALIDATORS_COUNT_OFFSET)
            || block.timestamp <= _get(stuckPenaltyStats, STUCK_PENALTY_END_TIMESTAMP_OFFSET);
    }

    function _onlyNodeOperatorManager(address _sender, uint256 _nodeOperatorId) internal view {
        bool isRewardAddress = _sender == _nodeOperators[_nodeOperatorId].rewardAddress;  // 检查是否为运营商的奖励地址
        bool isActive = _nodeOperators[_nodeOperatorId].active;                           // 检查运营商是否活跃
        // 验证权限：必须是（活跃运营商的奖励地址）或（拥有MANAGE_SIGNING_KEYS角色）
        _requireAuth((isRewardAddress && isActive) || hasRole(MANAGE_SIGNING_KEYS, _sender));
    }

    function _increaseValidatorsKeysNonce() internal {
        keysOpIndex += 1;                           // 增加密钥操作索引
        emit KeysOpIndexSet(keysOpIndex);           // 触发密钥操作索引设置事件
        emit NonceChanged(keysOpIndex);             // 触发随机数变更事件
    }

    function _updateRewardDistributionState(RewardDistributionState _state) internal {
        rewardDistributionState = _state;           // 更新奖励分发状态
        emit RewardDistributionStateChanged(_state); // 触发奖励分发状态变更事件
    }

    function _getNodeOperator(uint256 _nodeOperatorId)
        internal
        view
        returns (uint256 exitedSigningKeysCount, uint256 depositedSigningKeysCount, uint256 maxSigningKeysCount)
    {
        Packed64x4 memory signingKeysStats = _loadOperatorSigningKeysStats(_nodeOperatorId);    // 加载签名密钥统计
        Packed64x4 memory operatorTargetStats = _loadOperatorTargetValidatorsStats(_nodeOperatorId); // 加载目标验证者统计

        exitedSigningKeysCount = _get(signingKeysStats, TOTAL_EXITED_KEYS_COUNT_OFFSET);       // 获取已退出密钥数量
        depositedSigningKeysCount = _get(signingKeysStats, TOTAL_DEPOSITED_KEYS_COUNT_OFFSET); // 获取已存款密钥数量
        maxSigningKeysCount = _get(operatorTargetStats, MAX_VALIDATORS_COUNT_OFFSET);          // 获取最大密钥数量

        // 验证数据边界不变性，避免在调用方法中使用SafeMath
        require(maxSigningKeysCount >= depositedSigningKeysCount && depositedSigningKeysCount >= exitedSigningKeysCount, "INVALID_OPERATOR_DATA");
    }

    /// @notice 最小优先分配策略 - 优先分配给验证者数量最少的运营商
    /// @param _currentAllocations 当前各运营商的分配数量
    /// @param _capacities 各运营商的最大容量
    /// @param _allocationSize 需要分配的总数量
    /// @return allocated 实际分配的数量
    /// @return newAllocations 分配后各运营商的新分配数量
    function _allocateKeys(
        uint256[] memory _currentAllocations,
        uint256[] memory _capacities,
        uint256 _allocationSize
    ) internal pure returns (uint256 allocated, uint256[] memory newAllocations) {
        require(_currentAllocations.length == _capacities.length, "LENGTH_MISMATCH");
        
        newAllocations = new uint256[](_currentAllocations.length);
        // 复制当前分配数量到新数组
        for (uint256 i = 0; i < _currentAllocations.length; i++) {
            newAllocations[i] = _currentAllocations[i];
        }
        
        allocated = 0;
        
        // 使用最小优先策略：每次给当前分配数量最少的运营商分配一个验证者
        while (allocated < _allocationSize) {
            uint256 minAllocation = type(uint256).max; // 当前最小分配数量
            uint256 minIndex = type(uint256).max;      // 最小分配数量的运营商索引
            
            // 找到当前分配数量最少且还有容量的运营商
            for (uint256 i = 0; i < newAllocations.length; i++) {
                // 跳过已达到容量上限的运营商
                if (newAllocations[i] >= _capacities[i]) continue;
                
                // 找到分配数量最少的运营商
                if (newAllocations[i] < minAllocation) {
                    minAllocation = newAllocations[i];
                    minIndex = i;
                }
            }
            
            // 如果所有运营商都已达到容量上限，退出循环
            if (minIndex == type(uint256).max) break;
            
            // 给选中的运营商分配一个验证者
            newAllocations[minIndex]++;
            allocated++;
        }
    }
}