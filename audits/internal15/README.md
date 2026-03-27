# Internal Audit 15 — autonolas-registries (v2.20 methodology)

**Audit Date:** March 26-27, 2026
**Commit:** 180356f (origin/main)
**Repository:** `https://github.com/valory-xyz/autonolas-registries`
**Scope:** ~9,800 LOC, 32 production contracts
**Methodology:** Playbook v2.20 (620+ checklist items), bounty-audit emulation

## Objectives

Full security audit before potential Immunefi deployment. Verify all C4A findings fixed. Identify new vulnerabilities.

## Audit Streams

| # | Stream | LOC | Result |
|---|--------|:---:|--------|
| A | StakingBase (staking core) | 1,221 | 1 Low (latent reentrancy) |
| B | ServiceRegistry + ServiceManager | 2,900 | 2 Low, 2 Info |
| C | Multisigs + Recovery | 1,000 | 1 Low/Info |
| D | New Code + Utilities | 1,400 | 1 Info |

## C4A Findings Verification

| C4A # | Description | Status | Details |
|:-----:|-------------|:------:|---------|
| #1 | Reentrancy in ServiceRegistry.create() via _safeMint | **FIXED** | `_locked` guard added in ServiceManager (PR #241 commit 7674c5c) + ServiceRegistry line 226 |
| #2 | Cross-service reentrancy in StakingBase._withdraw() | **LATENT** | Code bug confirmed. StakingNativeToken on Mode only (0 balance, 0 services). Not actively exploitable. |
| #3 | Transfer failure DoS in StakingBase.withdraw | **MITIGATED** | `forcedUnstake()` provides alternative path |
| #4 | Incomplete slashing integration | **BY DESIGN** | Independent bond/reward systems |
| #5 | registerAgentsWithSignature whitelist bypass | **PRESENT** | Low — service owner consent implied |
| #6 | msg.value missing in registerAgentsWithSignature | **PRESENT** | Low — tiny amounts (1 wei per agent) |

## Security Issues

### Low. StakingBase._withdraw() cross-service reentrancy (latent)
```
StakingBase._withdraw() reads `balance` into local variable, loops through
receivers calling `_transfer()` for each, then writes `balance` back to storage
AFTER all transfers complete.

For StakingNativeToken, `_transfer()` sends ETH via `.call{value}` which gives
the receiver a callback. A contract owning two services (A and B) on the same
StakingNativeToken instance can:
1. claim(serviceA) → _withdraw → _transfer sends ETH → receive() callback
2. In callback: claim(serviceB) → _withdraw → reads stale balance → writes balance
3. Outer _withdraw writes its stale balance → overwrites inner update

Developer comment at line 564: "reentrancy is not possible since reward is set
to zero" — TRUE for same-service, FALSE for cross-service.

File: contracts/staking/StakingBase.sol:931-947

Current deployment status:
- StakingNativeToken deployed ONLY on Mode (0x88DE7346...)
- Template contract: balance=0, availableRewards=0, no services staked
- All other chains: only StakingToken (ERC20, no callback)
- StakingToken uses SafeTransferLib.safeTransfer — no reentrancy possible

Severity: Low (latent). Real code bug but not exploitable on current deployments.
Would become Medium/High if StakingNativeToken is actively used with multiple
services having a contract as reward receiver.

Suggested fix: Add reentrancy guard (_locked) to StakingBase claim(), unstake(),
forcedUnstake(), checkpoint(), checkpointAndClaim().
```
[x] Already documented or fixed

### Low. ServiceRegistry.registerAgents() missing reentrancy guard
```
registerAgents() and activateRegistration() in ServiceRegistry (and L2 variant)
have no _locked reentrancy guard, unlike create(), deploy(), terminate(), unbond()
which all have guards. Mitigated by ServiceManager having its own _locked guard,
but inconsistent.

Files: ServiceRegistry.sol:389, ServiceRegistryL2.sol:382
       ServiceRegistry.sol:353, ServiceRegistryL2.sol:346

Suggested fix: Add _locked guard for consistency.
Note: registerAgents() and activateRegistration() are called by ServiceManager only,
which has its own _locked reentrancy guard covering these calls.
```
[x] Already documented or fixed

