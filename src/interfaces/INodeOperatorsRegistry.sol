// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title INode
 * @notice 节点运营商管理合约接口
 */
interface INodeOperatorsRegistry {

    //
    // 节点运营商管理函数
    //
    
    function addNodeOperator(string memory _name, address _rewardAddress) external returns (uint256 id);
    function activateNodeOperator(uint256 _nodeOperatorId) external;
    function deactivateNodeOperator(uint256 _nodeOperatorId) external;
    function setNodeOperatorName(uint256 _nodeOperatorId, string memory _name) external;
    function setNodeOperatorRewardAddress(uint256 _nodeOperatorId, address _rewardAddress) external;
    function setNodeOperatorStakingLimit(uint256 _nodeOperatorId, uint64 _vettedSigningKeysCount) external;

    //
    // 签名密钥管理函数
    //

    function addSigningKeys(
        uint256 _nodeOperatorId, 
        uint256 _keysCount, 
        bytes calldata _publicKeys, 
        bytes calldata _signatures
    ) external;

    function removeSigningKeys(uint256 _nodeOperatorId, uint256 _fromIndex, uint256 _keysCount) external;

    function getSigningKey(uint256 _nodeOperatorId, uint256 _index) external view returns (
        bytes memory key, 
        bytes memory depositSignature, 
        bool used
    );

    function getSigningKeys(uint256 _nodeOperatorId, uint256 _offset, uint256 _limit) external view returns (
        bytes memory pubkeys, 
        bytes memory signatures, 
        bool[] memory used
    );

    //
    // 验证者状态管理函数
    //

    function decreaseVettedSigningKeysCount(
        bytes calldata _nodeOperatorIds,
        bytes calldata _vettedSigningKeysCounts
    ) external;

    function onRewardsMinted() external;

    function updateStuckValidatorsCount(
        bytes calldata _nodeOperatorIds, 
        bytes calldata _stuckValidatorsCounts
    ) external;

    function updateExitedValidatorsCount(
        bytes calldata _nodeOperatorIds,
        bytes calldata _exitedValidatorsCounts
    ) external;

    function updateRefundedValidatorsCount(uint256 _nodeOperatorId, uint256 _refundedValidatorsCount) external;

    function updateTargetValidatorsLimits(
        uint256 _nodeOperatorId,
        uint256 _targetLimitMode,
        uint256 _targetLimit
    ) external;

    function obtainDepositData(
        uint256 _depositsCount,
        bytes calldata _depositCalldata
    ) external returns (bytes memory publicKeys, bytes memory signatures);

    //
    // 奖励分配函数
    //

    function distributeReward() external;
    function onExitedAndStuckValidatorsCountsUpdated() external;

    //
    // 提取凭证变更通知函数
    //

    /**
     * @notice 当提取凭证发生变更时被调用
     * @dev 当StakingRouter更新提取凭证时，会通知所有质押模块
     *      质押模块需要处理这种变更，通常会使现有的存款数据失效
     */
    function onWithdrawalCredentialsChanged() external;

    //
    // 查询函数
    //

    function getNodeOperator(uint256 _nodeOperatorId, bool _fullInfo) external view returns (
        bool active,
        string memory name,
        address rewardAddress,
        uint64 totalVettedValidators,
        uint64 totalExitedValidators,
        uint64 totalAddedValidators,
        uint64 totalDepositedValidators
    );

    function getRewardsDistribution(uint256 _totalRewardAmount) external view returns (
        address[] memory recipients, 
        uint256[] memory amounts, 
        bool[] memory penalized
    );

    function getType() external view returns (bytes32);

    function getStakingModuleSummary() external view returns (
        uint256 totalExitedValidators, 
        uint256 totalDepositedValidators, 
        uint256 depositableValidatorsCount
    );

    function getNodeOperatorSummary(uint256 _nodeOperatorId) external view returns (
        uint256 targetLimitMode,
        uint256 targetValidatorsCount,
        uint256 stuckValidatorsCount,
        uint256 refundedValidatorsCount,
        uint256 stuckPenaltyEndTimestamp,
        uint256 totalExitedValidators,
        uint256 totalDepositedValidators,
        uint256 depositableValidatorsCount
    );

    function getNodeOperatorsCount() external view returns (uint256);
    function getActiveNodeOperatorsCount() external view returns (uint256);
    function getNodeOperatorIsActive(uint256 _nodeOperatorId) external view returns (bool);
    function isOperatorPenalized(uint256 _nodeOperatorId) external view returns (bool);
    function isOperatorPenaltyCleared(uint256 _nodeOperatorId) external view returns (bool);
    function clearNodeOperatorPenalty(uint256 _nodeOperatorId) external returns (bool);
    function getNonce() external view returns (uint256);
    function getStuckPenaltyDelay() external view returns (uint256);
    function setStuckPenaltyDelay(uint256 _delay) external;
    
    function unsafeUpdateValidatorsCount(
        uint256 _nodeOperatorId,
        uint256 _exitedValidatorsCount,
        uint256 _stuckValidatorsCount
    ) external;
    
    function getTotalSigningKeyCount(uint256 _nodeOperatorId) external view returns (uint256);
    function getUnusedSigningKeyCount(uint256 _nodeOperatorId) external view returns (uint256);
    function getNodeOperatorIds(uint256 _offset, uint256 _limit) external view returns (uint256[] memory);
} 