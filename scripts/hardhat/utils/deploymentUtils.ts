import { ethers } from "hardhat";
import * as fs from "fs";
import * as path from "path";

export interface DeploymentInfo {
  [contractName: string]: {
    proxy?: string;
    implementation?: string;
    address?: string;
    constructorArguments?: any[];
  };
}

/**
 * Read deployment configuration file
 * @param networkName Network name
 * @returns Deployment info object
 */
export async function readDeploymentConfig(networkName?: string): Promise<DeploymentInfo> {
  const network = networkName || (await ethers.provider.getNetwork()).name;
  const deploymentPath = path.join(__dirname, '../../deployments');
  const fileName = `deployment-${network}.json`;
  const filePath = path.join(deploymentPath, fileName);

  if (fs.existsSync(filePath)) {
    try {
      const existingData = fs.readFileSync(filePath, 'utf8');
      const deploymentInfo = JSON.parse(existingData);
      console.log(`📖 Reading existing deployment config (${network}):`, Object.keys(deploymentInfo));
      return deploymentInfo;
    } catch (error) {
      console.warn(`⚠️  Failed to read existing deployment config (${network}):`, error instanceof Error ? error.message : String(error));
      return {};
    }
  } else {
    console.log(`📝 Deployment config file does not exist (${network}), will create new config`);
    return {};
  }
}

/**
 * Save deployment configuration file
 * @param deploymentInfo Deployment info object
 * @param networkName Network name
 */
export async function saveDeploymentConfig(
  deploymentInfo: DeploymentInfo, 
  networkName?: string
): Promise<string> {
  const network = networkName || (await ethers.provider.getNetwork()).name;
  const deploymentPath = path.join(__dirname, '../../deployments');
  
  // Ensure directory exists
  if (!fs.existsSync(deploymentPath)) {
    fs.mkdirSync(deploymentPath, { recursive: true });
  }
  
  const fileName = `deployment-${network}.json`;
  const filePath = path.join(deploymentPath, fileName);

  // Save deployment info
  fs.writeFileSync(filePath, JSON.stringify(deploymentInfo, null, 2));
  
  console.log(`✅ Deployment info saved to: ${filePath}`);
  console.log(`📋 Currently deployed contracts: ${Object.keys(deploymentInfo).join(', ')}`);
  
  return filePath;
}

/**
 * Update specific contract deployment info
 * @param contractName Contract name
 * @param contractInfo Contract info
 * @param networkName Network name
 */
export async function updateContractDeployment(
  contractName: string,
  contractInfo: {
    proxy?: string;
    implementation?: string;
    address?: string;
    constructorArguments?: any;
  },
  networkName?: string
): Promise<void> {
  // Read existing config
  const deploymentInfo = await readDeploymentConfig(networkName);
  
  // Update specific contract info
  deploymentInfo[contractName] = {
    ...deploymentInfo[contractName], // Keep existing info
    ...contractInfo, // Update with new info
  };
  
  // Save updated config
  await saveDeploymentConfig(deploymentInfo, networkName);
}

/**
 * Get contract deployment info
 * @param contractName Contract name
 * @param networkName Network name
 * @returns Contract deployment info
 */
export async function getContractDeployment(
  contractName: string,
  networkName?: string
): Promise<{
  proxy?: string;
  implementation?: string;
  address?: string;
} | null> {
  const deploymentInfo = await readDeploymentConfig(networkName);
  return deploymentInfo[contractName] || null;
}

/**
 * Check if contract is deployed
 * @param contractName Contract name
 * @param networkName Network name
 * @returns Whether contract is deployed
 */
export async function isContractDeployed(
  contractName: string,
  networkName?: string
): Promise<boolean> {
  const contractInfo = await getContractDeployment(contractName, networkName);
  return !!(contractInfo?.proxy || contractInfo?.address);
}
