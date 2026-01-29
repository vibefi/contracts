# VibeFi DAO + Dapp Registry Initial Spec

Status: Draft

This spec captures the first on-chain architecture for the VibeFi DAO, voting, and
dapp registry. Contracts are intended for Foundry (forge) and Solidity, and use
OpenZeppelin 5.0 governance components.

## Goals

- Decentralized governance for approving and managing dapps.
- On-chain registry that stores only the root IPFS CID for each dapp version.
- Minimal on-chain storage for metadata; human-readable data lives in logs.
- Security Council with maximal ability to veto proposals and pause dapps.
- Proposal eligibility requires a minimum delegation or stake; voting has no minimum.
- Proposal bonding rules are pluggable and upgradable by governance.
- Minimum proposal delegation target is 1% of total supply.

## Non-Goals (for now)

- On-chain dapp metadata registries beyond logs.
- On-chain audit registries or delegate registries.
- Upgradeability or proxy patterns.

## Core Contracts

### VfiToken

- ERC20 + `ERC20Votes` (OpenZeppelin 5.0).
- Delegation enabled for governance power.
- Total supply and distribution are out of scope for this spec.

### VfiGovernor

Use the OpenZeppelin 5.0 governance stack:

- `Governor`
- `GovernorSettings` (voting delay, voting period, proposal threshold)
- `GovernorCountingSimple` (For/Against/Abstain)
- `GovernorVotes` (token-based voting power)
- `GovernorTimelockControl` (optional but recommended)

Key parameters:

- `proposalThreshold`: minimum delegated voting power required to propose.
- `quorum`: set as a fraction of total supply (configurable).
- `votingDelay`, `votingPeriod`: initial values set by deployer, later governed.

### VfiTimelock (if used)

- OpenZeppelin `TimelockController`.
- Governor is the proposer/executor, Security Council is an optional proposer
  only for emergency actions if required.

### DappRegistry

Stores the on-chain registry of dapps and versions. Only stores the root CID
for each version and status flags.

Data model (conceptual):

- `dappId`: monotonically increasing identifier.
- `versionId`: per-dapp version index (or global id), monotonically increasing.
- `DappVersion`:
  - `rootCid` (bytes): IPFS CID bytes, stored on-chain.
  - `status`: `Published`, `Paused`, `Deprecated`.
  - `proposer`: address that submitted the proposal.
  - `timestamp`: block timestamp.

Metadata is *not* stored on-chain. Human-readable metadata is emitted as events.

Events (illustrative):

- `DappPublished(dappId, versionId, rootCid, proposer)`
- `DappMetadata(dappId, versionId, name, version, description)`
- `DappPaused(dappId, versionId, pausedBy, reason)`
- `DappDeprecated(dappId, versionId, deprecatedBy, reason)`
- `DappUpgraded(dappId, fromVersionId, toVersionId, rootCid, proposer)`

Notes:

- The `DappMetadata` event should emit: dapp name, version string, and a single
  sentence description.
- Clients can index metadata from logs without fetching IPFS for every dapp.
- `rootCid` is the single authoritative content pointer for each version.

Access control:

- Governance (Governor/Timelock) can add dapps, add versions, and deprecate.
- Security Council can pause and deprecate in emergencies.
- Security Council can optionally unpause if desired, or unpause may be DAO-only.

### ConstraintsRegistry

Maintains a DAO-governed list of constraints for dapp builds.

- `constraintsId` (bytes32) -> `rootCid` (bytes) or hash.
- Adding or updating constraints is governance-only.
- Intended to anchor build constraints without requiring on-chain policy logic.

### Proposal Requirements (pluggable)

A governance-configurable contract defines proposal eligibility and bonding
requirements. This keeps bond economics flexible while standardizing interface.

Interface (conceptual):

- `onPropose(address proposer, uint256 proposalId) returns (bytes32 bondId)`
- `onProposalResolved(uint256 proposalId, ProposalOutcome outcome)`
- `proposalEligible(address proposer) view returns (bool)`

The Governor checks `proposalEligible` before allowing proposal creation.
`onPropose` can lock or transfer a bond. `onProposalResolved` handles refunds
or slashing. The exact bond economics can evolve over time by swapping this
contract via governance.

## Security Council

The Security Council is a designated role (a multisig address).
Powers are maximal:

- Veto proposals by calling `cancel` in Governor.
- Pause any dapp or version in `DappRegistry`.
- Deprecate any dapp or version in `DappRegistry` if urgent.

The DAO can replace or remove the Security Council over time.

## Governance Flow (high level)

1. Proposer meets minimum delegated voting power and bonding requirements.
2. Proposer submits a proposal to add a new dapp or upgrade an existing dapp.
3. Vote occurs via OZ Governor with quorum/threshold settings.
4. On approval, the Timelock executes the action in `DappRegistry`.
5. Events emit metadata to enable client indexing.

## Dapp Lifecycle

State transitions for a dapp version:

- `Published` (default)
- `Paused` (Security Council or DAO)
- `Deprecated` (DAO or Security Council, final)

Upgrades publish a new version and may optionally deprecate older ones.

## IPFS Addressing

- Store only a single root CID per dapp version.
- CID stored as `bytes` on-chain (CIDv1 recommended).
- The protocol does not store the name, version, or description on-chain, but
  emits them via `DappMetadata` logs.
  - Pausing/unpausing a specific dapp/version emits events and updates status.

## Open Questions / Parameters to finalize

- Initial governance parameter values (delay, period, quorum, threshold).
- Security Council unpause permissions.
- Exact proposal requirement interface shape.
- Deprecation rules for older versions (automatic vs explicit).

## Deployment Notes

- `VfiGovernor` is large; deployments must use an optimizer + `via_ir` profile to
  stay under EIP-170. The current `profile.ci` is the recommended deployment profile.
- Security Council rotation requires updating AccessControl roles on `DappRegistry`
  and `ConstraintsRegistry` in addition to `VfiGovernor`.
