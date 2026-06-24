/**
 * Token config for Arbitrum Sepolia — Aether demo market (mock Ondo RWAs).
 *
 * Tokens deployed via ArbitrumDeploymentModule Ignition module.
 * Addresses updated after deployment.
 */

export const CHAIN_ID = 421614;

export const RPC_URL = "https://arbitrum-sepolia.publicnode.com";
export const EXPLORER_URL = "https://sepolia-explorer.arbitrum.io";

export const tokens = {
  USDC: {
    address: "0xe3611967ea9b4C874Edf99079c30FC4ecb877d20",
    name: "USDC",
    symbol: "USDC",
    decimals: 6,
    category: "stablecoin",
    priceUsd: 1,
    borrowingEnabled: true,
    collateralEnabled: false,
    supplyRateBps: 320,
    borrowRateBps: 500,
    ltvBps: 0,
    liquidationThresholdBps: 0,
    liquidationBonusBps: 0,
  },
  OUSG: {
    address: "0x825422622894FfAc56939808A107715d4816e359",
    name: "Ondo Short-Term US Gov Bond",
    symbol: "OUSG",
    decimals: 18,
    category: "rwa",
    priceUsd: 100_00000000,
    borrowingEnabled: false,
    collateralEnabled: true,
    supplyRateBps: 0,
    borrowRateBps: 0,
    ltvBps: 7500,
    liquidationThresholdBps: 8000,
    liquidationBonusBps: 500,
  },
  USDY: {
    address: "0x7Be8e67f6ff18D47d1A6e28DA14a1008E739D7Db",
    name: "Ondo US Dollar Yield",
    symbol: "USDY",
    decimals: 18,
    category: "rwa",
    priceUsd: 105_00000000,
    borrowingEnabled: false,
    collateralEnabled: true,
    supplyRateBps: 0,
    borrowRateBps: 0,
    ltvBps: 7000,
    liquidationThresholdBps: 7500,
    liquidationBonusBps: 500,
  },
};

export const WETH = "";