### Low. registerAgentsWithSignature excess ETH trapped (C4A #6)
```
When registerAgentsWithSignature() is called for token-secured services,
excess msg.value beyond agentInstances.length * BOND_WRAPPER stays in
ServiceManager with no recovery mechanism.

File: ServiceManager.sol:619-630

Suggested fix: Add require(msg.value == agentInstances.length * BOND_WRAPPER).
```
[x] Already documented or fixed

### Medium. PolySafe execTransaction return value not checked — recovery module silently not enabled
```
PolySafeCreatorWithRecoveryModule.create() calls ISafe.execTransaction()
to enable the recovery module on the newly created multisig. The return
value (bool success) is NOT checked. If enableModule fails (invalid
signature, gas issues, edge case), the function completes and emits
MultisigCreated, but the recovery module is NOT actually enabled.

Impact: Service deployed with a multisig that appears to have recovery
capability but does not. If agent instances lose access, the service
owner cannot recover — defeating the entire purpose of this contract.

File: contracts/multisigs/PolySafeCreatorWithRecoveryModule.sol:201-204

Comparison: RecoveryModule uses execTransactionFromModule (module-level,
different pattern). Only PolySafe uses execTransaction with unchecked return.

Suggested fix:
  bool success = ISafe(multisig).execTransaction(...);
  if (!success) {
      revert EnableModuleFailed(multisig, recoveryModule);
  }
```
[x] Already documented or fixed

### Low/Info. PolySafe CREATE2 deployment front-running
```
PolySafe proxy address is deterministic from owner address. Attacker can
extract safeCreateSig from mempool and front-run proxy creation. No fund
loss but griefs deployment. Service owner must manually recover.

File: PolySafeCreatorWithRecoveryModule.sol:153-207
```
[x] Already documented or fixed

### Notes. registerAgentsWithSignature whitelist bypass (C4A #5, disputed)
```
registerAgents() checks OperatorWhitelist; registerAgentsWithSignature() does not.
Service owner is the caller — consent implied. Inconsistent but not exploitable.

File: ServiceManager.sol:577-635
```
[x] Already documented or fixed

### Notes. uint96(msg.value) unsafe downcast (theoretical)
```
ServiceRegistry.registerAgents() line 478: uint96(msg.value) silently truncates
if msg.value > type(uint96).max. Requires >79.2B ETH — not practically possible.

File: ServiceRegistry.sol:478, ServiceRegistryL2.sol:471
Note: Requires >79.2B ETH — not practically possible.
```
[x] Already documented or fixed

### Low. Custom reward distributor can return address(stakingContract) as receiver
```
A staker using RewardDistributionType.Custom can set a distributor that returns
the staking contract itself as a reward receiver. When _withdraw() transfers
tokens to address(this):
- StakingToken: ERC20 transfer to self succeeds, tokens stay in contract
  but balance accounting desynchronizes (tracked balance < actual balance)
- StakingNativeToken: ETH sent to self triggers receive() which increments
  balance+availableRewards, then _withdraw overwrites balance with stale value

Impact: Staker loses their own reward (self-inflicted). Tokens permanently
orphaned in contract (no drain/rescue function). Other stakers unaffected
directly — their rewards calculated from availableRewards which decrements
correctly. Balance desync is cosmetic for existing stakers.

Validation checks (line 720-733) verify sum(amounts)==reward and non-empty
arrays, but do NOT check receivers != address(this).

File: contracts/staking/StakingBase.sol:710-734 (Custom path)
      contracts/staking/StakingBase.sol:929-947 (_withdraw)

Suggested fix: Add check in _getRewardReceiversAndAmounts Custom path:
  for (uint256 i = 0; i < receivers.length; ++i) {
      if (receivers[i] == address(this) || receivers[i] == address(0)) {
          revert WrongAddress(receivers[i]);
      }
  }
```
[x] Documented

### Low. No code-existence check on Custom rewards distributor at stake time
```
stake() with RewardDistributionType.Custom validates only that the
distributor address != address(0). Does NOT check code.length > 0.
If an EOA or not-yet-deployed contract is set as distributor, the
service's claim() will revert (empty returndata from staticcall to EOA).
Impact: Self-inflicted — service owner bricks their own claims.
Other stakers unaffected (claim is per-service, not batched).

File: contracts/staking/StakingBase.sol:824-827

Suggested fix: Add require(customDistributorAddr.code.length > 0).
```
[x] Documented

