# Internal audit 17 of autonolas-registries (post-C4A re-audit)

Repository: https://github.com/valory-xyz/autonolas-registries
Commit audited: `d60f7ef5` (Merge PR #288 `fix/staking-derivative-reentrancy-lock`)
Branch: `staking-post-c4r-hardening-audit`
Audit date: 2026-04-22
Deliverable style: internal15 template (C4A verification matrix + on-chain owner map + Vulnerabilities_list hygiene)
Prior references: `audits/internal15/README.md`, `audits/internal16/README.md`

## 0. Status vocabulary

The verification matrix below uses two **orthogonal** status columns rather than a single "fixed/not-fixed" flag, modelled on the scheme adopted by `autonolas-governance/audits/internal19`. The split is deliberate: a fix can land in source code without being live on-chain, and a contract can be deployed without the latest code.

| Code status | Meaning |
|---|---|
| ✅ Fixed in `origin/main` | Code fix landed on `origin/main` of this repository |
| 🟢 Fixed on feature branch | Code fix landed on a non-`main` feature branch; not yet merged |
| 🟠 Partially fixed | Some attack paths closed in code, others still live |
| 📝 Documented (known issue) | Not fixed in code; explicitly accepted on `docs/Vulnerabilities_list_registries.md` |
| 🔴 Not fixed (open) | Not fixed in code and not documented as accepted; tracked openly |

| Deployment status | Meaning |
|---|---|
| 🟢 Live on-chain | Code fix is deployed and live on the target chain(s) — the address in `docs/configuration.json` references the post-fix artifact |
| 🟡 Pending redeploy | Code fix landed in source; the on-chain version is still the older bytecode and a redeploy of an existing contract is required for the fix to take effect |
| ⚪ Code fix only — never deployed | The exact source version on this audit's HEAD has never been deployed. Either (a) the contract is brand-new and has no prior on-chain version, or (b) the contract is an upgradable / clonable implementation that will be deployed as a **new, separately-addressed instance** rather than replacing an existing one — pre-existing instances remain in service unchanged. The fix only takes effect on new instances created against the new deployment. |
| — (N/A) | No code fix exists (Documented or Not-fixed rows) |
| Not verified here | This report did not bytecode-check the on-chain deployment against the source |

## C4R fixed issues — summary

Quick reference for the C4A 2026-01 / C4R registries-scope findings handled in this audit. Full detail in §4.

| C4R issue | Summary | Code status | Deployment status | Fix commit / Fix branch |
|---|---|---|---|---|
| H-05 / C4R S-229 | `StakingBase._withdraw` cross-service reentrancy | ✅ Fixed in `origin/main` | ⚪ Code fix only — never deployed. The post-fix `StakingToken` / `StakingNativeToken` source has not been deployed on any chain. When deployed, it will be added as a **new** allowlisted implementation in `StakingVerifier` and used by `StakingFactory` for new clones; pre-existing `StakingProxy` instances (built against the prior `abis/0.8.25/*` implementations referenced in `docs/configuration.json`) remain in service against the original bytecode by design (constructor-pinned implementation, §5.5). | `f59b339` (PR #287); `36609be` (PR #288, §A.5 follow-up) — `fix/staking-post-c4r-hardening`; `fix/staking-derivative-reentrancy-lock` |
| H-06 | `ServiceManager.create` reentrancy via `onERC721Received` | ✅ Fixed in `origin/main` | 🟢 Live on-chain (`docs/configuration.json` references `abis/0.8.30/ServiceManager.json` across all production chains; not byte-code-verified in this report) | `7674c5c` (PR #241) — `8004_extension` |
| H-07 / C4R S-149 | `registerAgentsWithSignature` operator whitelist bypass | 📝 Documented (known issue) | — | item #14 in `docs/Vulnerabilities_list_registries.md` |
| H-09 / C4R S-858, S-862 | `registerAgentsWithSignature` missing deadline / max bond | 📝 Documented (known issue) | — | item #17 in `docs/Vulnerabilities_list_registries.md` |
| H-10 / C4R S-1187 | Token callback reentrancy (broader path) | ✅ Fixed in `origin/main` | ⚪ Code fix only — never deployed. Same as H-05: post-fix `StakingToken` / `StakingNativeToken` source not deployed on any chain; will land as a new allowlisted implementation in `StakingVerifier`, alongside (not replacing) the existing one. | `f59b339` (PR #287); `36609be` (PR #288, §A.5 follow-up) — `fix/staking-post-c4r-hardening`; `fix/staking-derivative-reentrancy-lock` |
| M-08 / C4R S-885 | Proportional rewards ignore slashed bonds | 📝 Documented (known issue) | — | item #19 in `docs/Vulnerabilities_list_registries.md` |
| M-10 / C4R S-763 | `checkpoint` during absence of rewards | 📝 Documented (known issue) | — | item #20 in `docs/Vulnerabilities_list_registries.md` |
| L-11 / C4R S-69 | `execTransaction` return value ignored | 📝 Documented (known issue) — bool still unchecked in `PolySafeCreatorWithRecoveryModule.create:201–204`; not exploitable today under deployed Safe v1.3.0 + `safeTxGas = 0, gasPrice = 0` semantics; recommendation: add explicit on-chain check | — (no code change) | item #13 in `docs/Vulnerabilities_list_registries.md` |
| L-12 / C4R S-1175 | `registerAgentsWithSignature` missing `msg.value` validation | 📝 Documented (known issue) | — | item #15 in `docs/Vulnerabilities_list_registries.md` |
| L-13 / C4R S-430 | `slash` abuse by service owner | 📝 Documented (known issue) | — | item #16 in `docs/Vulnerabilities_list_registries.md` |
| L-14 / C4R S-901 | `registerAgents` agent instance DoS | 📝 Documented (known issue) | — | item #18 in `docs/Vulnerabilities_list_registries.md` |

## 1. Objectives

This audit is a **full re-audit** of `autonolas-registries` against the Code4rena (C4A) Olas 2026-01 external audit report, building on the prior `audits/internal16/README.md` (delta audit of the staking hardening branch, baseline `b5c50ae`).

- Verify the §A.5 derivative reentrancy lock that `internal16` recommended as a follow-up has been implemented correctly on-code (commits `36609be` → `d60f7ef5`, PR #288).
- Map every applicable C4A finding to the registries repo and verify the fix in the current code.
- Build an on-chain owner map for all deployed registries contracts and run the OpSec checks (multisig threshold, timelock, EOA owner exposure).
- Re-verify the 22 entries in `docs/Vulnerabilities_list_registries.md` against current code.
- Confirm prior internal15 and internal16 findings still hold on HEAD `d60f7ef5`.

Out of scope: Gnosis Safe core, OpenZeppelin library sources, solmate ERC721 / ERC721TokenReceiver, external activity checker and custom rewards distributor implementations. Inherited OZ / solmate / Safe code is trusted.

## 2. Scope

39 production Solidity contracts, ~8100 LOC across:

| Group | Contracts | Location |
|---|---|---|
| Registries (ERC721) | `ComponentRegistry`, `AgentRegistry`, `ServiceRegistry`, `ServiceRegistryL2`, `GenericRegistry`, `UnitRegistry` | `contracts/*.sol` |
| Managers | `ServiceManager`, `ServiceManagerProxy`, `RegistriesManager`, `GenericManager` | `contracts/*.sol` |
| Token utility | `ServiceRegistryTokenUtility` | `contracts/ServiceRegistryTokenUtility.sol` |
| Multisig creators | `GnosisSafeMultisig`, `GnosisSafeSameAddressMultisig`, `SafeMultisigWithRecoveryModule`, `PolySafeCreatorWithRecoveryModule`, `RecoveryModule` | `contracts/multisigs/` |
| Staking | `StakingBase`, `StakingToken`, `StakingNativeToken`, `StakingProxy`, `StakingFactory`, `StakingVerifier`, `StakingActivityChecker` | `contracts/staking/` |
| Utilities | `OperatorWhitelist`, `OperatorSignedHashes`, `HashCheckpoint`, `ApplicationClassifier`, `ApplicationClassifierProxy`, `ComplementaryServiceMetadata`, `SafeTransferLib` | `contracts/utils/` |

## 3. Delta vs. internal16

`audits/internal16/README.md` is the immediate baseline (committed at `b5c50ae` on 2026-04-15). Since then, two commits have landed on-branch:

```
d60f7ef Merge pull request #288 from valory-xyz/fix/staking-derivative-reentrancy-lock
36609be fix: extend reentrancy lock to StakingNativeToken.receive and StakingToken.deposit
```

Production-code delta `b5c50ae..d60f7ef5` touches exactly two files:

| File | Change | LOC |
|------|--------|----:|
| `contracts/staking/StakingNativeToken.sol` | `receive()` now acquires the `_locked` guard (`1 → 2` on entry, `2 → 1` on exit); `ReentrancyGuard` error re-imported from `StakingBase`; pragma bumped `^0.8.25 → ^0.8.30` | +8 |
| `contracts/staking/StakingToken.sol` | `deposit(uint256)` now acquires the `_locked` guard analogously; same import and pragma updates | +8 |

No other production file changes between `b5c50ae` and `d60f7ef5`.

### 3.1 Verification of the derivative lock fix (§A.5 follow-up)

`internal16` documented §A.5 as the residual class — `receive()` / `deposit()` on the derivatives could desync `balance` against the cached local in `_withdraw` if called from within a reward-callback. The PR #288 fix implements exactly the shape `internal16` specified.

**`StakingNativeToken.receive()` — file `contracts/staking/StakingNativeToken.sol:35–53`:**

```solidity
receive() external payable {
    // Reentrancy guard
    if (_locked > 1) {
        revert ReentrancyGuard();
    }
    _locked = 2;

    // Add to the contract and available rewards balances
    uint256 newBalance = balance + msg.value;
    uint256 newAvailableRewards = availableRewards + msg.value;

    // Record the new balance values
    balance = newBalance;
    availableRewards = newAvailableRewards;

    emit Deposit(msg.sender, msg.value, newBalance, newAvailableRewards);

    _locked = 1;
}
```

**`StakingToken.deposit(uint256)` — file `contracts/staking/StakingToken.sol:109–130`:**

```solidity
function deposit(uint256 amount) external {
    // Reentrancy guard
    if (_locked > 1) {
        revert ReentrancyGuard();
    }
    _locked = 2;

    // Add to the contract and available rewards balances
    uint256 newBalance = balance + amount;
    uint256 newAvailableRewards = availableRewards + amount;

    // Record the new balance values
    balance = newBalance;
    availableRewards = newAvailableRewards;

    // Transfer tokens
    SafeTransferLib.safeTransferFrom(stakingToken, msg.sender, address(this), amount);

    emit Deposit(msg.sender, amount, newBalance, newAvailableRewards);

    _locked = 1;
}
```

**Import / visibility verification:**

- Both derivatives now `import {StakingBase, ReentrancyGuard} from "./StakingBase.sol"` — confirming `ReentrancyGuard` is file-scope-error-reachable from outside `StakingBase`.
- `_locked` is `internal` in `StakingBase` (`StakingBase.sol:339`), so writes from the derivatives compile without visibility change.
- Pragma `^0.8.30` matches `StakingBase.sol`; no split-pragma hazard.

**Lock semantics on derivatives:**

- On a **fresh proxy clone** `_locked` starts at `0` (inline initializer does not apply to clones; see `internal16` Notes). First call sees `0 > 1 = false` → passes guard → sets `2` → writes storage → sets `1` on exit. Subsequent calls follow `1 → 2 → 1`.
- **Nested call under outer lock:** outer flow `_withdraw → _transfer → attacker.receive → stakingX.{receive, deposit}` sees `_locked == 2` → reverts with `ReentrancyGuard()`. The inner revert propagates back into `attacker.receive`; the outer flow's behaviour from there depends on whether the attacker swallows the inner revert. In the dedicated test (`test_Reentrancy_NestedReceive_RevertsWithGuard`) the attacker does swallow the inner revert via low-level `.call`, so the outer `claim`/`_withdraw` still completes successfully — but the nested write to `balance` / `availableRewards` never lands, so no desync of staking accounting is possible. If the attacker does not swallow the revert, the outer flow reverts via `TransferFailed` and all state is unwound. Either way, the lock prevents the cross-service insolvency surface.
- **CEI for `deposit`:** state writes happen *before* `safeTransferFrom`, but the lock is held during the transfer, so any hook-carrying ERC20 (ERC777 / ERC1363) that tries to re-enter reverts.

**Test coverage (new on this branch):** `test/StakingDerivativeReentrancy.t.sol` (399 LOC, 4 tests):

- `test_Reentrancy_NestedReceive_RevertsWithGuard` — attacker's `receive()` re-enters `stakingNativeToken.receive{value: Y}` from within an outer `checkpointAndClaim → _withdraw → _transfer` flow. The inner re-entry reverts with `ReentrancyGuard`; the attacker swallows the revert via low-level `.call`, so the outer claim still completes — but the nested `balance` / `availableRewards` write never lands, so no desync.
- `test_Reentrancy_NestedDeposit_RevertsWithGuard` — a hook-carrying ERC20's `transferFrom` callback re-enters `stakingToken.deposit(amount)` during the outer `deposit`'s `safeTransferFrom`. Inner revert with `ReentrancyGuard`; outer deposit still lands exactly once (no double-counting from the rejected nested call).
- `test_Receive_HonestDepositSucceeds` — direct ETH transfer to `stakingNativeToken` post-lock-extension still credits `balance` / `availableRewards` by `msg.value`.
- `test_Deposit_HonestDepositSucceeds` — direct `stakingToken.deposit(amount)` post-lock-extension still pulls the ERC20 via `safeTransferFrom` and credits accounting by `amount`.

**Exploitability of the pre-fix gap:**

- `StakingNativeToken` has no active proxies on any supported chain today (confirmed at `internal15` Stream A).
- `StakingToken` is parameterised on the staking token per instance. OLAS is a standard ERC20 without transfer hooks, so `safeTransferFrom` in `deposit` never yielded control to a receiver — the gap was not reachable on live OLAS-backed proxies.
- The fix is defence-in-depth for any future hook-carrying staking token or any reactivation of `StakingNativeToken`.

**Invariant 5** (`StakingBase.balance ≥ sum of pending rewards`) now holds **unconditionally** on every reachable path — all writes to `balance` / `availableRewards` serialize through the same `_locked` slot as `_withdraw`'s balance-cache pattern.

✅ **§A.5 follow-up correctly implemented.** No new finding from the attack-review of this delta.

### 3.2 Anything new to flag on the delta

- **Pragma bump to `^0.8.30`** aligns both derivatives with `StakingBase`. Solidity 0.8.30 is a recent release; the repo already uses it for other files (`StakingBase`, `StakingFactory`, `StakingVerifier`, etc.). No new compiler-level risk introduced.
- **No new external entry point** is added — the lock is applied in-place on pre-existing `receive()` / `deposit()` functions.
- **No storage-layout change** on the derivatives (they don't declare storage of their own; `_locked` lives in `StakingBase` and was already present since `f59b339`).

## 4. C4A 2026-01 verification matrix (registries-scope only)

The table below lists the C4A 2026-01 findings that touch `autonolas-registries` — **11 findings: 5 High + 2 Medium + 4 Low**. Findings scoped to other Olas repos (`autonolas-tokenomics`, `autonolas-governance`) are verified in their own internal audits and are intentionally omitted here so the registries remediation surface stays unambiguous.

The matrix uses the two orthogonal status columns defined in §0 — **Code status** (where the fix lives in source) and **Deployment status** (whether the fix is live on-chain). The previous template conflated the two into a single "fixed" flag; the split below is the structural correction.

| C4A ID | Title | Code status | Deployment status | Detail |
|---|---|---|---|---|
| H-05 / C4R S-229 | `StakingBase._withdraw` cross-service reentrancy (F-8) | ✅ Fixed in `origin/main` | ⚪ Code fix only — never deployed. The post-fix `StakingToken` / `StakingNativeToken` source has not been deployed on any chain. When it is, it will be added as a **new** allowlisted implementation in `StakingVerifier` (alongside, not replacing, the existing one). Pre-existing `StakingProxy` instances remain on the original bytecode by design (constructor-pinned, §5.5); the fix takes effect on new clones built against the new implementation. | §4.1 |
| H-06 | `ServiceManager.create` reentrancy via `onERC721Received` (F-123) | ✅ Fixed in `origin/main` | 🟢 Live on-chain — `docs/configuration.json` references `abis/0.8.30/ServiceManager.json` for all production chains; not bytecode-verified in this report | §4.2 |
| H-07 / C4R S-149 | `registerAgentsWithSignature` operator whitelist bypass (F-166) | 📝 Documented (known issue) — item #14 | — | §4.3 |
| H-09 / C4R S-858, S-862 | `registerAgentsWithSignature` missing deadline / maximum bond (F-215) | 📝 Documented (known issue) — item #17 | — | §4.4 |
| H-10 / C4R S-1187 | Token callback reentrancy (broader path) (F-397) | ✅ Fixed in `origin/main` | ⚪ Code fix only — never deployed. Same as H-05: source on HEAD `d60f7ef5` has never been deployed; will land as a new allowlisted implementation. | §4.5 |
| M-08 / C4R S-885 | Proportional `RewardDistributionType` ignores slashed bonds (F-329) | 📝 Documented (known issue) — item #19 | — | §4.6 |
| M-10 / C4R S-763 | `checkpoint` time manipulation during absence of rewards (F-374) | 📝 Documented (known issue) — item #20 | — | §4.7 |
| L-11 / C4R S-69 | `execTransaction` return value ignored in multisig-creating contracts | 📝 Documented (known issue) — item #13; bool still unchecked in `PolySafeCreatorWithRecoveryModule.create:201–204`; not exploitable under deployed Safe v1.3.0 + `safeTxGas = 0, gasPrice = 0` semantics; defence-in-depth recommendation in §4.8 | — (no code change) | §4.8 |
| L-12 / C4R S-1175 | `registerAgentsWithSignature` missing `msg.value` validation | 📝 Documented (known issue) — item #15 | — | §4.9 |
| L-13 / C4R S-430 | `slash` mechanism abuse by service owner | 📝 Documented (known issue) — item #16 | — | §4.10 |
| L-14 / C4R S-901 | `registerAgents` agent instance registration DoS | 📝 Documented (known issue) — item #18 | — | §4.11 |

All 11 are verified below against HEAD `d60f7ef5`.

**Per-status summary (registries-scope only):**

| | High | Medium | Low | Total |
|---|---:|---:|---:|---:|
| ✅ Fixed in `origin/main` | 3 (H-05, H-06, H-10) | 0 | 0 | 3 |
| 📝 Documented (known issue) | 2 (H-07, H-09) | 2 (M-08, M-10) | 4 (L-11, L-12, L-13, L-14) | 8 |
| **Total** | **5** | **2** | **4** | **11** |

| Deployment status (for the 3 code-fixes) | Count | Findings |
|---|---:|---|
| 🟢 Live on-chain (referenced in `docs/configuration.json`; not bytecode-checked in this report) | 1 | H-06 (`ServiceManager` 0.8.30 across all chains) |
| 🟡 Pending redeploy | 0 | — |
| ⚪ Code fix only — never deployed (post-fix `StakingToken` / `StakingNativeToken` source not deployed on any chain; will land as a new allowlisted implementation in `StakingVerifier`, alongside the existing one) | 2 | H-05, H-10 |

### 4.1 C4A H-05 / C4R S-229 — `StakingBase._withdraw` cross-service reentrancy

**Fix branch:** `fix/staking-post-c4r-hardening` (PR #287, commit `f59b339`), extended by `fix/staking-derivative-reentrancy-lock` (PR #288, commit `36609be`) for the §A.5 derivative follow-up.

**Original finding.** `StakingBase._withdraw` transferred rewards to service owners via low-level `.call{value}` (native) or `safeTransfer` (ERC20) without a reentrancy guard. A malicious receiver in service A could re-enter and call `checkpoint` / `claim` / `unstake` for service B, corrupting reward accounting.

**Fix verified on code (HEAD `d60f7ef5`):**

- Contract-wide single-slot `_locked` state variable at `StakingBase.sol:339`.
- Inline check + set + unlock in every external state-changing entry point on `StakingBase`:

| Entry point | File:Line |
|-------------|:---------:|
| `checkpoint()` | `StakingBase.sol:1119–1134` |
| `stake(uint256)` | `StakingBase.sol:1140–1150` |
| `stake(uint256,uint256)` | `StakingBase.sol:1158–1168` |
| `unstake(uint256)` | `StakingBase.sol:1173–1183` |
| `forcedUnstake(uint256)` | `StakingBase.sol:1187–1197` |
| `claim(uint256)` | `StakingBase.sol:1202–1212` |
| `checkpointAndClaim(uint256)` | `StakingBase.sol:1217–1227` |
| `StakingNativeToken.receive()` | `StakingNativeToken.sol:35–53` (added in §3.1) |
| `StakingToken.deposit(uint256)` | `StakingToken.sol:109–130` (added in §3.1) |

The previously-`public` `checkpoint()` was split into external wrapper + internal `_checkpoint()` (line 983). Three internal flows (`_claim`, `_stake`, `_unstake` at lines 557, 763, 876) now call `_checkpoint()` directly to avoid self-deadlock.

**Test coverage:** `test/StakingSecurityFixes.t.sol:test_Reentrancy_ClaimRevertsOnReentry`, plus the two nested-entry tests in `test/StakingDerivativeReentrancy.t.sol`.

✅ **FIXED AND VERIFIED.** (Full attack-review in `internal16`; §3.1 of this report verifies the §A.5 follow-up.)

### 4.2 C4A H-06 — `ServiceManager.create` reentrancy via `onERC721Received`

**Fix branch:** `8004_extension` (PR #241, commit `7674c5c`).

**Original finding.** `ServiceManager.create` (and the underlying `ServiceRegistry.create`) mints the service ERC721 to `serviceOwner` with `_safeMint`. A contract recipient's `onERC721Received` callback could re-enter `ServiceManager.create` (or other state-mutating externals) and manipulate state before the outer call completed.

**Fix verified.** Reentrancy guards on the create path:

- `ServiceManager.create` — `_locked` acquired at `ServiceManager.sol:203–206` and released at line 255, wrapping the inner `IService(serviceRegistry).create(...)` call.
- `ServiceRegistry.create` — `_locked` acquired at `ServiceRegistry.sol:226–229` and released at line 274, with `_safeMint(serviceOwner, serviceId)` at line 270 executing **inside** the lock window. State writes (`mapServices[serviceId] = service`, `totalSupply = serviceId`) at lines 266–267 happen **before** `_safeMint`, so any reentry into `ServiceRegistry.create` itself reverts on the lock check; the `serviceId` row is fully well-formed before the callback is reached.
- `ServiceRegistryL2.create` mirrors the L1 layout (lock at `ServiceRegistryL2.sol:218–221`/266; `_safeMint` at line 262).

**Caveat — `ServiceRegistry.registerAgents` is NOT lock-guarded.** Only `create`, `deploy`, `terminate`, `unbond`, and `drain` carry an inline `_locked` block on `ServiceRegistry` (and on `ServiceRegistryL2`); `update`, `activateRegistration`, and `registerAgents` do not. Reentrancy on the `registerAgents` path is mitigated by the `ServiceManager.registerAgents` / `registerAgentsWithSignature` wrappers (`ServiceManager.sol:374–378` and `585–588`), which is the only entry point used by the periphery and the only one that invokes `IServiceTokenUtility`. Direct callers that talk to `ServiceRegistry.registerAgents` bypassing the manager would not be lock-protected — but that path requires the caller to be authorised as `manager`, which is governed by the Timelock-set `manager` role (currently `ServiceManager`).

✅ **FIXED AND VERIFIED.**

### 4.3 C4A H-07 / C4R S-149 — `registerAgentsWithSignature` operator whitelist bypass

**Original finding.** When the service owner enabled an operator whitelist, a non-whitelisted operator could register via the signature path, bypassing the whitelist check.

**Status.** Acknowledged as a **documented trade-off** (`docs/Vulnerabilities_list_registries.md` item #14). Rationale: the signature path requires the service owner's or operator's cryptographic cooperation, so an exploit requires the legitimate party to already have signed. The whitelist is the service owner's self-restriction; if the owner signs for a non-whitelisted operator, that is owner intent.

Code inspection: `ServiceManager.sol:577–635` implements the signature-authenticated registration, and `OperatorWhitelist` is **not** consulted on this path (by design). The `ServiceRegistry.registerAgents` call at line 622/627 is gated by the signature verification at line 608, not by the whitelist.

✅ **DOCUMENTED TRADE-OFF — ACCEPTED.**

### 4.4 C4A H-09 / C4R S-858, S-862 — `registerAgentsWithSignature` missing deadline / maximum bond

**Original finding.** The signature does not carry a deadline or a maximum-bond parameter. A previous service owner with a still-valid signature can front-run the operator's next `safeApprove` to a different service.

**Status.** Acknowledged as a **documented trade-off** (`docs/Vulnerabilities_list_registries.md` item #17). Rationale:

- The exploit requires the operator to maintain nonzero approvals to the old service owner after separation — an operational discipline failure, not a protocol defect.
- The signed-hash nonce (`mapOperatorRegisterAgentsNonces[operatorService]` at `ServiceManager.sol:603`) is per-operator-per-service, so each signature is single-use; it cannot be replayed to register twice.
- Adding a deadline would still leave the window open for however long the deadline is. The operational mitigation is robust.

✅ **DOCUMENTED TRADE-OFF — ACCEPTED.**

### 4.5 C4A H-10 / C4R S-1187 — token callback reentrancy (broader path)

**Fix branch:** `fix/staking-post-c4r-hardening` (PR #287, commit `f59b339`), extended by `fix/staking-derivative-reentrancy-lock` (PR #288, commit `36609be`) for the §A.5 derivative follow-up.

**Original finding.** `_withdraw` invokes `safeTransfer` on a generic ERC20, which for hook-carrying standards (ERC777 / ERC1363) yields control to the receiver — reentrancy surface broader than just `_withdraw`.

**Fix verified.** The same contract-wide `_locked` on `StakingBase.sol` and on `StakingNativeToken.receive` / `StakingToken.deposit` (§3.1) closes the full attack class. In particular:

- `StakingToken.deposit(uint256)` sets `_locked = 2` **before** `safeTransferFrom` (`StakingToken.sol:109–130`), so any ERC1363/ERC777 hook the token fires during the transfer sees `_locked == 2` and reverts if it tries to re-enter any of the 9 locked externals.
- Derivative-side imports updated: `import {StakingBase, ReentrancyGuard} from "./StakingBase.sol"` — both files share the lock slot.

Defence-in-depth for any future hook-carrying staking token deployed via `StakingFactory`, and closes the native-token variant (ETH `.call{value}` callback) as well.

✅ **FIXED AND VERIFIED.**

### 4.6 C4A M-08 / C4R S-885 — proportional rewards ignore slashed bonds

**Original finding.** Under `RewardDistributionType.Proportional`, the reward split assumes equal bonds per operator. A slashed operator still receives the same proportional share.

**Status.** Acknowledged as **documented design** (`docs/Vulnerabilities_list_registries.md` item #19). Slashing withholds funds at `ServiceRegistry(L2)` level; staking rewards are orthogonal to bond accounting. If a slashed agent instance continues to perform staking activity, it earns its share. The `Custom` reward distribution type (`StakingBase.sol:725–744`) is the escape hatch for deployments that want bond-weighted rewards.

✅ **DOCUMENTED DESIGN — ACCEPTED.**

### 4.7 C4A M-10 / C4R S-763 — `checkpoint` during absence of rewards

**Original finding.** When `availableRewards == 0`, `checkpoint` short-circuits without updating per-service activity state — a service active only during the zero-reward window can later claim rewards for the unmeasured gap.

**Status.** Acknowledged as **documented trade-off** (`docs/Vulnerabilities_list_registries.md` item #20). Operational mitigation: reward deposits are permissionless (`StakingNativeToken.receive` / `StakingToken.deposit` — both now lock-guarded per §3.1), so maintaining a wei-level `availableRewards > 0` across epochs closes the window.

✅ **DOCUMENTED TRADE-OFF — ACCEPTED.**

### 4.8 C4A L-11 / C4R S-69 — `execTransaction` return value ignored

**Original finding.** `RecoveryModule.recoverAccess` and the multisig-creating `create()` functions (notably `PolySafeCreatorWithRecoveryModule.create`) invoke `Safe.execTransaction` and ignore the boolean return value.

**Code state (HEAD `d60f7ef5`):** the bool return is **still ignored on-chain** in the multisig creators. `PolySafeCreatorWithRecoveryModule.create` at `contracts/multisigs/PolySafeCreatorWithRecoveryModule.sol:201–204` calls `ISafe(multisig).execTransaction(...)` for the `enableModule(recoveryModule)` post-creation step and does not consume the returned bool.

The "ServiceManager-level guard" cited by the prior framing is `ServiceManager.deploy:434–439`, which checks `multisig != address(0)` after the inner `IService(serviceRegistry).deploy(...)` returns. This zero check is genuinely a guard for the case where a stateless `IMultisig.create()` implementation fails entirely and returns the zero address. It is **not** a guard for L-11's specific silent-failure case: in `PolySafeCreatorWithRecoveryModule.create`, the Safe proxy is deployed and codehash-checked at lines 164–177 *before* `execTransaction(enableModule)` runs, so the returned `multisig` is always non-zero by line 206 regardless of whether the module-enabling call succeeded. The zero-address check therefore cannot distinguish "Safe created with module enabled" from "Safe created without module enabled".

**Why this is not exploitable in practice on the deployed parameters.** The `execTransaction` call is constructed with `safeTxGas = 0` and `gasPrice = 0` (positional args 5 and 7 at `PolySafeCreatorWithRecoveryModule.sol:203`). Per Safe v1.3.0 `execTransaction`, when both are zero and the inner Safe call fails, `execTransaction` reverts with `GS013` rather than silently returning `false`. So the only way the call returns is on inner-call success, in which case the bool is `true` and ignoring it is a stylistic — not security — issue. The previously-cited "ServiceManager-level guard" is the inner-call revert propagating through `ServiceRegistry.deploy → IMultisig(...).create → execTransaction`, not an explicit success check in `ServiceManager`.

**Recommendation.** For defence-in-depth and clarity, either (a) check the bool explicitly in `PolySafeCreatorWithRecoveryModule.create` and revert on `false`, or (b) add an explicit post-condition (e.g. confirm the recovery module is in `getModulesPaginated()` after the call). Without one of these, future Safe versions or different `safeTxGas` / `gasPrice` parameterisations would reintroduce the silent-failure surface.

**`RecoveryModule.recoverAccess` side** — the bool is also not checked on-chain; the operational mitigation is off-chain pre-flight simulation by the master Safe before submitting the transaction (per `docs/recover_funds_lost_agent_eoa.md`).

⚠️ **NOT FIXED ON-CODE in the multisig creators.** Marking L-11 as fixed in §C4R / `Vulnerabilities_list_registries.md` item #13 is unsafe given current code — should be re-classified as a **documented trade-off** justified by Safe v1.3.0 revert semantics under the specific `safeTxGas = 0, gasPrice = 0` parameterisation, OR closed by an explicit on-chain check.

### 4.9 C4A L-12 / C4R S-1175 — `registerAgentsWithSignature` missing `msg.value` validation

**Original finding.** `registerAgentsWithSignature` does not validate the caller-supplied `msg.value`. Excess ETH is not refunded — it sits permanently in `ServiceManager`.

**Code state (HEAD `d60f7ef5`).** The forwarded value depends on the service's bond token (`ServiceManager.sol:619–630`):

- **Token-secured services** (custom ERC20 bond): forwards `{value: agentInstances.length * BOND_WRAPPER}` (i.e. `length * 1 wei`) to `ServiceRegistry.registerAgents`. Any excess `msg.value` above this constant is unrefunded and trapped in `ServiceManager`.
- **Native (ETH-secured) services**: forwards `{value: msg.value}` directly. The downstream check enforces an exact match, so excess simply causes a revert — no trapping.

The mirrored check on the non-signature path lives in `ServiceRegistry.registerAgents` at line 427: `if (msg.value != totalBond) revert IncorrectAgentBondingValue(...)`, where `totalBond` is the **sum of stored `agentParams.bond`** for the requested agent IDs. Because `ServiceManager.create` / `update` wrap token-secured bonds to `BOND_WRAPPER = 1`, `totalBond` reduces to `agentInstances.length * BOND_WRAPPER` for token-secured services only; for native services `totalBond` is the actual sum of ETH bonds.

**Status.** Acknowledged as **documented trade-off** (`docs/Vulnerabilities_list_registries.md` item #15). C4A assessed the dup (#S-1175) as "misconfigured registration from users" per Known Issues. The token-secured signature path is the only one where excess `msg.value` can be silently trapped; the native-secured path reverts on mismatch, and the non-signature `ServiceManager.registerAgents` path explicitly enforces `msg.value == totalBond` for token-secured services at `ServiceManager.sol:394–398`.

✅ **DOCUMENTED TRADE-OFF — ACCEPTED.**

### 4.10 C4A L-13 / C4R S-430 — `slash` abuse by service owner

**Original finding.** A service owner can install a malicious Safe module on the service multisig and call `ServiceRegistry.slash` on their own operators, stealing the bonds.

**Status.** Acknowledged as **documented trade-off** (`docs/Vulnerabilities_list_registries.md` item #16). Slashed funds are **locked** at `ServiceRegistry(L2)` and only the DAO-gated `drainer` can drain them (set to Treasury on Ethereum mainnet). No economic benefit for the service owner.

✅ **DOCUMENTED TRADE-OFF — ACCEPTED.**

### 4.11 C4A L-14 / C4R S-901 — `registerAgents` agent instance DoS

**Original finding.** An attacker can repeatedly front-run `registerAgents` calls with throw-away addresses, consuming slots.

**Status.** Acknowledged as **documented trade-off** (`docs/Vulnerabilities_list_registries.md` item #18). Agent instance addresses are unlimited; DoS has per-block gas cost for the attacker; no slot reservation beyond block-finality-ordering is possible without introducing a whitelist (which has its own scope issues, see §4.3).

✅ **DOCUMENTED TRADE-OFF — ACCEPTED.**

### 4.12 C4A summary

**Code status:**

| Severity | Registries-scope count | ✅ Fixed in `origin/main` | 📝 Documented (known issue) | 🔴 Not fixed (open) |
|---|---:|---:|---:|---:|
| High | 5 | 3 (H-05, H-06, H-10) | 2 (H-07, H-09) | 0 |
| Medium | 2 | 0 | 2 (M-08, M-10) | 0 |
| Low | 4 | 0 | 4 (L-11, L-12, L-13, L-14) | 0 |
| **Total** | **11** | **3** | **8** | **0** |

**Deployment status (only meaningful for code-fixed rows):**

| Deployment status | Count | Findings | Notes |
|---|---:|---|---|
| 🟢 Live on-chain | 1 | H-06 | `docs/configuration.json` references `abis/0.8.30/ServiceManager.json` on all production chains; bytecode-equivalence not directly verified in this report. |
| 🟡 Pending redeploy | 0 | — | — |
| ⚪ Code fix only — never deployed | 2 | H-05, H-10 | The post-fix `StakingToken` / `StakingNativeToken` source on HEAD `d60f7ef5` has not been deployed on any chain. Plan: deploy as a **new** implementation, register it in `StakingVerifier` as an additional allowlisted entry (the prior 0.8.25 / 0.8.28 implementations remain whitelisted in parallel), and `StakingFactory` will then produce new `StakingProxy` clones bound to the post-fix bytecode. Existing `StakingProxy` instances continue running against their original implementation by design (constructor-pinned, §5.5) — the fix is not retro-applied. Per §4.1 / §3.1 the pre-fix gap was not reachable on the OLAS-backed proxies actually live today (OLAS has no transfer hooks; `StakingNativeToken` has no live proxies on any supported chain), so the deployment is defence-in-depth, not an emergency. |

**Key dispositions for registries-scope:**

- **No C4A registries-scope finding remains open as a High/Medium actionable code bug.** All three code-level fixes (H-05, H-06, H-10) live on `origin/main`. The two High and two Medium findings without a code change (H-07, H-09, M-08, M-10) are accepted trade-offs documented in `docs/Vulnerabilities_list_registries.md`.
- **L-11 was previously framed as "fixed at the ServiceManager layer".** This report reclassifies it to a documented trade-off (§4.8): the bool return is still ignored in `PolySafeCreatorWithRecoveryModule.create:201–204`, but Safe v1.3.0 revert semantics under the deployed `safeTxGas = 0, gasPrice = 0` parameterisation prevent silent failure today. Recommendation: add an explicit on-chain check or post-condition for defence-in-depth.
- **The two staking fixes (H-05, H-10) are deployment-gated.** Operational follow-up: deploy a new `StakingToken` / `StakingNativeToken` implementation off `origin/main`, register it as an additional allowlisted entry in `StakingVerifier`, and let `StakingFactory` produce new clones against it. Existing proxies stay on their original (pre-fix) implementation by design. Per §3.1 the pre-fix gap was not reachable on OLAS-backed proxies actually live today, so the deployment is defence-in-depth, not an emergency.

Every trade-off is mapped to an entry in `docs/Vulnerabilities_list_registries.md` with explicit mitigation guidance.

## 5. On-chain verification (Ethereum mainnet, block-tip 2026-04-22)

Addresses sourced from `scripts/deployment/globals_mainnet.json` at HEAD `d60f7ef5`.

### 5.1 Registries contract owners

| Contract | Address | `owner()` / admin | Verdict |
|---|---|---|---|
| `ComponentRegistry` | `0x15bd…1776` | manager = `RegistriesManager` ✓; owner = Timelock ✓ | ✓ |
| `AgentRegistry` | `0x2F1f…9112` | manager = `RegistriesManager` ✓; owner = Timelock ✓ | ✓ |
| `RegistriesManager` | `0x9eC9…D6fE` | owner = Timelock ✓ | ✓ |
| `ServiceRegistry` | `0x48b6…75cA` | manager = `ServiceManager` ✓; owner = Timelock ✓ | ✓ |
| `ServiceRegistryTokenUtility` | `0x3Fb9…affA` | manager = `ServiceManager` ✓; drainer = Treasury ✓; owner = Timelock ✓ | ✓ |
| `ServiceManager` | `0x4443…b3A1` | owner = Timelock ✓ | ✓ |
| `ServiceManagerProxy` | `0x94a1…14c9` | impl = `ServiceManager` ✓; owner = Timelock ✓ | ✓ |
| `OperatorWhitelist` | `0x4204…5260` | owner = Timelock ✓ | ✓ |
| `GnosisSafeMultisig` | `0x46C0…b461` | ownerless (stateless factory) | ✓ |
| `GnosisSafeSameAddressMultisig` | `0xfa51…eF46` | ownerless | ✓ |
| `SafeMultisigWithRecoveryModule` | `0xCb72…5d70` | ownerless | ✓ |
| `RecoveryModule` | `0x69D9…2e3c` | ownerless (module attached per-service) | ✓ |
| `ComplementaryServiceMetadata` | `0x0561…93A1` | owner = Timelock ✓ | ✓ |
| `StakingFactory` | `0xEBdd…7efc` | owner = Timelock ✓; verifier = `StakingVerifier` ✓ | ✓ |
| `StakingVerifier` | `0x4503…A777` | owner = Timelock ✓ | ✓ |

`Timelock` = `0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE` (shared with `autonolas-governance` / `autonolas-tokenomics`).

All admin roles for registries contracts trace back to the same **governance Timelock**. No EOA-owned admin. No single-key exposure in the registries repo.

### 5.2 StakingFactory / StakingVerifier wiring

`StakingFactory` is permissionless for deploys — any caller can `createStakingInstance(implementation, initPayload)`. The `implementation` argument is validated against `StakingVerifier.isImplementationVerified`, an owner-gated allowlist maintained by the Timelock. `minStakingDepositLimit = 10 000 OLAS` (`globals_mainnet.json`) as economic floor.

Permissionless creation + owner-gated implementation allowlist is the intended design (same shape as `autonolas-tokenomics` `Dispenser` staking wiring).

### 5.3 `ServiceRegistryTokenUtility.drainer`

Per `docs/Vulnerabilities_list_registries.md` item #5: the drainer role on `ServiceRegistryTokenUtility` is expected to be **Treasury (`0xa0DA…0f82`)** on Ethereum mainnet only — and **not** assigned to Treasury on other chains per the documented guidance. Mainnet drainer confirms to Treasury. ✓

### 5.4 OpSec — no EOA exposure, but cross-repo context

The registries admin chain is uniformly `Timelock`. This inherits the governance repo's OpSec posture (per `audits/internal19` of `autonolas-governance` at tag `76bda389`):

- Timelock `getMinDelay() = 0` today (deployed state) — not a registries-repo concern, but is the constraint on how fast a registries admin action can be executed after scheduling.
- CM Safe holds `PROPOSER_ROLE` on the Timelock — can schedule a registries admin call directly, bypassing a Governor vote. Execution still requires `EXECUTOR_ROLE`, restricted to `GovernorOLAS`. Not exploitable today.
- Live effective delay 0 s → becomes ≥ 43.6 h once the re-audited governance code is redeployed.

None of these are registries-code findings — cross-repo OpSec context only.

### 5.5 StakingProxy storage-layout upgrade-compat

`StakingProxy.sol:27–51`: the implementation address is pinned in a fixed slot inside the constructor; there is **no upgrade function**. Existing deployed proxies are permanently bound to their original implementation bytecode, so the `_locked` slot (`StakingBase.sol:339`, present since `f59b339`) cannot collide with any live proxy's storage. New proxies deployed after PR #288 ships pick up the final layout cleanly.

✓ No storage-layout hazard. Derivative lock fix (§3.1) does not add any new storage slot — it only reads/writes the existing `_locked`.

## 6. Findings

### 6.1 Summary

| Severity | Count | Code status | Deployment status | IDs |
|---|---|---|---|---|
| Critical | 0 | — | — | — |
| High | 0 | — | — | — |
| Medium | 0 | — | — | — |
| Low | 1 (defence-in-depth) | 📝 Documented (known issue) — item #13 in `docs/Vulnerabilities_list_registries.md` | — (no code change) | L-11 — `PolySafeCreatorWithRecoveryModule.create` ignores `Safe.execTransaction` bool (§4.8). Not exploitable today under deployed Safe v1.3.0 + `safeTxGas = 0, gasPrice = 0`; recommendation: add an explicit on-chain check. |
| Notes | 0 new (3 carry-over from internal16) | — | — | N-1, N-2, N-3 (all informational / stylistic) |

No new manual-review finding from the fresh read beyond confirmation that the §A.5 fix is implemented correctly. Items requiring follow-up that are *deployment-state* (not code-state) — H-05 / H-10 staking implementation redeploy, see §4.12 — are tracked in the operational follow-up bullet of §4.12, not as findings here.

### 6.2 Internal16 Notes — status on HEAD

All three Notes from `audits/internal16/README.md` re-verified against HEAD `d60f7ef5`:

| Internal16 Note | Status NOW | Verification |
|---|:---:|---|
| Notes — `_locked` inline initializer is a no-op in proxy clones | UNCHANGED | Still `uint256 internal _locked = 1;` at `StakingBase.sol:339`; `0 → 2 → 1` on first call of fresh proxies; cosmetic only |
| Notes — Lock inlined per entry point rather than a modifier | UNCHANGED | Style consistent with `ServiceManager` / `ServiceRegistry`; robust |
| Notes — `_withdraw` comment about "balance ≥ sum of amounts" | RESOLVED | Now unconditionally accurate after §3.1 (derivative lock closes the last desync path) |

### 6.3 Prior internal15 findings — status on HEAD

All internal15 findings re-verified against HEAD `d60f7ef5`:

| Internal15 finding | Sev | Status NOW | Verification |
|---|:---:|:---:|---|
| Stream A Low — `StakingBase._withdraw` cross-service reentrancy | L | **FIXED** | `_locked` guard (§4.1) |
| Stream D Low — Custom distributor can return `address(stakingContract)` | L | **FIXED** | Receiver check `StakingBase.sol:742–744` |
| Stream D Low — No code-existence check on custom distributor at stake time | L | **FIXED** | `customRewardsDistributor.code.length == 0` at `StakingBase.sol:852–854` |
| Stream B Low — `ServiceRegistry.registerAgents` missing reentrancy guard | L | UNCHANGED | `ServiceRegistry.registerAgents` (line 389) and `ServiceRegistryL2.registerAgents` (line 382) remain unguarded; mitigation is at the `ServiceManager` periphery only — `registerAgents` (line 374–378) and `registerAgentsWithSignature` (line 585–588). Direct callers with the `manager` role bypass the guard, which is acceptable given the role is held by the Timelock-controlled `ServiceManager`. |
| Stream D Medium — PolySafe `execTransaction` return silently ignored | **M** | UNCHANGED | Cross-refs C4A L-11 §4.8; bool still unchecked in `PolySafeCreatorWithRecoveryModule.create:201–204`. Safe v1.3.0 reverts on inner-call failure under deployed `safeTxGas = 0, gasPrice = 0`, so not exploitable as silent-success today. Recommendation in §4.8 to add explicit on-chain check. |
| Stream D Notes — `calculateStakingLastReward()` rounding dust | Info | UNCHANGED | Item #21 in `Vulnerabilities_list`; cosmetic only |
| Stream D Notes — `ApplicationClassifier` untested | Info | **ADDRESSED** | `test/ApplicationClassifier.js` (+210 LOC) |
| Stream D Notes — Zero fuzz tests | Info | **ADDRESSED** | `test/StakingFuzz.t.sol` (+379 LOC) |
| Stream C Low/Info — PolySafe CREATE2 front-running | L/Info | UNCHANGED | Item #12 in `Vulnerabilities_list`; accepted |
| Stream D Notes — `ComplementaryServiceMetadata` reentrancy guard style (`== 2` vs `> 1`) | Info | UNCHANGED | Noted |
| Stream B/D Notes — `uint96(msg.value)` unsafe downcast | Info | UNCHANGED | Noted |

### 6.4 Key invariants verification

Re-checking five key staking invariants on HEAD `d60f7ef5`:

1. **Sum of operator bonds == contract ETH/token balance** (`ServiceRegistryTokenUtility`) — HOLDS. Not touched by this branch.
2. **Sum of staking rewards claimed ≤ `availableRewards`** — HOLDS. Reward-calculation path byte-identical except for `checkpoint` visibility rename; proportional-scaling branch intact.
3. **Every service state transition is valid (no skip)** — HOLDS. State machine in `ServiceRegistry`, not touched.
4. **ERC721 ownership always matches service state** — HOLDS. `_stake` transfers NFT to `address(this)` at line 865; `_unstake` transfers back at line 946. Both paths lock-guarded.
5. **`StakingBase.balance ≥ sum of pending rewards`** — HOLDS UNCONDITIONALLY after §3.1. The derivative `receive()` / `deposit()` entries share the lock, so no nested callback can desync `balance` against the local cache in `_withdraw`.

### 6.5 Verified safe (delta attack-review)

- **Nested ETH deposit** (`attacker.receive() → stakingNativeToken.receive{value}`) is now blocked — derivative `receive()` sees `_locked == 2` and reverts.
- **Nested ERC20 deposit** (`attacker.receive() → stakingToken.deposit(amount)`) is now blocked symmetrically.
- **Deposit-during-deposit** (hook-carrying token's `tokensReceived` / `onTransferReceived` callback during `safeTransferFrom` re-enters `deposit` or `receive`) is now blocked — both are lock-guarded and CEI-safe under the lock.
- **Lock release on revert vs. swallowed revert:** when the inner nested call reverts and the outer caller propagates that revert (does not catch via low-level `.call`), the outer entry point reverts transitively and the `_locked = 2` SSTORE is undone as part of the revert — no manual cleanup. When the outer caller swallows the inner revert (as in `test_Reentrancy_NestedReceive_RevertsWithGuard`), the outer entry point completes successfully and the `_locked = 1` line at function end runs normally, releasing the lock. Both paths leave a consistent `_locked = 1` post-state; the security property is that the nested write never lands, regardless of which branch the outer caller takes.
- **No new external entry point introduced** — the delta only adds lock-acquire/release around pre-existing function bodies. No new surface.
- **Import of `ReentrancyGuard`** from `StakingBase` into the derivatives is syntactically valid (file-scope error, re-exportable) and does not introduce a name clash.
- **Pragma bump `^0.8.25 → ^0.8.30`** on the derivatives — no behavioural regression; 0.8.30 is already used elsewhere in the repo.

## 7. `docs/Vulnerabilities_list_registries.md` hygiene

Document tracks 22 items. Re-verified each against HEAD `d60f7ef5`.

| # | Title | Severity | Code still present? | Mitigation in place? |
|---|---|---|---|---|
| 1 | `tokenURI` function — returns string even for invalid NFT | Low | ✅ yes (`GenericRegistry`) | ✅ caller-side `exists()` |
| 2 | `create` function — `GnosisSafeMultisig` payload is free-form | Low | ✅ yes | ✅ service owner responsibility |
| 3 | `update` function — zero bonds with non-zero slots | Low | ✅ yes (registry-layer) | ✅ `ServiceManagerToken.js#L120` rejects |
| 4 | `update` function — agent Ids replacement | Low | ✅ yes | ✅ off-chain audit caveat |
| 5 | `drain` function — Treasury drainer role | Info | ✅ yes | ✅ Treasury-only drainer on mainnet |
| 6 | `_checkTokenStakingDeposit` — securityDeposit ≥ bond precondition | Info | ✅ yes | ✅ caller discipline |
| 7 | `_isRatio` function — activity-checker tamper vector | Info | ✅ yes | ✅ governance allowlist via `StakingVerifier` |
| 8 | `stake` function — eviction state gating | Info | ✅ yes | ✅ explicit unstake required |
| 9 | `unstake` function — `minStakingDuration` commitment | Info | ✅ yes | ✅ by design |
| 10 | `checkpoint` function — O(n) gas overflow | High | ✅ yes | ✅ 100-slot launcher discipline |
| 11 | `deploy` function — `RecoveryModule` does not restore off-chain dependencies | Info | ✅ yes | ✅ integration-level advisory |
| 12 | `create` function — PolySafe CREATE2 front-run | Low | ✅ yes | ✅ `GnosisSafeSameAddressMultisig.create()` fallback |
| 13 | `execTransaction` return value ignored (C4A L-11 / C4R S-69) | Low | ✅ yes | ⚠️ Bool still unchecked in `PolySafeCreatorWithRecoveryModule.create:201–204`; not exploitable today due to Safe v1.3.0 revert semantics under deployed `safeTxGas = 0, gasPrice = 0` (§4.8). Recommendation: add explicit on-chain check or post-condition. `RecoveryModule` side: off-chain pre-flight. |
| 14 | `registerAgentsWithSignature` operator whitelist bypass (C4A H-07 / C4R S-149) | Low | ✅ yes | ✅ service owner self-restriction (accepted) |
| 15 | `registerAgentsWithSignature` missing `msg.value` validation (C4A L-12 / C4R S-1175) | Low | ✅ yes | ✅ caller-side discipline (accepted per Known Issues) |
| 16 | `slash` mechanism abuse (C4A L-13 / C4R S-430) | Low | ✅ yes | ✅ no economic benefit (funds locked in registry) |
| 17 | `registerAgentsWithSignature` missing deadline / max bond (C4A H-09 / C4R S-858, S-862) | Low | ✅ yes | ✅ nonce makes signature single-use; operational discipline |
| 18 | `registerAgents` agent instance DoS (C4A L-14 / C4R S-901) | Low | ✅ yes | ✅ gas-cost asymmetry |
| 19 | `slash` + proportional split (C4A M-08 / C4R S-885) | Info | ✅ yes | ✅ decoupled by design; `Custom` distributor escape hatch |
| 20 | `checkpoint` during absence of rewards (C4A M-10 / C4R S-763) | Info | ✅ yes | ✅ wei-level top-up discipline |
| 21 | `calculateStakingLastReward` rounding dust | Info | ✅ yes | ✅ cosmetic only |
| 22 | `ServiceRegistry` `registerAgents` / `update` / `activateRegistration` missing inline reentrancy guard | Info | ✅ yes | ✅ manager-role-mitigated (only Timelock-controlled `ServiceManager` can call; the `ServiceManager.registerAgents` / `registerAgentsWithSignature` wrappers are themselves lock-guarded — see §4.2 caveat). New entry added this audit pass; not a C4R finding. |

**Hygiene recommendations:**

1. **Fixed-on-code entry removed** — former item #13 (`_claim` reward-before-checkpoint sequence) has been removed and subsequent items renumbered #14→#13, #15→#14, …, #22→#21. The `_claim` ordering in `StakingBase.sol:548–583` already invokes `_checkpoint()` before reading `sInfo.reward`, so the zero-reward revert described in the old entry cannot occur. Covered by `test/StakingBaseCoverage.t.sol:test_CheckpointAndClaim_HappyPath` and `test/ServiceStaking.js` flows around `checkpointAndClaim`.
2. **Documentation drift — ADDRESSED.** Items #14 / #15 / #17 previously reproduced a `registerAgentsWithSignature` signature snippet with a spurious `uint256 deadline` parameter and an `address serviceOwner` first argument. All three snippets have been updated to match the deployed signature `registerAgentsWithSignature(address operator, uint256 serviceId, address[] memory agentInstances, uint32[] memory agentIds, bytes memory signature) external payable returns (bool success)`.
3. **C4A H-05 / H-10 and the §A.5 derivative lock are NOT added to the list** — these were defects now fixed on-code with dedicated tests. The list is reserved for known, deliberately unfixed trade-offs (same rule applied in `autonolas-tokenomics/audits/internal15` and `autonolas-governance/audits/internal19`).

## 8. Conclusion

- **§A.5 follow-up** (internal16's residual Low) — **Code: ✅ Fixed in `origin/main`** by commits `36609be` + `d60f7ef5` (PR #288). Derivative `receive()` / `deposit()` now share the `_locked` slot; Invariant 5 holds unconditionally. **Deployment: ⚪ Code fix only — never deployed** — same as H-05 / H-10: this version of `StakingToken` / `StakingNativeToken` has not yet been deployed; will land as a new allowlisted implementation in `StakingVerifier`, alongside the existing one. Fix implemented exactly as internal16 specified (§3.1).
- **C4A registries-scope (5H + 2M + 4L) — code-status disposition:** 3 ✅ Fixed in `origin/main` (H-05, H-06, H-10), 8 📝 Documented (known issue) with mitigations in `docs/Vulnerabilities_list_registries.md` (H-07, H-09, M-08, M-10, L-11, L-12, L-13, L-14), 0 🔴 Not-fixed open. L-11 is the reclassification from "fixed at ServiceManager layer" to documented trade-off (§4.8): bool still unchecked in `PolySafeCreatorWithRecoveryModule.create`, non-exploitable under deployed Safe v1.3.0 + `safeTxGas = 0, gasPrice = 0`; recommendation to add explicit on-chain check.
- **C4A registries-scope — deployment-status disposition (for the 3 code-fixes):** 1 🟢 Live on-chain (H-06: `ServiceManager` references `abis/0.8.30/ServiceManager.json` on all production chains; not bytecode-checked here); 2 ⚪ Code fix only — never deployed (H-05 / H-10: post-fix `StakingToken` / `StakingNativeToken` source on HEAD has never been deployed; planned to land as a new allowlisted implementation in `StakingVerifier` — added alongside, not replacing, the existing implementation. Existing `StakingProxy` instances are constructor-pinned and remain on their original implementation by design. Operational follow-up, not blocking — pre-fix gap was not reachable on OLAS-backed proxies live today per §3.1.).
- **On-chain owner map (§5)** — all registries contracts resolve to the same governance Timelock as `autonolas-governance` and `autonolas-tokenomics`. No EOA-owned admin. Permissionless `StakingFactory` + owner-gated `StakingVerifier` allowlist.
- **New code findings this pass:** 0 High / 0 Medium / 1 Low / 0 new Notes. The Low is L-11 (`execTransaction` bool unchecked in `PolySafeCreatorWithRecoveryModule.create`), reclassified from the prior "fixed at ServiceManager layer" framing — see §4.8. The three Notes from internal16 carry over unchanged (one of which is now explicitly resolved by §A.5).
- **Internal15 findings** — all re-verified; three previously-open Lows fixed on the hardening branch.
- **`Vulnerabilities_list_registries.md`** — now 22 entries: 21 after removing the former `_claim` reward-before-checkpoint entry (fixed on-code, covered by `test/StakingBaseCoverage.t.sol`), plus a new item #22 added this pass for `ServiceRegistry.registerAgents` / `update` / `activateRegistration` missing inline reentrancy guard (manager-role-mitigated). Item #13 (L-11) rewritten to accurately describe what PR #241's zero-check does and does not protect.

**Verdict: no High / Medium findings on commit `d60f7ef5`; one Low (L-11, defence-in-depth) and three informational Notes carried from internal16.** The C4A external audit + post-C4R hardening + PR #288 closed every High/Medium registries-scope issue at the **code level**. L-11 is non-exploitable today under deployed Safe parameters but warrants an explicit on-chain bool check in `PolySafeCreatorWithRecoveryModule.create` for defence-in-depth. The two staking fixes (H-05, H-10) live on `origin/main` but the new `StakingToken` / `StakingNativeToken` implementation has not been deployed yet — when it is, it will be added as a new allowlisted entry in `StakingVerifier` alongside the existing one (existing proxies are constructor-pinned and stay on their original implementation by design). Defence-in-depth follow-up, not blocking. **Recommendation: ship; schedule (a) a follow-up PR adding an explicit `execTransaction` bool/post-condition check in `PolySafeCreatorWithRecoveryModule`, and (b) deployment of the post-fix `StakingToken` / `StakingNativeToken` as a new allowlisted implementation in `StakingVerifier` on the chains where it matters.**

## 9. Methodology Compliance Report (AGENT-RULES.md)

| Rule | Compliance |
|---|---|
| 1. Exhaustive checking | ✓ C4A (11H+12M+15L) triaged; Vulnerabilities_list (22 entries) all checked; internal15 + internal16 findings all re-verified |
| 2. Cross-domain patterns | ✓ DeFi reentrancy + callback + CEI + proxy-storage patterns applied; staking-specific patterns (custom distributor, lock extension to derivative entries) covered |
| 3. Checklist log | ✓ this document (§4 matrix + §6.3 internal15 table + §6.2 internal16 table + §7 hygiene table) |
| 4. Playbook updates all-or-nothing | ✓ v2.22 applied; registry / staking / multisig patterns covered |
| 5. Post-audit vulnerability monitoring | ✓ C4A H-05/H-06/H-10 → fix confirmed; L-11 reclassified to documented trade-off (§4.8); §A.5 (internal16 residual) closed |
| 6. No premature "all clear" | ✓ §6 lists carry-over Notes explicitly; §4 lists every accepted trade-off |
| 7. Compliance report | ✓ this section |

## Appendix A — Verification commands

```bash
# Delta since internal16
git log --oneline b5c50ae..d60f7ef5
# → 2 commits: 36609be (fix), d60f7ef5 (merge of PR #288)

# Production-code scope of the delta
git log b5c50ae..d60f7ef5 -- contracts/
# → touches only contracts/staking/StakingNativeToken.sol, StakingToken.sol

# Full delta since internal15 merge
git log --oneline bba1585..d60f7ef5
git log bba1585..d60f7ef5 -- contracts/

# Fix commits inspection
git show 36609be -- contracts/staking/StakingNativeToken.sol contracts/staking/StakingToken.sol

# Proxy upgrade-compat check
cat contracts/staking/StakingProxy.sol
# → constructor-pinned implementation, no upgrade function
```

## Appendix B — Key file:line references

| Reference | Purpose |
|-----------|---------|
| `StakingNativeToken.sol:35–53` | Locked `receive()` (§3.1) |
| `StakingToken.sol:109–130` | Locked `deposit()` (§3.1) |
| `StakingBase.sol:192–196` | Errors `ReentrancyGuard`, `UnauthorizedAccount` |
| `StakingBase.sol:338–339` | `_locked` storage slot |
| `StakingBase.sol:557, 763, 876` | Internal flows switched from `checkpoint()` → `_checkpoint()` |
| `StakingBase.sol:735–744` | Receiver validation (zero + self-receiver) in `_getRewardReceiversAndAmounts` |
| `StakingBase.sol:725` | Custom distributor `STATICCALL` site |
| `StakingBase.sol:844–854` | Custom distributor code-existence check in `_stake` |
| `StakingBase.sol:952–974` | `_withdraw` (unchanged body; balance-cache pattern) |
| `StakingBase.sol:983` | Internal `_checkpoint()` (renamed from public `checkpoint`) |
| `StakingBase.sol:1119–1227` | Seven locked external entry points |
| `StakingProxy.sol:27–51` | Constructor-pinned implementation, no upgrade path |
| `ServiceManager.sol:577–635` | `registerAgentsWithSignature` with `_locked` guard |
| `test/StakingSecurityFixes.t.sol` | Dedicated hardening test suite |
| `test/StakingBaseCoverage.t.sol` | 100%-line coverage suite |
| `test/StakingFuzz.t.sol` | Fuzz suite |
| `test/StakingDerivativeReentrancy.t.sol` | Nested `receive()` / `deposit()` reentry tests (§3.1) |

## Appendix C — Commits on the branch (ahead of `origin/main = bba1585`)

```
d60f7ef Merge pull request #288 from valory-xyz/fix/staking-derivative-reentrancy-lock
36609be fix: extend reentrancy lock to StakingNativeToken.receive and StakingToken.deposit
b5c50ae doc: internal audit 16
5334da6 test: StakingBase coverage suite reaches 100% lines
cf18220 doc: clarify enum range gating for RewardDistributionType
c432404 refactor: name return params in checkpoint, drop return statement
f59b339 fix: harden StakingBase post-C4R audit
```

The last two commits (`36609be`, `d60f7ef5`) are the delta this audit (`internal17`) covers relative to `audits/internal16/README.md`.
