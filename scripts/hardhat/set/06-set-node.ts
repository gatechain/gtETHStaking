import { ethers, upgrades } from "hardhat";
import { NodeOperatorsRegistry } from "../../../typechain-types";
import {
  getContractDeployment,
} from "../utils/deploymentUtils";

async function main() {
  // const [deployer] = await ethers.getSigners();
  const nodeOperatorsRegistry = await getContractDeployment(
    "NodeOperatorsRegistry"
  );
  if (!nodeOperatorsRegistry?.proxy) {
    throw new Error("NodeOperatorsRegistry is not deployed");
  }

  const stakingRouter = await getContractDeployment(
    "StakingRouter"
  );
  if (!stakingRouter?.proxy) {
    throw new Error("StakingRouter is not deployed");
  }

  const nodeOperatorsRegistryProxy = <NodeOperatorsRegistry>(
    await ethers.getContractAt(
      "NodeOperatorsRegistry",
      nodeOperatorsRegistry.proxy
    )
  );

  // await nodeOperatorsRegistryProxy.grantRole(await nodeOperatorsRegistryProxy.SET_NODE_OPERATOR_LIMIT_ROLE(), deployer.address);
  // await nodeOperatorsRegistryProxy.setNodeOperatorStakingLimit(0, 1000000);


  const STAKING_ROUTER_ROLE = await nodeOperatorsRegistryProxy.STAKING_ROUTER_ROLE();
  if (!await nodeOperatorsRegistryProxy.hasRole(STAKING_ROUTER_ROLE, stakingRouter.proxy)) {
    console.log("Setting NodeOperatorsRegistry STAKING_ROUTER_ROLE for StakingRouter");
    await nodeOperatorsRegistryProxy.grantRole(STAKING_ROUTER_ROLE, stakingRouter.proxy);
  } else {
    console.log("NodeOperatorsRegistry STAKING_ROUTER_ROLE for StakingRouter is already set");
  }

  const locator = await getContractDeployment(
    "GTETHLocator"
  );
  if (!locator?.address) {
    throw new Error("GTETHLocator is not deployed");
  }
  if (locator.address !== await nodeOperatorsRegistryProxy.locator()) {
    await nodeOperatorsRegistryProxy.setLocator(locator.address);
    console.log("Setting NodeOperatorsRegistry locator");
  } else {
    console.log("NodeOperatorsRegistry locator is already set");
  }

  let roles = process.env.NODE_ROLE_DEFAULT_ADMIN_ROLE!.split(",");
  for (const role of roles) {
    const defaultAdminRole = await nodeOperatorsRegistryProxy.DEFAULT_ADMIN_ROLE();
    const hasRole = await nodeOperatorsRegistryProxy.hasRole(defaultAdminRole, role);
    if (!hasRole) {
      console.log("Setting NodeOperatorsRegistry default admin role");
      await nodeOperatorsRegistryProxy.grantRole(defaultAdminRole, role);
    } else {
      console.log("NodeOperatorsRegistry default admin role is already set");
    }
  }

  roles = process.env.NODE_ROLE_MANAGE_NODE_OPERATOR_ROLE!.split(",");
  for (const role of roles) {
    const manageNodeOperatorRole = await nodeOperatorsRegistryProxy.MANAGE_NODE_OPERATOR_ROLE();
    const hasRole = await nodeOperatorsRegistryProxy.hasRole(manageNodeOperatorRole, role);
    if (!hasRole) {
      console.log("Setting NodeOperatorsRegistry manageNodeOperatorRole");
      await nodeOperatorsRegistryProxy.grantRole(manageNodeOperatorRole, role);
    } else {
      console.log("NodeOperatorsRegistry manageNodeOperatorRole is already set");
    }
  }

  roles = process.env.NODE_ROLE_MANAGE_SIGNING_KEYS!.split(",");
  for (const role of roles) {
    const manageSigningKeysRole = await nodeOperatorsRegistryProxy.MANAGE_SIGNING_KEYS();
    const hasRole = await nodeOperatorsRegistryProxy.hasRole(manageSigningKeysRole, role);
    if (!hasRole) {
      console.log("Setting NodeOperatorsRegistry manageSigningKeysRole");
      await nodeOperatorsRegistryProxy.grantRole(manageSigningKeysRole, role);
    } else {
      console.log("NodeOperatorsRegistry manageSigningKeysRole is already set");
    }
  }

  roles = process.env.NODE_ROLE_SET_NODE_OPERATOR_LIMIT_ROLE!.split(",");
  for (const role of roles) {
    const setNodeOperatorLimitRole = await nodeOperatorsRegistryProxy.SET_NODE_OPERATOR_LIMIT_ROLE();
    const hasRole = await nodeOperatorsRegistryProxy.hasRole(setNodeOperatorLimitRole, role);
    if (!hasRole) {
      console.log("Setting NodeOperatorsRegistry setNodeOperatorLimitRole");
      await nodeOperatorsRegistryProxy.grantRole(setNodeOperatorLimitRole, role);
    } else {
      console.log("NodeOperatorsRegistry setNodeOperatorLimitRole is already set");
    }
  }

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
