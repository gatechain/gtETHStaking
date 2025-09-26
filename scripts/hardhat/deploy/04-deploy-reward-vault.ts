import { ethers } from "hardhat";

import { ExecutionLayerRewardsVault__factory } from "../../../typechain-types";
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

  // 1. Deploy withdrawalVault
  console.log("\n--- Deploying ExecutionLayerRewardsVault ---");

  const TREASURY = process.env.TREASURY;
  const GTETH = await getContractDeployment("GTETH");

  if (!GTETH?.proxy) {
    throw new Error("GTETH is not deployed");
  }

  if (!TREASURY) {
    throw new Error("TREASURY is not set");
  }

  const ExecutionLayerRewardsVaultFactory = <
    ExecutionLayerRewardsVault__factory
  >await ethers.getContractFactory("ExecutionLayerRewardsVault");
  const constructorArguments: [string, string] = [GTETH.proxy, TREASURY];
  const executionLayerRewardsVault =
    await ExecutionLayerRewardsVaultFactory.deploy(...constructorArguments);

  await executionLayerRewardsVault.waitForDeployment();
  const address = await executionLayerRewardsVault.getAddress();
  console.log("ExecutionLayerRewardsVault proxy address:", address);

  // Save deployment info to file
  await updateContractDeployment("ExecutionLayerRewardsVault", {
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
