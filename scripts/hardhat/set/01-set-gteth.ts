import { ethers, upgrades } from "hardhat";
import { GTETH } from "../../../typechain-types";
import {
  updateContractDeployment,
  getContractDeployment,
} from "../utils/deploymentUtils";

async function main() {
  const gteth = await getContractDeployment("GTETH");
  if (!gteth?.proxy) {
    throw new Error("GTETH is not deployed");
  }

  const gtethLocator = await getContractDeployment("GTETHLocator");
  if (!gtethLocator?.address) {
    throw new Error("GTETHLocator is not deployed");
  }

  const gtethProxy = <GTETH>await ethers.getContractAt("GTETH", gteth.proxy);
  const locator = await gtethProxy.locator();

  if (locator !== gtethLocator.address) {
    console.log("Setting GTETH locator");
    await gtethProxy.setGTETHLocator(gtethLocator.address);
  } else {
    console.log("GTETH locator is already set");
  }

  let roles = process.env.GTETH_ROLE_DEFAULT_ADMIN_ROLE!.split(",");
  for (const role of roles) {
    const defaultAdminRole = await gtethProxy.DEFAULT_ADMIN_ROLE();
    const hasRole = await gtethProxy.hasRole(defaultAdminRole, role);
    if (!hasRole) {
      console.log("Setting GTETH default admin role");
      await gtethProxy.grantRole(defaultAdminRole, role);
    } else {
      console.log("GTETH default admin role is already set");
    }
  }

  roles = process.env.GTETH_ROLE_PAUSER_ROLE!.split(",");
  for (const role of roles) {
    const pauserRole = await gtethProxy.PAUSER_ROLE();
    const hasRole = await gtethProxy.hasRole(pauserRole, role);
    if (!hasRole) {
      console.log("Setting GTETH pauser role");
      await gtethProxy.grantRole(pauserRole, role);
    } else {
      console.log("GTETH pauser role is already set");
    }
  }

  roles = process.env.GTETH_ROLE_DEPOSIT_SECURITY_MODULE_ROLE!.split(",");
  for (const role of roles) {
    const depositSecurityModuleRole =
      await gtethProxy.DEPOSIT_SECURITY_MODULE_ROLE();
    const hasRole = await gtethProxy.hasRole(depositSecurityModuleRole, role);
    if (!hasRole) {
      console.log("Setting GTETH deposit security module role");
      await gtethProxy.grantRole(depositSecurityModuleRole, role);
    } else {
      console.log("GTETH deposit security module role is already set");
    }
  }

  roles = process.env.GTETH_ROLE_UPGRADER_ROLE!.split(",");
  for (const role of roles) {
    const upgraderRole = await gtethProxy.UPGRADER_ROLE();
    const hasRole = await gtethProxy.hasRole(upgraderRole, role);
    if (!hasRole) {
      console.log("Setting GTETH upgrader role");
      await gtethProxy.grantRole(upgraderRole, role);
    } else {
      console.log("GTETH upgrader role is already set");
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
