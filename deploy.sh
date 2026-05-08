#!/bin/bash
set -e

WALLET=0xF40003d36567478489BcCF1a1fEd094f87EeC9a5
RPC=http://127.0.0.1:8545
ACCOUNT=anvil-deployer
SENDER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
FRONTEND_DIR=./Pool-frontend

echo "==================================="
echo "  POOL DEPLOY SCRIPT"
echo "==================================="

# ── 1. Deploy contracts ───────────────────────────────────────────────────────
echo ""
echo "Deploying contracts..."

OUTPUT=$(forge script scripts/Deploy.s.sol:Deploy \
  --rpc-url $RPC \
  --broadcast \
  --account $ACCOUNT \
  --sender $SENDER 2>&1)

echo "$OUTPUT"

# ── 2. Parse deployed addresses ───────────────────────────────────────────────
POOL=$(echo "$OUTPUT"  | grep "Pool deployed at:"  | awk '{print $NF}')
MUSDT=$(echo "$OUTPUT" | grep "mUSDT deployed at:" | awk '{print $NF}')
MWETH=$(echo "$OUTPUT" | grep "mWETH deployed at:" | awk '{print $NF}')
MWBTC=$(echo "$OUTPUT" | grep "mWBTC deployed at:" | awk '{print $NF}')

if [ -z "$POOL" ] || [ -z "$MUSDT" ]; then
  echo ""
  echo "ERROR: Failed to parse deployed addresses. Check forge output above."
  exit 1
fi

# ── 3. Write frontend .env ────────────────────────────────────────────────────
echo ""
echo "Writing $FRONTEND_DIR/.env..."

# Use printf to avoid heredoc scope issues
printf "VITE_POOL_ADDRESS=%s\nVITE_TOKEN_MUSDT=%s\nVITE_TOKEN_MWETH=%s\nVITE_TOKEN_MWBTC=%s\n" \
  "$POOL" "$MUSDT" "$MWETH" "$MWBTC" > "$FRONTEND_DIR/.env"

echo "Done."

# ── 4. Mint test tokens ───────────────────────────────────────────────────────
echo ""
echo "Minting test tokens to $WALLET..."

cast send $MUSDT "mint(address,uint256)" $WALLET 100000000000000000000000 \
  --rpc-url $RPC --account $ACCOUNT

cast send $MWETH "mint(address,uint256)" $WALLET 1000000000000000000000 \
  --rpc-url $RPC --account $ACCOUNT

cast send $MWBTC "mint(address,uint256)" $WALLET 100000000000000000000 \
  --rpc-url $RPC --account $ACCOUNT

# ── 5. Send ETH for gas ───────────────────────────────────────────────────────
echo ""
echo "Sending 10 ETH for gas to $WALLET..."

cast send $WALLET --value 10ether --rpc-url $RPC --account $ACCOUNT

# ── 6. Verify pool state ──────────────────────────────────────────────────────
echo ""
echo "Verifying pool reserves..."
cast call $POOL "getAllReserves()" --rpc-url $RPC

echo ""
echo "==================================="
echo "  DEPLOYMENT COMPLETE"
echo "==================================="
echo "Pool:  $POOL"
echo "mUSDT: $MUSDT"
echo "mWETH: $MWETH"
echo "mWBTC: $MWBTC"
echo "==================================="