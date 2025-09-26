import { ethers, upgrades } from "hardhat";
import { AccountingOracle__factory } from "../../../typechain-types";
import {
  getContractDeployment,
  updateContractDeployment,
} from "../utils/deploymentUtils";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log(
    "Deployer balance:",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    "ETH"
  );

  // 1. Deploy AccountingOracle
  console.log("\n--- Deploying AccountingOracle ---");

  const GTETH = await getContractDeployment("GTETH");
  if (!GTETH?.proxy) {
    throw new Error("GTETH is not deployed");
  }
  const GTETHAddress = GTETH.proxy;
  // not deploy Locator contract set by deployed
  const Locator = GTETH.proxy;
  const SlotsPerEpoch = process.env.SLOTS_PER_EPOCH;
  const SecondsPerSlot = process.env.SECONDS_PER_SLOT;
  const GenesisTime = process.env.GENESIS_TIME;
  const OracleMember = process.env.ORACLE_MEMBER;
  const LastProcessingRefSlot = process.env.LAST_PROCESSING_REF_SLOT;
  const EpochsPerFrame = process.env.EPOCHS_PER_FRAME;

  const AccountingOracle = <AccountingOracle__factory>(
    await ethers.getContractFactory("AccountingOracle")
  );
  const accountingOracle = await upgrades.deployProxy(
    AccountingOracle,
    [
      Locator,
      GTETHAddress,
      SlotsPerEpoch,
      SecondsPerSlot,
      GenesisTime,
      OracleMember,
      LastProcessingRefSlot,
      EpochsPerFrame,
    ],
    {
      kind: "uups",
      initializer: "initialize",
    }
  );

  await accountingOracle.waitForDeployment();
  const address = await accountingOracle.getAddress();
  console.log("AccountingOracle proxy address:", address);
  console.log(
    "AccountingOracle implementation address:",
    await upgrades.erc1967.getImplementationAddress(address)
  );

  // Save deployment info to file
  await updateContractDeployment("AccountingOracle", {
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
