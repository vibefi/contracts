# VibeFi Contracts

This package contains the on-chain governance, registry, and deployment tooling for VibeFi.
The design below reflects the current Solidity contracts (source of truth), with the spec
used only as reference.

## Architecture Overview

Core contracts and roles:

- `VfiToken`: ERC20 + `ERC20Votes` governance token.
- `VfiGovernor`: OpenZeppelin 5.4 Governor stack with quorum fraction, Timelock control,
  simple counting (For/Against/Abstain), and a Security Council veto hook.
- `VfiTimelock`: OpenZeppelin `TimelockController` used as the executor for governance actions.
- `DappRegistry`: On-chain registry of dapp versions and statuses with metadata emitted as events.
- `ConstraintsRegistry`: On-chain registry of build constraints (CID roots).
- `MinimumDelegationRequirement`: pluggable proposal eligibility check (default: 1% total supply).

Access control and on-chain sources of truth:

- Governance actions execute through `VfiTimelock` (the registry governance role is the Timelock).
- Security Council is a distinct address and can pause/deprecate dapps and veto proposals.
- Metadata (dapp name/version/description) is emitted as events, not stored.
- IPFS root CIDs are stored on-chain as `bytes` per version.

## Contract Details

### VfiToken

- ERC20 token with delegation and snapshots (`ERC20Votes`).
- Voting power is delegated (self-delegation required to count votes).
- Initial supply minted to a deploy-time holder.

### VfiGovernor

OpenZeppelin extensions:

- `Governor`, `GovernorSettings`, `GovernorCountingSimple`
- `GovernorVotes`, `GovernorVotesQuorumFraction`
- `GovernorTimelockControl`

Key behaviors:

- Proposal eligibility is enforced by `IProposalRequirements` (default uses `MinimumDelegationRequirement`).
- `proposalThreshold` comes from `GovernorSettings` and can be updated by governance.
- Security Council can veto proposals using `vetoProposal(...)`, which calls `_cancel`.
- Governor executes via the Timelock, and `queue` is required before execution.

### VfiTimelock

- Standard `TimelockController`.
- Roles:
  - `PROPOSER_ROLE` granted to the Governor.
  - `EXECUTOR_ROLE` granted to `address(0)` for open execution.

### DappRegistry

Data model:

- `dappId` increments per new dapp.
- `versionId` increments per dapp.
- `DappVersion` stores:
  - `rootCid` (bytes)
  - `status` (`Published`, `Paused`, `Deprecated`)
  - `proposer`
  - `createdAt`

Events:

- `DappPublished(dappId, versionId, rootCid, proposer)`
- `DappUpgraded(dappId, fromVersionId, toVersionId, rootCid, proposer)`
- `DappMetadata(dappId, versionId, name, version, description)`
- `DappPaused(dappId, versionId, pausedBy, reason)`
- `DappUnpaused(dappId, versionId, unpausedBy, reason)`
- `DappDeprecated(dappId, versionId, deprecatedBy, reason)`

Access control:

- Governance (Timelock) can publish/upgrade/deprecate.
- Security Council can pause/unpause/deprecate.

### ConstraintsRegistry

- Mapping from `constraintsId` to `rootCid` (bytes).
- Updates are governance-only (Timelock role).
- Emits `ConstraintsUpdated`.

### Proposal Requirements

`IProposalRequirements` defines:

- `isEligible(address proposer, uint256 proposerVotes, uint256 totalSupply)`
- `onProposalCreated(uint256 proposalId, address proposer)`

Default implementation:

- `MinimumDelegationRequirement` requires minimum voting power as basis points of total supply.
- Current default in deployment script is 100 BPS (1%).

## Security Council Footgun (Documented Behavior)

Security Council rotation is not globally centralized. Updating `securityCouncil` in the
Governor does **not** automatically update AccessControl roles in `DappRegistry` or
`ConstraintsRegistry`. A rotation requires explicit role updates on those contracts.

## Build and Size Profiles

`VfiGovernor` exceeds EIP-170 size limits unless the optimizer + `via_ir` are enabled.
Deployment builds must use the `ci` profile (or an equivalent deploy profile).

```shell
$ FOUNDRY_PROFILE=ci forge build --sizes
```

## Testing

Run format, build, and tests:

```shell
$ FOUNDRY_PROFILE=ci forge fmt --check
$ FOUNDRY_PROFILE=ci forge build --sizes
$ FOUNDRY_PROFILE=ci forge test -vvv
```

Integration tests use the deployment script to mirror the on-chain deployment sequence.

## Deployment

Deployment script: `script/DeployVibeFi.s.sol`.

Environment variables expected by `run()`:

- `PRIVATE_KEY`: deployer key
- `SECURITY_COUNCIL`: multisig address
- `INITIAL_SUPPLY`
- `VOTING_DELAY`
- `VOTING_PERIOD`
- `QUORUM_FRACTION` (percent, OZ quorum fraction)
- `TIMELOCK_DELAY`
- `MIN_PROPOSAL_BPS` (basis points)

Example:

