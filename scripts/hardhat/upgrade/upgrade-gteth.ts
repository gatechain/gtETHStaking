import { GTETH } from './../../../typechain-types/src/GTETH';
import { ethers, upgrades } from "hardhat";
import { GTETH__factory } from "../../../typechain-types";
import { updateContractDeployment, getContractDeployment } from "../utils/deploymentUtils";

async function main() {

  // 1. Upgrade GTETH
  console.log("\n--- Upgrading GTETH ---");

  const GTETHAddress = await getContractDeployment("GTETH");
  if (!GTETHAddress?.proxy) {
    throw new Error("GTETH is not deployed");
  }
  const GTETH = <GTETH__factory>(
    await ethers.getContractFactory("GTETH")
  );

  await upgrades.validateUpgrade(
    GTETHAddress.proxy,
    GTETH,
    {
      kind: "uups",
    }
  );

  const gteth = await upgrades.upgradeProxy(
    GTETHAddress.proxy,
    GTETH,
    {
      kind: "uups",
    }
  );

  await gteth.waitForDeployment();

  const address = await gteth.getAddress();
  console.log("GTETH proxy address:", address);
  console.log(
    "GTETH implementation address:",
    await upgrades.erc1967.getImplementationAddress(address)
  );

  // Save deployment info to file
  await updateContractDeployment("GTETH", {
    proxy: address,
    implementation: await upgrades.erc1967.getImplementationAddress(address),
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
