// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import {GTETHLocator} from "../src/GTETHLocator.sol";
import {IGTETHLocator} from "../src/interfaces/IGTETHLocator.sol";

contract DeployLocator is Script {
    uint256 internal deployerPrivateKey;
    address internal gteth = 0xA5b68cE84F12c55ACAC70dEbB46A064624951554;
    address internal stakingRouter = 0xcd59e12Ed51108568f8963a12959b5d6447B32AD;
    address internal nodeOperatorsRegistry = 0x98162c710AF37B63207847d45808684D0e4742bb;
    address internal withdrawalQueueERC721 = 0xc0675B6Cb094F395281B7deF89c26AEa6444F1F8;
    address internal withdrawalVault = 0x80EcEfF963F04558893C232988D4D1F5D42F3633;
    address internal accountingOracle = 0xAdd4D91Ca960032611D35D7a7d1Df4C3386838E5;
    address internal elRewardsVault = 0x42E27c9d456D969392e6cf790e649682654EDE00;
    address internal treasury = 0x03b2349fb8e6D6d13fa399880cE79750721E99D5;
    address internal validatorsExitBusOracle = 0x322542F6dAcf6f5428Ad912BD71d762F255248AF;

    IGTETHLocator.Config config = IGTETHLocator.Config({
        gteth: gteth,
        stakingRouter: stakingRouter,
        nodeOperatorsRegistry: nodeOperatorsRegistry,
        withdrawalQueueERC721: withdrawalQueueERC721,
        withdrawalVault: withdrawalVault,
        accountingOracle: accountingOracle,
        elRewardsVault: elRewardsVault,
        validatorsExitBusOracle: validatorsExitBusOracle,
        treasury: treasury
    });

    address internal locator = 0x42Aa599CD3db948f2d66F7dc14135804d0DBe1c7;

    function run() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY3");

        vm.startBroadcast(deployerPrivateKey);
        // GTETHLocator locator = new GTETHLocator(config);
        // console.log("GTETHLocator deployed at:", address(locator));

        // update contract address
        // GTETHLocator.Config memory config2 = GTETHLocator(locator).config();
        // config2.accountingOracle = 0xAdd4D91Ca960032611D35D7a7d1Df4C3386838E5;
        IGTETHLocator(locator).setConfig(config);

        vm.stopBroadcast();
    }
}