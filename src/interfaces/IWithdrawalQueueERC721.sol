// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IWithdrawalQueueERC721 {
    struct WithdrawalRequest {
        uint256 cumulativeGTETHAmount;
        uint256 cumulativeETHAmount;
        address creator;
        uint256 createdAt;
        address recipient;
        uint256 claimedAt;
        bool isClaimed;
    }

    struct WithdrawalRequestStatus {
        uint256 gtETHAmount;
        uint256 ethAmount;
        address creator;
        uint256 createdAt;
        address recipient;
        uint256 claimedAt;
        bool isClaimed;
        bool isFinalized;
    }

    event WithdrawalRequested(address indexed owner, uint256 indexed requestId, uint256 gtETHAmount, uint256 ethAmount);
    event WithdrawalsFinalized(
        uint256 indexed firstRequestId,
        uint256 indexed lastRequestId,
        uint256 amountOfETH,
        uint256 shares,
        uint256 timestamp
    );
    event WithdrawalClaimed(address indexed owner, uint256 indexed requestId, uint256 ethAmount);

    function calcFinalize(uint256 _finalizeId) external view returns (uint256 etherToLockOnWithdrawalQueue, uint256 sharesToBurnFromWithdrawalQueue);
    function requestWithdrawal(uint256 _gtETHAmount, uint256 _eTHAmount, address _creator) external returns (uint256 requestId);
    function claimWithdrawal(uint256 _requestId, address _recipient) external;
    function getWithdrawalRequestStatus(uint256 _requestId) external view returns (WithdrawalRequestStatus memory);
    function getWithdrawalRequest(uint256 _requestId) external view returns (WithdrawalRequest memory);
    function finalize(uint256 _lastRequestIdToBeFinalized) external payable;
}