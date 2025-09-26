// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Error
/// @notice 错误定义
/// @dev 提供常用的错误定义
library Error {

    // ================ GTETH ================
    error NoRewardsToReceive();
    error NoWithdrawalsToReceive();
    error NoETHToReceive();
    error NoETHToSubmit();
    error InvalidAmount();
    error NoETHToWithdraw(uint256 amount);
    error NoETHToRefillBuffer(uint256 amount);
    error BlackListed();
    error AppAuthFailed(address sender, address expected);
    error InvalidReportTimestamp();
    error ReportedMoreDeposited();
    error ReportedLessValidators();
    error RequestBlackListed();
    error InvalidExchangeRateLimit();
    error InvalidFeePoint();
    error ExchangeRateLimitExceeded();
    error ExchangeRateDecreased();

    // ================ WithdrawalQueueERC721 ================
    error InvalidRequestId(uint256 requestId);
    error TooMuchEtherToFinalize(uint256 amount, uint256 maxAmount);
    error RequestNotFinalized();
    error NotTheOwnerOfTheRequest();
    error RequestAlreadyClaimed();
    error TransferFailed();

    // ================ Base Oracle ================
    error AddressCannotBeZero(); 
    error InvalidChainConfig();
    error NumericOverflow();
    error InitialEpochIsYetToArrive();
    error InitialEpochAlreadyArrived();
    error EpochsPerFrameCannotBeZero();
    error RefSlotMustBeGreaterThanProcessingOne(uint256 refSlot, uint256 processingRefSlot); 
    error RefSlotCannotDecrease(uint256 refSlot, uint256 prevRefSlot); 
    error NoConsensusReportToProcess(); 
    error ProcessingDeadlineMissed(uint256 deadline); 
    error RefSlotAlreadyProcessing(); 
    error UnexpectedRefSlot(uint256 consensusRefSlot, uint256 dataRefSlot); 
    error UnexpectedConsensusVersion(uint256 expectedVersion, uint256 receivedVersion); 
    error HashCannotBeZero(); 
    error UnexpectedDataHash(bytes32 consensusHash, bytes32 receivedHash); 
    error SecondsPerSlotCannotBeZero(); 
    error GenesisTimeCannotBeZero(); 
    error InvalidSlot();
    error EmptyReport();
    error StaleReport();
    error NonMember();
    
    error SenderNotAllowed();

    // ================ AccountingOracle ================
    error GTETHCannotBeZero();
    error GTETHLocatorCannotBeZero();
    error InvalidExitedValidatorsData();
    error UnsupportedExtraDataFormat(uint256 format);
    error UnsupportedExtraDataType(uint256 itemIndex, uint256 dataType);
    error CannotSubmitExtraDataBeforeMainData();
    error ExtraDataAlreadyProcessed();
    error UnexpectedExtraDataHash(bytes32 consensusHash, bytes32 receivedHash);
    error UnexpectedExtraDataFormat(
        uint256 expectedFormat,
        uint256 receivedFormat
    );
    error ExtraDataItemsCountCannotBeZeroForNonEmptyData();
    error ExtraDataHashCannotBeZeroForNonEmptyData();
    error UnexpectedExtraDataItemsCount(
        uint256 expectedCount,
        uint256 receivedCount
    );
    error UnexpectedExtraDataIndex(
        uint256 expectedIndex,
        uint256 receivedIndex
    );
    error InvalidExtraDataItem(uint256 itemIndex);
    error InvalidExtraDataSortOrder(uint256 itemIndex);
    error InvalidSlotsElapsed();

    // ================ ValidatorsExitBusOracle ================
    
    error AdminCannotBeZero();
    error UnsupportedRequestsDataFormat(uint256 format); 
    error InvalidRequestsData(); 
    error InvalidRequestsDataLength(); 
    error UnexpectedRequestsDataLength(); 
    error InvalidRequestsDataSortOrder(); 
    error ArgumentOutOfBounds(); 
    error NodeOpValidatorIndexMustIncrease( 
        uint256 moduleId,         
        uint256 nodeOpId,         
        uint256 prevRequestedValidatorIndex,  
        uint256 requestedValidatorIndex       
    );
}