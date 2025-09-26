// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IGTETH} from "./interfaces/IGTETH.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IWithdrawalQueueERC721} from "./interfaces/IWithdrawalQueueERC721.sol";
import {IWithdrawalVault} from "./interfaces/IWithdrawalVault.sol";
import {IExecutionLayerRewardsVault} from "./interfaces/IExecutionLayerRewardsVault.sol";
import {IGTETHLocator} from "./interfaces/IGTETHLocator.sol";
import {IStakingRouter} from "./interfaces/IStakingRouter.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Error} from "./lib/Error.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title GTETH Liquid Staking Token
 * @notice This contract implements the GTETH token, an ERC-20 liquid staking token
 * that represents a share of the total ETH staked in the protocol. Its value
 * appreciates as staking rewards accumulate. The conversion rate between ETH
 * and GTETH is determined by an external Oracle contract.
 *
 * The contract uses a shares-based model similar to ERC-4626. User balances
 * represent "shares," and the total underlying ETH ("assets") is tracked by the
 * oracle.
 */
contract GTETH is 
    IGTETH, 
    ERC20PermitUpgradeable,  
    ReentrancyGuardUpgradeable, 
    AccessControlUpgradeable, 
    PausableUpgradeable,
    UUPSUpgradeable
{

    // ================ state variables ================

    struct ProtocolState {
        uint256 bufferedETH;
        uint256 depositedValidators;
        uint256 clValidators;
        uint256 clBalance;
        uint256 pendingWithdrawals;
    }

    /**
     * @dev Intermediate data structure for `_handleOracleReport`
     * Helps to overcome `stack too deep` issue.
     */
    struct OracleReportContext {
        uint256 preCLValidators;
        uint256 preCLBalance;
        uint256 preTotalPooledEther;
        uint256 preTotalShares;
        uint256 etherToLockOnWithdrawalQueue;
        uint256 sharesToBurnFromWithdrawalQueue;
        uint256 sharesMintedAsFees;
    }

    /**
     * The structure is used to aggregate the `handleOracleReport` provided data.
     * @dev Using the in-memory structure addresses `stack too deep` issues.
     */
    struct OracleReportedData {
        // Oracle timings
        uint256 reportTimestamp;
        uint256 timeElapsed;
        // CL values
        uint256 clValidators;
        uint256 postCLBalance;
        // EL values
        uint256 withdrawalVaultBalance;
        uint256 elRewardsVaultBalance;
        // Decision about withdrawals processing
        uint256[] withdrawalFinalizationBatches;
    }

    /**
     * The structure is used to preload the contract using `getLidoLocator()` via single call
     */
    struct OracleReportContracts {
        address accountingOracle;
        address elRewardsVault;
        address oracleReportSanityChecker;
        address burner;
        address withdrawalQueue;
        address withdrawalVault;
        address postTokenRebaseReceiver;
    }

    /**
     * @dev Structure to store yield calculation data
     */
    struct YieldData {
        uint256 lastExchangeRate;     // Last recorded exchange rate
        uint256 lastTimestamp;        // Last recorded timestamp (0 means not initialized)
        uint256 yieldPerSecond;       // Yield per second (in PRECISION units, 1e18 = 100%)
    }


    // ================ constants ================
    bytes32 public constant DEPOSIT_SECURITY_MODULE_ROLE = keccak256("DEPOSIT_SECURITY_MODULE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    uint256 public constant PRECISION = 1e18; // 1:1 initial rate
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint256 public constant BASIS_POINTS = 10000;

    // ================ state variables ================
    ProtocolState public protocolState;
    IGTETHLocator public locator;
    mapping(address => bool) public blackList;
    mapping(uint256 => bool) public claimBlackList;
    
    // Yield calculation state variables
    YieldData public yieldData;
    uint256 public exchangeRateLimitPoint;
    uint256 public feePoint;

    receive() external payable nonReentrant whenNotPaused {
        if (msg.value > 0) {
            _submit();
        }
    }
    
    /**
     * @notice Initializes the GTETH token.
     * @param _name The name of the token (e.g., "Gemini Staked ETH").
     * @param _symbol The symbol of the token (e.g., "GTETH").
     * @param _initialOwner The address of the contract owner (e.g., StakingRouter).
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _initialOwner
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        // grant roles to the initial owner
        _grantRole(DEFAULT_ADMIN_ROLE, _initialOwner);
        _grantRole(DEPOSIT_SECURITY_MODULE_ROLE, _initialOwner);
        _grantRole(PAUSER_ROLE, _initialOwner);
        _grantRole(UPGRADER_ROLE, _initialOwner);

        // 1% exchange rate limit
        exchangeRateLimitPoint = 100;
        // 10% fee
        feePoint = 1000;
    }

    // ================ view functions ================
    function getAvailableBuffer() public view returns (uint256) {
        return protocolState.bufferedETH > protocolState.pendingWithdrawals ? protocolState.bufferedETH - protocolState.pendingWithdrawals : 0;
    }

    function getTotalPooledETH() public view returns (uint256) {
        return protocolState.bufferedETH + protocolState.clBalance + _getTransientBalance();
    }

    function getETHAmount(uint256 _gtETHAmount) external view returns (uint256) {
        return _getETHAmount(_gtETHAmount);
    }

    
    function getGTETHAmount(uint256 _ethAmount) external view returns (uint256) {
        return _getGTETHAmount(_ethAmount);
    }

    function getExchangeRate() external view returns (uint256) {
        return _getExchangeRate();
    }

    /**
     * @notice Get the current yield per second in PRECISION units
     * @return Current yield per second (1e18 = 100%)
     */
    function getYield() external view returns (uint256) {
        return yieldData.yieldPerSecond;
    }

    // ================ external functions ================
    function receiveELRewards() external payable {
        if (msg.sender != address(locator.elRewardsVault())) {
            revert Error.AppAuthFailed(msg.sender, locator.elRewardsVault());
        }
        if (msg.value == 0) {
            revert Error.NoRewardsToReceive();
        }
        protocolState.bufferedETH += msg.value;
        emit ReceiveELRewards(msg.value);
    }

    function receiveWithdrawals() external payable {
        if (msg.sender != address(locator.withdrawalVault())) {
            revert Error.AppAuthFailed(msg.sender, locator.withdrawalVault());
        }
        if (msg.value == 0) {
            revert Error.NoWithdrawalsToReceive();
        }
        protocolState.bufferedETH += msg.value;
        emit ReceiveWithdrawals(msg.value);
    }

    function submit() external payable nonReentrant whenNotPaused {
        _submit();
    }

    function withdraw(uint256 _gtETHAmount) external nonReentrant whenNotPaused {
        if (_gtETHAmount == 0) {
            revert Error.InvalidAmount();
        }

        // calculate the amount of ETH to withdraw
        uint256 ethAmount = _getETHAmount(_gtETHAmount);
        // lock the amount of GTETH
        _transfer(msg.sender, address(this), _gtETHAmount);
        // request withdrawal
        IWithdrawalQueueERC721 withdrawalQueueERC721 = IWithdrawalQueueERC721(locator.withdrawalQueueERC721());
        uint256 requestId = withdrawalQueueERC721.requestWithdrawal(_gtETHAmount, ethAmount, msg.sender);

        // update the protocol state
        protocolState.pendingWithdrawals += ethAmount;

        emit Withdraw(msg.sender, requestId, _gtETHAmount, ethAmount, block.timestamp);

    }

    function claim(uint256 _requestId) external nonReentrant whenNotPaused {
        if (claimBlackList[_requestId]) {
            revert Error.RequestBlackListed();
        }
        // Note: In a full implementation, this would interact with the WithdrawalQueueERC721 contract
        IWithdrawalQueueERC721 withdrawalQueueERC721 = IWithdrawalQueueERC721(locator.withdrawalQueueERC721());
        IWithdrawalQueueERC721.WithdrawalRequestStatus memory request = withdrawalQueueERC721.getWithdrawalRequestStatus(_requestId);
        if (request.isClaimed) {
            revert Error.RequestAlreadyClaimed();
        }
        withdrawalQueueERC721.claimWithdrawal(_requestId, msg.sender);
    }

      /**
     * @dev Invokes a deposit call to the Staking Router contract and updates buffered counters
     * @param _maxDepositsCount max deposits count
     * @param _stakingModuleId id of the staking module to be deposited
     * @param _depositCalldata module calldata
     */
    function deposit(uint256 _maxDepositsCount, uint256 _stakingModuleId, bytes calldata _depositCalldata) external nonReentrant onlyRole(DEPOSIT_SECURITY_MODULE_ROLE) whenNotPaused{
        IStakingRouter stakingRouter = IStakingRouter(locator.stakingRouter());
        uint256 depositsCount = Math.min(
            _maxDepositsCount,
            stakingRouter.getStakingModuleMaxDepositsCount(_stakingModuleId, getAvailableBuffer())
        );

        uint256 depositsValue;
        if (depositsCount > 0) {
            depositsValue = depositsCount * DEPOSIT_SIZE;
            // firstly update the local state of the contract to prevent a reentrancy attack,
            // even if the StakingRouter is a trusted contract.
            protocolState.bufferedETH = protocolState.bufferedETH - depositsValue;
            protocolState.depositedValidators += depositsCount;
            emit Unbuffered(depositsValue);
            emit DepositedValidatorsChanged(protocolState.depositedValidators);
        }

        // transfer ether to StakingRouter and make a deposit at the same time. All the ether
        // sent to StakingRouter is counted as deposited. If StakingRouter can't deposit all
        // passed ether it MUST revert the whole transaction (never happens in normal circumstances)
        stakingRouter.deposit{value: depositsValue}(depositsCount, _stakingModuleId, _depositCalldata);
    }

    function handleOracleReport(
        uint256 _reportTimestamp,
        uint256 _timeElapsed,
        uint256 _clValidators,
        uint256 _clBalance,
        uint256 _withdrawalVaultBalance,
        uint256 _elRewardsVaultBalance,
        uint256[] calldata _withdrawalFinalizationBatches
    ) external nonReentrant whenNotPaused {
         _handleOracleReport(
            OracleReportedData(
                _reportTimestamp,
                _timeElapsed,
                _clValidators,
                _clBalance,
                _withdrawalVaultBalance,
                _elRewardsVaultBalance,
                _withdrawalFinalizationBatches
            )
        );
    }

    // ================ internal functions ================
    function _getETHAmount(uint256 _gtETHAmount) internal view returns (uint256) {
        uint256 ethAmount = _gtETHAmount * _getExchangeRate() / PRECISION;
        return ethAmount;
    }

    function _getGTETHAmount(uint256 _ethAmount) internal view returns (uint256) {
        uint256 gtETHAmount = _ethAmount * PRECISION / _getExchangeRate();
        return gtETHAmount;
    }

    function _getExchangeRate() internal view returns (uint256) {
        uint256 supply = totalSupply();
        if (supply == 0) {
            return PRECISION; // 1:1 rate when no shares exist
        }
        return (getTotalPooledETH() * PRECISION) / supply;
    }

    function _submit() internal {
        if (msg.value == 0) {
            revert Error.NoETHToSubmit();
        }
        // get the amount of GTETH to mint
        uint256 gtETHAmount = _getGTETHAmount(msg.value);
        _mint(msg.sender, gtETHAmount);

        // update the protocol state
        protocolState.bufferedETH += msg.value;        
        emit Submit(msg.sender, msg.value);
    }

    function _update(address _from, address _to, uint256 _amount) internal virtual override {
        if (blackList[_from] || blackList[_to]) {
            revert Error.BlackListed();
        }
        super._update(_from, _to, _amount);
    }

    function _handleOracleReport(OracleReportedData memory _reportedData) internal {
        OracleReportContracts memory contracts = _loadOracleReportContracts();

        if (msg.sender != contracts.accountingOracle) {
            revert Error.AppAuthFailed(msg.sender, contracts.accountingOracle);
        }
        if (_reportedData.reportTimestamp > block.timestamp) {
            revert Error.InvalidReportTimestamp();
        }

        OracleReportContext memory reportContext;

        uint256 preExchangeRate = _getExchangeRate();

        // Step 1.
        // Take a snapshot of the current (pre-) state
        reportContext.preTotalPooledEther = getTotalPooledETH();
        reportContext.preTotalShares = totalSupply();
        reportContext.preCLValidators = protocolState.clValidators;
        reportContext.preCLBalance = _processClStateUpdate(
            _reportedData.reportTimestamp,
            reportContext.preCLValidators,
            _reportedData.clValidators,
            _reportedData.postCLBalance
        );

        if (_reportedData.withdrawalFinalizationBatches.length != 0) {
            IWithdrawalQueueERC721 withdrawalQueueERC721 = IWithdrawalQueueERC721(locator.withdrawalQueueERC721());
            (reportContext.etherToLockOnWithdrawalQueue, reportContext.sharesToBurnFromWithdrawalQueue) = withdrawalQueueERC721.calcFinalize(_reportedData.withdrawalFinalizationBatches[_reportedData.withdrawalFinalizationBatches.length - 1]);
        }

        // 2. Collect rewards and process withdrawals
        _collectRewardsAndProcessWithdrawals(
            contracts,
            _reportedData.withdrawalVaultBalance,
            _reportedData.elRewardsVaultBalance,
            _reportedData.withdrawalFinalizationBatches,
            reportContext.etherToLockOnWithdrawalQueue
        );

        emit ETHDistributed(
            _reportedData.reportTimestamp,
            reportContext.preCLBalance,
            _reportedData.postCLBalance,
            _reportedData.withdrawalVaultBalance,
            _reportedData.elRewardsVaultBalance,
            protocolState.bufferedETH
        );

        // 3. Distribute rewards
        _processRewards(
            reportContext,
            _reportedData.postCLBalance,
            _reportedData.withdrawalVaultBalance,
            _reportedData.elRewardsVaultBalance
        );

        // 4. Burn gteth
        if (reportContext.sharesToBurnFromWithdrawalQueue > 0) {
            _burn(address(this), reportContext.sharesToBurnFromWithdrawalQueue);
        }

        // 5. Update yield calculation
        _updateYieldData(_reportedData.reportTimestamp);

        // 6. check exchange rate
        uint256 postExchangeRate = _getExchangeRate();

        if (postExchangeRate < preExchangeRate) {
            revert Error.ExchangeRateDecreased();
        }

        if (postExchangeRate > preExchangeRate * (BASIS_POINTS + exchangeRateLimitPoint) / BASIS_POINTS) {
            revert Error.ExchangeRateLimitExceeded();
        }
        
    }

    /**
     * @dev calculate the amount of rewards and distribute it
     */
    function _processRewards(
        OracleReportContext memory _reportContext,
        uint256 _postCLBalance,
        uint256 _withdrawnWithdrawals,
        uint256 _withdrawnElRewards
    ) internal returns (uint256 sharesMintedAsFees) {
        uint256 postCLTotalBalance = _postCLBalance + _withdrawnWithdrawals;
        if (postCLTotalBalance > _reportContext.preCLBalance) {
            uint256 consensusLayerRewards = postCLTotalBalance - _reportContext.preCLBalance;

            sharesMintedAsFees = _distributeFee(
                _reportContext.preTotalPooledEther,
                _reportContext.preTotalShares,
                consensusLayerRewards + _withdrawnElRewards
            );
        }
    }

    /**
     * @dev Distributes fee portion of the rewards by minting and distributing corresponding amount of liquid tokens.
     * @param _preTotalPooledEther Total supply before report-induced changes applied
     * @param _preTotalShares Total shares before report-induced changes applied
     * @param _totalRewards Total rewards accrued both on the Execution Layer and the Consensus Layer sides in wei.
     */
    function _distributeFee(
        uint256 _preTotalPooledEther,
        uint256 _preTotalShares,
        uint256 _totalRewards
    ) internal returns (uint256 sharesMintedAsFees) {
        // calculate 10% of the rewards as fee
        uint256 totalFeeBasisPoints = feePoint; // 10% = 1000 basis points
        uint256 precisionPoints = BASIS_POINTS; // 100% = 10000 basis points
        
        if (totalFeeBasisPoints > 0 && _totalRewards > 0) {
            uint256 totalPooledEtherWithRewards = _preTotalPooledEther + _totalRewards;

            // 计算需要铸造的份额数量
            sharesMintedAsFees = (_totalRewards * totalFeeBasisPoints * _preTotalShares) / 
                (totalPooledEtherWithRewards * precisionPoints - (_totalRewards * totalFeeBasisPoints));

            // 获取奖励分配信息
            (
                address[] memory recipients,
                uint256[] memory stakingModuleIds,
                uint96[] memory stakingModuleFees,
                uint96 totalFee,
            ) = IStakingRouter(locator.stakingRouter()).getStakingRewardsDistribution();

            if (sharesMintedAsFees > 0 && totalFee > 0) {
                // 铸造GTETH给费用接收者
                _mint(address(this), sharesMintedAsFees);

                // 获取质押路由器
                IStakingRouter router = IStakingRouter(locator.stakingRouter());


                // 计算各模块的奖励
                uint256[] memory moduleRewards = new uint256[](stakingModuleIds.length);
                uint256 totalModuleRewards = 0;

                for (uint256 i = 0; i < stakingModuleIds.length; i++) {
                    moduleRewards[i] = (sharesMintedAsFees * stakingModuleFees[i]) / totalFee;
                    totalModuleRewards += moduleRewards[i];
                }

                // 转移模块奖励
                for (uint256 i = 0; i < recipients.length; i++) {
                    if (moduleRewards[i] > 0) {
                        _transfer(address(this), recipients[i], moduleRewards[i]);
                    }
                }

                // 转移国库奖励（剩余部分）
                uint256 treasuryRewards = sharesMintedAsFees - totalModuleRewards;
                if (treasuryRewards > 0) {
                    _transfer(address(this), locator.treasury(), treasuryRewards);
                }

                // 通知路由器奖励已铸造
                router.reportRewardsMinted(stakingModuleIds, moduleRewards);
                
            }
        }
    }

    /**
     * @dev collect ETH from ELRewardsVault and WithdrawalVault, then send to WithdrawalQueue
     */
    function _collectRewardsAndProcessWithdrawals(
        OracleReportContracts memory _contracts,
        uint256 _withdrawalsToWithdraw,
        uint256 _elRewardsToWithdraw,
        uint256[] memory _withdrawalFinalizationBatches,
        uint256 _etherToLockOnWithdrawalQueue
    ) internal {
        // withdraw execution layer rewards and put them to the buffer
        if (_elRewardsToWithdraw > 0) {
            IExecutionLayerRewardsVault(_contracts.elRewardsVault).withdrawRewards(_elRewardsToWithdraw);
        }

        // withdraw withdrawals and put them to the buffer
        if (_withdrawalsToWithdraw > 0) {
            IWithdrawalVault(_contracts.withdrawalVault).withdrawWithdrawals(_withdrawalsToWithdraw);
        }

        // finalize withdrawals (send ether, assign shares for burning)
        if (_etherToLockOnWithdrawalQueue > 0) {
            IWithdrawalQueueERC721 withdrawalQueue = IWithdrawalQueueERC721(_contracts.withdrawalQueue);
            // Note: finalize function needs to be added to IWithdrawalQueueERC721 interface
            withdrawalQueue.finalize{value: _etherToLockOnWithdrawalQueue}(
                _withdrawalFinalizationBatches[_withdrawalFinalizationBatches.length - 1]
            );
        }

        uint256 postBufferedEther = protocolState.bufferedETH - _etherToLockOnWithdrawalQueue;
        protocolState.pendingWithdrawals -= _etherToLockOnWithdrawalQueue;

        protocolState.bufferedETH = postBufferedEther;
    }

    /**
     * @dev Load the contracts used for `handleOracleReport` internally.
     */
    function _loadOracleReportContracts() internal view returns (OracleReportContracts memory ret) {
        ret.accountingOracle = locator.accountingOracle();
        ret.elRewardsVault = locator.elRewardsVault();
        ret.withdrawalQueue = locator.withdrawalQueueERC721();
        ret.withdrawalVault = locator.withdrawalVault();
    }

    function _processClStateUpdate(
        uint256 _reportTimestamp,
        uint256 _preClValidators,
        uint256 _postClValidators,
        uint256 _postClBalance
    ) internal returns (uint256 preCLBalance) {
        uint256 depositedValidators = protocolState.depositedValidators;
        if (_postClValidators > depositedValidators) {
            revert Error.ReportedMoreDeposited();
        }
        if (_postClValidators < _preClValidators) {
            revert Error.ReportedLessValidators();
        }

        if (_postClValidators > _preClValidators) {
            protocolState.clValidators = _postClValidators;
        }

        uint256 appearedValidators = _postClValidators - _preClValidators;
        preCLBalance = protocolState.clBalance;
        // Take into account the balance of the newly appeared validators
        preCLBalance = preCLBalance + appearedValidators * DEPOSIT_SIZE;

        // Save the current CL balance and validators to
        // calculate rewards on the next push
        protocolState.clBalance = _postClBalance;

        emit CLValidatorsUpdated(_reportTimestamp, _preClValidators, _postClValidators);
    }

    /// @dev Calculates and returns the total base balance (multiple of 32) of validators in transient state,
    ///     i.e. submitted to the official Deposit contract but not yet visible in the CL state.
    /// @return transient balance in wei (1e-18 Ether)
    function _getTransientBalance() internal view returns (uint256) {
        uint256 depositedValidators = protocolState.depositedValidators;
        uint256 clValidators = protocolState.clValidators;
        // clValidators can never be less than deposited ones.
        assert(depositedValidators >= clValidators);
        return (depositedValidators - clValidators) * DEPOSIT_SIZE;
    }

    /**
     * @dev Update yield data based on current exchange rate and timestamp
     * @param _timestamp The current timestamp (from oracle report)
     */
    function _updateYieldData(uint256 _timestamp) internal {
        uint256 currentExchangeRate = _getExchangeRate();
        
        if (yieldData.lastTimestamp == 0) {
            // Initialize yield data
            yieldData.lastExchangeRate = currentExchangeRate;
            yieldData.lastTimestamp = _timestamp;
            yieldData.yieldPerSecond = 0;
            return;
        }

        // Calculate yield per second based on exchange rate change over time
        uint256 timeElapsed = _timestamp - yieldData.lastTimestamp;
        
        if (timeElapsed > 0 && yieldData.lastExchangeRate > 0) {
            // Calculate the rate of change in exchange rate
            // periodReturn = (new_rate / old_rate) - 1
            uint256 periodReturn = (currentExchangeRate * PRECISION) / yieldData.lastExchangeRate;
            
            // Only calculate yield if exchange rate increased (periodReturn >= PRECISION)
            // If exchange rate decreased (due to slashing, adjustments, etc.), set yield to 0
            if (periodReturn >= PRECISION) {
                uint256 periodReturnBasisPoints = periodReturn - PRECISION;
                
                // Calculate yield per second: periodReturn / timeElapsed
                uint256 yieldPerSecond = periodReturnBasisPoints / timeElapsed;
                
                // Store the yield per second calculated at this oracle report
                yieldData.yieldPerSecond = yieldPerSecond;
            } else {
                // Exchange rate decreased, set yield to 0 (no negative yield)
                yieldData.yieldPerSecond = 0;
            }
        }

        // Update last recorded values
        yieldData.lastExchangeRate = currentExchangeRate;
        yieldData.lastTimestamp = _timestamp;
    }

    // ================ governance functions ================
    function setGTETHLocator(address _gtETHLocator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        locator = IGTETHLocator(_gtETHLocator);
    }

    function setClaimBlackList(uint256 _requestId, bool _isBlackListed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        claimBlackList[_requestId] = _isBlackListed;
    }

    function setBlackList(address _address, bool _isBlackListed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        blackList[_address] = _isBlackListed;
    }

    function setExchangeRateLimit(uint256 _exchangeRateLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_exchangeRateLimit > BASIS_POINTS) {
            revert Error.InvalidExchangeRateLimit();
        }
        exchangeRateLimitPoint = _exchangeRateLimit;
    }

    function setFeePoint(uint256 _feePoint) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_feePoint > BASIS_POINTS) {
            revert Error.InvalidFeePoint();
        }
        feePoint = _feePoint;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Authorize upgrade for UUPS proxy
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {
        // Can add additional upgrade validation logic here
    }
}