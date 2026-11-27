#!/usr/bin/env bash
# SentinelOmni — Zero-Cost Testnet Deployment & Full-Loop Verification Runbook
# Networks:
#   - Base Sepolia (84532):     https://sepolia.base.org
#   - Unichain Sepolia (1301):  https://sepolia.unichain.org
#   - Reactive Lasna (5318007): https://lasna-rpc.rnk.dev/
#
# Required env vars before execution (DO NOT commit private keys):
#   export PRIVATE_KEY="0x..."
#   export WALLET_ADDR="0x..."

set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../.env.testnet" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/../.env.testnet"
  set +a
fi

ETH_SEPOLIA_RPC="${ETH_SEPOLIA_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
BASE_SEPOLIA_RPC="${BASE_SEPOLIA_RPC:-https://sepolia.base.org}"
UNICHAIN_SEPOLIA_RPC="${UNICHAIN_SEPOLIA_RPC:-https://sepolia.unichain.org}"
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
BASE_FAUCET="0x2afaFD298b23b62760711756088F75B7409f5967"
ETH_SEPOLIA_REACTIVE_FAUCET="0x9b9BB25f1A81078C544C829c5EB7822d747Cf434"
BASE_SEPOLIA_PORTAL="0x49f53e41452C74589E85cA1677426Ba426459e85"
UNICHAIN_SEPOLIA_PORTAL="0x0d83dab629f0e0F9d36c0Cbc89B69a489f0751bD"

usage() {
  echo "Usage: $0 {balances|split-sepolia|faucet|deploy-base|deploy-unichain|deploy-lasna|bind|trigger-demo}"
  exit 1
}

cmd="${1:-}"
case "$cmd" in
  balances)
    echo "Wallet: $WALLET_ADDR"
    echo -n "Ethereum Sepolia (11155111): "; cast balance --ether --rpc-url "$ETH_SEPOLIA_RPC" "$WALLET_ADDR"
    echo -n "Base Sepolia (84532):        "; cast balance --ether --rpc-url "$BASE_SEPOLIA_RPC" "$WALLET_ADDR"
    echo -n "Unichain Sepolia (1301):     "; cast balance --ether --rpc-url "$UNICHAIN_SEPOLIA_RPC" "$WALLET_ADDR"
    echo -n "Reactive Lasna (5318007):    "; cast balance --ether --rpc-url "$LASNA_RPC" "$WALLET_ADDR"
    ;;
  split-sepolia)
    echo "[1/3] Swapping 0.015 Sepolia ETH -> ~1.5 lREACT on Reactive Lasna..."
    cast send "$ETH_SEPOLIA_REACTIVE_FAUCET" \
      --rpc-url "$ETH_SEPOLIA_RPC" \
      --private-key "$PRIVATE_KEY" \
      "request(address)" "$WALLET_ADDR" \
      --value 0.015ether
    echo "[2/3] Bridging 0.015 Sepolia ETH -> Base Sepolia via OptimismPortal..."
    cast send "$BASE_SEPOLIA_PORTAL" \
      --rpc-url "$ETH_SEPOLIA_RPC" \
      --private-key "$PRIVATE_KEY" \
      --value 0.015ether
    echo "[3/3] Bridging 0.01 Sepolia ETH -> Unichain Sepolia via OptimismPortal..."
    cast send "$UNICHAIN_SEPOLIA_PORTAL" \
      --rpc-url "$ETH_SEPOLIA_RPC" \
      --private-key "$PRIVATE_KEY" \
      --value 0.01ether
    ;;
  faucet)
    FAUCET_VALUE="${FAUCET_VALUE:-0.005ether}"
    echo "[1/1] Requesting free lREACT via Base Sepolia faucet ($FAUCET_VALUE -> lREACT)..."
    cast send "$BASE_FAUCET" \
      --rpc-url "$BASE_SEPOLIA_RPC" \
      --private-key "$PRIVATE_KEY" \
      "request(address)" "$WALLET_ADDR" \
      --value "$FAUCET_VALUE"
    ;;
  deploy-base)
    forge script script/DeploySentinelOmni.s.sol:DeployDestinationBaseSepolia \
      --rpc-url "$BASE_SEPOLIA_RPC" \
      --private-key "$PRIVATE_KEY" \
      --broadcast
    ;;
  deploy-unichain)
    forge script script/DeploySentinelOmni.s.sol:DeployOriginUnichainSepolia \
      --rpc-url "$UNICHAIN_SEPOLIA_RPC" \
      --private-key "$PRIVATE_KEY" \
      --broadcast
    ;;
  deploy-lasna)
    : "${VAULT_ADDR:?set VAULT_ADDR}"
    : "${POOL_ADDR:?set POOL_ADDR}"
    : "${MONITOR_ADDR:?set MONITOR_ADDR}"
    : "${VAULT_CB_ADDR:?set VAULT_CB_ADDR}"
    : "${VERIFIER_CB_ADDR:?set VERIFIER_CB_ADDR}"
    forge script script/DeploySentinelOmni.s.sol:DeployReactiveLasna \
      --sig "run(address,address,address,address,address)" \
      "$VAULT_ADDR" "$POOL_ADDR" "$MONITOR_ADDR" "$VAULT_CB_ADDR" "$VERIFIER_CB_ADDR" \
      --rpc-url "$LASNA_RPC" \
      --private-key "$PRIVATE_KEY" \
      --broadcast
    ;;
  bind)
    : "${VAULT_CB_ADDR:?set VAULT_CB_ADDR}"
    : "${VERIFIER_CB_ADDR:?set VERIFIER_CB_ADDR}"
    : "${REACTIVE_ADDR:?set REACTIVE_ADDR}"
    cast send "$VAULT_CB_ADDR" "bindReactiveSender(address)" "$REACTIVE_ADDR" \
      --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PRIVATE_KEY"
    cast send "$VERIFIER_CB_ADDR" "bindReactiveSender(address)" "$REACTIVE_ADDR" \
      --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PRIVATE_KEY"
    ;;
  trigger-demo)
    : "${VAULT_ADDR:?set VAULT_ADDR}"
    : "${POOL_ADDR:?set POOL_ADDR}"
    echo "[Step A] Triggering Unichain Sepolia -45% collateral price shock..."
    cast send "$POOL_ADDR" "reportSwapPrice(address,uint256)" "$VAULT_ADDR" 550000000000000000 \
      --rpc-url "$UNICHAIN_SEPOLIA_RPC" --private-key "$PRIVATE_KEY"
    echo "[Step B] Triggering Base Sepolia deposit + NAV lock + 50% distressed sale..."
    cast send "$VAULT_ADDR" "depositAllocated(address,uint256)" "$WALLET_ADDR" 100000000000 \
      --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PRIVATE_KEY"
    cast send "$VAULT_ADDR" "beginTxNavLock()" \
      --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PRIVATE_KEY"
    cast send "$VAULT_ADDR" "executeDistressedSale(uint256)" 5000 \
      --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PRIVATE_KEY"
    echo "Check ReactScan: https://lasna.reactscan.net/ and BaseScan Sepolia for callback tx hashes!"
    ;;
  *)
    usage
    ;;
esac
