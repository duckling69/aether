import { defineConfig, configVariable } from "hardhat/config";
import hardhatIgnition from "@nomicfoundation/hardhat-ignition";
import hardhatIgnitionEthers from "@nomicfoundation/hardhat-ignition-ethers";
import hardhatEthers from "@nomicfoundation/hardhat-ethers";
import hardhatKeystore from "@nomicfoundation/hardhat-keystore";

export default defineConfig({
  plugins: [hardhatKeystore, hardhatEthers, hardhatIgnition, hardhatIgnitionEthers],
  // Aether hardhat config (Arbitrum focus)
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true,
    },
    npmFilesToBuild: [
      "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol",
      "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol",
    ],
  },
  networks: {
    development: {
      type: "edr-simulated",
      chainType: "l1",
    },
    robinhoodTestnet: {
      type: "http",
      url: process.env.ROBINHOOD_RPC_URL || "https://example.invalid",
      chainId: Number(process.env.ROBINHOOD_CHAIN_ID || 46630),
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [],
    },
    arbitrumSepolia: {
      type: "http",
      url: process.env.ARBITRUM_RPC_URL || "https://arbitrum-sepolia.publicnode.com",
      chainId: Number(process.env.ARBITRUM_CHAIN_ID || 421614),
      accounts: process.env.DEPLOYER_PRIVATE_KEY ? [process.env.DEPLOYER_PRIVATE_KEY] : [],
    },
  },
});
