import { ethers, upgrades } from "hardhat";
import { WithdrawalQueueERC721__factory } from "../../../typechain-types";
import { updateContractDeployment, getContractDeployment } from "../utils/deploymentUtils";

async function main() {

  // 1. Upgrade withdrawalQueueERC721
  console.log("\n--- Upgrading withdrawalQueueERC721 ---");

  const WithdrawalQueueERC721Address = await getContractDeployment("WithdrawalQueueERC721");
  if (!WithdrawalQueueERC721Address?.proxy) {
    throw new Error("WithdrawalQueueERC721 is not deployed");
  }
  const WithdrawalQueueERC721 = <WithdrawalQueueERC721__factory>(
    await ethers.getContractFactory("WithdrawalQueueERC721")
  );

  await upgrades.validateUpgrade(
    WithdrawalQueueERC721Address.proxy,
    WithdrawalQueueERC721,
    {
      kind: "uups",
    }
  );

  const withdrawalQueueERC721 = await upgrades.upgradeProxy(
    WithdrawalQueueERC721Address.proxy,
    WithdrawalQueueERC721,
    {
      kind: "uups",
    }
  );

  await withdrawalQueueERC721.waitForDeployment();

  const address = await withdrawalQueueERC721.getAddress();
  console.log("WithdrawalQueueERC721 proxy address:", address);
  console.log(
    "WithdrawalQueueERC721 implementation address:",
    await upgrades.erc1967.getImplementationAddress(address)
  );

  // Save deployment info to file
  await updateContractDeployment("WithdrawalQueueERC721", {
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
