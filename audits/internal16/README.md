# Internal Audit 16 — autonolas-registries (post-C4R StakingBase hardening)

**Audit Date:** April 15, 2026
**Base commit:** `bba1585` (origin/main — merge of `audit_internal15`)
**Branch tip:** `5334da6` on `fix/staking-post-c4r-hardening` (treated as if merged into `main`)
**Repository:** `https://github.com/valory-xyz/autonolas-registries`
**Scope:** delta review of `contracts/staking/StakingBase.sol` (+126 / −10 LOC) — the only production file touched by the hardening branch
**Methodology:** Playbook v2.22 delta-audit discipline — re-verify every prior staking-related C4A / C4R / internal15 finding against post-hardening code, then attack-review the diff itself

## Objectives

1. Confirm that every C4A, Code4rena 2026-01, and internal15 finding that touches `StakingBase` has a concrete fix on-branch with file:line citation, or is explicitly kept open for a documented reason.
2. Attack-review the hardening diff for new bugs, lock-bypass paths, storage-layout hazards, and residual invariants.
3. Verify that the hardening does not break any invariant held by internal15.
4. Produce a clear go/no-go recommendation for merge.

## Audit Streams

| # | Stream | LOC | Result |
|---|--------|:---:|--------|
| A | `StakingBase.sol` — reentrancy guard + receiver validation + code-existence check | 126 delta | 1 Low (latent), 3 Notes |
| B | `StakingNativeToken.sol` / `StakingToken.sol` — derivatives review | 0 delta | 1 Low (latent, same issue as Stream A — residual lock gap) |
| C | `StakingProxy.sol` — storage-layout / upgrade-compat review | 0 delta | 0 findings (no upgrade path; new slot is safe) |
| D | `test/StakingSecurityFixes.t.sol` + `test/StakingBaseCoverage.t.sol` + `test/StakingFuzz.t.sol` — coverage of the hardening | +1837 LOC | Verified: lock + distributor checks exercised; nested-deposit reentrancy case not exercised |

All other staking contracts (`StakingFactory`, `StakingVerifier`, `StakingActivityChecker`) are byte-identical to `main` and out of delta scope.

## Prior Findings Verification

### C4A and Code4rena 2026-01 (Olas) findings

