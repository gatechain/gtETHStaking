// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IGTETHLocator} from "./interfaces/IGTETHLocator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GTETHLocator
 * @notice GTETH service locator
 * @dev configuration is stored as public immutables to reduce gas consumption
 */
contract GTETHLocator is IGTETHLocator ,Ownable{

    error ZeroAddress();

    Config public config;

    // ================================ 服务地址 ================================
    address public gteth;
    address public stakingRouter;
    address public nodeOperatorsRegistry;
    address public withdrawalQueueERC721;
    address public withdrawalVault;
    address public accountingOracle;
    address public elRewardsVault;
    address public validatorsExitBusOracle;
    address public treasury;

    /**
     * @notice declare service locations
     * @dev accepts a struct to avoid the "stack-too-deep" error
     * @param _config struct of addresses
     */
    constructor(Config memory _config) Ownable(msg.sender) {
        config = _config;
        gteth = _assertNonZero(_config.gteth);
        accountingOracle = _assertNonZero(_config.accountingOracle);
        elRewardsVault = _assertNonZero(_config.elRewardsVault);    
        withdrawalVault = _assertNonZero(_config.withdrawalVault);
        stakingRouter = _assertNonZero(_config.stakingRouter);
        nodeOperatorsRegistry = _assertNonZero(_config.nodeOperatorsRegistry);
        withdrawalQueueERC721 = _assertNonZero(_config.withdrawalQueueERC721);
        validatorsExitBusOracle = _assertNonZero(_config.validatorsExitBusOracle);
        treasury = _assertNonZero(_config.treasury);
    }

    function _assertNonZero(address _address) internal pure returns (address) {
        if (_address == address(0)) revert ZeroAddress();
        return _address;
    }

    // ================================ 管理员函数 ================================
    // 管理员可以修改服务地址 debug 使用
    function setConfig(Config memory _config) external onlyOwner {
        config = _config;
        gteth = _assertNonZero(_config.gteth);
        accountingOracle = _assertNonZero(_config.accountingOracle);
        elRewardsVault = _assertNonZero(_config.elRewardsVault);    
        withdrawalVault = _assertNonZero(_config.withdrawalVault);
        stakingRouter = _assertNonZero(_config.stakingRouter);
        nodeOperatorsRegistry = _assertNonZero(_config.nodeOperatorsRegistry);
        withdrawalQueueERC721 = _assertNonZero(_config.withdrawalQueueERC721);
        validatorsExitBusOracle = _assertNonZero(_config.validatorsExitBusOracle);
        treasury = _assertNonZero(_config.treasury);
    }
}
