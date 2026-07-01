'use client';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import dynamic from 'next/dynamic';
import { ConnectKitProvider } from 'connectkit';
import { ReactNode, useState } from 'react';
import { WagmiProvider } from 'wagmi';

import { AppGlobalStyles } from '../layouts/AppGlobalStyles';
import { LanguageProvider } from '../libs/LanguageProvider';
import { Web3ContextProvider } from '../libs/web3-data-provider/Web3Provider';
import { SharedDependenciesProvider } from '../ui-config/SharedDependenciesProvider';
import { wagmiConfig } from '../ui-config/wagmiConfig';

// Block any accidental mainnet RPC / analytics fetches (e.g. eth.merkle.io, mainnet alchemy)
// that cause CORS errors on testnet-only deploys. Return neutral responses.
if (typeof window !== 'undefined') {
  const origFetch = window.fetch.bind(window);
  const BAD_HOSTS = ['eth.merkle.io', 'eth-mainnet', 'mainnet.g.alchemy'];
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (window as any).fetch = async (input: any, init?: any) => {
    try {
      const url = typeof input === 'string' ? input : (input && (input.url || input.toString())) || '';
      if (BAD_HOSTS.some((h) => url.includes(h))) {
        // eslint-disable-next-line no-console
        console.debug('[aether] blocked mainnet/CORS fetch:', url);
        return new Response(JSON.stringify({ jsonrpc: '2.0', id: 1, result: null }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        });
      }
    } catch {}
    return origFetch(input, init);
  };
}

const ReactQueryDevtools = dynamic(
  () =>
    import('@tanstack/react-query-devtools').then((mod) => mod.ReactQueryDevtools),
  { ssr: false }
);

export function Providers({ children }: { children: ReactNode }) {
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            refetchOnWindowFocus: false,
          },
        },
      })
  );

  const cleanLocalStorage = () => {
    localStorage.removeItem('readOnlyModeAddress');
  };

  return (
    <LanguageProvider>
      <WagmiProvider config={wagmiConfig}>
        <QueryClientProvider client={queryClient}>
          <ConnectKitProvider onDisconnect={cleanLocalStorage}>
            <AppGlobalStyles>
              <Web3ContextProvider>
                <SharedDependenciesProvider>{children}</SharedDependenciesProvider>
              </Web3ContextProvider>
            </AppGlobalStyles>
            {process.env.NODE_ENV !== 'production' && <ReactQueryDevtools initialIsOpen={false} />}
          </ConnectKitProvider>
        </QueryClientProvider>
      </WagmiProvider>
    </LanguageProvider>
  );
}