| Source | Description | Previous status (internal15) | Status NOW | Verification |
|:------:|-------------|:-----------------------------|:----------:|--------------|
| C4A #1 | Reentrancy in `ServiceRegistry.create()` via `_safeMint` | FIXED (PR #241) | **FIXED** | No regression — `ServiceManager` unchanged on this branch |
| C4A #2 / C4R S-229 | Cross-service reentrancy in `StakingBase._withdraw()` | LATENT (code bug confirmed) | **FIXED** | Contract-wide `_locked` guard on 7 externals (StakingBase.sol:1119–1227) + dedicated test `test_Reentrancy_ClaimRevertsOnReentry` |
| C4A #3 | Transfer failure DoS in `StakingBase.withdraw` | MITIGATED via `forcedUnstake()` | **STILL MITIGATED** | `forcedUnstake` path unchanged (line 1187), still lock-guarded |
| C4A #4 | Incomplete slashing integration | BY DESIGN | BY DESIGN | Unchanged |
| C4A #5 / C4R S-149 | `registerAgentsWithSignature` whitelist bypass | PRESENT (Low, accepted) | **UNCHANGED** | Not in staking scope |
| C4A #6 / C4R S-1175 | `msg.value` missing in `registerAgentsWithSignature` | PRESENT (Low, accepted) | **UNCHANGED** | Not in staking scope |
| C4R S-69 | `execTransaction` return value in Recovery / multisig-create | Guarded at ServiceManager level (PR #241); RecoveryModule off-chain-checked | **UNCHANGED** | Not in staking scope |
| C4R S-430 | `slash` mechanism abuse by service owner | ACCEPTED (no economic benefit) | ACCEPTED | Unchanged |
| C4R S-858 / S-862 | `registerAgentsWithSignature` missing deadline / max bond | ACCEPTED | ACCEPTED | Unchanged |
| C4R S-901 | `registerAgents` agent instance DoS | ACCEPTED (gas-costly, permissionless) | ACCEPTED | Unchanged |
| C4R S-885 | `slash` + proportional reward split | INFO, accepted | ACCEPTED | Unchanged |
| C4R S-763 | `checkpoint` during absence of rewards | INFO, accepted (wei-level top-up mitigation) | ACCEPTED | Unchanged |
| C4R S-1187 | Token callback reentrancy broader path | PARTIAL (ServiceManager only) | **FIXED** for StakingBase | Same `_locked` guard closes the StakingBase portion |

### Internal15 findings against staking

| Internal15 section | Sev | Previous status | Status NOW | Verification |
|--------------------|:---:|-----------------|:----------:|--------------|
| Stream A Low — `StakingBase._withdraw()` cross-service reentrancy | L | latent | **FIXED** | `_locked` guard §Security Issue §A.1 |
| Stream D Low — Custom reward distributor can return `address(stakingContract)` as receiver | L | open | **FIXED** | `receivers[i] == address(this)` check at StakingBase.sol:742–744 + `test_CustomDistributor_RejectsSelfReceiver` |
| Stream D Low — No code-existence check on Custom distributor at stake time | L | open | **FIXED** | `customRewardsDistributor.code.length == 0` check at StakingBase.sol:852–854 + `test_CustomDistributor_EOAReverts` / `test_CustomDistributor_UndeployedAddressReverts` |
| Stream D Notes — `calculateStakingLastReward()` rounding dust | Info | open | **UNCHANGED** (cosmetic) | Still item #22 in `Vulnerabilities_list_registries.md`; no fix required |
| Stream D Notes — ApplicationClassifier completely untested | Info | open | **ADDRESSED** | `test/ApplicationClassifier.js` (+210) added in commit `2e6bca0` |
| Stream D Notes — Zero fuzz tests in entire repository | Info | open | **ADDRESSED** | `test/StakingFuzz.t.sol` (+379) |
| Stream B Low — `ServiceRegistry.registerAgents()` missing reentrancy guard | L | open | **UNCHANGED** | Not in staking scope; track separately |
| Stream C Low/Info — PolySafe CREATE2 front-running | L/Info | accepted | ACCEPTED | Unchanged |
| Stream D Medium — PolySafe `execTransaction` return value not checked — recovery module silently not enabled | **M** | open | **UNCHANGED** | Lives in `ServiceManager` / `PolySafeCreatorWithRecoveryModule`, out of staking-hardening scope; **still open** |
| Stream D Notes — `ComplementaryServiceMetadata` reentrancy guard style (`== 2` vs `> 1`) | Info | noted | NOTED | Unchanged |
| Stream B/D Notes — `uint96(msg.value)` unsafe downcast | Info | noted | NOTED | Unchanged |

## Security Issues

### Low (latent). `receive()` and `deposit()` on StakingBase derivatives bypass the contract-wide lock

```
The contract-wide `_locked` guard added by this branch protects the seven
external state-changing entry points on StakingBase itself (checkpoint, stake×2,
unstake, forcedUnstake, claim, checkpointAndClaim). It does NOT cover two
entry points defined on the derivatives:

  - StakingNativeToken.receive() — increments `balance` and `availableRewards`
    on incoming ETH (StakingNativeToken.sol:35-45).
  - StakingToken.deposit(uint256) — increments `balance` and `availableRewards`,
    then pulls ERC20 via safeTransferFrom (StakingToken.sol:109-122).

Neither of these is a reentrancy *source* in normal usage, but both directly
WRITE to the `balance` storage slot — the same slot that `_withdraw()` caches
into a local variable (StakingBase.sol:957 `uint256 updatedBalance = balance`).

Attack sketch (StakingNativeToken):

1. Attacker owns service A with RewardDistributionType.Custom and a distributor
   that points the first receiver at an attacker-controlled contract.
2. Attacker calls checkpointAndClaim(serviceA). Lock set to 2, _claim runs,
   _withdraw begins:
     updatedBalance = balance;            // local = B
     updatedBalance -= amounts[0];        // local = B - a0
     _transfer(attacker, amounts[0]);     // .call{value: a0}("")
3. Attacker's receive() callback fires. Attacker does NOT call any of the
   7 locked externals (would revert). Instead attacker calls:
     stakingNativeToken.receive{value: Y}("");
   The nested receive() writes directly to storage:
     balance = B + Y;
     availableRewards = A + Y;
4. Nested call returns. Outer _withdraw loop completes and writes
     balance = updatedBalance;            // ≈ B - Σ amounts
   This OVERWRITES the nested `balance = B + Y` from step 3. The Y wei is no
   longer tracked in `balance`.
5. Post-attack invariants:
     Actual contract ETH: B + Y - Σ amounts  (Y orphaned in contract)
     `balance` storage:   B - Σ amounts      (Y less than actual)
     `availableRewards`:  A + Y              (Y more than expected)

Consequences: `availableRewards` now exceeds `balance` by Y. Future claim
attempts that try to pay from `balance` can underflow `updatedBalance -= amount`
on a subsequent _withdraw → DoS of future honest claims.

The attacker LOSES the Y ETH — it becomes permanently orphaned because no
drain/rescue function exists. This is a self-griefing / DoS vector, not a
profit vector.

File: contracts/staking/StakingNativeToken.sol:35-45 (unlocked receive)
File: contracts/staking/StakingToken.sol:109-122 (unlocked deposit)
File: contracts/staking/StakingBase.sol:955-974 (_withdraw's balance-cache
      pattern that the attack exploits)

Exploitability today: NONE in production.
  - StakingNativeToken has no active proxies on any supported chain
    (confirmed by internal15 Stream A deployed-state check).
  - StakingToken's deposit() variant requires an ERC20 with a transfer hook
    (ERC777 / ERC1363). OLAS is a standard ERC20 with no hooks, so
    SafeTransferLib.safeTransfer never yields control to the receiver, and
    the nested deposit() call cannot be injected from within _transfer().

Severity: Low (latent). The underlying defect is exactly the class of issue
this hardening branch set out to close — the lock is a control-flow guard
only, not a mutex on the `balance` storage slot. Upgrade to Medium if
StakingNativeToken is ever re-activated for production use, or if a
hook-carrying token is adopted as a staking token.

Suggested fix: extend the lock to the two derivative entry points. Preferred
option (symmetrical with the existing hardening):

  // StakingNativeToken.sol
  receive() external payable {
      if (_locked > 1) revert ReentrancyGuard();
      _locked = 2;
      uint256 newBalance = balance + msg.value;
      uint256 newAvailableRewards = availableRewards + msg.value;
      balance = newBalance;
      availableRewards = newAvailableRewards;
      emit Deposit(msg.sender, msg.value, newBalance, newAvailableRewards);
      _locked = 1;
  }

  // StakingToken.sol — analogous change to deposit(uint256)

Both `_locked` and `ReentrancyGuard` are already visible from the derivatives:
_locked is `internal`, ReentrancyGuard is a file-scope error in StakingBase.sol.
No visibility change required; ≤20 LOC total.

Alternative option: move the `balance` write inside `_withdraw()` into the
per-iteration body (re-read / re-write per receiver instead of caching into
a local). Smaller conceptual change but costs extra SLOAD per iteration.

Test coverage: the existing ReentrancyStakingAttacker helper only exercises
reentry via `checkpointAndClaim` and `unstake` (both of which are now locked).
It does not attempt the `receive{value}` nested-deposit variant described
above. A dedicated foundry test that asserts (a) the attack reverts with
ReentrancyGuard after the fix, or (b) explicitly demonstrates the desync
without the fix, would close the coverage gap.
```
[ ] Open — recommend fixing in this branch before merge, or tracking as
    must-fix before any StakingNativeToken reactivation.

### Notes. `_locked` inline initializer is a no-op in proxy clones

```
StakingBase.sol:339:
  uint256 internal _locked = 1;

Solidity inline storage initializers run in the implementation contract's
constructor, not in proxy clones. StakingBase is deployed as an implementation
and used via StakingProxy delegatecall (StakingProxy.sol:40-51), so the `= 1`
inline initializer is never applied to proxy storage. On a fresh proxy clone,
`_locked` starts at 0.

Behavioural impact: NONE. The first call on each proxy sees 0 > 1 = false,
passes the guard, sets _locked = 2 before any user-reachable logic runs, then
writes _locked = 1 on exit. Any reentry during that first call still sees
_locked = 2 and reverts. After the first call the intended resting value (1)
is reached. Subsequent calls follow the 1 → 2 → 1 transition as intended.

Cosmetic impact: a reader may misread the inline `= 1` as implying the first
call follows the 1 → 2 → 1 pattern rather than the 0 → 2 → 1 pattern that
actually occurs on fresh proxies.

File: contracts/staking/StakingBase.sol:339

Suggested fix (optional): set `_locked = 1;` explicitly inside `_initialize()`,
or drop the inline `= 1` (0 behaves identically on the first call). No
functional change required.
```
[x] Noted — informational only

### Notes. Lock is inlined in every entry point rather than a modifier

```
Each of the seven locked entry points repeats the 4-line check/set/unlock
sequence:
  if (_locked > 1) { revert ReentrancyGuard(); }
  _locked = 2;
  ...
  _locked = 1;

This is robust (no modifier surprises, no hidden state) and matches the
style used in ServiceManager / ServiceRegistry (C4A #1 fix). It is mildly
error-prone if a new external entry point is added later without the author
remembering to copy the 4 lines. A `nonReentrant` modifier would make the
intent structural.

Files: contracts/staking/StakingBase.sol:1119-1227 (seven entry points)

No action required — style consistency with the rest of the registries
codebase.
```
[x] Noted — stylistic

### Notes. `_withdraw` comment about "balance ≥ sum of amounts" is conditional

```
contracts/staking/StakingBase.sol:952-953:
  /// @notice The balance is always greater or equal the sum of amounts,
  ///         as follows from the contract logic.

This assertion holds for flows controlled entirely by StakingBase's seven
locked externals. It does NOT hold under the §"Low (latent)" scenario above,
where a nested `receive{value}` / `deposit()` call during _withdraw can
transiently desync `balance` below actual ETH holdings.

If the Low finding above is fixed (lock extended to receive/deposit), this
comment becomes fully accurate. If the Low finding is left as-is, the comment
should be weakened to:
  /// @notice The balance is greater or equal the sum of amounts for the
  ///         flow controlled by this contract's locked entry points.

File: contracts/staking/StakingBase.sol:952
```
[x] Noted — tied to the Low finding above

---

## Hardening diff — what was changed and why

### §A.1 Contract-wide reentrancy guard

A single-slot `_locked` state variable is added as the last slot of `StakingBase` (StakingBase.sol:339). Seven external state-changing entries take the lock via an inline check:

| Entry point | Line | Internal flow reached |
|-------------|:----:|-----------------------|
| `checkpoint()` | 1119–1134 | `_checkpoint()` |
| `stake(uint256)` | 1140–1150 | `_stake(id, 0)` |
| `stake(uint256,uint256)` | 1158–1168 | `_stake(id, info)` |
| `unstake(uint256)` | 1173–1183 | `_unstake(id, false)` |
| `forcedUnstake(uint256)` | 1187–1197 | `_unstake(id, true)` |
| `claim(uint256)` | 1202–1212 | `_claim(id, false)` |
| `checkpointAndClaim(uint256)` | 1217–1227 | `_claim(id, true)` |

The previously-`public` `checkpoint()` function is split in two:
- Internal `_checkpoint()` (line 983) contains the original logic, unchanged apart from visibility.
- External `checkpoint()` wrapper (line 1119) takes the lock, calls `_checkpoint()`, releases the lock.

The three internal flows that used to call the public `checkpoint()` now call `_checkpoint()` directly to avoid self-deadlocking the lock:
- `_claim` (line 557) — was `checkpoint()`
- `_stake` (line 763) — was `checkpoint()`
- `_unstake` (line 876) — was `checkpoint()`

### §A.2 Custom rewards distributor receiver validation

`_getRewardReceiversAndAmounts()` now rejects two forbidden receiver addresses when the distribution type is `Custom`:

```solidity
// StakingBase.sol:736–744
for (uint256 i = 0; i < amounts.length; ++i) {
    if (receivers[i] == address(0)) {
        revert ZeroAddress();
    }
    if (receivers[i] == address(this)) {
        revert UnauthorizedAccount(receivers[i]);
    }
    amountCheck += amounts[i];
}
```

New custom error: `UnauthorizedAccount(address)` at line 196.

### §A.3 Custom rewards distributor code-existence check

`_stake()` refuses to register a custom distributor whose address has no code:

```solidity
// StakingBase.sol:844–854
if (rewardDistributionType == RewardDistributionType.Custom) {
    address customRewardsDistributor = address(uint160(rewardDistributionInfo >> 8));
    if (customRewardsDistributor == address(0)) {
        revert ZeroAddress();
    }
    if (customRewardsDistributor.code.length == 0) {
        revert ContractOnly(customRewardsDistributor);
    }
}
```

Post-EIP-6780 (Cancun) `SELFDESTRUCT` only clears code in the same transaction as deploy, and `CREATE2` redeploy requires the prior occupant to be absent. Both paths are closed, so a deployed-contract check at stake-time is sufficient — no TOCTOU hazard between stake and claim.

### §A.4 Cosmetic refactors (commits `c432404`, `cf18220`)

- External `checkpoint()` wrapper uses named return parameters (`serviceIds`, `finalEligibleServiceIds`, `finalEligibleServiceRewards`, `evictServiceIds`) and drops the explicit `return` statement — NOP-equivalent, earlier lock release.
- Inline comments clarify that `RewardDistributionType(uint8(...))` reverts with `Panic(0x21)` for out-of-range values, so downstream reads of `sInfo.rewardDistributionInfo` are safe (it is only written via `_stake`, which validates the enum range).

---

## Review summary

| Severity | Count |
|----------|------:|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low (latent) | 1 |
| Notes | 3 |
| **Total** | **4** |

## Verified Safe

- **C4A #2 scenario — cross-service `claim` / `unstake` reentrancy** is now blocked. Attacker's `receive()` / `onERC721Received` callback calling back into any of the seven locked externals sees `_locked == 2` and reverts with `ReentrancyGuard`. Confirmed by `test_Reentrancy_ClaimRevertsOnReentry` and by the existing `ReentrancyStakingAttacker` helper (`contracts/test/ReentrancyStakingAttacker.sol:61-87`).
- **Custom-distributor self-receiver path** — `_getRewardReceiversAndAmounts` rejects `address(this)` before `_withdraw` is called, so the old orphan-by-self-transfer scenario is prevented. Confirmed by `test_CustomDistributor_RejectsSelfReceiver`.
- **Custom-distributor EOA/undeployed address path** — `_stake` rejects the set-up, so the staticcall-to-EOA-returns-empty brick is prevented. Confirmed by `test_CustomDistributor_EOAReverts` and `test_CustomDistributor_UndeployedAddressReverts`.
- **Internal flows do not self-deadlock the lock** — `_claim`, `_stake`, `_unstake` all route through `_checkpoint()` (internal, no lock), not the external `checkpoint()`. Verified by reading lines 557, 763, 876.
- **Storage layout upgrade-compat** — `StakingProxy.sol:27-37` pins the implementation address in a fixed slot inside the constructor; there is no upgrade function. Existing deployed proxies are permanently bound to their original implementation bytecode, so the new `_locked` slot cannot collide with any live proxy's storage. New proxies deployed after this change pick up the new layout cleanly.
- **Custom distributor call path is STATICCALL** — `ICustomRewardsDistributor.getRewardReceiversAndAmounts` is declared `external view`, so Solidity compiles the call at `StakingBase.sol:725` as `STATICCALL`. A malicious distributor that attempts state modification will revert automatically. The lock guard is defense-in-depth here, not a strict requirement.
- **View functions correctly unlocked** — `calculateStakingLastReward`, `calculateStakingReward`, `calculateStakingRewardReceiversAndAmounts`, `getStakingState`, `getNextRewardCheckpointTimestamp`, `getServiceInfo`, `getServiceIds`, `getAgentIds` do not write state and do not take the lock.
- **`onERC721Received` (inherited from solmate `ERC721TokenReceiver`)** — default implementation returns the selector constant and does nothing else; no user code path, no reentrancy vector.
- **Check-effect-interaction ordering** preserved: `_claim` zeros `sInfo.reward` before the external transfer (StakingBase.sol:569); `_unstake` deletes `mapServiceInfo[serviceId]` before the NFT transfer (line 910); both were already correct and are unchanged.

---

## Stream 5: Cross-Contract Interaction Chains

The hardening only affects the **Staking Lifecycle** chain from internal15. The other two chains (Service Lifecycle, Recovery → Redeploy) are unaffected because `ServiceRegistry`, `ServiceManager`, `PolySafeCreatorWithRecoveryModule`, and `RecoveryModule` are byte-identical to `main` on this branch.

### Chain: Staking Lifecycle (stake → checkpoint → claim/unstake) — revisited

**Q: After the hardening, can a malicious receiver reenter via the reward callback and corrupt reward accounting?**

NO for the seven locked externals. The `_locked` check at each entry point reverts any nested call with `ReentrancyGuard()`. The revert propagates through the low-level `.call{value}` inside `_transfer` and surfaces as `TransferFailed` to the outer `_withdraw` (this is the behaviour tested by `test_Reentrancy_ClaimRevertsOnReentry`).

YES, latently, for `StakingNativeToken.receive()` and `StakingToken.deposit()` when reached via a nested callback during `_withdraw`. See the Low finding above. Not exploitable on the current production deployment; recommendation is to close this class of issue as part of the same hardening commit.

**Q: Does the rename of `checkpoint` → `_checkpoint` leak state to callers that previously relied on the public signature?**

NO for on-chain callers:
- No other contract in this repository calls `StakingBase.checkpoint()` internally through the interface. Searched via `grep -rn "\.checkpoint(" contracts/` — only `ReentrancyStakingAttacker` calls it on the staking contract from outside, which still hits the external wrapper.
- Off-chain integrators that were calling the public `checkpoint()` continue to work because the external function is still called `checkpoint()` with the same selector, return types, and argument list. The only change is that it now reverts with `ReentrancyGuard` if reached via nested reentry — impossible for an EOA under normal gas rules.

**Q: Does `_stake`'s reversion on non-contract custom distributor introduce any new DoS vector?**

NO. The check happens before any state is written (`setServiceIds.push` is at line 862, AFTER the custom distributor validation at line 844–854). A failing check reverts before `sInfo` is mutated. No stuck state. Existing services are unaffected — the check only runs when a staker explicitly opts in via `RewardDistributionType.Custom`.

**Q: Does the `checkpoint()` external wrapper take the lock early enough?**

YES. Lock is set to `2` on the first instruction after the revert check (StakingBase.sol:1129). `_checkpoint()` is called only after the lock is set. Nested reentry during `_checkpoint`'s staticcall to the activity checker would see `_locked == 2` and revert — which is fine because the activity checker is a trusted, audited contract set at initialization.

---

## Stream 6: Test Coverage of the Hardening

### New test files on this branch

| File | Added LOC | Covers |
|------|----------:|--------|
| `test/StakingSecurityFixes.t.sol` | +366 | Reentrancy guard + custom-distributor receiver/code checks |
| `test/StakingBaseCoverage.t.sol` | +1092 | Pushes StakingBase coverage from 46.60% → 100% lines |
| `test/StakingFuzz.t.sol` | +379 | Fuzz suite for reward bit-packing, checkpoint math, proportional scaling |
| `test/ApplicationClassifier.js` | +210 | Internal15 coverage closure |

### Dedicated hardening tests (`test/StakingSecurityFixes.t.sol`)

| Test | What it checks | Status |
|------|----------------|:------:|
| `test_Reentrancy_ClaimRevertsOnReentry` | Attacker's `receive()` calls `checkpointAndClaim` → reverts through `TransferFailed` | [x] |
| `test_Checkpoint_PublicCallSucceeds` | External `checkpoint()` still callable (rename didn't break the public ABI) | [x] |
| `test_CustomDistributor_EOAReverts` | `_stake` rejects EOA distributor with `ContractOnly` | [x] |
| `test_CustomDistributor_UndeployedAddressReverts` | `_stake` rejects unused address | [x] |
| `test_CustomDistributor_DeployedContractAccepted` | Happy path | [x] |
| `test_CustomDistributor_RejectsZeroAddressReceiver` | `_withdraw` rejects `address(0)` receiver | [x] |
| `test_CustomDistributor_RejectsSelfReceiver` | `_withdraw` rejects `address(this)` receiver | [x] |

### Coverage gaps identified by this review

1. **Nested-deposit reentrancy case (`receive{value}` or `deposit` called from within `_withdraw`)** — NOT exercised by any test. `ReentrancyStakingAttacker.receive()` calls `checkpointAndClaim(localServiceId)`, which is now blocked by the lock; it does not attempt a `receive{value}` nested-deposit to desync `balance`. A dedicated test is recommended — see the Low finding suggested fix for the form it should take.
2. **`ReentrancyStakingAttacker` for cross-service** — internal15 already flagged this as a coverage gap. The current attacker uses a single `localServiceId` and re-enters via the same service. A multi-service variant that claims service A in the outer call and re-enters into service B in the callback would more directly match the C4A #2 scenario, even though the lock closes both single- and cross-service variants equivalently.
3. **Lock release on revert** — no explicit negative test that confirms a revert during `_withdraw` releases the lock (it does, because the inner revert propagates and undoes the `_locked = 2` SSTORE as part of the outer revert; but an explicit test would document the intent).

None of these gaps represents a new risk — they are test-quality observations.

---

## Stream 7: Key Invariants Verification (delta from internal15)

Re-checking the five invariants from internal15 §Stream 7 against post-hardening code.

### Invariant 1: Sum of operator bonds == contract ETH/token balance (ServiceRegistryTokenUtility)

**HOLDS** — unchanged. `ServiceRegistryTokenUtility` is not touched by this branch.

### Invariant 2: Sum of staking rewards claimed ≤ availableRewards

**HOLDS** — unchanged by the hardening. The reward calculation path (`_calculateStakingRewards`, `_checkpoint`) is byte-identical except for the rename; the proportional-scaling branch at line 1006–1048 is intact. The new lock only affects reentry, not the arithmetic.

### Invariant 3: Every service state transition is valid (no skip)

**HOLDS** — unchanged. State machine lives in `ServiceRegistry`, not touched.

### Invariant 4: ERC721 ownership always matches service state

**HOLDS** — unchanged. `_stake` still transfers the NFT to `address(this)` at line 865; `_unstake` still transfers it back at line 946. Both paths now run under the `_locked` guard, which eliminates the pre-existing risk of nested re-entry during `safeTransferFrom`'s `onERC721Received` callback.

### Invariant 5: StakingBase.balance ≥ sum of pending rewards

**PARTIALLY HOLDS — same caveat as internal15**, now narrower in scope but not fully closed.

- For the seven locked externals, the invariant holds: `_withdraw` caches `balance` locally, decrements the local per-iteration, writes back at the end. Since no nested call can re-take the lock, no other flow can write to `balance` mid-loop → the cached value is guaranteed to be consistent with the final write. ✓
- The residual gap is the one described in the Low finding: `StakingNativeToken.receive()` and `StakingToken.deposit()` are not lock-protected, so a nested callback that calls them during `_withdraw` can desync `balance` vs actual holdings. On current deployments this is not exploitable (StakingNativeToken has no active proxies; OLAS has no transfer hooks), but the invariant is not unconditionally true for all reachable configurations.

Recommendation: close the gap via the suggested fix above so that Invariant 5 becomes unconditional.

---

## Methodology

- **Base commit:** `origin/main = bba1585` (post-internal15 merge, contains the 13-item `Vulnerabilities_list_registries.md` and internal15 README).
- **Branch reviewed:** `fix/staking-post-c4r-hardening` at `5334da6`, treated as if merged into `main` per audit discipline rule "review mergeable branches".
- **Delta scope:** one production file (`contracts/staking/StakingBase.sol`), verified via:
  ```
  git log origin/main..origin/fix/staking-post-c4r-hardening -- contracts/
  # returns exactly 3 commits, all touching only StakingBase.sol
  ```
- **Finding inventory:** extracted from (a) internal15 `audits/internal15/README.md`, (b) pre-hardening `docs/Vulnerabilities_list_registries.md` at commit `f59b339^`, (c) internal15 memory (`olas-internal-audits.md`).
- **Verification per item:** on-branch file:line citation for every "FIXED" disposition, with the corresponding forge test named where applicable.
- **Attack-review of the diff itself:** full DEFI-ATTACK-PATTERNS reentrancy subset (read-only, cross-contract, fallback/receive bypass, lock self-deadlock, CEI, CREATE2/SELFDESTRUCT distributor-swap, staticcall-to-EOA), plus proxy storage-layout analysis.
- **Tests consulted:** `test/StakingSecurityFixes.t.sol` (dedicated hardening suite), `contracts/test/ReentrancyStakingAttacker.sol` (attacker helper), and the forge coverage suite `test/StakingBaseCoverage.t.sol`.
- **Out of scope:** everything outside `contracts/staking/*` that is not directly invoked by the hardening diff. Open items in `ServiceRegistry` / `ServiceManager` / multisig-creation contracts (e.g., internal15 Stream D Medium on PolySafe `execTransaction` return) are **not** re-audited here; they remain in the vuln list as previously classified.

---

## Verdict

**The hardening branch delivers what it claims.** All four target classes of issue — cross-service `_withdraw` reentrancy (C4A #2 / C4R S-229), custom-distributor address validation, custom-distributor code-existence, and the broader token-callback reentrancy path (C4R S-1187, StakingBase portion) — are closed on-code with named file:line citations and dedicated forge tests. No pre-existing finding has been missed. The hardening diff does not introduce any new High or Medium vulnerability.

**One residual Low/latent defect is documented above.** The `_locked` guard is a control-flow guard on seven external entry points, not a mutex on the `balance` storage slot. `StakingNativeToken.receive()` and `StakingToken.deposit()` on the derivatives remain unlocked and can — in theory — be reached via a nested callback during `_withdraw`, producing a `balance` vs `availableRewards` desync. Not exploitable on the current production deployment (StakingNativeToken has no active proxies; OLAS has no transfer hooks). Upgrade to Medium if StakingNativeToken is ever re-activated or if a hook-carrying token is adopted as the staking token.

**Recommendation for merge:**

- **Preferred:** extend the `_locked` guard to `StakingNativeToken.receive()` and `StakingToken.deposit()` in this same branch before merging (≤20 LOC). This closes the entire `_withdraw` / balance-desync class in one commit, matching the stated scope of the hardening, and Invariant 5 becomes unconditional.
- **Acceptable:** merge as-is and track the Low finding as a must-fix-before-reactivation for StakingNativeToken. The current deployment is not exposed.

Either path is safe for production; the preferred option is strictly cleaner.

---

## Appendix A — Verification commands

```bash
# Branch scope
git log --oneline origin/main..origin/fix/staking-post-c4r-hardening
git diff --stat origin/main...origin/fix/staking-post-c4r-hardening

# Production-code scope only
git log origin/main..origin/fix/staking-post-c4r-hardening -- contracts/
# → 3 commits: f59b339, c432404, cf18220 — all StakingBase.sol only

# Fix commit inspection
git show f59b339 --stat
git show f59b339 -- contracts/staking/StakingBase.sol

# Vulnerabilities list before/after
git show f59b339^:docs/Vulnerabilities_list_registries.md > /tmp/vuln-before.md
git show f59b339:docs/Vulnerabilities_list_registries.md  > /tmp/vuln-after.md
diff /tmp/vuln-before.md /tmp/vuln-after.md
# → items #22, #23, #24, #26 removed as "now-fixed"

# Proxy upgrade-compat check
cat contracts/staking/StakingProxy.sol
# → constructor-pinned implementation, no upgrade function
```

## Appendix B — Key file:line references

| Reference | Purpose |
|-----------|---------|
| `StakingBase.sol:192-196` | New errors `ReentrancyGuard`, `UnauthorizedAccount` |
| `StakingBase.sol:338-339` | `_locked` storage slot |
| `StakingBase.sol:557, 763, 876` | Internal flows switched from `checkpoint()` → `_checkpoint()` |
| `StakingBase.sol:736-744` | Receiver validation (zero + self-receiver) in `_getRewardReceiversAndAmounts` |
| `StakingBase.sol:725` | Custom distributor `STATICCALL` site |
| `StakingBase.sol:844-854` | Custom distributor code-existence check in `_stake` |
| `StakingBase.sol:952-974` | `_withdraw` (unchanged body; balance-cache pattern referenced by the Low finding) |
| `StakingBase.sol:983` | Internal `_checkpoint()` (renamed from public `checkpoint`) |
| `StakingBase.sol:1119-1134` | External `checkpoint()` wrapper with lock |
| `StakingBase.sol:1140-1227` | Six further locked entry points (stake×2, unstake, forcedUnstake, claim, checkpointAndClaim) |
| `StakingNativeToken.sol:35-45` | Unlocked `receive()` (Low finding §) |
| `StakingToken.sol:109-122` | Unlocked `deposit()` (Low finding §) |
| `StakingProxy.sol:27-51` | Constructor-pinned implementation, no upgrade path |
| `test/StakingSecurityFixes.t.sol` | New dedicated hardening test suite |
| `test/StakingBaseCoverage.t.sol` | New 100%-line coverage suite |
| `test/StakingFuzz.t.sol` | New fuzz suite |
| `contracts/test/ReentrancyStakingAttacker.sol:61-87` | Attacker helper (`receive()` + `onERC721Received` callbacks) |

## Appendix C — Commits on the hardening branch (ahead of `origin/main`)

```
5334da6 test: StakingBase coverage suite reaches 100% lines
cf18220 doc: clarify enum range gating for RewardDistributionType
c432404 refactor: name return params in checkpoint, drop return statement
f59b339 fix: harden StakingBase post-C4R audit
bba1585 Merge pull request #284 from valory-xyz/audit_internal15
19cdb66 Merge pull request #285 from valory-xyz/doc/vulnerabilities-md-and-relative-links
b63ac75 doc: add explicit C4 source tag for S-229 in vulnerabilities list
58f2585 doc: convert vulnerabilities PDF to markdown and use relative links
2e6bca0 test: add ApplicationClassifier tests and staking fuzz tests
3378b18 doc: addressing audit
3b41f26 doc: audit internal15
```

*Audit performed 2026-04-15. Branch tip at time of audit: `5334da6`. All findings are against code present on `origin/fix/staking-post-c4r-hardening` at that commit.*
