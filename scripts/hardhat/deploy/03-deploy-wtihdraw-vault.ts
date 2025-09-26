import { ethers, upgrades } from "hardhat";
import { WithdrawalVault__factory } from "../../../typechain-types";
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
  console.log("\n--- Deploying withdrawalVault ---");

  const TREASURY = process.env.TREASURY;
  const GTETH = await getContractDeployment("GTETH");

  if (!GTETH?.proxy) {
    throw new Error("GTETH is not deployed");
  }

  if (!TREASURY) {
    throw new Error("TREASURY is not set");
  }

  const WithdrawalVaultFactory = <WithdrawalVault__factory>(
    await ethers.getContractFactory("WithdrawalVault")
  );
  const constructorArguments: [string, string] = [GTETH.proxy, TREASURY];
  const withdrawalVault = await WithdrawalVaultFactory.deploy(
    ...constructorArguments
  );

  await withdrawalVault.waitForDeployment();
  const address = await withdrawalVault.getAddress();
  console.log("WithdrawalVault proxy address:", address);

  // Save deployment info to file
  await updateContractDeployment("WithdrawalVault", {
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
