# Proposal 25 — un-nominate retired staking contracts

The second of the two proposals that replace the original single 41-action bundle, which reverted
on-chain ([tx `0x540c…20f`](https://etherscan.io/tx/0x540c2026c0a122465806240becdd8381489e19e61d74e74ec184a9660621e20f))
because its `execute()` needed **~19.9M gas** while **EIP-7825** (Fusaka) caps a single transaction at
**2²⁴ = 16,777,216 gas**. This half (**32 actions**) measures **~9.55M gas**; the de-whitelists + GuardCM batch
(~10.3M) live in proposal 24.

## Action (32)
**Un-nominate staking contracts** — `VoteWeighting.removeNominee(bytes32 account, uint256 chainId)` for each
retired (account, chainId) pair across Ethereum, Gnosis, Base, Polygon, Optimism, Celo and Arbitrum.
`VoteWeighting` lives on L1 and tracks nominees for every chain via the `chainId` argument, so **all 32 calls are
direct L1 Timelock calls** — there are **no L2 bridge messages** in this proposal, and therefore no L2 fork test.

## Files
- `Proposal25Unnominate.s.sol` — the builder (`buildProposal()` returns `targets/values/calldatas/description`
  and prints the `proposalId`).
- `description.txt` — byte-for-byte equal to the builder's `DESCRIPTION`.

## Fork test (`test/`)
- `Proposal25ForkL1.t.sol` — full propose → vote → queue → execute through the live GovernorOLAS; asserts every
  one of the 32 nominees is removed from `VoteWeighting`.

```
forge test --match-contract Proposal25ForkL1 -vvv    # uses ETH_RPC or the public RPC default
```

## Operational notes
- **Nominee-removal timing:** `removeNominee` routes through `Dispenser.removeNominee`, which reverts `Overflow`
  within the last week of the ongoing epoch (`block.timestamp >= epochEnd - 1 week`). This proposal must be
  **executed with > 7 days left in the epoch** (epoch length is 14 days). The fork test mocks `getEpochEndTime`
  to exercise the removal logic regardless of where the fork block sits in the epoch.
