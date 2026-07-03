# Proposal 24a — de-whitelist same-address multisigs + extend the GuardCM allowlist

The first of the two proposals that replace the original single 41-action **proposal 24**, which reverted
on-chain ([tx `0x540c…20f`](https://etherscan.io/tx/0x540c2026c0a122465806240becdd8381489e19e61d74e74ec184a9660621e20f))
because its `execute()` needed **~19.9M gas** while **EIP-7825** (Fusaka) caps a single transaction at
**2²⁴ = 16,777,216 gas**. The bundle was split so each proposal's execute stays well under the cap. This half
(**9 actions**) measures **~10.3M gas**; the 32 `removeNominee` calls (~9.55M) live in proposal 24b.

## Actions (9)
1. **De-whitelist the same-address multisig adapters** (8 calls) — `changeMultisigPermission(adapter, false)` on
   the `ServiceRegistry` (Ethereum) and `ServiceRegistryL2` (Gnosis, Polygon, Arbitrum, Optimism, Base, Celo,
   Mode). Removes the same-address multisig adoption path from service deployment. Mainnet is a direct Timelock
   call; each L2 is bridged through its mediator (AMB / FxRoot / Arbitrum Inbox retryable / OP-stack messenger).
   Polygon carries **two** adapters — `GnosisSafeSameAddressMultisig` and `PolySafeSameAddressMultisig` — batched
   as two concatenated tuples in the single FxRoot message.
2. **Extend the GuardCM allowlist** (1 call) — `setTargetSelectorChainIds(...)` adding 19 (target, selector,
   chainId) emergency-pause triples (Dispenser `setPauseState`, ServiceManager / RegistriesManager `pause`,
   per-L2 `TargetDispenserL2.pause`) plus the Mode `ServiceRegistryL2.drain` / `ServiceRegistryTokenUtility.drain`
   backfill that Phase 0 omitted. All statuses = true (additions).

The bridge encodings and the GuardCM batch are **byte-for-byte identical** to the original proposal 24, so the
L2 delivery was already simulated; only the bundling changed.

## Files
- `Proposal24aDewhitelistAndGuard.s.sol` — the builder (`buildProposal()` returns `targets/values/calldatas/
  description` and prints the `proposalId`).
- `description.txt` — byte-for-byte equal to the builder's `DESCRIPTION` (`proposalId` is computed from
  `keccak256(abi.encode(targets, values, calldatas, keccak256(description)))`).
- `estimate_arb_submission_cost.js` — Arbitrum retryable estimator (Arbitrum SDK `estimateAll`, +1000% buffers,
  `value = deposit * 10`); mirrors `scripts/proposals/proposal_15_*`. Re-run right before submission to refresh
  the baked `ARB_*` constants against L1 basefee drift.

## Fork tests (`test/`)
- `Proposal24aForkL1.t.sol` — full propose → vote → queue → execute through the live GovernorOLAS; asserts the
  mainnet de-whitelist and all 19 GuardCM triples; Arbitrum retryable is executor-funded (Timelock keeps no balance).
- `Proposal24aForkL2OpStack.t.sol` — Optimism / Base / Celo / Mode mediator replay → adapter de-whitelisted.
- `Proposal24aForkL2Other.t.sol` — Gnosis (AMB) / Polygon (FxRoot, two adapters) / Arbitrum (aliased Timelock).

```
forge test --match-contract Proposal24aFork -vvv      # uses ETH_RPC / OP_RPC / ... or public RPC defaults
```

## Operational notes
- **Arbitrum value:** the executor of `execute()` supplies the retryable ETH (`ARB_RETRYABLE_VALUE`); it flows
  executor → Governor → Timelock → Inbox, so the Timelock needs no balance. Re-run the estimator before submission.
- **Gas headroom:** ~10.3M gas leaves ~6M under the 16,777,216 cap. The 2M `MIN_GAS` on the four OP-stack sends
  (a trivial L2 sstore) is intentionally left unchanged to keep the bridged payloads byte-identical to the already-
  simulated proposal 24; it accounts for ~9.6M of the total and could be trimmed in a future revision if desired.
