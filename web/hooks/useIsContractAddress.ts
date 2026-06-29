import { useQuery } from '@tanstack/react-query';
import { useRootStore } from 'store/root';
import { getNetworkConfig, getProvider } from 'utils/marketsAndNetworksConfig';

export const useIsContractAddress = (address: string, chainId?: number) => {
  const defaultChainId = useRootStore((store) => store.currentChainId);
  const effectiveChainId = chainId ?? defaultChainId;

  // Only attempt provider calls for chains we have config for (prevents crashes when wallet is on unsupported chain like 11155111)
  const networkCfg = getNetworkConfig(effectiveChainId);
  const hasConfig = !!(networkCfg && networkCfg.publicJsonRPCUrl && networkCfg.publicJsonRPCUrl.length > 0);

  return useQuery({
    queryFn: async () => {
      if (!hasConfig) {
        return '0x'; // treat as EOA for unsupported chains
      }
      try {
        const provider = getProvider(effectiveChainId);
        return await provider.getCode(address);
      } catch (error) {
        console.error('Error getting code:', error);
        return '0x';
      }
    },
    queryKey: ['isContractAddress', address, effectiveChainId],
    enabled: address !== '' && hasConfig,
    staleTime: Infinity,
    select: (data) => data !== '0x',
  });
};
