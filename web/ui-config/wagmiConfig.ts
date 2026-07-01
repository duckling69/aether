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
import { createConfig } from 'wagmi';
import { injected, safe } from 'wagmi/connectors';

import { prodNetworkConfig, testnetConfig } from './networksConfig';

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

const getTransport = (chainId: number) => {
  return networkConfigs[chainId]?.publicJsonRPCUrl[0];
};
void getTransport; // referenced to satisfy unused var check (fork path)

const prodCkConfig = getDefaultConfig({
  chains: testnetChains,  // force only testnets (Arbitrum + Robinhood) to avoid mainnet RPC fetches and CORS issues
  transports: undefined,
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
