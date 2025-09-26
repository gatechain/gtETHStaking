import { ethers, upgrades } from "hardhat";
import { StakingRouter } from "../../../typechain-types";
import {
  getContractDeployment,
} from "../utils/deploymentUtils";

async function main() {
  const stakingRouter = await getContractDeployment(
    "StakingRouter"
  );
  const gteth = await getContractDeployment(
    "GTETH"
  );
  const accountingOracle = await getContractDeployment(
    "AccountingOracle"
  );
  if (!stakingRouter?.proxy) {
    throw new Error("StakingRouter is not deployed");
  }

  if (!gteth?.proxy) {
    throw new Error("GTETH is not deployed");
  }
  if (!accountingOracle?.proxy) {
    throw new Error("AccountingOracle is not deployed");
  }

  const stakingRouterProxy = <StakingRouter>(
    await ethers.getContractAt(
      "StakingRouter",
      stakingRouter.proxy
    )
  );

  const REPORT_REWARDS_MINTED_ROLE = await stakingRouterProxy.REPORT_REWARDS_MINTED_ROLE();
  if (!await stakingRouterProxy.hasRole(REPORT_REWARDS_MINTED_ROLE, gteth.proxy)) {
    console.log("Setting StakingRouter REPORT_REWARDS_MINTED_ROLE for GTETH");
    await stakingRouterProxy.grantRole(REPORT_REWARDS_MINTED_ROLE, gteth.proxy);
  } else {
    console.log("StakingRouter REPORT_REWARDS_MINTED_ROLE for GTETH is already set");
  }

  const REPORT_EXITED_VALIDATORS_ROLE = await stakingRouterProxy.REPORT_EXITED_VALIDATORS_ROLE();
  if (!await stakingRouterProxy.hasRole(REPORT_EXITED_VALIDATORS_ROLE, accountingOracle.proxy)) {
    console.log("Setting StakingRouter REPORT_EXITED_VALIDATORS_ROLE for AccountingOracle");
    await stakingRouterProxy.grantRole(REPORT_EXITED_VALIDATORS_ROLE, accountingOracle.proxy);
  } else {
    console.log("StakingRouter REPORT_EXITED_VALIDATORS_ROLE for AccountingOracle is already set");
  }

  let roles = process.env.STAKING_ROUTER_ROLE_DEFAULT_ADMIN_ROLE!.split(",");
  for (const role of roles) {
    const defaultAdminRole = await stakingRouterProxy.DEFAULT_ADMIN_ROLE();
    const hasRole = await stakingRouterProxy.hasRole(defaultAdminRole, role);
    if (!hasRole) {
      console.log("Setting StakingRouter default admin role");
      await stakingRouterProxy.grantRole(defaultAdminRole, role);
    } else {
      console.log("StakingRouter default admin role is already set");
    }
  }

  roles = process.env.STAKING_ROUTER_ROLE_MANAGE_WITHDRAWAL_CREDENTIALS_ROLE!.split(",");
  for (const role of roles) {
    const manageWithdrawalCredentialsRole = await stakingRouterProxy.MANAGE_WITHDRAWAL_CREDENTIALS_ROLE();
    const hasRole = await stakingRouterProxy.hasRole(manageWithdrawalCredentialsRole, role);
    if (!hasRole) {
      console.log("Setting StakingRouter manageWithdrawalCredentialsRole");
      await stakingRouterProxy.grantRole(manageWithdrawalCredentialsRole, role);
    } else {
      console.log("StakingRouter manageWithdrawalCredentialsRole is already set");
    }
  }

  roles = process.env.STAKING_ROUTER_ROLE_STAKING_MODULE_MANAGE_ROLE!.split(",");
  for (const role of roles) {
    const stakingModuleManageRole = await stakingRouterProxy.STAKING_MODULE_MANAGE_ROLE();
    const hasRole = await stakingRouterProxy.hasRole(stakingModuleManageRole, role);
    if (!hasRole) {
      console.log("Setting StakingRouter stakingModuleManageRole");
      await stakingRouterProxy.grantRole(stakingModuleManageRole, role);
    } else {
      console.log("StakingRouter stakingModuleManageRole is already set");
    }
  }

  roles = process.env.STAKING_ROUTER_ROLE_PAUSER_ROLE!.split(",");
  for (const role of roles) {
    const pauserRole = await stakingRouterProxy.PAUSER_ROLE();
    const hasRole = await stakingRouterProxy.hasRole(pauserRole, role);
    if (!hasRole) {
      console.log("Setting StakingRouter pauserRole");
      await stakingRouterProxy.grantRole(pauserRole, role);
    } else {
      console.log("StakingRouter pauserRole is already set");
    }
  }
 
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