### Notes. calculateStakingLastReward() view omits rounding dust for service index 0
```
checkpoint() gives rounding dust (up to numServices-1 wei) to service
at index 0. calculateStakingLastReward() does not include this bonus.
Impact: View function shows slightly less reward than actually distributed.

File: contracts/staking/StakingBase.sol:1146 vs checkpoint line 1002-1004
```
[x] Documented

### Notes. ApplicationClassifier completely untested (0 tests)
```
All 5 functions in ApplicationClassifier.sol have ZERO test coverage.
changeImplementation() uses inline assembly for proxy storage slot write.
If the constant PROXY_AGENT_CLASSIFICATION doesn't match the proxy's
fallback read slot, upgrades are silently broken.

File: contracts/utils/ApplicationClassifier.sol (124 LOC)
```
[x] Already documented or fixed

### Notes. Zero fuzz tests in entire repository
```
No fuzz/property-based tests exist. Critical paths untested for edge values:
- checkpoint() reward calculation with varying service counts
- stake() rewardDistributionInfo bit-packing
- verifyInstance() staking parameters
- Custom distributor return value validation
```
[x] Already documented or fixed

### Notes. ComplementaryServiceMetadata reentrancy guard style
```
Uses `_locked == 2` instead of `_locked > 1` used everywhere else.
Functionally equivalent for valid state space {1, 2}.

File: ComplementaryServiceMetadata.sol:116
Note: Noted. Functionally equivalent for valid state space {1, 2}.
```
[x] Already documented or fixed

---

## Review summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Medium | 1 |
| Low | 6 |
| Notes | 7 |
| **Total** | **14** |

## Verified Safe

- Service lifecycle state machine: strictly linear, no state skipping possible
- EIP-712 signature handling: correct domain separator, nonce replay protection, cross-chain safe
- RecoveryModule: linked list traversal correct, owner-only gated, PreRegistration state required
- Token bonding: balance-before/after check rejects fee-on-transfer tokens
- IdentityRegistryBridger: reentrancy guarded, immutable serviceManager acceptable with proxy upgradeability
- StakingFactory: reentrancy guarded, proxy creation deterministic
- StakingBase checkpoint: reward distribution math correct (rounding dust to first service)
- Access control: consistent manager/owner separation throughout

---

## Stream 5: Cross-Contract Interaction Chains

### Chain 1: Service Lifecycle (create -> register -> deploy -> terminate -> unbond)

**Q: Can a service be created, deployed, and terminated in a way that extracts more bond than deposited?**

NO. Verified safe. The flow:

1. `create()` (ServiceRegistry.sol:217-275): Sets `service.state = PreRegistration`. No ETH held yet.
2. `activateRegistration()` (line 353-381): Requires `msg.value == service.securityDeposit` (exact match, line 372). State -> ActiveRegistration.
3. `registerAgents()` (line 389-482): Requires `msg.value == totalBond` (exact match, line 427-428). Operator balance tracked: `mapOperatorAndServiceIdOperatorBalances[operatorService] += uint96(msg.value)` (line 478).
4. `deploy()` (line 490-541): No funds movement. State -> Deployed.
5. `terminate()` (line 598-657): Returns `refund = service.securityDeposit` (line 645) to service owner. State -> TerminatedBonded (if numAgentInstances > 0) or PreRegistration.
6. `unbond()` (line 664-744): Calculates refund from `mapServiceAndAgentIdAgentParams[serviceAgent].bond` per agent (line 714). Caps at operator's recorded balance (line 722-726: `if (refund > balance) refund = balance`). Zeroes operator balance (line 731).

Key invariant holds: `terminate()` refunds exactly `securityDeposit` (what was paid in `activateRegistration()`), and `unbond()` refunds at most what was deposited via `registerAgents()`. The slash mechanism can only reduce, never increase, operator balances.

For **token-secured services** via ServiceManager: bonds are wrapped at BOND_WRAPPER (1 wei) in ServiceRegistry, actual token bonds tracked in ServiceRegistryTokenUtility. Same flow applies -- `unbondTokenRefund()` returns exactly `mapOperatorAndServiceIdOperatorBalances[operatorService]` which was set from `totalBond` computed from `mapServiceAndAgentIdAgentBond` (line 434-436 of ServiceRegistryTokenUtility). Balance-before/after check in `registerAgentsTokenDeposit()` (line 456-464) prevents fee-on-transfer inflation.

**Q: Can an operator register -> unbond in a way that gets more back than bonded?**

