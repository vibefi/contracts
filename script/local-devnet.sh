#!/usr/bin/env bash
set -euo pipefail

if ! command -v anvil >/dev/null 2>&1; then
  echo "anvil not found on PATH. Install foundry (https://book.getfoundry.sh/) to continue."
  exit 1
fi

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
CHAIN_ID="${CHAIN_ID:-31337}"
BLOCK_TIME="${BLOCK_TIME:-0}"
STATE_DIR="${STATE_DIR:-.anvil}"
STATE_FILE="$STATE_DIR/state.json"
OUTPUT_JSON="${OUTPUT_JSON:-.devnet/devnet.json}"

mkdir -p "$STATE_DIR"
mkdir -p "$(dirname "$OUTPUT_JSON")"

export DEV_PRIVATE_KEY="${DEV_PRIVATE_KEY:-0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d}"
export VOTER1_PRIVATE_KEY="${VOTER1_PRIVATE_KEY:-0x8b3a350cf5c34c9194ca3ab2f7b6c5b7b6b88a83f1f1192e8bff9bb5f1e66e0a}"
export VOTER2_PRIVATE_KEY="${VOTER2_PRIVATE_KEY:-0x4f3edf983ac636a65a842ce7c78d9aa706d3b113b37a19f4d4f79a5f9f7b8f0d}"
export SECURITY_COUNCIL_1_PRIVATE_KEY="${SECURITY_COUNCIL_1_PRIVATE_KEY:-0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6ed0f60}"
export SECURITY_COUNCIL_2_PRIVATE_KEY="${SECURITY_COUNCIL_2_PRIVATE_KEY:-0x5c8a5a8ec6b2e3d1ebf8a36b1ddc5c0b5e20efb6f6c3b7db6a99a4b43b5c6f2e}"

export SECURITY_COUNCIL="${SECURITY_COUNCIL:-$(cast wallet address "$SECURITY_COUNCIL_1_PRIVATE_KEY")}"

export INITIAL_SUPPLY="${INITIAL_SUPPLY:-1000000000000000000000000}"
export VOTING_DELAY="${VOTING_DELAY:-1}"
export VOTING_PERIOD="${VOTING_PERIOD:-20}"
export QUORUM_FRACTION="${QUORUM_FRACTION:-4}"
export TIMELOCK_DELAY="${TIMELOCK_DELAY:-1}"
export MIN_PROPOSAL_BPS="${MIN_PROPOSAL_BPS:-100}"
export VOTER_ALLOCATION="${VOTER_ALLOCATION:-100000000000000000000000}"
export COUNCIL_ALLOCATION="${COUNCIL_ALLOCATION:-50000000000000000000000}"
export OUTPUT_JSON

ANVIL_LOAD_ARGS=()
if [ -f "$STATE_FILE" ]; then
  ANVIL_LOAD_ARGS=(--load-state "$STATE_FILE")
fi

anvil \\
  --port 8545 \\
  --chain-id "$CHAIN_ID" \\
  --block-time "$BLOCK_TIME" \\
  --silent \\
  --state "$STATE_FILE" \\
  "${ANVIL_LOAD_ARGS[@]}" \\
  --account "$DEV_PRIVATE_KEY,1000000000000000000000" \\
  --account "$VOTER1_PRIVATE_KEY,1000000000000000000000" \\
  --account "$VOTER2_PRIVATE_KEY,1000000000000000000000" \\
  --account "$SECURITY_COUNCIL_1_PRIVATE_KEY,1000000000000000000000" \\
  --account "$SECURITY_COUNCIL_2_PRIVATE_KEY,1000000000000000000000" \\
  &

ANVIL_PID=$!
cleanup() { kill "$ANVIL_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

for _ in {1..30}; do
  if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

echo "Deploying VibeFi contracts to $RPC_URL"
FOUNDRY_PROFILE=ci forge script script/LocalDevnet.s.sol:LocalDevnet \\
  --rpc-url "$RPC_URL" \\
  --private-key "$DEV_PRIVATE_KEY" \\
  --broadcast

echo "Local devnet ready."
echo "Devnet JSON: $OUTPUT_JSON"
echo "Accounts:"
echo "  DEV_PRIVATE_KEY=$DEV_PRIVATE_KEY"
echo "  VOTER1_PRIVATE_KEY=$VOTER1_PRIVATE_KEY"
echo "  VOTER2_PRIVATE_KEY=$VOTER2_PRIVATE_KEY"
echo "  SECURITY_COUNCIL_1_PRIVATE_KEY=$SECURITY_COUNCIL_1_PRIVATE_KEY"
echo "  SECURITY_COUNCIL_2_PRIVATE_KEY=$SECURITY_COUNCIL_2_PRIVATE_KEY"

wait "$ANVIL_PID"
