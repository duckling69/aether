# Aether

Non-custodial RWA lending protocol on Arbitrum Sepolia.

Supply Ondo-style RWA tokens as collateral and borrow stablecoins directly on-chain.

## Live Deployment (Arbitrum Sepolia)

- Pool: 0xF4C249E21C7Eb553876F3Ab45C826710106343EF
- USDC (mock): 0xe3611967ea9b4C874Edf99079c30FC4ecb877d20
- OUSG (mock): 0x825422622894FfAc56939808A107715d4816e359
- USDY (mock): 0x7Be8e67f6ff18D47d1A6e28DA14a1008E739D7Db

## Features

- Upgradeable lending pool
- Supply, withdraw, borrow, repay
- Health factor based liquidations
- Configurable reserves and risk parameters
- Simple interest accrual

## Contracts

Core contract is AetherPool (upgradeable).

See `contracts/contracts/AetherPool.sol`.

Deployment uses Hardhat Ignition.

## Getting Started

### Contracts

```bash
cd contracts
yarn install
cp .env.example .env
# Add your deployer private key
npx hardhat compile
```

### Frontend

```bash
cd web
yarn install
yarn dev
```

Connect a wallet on Arbitrum Sepolia.

## Configuration

Deployment addresses are in `web/ui-config/arbitrumDeployment.json` and `contracts/config/tokens-arbitrum.js`.

Update after new deployments using the sync scripts.

## License

MIT
