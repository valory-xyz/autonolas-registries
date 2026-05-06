# Internal audit 17 — closing PR review (C4R 2026-01 registries-scope cross-reference)

**Date:** 2026-05-06
**Scope:** Every C4R 2026-01 Olas finding whose code lives in `autonolas-registries`. Tokenomics findings are tracked in [`autonolas-tokenomics/audits/internal16/FINAL_REVIEW.md`](../../../autonolas-tokenomics/audits/internal16/FINAL_REVIEW.md); governance findings in `autonolas-governance/audits/internal19`. Both are explicitly out of scope for this document.
**Source of truth — C4R draft report:** [gist `kobi-c4/e232003edf0a4aa5fef5d0b6f0717b38`](https://gist.github.com/kobi-c4/e232003edf0a4aa5fef5d0b6f0717b38)
**Source of truth — fix dispositions / on-chain implications:** [`audits/internal17/README.md`](README.md). This doc is a C4R-ID-keyed re-presentation of the same dispositions, intended as a single landing page for downstream auditors who arrive holding the C4R draft and want to know, finding-by-finding, where each registries-scope item was addressed.

> **Why this doc exists.** [`audits/internal17/README.md`](README.md) carries the full disposition story but is organised around the audit's own structure (delta vs internal16, on-chain owner map, hygiene table). A reader holding only the C4R draft (e.g. an Immunefi reviewer, a third-party auditor, or a future maintainer trying to verify "C4R H-06 — was it fixed or only documented?") has to navigate around that internal structure. This file collapses the answer to a single matrix keyed by C4R ID, with the fix commit hash (or `docs/Vulnerabilities_list_registries.md` entry number) cited inline.

> **What this doc does *not* duplicate.** This is **not** a re-audit. The fix mechanics, the §A.5 derivative reentrancy lock attack-review, the on-chain owner map (§5), and the deployment-status analysis (`StakingFactory` allowlist semantics) live in [`audits/internal17/README.md`](README.md). Use this doc to navigate from a C4R ID to the fix commit; use the README to understand what the fix actually does and whether the live on-chain proxies have it yet.

---

## §1. Disposition legend

Same legend as [`audits/internal17/README.md` §0](README.md), using the two orthogonal status columns (Code status × Deployment status) introduced for this audit cycle.

**Code status:**

| Code status | Meaning |
|---|---|
| ✅ Fixed in code | Fix landed in a named commit on `origin/main` (or branch staged for merge). Cited inline. |
| 📝 Documented | Not fixed; explicitly accepted in [`docs/Vulnerabilities_list_registries.md`](../../docs/Vulnerabilities_list_registries.md). Cited as **VL #N**. |
| 🔄 Resolved by replacement | Surface that the C4R finding targeted no longer exists. |
| ⚖️ Rejected on review | Finding does not reproduce on the audited code; rebuttal cited. |

**Deployment status** (for ✅ rows only; `—` otherwise):

| Deployment status | Meaning |
|---|---|
| 🟢 Live on-chain | Address in `docs/configuration.json` references the post-fix artifact (per `internal17/README.md` §5; not bytecode-verified in this report). |
| 🟡 Pending redeploy | Code fix landed in source; on-chain bytecode is still pre-fix; redeploy of an existing contract is required. |
| ⚪ Code fix only — never deployed | Source on this audit's HEAD has never been deployed. For staking implementations, this means the fix will land as a **new** allowlisted entry in `StakingVerifier`, alongside (not replacing) the existing one — pre-existing `StakingProxy` instances are constructor-pinned and remain on their original implementation by design (see `internal17/README.md` §5.5). |

**Important — `docs/Vulnerabilities_list_registries.md` is forward-looking.** Per team policy applied across all three Olas repos, VL is a "currently known, not yet resolved" list. When a finding is fixed, its VL entry is **removed**, not annotated. The historical record for fixed items lives in (a) the audit README that closed it, (b) the fix commit, and (c) this doc. So a C4R finding marked ✅ Fixed below will *not* have a corresponding live VL entry — that is intentional, not an omission.

**Per-row "Disposition" reads from left to right.** Severity is the C4R rating; *Code status* is one of the four buckets above; *Deployment status* applies only to ✅ rows; *Where it landed* names the fix commit (linked) or VL entry (numbered) or rejection rationale; *Evidence on `origin/main`* points at file:line where the relevant logic now lives or where the finding's referenced surface has been removed.

---

## §2. Registries-scope C4R findings — full matrix

Eleven C4R 2026-01 findings touch this repo: **5 High + 2 Medium + 4 Low**. All are listed below. The full attack-review and fix-validation for each lives in [`audits/internal17/README.md` §4.1–§4.11](README.md).

### High (5)

| C4R | C4R sub-ID | Title | Code status | Deployment status | Where it landed | Evidence on `origin/main` |
|-----|------------|-------|-------------|-------------------|-----------------|---------------------------|
| **H-05** | S-229 | Insolvency via cross-service reentrancy in `StakingBase._withdraw` | ✅ Fixed in code | ⚪ Code fix only — never deployed¹ | [`f59b339`](https://github.com/valory-xyz/autonolas-registries/commit/f59b339) (PR [#287](https://github.com/valory-xyz/autonolas-registries/pull/287), `fix/staking-post-c4r-hardening`) + [`36609be`](https://github.com/valory-xyz/autonolas-registries/commit/36609be) (PR [#288](https://github.com/valory-xyz/autonolas-registries/pull/288), `fix/staking-derivative-reentrancy-lock`, §A.5 derivative follow-up) | Contract-wide single-slot `_locked` at `contracts/staking/StakingBase.sol:339`; inline check + set + unlock on **9** external state-changing entry points: `checkpoint`, `stake(uint256)`, `stake(uint256,uint256)`, `unstake`, `forcedUnstake`, `claim`, `checkpointAndClaim` (StakingBase.sol:1119–1227), plus `StakingNativeToken.receive()` (StakingNativeToken.sol:35–53) and `StakingToken.deposit(uint256)` (StakingToken.sol:109–130). Public `checkpoint()` split into external wrapper + internal `_checkpoint()` (StakingBase.sol:983) so internal flows (`_claim`, `_stake`, `_unstake` at 557, 763, 876) avoid self-deadlock. Test: `test/StakingSecurityFixes.t.sol:test_Reentrancy_ClaimRevertsOnReentry`, plus 4 tests in `test/StakingDerivativeReentrancy.t.sol` (399 LOC) — 2 nested-entry rejection tests (`test_Reentrancy_NestedReceive_RevertsWithGuard`, `test_Reentrancy_NestedDeposit_RevertsWithGuard`) and 2 honest-path regression tests (`test_Receive_HonestDepositSucceeds`, `test_Deposit_HonestDepositSucceeds`). |
| **H-06** | — | Service owner can steal protocol tokens via reentrancy in `ServiceManager.create` (via `onERC721Received`) | ✅ Fixed in code | 🟢 Live on-chain² | [`7674c5c`](https://github.com/valory-xyz/autonolas-registries/commit/7674c5c) (PR [#241](https://github.com/valory-xyz/autonolas-registries/pull/241), `8004_extension`) | `_locked` acquired in `ServiceManager.create` at `contracts/ServiceManager.sol:203–206` and released at line 255, wrapping `IService(serviceRegistry).create(...)`. `ServiceRegistry.create` mirrors with `_locked` at `contracts/ServiceRegistry.sol:226–229` / 274; state writes (`mapServices[serviceId] = service`, `totalSupply = serviceId`) at lines 266–267 happen **before** `_safeMint(serviceOwner, serviceId)` at line 270 (which is inside the lock window). `ServiceRegistryL2.create` mirrors L1 (lock at L2:218–221/266; `_safeMint` at line 262). The `onERC721Received` callback can no longer re-enter `ServiceManager.create` / `ServiceRegistry.create` to mutate bond parameters before `createWithToken` records them. |
| **H-07** | S-149 | `registerAgentsWithSignature` operator whitelist bypass | 📝 Documented | — | VL **#14** | `contracts/ServiceManager.sol:577–635` — `OperatorWhitelist` is intentionally not consulted on this path. Rationale: the signature path requires the operator's own cryptographic cooperation; if the service owner signs for a non-whitelisted operator, that is owner intent. The whitelist is the service owner's self-restriction. Documented as accepted trade-off in [`docs/Vulnerabilities_list_registries.md` §14](../../docs/Vulnerabilities_list_registries.md). |
| **H-09** | S-858, S-862 | `registerAgentsWithSignature` missing deadline / maximum bond signature parameter | 📝 Documented | — | VL **#17** | `contracts/ServiceManager.sol:577–635` — the per-`(operator, service)` nonce at line 603 (`mapOperatorRegisterAgentsNonces`) makes each signature single-use; replay across separate registrations is structurally impossible. Exploit requires the operator to maintain non-zero `safeApprove` to the old service owner *after* separation — operational discipline failure rather than protocol defect. Documented as accepted trade-off in [`docs/Vulnerabilities_list_registries.md` §17](../../docs/Vulnerabilities_list_registries.md). |
| **H-10** | S-1187 | Token-callback reentrancy (broader path: ERC777/ERC1363 hooks during `_claim` / `_withdraw` / `create`) | ✅ Fixed in code | ⚪ Code fix only — never deployed¹ | [`f59b339`](https://github.com/valory-xyz/autonolas-registries/commit/f59b339) (PR [#287](https://github.com/valory-xyz/autonolas-registries/pull/287)) + [`36609be`](https://github.com/valory-xyz/autonolas-registries/commit/36609be) (PR [#288](https://github.com/valory-xyz/autonolas-registries/pull/288), §A.5 follow-up) | Same `_locked` slot covers the broader hook-token surface. Critically, `StakingToken.deposit(uint256)` at `contracts/staking/StakingToken.sol:109–130` sets `_locked = 2` **before** `safeTransferFrom`, so any ERC1363/ERC777 hook the staking token fires during transfer sees `_locked == 2` and reverts if it tries to re-enter any of the 9 locked externals. Defence-in-depth for any future hook-carrying staking token deployed via `StakingFactory`; closes the native ETH `.call{value}` callback variant via `StakingNativeToken.receive()` (lines 35–53). |

¹ For H-05 / H-10 / §A.5: the post-fix `StakingToken` / `StakingNativeToken` source on HEAD has never been deployed on any chain. Plan: deploy as a new implementation, register it in `StakingVerifier` as an additional allowlisted entry (the prior `abis/0.8.25/*` implementations remain whitelisted in parallel), and `StakingFactory` will then produce new `StakingProxy` clones bound to the post-fix bytecode. Existing instances are constructor-pinned (see `internal17/README.md` §5.5) and remain on their original implementation by design — the fix is not retro-applied. Per `internal17/README.md` §3.1 / §4.1 the pre-fix gap was not reachable on the OLAS-backed proxies actually live today (OLAS is a standard ERC20 with no transfer hooks; `StakingNativeToken` has no live proxies on any supported chain), so the deployment is defence-in-depth, not an emergency.

² For H-06: `docs/configuration.json` references `abis/0.8.30/ServiceManager.json` for all production chains; bytecode-equivalence to `origin/main` source not directly verified in this report.

### Medium (2)

| C4R | C4R sub-ID | Title | Code status | Deployment status | Where it landed | Evidence on `origin/main` |
|-----|------------|-------|-------------|-------------------|-----------------|---------------------------|
| **M-08** | S-885 | Proportional `RewardDistributionType` ignores slashed bonds | 📝 Documented | — | VL **#19** | Acknowledged as documented design in [`docs/Vulnerabilities_list_registries.md` §19](../../docs/Vulnerabilities_list_registries.md). Slashing withholds funds at `ServiceRegistry(L2)` level; staking rewards are orthogonal to bond accounting (a slashed agent instance still earns its share if it continues to perform staking activity). The `Custom` distribution type (`contracts/staking/StakingBase.sol:725–744`) is the escape hatch for deployments that want bond-weighted rewards. |
| **M-10** | S-763 | `checkpoint` time manipulation during absence of rewards | 📝 Documented | — | VL **#20** | When `availableRewards == 0`, `checkpoint` short-circuits without updating per-service activity state — a service active only during the zero-reward window can later claim rewards for the unmeasured gap. Operational mitigation: reward deposits are permissionless via `StakingNativeToken.receive` / `StakingToken.deposit` (now lock-guarded per §A.5), so maintaining a wei-level `availableRewards > 0` across epochs closes the window. Documented in [`docs/Vulnerabilities_list_registries.md` §20](../../docs/Vulnerabilities_list_registries.md). |

### Low / QA (4)

| C4R | C4R sub-ID | Title | Code status | Deployment status | Where it landed | Evidence on `origin/main` |
|-----|------------|-------|-------------|-------------------|-----------------|---------------------------|
| **L-11** | S-69 | `execTransaction` return value ignored in multisig-creating contracts | 📝 Documented | — | VL **#13** | Bool return is **still ignored on-chain** at `contracts/multisigs/PolySafeCreatorWithRecoveryModule.sol:201–204` (post-creation `enableModule(recoveryModule)` step). Not exploitable today: the call uses `safeTxGas = 0, gasPrice = 0`, and Safe v1.3.0 `execTransaction` reverts with `GS013` on inner-call failure under those parameters rather than silently returning `false`. The previously-cited "ServiceManager-level guard" (`ServiceManager.deploy:434–439`) only protects against zero-address Safe creation — not against silent module-enable failure (see `internal17/README.md` §4.8 for the proof). Documented in [`docs/Vulnerabilities_list_registries.md` §13](../../docs/Vulnerabilities_list_registries.md). **Recommendation:** add an explicit on-chain bool check or post-condition (`getModulesPaginated()` confirms recovery module is attached) for defence-in-depth — see §4.8 of the audit README. |
| **L-12** | S-1175 | `registerAgentsWithSignature` missing `msg.value` validation | 📝 Documented | — | VL **#15** | `contracts/ServiceManager.sol:619–630`. Token-secured services forward `{value: agentInstances.length * BOND_WRAPPER}` (i.e. `length * 1 wei`); excess `msg.value` above this constant is unrefunded and trapped in `ServiceManager`. Native (ETH-secured) services forward `{value: msg.value}` and the downstream `if (msg.value != totalBond) revert IncorrectAgentBondingValue(...)` check at `contracts/ServiceRegistry.sol:427` enforces exact match (no trapping on the native path). C4R assessed this as a "misconfigured registration from users" Known Issue. Documented in [`docs/Vulnerabilities_list_registries.md` §15](../../docs/Vulnerabilities_list_registries.md). |
| **L-13** | S-430 | `slash` mechanism abuse by service owner | 📝 Documented | — | VL **#16** | A service owner can install a malicious Safe module on the service multisig and call `ServiceRegistry.slash` on their own operators to steal bonds. **No economic benefit:** slashed funds are locked at `ServiceRegistry(L2)` and only the DAO-gated `drainer` can drain them (set to Treasury on Ethereum mainnet per `docs/configuration.json` and `internal17/README.md` §5.3). Documented in [`docs/Vulnerabilities_list_registries.md` §16](../../docs/Vulnerabilities_list_registries.md). |
| **L-14** | S-901 | `registerAgents` agent instance registration DoS | 📝 Documented | — | VL **#18** | An attacker can repeatedly front-run `registerAgents` calls with throw-away addresses to consume slots. Mitigation is gas-cost asymmetry: agent instance addresses are unlimited and the attacker pays per-block gas; no slot reservation is possible without introducing a whitelist (which has its own scope issues — see H-07 / VL #14). Documented in [`docs/Vulnerabilities_list_registries.md` §18](../../docs/Vulnerabilities_list_registries.md). |

> **Note on Low-finding numbering.** The C4R draft report bundles 28 QA submissions without a canonical L-NN numbering. The L-IDs above (L-11 through L-14) follow [`audits/internal17/README.md`](README.md) §4 and are paired with the C4R submission IDs (S-69, S-1175, S-430, S-901) for unambiguous cross-reference. The sister doc [`autonolas-tokenomics/audits/internal16/FINAL_REVIEW.md`](../../../autonolas-tokenomics/audits/internal16/FINAL_REVIEW.md) §3 uses different L-numbers when listing registries-scope findings as out-of-scope for that repo (it labels the staking-related QA items "L-11" / "L-12" while reserving its own L-11/L-12 numbering for its tokenomics scope). Both numbering schemes are local to the respective audit; the **C4R S-IDs** are the authoritative cross-reference. The two staking-related QA items the tokenomics doc references map onto existing entries in this repo's `Vulnerabilities_list_registries.md`: `calculateStakingLastReward` rounding-dust precision is item **#21** and the slashed-bond proportional-split interaction is item **#19** (= M-08 here).

---

## §3. Aggregate roll-up

### By disposition (registries-scope C4R findings only — 11 total)

| Bucket | Count | C4R IDs |
|--------|------:|---------|
| ✅ Fixed in code | **3** | H-05, H-06, H-10 |
| 📝 Documented (VL entry) | **8** | H-07 (VL #14), H-09 (VL #17), M-08 (VL #19), M-10 (VL #20), L-11 (VL #13), L-12 (VL #15), L-13 (VL #16), L-14 (VL #18) |
| 🔄 Resolved by replacement | **0** | — |
| ⚖️ Rejected on review | **0** | — |
| **Total** | **11** | — |

### By severity (registries-scope C4R findings only)

| Severity | Count | ✅ Fixed | 📝 Documented |
|----------|------:|--------:|--------------:|
| High | 5 | 3 (H-05, H-06, H-10) | 2 (H-07, H-09) |
| Medium | 2 | 0 | 2 (M-08, M-10) |
| Low / QA | 4 | 0 | 4 (L-11, L-12, L-13, L-14) |
| **Total** | **11** | **3** | **8** |

### By deployment status (only meaningful for ✅ rows)

| Deployment status | Count | Findings | Notes |
|---|---:|---|---|
| 🟢 Live on-chain | 1 | H-06 | `docs/configuration.json` references `abis/0.8.30/ServiceManager.json` on all production chains; bytecode-equivalence not directly verified in this report. |
| 🟡 Pending redeploy | 0 | — | — |
| ⚪ Code fix only — never deployed | 2 | H-05, H-10 | Post-fix `StakingToken` / `StakingNativeToken` source not deployed on any chain. Plan: register as a new allowlisted implementation in `StakingVerifier` (alongside the existing 0.8.25/0.8.28 entries); `StakingFactory` will produce new clones against it. Existing proxies stay constructor-pinned to their original implementation by design (`internal17/README.md` §5.5). Per `internal17/README.md` §3.1, the pre-fix gap was not reachable on OLAS-backed proxies live today — defence-in-depth, not blocking. |

---

## §4. Fix-commit roll-up by PR

The same fix commits cited above, organised by the PR that landed them. Useful when a reader wants to verify a *PR* rather than a finding.

| PR | Branch | Tip commit | Registries-scope C4R IDs closed |
|----|--------|------------|---------------------------------|
| [#241](https://github.com/valory-xyz/autonolas-registries/pull/241) `8004_extension` | `8004_extension` | [`7674c5c`](https://github.com/valory-xyz/autonolas-registries/commit/7674c5c) | H-06 (`ServiceManager.create` reentrancy guard) |
| [#287](https://github.com/valory-xyz/autonolas-registries/pull/287) `fix/staking-post-c4r-hardening` | `fix/staking-post-c4r-hardening` | [`f59b339`](https://github.com/valory-xyz/autonolas-registries/commit/f59b339) | H-05 (StakingBase 7-entry-point lock) + H-10 (broader callback path closed via the same `_locked` slot) |
| [#288](https://github.com/valory-xyz/autonolas-registries/pull/288) `fix/staking-derivative-reentrancy-lock` | `fix/staking-derivative-reentrancy-lock` | [`36609be`](https://github.com/valory-xyz/autonolas-registries/commit/36609be) (merged at [`d60f7ef`](https://github.com/valory-xyz/autonolas-registries/commit/d60f7ef)) | H-05 / H-10 §A.5 derivative follow-up: extended `_locked` to `StakingNativeToken.receive()` and `StakingToken.deposit()` |
| [#286](https://github.com/valory-xyz/autonolas-registries/pull/286) `fix/staking-post-c4r-hardening` (merge) | `fix/staking-post-c4r-hardening` | [`18eb483`](https://github.com/valory-xyz/autonolas-registries/commit/18eb483) | (Merge of #287 work into the integration branch — no new fix landings) |
| [#289](https://github.com/valory-xyz/autonolas-registries/pull/289) `staking-post-c4r-hardening-audit-post-check` | `staking-post-c4r-hardening-audit-post-check` | [`435678a`](https://github.com/valory-xyz/autonolas-registries/commit/435678a) | (Audit-only; no new fix landings — `internal17` README + this doc track the verification.) |

---

## §5. Quick reference — VL # ↔ C4R ID

The "VL #N" citations in §2 follow the numbering in [`docs/Vulnerabilities_list_registries.md`](../../docs/Vulnerabilities_list_registries.md) at the time of writing (HEAD `c59e201`, branch `doc/internal17-status-matrix-corrections`). Per team policy, VL entries are removed when fixed; the live numbering may shift as entries close. The mapping below is a snapshot.

| VL # (current) | Title | C4R origin |
|---|---|---|
| #13 | `execTransaction` return value ignored in `RecoveryModule` and other multisig creating contracts | L-11 / S-69 |
| #14 | `registerAgentsWithSignature` operator whitelist bypass | H-07 / S-149 |
| #15 | `registerAgentsWithSignature` missing `msg.value` validation | L-12 / S-1175 |
| #16 | `slash` mechanism abuse by service owner | L-13 / S-430 |
| #17 | `registerAgentsWithSignature` missing deadline and maximum bond parameters | H-09 / S-858, S-862 |
| #18 | `registerAgents` agent instance registration DoS | L-14 / S-901 |
| #19 | `slash` and proportional `RewardDistributionType` split | M-08 / S-885 |
| #20 | `checkpoint` function during absence of rewards | M-10 / S-763 |
| #22 | `ServiceRegistry.registerAgents` / `update` / `activateRegistration` missing reentrancy guard | (Not a C4R finding — internal-15-derived, added this audit; manager-role-mitigated.) |

VL entries #1–#12 and #21 predate the C4R 2026-01 cycle and originate from earlier internal audits; not reproduced here. VL #21 (`calculateStakingLastReward` rounding dust) is informational and cosmetic, retained from the internal15 cycle.

---

## §6. Verdict

Every C4R 2026-01 registries-scope finding has a known disposition on the current code:

- **3 of 11 are ✅ Fixed in code** with named fix commits (H-05, H-06, H-10).
- **8 of 11 are 📝 Documented** in `docs/Vulnerabilities_list_registries.md` (entries #13, #14, #15, #16, #17, #18, #19, #20).
- **None are open or unaccounted-for.**

For the deployment-side picture — which fixes are 🟢 live on-chain vs ⚪ never deployed vs 🟡 pending redeploy — see [`audits/internal17/README.md` §4.12](README.md). Summary: H-06 is 🟢 live on-chain across all production chains; H-05 and H-10 are ⚪ code-only — the post-fix `StakingToken` / `StakingNativeToken` source has not yet been deployed and will land as a *new* allowlisted implementation in `StakingVerifier` rather than replacing the existing one. Existing `StakingProxy` instances are constructor-pinned and stay on their original implementation by design.

For the new finding that this audit cycle (internal17) carried forward beyond the C4R scope — L-11 reclassification (`PolySafeCreatorWithRecoveryModule` bool unchecked, defence-in-depth recommendation to add explicit on-chain check) — see [`audits/internal17/README.md` §4.8 and §6.1](README.md).

---

### Doc metadata

- **Author:** internal audit 17 closing review (2026-05-06)
- **Composite tip:** branch `doc/internal17-status-matrix-corrections` (current PR head; this metadata is intentionally branch-keyed rather than commit-keyed since the PR tip advances as review feedback lands)
- **C4R draft:** [gist](https://gist.github.com/kobi-c4/e232003edf0a4aa5fef5d0b6f0717b38)
- **Companion documents:** [`audits/internal17/README.md`](README.md) (full attack-review + on-chain owner map + hygiene table + §A.5 derivative lock verification), [`audits/internal16/README.md`](../internal16/README.md) (immediate baseline; staking hardening branch delta audit), [`audits/internal15/README.md`](../internal15/README.md) (initial C4A fix matrix and Stream A–D framework)
- **Cross-repo companion:** [`autonolas-tokenomics/audits/internal16/FINAL_REVIEW.md`](../../../autonolas-tokenomics/audits/internal16/FINAL_REVIEW.md) (sister doc covering the tokenomics-scope C4R findings)
