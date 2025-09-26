import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import "solidity-coverage";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.30",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true, // 解决 Stack too deep 错误
    },
  },
  
  networks: {
    hardhat: {
      chainId: 31337,
      forking: process.env.MAINNET_RPC_URL ? {
        url: process.env.MAINNET_RPC_URL,
        blockNumber: process.env.FORK_BLOCK_NUMBER ? parseInt(process.env.FORK_BLOCK_NUMBER) : undefined,
      } : undefined,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 31337,
    },
    goerli: {
      url: process.env.GOERLI_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY3 ? [process.env.PRIVATE_KEY3] : [],
      chainId: 5,
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY3 ? [process.env.PRIVATE_KEY3] : [],
      chainId: 11155111,
    },
    mainnet: {
      url: process.env.MAINNET_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY3 ? [process.env.PRIVATE_KEY3] : [],
      chainId: 1,
    },
    hoodi: {
      url: process.env.HOODI_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY3 ? [process.env.PRIVATE_KEY3] : [],
      chainId: 560048,
    },
  },

  // Foundry 集成配置
  paths: {
    sources: "./src",
    tests: "./test",
    cache: "./cache_hardhat",
    artifacts: "./artifacts",
  },

  // Gas 报告配置
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    gasPrice: 20,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  },

  // 合约大小检查
  contractSizer: {
    alphaSort: true,
    runOnCompile: false,
    disambiguatePaths: false,
  },

  // Etherscan 验证配置
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      goerli: process.env.ETHERSCAN_API_KEY || "",
      sepolia: process.env.ETHERSCAN_API_KEY || "",
    },
  },

  // TypeChain 配置
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
  },

  // Mocha 测试配置
  mocha: {
    timeout: 40000,
  },
};

export default config; 