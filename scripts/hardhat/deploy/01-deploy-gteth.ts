import { ethers, upgrades } from "hardhat";
import { GTETH__factory } from "../../../typechain-types";
import { updateContractDeployment } from "../utils/deploymentUtils";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log(
    "Deployer balance:",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    "ETH"
  );

  // 1. Deploy GTETH
  console.log("\n--- Deploying GTETH ---");

  const GTETH_NAME = process.env.GTETH_NAME;
  const GTETH_SYMBOL = process.env.GTETH_SYMBOL;
  const initialOwner = deployer.address;
  const GTETH = <GTETH__factory>await ethers.getContractFactory("GTETH");
  const gteth = await upgrades.deployProxy(
    GTETH,
    [GTETH_NAME, GTETH_SYMBOL, initialOwner],
    {
      kind: "uups",
      initializer: "initialize",
    }
  );

  await gteth.waitForDeployment();
  const gtethAddress = await gteth.getAddress();
  const name = await gteth.name();
  const symbol = await gteth.symbol();
  const totalSupply = await gteth.totalSupply();
  console.log("GTETH name:", name);
  console.log("GTETH symbol:", symbol);
  console.log("GTETH totalSupply:", ethers.formatEther(totalSupply));
  console.log("GTETH proxy address:", gtethAddress);
  console.log(
    "GTETH implementation address:",
    await upgrades.erc1967.getImplementationAddress(gtethAddress)
  );

  // Save deployment info to file
  await updateContractDeployment("GTETH", {
    proxy: gtethAddress,
    implementation: await upgrades.erc1967.getImplementationAddress(
      gtethAddress
    ),
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
