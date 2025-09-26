import { ethers, upgrades } from "hardhat";

import { ValidatorsExitBusOracle__factory } from "../../../typechain-types";
import { updateContractDeployment } from "../utils/deploymentUtils";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log(
    "Deployer balance:",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    "ETH"
  );

  // 1. Deploy ValidatorsExitBusOracle
  console.log("\n--- Deploying ValidatorsExitBusOracle ---");
  const SlotsPerEpoch = process.env.SLOTS_PER_EPOCH;
  const SecondsPerSlot = process.env.SECONDS_PER_SLOT;
  const GenesisTime = process.env.GENESIS_TIME;
  const OracleMember = process.env.ORACLE_MEMBER;
  const LastProcessingRefSlot = process.env.LAST_PROCESSING_REF_SLOT;
  const EpochsPerFrame = process.env.EPOCHS_PER_FRAME;

  const ValidatorsExitBusOracle = <ValidatorsExitBusOracle__factory>(
    await ethers.getContractFactory("ValidatorsExitBusOracle")
  );
  const validatorsExitBusOracle = await upgrades.deployProxy(
    ValidatorsExitBusOracle,
    [
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

  await validatorsExitBusOracle.waitForDeployment();
  const address = await validatorsExitBusOracle.getAddress();
  console.log("ValidatorsExitBusOracle proxy address:", address);
  console.log(
    "ValidatorsExitBusOracle implementation address:",
    await upgrades.erc1967.getImplementationAddress(address)
  );

  // Save deployment info to file
  await updateContractDeployment("ValidatorsExitBusOracle", {
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
