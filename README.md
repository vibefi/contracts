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
