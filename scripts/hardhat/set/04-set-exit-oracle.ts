import { ethers, upgrades } from "hardhat";
import { ValidatorsExitBusOracle } from "../../../typechain-types";
import {
  getContractDeployment,
} from "../utils/deploymentUtils";

async function main() {
  const [deployer] = await ethers.getSigners();
  const validatorsExitBusOracle = await getContractDeployment(
    "ValidatorsExitBusOracle"
  );
  if (!validatorsExitBusOracle?.proxy) {
    throw new Error("ValidatorsExitBusOracle is not deployed");
  }

  const validatorsExitBusOracleProxy = <ValidatorsExitBusOracle>(
    await ethers.getContractAt(
      "ValidatorsExitBusOracle",
      validatorsExitBusOracle.proxy
    )
  );


  let hasRole = await validatorsExitBusOracleProxy.hasRole(await validatorsExitBusOracleProxy.RESUME_ROLE(), deployer.address);
  if (!hasRole) {
    console.log("Setting ValidatorsExitBusOracle resume role");
    await validatorsExitBusOracleProxy.grantRole(await validatorsExitBusOracleProxy.RESUME_ROLE(), deployer.address);
  } else {
    console.log("ValidatorsExitBusOracle resume role is already set");
  }

  const initialEpoch = process.env.INITIAL_EPOCH!;
  const frameConfig = await validatorsExitBusOracleProxy.getFrameConfig();
  if (frameConfig.initialEpoch > Number(initialEpoch)) {
    console.log("Setting ValidatorsExitBusOracle initialEpoch", initialEpoch);
    await validatorsExitBusOracleProxy.updateInitialEpoch(initialEpoch);
    await validatorsExitBusOracleProxy.resume();
  } else {
    console.log("ValidatorsExitBusOracle initialEpoch is already set");
  }

  let roles = process.env.ORACLE_ROLE_DEFAULT_ADMIN_ROLE!.split(",");
  for (const role of roles) {
    const defaultAdminRole = await validatorsExitBusOracleProxy.DEFAULT_ADMIN_ROLE();
    const hasRole = await validatorsExitBusOracleProxy.hasRole(defaultAdminRole, role);
    if (!hasRole) {
      console.log("Setting ValidatorsExitBusOracle default admin role");
      await validatorsExitBusOracleProxy.grantRole(defaultAdminRole, role);
    } else {
      console.log("ValidatorsExitBusOracle default admin role is already set");
    }
  }

  roles = process.env.ORACLE_ROLE_MANAGE_ORACLE_MEMBER_ROLE!.split(",");
  for (const role of roles) {
    const manageOracleMemberRole = await validatorsExitBusOracleProxy.MANAGE_ORACLE_MEMBER_ROLE();
    const hasRole = await validatorsExitBusOracleProxy.hasRole(manageOracleMemberRole, role);
    if (!hasRole) {
      console.log("Setting ValidatorsExitBusOracle manageOracleMemberRole");
      await validatorsExitBusOracleProxy.grantRole(manageOracleMemberRole, role);
    } else {
      console.log("ValidatorsExitBusOracle manageOracleMemberRole is already set");
    }
  }

  roles = process.env.ORACLE_ROLE_MANAGE_FRAME_CONFIG_ROLE!.split(",");
  for (const role of roles) {
    const manageFrameConfigRole = await validatorsExitBusOracleProxy.MANAGE_FRAME_CONFIG_ROLE();
    const hasRole = await validatorsExitBusOracleProxy.hasRole(manageFrameConfigRole, role);
    if (!hasRole) {
      console.log("Setting ValidatorsExitBusOracle manageFrameConfigRole");
      await validatorsExitBusOracleProxy.grantRole(manageFrameConfigRole, role);
    } else {
      console.log("ValidatorsExitBusOracle manageFrameConfigRole is already set");
    }
  }

  roles = process.env.ORACLE_ROLE_SUBMIT_DATA_ROLE!.split(",");
  for (const role of roles) {
    const submitDataRole = await validatorsExitBusOracleProxy.SUBMIT_DATA_ROLE();
    const hasRole = await validatorsExitBusOracleProxy.hasRole(submitDataRole, role);
    if (!hasRole) {
      console.log("Setting ValidatorsExitBusOracle submitDataRole");
      await validatorsExitBusOracleProxy.grantRole(submitDataRole, role);
    } else {
      console.log("ValidatorsExitBusOracle submitDataRole is already set");
    }
  }

  roles = process.env.ORACLE_ROLE_PAUSE_ROLE!.split(",");
  for (const role of roles) {
    const pauseRole = await validatorsExitBusOracleProxy.PAUSE_ROLE();
    const hasRole = await validatorsExitBusOracleProxy.hasRole(pauseRole, role);
    if (!hasRole) {
      console.log("Setting ValidatorsExitBusOracle pauseRole");
      await validatorsExitBusOracleProxy.grantRole(pauseRole, role);
    } else {
      console.log("ValidatorsExitBusOracle pauseRole is already set");
    }
  }

  roles = process.env.ORACLE_ROLE_RESUME_ROLE!.split(",");
  for (const role of roles) {
    const resumeRole = await validatorsExitBusOracleProxy.RESUME_ROLE();
    const hasRole = await validatorsExitBusOracleProxy.hasRole(resumeRole, role);
    if (!hasRole) {
      console.log("Setting ValidatorsExitBusOracle resumeRole");
      await validatorsExitBusOracleProxy.grantRole(resumeRole, role);
    } else {
      console.log("ValidatorsExitBusOracle resumeRole is already set");
    }
  }

  roles = process.env.ORACLE_ROLE_UPGRADER_ROLE!.split(",");
  for (const role of roles) {
    const upgraderRole = await validatorsExitBusOracleProxy.UPGRADER_ROLE();
    const hasRole = await validatorsExitBusOracleProxy.hasRole(upgraderRole, role);
    if (!hasRole) {
      console.log("Setting ValidatorsExitBusOracle upgraderRole");
      await validatorsExitBusOracleProxy.grantRole(upgraderRole, role);
    } else {
      console.log("ValidatorsExitBusOracle upgraderRole is already set");
    }
  }

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
