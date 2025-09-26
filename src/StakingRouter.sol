// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./interfaces/INodeOperatorsRegistry.sol";
import "./BeaconChainDepositor.sol";

/**
 * @title StakingRouter - 质押路由合约
 * @notice 这个合约管理多个质押模块，负责ETH存款分配、验证者状态跟踪和奖励分配
 * @dev 基于OpenZeppelin库
 */
contract StakingRouter is AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, BeaconChainDepositor {
    
    /// @notice 32 ETH的存款大小（以wei为单位）
    uint256 public constant DEPOSIT_ETH_SIZE = 32 ether;
    
    /// @notice 费用精度点数，用于计算百分比（100% = 10^20）
    uint256 public constant FEE_PRECISION_POINTS = 10 ** 20;
    
    /// @notice 总基点数，用于百分比计算（100% = 10000）
    uint256 public constant TOTAL_BASIS_POINTS = 10000;
    
    /// @notice 最大支持的质押模块数量
    uint256 public constant MAX_STAKING_MODULES_COUNT = 32;
    
    /// @notice 质押模块名称的最大长度（字节）
    uint256 public constant MAX_STAKING_MODULE_NAME_LENGTH = 31;

    /// @notice 管理提取凭证的角色
    bytes32 public constant MANAGE_WITHDRAWAL_CREDENTIALS_ROLE = keccak256("MANAGE_WITHDRAWAL_CREDENTIALS_ROLE");
    
    /// @notice 管理质押模块的角色（添加、更新、状态变更）
    bytes32 public constant STAKING_MODULE_MANAGE_ROLE = keccak256("STAKING_MODULE_MANAGE_ROLE");
    
    /// @notice 报告退出验证者数量的角色
    bytes32 public constant REPORT_EXITED_VALIDATORS_ROLE = keccak256("REPORT_EXITED_VALIDATORS_ROLE");
    
    /// @notice 报告奖励铸造的角色
    bytes32 public constant REPORT_REWARDS_MINTED_ROLE = keccak256("REPORT_REWARDS_MINTED_ROLE");
    
    /// @notice 暂停/恢复合约的角色
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @notice 质押模块状态枚举
     */
    enum StakingModuleStatus {
        Active,         // 激活状态
        DepositsPaused, // 暂停存款
        Stopped         // 完全停止
    }

    /**
     * @notice 质押模块数据结构
     * @dev 存储质押模块的所有配置和状态信息
     */
    struct StakingModule {
        uint24 id;                          // 质押模块的唯一ID
        address stakingModuleAddress;       // 质押模块合约地址
        uint16 stakingModuleFee;           // 质押模块从奖励中获得的费用（基点）
        uint16 treasuryFee;                // 财库从奖励中获得的费用（基点）
        uint16 stakeShareLimit;            // 该模块可分配的最大质押份额（基点）
        uint8 status;                      // 质押模块状态
        string name;                       // 质押模块名称
        uint256 exitedValidatorsCount;     // 已退出的验证者数量
        uint16 priorityExitShareThreshold; // 优先退出份额阈值（基点）
    }

    /**
     * @notice 质押模块缓存结构
     * @dev 用于优化gas消耗的临时数据结构
     */
    struct StakingModuleCache {
        address stakingModuleAddress;       // 质押模块地址
        uint24 stakingModuleId;            // 质押模块ID
        uint16 stakingModuleFee;           // 质押模块费用
        uint16 treasuryFee;                // 财库费用
        uint16 stakeShareLimit;            // 质押份额限制
        StakingModuleStatus status;        // 模块状态
        uint256 activeValidatorsCount;     // 活跃验证者数量
        uint256 availableValidatorsCount;  // 可用验证者数量
    }

    /**
     * @notice 质押模块摘要结构
     * @dev 包含质押模块验证者的摘要信息
     */
    struct StakingModuleSummary {
        uint256 totalExitedValidators;      // 总已退出验证者数量
        uint256 totalDepositedValidators;   // 总已存款验证者数量
        uint256 depositableValidatorsCount; // 可存款验证者数量
    }

    /**
     * @notice 节点运营商摘要结构
     * @dev 包含节点运营商及其验证者的摘要信息
     */
    struct NodeOperatorSummary {
        uint256 targetLimitMode;            // 目标限制模式
        uint256 targetValidatorsCount;      // 目标验证者数量
        uint256 stuckValidatorsCount;       // 卡住验证者数量
        uint256 refundedValidatorsCount;    // 退款验证者数量
        uint256 stuckPenaltyEndTimestamp;   // 卡住惩罚结束时间戳
        uint256 totalExitedValidators;      // 总已退出验证者数量
        uint256 totalDepositedValidators;   // 总已存款验证者数量
        uint256 depositableValidatorsCount; // 可存款验证者数量
    }

    /// @notice GTETH主合约地址
    address public gteth;
    
    /// @notice 提取凭证，用于信标链提取
    bytes32 public withdrawalCredentials;
    
    /// @notice 质押模块总数
    uint256 public stakingModulesCount;
    
    /// @notice 最后添加的质押模块ID（递增计数器）
    uint256 public lastStakingModuleId;
    
    /// @notice 质押模块数据映射：索引 => 质押模块
    mapping(uint256 => StakingModule) public stakingModules;
    
    /// @notice 质押模块ID到索引的映射：模块ID => 索引+1（0表示不存在）
    mapping(uint256 => uint256) public stakingModuleIndicesOneBased;

    /// @notice 质押模块添加事件
    event StakingModuleAdded(
        uint256 indexed stakingModuleId,    // 质押模块ID
        address indexed stakingModule,      // 质押模块地址
        string name,                        // 质押模块名称
        address indexed createdBy           // 创建者地址
    );

    /// @notice 质押模块份额限制设置事件
    event StakingModuleShareLimitSet(
        uint256 indexed stakingModuleId,            // 质押模块ID
        uint256 stakeShareLimit,                    // 质押份额限制
        uint256 priorityExitShareThreshold,         // 优先退出阈值
        address indexed setBy                       // 设置者地址
    );

    /// @notice 质押模块费用设置事件
    event StakingModuleFeesSet(
        uint256 indexed stakingModuleId,    // 质押模块ID
        uint256 stakingModuleFee,           // 质押模块费用
        uint256 treasuryFee,                // 财库费用
        address indexed setBy               // 设置者地址
    );

    /// @notice 质押模块状态设置事件
    event StakingModuleStatusSet(
        uint256 indexed stakingModuleId,    // 质押模块ID
        StakingModuleStatus status,         // 新状态
        address indexed setBy               // 设置者地址
    );

    /// @notice 提取凭证设置事件
    event WithdrawalCredentialsSet(
        bytes32 withdrawalCredentials,      // 新的提取凭证
        address indexed setBy               // 设置者地址
    );

    /// @notice ETH存款事件
    event StakingRouterETHDeposited(
        uint256 indexed stakingModuleId,    // 质押模块ID
        uint256 amount                      // 存款金额
    );

    /// @notice 退出验证者报告不完整事件
    event StakingModuleExitedValidatorsIncompleteReporting(
        uint256 indexed stakingModuleId,            // 质押模块ID
        uint256 unreportedExitedValidatorsCount     // 未报告的退出验证者数量
    );

    error ZeroAddressGTETH();                       
    error ZeroAddressAdmin();                       
    error ZeroAddressStakingModule();               
    error InvalidStakeShareLimit();                 
    error InvalidFeeSum();                          
    error StakingModuleNotActive();                
    error EmptyWithdrawalsCredentials();            
    error DirectETHTransfer();                      
    error StakingModulesLimitExceeded();            
    error StakingModuleUnregistered();              
    error StakingModuleStatusTheSame();             
    error StakingModuleWrongName();                 
    error InvalidDepositsValue(uint256 etherValue, uint256 depositsCount);  
    error StakingModuleAddressExists();             
    error ArraysLengthMismatch(uint256 firstArrayLength, uint256 secondArrayLength);  
    error ExitedValidatorsCountCannotDecrease();    
    error ReportedExitedValidatorsExceedDeposited(uint256 reported, uint256 deposited);  
    error InvalidPriorityExitShareThreshold();       

    /**
     * @notice 初始化合约
     * @param _admin 管理员地址，将获得DEFAULT_ADMIN_ROLE
     * @param _gteth GTETH主合约地址
     * @param _depositContract 信标链存款合约地址
     * @param _withdrawalCredentials 初始提取凭证
     */
    function initialize(
        address _admin,
        address _gteth,
        address _depositContract,
        bytes32 _withdrawalCredentials
    ) external initializer {
        if (_admin == address(0)) revert ZeroAddressAdmin();
        if (_gteth == address(0)) revert ZeroAddressGTETH();

        // 初始化父合约
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __BeaconChainDepositor_init(_depositContract);

        // 设置管理员角色
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        // 设置各种管理角色给管理员
        _grantRole(MANAGE_WITHDRAWAL_CREDENTIALS_ROLE, _admin);
        _grantRole(STAKING_MODULE_MANAGE_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);

        // 需要给链下oracle地址设置权限
        _grantRole(REPORT_EXITED_VALIDATORS_ROLE, _admin);
        _grantRole(REPORT_REWARDS_MINTED_ROLE, _admin);

        // 初始化状态变量
        gteth = _gteth;
        withdrawalCredentials = _withdrawalCredentials;
        
        emit WithdrawalCredentialsSet(_withdrawalCredentials, msg.sender);
    }

    /// @notice 授权升级函数 - 仅允许默认管理员升级合约
    /// @param newImplementation 新的实现合约地址
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        // 空实现，权限检查在 onlyRole 修饰符中完成
    }

    /** 
     * @notice 设置GTETH合约地址
     * @param _gteth GTETH合约地址
     */
    function setGTETH(address _gteth) external onlyRole(DEFAULT_ADMIN_ROLE) {
        gteth = _gteth;
    }

    /**
     * @notice 获取GTETH合约地址
     * @return gtETH合约地址
     */
    function getGTETH() public view returns (address) {
        return gteth;
    }

    /**
     * @notice 添加新的质押模块
     * @param _name 质押模块名称
     * @param _stakingModuleAddress 质押模块合约地址
     * @param _stakeShareLimit 最大质押份额（基点）
     * @param _priorityExitShareThreshold 优先退出份额阈值（基点）
     * @param _stakingModuleFee 质押模块费用（基点）
     * @param _treasuryFee 财库费用（基点）
     */
    function addStakingModule(
        string calldata _name,
        address _stakingModuleAddress,
        uint256 _stakeShareLimit,
        uint256 _priorityExitShareThreshold,
        uint256 _stakingModuleFee,
        uint256 _treasuryFee
    ) external onlyRole(STAKING_MODULE_MANAGE_ROLE) {
        if (_stakingModuleAddress == address(0)) revert ZeroAddressStakingModule();
        if (bytes(_name).length == 0 || bytes(_name).length > MAX_STAKING_MODULE_NAME_LENGTH) {
            revert StakingModuleWrongName();
        }

        // 获取新质押模块的索引
        uint256 newStakingModuleIndex = stakingModulesCount;
        // 检查是否超过最大质押模块数量
        if (newStakingModuleIndex >= MAX_STAKING_MODULES_COUNT) {
            revert StakingModulesLimitExceeded();
        }

        // 检查地址是否已存在
        for (uint256 i; i < newStakingModuleIndex; ) {
            if (_stakingModuleAddress == stakingModules[i].stakingModuleAddress) {
                revert StakingModuleAddressExists();
            }
            unchecked { ++i; }  // 使用unchecked优化gas
        }

        // 创建新的质押模块ID，从1开始
        uint24 newStakingModuleId = uint24(lastStakingModuleId) + 1;
        
        // 获取新质押模块的存储引用
        StakingModule storage newStakingModule = stakingModules[newStakingModuleIndex];
        
        // 设置基本信息
        newStakingModule.id = newStakingModuleId;
        newStakingModule.name = _name;
        newStakingModule.stakingModuleAddress = _stakingModuleAddress;
        newStakingModule.status = uint8(StakingModuleStatus.Active);  // 默认激活状态

        // 设置索引映射（+1是因为0表示不存在）
        stakingModuleIndicesOneBased[newStakingModuleId] = newStakingModuleIndex + 1;
        // 更新计数器
        lastStakingModuleId = newStakingModuleId;
        stakingModulesCount = newStakingModuleIndex + 1;

        emit StakingModuleAdded(newStakingModuleId, _stakingModuleAddress, _name, msg.sender);
        
        // 更新质押模块参数
        _updateStakingModule(
            newStakingModule,
            newStakingModuleId,
            _stakeShareLimit,
            _priorityExitShareThreshold,
            _stakingModuleFee,
            _treasuryFee
        );
    }

    /**
     * @notice 更新质押模块参数
     * @param _stakingModuleId 质押模块ID
     * @param _stakeShareLimit 质押份额限制
     * @param _priorityExitShareThreshold 优先退出份额阈值
     * @param _stakingModuleFee 质押模块费用
     * @param _treasuryFee 财库费用
     */
    function updateStakingModule(
        uint256 _stakingModuleId,
        uint256 _stakeShareLimit,
        uint256 _priorityExitShareThreshold,
        uint256 _stakingModuleFee,
        uint256 _treasuryFee
    ) external onlyRole(STAKING_MODULE_MANAGE_ROLE) {
        StakingModule storage stakingModule = _getStakingModuleById(_stakingModuleId);
        // 更新质押模块参数
        _updateStakingModule(
            stakingModule,
            _stakingModuleId,
            _stakeShareLimit,
            _priorityExitShareThreshold,
            _stakingModuleFee,
            _treasuryFee
        );
    }

    /**
     * @notice 设置质押模块状态
     * @param _stakingModuleId 质押模块ID
     * @param _status 新状态
     */
    function setStakingModuleStatus(
        uint256 _stakingModuleId,
        StakingModuleStatus _status
    ) external onlyRole(STAKING_MODULE_MANAGE_ROLE) {
        StakingModule storage stakingModule = _getStakingModuleById(_stakingModuleId);
        // 检查状态是否相同
        if (StakingModuleStatus(stakingModule.status) == _status) {
            revert StakingModuleStatusTheSame();
        }
        // 设置新状态
        _setStakingModuleStatus(stakingModule, _status);
    }

    /**
     * @notice 执行ETH存款到信标链
     * @param _depositsCount 存款数量
     * @param _stakingModuleId 目标质押模块ID
     * @param _depositCalldata 存款调用数据
     */
    function deposit(
        uint256 _depositsCount,
        uint256 _stakingModuleId,
        bytes calldata _depositCalldata
    ) external payable nonReentrant whenNotPaused {
        // 验证调用者是GTETH合约
        if (msg.sender != gteth) revert ZeroAddressGTETH();

        // 验证提取凭证已设置
        if (withdrawalCredentials == 0) revert EmptyWithdrawalsCredentials();

        // 获取质押模块
        StakingModule storage stakingModule = _getStakingModuleById(_stakingModuleId);
        // 验证质押模块处于活跃状态
        if (StakingModuleStatus(stakingModule.status) != StakingModuleStatus.Active) {
            revert StakingModuleNotActive();
        }

        // 验证存款金额正确
        uint256 depositsValue = msg.value;
        if (depositsValue != _depositsCount * DEPOSIT_ETH_SIZE) {
            revert InvalidDepositsValue(depositsValue, _depositsCount);
        }

        emit StakingRouterETHDeposited(_stakingModuleId, depositsValue);

        // 如果存款数量大于0，执行实际存款
        if (_depositsCount > 0) {
            // 从质押模块获取存款数据
            (bytes memory publicKeysBatch, bytes memory signaturesBatch) = 
                INodeOperatorsRegistry(stakingModule.stakingModuleAddress).obtainDepositData(_depositsCount, _depositCalldata);

            // 记录存款前的余额
            uint256 etherBalanceBeforeDeposits = address(this).balance;
            
            // 执行信标链存款
            _makeBeaconChainDeposits32ETH(
                _depositsCount,
                abi.encodePacked(withdrawalCredentials),  // 转换为bytes格式
                publicKeysBatch,
                signaturesBatch
            );
            
            // 记录存款后的余额
            uint256 etherBalanceAfterDeposits = address(this).balance;
            
            // 验证所有ETH都已存款，余额变化等于存款金额
            assert(etherBalanceBeforeDeposits - etherBalanceAfterDeposits == depositsValue);
        }
    }

    /**
     * @notice 更新节点运营商的目标验证者限制
     * @param _stakingModuleId 质押模块ID
     * @param _nodeOperatorId 节点运营商ID
     * @param _targetLimitMode 目标限制模式
     * @param _targetLimit 目标限制值
     */
    function updateTargetValidatorsLimits(
        uint256 _stakingModuleId,
        uint256 _nodeOperatorId,
        uint256 _targetLimitMode,
        uint256 _targetLimit
    ) external onlyRole(STAKING_MODULE_MANAGE_ROLE) {
        INodeOperatorsRegistry(_getStakingModuleAddressById(_stakingModuleId)).updateTargetValidatorsLimits(
            _nodeOperatorId, _targetLimitMode, _targetLimit
        );
    }

    /**
     * @notice 更新节点运营商的退款验证者数量
     * @param _stakingModuleId 质押模块ID
     * @param _nodeOperatorId 节点运营商ID
     * @param _refundedValidatorsCount 新的退款验证者数量
     */
    function updateRefundedValidatorsCount(
        uint256 _stakingModuleId,
        uint256 _nodeOperatorId,
        uint256 _refundedValidatorsCount
    ) external onlyRole(STAKING_MODULE_MANAGE_ROLE) {
        INodeOperatorsRegistry(_getStakingModuleAddressById(_stakingModuleId)).updateRefundedValidatorsCount(
            _nodeOperatorId, _refundedValidatorsCount
        );
    }

    /**
     * @notice 更新质押模块的退出验证者数量
     * @param _stakingModuleIds 质押模块ID数组
     * @param _exitedValidatorsCounts 对应的退出验证者数量数组
     * @return newlyExitedValidatorsCount 新退出的验证者总数
     */
    function updateExitedValidatorsCountByStakingModule(
        uint256[] calldata _stakingModuleIds,
        uint256[] calldata _exitedValidatorsCounts
    ) external onlyRole(REPORT_EXITED_VALIDATORS_ROLE) returns (uint256 newlyExitedValidatorsCount) {
        // 验证数组长度匹配
        _validateEqualArrayLengths(_stakingModuleIds.length, _exitedValidatorsCounts.length);

        // 遍历所有质押模块
        for (uint256 i = 0; i < _stakingModuleIds.length; ) {
            uint256 stakingModuleId = _stakingModuleIds[i];
            StakingModule storage stakingModule = _getStakingModuleById(stakingModuleId);

            // 获取之前报告的退出验证者数量
            uint256 prevReportedExitedValidatorsCount = stakingModule.exitedValidatorsCount;
            // 验证退出验证者数量不能减少
            if (_exitedValidatorsCounts[i] < prevReportedExitedValidatorsCount) {
                revert ExitedValidatorsCountCannotDecrease();
            }

            // 从质押模块获取摘要信息
            (
                uint256 totalExitedValidators,
                uint256 totalDepositedValidators,
                /* uint256 depositableValidatorsCount */
            ) = _getStakingModuleSummary(INodeOperatorsRegistry(stakingModule.stakingModuleAddress));

            // 验证报告的退出验证者数量不超过已存款的验证者数量
            if (_exitedValidatorsCounts[i] > totalDepositedValidators) {
                revert ReportedExitedValidatorsExceedDeposited(
                    _exitedValidatorsCounts[i],
                    totalDepositedValidators
                );
            }

            // 累加新退出的验证者数量
            newlyExitedValidatorsCount += _exitedValidatorsCounts[i] - prevReportedExitedValidatorsCount;

            // 检查是否存在未完整报告的退出验证者
            if (totalExitedValidators < prevReportedExitedValidatorsCount) {
                emit StakingModuleExitedValidatorsIncompleteReporting(
                    stakingModuleId,
                    prevReportedExitedValidatorsCount - totalExitedValidators
                );
            }

            // 更新退出验证者数量
            stakingModule.exitedValidatorsCount = _exitedValidatorsCounts[i];
            unchecked { ++i; } 
        }

        return newlyExitedValidatorsCount;
    }

    /**
     * @notice 按节点运营商报告退出验证者数量
     * @param _stakingModuleId 质押模块ID
     * @param _nodeOperatorIds 节点运营商ID数据（字节编码）
     * @param _exitedValidatorsCounts 退出验证者数量数据（字节编码）
     */
    function reportStakingModuleExitedValidatorsCountByNodeOperator(
        uint256 _stakingModuleId,
        bytes calldata _nodeOperatorIds,
        bytes calldata _exitedValidatorsCounts
    ) external onlyRole(REPORT_EXITED_VALIDATORS_ROLE) {
        _checkValidatorsByNodeOperatorReportData(_nodeOperatorIds, _exitedValidatorsCounts);
        INodeOperatorsRegistry(_getStakingModuleAddressById(_stakingModuleId)).updateExitedValidatorsCount(
            _nodeOperatorIds, 
            _exitedValidatorsCounts
        );
    }

    /**
     * @notice 按节点运营商报告卡住验证者数量
     * @param _stakingModuleId 质押模块ID
     * @param _nodeOperatorIds 节点运营商ID数据（字节编码）
     * @param _stuckValidatorsCounts 卡住验证者数量数据（字节编码）
     */
    function reportStakingModuleStuckValidatorsCountByNodeOperator(
        uint256 _stakingModuleId,
        bytes calldata _nodeOperatorIds,
        bytes calldata _stuckValidatorsCounts
    ) external onlyRole(REPORT_EXITED_VALIDATORS_ROLE) {
        _checkValidatorsByNodeOperatorReportData(_nodeOperatorIds, _stuckValidatorsCounts);
        INodeOperatorsRegistry(_getStakingModuleAddressById(_stakingModuleId)).updateStuckValidatorsCount(
            _nodeOperatorIds, 
            _stuckValidatorsCounts
        );
    }

    /**
     * @notice 完成节点运营商验证者计数报告
     * @dev 当预言机完成第二阶段数据提交后调用，通知所有质押模块完成状态更新
     */
    function onValidatorsCountsByNodeOperatorReportingFinished() 
        external 
        onlyRole(REPORT_EXITED_VALIDATORS_ROLE) 
    {
        uint256 modulesCount = stakingModulesCount;
        for (uint256 i; i < modulesCount; ) {
            StakingModule storage stakingModule = stakingModules[i];
            INodeOperatorsRegistry moduleContract = INodeOperatorsRegistry(stakingModule.stakingModuleAddress);

            // 获取模块内部的退出验证者数量
            (uint256 exitedValidatorsCount, , ) = _getStakingModuleSummary(moduleContract);
            
            // 只有当模块内部数量与路由器记录数量匹配时，才触发完成回调
            if (exitedValidatorsCount == stakingModule.exitedValidatorsCount) {
                try moduleContract.onExitedAndStuckValidatorsCountsUpdated() {
                } catch {
                }
            }

            unchecked { ++i; }
        }
    }

    /**
     * @notice 减少节点运营商的审核密钥数量
     * @param _stakingModuleId 质押模块ID
     * @param _nodeOperatorIds 节点运营商ID数据（字节编码）
     * @param _vettedSigningKeysCounts 审核密钥数量数据（字节编码）
     * @dev 用于紧急情况下减少审核密钥
     */
    function decreaseStakingModuleVettedKeysCountByNodeOperator(
        uint256 _stakingModuleId,
        bytes calldata _nodeOperatorIds,
        bytes calldata _vettedSigningKeysCounts
    ) external onlyRole(STAKING_MODULE_MANAGE_ROLE) {
        _checkValidatorsByNodeOperatorReportData(_nodeOperatorIds, _vettedSigningKeysCounts);
        INodeOperatorsRegistry(_getStakingModuleAddressById(_stakingModuleId)).decreaseVettedSigningKeysCount(
            _nodeOperatorIds, 
            _vettedSigningKeysCounts
        );
    }

    /**
     * @notice 报告奖励分配给指定的质押模块
     * @param _stakingModuleIds 质押模块ID数组  
     * @param _totalRewards 对应的总奖励ETH数量数组（wei为单位）
     * @dev 适配gtETH的兑换率机制：直接分配ETH奖励而不是份额
     */
    function reportRewardsMinted(
        uint256[] calldata _stakingModuleIds,
        uint256[] calldata _totalRewards
    ) external onlyRole(REPORT_REWARDS_MINTED_ROLE) {
        // 验证数组长度匹配
        _validateEqualArrayLengths(_stakingModuleIds.length, _totalRewards.length);

        // 遍历所有质押模块
        for (uint256 i = 0; i < _stakingModuleIds.length; ) {
            // 如果奖励金额大于0，通知质押模块
            if (_totalRewards[i] > 0) {
                try INodeOperatorsRegistry(_getStakingModuleAddressById(_stakingModuleIds[i])).onRewardsMinted() {
                } catch {
                }
            }
            unchecked { ++i; }
        }
    }
    
    /**
     * @notice 设置新的提取凭证
     * @param _withdrawalCredentials 新的提取凭证
     * @dev 注意：设置提取凭证会使所有未使用的存款数据失效，因为签名会变得无效
     */
    function setWithdrawalCredentials(bytes32 _withdrawalCredentials) 
        external 
        onlyRole(MANAGE_WITHDRAWAL_CREDENTIALS_ROLE) 
    {
        // 更新提取凭证
        withdrawalCredentials = _withdrawalCredentials;

        // 通知所有质押模块提取凭证已更改
        uint256 modulesCount = stakingModulesCount;
        for (uint256 i; i < modulesCount; ) {
            StakingModule storage stakingModule = stakingModules[i];
                
            try INodeOperatorsRegistry(stakingModule.stakingModuleAddress).onWithdrawalCredentialsChanged() {
            } catch {
                _setStakingModuleStatus(stakingModule, StakingModuleStatus.DepositsPaused);
            }
            unchecked { ++i; }
        }

        emit WithdrawalCredentialsSet(_withdrawalCredentials, msg.sender);
    }
    
    /**
     * @notice 暂停合约
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice 恢复合约
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice 获取所有质押模块
     * @return res 质押模块数组
     */
    function getStakingModules() external view returns (StakingModule[] memory res) {
        uint256 count = stakingModulesCount;
        res = new StakingModule[](count);
        for (uint256 i; i < count; ) {
            res[i] = stakingModules[i];
            unchecked { ++i; }
        }
    }

    /**
     * @notice 获取质押模块
     * @param _stakingModuleId 质押模块ID
     * @return 质押模块数据
     */
    function getStakingModule(uint256 _stakingModuleId) 
        external 
        view 
        returns (StakingModule memory) 
    {
        return _getStakingModuleById(_stakingModuleId);
    }

    /**
     * @notice 检查质押模块是否存在
     * @param _stakingModuleId 质押模块ID
     * @return 如果存在返回true，否则返回false
     */
    function hasStakingModule(uint256 _stakingModuleId) external view returns (bool) {
        return stakingModuleIndicesOneBased[_stakingModuleId] != 0;
    }

    /**
     * @notice 获取质押模块状态
     * @param _stakingModuleId 质押模块ID
     * @return 质押模块状态
     */
    function getStakingModuleStatus(uint256 _stakingModuleId) 
        external 
        view 
        returns (StakingModuleStatus) 
    {
        return StakingModuleStatus(_getStakingModuleById(_stakingModuleId).status);
    }

    /**
     * @notice 获取质押模块活跃验证者数量
     * @param _stakingModuleId 质押模块ID
     * @return activeValidatorsCount 活跃验证者数量
     */
    function getStakingModuleActiveValidatorsCount(uint256 _stakingModuleId)
        external
        view
        returns (uint256 activeValidatorsCount)
    {
        StakingModule memory stakingModule = _getStakingModuleById(_stakingModuleId);
        
        // 从质押模块获取摘要
        (
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            /* uint256 depositableValidatorsCount */
        ) = _getStakingModuleSummary(INodeOperatorsRegistry(stakingModule.stakingModuleAddress));

        // 活跃验证者 = 总存款验证者 - 最大(模块记录的退出数, 实际退出数)
        /* 
        由于reportStakingModuleExitedValidatorsCountByNodeOperator和
        updateExitedValidatorsCountByStakingModule的预言机调用时间可能会有差异，
        所以为了防止两边记录的数据不一致，导致活跃验证者数量计算错误，这里取最大值
        */ 
        activeValidatorsCount = totalDepositedValidators - 
            _max(stakingModule.exitedValidatorsCount, totalExitedValidators);
    }

    /**
     * @notice 获取存款分配
     * @param _depositsCount 要分配的存款数量
     * @return allocated 实际分配的存款数量
     * @return allocations 各模块的分配数量数组
     */
    function getDepositsAllocation(uint256 _depositsCount) 
        external 
        view 
        returns (uint256 allocated, uint256[] memory allocations) 
    {
        return _getDepositsAllocation(_depositsCount);
    }

    /**
     * @notice 获取当前提取凭证
     * @return 当前设置的提取凭证
     */
    function getWithdrawalCredentials() external view returns (bytes32) {
        return withdrawalCredentials;
    }

    /**
     * @notice 获取质押模块摘要
     * @param _stakingModuleId 质押模块ID
     * @return summary 质押模块摘要信息
     */
    function getStakingModuleSummary(uint256 _stakingModuleId)
        external
        view
        returns (StakingModuleSummary memory summary)
    {
        StakingModule memory stakingModule = _getStakingModuleById(_stakingModuleId);
        INodeOperatorsRegistry moduleContract = INodeOperatorsRegistry(stakingModule.stakingModuleAddress);
        
        (
            summary.totalExitedValidators,
            summary.totalDepositedValidators,
            summary.depositableValidatorsCount
        ) = _getStakingModuleSummary(moduleContract);
    }

    /**
     * @notice 获取节点运营商摘要
     * @param _stakingModuleId 质押模块ID
     * @param _nodeOperatorId 节点运营商ID
     * @return summary 节点运营商摘要信息
     */
    function getNodeOperatorSummary(uint256 _stakingModuleId, uint256 _nodeOperatorId)
        external
        view
        returns (NodeOperatorSummary memory summary)
    {
        INodeOperatorsRegistry moduleContract = INodeOperatorsRegistry(_getStakingModuleAddressById(_stakingModuleId));
        
        (
            summary.targetLimitMode,
            summary.targetValidatorsCount,
            summary.stuckValidatorsCount,
            summary.refundedValidatorsCount,
            summary.stuckPenaltyEndTimestamp,
            summary.totalExitedValidators,
            summary.totalDepositedValidators,
            summary.depositableValidatorsCount
        ) = moduleContract.getNodeOperatorSummary(_nodeOperatorId);
    }

    /**
     * @notice 检查质押模块是否为活跃状态
     * @param _stakingModuleId 质押模块ID
     * @return 如果质押模块为活跃状态返回true
     */
    function getStakingModuleIsActive(uint256 _stakingModuleId) external view returns (bool) {
        return StakingModuleStatus(_getStakingModuleById(_stakingModuleId).status) == StakingModuleStatus.Active;
    }

    /**
     * @notice 检查质押模块是否暂停存款
     * @param _stakingModuleId 质押模块ID
     * @return 如果质押模块暂停存款返回true
     */
    function getStakingModuleIsDepositsPaused(uint256 _stakingModuleId) external view returns (bool) {
        return StakingModuleStatus(_getStakingModuleById(_stakingModuleId).status) == StakingModuleStatus.DepositsPaused;
    }

    /**
     * @notice 检查质押模块是否已停止
     * @param _stakingModuleId 质押模块ID
     * @return 如果质押模块已停止返回true
     */
    function getStakingModuleIsStopped(uint256 _stakingModuleId) external view returns (bool) {
        return StakingModuleStatus(_getStakingModuleById(_stakingModuleId).status) == StakingModuleStatus.Stopped;
    }

    /**
     * @notice 获取质押模块的nonce
     * @param _stakingModuleId 质押模块ID
     * @return 质押模块的nonce值
     */
    function getStakingModuleNonce(uint256 _stakingModuleId) external view returns (uint256) {
        return INodeOperatorsRegistry(_getStakingModuleAddressById(_stakingModuleId)).getNonce();
    }

    /**
     * @notice 获取质押模块可执行的最大存款数量
     * @param _stakingModuleId 质押模块ID
     * @param _maxDepositsValue 最大存款ETH数量
     * @return 该质押模块可执行的最大存款数量
     */
    function getStakingModuleMaxDepositsCount(uint256 _stakingModuleId, uint256 _maxDepositsValue)
        external
        view
        returns (uint256)
    {
        (, uint256[] memory allocations) = _getDepositsAllocation(_maxDepositsValue / DEPOSIT_ETH_SIZE);
        uint256 moduleIndex = _getStakingModuleIndexById(_stakingModuleId);
        
        if (moduleIndex < allocations.length) {
            return allocations[moduleIndex];
        }
        return 0;
    }

    /**
     * @notice 获取奖励分配表
     * @return recipients 奖励接收者地址数组
     * @return stakingModuleIds 质押模块ID数组
     * @return stakingModuleFees 各模块费用数组
     * @return totalFee 总费用
     * @return precisionPoints 精度点数
     */
    function getStakingRewardsDistribution()
        public
        view
        returns (
            address[] memory recipients,
            uint256[] memory stakingModuleIds,
            uint96[] memory stakingModuleFees,
            uint96 totalFee,
            uint256 precisionPoints
        )
    {
        return _getStakingRewardsDistribution();
    }

    /**
     * @notice 内部函数：获取奖励分配表（拆分以避免stack too deep）
     */
    function _getStakingRewardsDistribution()
        internal
        view
        returns (
            address[] memory recipients,
            uint256[] memory stakingModuleIds,
            uint96[] memory stakingModuleFees,
            uint96 totalFee,
            uint256 precisionPoints
        )
    {
        uint256 totalActiveValidators = _getTotalActiveValidators();
        uint256 modulesCount = stakingModulesCount;
        
        // 如果没有模块或活跃验证者，返回空数组
        if (modulesCount == 0 || totalActiveValidators == 0) {
            return (new address[](0), new uint256[](0), new uint96[](0), 0, FEE_PRECISION_POINTS);
        }

        precisionPoints = FEE_PRECISION_POINTS;
        stakingModuleIds = new uint256[](modulesCount);
        recipients = new address[](modulesCount);
        stakingModuleFees = new uint96[](modulesCount);

        uint256 rewardedCount = _fillRewardsDistribution(
            stakingModuleIds,
            recipients,
            stakingModuleFees,
            totalActiveValidators,
            precisionPoints
        );
        
        totalFee = _calculateTotalFee(totalActiveValidators, precisionPoints);

        // 缩小数组
        if (rewardedCount < modulesCount) {
            assembly {
                mstore(stakingModuleIds, rewardedCount)
                mstore(recipients, rewardedCount)
                mstore(stakingModuleFees, rewardedCount)
            }
        }
    }
    
    /**
     * @notice 禁止直接向合约转账ETH
     * @dev 所有ETH必须通过deposit函数进行存款
     */
    receive() external payable {
        revert DirectETHTransfer();
    }

    /**
     * @notice 内部函数：更新质押模块参数
     * @dev 包含所有参数验证逻辑
     */
    function _updateStakingModule(
        StakingModule storage stakingModule,
        uint256 _stakingModuleId,
        uint256 _stakeShareLimit,
        uint256 _priorityExitShareThreshold,
        uint256 _stakingModuleFee,
        uint256 _treasuryFee
    ) internal {
        // 验证质押份额限制不超过100%
        if (_stakeShareLimit > TOTAL_BASIS_POINTS) revert InvalidStakeShareLimit();
        // 验证优先退出阈值不超过100%
        if (_priorityExitShareThreshold > TOTAL_BASIS_POINTS) revert InvalidPriorityExitShareThreshold();
        // 验证质押份额限制不小于优先退出阈值
        if (_stakeShareLimit < _priorityExitShareThreshold) revert InvalidPriorityExitShareThreshold();
        // 验证费用总和不超过100%
        if (_stakingModuleFee + _treasuryFee > TOTAL_BASIS_POINTS) revert InvalidFeeSum();

        // 更新参数
        stakingModule.stakeShareLimit = uint16(_stakeShareLimit);
        stakingModule.priorityExitShareThreshold = uint16(_priorityExitShareThreshold);
        stakingModule.treasuryFee = uint16(_treasuryFee);
        stakingModule.stakingModuleFee = uint16(_stakingModuleFee);

        // 发出事件
        emit StakingModuleShareLimitSet(_stakingModuleId, _stakeShareLimit, _priorityExitShareThreshold, msg.sender);
        emit StakingModuleFeesSet(_stakingModuleId, _stakingModuleFee, _treasuryFee, msg.sender);
    }

    /**
     * @notice 内部函数：设置质押模块状态
     */
    function _setStakingModuleStatus(StakingModule storage _stakingModule, StakingModuleStatus _status) internal {
        _stakingModule.status = uint8(_status);
        emit StakingModuleStatusSet(_stakingModule.id, _status, msg.sender);
    }

    /**
     * @notice 内部函数：通过ID获取质押模块
     */
    function _getStakingModuleById(uint256 _stakingModuleId) 
        internal 
        view 
        returns (StakingModule storage) 
    {
        return stakingModules[_getStakingModuleIndexById(_stakingModuleId)];
    }

    /**
     * @notice 内部函数：通过ID获取质押模块索引
     */
    function _getStakingModuleIndexById(uint256 _stakingModuleId) internal view returns (uint256) {
        uint256 indexOneBased = stakingModuleIndicesOneBased[_stakingModuleId];
        if (indexOneBased == 0) revert StakingModuleUnregistered();
        return indexOneBased - 1;  // 减1得到实际索引
    }

    /**
     * @notice 内部函数：通过ID获取质押模块地址
     */
    function _getStakingModuleAddressById(uint256 _stakingModuleId) internal view returns (address) {
        return _getStakingModuleById(_stakingModuleId).stakingModuleAddress;
    }

    /**
     * @notice 内部函数：验证数组长度相等
     */
    function _validateEqualArrayLengths(uint256 firstArrayLength, uint256 secondArrayLength) internal pure {
        if (firstArrayLength != secondArrayLength) {
            revert ArraysLengthMismatch(firstArrayLength, secondArrayLength);
        }
    }

    /**
     * @notice 内部函数：获取质押模块摘要（优化gas的包装函数）
     */
    function _getStakingModuleSummary(INodeOperatorsRegistry stakingModule) 
        internal 
        view 
        returns (uint256, uint256, uint256) 
    {
        return stakingModule.getStakingModuleSummary();
    }

    /**
     * @notice 内部函数：返回两个数中的较大值
     */
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @notice 内部函数：验证节点运营商报告数据格式
     * @param _nodeOperatorIds 节点运营商ID数据
     * @param _validatorsCounts 验证者数量数据
     */
    function _checkValidatorsByNodeOperatorReportData(
        bytes calldata _nodeOperatorIds,
        bytes calldata _validatorsCounts
    ) internal pure {
        // 验证ID数据长度必须是8的倍数（每个ID占8字节）
        if (_nodeOperatorIds.length % 8 != 0 || _validatorsCounts.length % 16 != 0) {
            revert ArraysLengthMismatch(_nodeOperatorIds.length, _validatorsCounts.length);
        }
        
        // 验证数量数据长度必须是16的倍数（每个数量占16字节）
        uint256 nodeOperatorsCount = _nodeOperatorIds.length / 8;
        if (_validatorsCounts.length / 16 != nodeOperatorsCount) {
            revert ArraysLengthMismatch(_nodeOperatorIds.length, _validatorsCounts.length);
        }
        
        // 验证至少有一个节点运营商
        if (nodeOperatorsCount == 0) {
            revert ArraysLengthMismatch(_nodeOperatorIds.length, _validatorsCounts.length);
        }
    }

    /**
     * @notice 内部函数：获取存款分配（最小分配策略）
     * @dev 实现最小优先分配算法，优先给分配数量最少的模块分配存款
     */
    function _getDepositsAllocation(uint256 _depositsToAllocate)
        internal
        view
        returns (uint256 allocated, uint256[] memory allocations)
    {
        uint256 modulesCount = stakingModulesCount;
        allocations = new uint256[](modulesCount);
        
        if (modulesCount == 0 || _depositsToAllocate == 0) {
            return (0, allocations);
        }

        // 创建模块缓存数组以存储计算所需数据
        StakingModuleCache[] memory stakingModulesCache = new StakingModuleCache[](modulesCount);
        uint256 totalActiveValidators = 0;
        uint256 activeModulesCount = 0;

        // 加载所有模块的缓存数据
        for (uint256 i; i < modulesCount; ) {
            StakingModule storage stakingModule = stakingModules[i];
            stakingModulesCache[i].stakingModuleAddress = stakingModule.stakingModuleAddress;
            stakingModulesCache[i].stakingModuleId = uint24(stakingModule.id);
            stakingModulesCache[i].stakeShareLimit = stakingModule.stakeShareLimit;
            stakingModulesCache[i].status = StakingModuleStatus(stakingModule.status);

            if (stakingModulesCache[i].status == StakingModuleStatus.Active) {
                // 获取模块摘要数据
                (
                    uint256 totalExitedValidators,
                    uint256 totalDepositedValidators,
                    uint256 depositableValidatorsCount
                ) = _getStakingModuleSummary(INodeOperatorsRegistry(stakingModule.stakingModuleAddress));

                // 计算活跃验证者数量
                uint256 moduleActiveValidators = totalDepositedValidators - 
                    _max(stakingModule.exitedValidatorsCount, totalExitedValidators);
                
                stakingModulesCache[i].activeValidatorsCount = moduleActiveValidators;
                stakingModulesCache[i].availableValidatorsCount = depositableValidatorsCount;
                
                totalActiveValidators += moduleActiveValidators;
                activeModulesCount++;
            }
            unchecked { ++i; }
        }

        if (activeModulesCount == 0) {
            return (0, allocations);
        }

        // 计算预期的总活跃验证者数量（包括新存款）
        uint256 newTotalActiveValidators = totalActiveValidators + _depositsToAllocate;
        
        // 为每个模块计算容量和目标分配
        uint256[] memory capacities = new uint256[](modulesCount);
        uint256[] memory currentAllocations = new uint256[](modulesCount);
        
        for (uint256 i; i < modulesCount; ) {
            currentAllocations[i] = stakingModulesCache[i].activeValidatorsCount;
            
            if (stakingModulesCache[i].status == StakingModuleStatus.Active) {
                // 计算基于份额限制的目标验证者数量
                uint256 targetValidators = (stakingModulesCache[i].stakeShareLimit * newTotalActiveValidators) / TOTAL_BASIS_POINTS;
                
                // 容量是目标数量和可用数量的最小值
                capacities[i] = _min(
                    targetValidators,
                    stakingModulesCache[i].activeValidatorsCount + stakingModulesCache[i].availableValidatorsCount
                );
            }
            unchecked { ++i; }
        }

        // 执行最小优先分配策略
        (allocated, allocations) = _minFirstAllocate(currentAllocations, capacities, _depositsToAllocate);
        
        // 计算新增分配（从当前分配中减去）
        for (uint256 i; i < modulesCount; ) {
            if (allocations[i] >= currentAllocations[i]) {
                allocations[i] = allocations[i] - currentAllocations[i];
            } else {
                allocations[i] = 0;
            }
            unchecked { ++i; }
        }
    }

    /**
     * @notice 内部函数：最小优先分配算法
     * @dev 优先给当前分配数量最少的模块分配新的存款
     * @param _currentAllocations 当前各模块的分配数量
     * @param _capacities 各模块的容量上限
     * @param _depositsToAllocate 要分配的存款数量
     * @return newAllocated 实际分配的数量
     * @return newAllocations 分配后各模块的总分配数量
     */
    function _minFirstAllocate(
        uint256[] memory _currentAllocations,
        uint256[] memory _capacities,
        uint256 _depositsToAllocate
    ) internal pure returns (uint256 newAllocated, uint256[] memory newAllocations) {
        uint256 modulesCount = _currentAllocations.length;
        newAllocations = new uint256[](modulesCount);
        
        // 复制当前分配作为起始点
        for (uint256 i; i < modulesCount; ) {
            newAllocations[i] = _currentAllocations[i];
            unchecked { ++i; }
        }
        
        uint256 remainingDeposits = _depositsToAllocate;
        
        // 持续分配直到没有剩余存款或无法再分配
        while (remainingDeposits > 0) {
            uint256 minAllocation = type(uint256).max;
            uint256 candidatesCount = 0;
            
            // 找到当前分配最少的数量
            for (uint256 i; i < modulesCount; ) {
                if (_capacities[i] > newAllocations[i]) {
                    if (newAllocations[i] < minAllocation) {
                        minAllocation = newAllocations[i];
                        candidatesCount = 1;
                    } else if (newAllocations[i] == minAllocation) {
                        candidatesCount++;
                    }
                }
                unchecked { ++i; }
            }
            
            // 如果没有可分配的模块，跳出循环
            if (candidatesCount == 0) break;
            
            // 找到下一个分配水平
            uint256 nextLevel = type(uint256).max;
            for (uint256 i; i < modulesCount; ) {
                if (_capacities[i] > newAllocations[i] && newAllocations[i] > minAllocation) {
                    nextLevel = _min(nextLevel, newAllocations[i]);
                }
                unchecked { ++i; }
            }
            
            // 计算需要多少存款来让最少的模块达到下一个水平
            uint256 levelGap = nextLevel == type(uint256).max ? 1 : nextLevel - minAllocation;
            uint256 neededDeposits = levelGap * candidatesCount;
            
            // 如果需要的存款超过剩余存款，平均分配剩余存款
            if (neededDeposits > remainingDeposits) {
                uint256 depositsPerCandidate = remainingDeposits / candidatesCount;
                uint256 extraDeposits = remainingDeposits % candidatesCount;
                
                for (uint256 i; i < modulesCount; ) {
                    if (_capacities[i] > newAllocations[i] && newAllocations[i] == minAllocation) {
                        uint256 toAllocate = depositsPerCandidate;
                        if (extraDeposits > 0) {
                            toAllocate++;
                            extraDeposits--;
                        }
                        
                        // 确保不超过容量限制
                        uint256 maxToAllocate = _capacities[i] - newAllocations[i];
                        toAllocate = _min(toAllocate, maxToAllocate);
                        
                        newAllocations[i] += toAllocate;
                        newAllocated += toAllocate;
                    }
                    unchecked { ++i; }
                }
                break;
            }
            
            // 将所有最少分配的模块提升到下一个水平
            for (uint256 i; i < modulesCount; ) {
                if (_capacities[i] > newAllocations[i] && newAllocations[i] == minAllocation) {
                    uint256 toAllocate = _min(levelGap, _capacities[i] - newAllocations[i]);
                    newAllocations[i] += toAllocate;
                    newAllocated += toAllocate;
                }
                unchecked { ++i; }
            }
            
            remainingDeposits -= _min(remainingDeposits, neededDeposits);
        }
    }

    /**
     * @notice 内部函数：返回两个数中的较小值
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice 内部函数：获取总的活跃验证者数量
     */
    function _getTotalActiveValidators() internal view returns (uint256 totalActiveValidators) {
        for (uint256 i; i < stakingModulesCount; ) {
            totalActiveValidators += _getModuleActiveValidators(stakingModules[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @notice 内部函数：获取单个模块的活跃验证者数量
     */
    function _getModuleActiveValidators(StakingModule storage stakingModule) internal view returns (uint256 activeValidators) {
        (
            uint256 totalExitedValidators,
            uint256 totalDepositedValidators,
            /* uint256 depositableValidatorsCount */
        ) = _getStakingModuleSummary(INodeOperatorsRegistry(stakingModule.stakingModuleAddress));

        activeValidators = totalDepositedValidators - _max(stakingModule.exitedValidatorsCount, totalExitedValidators);
    }

    /**
     * @notice 内部函数：填充奖励分配数组
     */
    function _fillRewardsDistribution(
        uint256[] memory stakingModuleIds,
        address[] memory recipients,
        uint96[] memory stakingModuleFees,
        uint256 totalActiveValidators,
        uint256 precisionPoints
    ) internal view returns (uint256 rewardedCount) {
        uint256 modulesCount = stakingModulesCount;
        
        for (uint256 i; i < modulesCount; ) {
            StakingModule storage stakingModule = stakingModules[i];
            uint256 moduleActiveValidators = _getModuleActiveValidators(stakingModule);
            
            if (moduleActiveValidators > 0) {
                stakingModuleIds[rewardedCount] = stakingModule.id;
                recipients[rewardedCount] = stakingModule.stakingModuleAddress;
                
                uint256 validatorsShare = (moduleActiveValidators * precisionPoints) / totalActiveValidators;
                uint96 moduleFee = uint96((validatorsShare * stakingModule.stakingModuleFee) / TOTAL_BASIS_POINTS);
                
                if (StakingModuleStatus(stakingModule.status) != StakingModuleStatus.Stopped) {
                    stakingModuleFees[rewardedCount] = moduleFee;
                }
                
                rewardedCount++;
            }
            unchecked { ++i; }
        }
    }

    /**
     * @notice 内部函数：计算总费用
     */
    function _calculateTotalFee(uint256 totalActiveValidators, uint256 precisionPoints) internal view returns (uint96 totalFee) {
        uint256 modulesCount = stakingModulesCount;
        
        for (uint256 i; i < modulesCount; ) {
            StakingModule storage stakingModule = stakingModules[i];
            uint256 moduleActiveValidators = _getModuleActiveValidators(stakingModule);
            
            if (moduleActiveValidators > 0) {
                uint256 validatorsShare = (moduleActiveValidators * precisionPoints) / totalActiveValidators;
                uint96 moduleFee = uint96((validatorsShare * stakingModule.stakingModuleFee) / TOTAL_BASIS_POINTS);
                uint96 treasuryFee = uint96((validatorsShare * stakingModule.treasuryFee) / TOTAL_BASIS_POINTS);
                
                totalFee += moduleFee + treasuryFee;
            }
            unchecked { ++i; }
        }
        
        assert(totalFee <= precisionPoints);
    }
}