```shell
$ FOUNDRY_PROFILE=ci forge script script/DeployVibeFi.s.sol:DeployVibeFi \
  --rpc-url <RPC_URL> \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## Sepolia Testnet Deployment

Copy `.env.example` to `.env` and fill in `SEPOLIA_MNEMONIC` and `SEPOLIA_RPC_URL`. Forge reads `.env` automatically, and `foundry.toml` defines a `sepolia` RPC alias.

The deploy script derives the deployer key from `SEPOLIA_MNEMONIC` (index 0) and self-delegates all tokens, so the deployer satisfies both the proposal threshold and quorum on its own.

### Current deployment (2026-02-17)

| Contract | Address |
|---|---|
| VfiToken | `0xD11496882E083Ce67653eC655d14487030E548aC` |
| VfiTokenSeller (testnet seller) | `0x93bb81a54d9Dd29b8e8037260aF93770c4F2A64E` |
| VfiGovernor | `0x753d33e2E61F249c87e6D33c4e04b39731776297` |
| VfiTimelock | `0xA1349b43D3f233287762897047980bAb3846E23b` |
| DappRegistry | `0xFb84B57E757649Dff3870F1381C67c9097D0c67f` |
| ConstraintsRegistry | `0x6F88C22Aed57a7175E2655AA5f2b5863A0c0a7b7` |
| MinimumDelegationRequirement | `0x641d8C8823e72af936b78026d3bb514Be3f22383` |

### 1. Deploy contracts

```shell
source .env
$ OUTPUT_JSON=.devnet/sepolia.json FOUNDRY_PROFILE=ci forge script \
    script/DeploySepolia.s.sol:DeploySepolia \
    --rpc-url sepolia --broadcast --verify -vvv
```

Contract addresses are written to `.devnet/sepolia.json`.

### 2. Derive the deployer private key

The CLI needs a raw private key. Derive it once:

```shell
$ export DEPLOYER_PK=$(cast wallet private-key --mnemonic "$SEPOLIA_MNEMONIC")
```

### 3. Package a dapp

Start IPFS if not running (`docker compose -f docker-compose.ipfs.yml up -d` from the monorepo root), then from `cli/`:

```shell
$ bun run src/index.ts package \
    --path ../dapp-examples/uniswap-v2 \
    --name "Uniswap V2" --dapp-version 0.0.1 \
    --description "Uniswap V2 example" --json
```

Note the `rootCid` from the output.

### 4. Propose the dapp

```shell
$ bun run src/index.ts dapp:propose \
    --root-cid <rootCid> \
    --name "Uniswap V2" --dapp-version 0.0.1 \
    --description "Uniswap V2 example" \
    --proposal-description "Publish Uniswap V2 v0.0.1" \
    --rpc $SEPOLIA_RPC_URL --devnet ../contracts/.devnet/sepolia.json \
    --pk $DEPLOYER_PK --json
```

### 5. Vote

Wait ~12s for the voting delay (1 block), then find the proposal ID and vote:

```shell
$ bun run src/index.ts proposals:list \
    --rpc $SEPOLIA_RPC_URL --devnet ../contracts/.devnet/sepolia.json --json
$ bun run src/index.ts vote:cast <proposalId> --support for \
    --rpc $SEPOLIA_RPC_URL --devnet ../contracts/.devnet/sepolia.json \
    --pk $DEPLOYER_PK --json
```

### 6. Queue and execute

Wait ~10 min for the voting period (50 blocks), then queue:

```shell
$ bun run src/index.ts proposals:queue <proposalId> \
    --rpc $SEPOLIA_RPC_URL --devnet ../contracts/.devnet/sepolia.json \
    --pk $DEPLOYER_PK --json
```

Wait 60s for the timelock delay, then execute:

```shell
$ bun run src/index.ts proposals:execute <proposalId> \
    --rpc $SEPOLIA_RPC_URL --devnet ../contracts/.devnet/sepolia.json \
    --pk $DEPLOYER_PK --json
```

### 7. Verify

```shell
$ bun run src/index.ts dapp:list \
    --rpc $SEPOLIA_RPC_URL --devnet ../contracts/.devnet/sepolia.json --json
```

### 8. Pin IPFS content:

```shell
curl -X POST "https://api.4everland.dev/pins" \ 
  -H "Authorization: Bearer <4EVERLAND_API_KEY>" \
  -H "Content-Type: application/json" \
  --data '{
    "cid": "<root cid>",
    "name": "<folder-name>"
  }'
```

## Local Devnet

Spin up a local Anvil devnet with predefined keys, deploy contracts, and leave the chain running:

```shell
$ ./script/local-devnet.sh
```

Defaults:

- Accounts: developer, two voters, two security council members (see script output).
- `SECURITY_COUNCIL` is set to the first council address. The second council key is funded but not assigned on-chain.
- Governance params are configurable via env vars (see `script/local-devnet.sh`).
- A machine-readable JSON file is written to `.devnet/devnet.json` (override with `OUTPUT_JSON`).

The devnet deploys using `script/LocalDevnet.s.sol`, which also distributes tokens and self-delegates.

## Developer Notes

- The contracts assume mainnet-style governance flows (Timelock + Governor).
- Off-chain indexing should treat events as the primary metadata source.
