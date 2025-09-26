// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IGTETH {
    // ================ events ================
    event Submit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 requestId, uint256 gtETHAmount, uint256 ethAmount, uint256 timestamp);
    event SubmitBuffer(address indexed user, uint256 amount);
    event HandleOracleReport(uint256[] postRebaseAmounts);
    event ReceiveELRewards(uint256 amount);
    event ReceiveWithdrawals(uint256 amount);
    event BufferInsufficient(uint256 amount, uint256 timestamp);
    event Unbuffered(uint256 ethAmount);
    event DepositedValidatorsChanged(uint256 depositedValidators);
    event CLValidatorsUpdated(uint256 timestamp, uint256 preCLValidators, uint256 postCLValidators);
    // Emits when oracle accounting report processed
    event ETHDistributed(
        uint256 indexed reportTimestamp,
        uint256 preCLBalance,
        uint256 postCLBalance,
        uint256 withdrawalsWithdrawn,
        uint256 executionLayerRewardsWithdrawn,
        uint256 postBufferedEther
    );


    // ================ core functions ================
    // Submit ETH to the contract
    function submit() external payable;

    // Withdraw ETH from the contract
    function withdraw(uint256 _gtETHAmount) external;

    // Handle the oracle report
    function handleOracleReport(
        // Oracle timings
        uint256 _reportTimestamp,
        uint256 _timeElapsed,
        // CL values
        uint256 _clValidators,
        uint256 _clBalance,
        // EL values
        uint256 _withdrawalVaultBalance,
        uint256 _elRewardsVaultBalance,
        // Decision about withdrawals processing
        uint256[] calldata _withdrawalFinalizationBatches
    ) external;

    // Get the current share rate
    function receiveELRewards() external payable;

    // Receive withdrawals
    function receiveWithdrawals() external payable;

    // ================ view functions ================

    function getETHAmount(uint256 _gtETHAmount) external view returns(uint256);

    function getGTETHAmount(uint256 _ethAmount) external view returns(uint256);

    function deposit(uint256 _maxDepositsCount, uint256 _stakingModuleId, bytes calldata _depositCalldata) external;

}

