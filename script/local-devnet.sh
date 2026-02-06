#!/usr/bin/env bash
set -euo pipefail

# Load .env if present
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

if ! command -v anvil >/dev/null 2>&1; then
  echo "anvil not found on PATH. Install foundry (https://book.getfoundry.sh/) to continue."
  exit 1
fi

ANVIL_PORT="${ANVIL_PORT:-8545}"
RPC_URL="${RPC_URL:-http://127.0.0.1:${ANVIL_PORT}}"
CHAIN_ID="${CHAIN_ID:-1}"
BLOCK_TIME="${BLOCK_TIME:-0}"
STATE_DIR="${STATE_DIR:-.anvil}"
STATE_FILE="$STATE_DIR/state.json"
PERSIST_STATE="${PERSIST_STATE:-0}"
OUTPUT_JSON="${OUTPUT_JSON:-.devnet/devnet.json}"
FORK_URL="${FORK_URL:-}"
FORK_BLOCK="${FORK_BLOCK:-}"

mkdir -p "$STATE_DIR"
mkdir -p "$(dirname "$OUTPUT_JSON")"

export MNEMONIC="${MNEMONIC:-test test test test test test test test test test test junk}"

derive_key() {
  local index=$1
  cast wallet private-key --mnemonic "$MNEMONIC" --mnemonic-index "$index"
}

export DEV_PRIVATE_KEY="${DEV_PRIVATE_KEY:-$(derive_key 0)}"
export VOTER1_PRIVATE_KEY="${VOTER1_PRIVATE_KEY:-$(derive_key 1)}"
export VOTER2_PRIVATE_KEY="${VOTER2_PRIVATE_KEY:-$(derive_key 2)}"
export SECURITY_COUNCIL_1_PRIVATE_KEY="${SECURITY_COUNCIL_1_PRIVATE_KEY:-$(derive_key 3)}"
export SECURITY_COUNCIL_2_PRIVATE_KEY="${SECURITY_COUNCIL_2_PRIVATE_KEY:-$(derive_key 4)}"

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
ANVIL_STATE_ARGS=()
if [ "$PERSIST_STATE" = "1" ]; then
  ANVIL_STATE_ARGS=(--state "$STATE_FILE")
  if [ -f "$STATE_FILE" ]; then
    ANVIL_LOAD_ARGS=(--load-state "$STATE_FILE")
  fi
fi

ANVIL_SUBCMD=()
if anvil --version 2>/dev/null | rg -qi "zksync"; then
  ANVIL_SUBCMD=(run)
fi

ANVIL_BLOCK_TIME_ARGS=()
if [ "$BLOCK_TIME" != "0" ]; then
  ANVIL_BLOCK_TIME_ARGS=(--block-time "$BLOCK_TIME")
fi

ANVIL_FORK_ARGS=()
if [ -n "$FORK_URL" ]; then
  ANVIL_FORK_ARGS=(--fork-url "$FORK_URL")
  if [ -n "$FORK_BLOCK" ]; then
    ANVIL_FORK_ARGS+=(--fork-block-number "$FORK_BLOCK")
  fi
fi

# Temporarily disable nounset: bash 3.2 (macOS default) treats empty
# array [@] expansions as unbound variables under set -u.
set +u
anvil "${ANVIL_SUBCMD[@]}" \
  --port "$ANVIL_PORT" \
  --chain-id "$CHAIN_ID" \
  "${ANVIL_BLOCK_TIME_ARGS[@]}" \
  "${ANVIL_FORK_ARGS[@]}" \
  --balance 10000 \
  --silent \
  "${ANVIL_STATE_ARGS[@]}" \
  "${ANVIL_LOAD_ARGS[@]}" \
  --accounts 5 \
  --mnemonic "$MNEMONIC" \
  &
set -u

ANVIL_PID=$!
cleanup() { kill "$ANVIL_PID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

CHAIN_READY=false
for _ in {1..30}; do
  if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    CHAIN_READY=true
    break
  fi
  sleep 0.2
done

if [ "$CHAIN_READY" != "true" ]; then
  echo "Anvil did not start or RPC is not ready at $RPC_URL" >&2
  exit 1
fi

check_account_balance() {
  local name=$1
  local key=$2
  local address
  address=$(cast wallet address "$key")
  local balance
  balance=$(cast balance "$address" --rpc-url "$RPC_URL")
  if [ "$balance" = "0" ]; then
    echo "Account $name ($address) has zero balance. Check anvil --account syntax." >&2
    exit 1
  fi
}

check_account_balance "dev" "$DEV_PRIVATE_KEY"
check_account_balance "voter1" "$VOTER1_PRIVATE_KEY"
check_account_balance "voter2" "$VOTER2_PRIVATE_KEY"
check_account_balance "council1" "$SECURITY_COUNCIL_1_PRIVATE_KEY"
check_account_balance "council2" "$SECURITY_COUNCIL_2_PRIVATE_KEY"

echo "Deploying VibeFi contracts to $RPC_URL"
FOUNDRY_PROFILE=ci forge script script/LocalDevnet.s.sol:LocalDevnet \
  --rpc-url "$RPC_URL" \
  --private-key "$DEV_PRIVATE_KEY" \
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
