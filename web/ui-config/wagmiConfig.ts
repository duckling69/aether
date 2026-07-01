import { Emitter } from '@wagmi/core/internal';
import { getDefaultConfig } from 'connectkit';
import {
  FORK_BASE_CHAIN_ID,
  FORK_CHAIN_ID,
  FORK_ENABLED,
  FORK_RPC_URL,
  networkConfigs,
} from 'utils/marketsAndNetworksConfig';
import { type Chain } from 'viem';
import { createConfig, http, type Transport } from 'wagmi';
import { injected, safe } from 'wagmi/connectors';

import { prodNetworkConfig, testnetConfig } from './networksConfig';

// Neutralize viem's built-in mainnet definition (and any vendored copies) at module evaluation time.
// viem/chains/definitions/mainnet hardcodes https://eth.merkle.io as default RPC (the source of the CORS errors).
// We force only testnet chains + explicit transports, plus this defensive override.
try {
  import('viem/chains').then((mod: any) => {
    const m = mod?.mainnet || mod?.default?.mainnet;
    if (m && m.rpcUrls) {
      m.rpcUrls = {
        default: { http: ['https://arbitrum-sepolia.publicnode.com'] },
        public: { http: ['https://arbitrum-sepolia.publicnode.com'] },
      };
    }
  }).catch(() => {});
  // Safe SDK vendors its own viem copy which also contains mainnet with merkle RPC.
  const safeViemChainsPath = '@safe-global/safe-apps-sdk/node_modules/viem/chains';
  import(/* webpackIgnore: true */ safeViemChainsPath as any)
    .then((mod: any) => {
      const m = mod?.mainnet;
      if (m && m.rpcUrls) {
        m.rpcUrls = { default: { http: ['https://arbitrum-sepolia.publicnode.com'] } };
      }
    })
    .catch(() => {});
} catch {}

const testnetChains = Object.values(testnetConfig).map((config) => config.wagmiChain) as [
  Chain,
  ...Chain[]
];

let prodChains = Object.values(prodNetworkConfig).map((config) => config.wagmiChain) as [
  Chain,
  ...Chain[]
];
void prodChains; // may be mutated for fork; referenced for TS

const forkBaseConfig = networkConfigs[FORK_BASE_CHAIN_ID];
const name = forkBaseConfig?.name || 'Unknown';
const baseAssetDecimals = forkBaseConfig?.baseAssetDecimals || 18;
const baseAssetSymbol = forkBaseConfig?.baseAssetSymbol || 'ETH';

const forkChain: Chain = {
  id: FORK_CHAIN_ID,
  name: `${name} Fork`,
  nativeCurrency: {
    decimals: baseAssetDecimals,
    name: baseAssetSymbol,
    symbol: baseAssetSymbol,
  },
  rpcUrls: {
    default: { http: [FORK_RPC_URL] },
  },
  testnet: false,
};

if (FORK_ENABLED) {
  prodChains = [forkChain, ...prodChains];
}

const defaultConfig = {
  walletConnectProjectId: process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID as string,
  appName: 'Aether',
  appDescription: 'Non-custodial RWA lending protocol',
  appUrl: '',
  appIcon: '',
};

const cypressConfig = createConfig(
  getDefaultConfig({
    chains: [forkChain],
    connectors: [injected()],
    ...defaultConfig,
  })
);

const getTransportUrl = (chainId: number) => {
  return networkConfigs[chainId]?.publicJsonRPCUrl[0] || 'https://arbitrum-sepolia.publicnode.com';
};
void getTransportUrl;

// Build explicit transports for ONLY our testnet chains.
// This prevents viem/wagmi from ever falling back to chain definitions (like mainnet's https://eth.merkle.io).
const testnetTransports: Record<number, Transport> = Object.fromEntries(
  testnetChains.map((chain) => [chain.id, http(getTransportUrl(chain.id))])
);

const prodCkConfig = getDefaultConfig({
  chains: testnetChains,  // force ONLY testnets (Arbitrum Sepolia + Robinhood) to avoid mainnet RPC fetches and CORS issues
  transports: testnetTransports,
  ...defaultConfig,
});

const aetherConnectorId = 'aetherAccountProvider';

const connectorConfig = {
  chains: prodCkConfig.chains,
  emitter: new Emitter(''),
};

const baseConnectors = prodCkConfig.connectors
  ?.map((connector) => {
    // initialize the connector with the emitter so we can access the id
    const c = connector(connectorConfig);
    if (c.id === 'safe') {
      return safe({
        allowedDomains: [/gnosis-safe.io$/, /app.safe.global$/, /dhedge.org$/],
      });
    } else {
      return connector;
    }
  })
  .sort((a, b) => {
    // sort connectors so the aave account connector is last
    // fixes slow wallet connections when running in the Safe UI
    if (a(connectorConfig).id === aetherConnectorId) {
      return 1;
    }
    if (b(connectorConfig).id === aetherConnectorId) {
      return -1;
    }
    return 0;
  });

const connectors = baseConnectors;

const prodConfig = createConfig({
  ...prodCkConfig,
  connectors,
});

const isCypressEnabled = process.env.NEXT_PUBLIC_IS_CYPRESS_ENABLED === 'true';

export const wagmiConfig = isCypressEnabled ? cypressConfig : prodConfig;