NO. The `unbond()` function calculates refund from the original `agentParams.bond` values per agent instance (ServiceRegistry.sol:714), then caps at the recorded operator balance (line 724-726). If slashed, balance is lower. If not slashed, refund == original deposit. The operator balance is zeroed after refund (line 731).

### Chain 2: Staking Lifecycle (stake -> checkpoint -> claim/unstake)

**Q: Can checkpoint be called multiple times to inflate rewards?**

NO. Verified safe. `checkpoint()` (StakingBase.sol:955-1084) is protected by the time gate at line 604:
```
if (size > 0 && block.timestamp - tsCheckpointLast >= livenessPeriod && lastAvailableRewards > 0)
```
If called again in the same block, `block.timestamp - tsCheckpointLast < livenessPeriod` so no rewards are calculated (all returned arrays are empty). The checkpoint updates `tsCheckpoint = block.timestamp` at line 1068, preventing double-counting.

The reward accumulation is additive: `mapServiceInfo[curServiceId].reward += eligibleServiceRewards[i]` (line 1015). Each checkpoint period's rewards are calculated fresh from `rewardsPerSecond * ts` where `ts = block.timestamp - serviceCheckpoint` (line 631-639). Two checkpoints at T1 and T2 give rewards for [T0, T1] then [T1, T2] -- no overlap.

Total rewards are capped: `if (totalRewards > lastAvailableRewards)` triggers proportional scaling (lines 978-1007), ensuring `availableRewards` is never exceeded.

**Q: Can a service earn rewards without actually being active?**

