// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IStakingRouter {
    function deposit(
        uint256 _depositsCount,
        uint256 _stakingModuleId,
        bytes calldata _depositCalldata
    ) external payable;

    function getStakingRewardsDistribution()
        external
        view
        returns (
            address[] memory recipients,
            uint256[] memory stakingModuleIds,
            uint96[] memory stakingModuleFees,
            uint96 totalFee,
            uint256 precisionPoints
        );

    function getWithdrawalCredentials() external view returns (bytes32);

    function reportRewardsMinted(uint256[] calldata _stakingModuleIds, uint256[] calldata _totalShares) external;

    function getTotalFeeE4Precision() external view returns (uint16 totalFee);

    function getStakingModuleMaxDepositsCount(uint256 _stakingModuleId, uint256 _maxDepositsValue)
        external
        view
        returns (uint256);

    function TOTAL_BASIS_POINTS() external view returns (uint256);

    function onValidatorsCountsByNodeOperatorReportingFinished() external;

    function reportStakingModuleStuckValidatorsCountByNodeOperator(
        uint256 _stakingModuleId,
        bytes calldata _nodeOperatorIds,
        bytes calldata _stuckValidatorsCounts
    ) external;

    function reportStakingModuleExitedValidatorsCountByNodeOperator(
        uint256 _stakingModuleId,
        bytes calldata _nodeOperatorIds,
        bytes calldata _exitedValidatorsCounts
    ) external;

    function updateExitedValidatorsCountByStakingModule(
        uint256[] calldata _stakingModuleIds,
        uint256[] calldata _exitedValidatorsCounts
    ) external returns (uint256 newlyExitedValidatorsCount);

}