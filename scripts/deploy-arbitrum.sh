#!/bin/bash
# Helper to deploy Aether contracts on Arbitrum Sepolia.
# Usage: from contracts/ dir: bash ../scripts/deploy-arbitrum.sh
set -e

echo "=== Aether Arbitrum Sepolia Deploy ==="
echo "Make sure .env has:"
echo "  DEPLOYER_PRIVATE_KEY=..."
echo "  ARBITRUM_RPC_URL=https://arbitrum-sepolia.publicnode.com"
echo ""
read -p "Continue? [y/N] " -n 1 -r; echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi

npx hardhat compile
npx hardhat ignition deploy ignition/modules/ArbitrumDeploymentModule.ts --network arbitrumSepolia --deployment-id aether-arbitrum

echo ""
echo "Syncing addresses to web..."
node scripts/sync-arbitrum-deployment.js

echo ""
echo "After reviewing the printed addresses, run init:"
echo "  POOL_ADDRESS=0xYourPool node scripts/init-reserves-arbitrum.js"
echo ""
echo "Then cd ../web && yarn dev"
