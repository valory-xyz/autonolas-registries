# Proposal 24 — de-whitelist GnosisSafeSameAddressMultisig, clean up nominees, extend GuardCM allowlist

A single GovernorOLAS proposal (41 actions) bundling three protocol-maintenance changes:

1. **De-whitelist `GnosisSafeSameAddressMultisig`** (8 calls) — `changeMultisigPermission(adapter, false)` on the
   `ServiceRegistry` (Ethereum) and `ServiceRegistryL2` (Gnosis, Polygon, Arbitrum, Optimism, Base, Celo, Mode).
   Removes the same-address multisig adoption path from service deployment. Mainnet is a direct Timelock call;
   each L2 is bridged through its mediator (AMB / FxRoot / Arbitrum Inbox retryable / OP-stack messenger).
2. **Un-nominate staking contracts** (32 calls) — `VoteWeighting.removeNominee(bytes32, uint256)` for the
   retired (account, chainId) pairs across Ethereum, Gnosis, Base, Polygon, Optimism, Celo and Arbitrum.
3. **Extend the GuardCM allowlist** (1 call) — `setTargetSelectorChainIds(...)` adding 19 (target, selector,
   chainId) emergency-pause triples (Dispenser `setPauseState`, ServiceManager / RegistriesManager `pause`,
   per-L2 `TargetDispenserL2.pause`) plus the Mode `ServiceRegistryL2.drain` / `ServiceRegistryTokenUtility.drain`
   backfill that Phase 0 omitted. All statuses = true (additions).

## Files
- `Proposal24DewhitelistAndUnnominate.s.sol` — the builder (`buildProposal()` returns
  `targets/values/calldatas/description` and prints the `proposalId`). Bridge encodings mirror the autonolas-
  governance proposal-11 builder; the GuardCM batch mirrors its Phase-0 `setTargetSelectorChainIds`.
- `description.txt` — the proposal description, byte-for-byte equal to the builder's `DESCRIPTION` (the
  `proposalId` is computed from `keccak256(abi.encode(targets, values, calldatas, keccak256(description)))`).
- `estimate_arb_submission_cost.js` — Arbitrum retryable estimator (Arbitrum SDK `estimateAll`, +1000% buffers,
  `value = deposit * 10`); mirrors `scripts/proposals/proposal_15_*`. Re-run right before submission to refresh
  the baked `ARB_*` constants against L1 basefee drift.

## Fork tests (`test/`)
Full propose → vote → queue → execute lifecycle on a mainnet fork plus per-L2 bridge-delivery sims:
- `Proposal24ForkL1.t.sol` — through the live GovernorOLAS; asserts the mainnet de-whitelist, all 32 nominee
  removals, and all 19 GuardCM triples; Arbitrum retryable is executor-funded (Timelock keeps no balance).
- `Proposal24ForkL2OpStack.t.sol` — Optimism / Base / Celo / Mode mediator replay → adapter de-whitelisted.
- `Proposal24ForkL2Other.t.sol` — Gnosis (AMB) / Polygon (FxRoot) / Arbitrum (aliased Timelock) → de-whitelisted.

```
forge test --match-contract Proposal24Fork -vvv      # uses ETH_RPC / OP_RPC / ... or public RPC defaults
forge script scripts/proposals/proposal_24_dewhitelist_sameaddr_and_unnominate/Proposal24DewhitelistAndUnnominate.s.sol:Proposal24DewhitelistAndUnnominate
```

## Operational notes
- **Nominee-removal timing:** `Dispenser.removeNominee` reverts within the last week of the ongoing epoch, so
  this proposal must be **executed with > 7 days left in the epoch** (epoch length is 14 days).
- **Arbitrum value:** the executor of `execute()` supplies the retryable ETH (`ARB_RETRYABLE_VALUE`); it flows
  executor → Governor → Timelock → Inbox, so the Timelock needs no balance. Re-run the estimator before submission.
