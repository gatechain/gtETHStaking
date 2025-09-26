import { Address } from '../../../typechain-types/@openzeppelin/contracts/utils/Address';
import { ethers, upgrades } from "hardhat";

import { StakingRouter__factory } from "../../../typechain-types";
import { updateContractDeployment, getContractDeployment } from "../utils/deploymentUtils";

async function main() {
  
  const [deployer] = await ethers.getSigners();
  console.log("Deployer address:", deployer.address);
  console.log("Deployer balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH");

  const GTETH = await getContractDeployment("GTETH");
  if (!GTETH?.proxy) {
    throw new Error("GTETH is not deployed");
  }

  const WithdrawalVault = await getContractDeployment("WithdrawalVault");
  if (!WithdrawalVault?.address) {
    throw new Error("WithdrawalVault is not deployed");
  }

  const withdrawalCredentialsOrigin = ethers.zeroPadValue(WithdrawalVault.address, 32);
  const withdrawalCredentials = "0x01" + withdrawalCredentialsOrigin.slice(4)

  // 1. Deploy StakingRouter
  console.log("\n--- Deploying StakingRouter ---");

  const initialOwner = deployer.address;
  const gtETHAddress = GTETH.proxy;
  const STAKING_ROUTER_DEPOSIT_CONTRACT = process.env.STAKING_ROUTER_DEPOSIT_CONTRACT;
  if (!STAKING_ROUTER_DEPOSIT_CONTRACT) {
    throw new Error("STAKING_ROUTER_DEPOSIT_CONTRACT is not set");
  }

  const StakingRouter = <StakingRouter__factory> await ethers.getContractFactory("StakingRouter");
  const stakingRouter = await upgrades.deployProxy(StakingRouter, [
    initialOwner,
    gtETHAddress,
    STAKING_ROUTER_DEPOSIT_CONTRACT,
    withdrawalCredentials,
  ], {
    kind: 'uups',
    initializer: 'initialize'
  });
  
  await stakingRouter.waitForDeployment();
  const address = await stakingRouter.getAddress();
  console.log("StakingRouter proxy address:", address);
  console.log("StakingRouter implementation address:", await upgrades.erc1967.getImplementationAddress(address));

  
  // Save deployment info to file
  await updateContractDeployment("StakingRouter", {
    proxy: address,
    implementation: await upgrades.erc1967.getImplementationAddress(address)
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

