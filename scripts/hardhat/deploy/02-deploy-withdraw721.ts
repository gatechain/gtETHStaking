import { ethers, upgrades } from "hardhat";
import { WithdrawalQueueERC721__factory } from "../../../typechain-types";
import { updateContractDeployment } from "../utils/deploymentUtils";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log(
    "Deployer balance:",
    ethers.formatEther(await ethers.provider.getBalance(deployer.address)),
    "ETH"
  );

  // 1. Deploy withdrawalQueueERC721
  console.log("\n--- Deploying withdrawalQueueERC721 ---");

  const GTETH_721_NAME = process.env.GTETH_721_NAME;
  const GTETH_721_SYMBOL = process.env.GTETH_721_SYMBOL;
  const initialOwner = deployer.address;
  const WithdrawalQueueERC721 = <WithdrawalQueueERC721__factory>(
    await ethers.getContractFactory("WithdrawalQueueERC721")
  );
  const withdrawalQueueERC721 = await upgrades.deployProxy(
    WithdrawalQueueERC721,
    [GTETH_721_NAME, GTETH_721_SYMBOL, initialOwner],
    {
      kind: "uups",
      initializer: "initialize",
    }
  );

  await withdrawalQueueERC721.waitForDeployment();
  const name = await withdrawalQueueERC721.name();
  const symbol = await withdrawalQueueERC721.symbol();
  console.log("WithdrawalQueueERC721 name:", name);
  console.log("WithdrawalQueueERC721 symbol:", symbol);
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