NO, if the activity checker is configured correctly. The `_checkRatioPass()` (line 456-481) calls `activityChecker.getMultisigNonces()` and `activityChecker.isRatioPass()` via staticcall. If the activity checker returns false (nonce didn't increase enough), the service gets NO reward for that epoch and accumulates inactivity (line 1038-1054).

However: if the activity checker is a malicious/broken contract that always returns true, a service COULD earn rewards without activity. This is by design -- the activity checker is an admin-configured contract set at initialization and immutable after that.

**Item 260: Evicted services -- repeatable side effects?**

Evicted services (inactivity > maxInactivityDuration) are removed from `setServiceIds` in `_evict()` (line 488-534). Their `mapServiceInfo` entry persists with `tsStart > 0` and elevated `inactivity`. This prevents re-staking: `_stake()` checks `sInfo.tsStart > 0` and reverts with `ServiceNotUnstaked` (line 755-756). The evicted service MUST call `unstake()` or `forcedUnstake()` first, which deletes `mapServiceInfo[serviceId]` (line 884).

Evicted service rewards: If a service was evicted mid-epoch, any rewards accumulated BEFORE eviction are preserved in `sInfo.reward`. The `_unstake()` function handles this:
- `unstake()` (enforced=false): Pays out accumulated reward (line 906-912)
- `forcedUnstake()` (enforced=true): Returns reward to `availableRewards` (line 904-905)

No repeatable side effects found. The eviction is a one-way transition per staking period.

### Chain 3: Recovery -> Redeploy

**Q: Can recoverAccess -> multisig now has service owner -> new deploy with different agents?**

Verified safe. The flow:

1. `recoverAccess()` (RecoveryModule.sol:229-290): Requires `state == PreRegistration` (line 246) and `msg.sender == serviceOwner` (line 240). Replaces all multisig owners with the service owner (threshold=1).
2. After recovery, the multisig is controlled by service owner.
3. To redeploy: service owner must go through full lifecycle again: `activateRegistration()` -> `registerAgents()` -> `deploy()`.
4. `deploy()` either creates a new multisig or reuses existing one via RecoveryModule.create().
5. RecoveryModule.create() (line 307-415): Called BY ServiceRegistry (line 320-322). Verifies agent instances match service registration (line 357-365). Updates multisig owners from service owner back to new agent instances.

**Q: Can recovery be used to steal funds from old agent instances?**

The recovery gives control to the service owner, NOT to arbitrary addresses. The service owner already has trust authority over the service. After recovery, any ETH/tokens in the multisig are controlled by the service owner -- but the service owner is the rightful custodian. Old agent instances lose multisig access, which is the intended behavior of recovery (access was lost, owner recovers it).

No vulnerability: recovery requires PreRegistration state (all agents unbonded), so no agent bonds are at risk.

---

## Stream 6: Test Coverage Gaps

### Test File Summary

| File | Lines | Coverage |
|------|------:|---------|
| ServiceStaking.js | 2,345 | Main staking lifecycle, rewards, eviction, reentrancy |
| ServiceStaking.t.sol | 520 | Foundry: gas limits, edge cases |
| ServiceStakingGasLimit.t.sol | 284 | Foundry: gas limit scenarios |
| ServiceRegistry.js | 3,975 | Full service lifecycle, recovery module |
| ServiceRegistryTokenUtility.js | 547 | Token bonding, slashing, draining |
| ServiceManagerNative.js | ~600 | ETH-based service management |
| ServiceManagerToken.js | ~900 | Token-based service management |
| SafeMultisigWithRecoveryModule.js | ~400 | Recovery module creation and access |

### Functions Tested in StakingBase

- [x] stake() -- multiple tests (lines 770-1876)
- [x] unstake() -- multiple tests with activity/inactivity
- [x] checkpoint() -- tested for timing, rewards math, eviction
- [x] claim() -- tested (line 1954)
- [x] checkpointAndClaim() -- tested (line 2048)
- [x] forcedUnstake() -- tested (line 2048)
- [x] deposit() -- tested via sendTransaction
- [x] _calculateStakingRewards() -- indirectly via checkpoint
- [x] _evict() -- tested (line 1823)
- [x] _checkRatioPass() -- tested via nonce manipulation (line 2298)
- [x] _getRewardReceiversAndAmounts() -- tested for all 4 distribution types (Proportional line 967, ServiceOwner line 1181, ServiceMultisig line 1108, Custom line 1252)
- [x] Reentrancy attack via onERC721Received -- tested via ReentrancyStakingAttacker
- [x] Reentrancy attack via receive() claim -- tested (line 2225)

### Coverage Gaps Identified

1. **NO fuzz tests.** Zero `fuzz` or `invariant` keywords in test directory. All tests use hardcoded values.

2. **Item 253 (alternative paths):** The forcedUnstake path IS tested, but the cross-service claim reentrancy path (our Low finding) is NOT tested -- the ReentrancyStakingAttacker only attempts same-service reentrancy via onERC721Received and single-service claim reentrancy via receive(). It does NOT test the cross-service `_withdraw()` scenario we identified.

3. **StakingToken._checkTokenStakingDeposit()** with mismatched tokens: tested only for wrong token revert, not for edge cases with 0-decimal tokens or tokens returning wrong balanceOf.

4. **Evicted service reward claim timing**: Only one eviction test (line 1823). Does not test the case where an evicted service calls `unstake()` vs `forcedUnstake()` and the reward difference.

5. **Custom RewardsDistributor**: Tested once (line 1252) but does not test malicious distributor returning wrong amounts (the contract does validate sum == reward at line 731, but no test for the revert path).

6. **RecoveryModule.create() with already-updated multisig**: The "multisig already updated" branch (when `checkOwners.length != 1 || checkOwners[0] != serviceOwner`) is tested in ServiceRegistry.js line 3605+ but coverage of the full verification logic (reverse owner ordering) is limited.

---

## Stream 7: Key Invariants Verification

### Invariant 1: Sum of operator bonds == contract ETH/token balance (ServiceRegistryTokenUtility)

**HOLDS with caveat.** The contract balance equals:
- Sum of all active operator bonds (`mapOperatorAndServiceIdOperatorBalances`) +
- Sum of all active security deposits (from `mapServiceIdTokenDeposit[].securityDeposit`) +
- Sum of all accumulated slashed funds (`mapSlashedFunds`)

The balance-before/after check in `registerAgentsTokenDeposit()` (line 456-464) and `activateRegistrationTokenDeposit()` (line 382-390) ensures actual received tokens match declared amounts. Refunds in `unbondTokenRefund()` and `terminateTokenRefund()` send exactly the recorded amounts.

**Caveat:** If a fee-on-transfer token is used (which the balance check correctly rejects), or if tokens are sent directly to the contract (not via the API), the accounting could diverge. The `drain()` function only drains `mapSlashedFunds[token]`, not excess balance, so directly-sent tokens would be permanently locked.

### Invariant 2: Sum of staking rewards claimed <= availableRewards

**HOLDS.** Verified through `_calculateStakingRewards()` (line 586-648):

1. `totalRewards` is computed as sum of `rewardsPerSecond * ts` for each eligible service.
2. If `totalRewards > lastAvailableRewards`, proportional scaling kicks in (line 978-1007), and `lastAvailableRewards` is set to 0.
3. If `totalRewards <= lastAvailableRewards`, `lastAvailableRewards -= totalRewards` (line 1019).
4. `availableRewards` is updated from `lastAvailableRewards` (line 1023).
5. Rounding dust from proportional scaling is added to the first service (line 1000-1002), ensuring `updatedTotalRewards <= lastAvailableRewards`.

The `_withdraw()` function (line 929-948) subtracts from `balance` (not `availableRewards`), but `balance >= availableRewards` always holds because deposits increment both simultaneously and withdrawals decrement `balance`.

### Invariant 3: Every service state transition is valid (no skip)

**HOLDS.** State machine verified:

```
NonExistent -> PreRegistration (create, line 262)
PreRegistration -> ActiveRegistration (activateRegistration, line 377)
ActiveRegistration -> FinishedRegistration (registerAgents, when numAgentInstances == maxNumAgentInstances, line 473-475)
FinishedRegistration -> Deployed (deploy, line 535)
Deployed -> TerminatedBonded (terminate, when numAgentInstances > 0, line 628-629)
ActiveRegistration -> PreRegistration (terminate, when numAgentInstances == 0, line 630-631)
TerminatedBonded -> PreRegistration (unbond, when all agents unbonded, line 703-704)
```

Each transition checks the required source state:
- `activateRegistration`: requires `PreRegistration` (line 368)
- `registerAgents`: requires `ActiveRegistration` (line 408)
- `deploy`: requires `FinishedRegistration` (line 520)
- `terminate`: rejects `PreRegistration` and `TerminatedBonded` (line 624)
- `unbond`: requires `TerminatedBonded` (line 683)
- `update`: requires `PreRegistration` (line 306)

No skip is possible. No backward transition except through the designed cycle.

### Invariant 4: ERC721 ownership always matches service state

**HOLDS.** The ERC721 token (service NFT) is minted to `serviceOwner` during `create()` via `_safeMint(serviceOwner, serviceId)` (line 270). Ownership can be transferred freely via standard ERC721 functions (inherited from GenericRegistry -> ERC721). All service management functions check `ownerOf(serviceId)` (e.g., line 300, 361, 509, 617) rather than a cached owner.

For staking: `_stake()` transfers the NFT to the staking contract via `safeTransferFrom(msg.sender, address(this), serviceId)` (line 839). The `mapServiceInfo[serviceId].owner` caches `msg.sender` (line 813). On unstake, the NFT is transferred back via `transferFrom(address(this), msg.sender, serviceId)` (line 920). The `msg.sender` is verified against `sInfo.owner` (line 854-857).

Note: While staked, the NFT owner is the staking contract, NOT the service owner. This is correct -- the service owner is recorded in `mapServiceInfo` and verified on unstake.

### Invariant 5: StakingBase.balance >= sum of pending rewards

**HOLDS.** The `balance` variable tracks actual contract holdings (updated on deposit and withdrawal). `availableRewards` tracks unallocated reward pool. Pending rewards (sum of `mapServiceInfo[].reward` across all services) are carved from `availableRewards` during checkpoint.

Flow:
1. Deposit: `balance += amount`, `availableRewards += amount` (StakingNativeToken.sol:37-38, StakingToken.sol:111-112)
2. Checkpoint: `availableRewards -= totalRewards` (line 1019) or `availableRewards = 0` (line 1007)
3. Withdraw: `balance -= amounts[i]` per receiver (line 938)

Since `balance >= availableRewards + sum(pending rewards)` at all times (deposits go to both, rewards come from availableRewards, withdrawals come from balance), the invariant holds.

The only risk scenario is the cross-service reentrancy in `_withdraw()` (our Low finding), where a stale `updatedBalance` could cause incorrect balance tracking. But as noted, this requires StakingNativeToken with multiple contract-owned services -- currently not deployed actively.

---

## Methodology
- Playbook: v2.20 (620+ checklist items)
- Deployed state verified: StakingNativeToken only on Mode (0 balance, 0 services)
- C4A findings cross-referenced with code and PR history
- All 32 production contracts reviewed across 4 audit streams
- Cross-contract interaction chains traced: 3 chains verified
- Key invariants verified: 5/5 hold
- Test coverage analyzed: no fuzz tests, cross-service reentrancy untested
