import { ethers, upgrades } from "hardhat";
import { AccountingOracle } from "../../../typechain-types";
import {
  getContractDeployment,
} from "../utils/deploymentUtils";

async function main() {
  const [deployer] = await ethers.getSigners();
  const accountingOracle = await getContractDeployment(
    "AccountingOracle"
  );
  if (!accountingOracle?.proxy) {
    throw new Error("AccountingOracle is not deployed");
  }

  const gtethLocator = await getContractDeployment("GTETHLocator");
  if (!gtethLocator?.address) {
    throw new Error("GTETHLocator is not deployed");
  }

  const accountingOracleProxy = <AccountingOracle>(
    await ethers.getContractAt(
      "AccountingOracle",
      accountingOracle.proxy
    )
  );

  if (accountingOracleProxy.LOCATOR() !== gtethLocator.address) {
    console.log("Setting AccountingOracle locator");
    await accountingOracleProxy.setLOCATOR(gtethLocator.address);
  } else {
    console.log("AccountingOracle locator is already set");
  }

  let hasRole = await accountingOracleProxy.hasRole(await accountingOracleProxy.RESUME_ROLE(), deployer.address);
  if (!hasRole) {
    console.log("Setting AccountingOracle resume role");
    await accountingOracleProxy.grantRole(await accountingOracleProxy.RESUME_ROLE(), deployer.address);
  } else {
    console.log("AccountingOracle resume role is already set");
  }

  const initialEpoch = process.env.INITIAL_EPOCH!;
  const frameConfig = await accountingOracleProxy.getFrameConfig();
  if (frameConfig.initialEpoch > Number(initialEpoch)) {
    console.log("Setting AccountingOracle initialEpoch", initialEpoch);
    await accountingOracleProxy.updateInitialEpoch(initialEpoch);
    await accountingOracleProxy.resume();
  } else {
    console.log("AccountingOracle initialEpoch is already set");
  }

  let roles = process.env.ORACLE_ROLE_DEFAULT_ADMIN_ROLE!.split(",");
  for (const role of roles) {
    const defaultAdminRole = await accountingOracleProxy.DEFAULT_ADMIN_ROLE();
    const hasRole = await accountingOracleProxy.hasRole(defaultAdminRole, role);
    if (!hasRole) {
      console.log("Setting AccountingOracle default admin role");
      await accountingOracleProxy.grantRole(defaultAdminRole, role);
    } else {
      console.log("AccountingOracle default admin role is already set");
    }
  }

  roles = process.env.ORACLE_ROLE_MANAGE_ORACLE_MEMBER_ROLE!.split(",");
  for (const role of roles) {
    const manageOracleMemberRole = await accountingOracleProxy.MANAGE_ORACLE_MEMBER_ROLE();
    const hasRole = await accountingOracleProxy.hasRole(manageOracleMemberRole, role);
    if (!hasRole) {
      console.log("Setting AccountingOracle manageOracleMemberRole");
      await accountingOracleProxy.grantRole(manageOracleMemberRole, role);
    } else {
      console.log("AccountingOracle manageOracleMemberRole is already set");
    }
  }

  roles = process.env.ORACLE_ROLE_MANAGE_FRAME_CONFIG_ROLE!.split(",");
  for (const role of roles) {
    const manageFrameConfigRole = await accountingOracleProxy.MANAGE_FRAME_CONFIG_ROLE();
    const hasRole = await accountingOracleProxy.hasRole(manageFrameConfigRole, role);
    if (!hasRole) {
      console.log("Setting AccountingOracle manageFrameConfigRole");
      await accountingOracleProxy.grantRole(manageFrameConfigRole, role);
    } else {
      console.log("AccountingOracle manageFrameConfigRole is already set");
    }
  }

  roles = process.env.ORACLE_ROLE_SUBMIT_DATA_ROLE!.split(",");
  for (const role of roles) {
    const submitDataRole = await accountingOracleProxy.SUBMIT_DATA_ROLE();
    const hasRole = await accountingOracleProxy.hasRole(submitDataRole, role);
    if (!hasRole) {
      console.log("Setting AccountingOracle submitDataRole");
      await accountingOracleProxy.grantRole(submitDataRole, role);
    } else {
      console.log("AccountingOracle submitDataRole is already set");
    }
  }

  roles = process.env.ORACLE_ROLE_PAUSE_ROLE!.split(",");
  for (const role of roles) {
    const pauseRole = await accountingOracleProxy.PAUSE_ROLE();
    const hasRole = await accountingOracleProxy.hasRole(pauseRole, role);
    if (!hasRole) {
      console.log("Setting AccountingOracle pauseRole");
      await accountingOracleProxy.grantRole(pauseRole, role);
    } else {
      console.log("AccountingOracle pauseRole is already set");
    }
  }

  roles = process.env.ORACLE_ROLE_RESUME_ROLE!.split(",");
  for (const role of roles) {
    const resumeRole = await accountingOracleProxy.RESUME_ROLE();
    const hasRole = await accountingOracleProxy.hasRole(resumeRole, role);
    if (!hasRole) {
      console.log("Setting AccountingOracle resumeRole");
      await accountingOracleProxy.grantRole(resumeRole, role);
    } else {
      console.log("AccountingOracle resumeRole is already set");
    }
  }

  roles = process.env.ORACLE_ROLE_UPGRADER_ROLE!.split(",");
  for (const role of roles) {
    const upgraderRole = await accountingOracleProxy.UPGRADER_ROLE();
    const hasRole = await accountingOracleProxy.hasRole(upgraderRole, role);
    if (!hasRole) {
      console.log("Setting AccountingOracle upgraderRole");
      await accountingOracleProxy.grantRole(upgraderRole, role);
    } else {
      console.log("AccountingOracle upgraderRole is already set");
    }
  }

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
