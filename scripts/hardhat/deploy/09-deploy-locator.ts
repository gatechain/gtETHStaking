import { ethers } from "hardhat";

import { GTETHLocator__factory, IGTETHLocator } from "../../../typechain-types";
import {
  updateContractDeployment,
  getContractDeployment,
} from "../utils/deploymentUtils";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log(
    "Deployer balance:",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    "ETH"
  );

  // 1. Deploy GTETHLocator
  console.log("\n--- Deploying GTETHLocator ---");

  const GTETH = await getContractDeployment("GTETH");
  const STAKING_ROUTER = await getContractDeployment("StakingRouter");
  const NODE_OPERATORS_REGISTRY = await getContractDeployment(
    "NodeOperatorsRegistry"
  );
  const WITHDRAWAL_QUEUE_ERC721 = await getContractDeployment(
    "WithdrawalQueueERC721"
  );
  const WITHDRAWAL_VAULT = await getContractDeployment("WithdrawalVault");
  const ACCOUNTING_ORACLE = await getContractDeployment("AccountingOracle");
  const EL_REWARDS_VAULT = await getContractDeployment(
    "ExecutionLayerRewardsVault"
  );
  const VALIDATORS_EXIT_BUS_ORACLE = await getContractDeployment(
    "ValidatorsExitBusOracle"
  );
  const TREASURY = process.env.TREASURY;
  if (!GTETH?.proxy) {
    throw new Error("GTETH is not deployed");
  }
  if (!STAKING_ROUTER?.proxy) {
    throw new Error("STAKING_ROUTER is not deployed");
  }

  if (!NODE_OPERATORS_REGISTRY?.proxy) {
    throw new Error("NODE_OPERATORS_REGISTRY is not deployed");
  }
  if (!WITHDRAWAL_QUEUE_ERC721?.proxy) {
    throw new Error("WITHDRAWAL_QUEUE_ERC721 is not deployed");
  }
  if (!WITHDRAWAL_VAULT?.address) {
    throw new Error("WITHDRAWAL_VAULT is not deployed");
  }
  if (!ACCOUNTING_ORACLE?.proxy) {
    throw new Error("ACCOUNTING_ORACLE is not deployed");
  }
  if (!EL_REWARDS_VAULT?.address) {
    throw new Error("EL_REWARDS_VAULT is not deployed");
  }
  if (!VALIDATORS_EXIT_BUS_ORACLE?.proxy) {
    throw new Error("VALIDATORS_EXIT_BUS_ORACLE is not deployed");
  }

  if (!TREASURY) {
    throw new Error("TREASURY is not set");
  }

  const GTETHLocatorFactory = <GTETHLocator__factory>(
    await ethers.getContractFactory("GTETHLocator")
  );
  const constructorArguments = {
    gteth: GTETH.proxy,
    stakingRouter: STAKING_ROUTER.proxy,
    nodeOperatorsRegistry: NODE_OPERATORS_REGISTRY.proxy,
    withdrawalQueueERC721: WITHDRAWAL_QUEUE_ERC721.proxy,
    withdrawalVault: WITHDRAWAL_VAULT.address,
    accountingOracle: ACCOUNTING_ORACLE.proxy,
    elRewardsVault: EL_REWARDS_VAULT.address,
    validatorsExitBusOracle: VALIDATORS_EXIT_BUS_ORACLE.proxy,
    treasury: TREASURY,
  };

  const gtethLocator = await GTETHLocatorFactory.deploy(constructorArguments);

  await gtethLocator.waitForDeployment();
  const address = await gtethLocator.getAddress();
  console.log("GTETHLocator proxy address:", address);

  // Save deployment info to file
  await updateContractDeployment("GTETHLocator", {
    address: address,
    constructorArguments: constructorArguments,
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
