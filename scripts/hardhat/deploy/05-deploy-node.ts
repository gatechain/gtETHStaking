import { ethers, upgrades } from "hardhat";

import { NodeOperatorsRegistry__factory } from "../../../typechain-types";
import { updateContractDeployment } from "../utils/deploymentUtils";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log(
    "Deployer balance:",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    "ETH"
  );

  // 1. Deploy NodeOperatorsRegistry
  console.log("\n--- Deploying NodeOperatorsRegistry ---");
  const initialOwner = deployer.address;
  const NodeOperatorsRegistry = <NodeOperatorsRegistry__factory>(
    await ethers.getContractFactory("NodeOperatorsRegistry")
  );
  const nodeOperatorsRegistry = await upgrades.deployProxy(
    NodeOperatorsRegistry,
    [ethers.encodeBytes32String("GTETH"), 7 * 24 * 3600, initialOwner],
    {
      kind: "uups",
      initializer: "initialize",
    }
  );

  await nodeOperatorsRegistry.waitForDeployment();
  const address = await nodeOperatorsRegistry.getAddress();
  console.log("NodeOperatorsRegistry proxy address:", address);
  console.log(
    "NodeOperatorsRegistry implementation address:",
    await upgrades.erc1967.getImplementationAddress(address)
  );

  // Save deployment info to file
  await updateContractDeployment("NodeOperatorsRegistry", {
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
