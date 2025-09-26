// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IGTETHLocator
 * @notice Interface for GTETH service locator
 */
interface IGTETHLocator {

    struct Config {
        address gteth;                          // GTETH token contract
        address stakingRouter;                  // Staking router contract
        address nodeOperatorsRegistry;          // Node operators registry
        address withdrawalQueueERC721;          // Withdrawal queue ERC721 contract
        address withdrawalVault;                // Withdrawal vault contract
        address accountingOracle;               // Accounting oracle contract
        address elRewardsVault;                 // EL rewards vault contract
        address validatorsExitBusOracle;        // Validators exit bus oracle contract
        address treasury;                       // Treasury contract
    }
    

    // Individual component getters
    function treasury() external view returns (address);
    function gteth() external view returns (address);
    function stakingRouter() external view returns (address);
    function nodeOperatorsRegistry() external view returns (address);
    function withdrawalQueueERC721() external view returns (address);
    function withdrawalVault() external view returns (address);
    function accountingOracle() external view returns (address);
    function elRewardsVault() external view returns (address);
    function validatorsExitBusOracle() external view returns (address);

    function setConfig(Config calldata config) external;
} 