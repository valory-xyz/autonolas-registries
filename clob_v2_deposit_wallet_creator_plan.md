# Polymarket Deposit-Wallet — Multisig Creator Contract Plan

**Date:** 2026-05-02 (initial); 2026-05-04 (probe correction — see §"Probe results"); 2026-05-09 (fresh code-side re-verification — see §"Re-verification 2026-05-09"); 2026-05-10 (design lock-in — see §"Design lock-in 2026-05-10")
**Status:** Design locked-in to corrected Design C (Option B). Two prior load-bearing caveats (DW recovery weakness, front-running) explicitly accepted by the product team. Implementation ready to scope.
**⚠️ READER NOTE:** Sections below pre-2026-05-04 assume a "Safe wraps DepositWallet by being its owner" topology. **That topology was invalidated by the 2026-05-04 source probe** — the DepositWallet's `isValidSignature` does plain ECDSA recovery against the owner, so the owner must be an EOA, not a Safe. See §"Probe results — 2026-05-04 — major design correction" immediately below for the corrected topology. The detailed sections that follow (Design B in depth, Design C, Recommended design) are preserved for historical context but their core "Safe-as-DW-owner" assumption is wrong; read them after the Probe results section.
**Companion to:** `clob_v2_impact_polySafeCreator.md` (impact on existing
PolySafeCreator) and `../wildcard/CLOB_V2_FOLLOWUPS.md` (full architecture
sweeps).
**Trigger:** Reading-B-contingent migration in §"Action items / Reading-B-contingent"
of CLOB_V2_FOLLOWUPS.md — if Polymarket's deposit-wallet rollout
forces new accounts off the PolySafe path, OLAS services need a new
`IMultisig`-shaped creator that produces a deposit-wallet-backed
multisig instead of a PolySafe.

## TL;DR

**Updated 2026-05-04 after Polygonscan/Sourcify source probe.**

- A **new creator contract is feasible** but its shape is materially different
  from `PolySafeCreatorWithRecoveryModule.sol` and `SafeMultisigWithRecoveryModule.sol`.
- The **OLAS service multisig stays a regular Gnosis Safe** (with `RecoveryModule`
  pre-enabled, ERC-8004 compatible). The deposit wallet is a **separate per-service
  asset** owned directly by the **agent-instance EOA** (not the Safe — the Safe
  cannot own a deposit wallet because the wallet's signature path requires the
  owner to be ECDSA-recoverable).
- The Safe and the DepositWallet are **independent peers**, both reachable
  through the same agent-instance EOA. The agent EOA is one of the Safe's
  owners and the sole owner of the DepositWallet.
- **`DepositWalletFactory.deploy()` is `onlyOperator`-gated; the factory has
  no meta-tx variant.** Polymarket's hosted relayer is the only deployer.
  Pearl client orchestrates: HTTP-call the relayer to pre-deploy the wallet
  in parallel with OLAS service registration; the on-chain creator only
  verifies the wallet exists and binds it to the Safe.
- **`DepositWallet.execute()` is `onlyFactory`-gated.** All batch operations
  (session-signer authorization, approvals) must go through the relayer. The
  wrapper cannot inline them in the deploy tx. Phase 4 stays an off-chain
  relayer batch.
- ERC-8004 compatibility (`IdentityRegistryBridger.setAgentWallet`) keeps working
  because the Safe — not the deposit wallet — is the multisig the bridger
  records as the agent wallet.
- **Recovery is materially weaker than today's PolySafe.** Lose the agent-EOA
  key, lose the DepositWallet's funds (no RecoveryModule equivalent for the
  DepositWallet). Mitigation: trader sweeps DW balance back to the Safe
  regularly, keeping DW balance close to current trading needs only.

## Probe results — 2026-05-04 — major design correction

Source for `DepositWalletFactory` (`0x00000000000Fb5C9ADea0298D729A0CB3823Cc07`)
and `DepositWallet` (`0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB`) extracted
via Sourcify. Three load-bearing facts:

### 1. Path 2 (operator-sig meta-tx variant) is confirmed NOT available

```solidity
// DepositWalletFactory.sol
function deploy(address[] calldata _owners, bytes32[] calldata _ids) external onlyOperator { ... }
function proxy(Batch[] calldata _batches, bytes[] calldata _signatures) external onlyOperator { ... }
```

Both write entry points are `onlyOperator`-gated. `proxy()` is *not* a deploy
meta-tx — it forwards `Batch[]` to existing wallets via their `execute()`. There
is no `deployWithOperatorSig` or any signature-bearing alternative. **Collapse
1 (in-tx deposit-wallet deploy from the creator) is permanently off the table.**

### 2. The DepositWallet's owner MUST be an EOA — Safe cannot own it

```solidity
// DepositWallet.sol — bottom-level signature check (the override)
function _erc1271IsValidSignatureNowCalldata(bytes32 hash, bytes calldata signature)
    internal view override returns (bool)
{
    address signer = _erc1271Signer();
    // always ECDSA, regardless of signer.code.length
    return (signer != address(0)) && (ECDSA.tryRecoverCalldata(hash, signature) == signer);
}
```

The verbatim `// always ECDSA` comment is on line 449. There is no
`signer.code.length > 0` fallback to `IERC1271(signer).isValidSignature(...)`.
**A Safe (or any contract) cannot satisfy this.**

This invalidates the previous Design B/C topology where the Safe owns the
DepositWallet via a CREATE2-precomputed address. **Replaced with the
"independent peers" topology in §"Corrected design — Safe + DepositWallet
as independent peers" below.**

#### Verification chain — triple-confirmed against source

The "EOA-only owner" claim is load-bearing for the entire architecture, so
worth showing in three layers:

**(a) `ECDSA.tryRecoverCalldata` is a pure ECDSA precompile call** (solady
`ECDSA.sol:202-231`):

```solidity
function tryRecoverCalldata(bytes32 hash, bytes calldata signature)
    internal view returns (address result)
{
    assembly {
        for { let m := mload(0x40) } 1 {} {
            switch signature.length
            case 64 { /* parse EIP-2098 compact: r, vs */ }
            case 65 { /* parse r, s, v */ }
            default { break }
            mstore(0x00, hash)
            pop(staticcall(gas(), 1, 0x00, 0x80, 0x40, 0x20))   // ← precompile 0x01 (ecrecover)
            mstore(0x60, 0)
            result := mload(xor(0x60, returndatasize()))
            mstore(0x40, m)
            break
        }
    }
}
```

- Only accepts 64-byte (EIP-2098 compact) or 65-byte (`r,s,v`) signatures —
  any other length returns `address(0)`.
- The `staticcall(gas(), 1, ...)` invokes Ethereum's `ecrecover` precompile
  at address `0x01`. **The precompile only handles ECDSA**; there is no
  `extcodesize` check, no `IERC1271(signer).isValidSignature(...)` call, no
  fallback path of any kind. By definition, only EOAs are recoverable.

**(b) Polymarket's override of `_erc1271IsValidSignatureNowCalldata` is
intentional, not accidental.** Solady's *default* base implementation
(`ERC1271.sol:65-72`) actually DID support contract sigs:

```solidity
// solady ERC1271.sol:65-72 — the default that Polymarket overrode
function _erc1271IsValidSignatureNowCalldata(bytes32 hash, bytes calldata signature)
    internal view virtual returns (bool)
{
    return SignatureCheckerLib.isValidSignatureNowCalldata(_erc1271Signer(), hash, signature);
}
```

`SignatureCheckerLib.isValidSignatureNowCalldata` tries ECDSA first **and
then falls back to `IERC1271(signer).isValidSignature(...)` if the signer
has code.** A Safe-as-owner would have worked with the default. **Polymarket
explicitly opted out of this fallback** by `override`-ing the function with
pure ECDSA. This is a deliberate design choice — the deposit wallet is
designed to require EOA owners.

**(c) All three solady ERC1271 validation paths converge on the override.**
Solady's `ERC1271._erc1271IsValidSignature` (the function that gets called
by external `isValidSignature(...)` requests) tries three paths in order:

```solidity
// solady ERC1271.sol:97-107
function _erc1271IsValidSignature(bytes32 hash, bytes calldata signature)
    internal view virtual returns (bool)
{
    return _erc1271IsValidSignatureViaSafeCaller(hash, signature)     // line 117 — calls override
        || _erc1271IsValidSignatureViaNestedEIP712(hash, signature)   // line 286 — calls override
        || _erc1271IsValidSignatureViaRPC(hash, signature);           // line 324 — calls override
}
```

All three branches ultimately invoke `_erc1271IsValidSignatureNowCalldata` —
which is overridden in DepositWallet to use pure ECDSA. So no matter which
entry path is taken (trusted "safe caller", external nested-EIP-712, or
RPC-based ERC-6492 pre-deploy), the leaf check is the same pure-ECDSA
override. **No escape hatch; no path that supports contract sigs.**

#### Why Polymarket might have made this choice (speculative)

- **Performance:** pure ECDSA is cheaper (no `EXTCODESIZE` check, no
  potential `STATICCALL` to the owner contract). For a wallet that processes
  many CLOB-order signature validations per second, the savings add up.
- **Simplicity / auditability:** the signing surface is one fixed primitive
  (ECDSA recovery). Auditors don't have to reason about delegated signature
  schemes via 1271 chains.
- **Architectural intent:** Polymarket's deposit-wallet design has a
  built-in session-signer mechanism. They likely view the
  `(owner, sessionSigners[])` model as the canonical way to delegate signing
  authority — not "let the owner be a contract that has its own signing
  scheme." Smart-contract-as-owner would compete with the session-signer
  abstraction.

Whatever the reason, the choice forecloses the "Safe wraps DW by being its
owner" topology. The corrected design treats the Safe and DW as independent
peers bridged by the agent-instance EOA.

### 3. `execute()` is `onlyFactory`-gated; Phase 4 cannot inline

```solidity
function execute(Batch calldata _batch, bytes calldata _signature) external onlyFactory { ... }
```

All batch ops (session-signer authorization, `transferOwnership`, approvals to
exchanges, etc.) must flow through `factory.proxy()` — which is `onlyOperator`.
**The wrapper cannot inline `wallet.execute(...)` in the deploy tx.** Phase 4
stays an off-chain relayer batch.

Owner-direct calls bypassing `execute()` are a small set: `pause`, `unpause`,
`withdrawERC20`, `withdrawERC1155`, `revokeAllowance`, `revokeApprovalForAll`,
`revokeSessionSignerEmergency`. These are `onlyOwner` (`msg.sender` check) and
work without the relayer — useful for emergency fund recovery (if Pearl pauses,
withdraws, then unpauses), but require the agent EOA to be live.

### 4. Salt scheme — confirmed from `relayer-client@0.0.9` `derive.js`

```javascript
walletId = bytes32(owner)                          // owner left-padded to 32 bytes
salt     = keccak256(abi.encode(factory, walletId))
init     = ERC1967 minimal proxy → implementation, with ctor args (factory, walletId)
addr     = CREATE2(factory, salt, keccak256(init))
```

- **One owner address = exactly one DepositWallet, ever.** No nonce, no version.
- The salt is entirely owner-derived. **No Safe-derived information enters
  the salt** — Phase 2 pre-deploy depends only on the agent-EOA address.

### Corrected design — Safe + DepositWallet as independent peers

```
                ServiceSafe                        DepositWallet
       (OLAS service multisig)                  (Polymarket trading)
                    │                                  ▲
                    │ owners[] include                 │
                    │ agentInstance                    │ owner field =
                    │                                  │ agentInstance
                    └──────────────┬───────────────────┘
                                   ▼
                       agent-instance EOA
                          (sole bridge)

  Safe-side: governance, threshold, RecoveryModule, ERC-8004 agent wallet,
             holds reserve funds, sweeps DW periodically.
  DW-side:   trading-only surface, ECDSA-validated by agent EOA via solady
             nested-EIP-712 envelope (ERC-7739), session signers optional,
             all batch ops via Polymarket relayer.
  Bridge:    agent-instance EOA is one of the Safe's owners AND is the
             DW's sole owner. Same key signs Safe-txs and DW typed-data.
```

The OLAS-side `IMultisig.create()` produces the Safe (unchanged). The
DepositWallet is created out-of-band by the relayer with the agent EOA as
owner. The creator's on-chain verification step changes from "DW owner ==
Safe" to "DW owner == agentInstance":

```solidity
// In creator.create():
require(IDepositWallet(depositWalletAddr).owner() == agentInstances[0]);
```

The on-chain link record (`mapMultisigDepositWallets[safe] = depositWallet`)
and the `DepositWalletLinked` event are still useful — they let third parties
(8004 indexers, dashboards, the trader itself) discover a service's DW from
its Safe.

### Updated revised flow (incorporates probe findings)

```
T = 0
  ├─ Pearl generates agent-instance EOA.
  ├─ Computes predictedSafe from Safe initializer.
  ├─ Computes predictedDw from agent-EOA address (NOT Safe).
  └─ Pre-signs the agent-EOA WALLET batch authorising session signer +
     approvals (signed by the agent EOA itself, since agent EOA is the DW owner).

T = 0+   Phase 1 ‖ Phase 2 in parallel:
  ├─ Phase 1: ServiceManager.create / activateRegistration / registerAgents
  │           (or one tx via the createAndDeploy wrapper if Collapse 2 is built).
  └─ Phase 2: HTTP → relayer → DepositWalletFactory.deploy([agentEOA], [bytes32(agentEOA)]).

T = max(Phase1, Phase2)
  Phase 3: ServiceManager.deploy(serviceId, creator, data).
           Inside creator.create():
             1. Decode (saltNonce, fallbackHandler, depositWalletAddr).
             2. Deploy Safe via SafeProxyFactory.createProxyWithNonce.
             3. require(depositWalletAddr.code.length > 0).
             4. require(depositWalletAddr.codehash == depositWalletBytecodeHash).
             5. require(IDepositWallet(depositWalletAddr).owner() == agentInstances[0]).
             6. mapMultisigDepositWallets[newSafe] = depositWalletAddr.
             7. emit DepositWalletLinked(newSafe, depositWalletAddr).
             8. return newSafe.

T = Phase3+
  Phase 4: Pearl trader submits the pre-signed WALLET batch to relayer →
           relayer.proxy([batch], [sig]) → wallet.execute(batch, sig) →
           authorizeSessionSigner + approvals applied.
           Service trading-ready ~5–30s after Phase 3 receipt.
```

User experience: **one click, one signing prompt, one user-paid on-chain tx,
plus background relayer roundtrips that resolve in seconds.** The "service
deployed" ↔ "trading ready" gap is the time for Phase 4's relayer batch to
land, typically under a minute.

### What this changes vs. the previous plan

| Section | Previous claim | Updated claim |
|---|---|---|
| §"Three design options" Design B/C | "Safe wraps DepositWallet via owner field" | **Invalidated.** Safe cannot own DW. New Design D ("independent peers") replaces them. |
| §"Why creator can't trigger deploy itself" Path 2 | "Probe-gated; might exist" | **Confirmed not present.** Factory has no meta-tx variant. |
| §"Can we collapse … Collapse 1" | "Gated on Path 2 probe" | **Permanently off the table.** Phase 2 must be off-chain via relayer. |
| §"Target end-state" — Phase 4 inlining | "Probe-gated public executeBatch" | **Off the table.** `wallet.execute` is `onlyFactory`. Phase 4 must be off-chain via relayer. |
| §"Why Safe should NOT have agent instances as direct owners of DW" | Argued the Safe should own DW | **Argument inverted.** Agent-EOA-as-owner is now the only viable model. The original argument's downsides (no recovery for DW funds, no threshold control over DW) are now load-bearing concerns, not avoidable costs. |
| §"Recovery flow under wrapping" | Master Safe regains control of DW after Safe recovery | **Materially weaker.** RecoveryModule recovers the Safe but not the DW. Lost agent EOA = DW funds stranded. Mitigation: frequent sweep. |

### What still applies from the previous plan

- The IMultisig `create()` shape and wrapper-data design (just with `agentInstances[0]` instead of the Safe in the owner-check).
- The on-chain link record (`mapMultisigDepositWallets`) and `DepositWalletLinked` event.
- Phase 1 ‖ Phase 2 parallelism.
- The CREATE2 front-running consideration (carries over from PolySafe).
- The OLAS-side Collapse 2 (`createAndDeploy` wrapper) — independently valuable.
- ERC-8004 compatibility analysis (Safe is the agent wallet; DW is invisible to the bridger).
- Reading A vs Reading B contingency framing.
- ERC-7739 / nested EIP-712 finding (it's solady's ERC1271 nested envelope; trader builds it via 1.0.3+ SDK).

## What we're building and why

OLAS services currently get a Polymarket-tradable wallet via
`PolySafeCreatorWithRecoveryModule` (`contracts/multisigs/PolySafeCreatorWithRecoveryModule.sol`),
whitelisted on `ServiceRegistryL2.mapMultisigs`. `ServiceRegistryL2.deploy(serviceId, multisigImplementation, data)`
calls `IMultisig(multisigImplementation).create(agentInstances, threshold, data)`,
which:

1. Calls `PolySafeProxyFactory.createProxy(...)` (Polymarket's variant of the
   Gnosis Safe factory at `0xaacFeEa…541b`) on Polygon, creating a PolySafe
   owned by the agent instance.
2. Verifies bytecode hash, owners, threshold.
3. Calls `Safe.execTransaction(enableModule(recoveryModule))` on the new Safe,
   using a pre-signed (or sender-approved) signature.

The resulting PolySafe is the OLAS service multisig, the ERC-8004 agent
wallet, and the CLOB trading wallet (signing orders as `sigType=2 POLY_GNOSIS_SAFE`).

CLOB v2 ships a new account model — **deposit wallets** — that may become
the only acceptable wallet type for new CLOB accounts (Reading B in
`CLOB_V2_FOLLOWUPS.md` §"2026-05-06 PM addendum"). Under Reading B, OLAS
services deployed after the rollout cannot trade on the CLOB unless they
adopt the deposit-wallet shape. We need an `IMultisig`-shaped contract that
produces a deposit-wallet-backed multisig and slots into the same
`ServiceRegistryL2.deploy()` path.

## Reference baseline — what we already have

| File | Role | Notes |
|------|------|-------|
| `contracts/multisigs/PolySafeCreatorWithRecoveryModule.sol` | Current Polymarket creator | One owner only; uses `PolySafeProxyFactory.createProxy` (Polymarket's gas-paid Safe factory) + `enableModule(RecoveryModule)`. Both txs use EIP-712 signatures presigned by the agent instance EOA. |
| `contracts/multisigs/SafeMultisigWithRecoveryModule.sol` | Generic Safe creator with module | Used on chains without the Polymarket factory. Calls standard `SafeProxyFactory.createProxyWithNonce` and passes the `enableModule(recoveryModule)` payload as the Safe's `setup` initializer (atomic — no second tx needed). |
| `contracts/multisigs/RecoveryModule.sol` | Module that lets service owner regain sole ownership of the Safe | Used after `unstake → terminate → unbond`. Independent of the multisig type. |
| `contracts/8004/IdentityRegistryBridger.sol` | Bridges OLAS service registrations to ERC-8004 identity registry | Records the **multisig address** as the agent wallet via `setAgentWallet(agentId, multisig, ...)`. Whatever wallet the registry sees as `service.multisig` is what becomes the ERC-8004 agent wallet. |
| `contracts/interfaces/IMultisig.sol` | The `create(owners, threshold, data) -> address` interface | Whitelisted via `ServiceRegistryL2.changeMultisigPermission`. |

## The new model — deposit wallet stack

Sourced from `CLOB_V2_FOLLOWUPS.md` sweeps 2026-05-04, 2026-05-05, 2026-05-06
(merged TS builder-relayer 0.0.9 source + official integration docs).

| Field | Polygon (137) | Notes |
|---|---|---|
| `DepositWalletFactory` | `0x00000000000Fb5C9ADea0298D729A0CB3823Cc07` | Same address on Amoy. Vanity-deterministic deploy via Singleton-Factory + mined salt — designed for cross-chain address parity. |
| `DepositWalletImplementation` | `0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB` | Different on Amoy (`0x50a88fE9…D7Fbd`). |
| `SafeFactory` (in deposit-wallet config) | `0xaacFeEa03eb1561C4e67d661e40682Bd20E3541b` | **Same as our existing `POLYSAFE_PROXY_FACTORY`.** Polymarket's deposit-wallet stack uses the same Safe substrate we already deploy through. |
| `SafeMultisend` | `0xA238CBeb142c10Ef7Ad8442C6D1f9E89e07e7761` | Standard Safe MultiSend. |

Architectural facts surfaced by official docs (`docs.polymarket.com/trading/deposit-wallet-migration`):

1. **`DepositWalletFactory.deploy()` is `onlyOperator`-gated.** Polymarket's
   hosted relayer is the only caller. No user signature required for
   deployment. Permissionless deploy is impossible.
2. **Order signing is `SignatureTypeV2.POLY_1271 = 3` with ERC-7739 wrapping.**
   ERC-7739 ("Readable Typed Signatures for Smart Accounts") nests the order's
   typed-data hash inside an outer envelope to prevent signature replay across
   smart accounts. Plain ECDSA-on-typed-data is insufficient.
3. **Order's `maker` and `signer` must both equal the deposit wallet address.**
   The deposit wallet validates the signature via its `isValidSignature` —
   which can in turn delegate to its `owner` (a Safe in our case) via a
   second ERC-1271 layer.
4. **Approvals are issued from the deposit wallet via relayer `WALLET` batch.**
   Standard ERC-20/ERC-1155 `approve` / `setApprovalForAll` calldata, but
   submitted to the relayer's `WALLET` tx type rather than executed via Safe
   `execTransaction`.
5. **Owner / session-signer model.** The deposit wallet has *one* owner and
   *N* session signers (`authorizeSessionSigner(addr, validUntil)`,
   `revokeSessionSigner(addr)`, `revokeSessionSignerEmergency(addr)`).
   Owner signs wallet-batch payloads; owner *or* session signer signs CLOB
   orders.

### Unverified-from-this-repo facts (need on-chain probe before coding)

- **Owner-set-at-deploy semantics.** Does the relayer-deployed deposit wallet
  take its owner address as a deploy-time argument, or is it set in a
  separate post-deploy `initializeOwner` call? The TS builder-relayer 0.0.9
  source (`src/config/index.ts`) hardcodes the factory + impl addresses but
  the wallet-deploy ABI surface is what we need. **Action:** read
  `0x00000000000Fb5C9ADea0298D729A0CB3823Cc07` ABI on Polygonscan and probe
  the deploy method's argument shape.
- **Owner-must-be-EOA-or-contract gate.** If the factory validates that
  `owner.code.length > 0` at deploy time, the Safe must be deployed *before*
  the deposit wallet. If it accepts any address, we can use CREATE2 address
  prediction and deploy in either order.
- **CREATE2 salt scheme.** Need the deterministic-address formula to
  pre-compute the deposit wallet from a given owner address. Likely
  `keccak256(owner)` or `keccak256(owner || nonce)` — to be confirmed from
  the merged TS source `deriveDepositWallet`.
- **POLY_1271 envelope shape.** ERC-7739 has two variants ("nested" vs
  "guardian"). Need to confirm which one Polymarket uses and whether the
  envelope includes the deposit wallet address explicitly (it almost
  certainly does — that's the whole point of cross-account replay defense).

## Architectural tension

The current `PolySafeCreatorWithRecoveryModule` model relies on three
properties that the deposit-wallet model breaks:

| Property | PolySafe | Deposit wallet |
|---|---|---|
| **Permissionless self-deploy** | Yes — anyone can call `PolySafeProxyFactory.createProxy` with a valid owner-signed digest. | No — `DepositWalletFactory.deploy` is `onlyOperator`. Only Polymarket's relayer can deploy. |
| **Module-extensible Safe shape** | Yes — `enableModule(RecoveryModule)` works because PolySafe is a regular Gnosis Safe v1.3.0. | Unknown / unlikely — deposit wallet has its own session-signer model, no documented Safe-module ABI. |
| **`setApprovalForAll` / approvals via the wallet's own `execTransaction`** | Yes — Safe `execTransaction` is the canonical path. | No — approvals must go through the relayer's `WALLET` batch. The deposit wallet may not even expose a generic `execTransaction`. |

## Three design options

### Design A — "Deposit wallet *is* the OLAS multisig"

Replace the PolySafe with a deposit wallet entirely. The deposit wallet
becomes the address recorded in `service.multisig`.

| Pro | Con |
|---|---|
| Simplest from a "wallet count" perspective. | **Probably impossible.** The deposit wallet is `onlyOperator`-deployed, so our `create()` cannot deploy it on-chain at all. We'd have to off-chain-deploy via the relayer first, then call our `create()` which would only *verify* the wallet exists and owners match. |
| | RecoveryModule almost certainly doesn't compose with the deposit wallet's session-signer model (unverified — but the deposit wallet's whole point is a constrained signing surface, not arbitrary modules). |
| | OLAS service governance (multisig threshold, agent-instance ownership semantics) doesn't match the deposit wallet's owner+session-signer shape. |
| | Reading B confirmation status: also unverified. We'd be locking the architecture to a maybe-required model. |

**Verdict:** rejected. Too many unverified incompatibilities, and the
relayer dependency means our `create()` becomes a verification-only
function — any failure mode (relayer offline, deposit wallet not yet
deployed) bricks `ServiceRegistryL2.deploy()` for that service.

### Design B — "Two-tier — Safe wraps a deposit wallet"

The OLAS service multisig is a **regular Gnosis Safe** with `RecoveryModule`
pre-enabled (same as `SafeMultisigWithRecoveryModule`). The Safe **owns**
a deposit wallet that is created out-of-band by the relayer with the
Safe's address (CREATE2-precomputed) as the deposit wallet's `owner`.

The new creator contract:
- Pre-computes the Safe's CREATE2 address from `(SafeFactory, singleton, initializer, saltNonce)`.
- Either:
  - **B1 — Safe-first:** deploys the Safe immediately. Off-chain client then
    calls the relayer to deploy a deposit wallet with this Safe as owner.
    The deposit-wallet address is stored off-chain (e.g., in the trader
    config or via an `event`-emitted record).
  - **B2 — Deposit-wallet-first:** off-chain client first calls the relayer
    with the precomputed Safe address as the deposit wallet's owner. Relayer
    deploys the deposit wallet (whose owner is an address with no code yet —
    works iff factory doesn't gate on `owner.code.length`). Then our
    `create()` deploys the Safe at the precomputed address. Atomic by
    address determinism.

| Pro | Con |
|---|---|
| Clean separation of concerns: OLAS service governance lives in the Safe; CLOB trading lives in the deposit wallet. | Two wallets per service. More moving parts. |
| Reuses `SafeMultisigWithRecoveryModule` patterns almost verbatim — minimal new on-chain code. | Approvals path changes (relayer `WALLET` batch) — must be wired into the trader codebase, not the on-chain creator. |
| RecoveryModule keeps working — Safe is unchanged. | ERC-7739 + POLY_1271 signing must be implemented in the trader (off-chain). |
| ERC-8004 compatibility intact — `IdentityRegistryBridger.setAgentWallet(agentId, safe)` keeps the Safe as the agent wallet. The deposit wallet is invisible to the bridger. | Need to settle which order (B1 vs B2) is feasible — depends on the unverified factory gate. |
| Permissionless Safe deploy stays our control plane. Relayer is only on the deposit-wallet side. | If Reading A holds (no migration needed), this work is wasted. |

**Verdict:** strong candidate. Cleanest fit with the existing architecture
and the smallest contract footprint.

#### Design B in depth — how "wrap" works

"Wrap" is shorthand. Concretely: the Safe is the **validator-of-record**
for the deposit wallet's owner-authority decisions. There's no proxying,
no delegate-call, no Safe-module relationship between the two. They are
two independently-deployed contracts. The deposit wallet's `owner`
storage slot holds the Safe's address; the deposit wallet's
`isValidSignature` (and any other owner-gated entry point) defers to
the Safe via a second ERC-1271 call. This is the same pattern used by
"smart-account-owns-smart-account" stacks (e.g., a Safe owning an
ERC-4337 account).

##### Topology

```
                   ┌─────────────────────────────────────────────────┐
                   │ Polymarket CLOB API                              │
                   │ (off-chain — validates orders via on-chain      │
                   │  ERC-1271 calls)                                 │
                   └────────────┬────────────────────────────────────┘
                                │ isValidSignature(orderHash7739, sig)
                                ▼
                   ┌─────────────────────────────────────────────────┐
                   │ DepositWallet  (CREATE2-deployed by relayer)    │
                   │  - owner = ServiceSafe                           │
                   │  - sessionSigners[]                              │
                   │  - holds pUSD / USDC.e / CTF positions           │
                   │  - approvals issued via relayer WALLET batch     │
                   └────────────┬────────────────────────────────────┘
                                │ Owner-path: isValidSignature(innerHash, ownerSig)
                                ▼
                   ┌─────────────────────────────────────────────────┐
                   │ ServiceSafe  (Gnosis Safe v1.3.0)               │
                   │  - owner = agent instance (single-agent)         │
                   │  - modules = [RecoveryModule]                    │
                   │  - this is the address recorded in:              │
                   │      · ServiceRegistryL2.service.multisig        │
                   │      · IdentityRegistryBridger.mapMultisigAgentIds│
                   └────────────┬────────────────────────────────────┘
                                │ standard Safe ECDSA
                                ▼
                   agent instance (EOA)
```

##### Ownership chain — what each layer enforces

| Layer | Owner / authoriser | What it can do |
|---|---|---|
| Agent instance EOA | self (private key) | Sole signer for the Safe (single-agent OLAS service); each Safe action is one ECDSA. |
| ServiceSafe | the agent instance plus `RecoveryModule` | Sign anything as `Safe.isValidSignature` validator. Holds OLAS service multisig role. |
| DepositWallet | ServiceSafe (`owner` slot) + N session signers (`authorize…`) | Trade on the CLOB. Hold trading collateral. Submit relayer `WALLET` batches. |
| RecoveryModule | Service owner (Master Safe) | Reset ServiceSafe's owner set to `[Master Safe]` after `unstake → terminate → unbond`. |

The key invariant: **only the ServiceSafe (or an active session signer)
can authorise deposit-wallet operations**. There is no path from agent
instance EOA → deposit wallet that bypasses the Safe — even though that
EOA holds the hot key — unless the agent instance has been explicitly
authorised as a session signer.

##### Signature flow — order signing (hot path)

Most CLOB orders traverse this flow per trade:

```
Trader builds CLOB v2 order with maker = signer = depositWallet.
Trader computes erc7739Hash = ERC7739_envelope(domain=depositWallet, orderHash).
                       │
                       ▼
              How does the trader sign?

  ┌────────────────────────────────┬────────────────────────────────┐
  │ Path A — Safe-as-signer         │ Path B — session-signer-as-signer│
  ├────────────────────────────────┼────────────────────────────────┤
  │ agent-instance EOA signs the    │ session signer's EOA signs the   │
  │ Safe's SafeTx hash that wraps   │ ERC-7739 hash directly.          │
  │ erc7739Hash, packs into safeSig │                                  │
  │ (single-agent: one ECDSA)        │                                  │
  │                                 │                                  │
  │ outerSig = abi.encode(safeAddr, │ outerSig = abi.encode(            │
  │            safeSig)             │   sessionSignerAddr, ecdsaSig)   │
  └────────────────────────────────┴────────────────────────────────┘
                       │
                       ▼
Trader submits to CLOB API: { sigType: 3, signature: outerSig, ... }
                       │
                       ▼
CLOB calls depositWallet.isValidSignature(erc7739Hash, outerSig)
                       │
                       ▼
DepositWallet decodes outerSig, picks branch:
  - If first 20 bytes == owner: forward to Safe.isValidSignature
  - If first 20 bytes ∈ active sessionSigners: ECDSA-recover and check match
                       │
                       ▼
Returns ERC1271_MAGICVALUE (0x1626ba7e) on success
```

**Path A is heavier (Safe-tx ceremony per order) but always available.**
Path B requires a one-time session-signer authorisation but lets the
trader sign each subsequent order with a single ECDSA-on-EOA — which is
exactly the same ergonomics as today's PolySafe + sigType=2 path. See
"Session-signer escape hatch" below.

The exact `outerSig` decoding scheme (20 bytes prefix vs RLP-encoded vs
length-prefixed) is **unverified** — needs reading the deposit-wallet
implementation at `0x58CA52…D1eB`. The shape above is a plausible
guess based on standard ERC-1271-with-multiple-validators patterns.

##### Signature flow — approvals batch (cold path, runs once per service)

```
ServiceSafe needs to authorise the relayer to submit approvals on behalf
of the deposit wallet (e.g., pUSD.approve(CTF_EXCHANGE), CTF.setApprovalForAll(CTF_EXCHANGE), …).

  1. Off-chain trader builds approvals calldata array.
  2. Trader builds the relayer WALLET-batch typed-data envelope:
       { wallet: depositWallet, nonce: …, calls: [(target, value, data), …] }
  3. Safe-tx ceremony: the agent-instance EOA (sole Safe owner under
     OLAS's single-agent model) signs the SafeTx that wraps the WALLET-batch
     hash. Trader assembles safeSig.
  4. Trader submits to relayer:
       relayer.submitWalletBatch(depositWallet, calls, safeSig, nonce, …)
  5. Relayer calls depositWallet.executeBatch(calls, ownerSig=safeSig).
  6. depositWallet.isValidSignature internally validates safeSig against
     Safe.isValidSignature → executes the batch via depositWallet's own
     execute path.

The Safe never directly calls the deposit wallet on-chain. The relayer
is the on-chain caller; the Safe is the signature provider.
```

The key cost-saving move: relayer pays the gas. The Safe never has to
hold MATIC to broadcast deposit-wallet ops. (PolySafe today has the same
property via `PolySafeProxyFactory`'s gas-paid model.)

##### Why the creator can't trigger the deploy itself (and the conditions under which it could)

A natural reading of "permissionless creator does the deploy" is: have
`creator.create()` call `DepositWalletFactory.deploy(owner=safe)` directly,
inside the same transaction that deploys the Safe. That would collapse
all the orchestration into one on-chain call. It doesn't work today —
but the reasons matter, because two of the three blockers are
**probe-able / askable**, not fundamental.

Two distinct concepts that look similar but aren't:

- **Pre-calculating the deposit-wallet address** is pure CREATE2 math.
  Given `(factory, salt(owner=safe), implementation-bytecode-hash)`, the
  resulting address is deterministic and computable by anyone — no deploy
  needed, no privileges required. This is what enables B1/B2 ordering
  flexibility.
- **Triggering the deploy** is gated on `onlyOperator`. The
  `msg.sender`-level access check is what makes the deploy non-self-serviceable.
  Pre-calculation tells us the address; only the operator can mint the
  bytecode at it.

For the creator to internalise the deploy call, one of these has to be
true:

1. **~~The creator contract is itself whitelisted as an operator~~ —
   ruled out.** Whitelisting a partner contract as a `DepositWalletFactory`
   operator dilutes the structural justification for `onlyOperator`
   (centralised wallet provisioning to mitigate ghost fills). Treat as
   "no" by default — we don't pursue this and don't expect Polymarket to
   grant it. Documented for completeness so future readers understand
   why the option is closed.
2. **The factory exposes a meta-tx variant** where any caller can submit
   on behalf of an operator carrying the operator's pre-signed
   authorisation (e.g.,
   `deployWithOperatorSig(owner, deadline, operatorSig)`). Then `create()`
   takes the operator's signature inside `data` and triggers the deploy
   itself; the off-chain client fetches a fresh operator-sig per-deploy
   from Polymarket's API. Closer to the on-chain-self-serviceable model.
   **Unverified — needs the on-chain ABI probe** (added explicitly to
   the pre-coding checklist below). **This is the only collapse-1 lever
   still on the table.**
3. **An on-chain "request → deploy" event pattern** where the creator
   emits a request and Polymarket's indexer picks it up off-chain and
   deploys later. Doable but async — no atomic completion guarantee,
   no revert path if the relayer doesn't follow up, racy with
   `serviceManager.deploy`'s state transitions. Almost certainly not what
   the docs describe (no such pattern is documented), but flagged for
   completeness.

If neither (2) nor (3) hold, deploys can only originate from Polymarket's
operator EOA off-chain. Solidity contracts can't make HTTP calls and
have no signing keys, so the orchestration must live in the off-chain
client — and pre-calculation is the mechanism that lets the off-chain
client and the creator agree on the deposit wallet's address despite
the temporal split.

**Structural implication of (1) being closed:** under Reading B,
Polymarket's relayer/API is a *permanent hard dependency* for new-user
onboarding regardless of which fallback (2 or default) wins. Path 2
makes the API call lighter (one signature fetch vs one full tx
submission) but doesn't remove the dependency. Pearl's "self-custody
from minute zero, no third-party in the deploy path" property — which
the existing PolySafe path provides via the permissionless
`PolySafeProxyFactory` — is not recoverable inside the deposit-wallet
model. This is the same architectural concern surfaced in the
`CLOB_V2_FOLLOWUPS.md` 2026-05-06 PM addendum.

**Decision tree:**

```
Probe DepositWalletFactory ABI (Polygonscan).

├── Operator-sig meta-tx variant exists? (Path 2)
│     ├── Yes → Use it. creator.create() takes operatorSig in `data`,
│     │         triggers deploy in-tx. Single-tx flow.
│     └── No → Continue.
└── Default → Off-chain orchestration. creator.create() only verifies
              the deposit wallet exists. Phase 2 runs in parallel with
              Phase 1 via Polymarket's relayer.
```

The default path is what the rest of this section assumes; it requires
no Polymarket cooperation beyond the relayer being online for the
deposit-wallet deploy. If Path 2 turns out to be available, the contract
surface simplifies — `data` grows by an operator-sig, the deposit wallet
is deployed in the same tx as the Safe, and the off-chain client's
relayer roundtrip becomes a sig-fetch instead of a deploy-await.

##### Deploy ordering — B1 vs B2 in detail

Both orderings rely on CREATE2 address determinism. The Safe's CREATE2
address is fully determined by `(SafeProxyFactory, safe-singleton, initializer, saltNonce)`.
The deposit wallet's CREATE2 address is fully determined by
`(DepositWalletFactory, salt(owner), implementation-bytecode-hash)`.
Both can be precomputed off-chain.

| Step | B1 — Safe-first | B2 — Deposit-wallet-first |
|---|---|---|
| 1 | Off-chain: predict `safe = predictSafeAddress(owners, salt, …)`. | Off-chain: predict `safe`, then `depositWallet = predictDepositWallet(safe)`. |
| 2 | `serviceManager.deploy(serviceId, creator, data)` → creator deploys the Safe. | Off-chain client calls `relayer.deployDepositWallet(owner=safe)`. Deposit wallet now exists, owner field holds an address with no code yet (the would-be Safe). |
| 3 | Off-chain client calls `relayer.deployDepositWallet(owner=safe)`. | `serviceManager.deploy(serviceId, creator, data)` → creator deploys the Safe at the predicted address. Safe now controls the pre-existing deposit wallet. |
| 4 | Trader records `(safe, depositWallet)` pair off-chain (or via creator-emitted event in Design C). | Same — though under Design C the on-chain link is recorded in `mapMultisigDepositWallets` during step 3. |
| **`serviceManager.deploy` failure** | Safe never deploys. Deposit wallet never requested. Service stays in `FinishedRegistration`. Clean retry. | Same. |
| **Relayer failure after Safe deploys (B1) / before Safe deploys (B2)** | Service has a Safe but no deposit wallet. Service is functional (can be terminated, recovered) but cannot trade. Need a separate "attach deposit wallet later" path or accept that the service is non-trading until the relayer recovers. | Deposit wallet exists, owned by a code-less address. Once `serviceManager.deploy` runs, the Safe materialises and assumes ownership. Atomic from the user's POV — the worst case is delay, not loss. |
| **Factory gates on `owner.code.length > 0`** | Works (Safe is real before deposit wallet deploys). | **Breaks.** Factory rejects the deploy because the Safe address has no code yet. Forces B1. |
| **Atomicity** | Two-step from user's POV (deploy service, then attach deposit wallet). | One-step from user's POV (off-chain client orchestrates the relayer call before submitting `serviceManager.deploy`, but failure-recovery is automatic via CREATE2). |
| **Operational complexity** | Higher — deploy-then-attach is a two-tx UX. | Lower — relayer + on-chain deploy can be racing concurrently as long as the on-chain deploy is the second to complete. |

**Recommendation: use B2 if the factory permits (`owner.code.length` is
not gated). Fall back to B1 if it doesn't.** The factory's behaviour
on a code-less owner is the load-bearing pre-coding probe — covered
in §"Pre-coding verification checklist".

##### Recovery flow under wrapping

The existing recovery flow (`scripts/recover_funds_lost_agent_eoa.py`)
works for the Safe layer unchanged. The new question: how does the
recovery flow reach **funds held in the deposit wallet**?

```
Step                                  | Effect on Safe        | Effect on DepositWallet
──────────────────────────────────────┼───────────────────────┼─────────────────────────
1. unstake(serviceId)                 | Returns service NFT   | No effect.
2. terminate(serviceId)                | Service → Terminated  | No effect.
3. unbond(serviceId)                   | Service → PreReg      | No effect.
4. recoveryModule.recoverAccess(svc)   | Safe owners reset to  | No effect — owner of
                                       | [Master Safe]         | DepositWallet is still
                                       |                       | (the same) ServiceSafe.
5. Master Safe (now sole Safe owner)   |                       | DepositWallet operations
   signs deposit-wallet ops as normal  |                       | proceed normally — the
                                       |                       | "owner who can authorise"
                                       |                       | is now the Master Safe via
                                       |                       | the ServiceSafe.
```

Crucial property: `RecoveryModule` does **not** change the ServiceSafe's
*address*. It changes its *owner set*. Therefore the deposit wallet's
`owner` slot (which points to the ServiceSafe address) remains valid
post-recovery. The Master Safe steps in to sign on behalf of the
ServiceSafe via standard Safe-tx flow.

What this requires from the deposit wallet's design (load-bearing,
**unverified**):

- **Owner-callable withdraw / sweep path.** The deposit wallet must
  expose some interface like `executeBatch(calls)` or `withdraw(token, amount, to)`
  that the owner can authorise via a Safe-validated EIP-1271 signature.
  If the deposit wallet only exposes operations through Polymarket's
  hosted relayer with no owner-direct path, recovery cannot reach the
  funds — they're stranded. Polymarket's design probably exposes such
  a path (otherwise the wallet would be custodial, contradicting their
  "self-custody" framing in the docs), but this needs explicit
  on-chain confirmation.
- **No `onlyOperator` gate on the withdraw path.** The relayer-deploy gate
  is fine because we orchestrate around it. A withdraw gate would be
  fatal — it would mean the only way to retrieve funds is through the
  relayer's continued cooperation.

##### Session-signer escape hatch — "agent instance as session signer"

The most important ergonomics-saving move under Design B. **If
Polymarket's session-signer model accepts a plain ECDSA EOA as a
session signer, then OLAS services can authorise the agent instance
EOA as a session signer on the deposit wallet.** Concretely:

```
1. Once at deploy time (or shortly after), Safe-tx ceremony:
   ServiceSafe signs authorizeSessionSigner(agentInstance, validUntil = +30 days)
   typed-data → relayer submits.

2. From then until validUntil, the agent instance EOA can sign CLOB
   orders directly with its private key:
   - Trader computes erc7739Hash for the order.
   - Agent instance signs erc7739Hash with its EOA key.
   - outerSig = abi.encode(agentInstance, ecdsaSig).
   - Trader submits sigType=3 + outerSig to CLOB.
   - CLOB → depositWallet.isValidSignature → recognises agentInstance
     as an active session signer → ECDSA-recovers and matches → returns
     MAGICVALUE.

3. Per-order cost: identical to today's PolySafe + sigType=2 — one EOA
   signature, no Safe ceremony. The Safe is touched only at:
   - service deploy (one-time)
   - session-signer rotation (every validUntil — e.g., monthly)
   - approvals batch (one-time, plus when new exchanges/adapters are added)
   - withdrawals (rare, owner-driven)
   - recovery (catastrophic-only)
```

This is the architectural reading of the docs' "Owner or session signer
signs two different kinds of payloads (wallet batches and CLOB orders)."
phrase. Wallet batches go through the owner (the Safe). Orders can go
through either the owner or a session signer.

**Why this matters for the migration scoping:**

- The trader's hot-path order-signing logic stays nearly identical to
  today — it's still "agent instance EOA signs an EIP-712 hash" — but
  the hash is the ERC-7739-wrapped CLOB v2 order rather than the plain
  CLOB v1 / PolySafe-wrapped sigType=2 hash.
- The only new on-chain ceremony is the periodic session-signer
  authorisation — which is just another Safe-tx, structurally identical
  to today's `enableModule(RecoveryModule)` pattern.
- Reading-B migration shrinks from "rewrite signing path entirely" to
  "swap the inner hash and add a periodic session-rotation cron".

If session signers DON'T accept plain EOAs (e.g., they require a separate
1271-compatible signer contract per session), the migration is
substantially heavier and we're back to Path A (per-order Safe-tx
ceremony). **Probing the session-signer signature scheme is the second-most
load-bearing pre-coding question.**

##### What's assumed vs confirmed at each step

| Assumption | Status | Source / probe needed |
|---|---|---|
| `DepositWalletFactory.deploy()` is `onlyOperator`-gated. | **Confirmed.** | Official docs `docs.polymarket.com/trading/deposit-wallet-migration`. |
| Deposit wallet has an `owner` storage slot settable at deploy. | **High confidence.** | Merged TS builder-relayer 0.0.9 `deployDepositWallet` signature implies it; needs ABI confirmation. |
| Deposit wallet's `isValidSignature` delegates to its owner via a second ERC-1271 call. | **Assumed.** | Inferred from POLY_1271 = sigType=3 + "owner or session signer signs" docs phrase. Probe: read the deposit wallet's `isValidSignature` source via Polygonscan. |
| Outer-sig encoding is `(signerAddress, signature)`-prefixed. | **Speculative on encoding; confirmed as outer envelope.** | `clob-client-v2@1.0.0` source (`exchangeOrderBuilderV2.js`) does NOT wrap — it signs the plain EIP-712 order hash. The wrap therefore lives outside the order builder, added in 1.0.3 PR #35. Exact byte layout still TBD from 1.0.3 source or on-chain `isValidSignature` reverse-engineering. |
| Order's EIP-712 domain is the CTFExchange v2 contract (not the deposit wallet). | **Confirmed from local source.** | `dist/order-utils/model/ctfExchangeV2TypedData.js`: `domain = { name: "Polymarket CTF Exchange", version: "2", chainId, verifyingContract: <CTFExchange v2 address> }`. The deposit wallet is `maker` and `signer` in the order body, not the domain. |
| Order struct shape `{salt, maker, signer, tokenId, makerAmount, takerAmount, side, signatureType, timestamp, metadata, builder}`. | **Confirmed from local source.** | `CTF_EXCHANGE_V2_ORDER_STRUCT` in `ctfExchangeV2TypedData.js`. For deposit-wallet orders, `maker = signer = depositWallet` and `signatureType = 3`. |
| Session signers can be plain EOAs (not 1271-contracts). | **Unverified, load-bearing.** | Probe: read the deposit wallet's `authorizeSessionSigner` and the validation logic in `isValidSignature`. |
| Deposit wallet exposes an owner-callable withdraw / sweep path. | **Unverified, load-bearing for recovery.** | Probe: enumerate the deposit wallet's external functions and look for `execute`, `executeBatch`, `withdraw`, `sweep`, or similar. |
| Factory does not gate on `owner.code.length > 0`. | **Unverified, determines B1 vs B2.** | Probe: deploy a deposit wallet with a precomputed-but-not-yet-deployed CREATE2 address as owner on Amoy testnet; observe success or revert. |
| Salt scheme is `keccak256(owner)`. | **High confidence by analogy with PolySafe.** | Probe: `deriveDepositWallet` in merged TS source has the formula. |
| ERC-7739 envelope format used. | **Confirmed.** | Official docs explicitly mention ERC-7739. Variant (nested vs guardian) probe: read the deposit wallet's `isValidSignature` implementation. |

##### Net — is "wrap" the right primitive?

Yes, with three caveats:

1. The wrap is **single-direction** — Safe authorises deposit-wallet
   operations; deposit wallet does not authorise Safe operations. Asymmetric
   delegation.
2. The wrap is **off-chain-orchestrated for setup** — the deploy
   ordering (B1 or B2) requires off-chain coordination because of the
   `onlyOperator` factory. Once both wallets exist, the wrap is on-chain
   and self-enforcing.
3. The wrap is **session-signer-augmentable** — the trader can short-circuit
   the per-order Safe ceremony by authorising session signers. This is
   the ergonomics win that makes Reading-B migration tractable.

If any of the three load-bearing unknowns above (delegation pattern,
session-signer EOA support, owner-callable withdraw) come back wrong on
the on-chain probe, the wrapping shape needs revisiting — and Designs A
and C inherit the same fragility because they sit atop the same primitives.

### Design C — "Hybrid creator + on-chain link record"

Same as Design B, but the creator contract additionally stores the
deposit-wallet address on-chain (in a per-service mapping) and emits an
event `DepositWalletLinked(serviceId, multisig, depositWallet)` so the
trader can discover the deposit wallet without off-chain config.

The creator's `create()`:
1. Decode `data` as `(safeInitializer, depositWalletAddress, depositWalletProof)`.
2. Deploy the Safe via `SafeProxyFactory.createProxyWithNonce` with
   `enableModule(RecoveryModule)` baked into the initializer (atomic).
3. Verify the deposit wallet was *already* deployed by the relayer
   (`depositWalletAddress.code.length > 0`).
4. Verify the deposit wallet's CREATE2 derivation matches the deployed
   Safe's address (i.e., the deposit wallet's owner is this Safe). The
   verification reads the deposit wallet's `owner()` directly.
5. Store `mapServiceDepositWallets[multisig] = depositWalletAddress`.
6. Emit the link event.

| Pro | Con |
|---|---|
| Discovery on-chain: no need for off-chain config to find a service's deposit wallet. | More state on-chain. Costs ~22k gas per `create()` for the SSTORE. |
| Verifiable link — third parties can confirm a Safe-deposit-wallet pairing without trusting off-chain claims. | If we ever support multiple deposit wallets per service (unlikely but possible), the mapping needs revising. |
| Slightly safer Reading-B migration path: the link can be queried by `IdentityRegistryBridger` or a future on-chain trader, not just by our trader code. | |
| Failure modes are atomic — if the deposit wallet isn't deployed yet, `create()` reverts and `ServiceRegistryL2.deploy` rolls back the service state transition. | Coupling between Safe deploy and deposit-wallet existence — relayer becoming a hard dependency is just as true as in B2. |

**Verdict:** preferred. Strict superset of B with a small storage/event
addition. Recommended.

## Recommended design — Design C in detail

### Contract surface

```solidity
contract DepositWalletSafeCreatorWithRecoveryModule {
    // Selector of the Safe setup function — identical to SafeMultisigWithRecoveryModule
    bytes4 public constant SAFE_SETUP_SELECTOR = 0xb63e800d;
    // enableModule selector
    bytes4 public constant ENABLE_MODULE_SELECTOR = 0x24292962;

    address public immutable safe;                  // Safe singleton (v1.3.0)
    address public immutable safeProxyFactory;      // 0xaacFeEa…541b on Polygon
    address public immutable recoveryModule;        // Olas RecoveryModule
    address public immutable depositWalletFactory;  // 0x000000…3Cc07
    bytes32 public immutable depositWalletBytecodeHash; // for CREATE2 sanity-check

    mapping(address => address) public mapMultisigDepositWallets;

    function create(address[] memory owners, uint256 threshold, bytes memory data)
        external returns (address multisig);

    // Helpers
    function predictSafeAddress(address[] memory owners, uint256 threshold, address fallbackHandler, uint256 saltNonce)
        external view returns (address);

    function predictDepositWalletAddress(address safeOwner)
        external view returns (address);
}
```

### `data` payload shape

```solidity
data = abi.encode(
    address fallbackHandler,        // optional Safe fallback handler (or 0)
    uint256 saltNonce,              // CREATE2 salt for the Safe
    address depositWalletAddress    // pre-computed via predictDepositWalletAddress
);
```

The off-chain client computes the Safe's predicted address, calls the
Polymarket relayer with that as the owner, gets back the deposit wallet's
deployed address (deterministic, so already known — relayer call just
materialises the bytecode), then submits the `ServiceManager.deploy()`
call with `data` carrying the saltNonce + deposit wallet address.

### Deployment flow — phases run in parallel where possible

The Safe's CREATE2 address depends only on `(agentInstances, threshold,
fallbackHandler, saltNonce, recoveryModule, safeSingleton, SafeProxyFactory)` —
none of which are produced by the OLAS service registration. Pearl client
generates the agent-instance EOA locally and picks `saltNonce`
deterministically (any locally-unique value: UUID, counter, or
`keccak256(agentInstance || nonce)`). That means **Phase 2 (deposit-wallet
pre-deploy via Polymarket's relayer) does not depend on Phase 1 (OLAS
service registration) and can run in parallel with it.** Phase 3 is the
synchronisation point.

```
T = 0
  ├─ Pearl client generates agent-instance EOA locally.
  ├─ Picks saltNonce, threshold, fallbackHandler.
  └─ Computes predictedSafe + predictedDw via CREATE2 (pure math, no tx).

T = 0+   FIRE BOTH PHASES IN PARALLEL:

  ├─ PHASE 1 — OLAS service registration (3 user txs)
  │     tx 1: ServiceManager.create(serviceOwner, token, configHash,
  │              agentIds, agentParams, threshold)         → PreRegistration
  │     tx 2: ServiceManager.activateRegistration{value:dep}(serviceId)
  │                                                       → ActiveRegistration
  │     tx 3: ServiceManager.registerAgents{value:bond}(serviceId,
  │              [agentInstance], agentIds)               → FinishedRegistration
  │
  └─ PHASE 2 — deposit-wallet pre-deploy (1 HTTP call)
        HTTP POST → Polymarket relayer:
            { owner: predictedSafe, ... }
        Relayer's operator EOA submits
            DepositWalletFactory.deploy(owner=predictedSafe).
        DepositWalletProxy materialises at predictedDw, owner slot
        holds predictedSafe (an address with no code yet — works iff
        the factory doesn't gate on owner.code.length, per the
        verification checklist probe).

T = max(Phase1, Phase2)

  PHASE 3 — service deploy (1 user tx, the synchronisation point)
        ServiceManager.deploy(serviceId, depositWalletSafeCreator,
            data = abi.encode(fallbackHandler, saltNonce, predictedDw))

        Inside depositWalletSafeCreator.create():
          1. abi.decode(data) → (fallbackHandler, saltNonce, depositWalletAddr).
          2. Build Safe initializer: SAFE_SETUP_SELECTOR(
                 owners=agentInstances, threshold, recoveryModule,
                 enableModule-payload, fallbackHandler, 0, 0, 0).
          3. newSafe = SafeProxyFactory.createProxyWithNonce(
                 safeSingleton, initializer, saltNonce).
                 // (CREATE2 → newSafe == predictedSafe by construction)
          4. require(depositWalletAddr.code.length > 0).
                 // pre-deployed by relayer in Phase 2
          5. require(depositWalletAddr.codehash == depositWalletBytecodeHash).
          6. require(IDepositWallet(depositWalletAddr).owner() == newSafe).
          7. mapMultisigDepositWallets[newSafe] = depositWalletAddr.
          8. emit DepositWalletLinked(newSafe, depositWalletAddr).
          9. return newSafe.

        ServiceRegistryL2 stores service.multisig = newSafe.
        State → Deployed. emit CreateMultisigWithAgents.
        IdentityRegistryBridger.register(serviceId)  // ERC-8004 agent
                                                    // wallet = newSafe.

PHASE 4 — post-deploy bootstrap (off-chain)

  Trader (agent-instance EOA signing as the DW owner directly — no Safe-tx
  needed under the corrected design, since the agent EOA owns the DW):
    relayer.executeWalletBatch on the deposit wallet:
      [authorizeSessionSigner(sessionEOA, +30days),
       pUSD.approve(CTF_EXCHANGE),
       CTF.setApprovalForAll(CTF_EXCHANGE),
       ...]                                          // one batched call

  Trader: Safe → ERC-20 transfer → depositWallet (funding).

  Hot-path order signing from now on: agent-instance EOA signs
  ERC-7739-wrapped order hash directly. sigType=3, outerSig =
  (sessionSigner, ecdsaSig). No Safe touch per order.
```

### Front-running consideration (carried over from PolySafe)

After Phase 2 lands, the deposit wallet's `owner` slot exposes
`predictedSafe` on-chain. From that moment, anyone can attempt to deploy
the Safe at that address by calling `SafeProxyFactory.createProxyWithNonce`
with our exact initializer + saltNonce. They'd need to brute-force
`(agentInstances, threshold, fallbackHandler, saltNonce)` from the
resulting address — computationally infeasible since CREATE2 is
non-invertible and the agent-instance EOA is locally generated and
unannounced. Even if they succeeded, the resulting Safe has *our* owners,
*our* threshold, *our* RecoveryModule — they pay gas to deploy a Safe
they don't control.

The only mild cost of a successful front-run: our own Phase 3 reverts
in step 3 (`createProxyWithNonce` reverts on existing-code), and we'd
need a fallback path that uses a `GnosisSafeSameAddressMultisig`-style
"register the already-deployed Safe" creator. **This is the same risk
profile as today's PolySafe creation** — the existing
`PolySafeCreatorWithRecoveryModule` flow has identical CREATE2-front-run
semantics and the codebase already tolerates it via the
`GnosisSafeSameAddressMultisig` fallback (see
`test/StakePolySafe.sol::testExternalCreatePolySafeAndStake` for the
pattern). Document and move on.

### Can we collapse this into a single atomic on-chain operation?

Yes, but in layered ways. "Single on-chain action" can mean three
different collapses, each gated on different work:

#### Collapse 1 — Phase 2 + Phase 3 atomic in one tx

The HTTP request to Polymarket carries all info already known
(`owner = predictedSafe`); its on-chain effect (the deposit-wallet
deploy) is normally a separate tx by the relayer's operator EOA.
**To collapse Phase 2's on-chain effect into Phase 3's tx, the factory
must expose an operator-sig meta-tx variant** (Path 2 from §"Why the
creator can't trigger the deploy itself" — the operator-whitelist option
is closed by assumption):

- **Path 2 (operator-sig meta-tx):** the factory exposes a
  `deployWithOperatorSig(owner, deadline, sig)` variant. Pearl client's
  HTTP call to Polymarket fetches a *signature* (not a deploy execution),
  embeds it in `data`, and `creator.create()` submits it on-chain. Phase
  2 becomes a pure info-fetch with no on-chain side effect of its own.

Under Path 2, the user's experience is: one HTTP call (info-fetch
only) + one on-chain tx that does both the Safe deploy and the
deposit-wallet deploy. The HTTP call does not need to land before
Phase 3; it just needs its returned signature to be in `data` when
Phase 3 runs.

The creator's `create()` extends to:

```
1. Decode data → (fallbackHandler, saltNonce, operatorSig, deadline).
2. Build Safe initializer.
3. newSafe = SafeProxyFactory.createProxyWithNonce(...).
4. DepositWalletFactory.deployWithOperatorSig(newSafe, deadline, operatorSig).
   → depositWalletAddr (returned by factory or computed via CREATE2).
5–8. Verify code/codehash/owner; record link; emit event.
9. return newSafe.
```

Atomicity is now total: if the factory call reverts (operator-sig
expired, signature mismatch, etc.), the entire Phase 3 reverts and
the OLAS service rolls back to FinishedRegistration cleanly. No
orphaned deposit wallet. No half-state.

**Status:** gated on the on-chain ABI probe. If Path 2 is not available,
the parallelised default flow above (Phase 2 off-chain via relayer,
Phase 3 on-chain) is the best we can do.

#### Collapse 2 — Phase 1 + Phase 3 atomic in one tx

Independent of Polymarket cooperation. Today, Phase 1's three OLAS
state transitions (`create → activateRegistration → registerAgents`)
are separate txs because the state machine was designed for flows
where different parties handle different transitions (service owner
creates, operators register agents). For the typical Pearl/Wildcard
case where one user is owner-and-operator-and-deployer, all four can
be batched.

Two implementation options:

- **Option A — periphery wrapper contract.** A new contract
  `DepositWalletServiceFactory.createAndDeploy(serviceConfig, multisigData)`
  that calls `ServiceManager.create / activateRegistration /
  registerAgents / deploy` in sequence. Complications: the wrapper
  becomes the temporary service NFT holder mid-flow and must transfer
  to the user at the end; ETH/token forwarding for security deposit
  and bonds must flow through the wrapper; `registerAgents` may
  require operator-as-msg.sender (workable since the wrapper IS the
  msg.sender when the user calls into it). Roughly ~150 lines of new
  contract code + tests. Reusable for *any* multisig type, not just
  deposit-wallet-backed.
- **Option B — `ServiceManager` extension.** Add
  `ServiceManager.createAndDeploy(...)` doing the full sequence in
  one external call. Smaller diff than Option A but requires upgrading
  ServiceManager (which is proxied — `ServiceManagerProxy` exists in
  this repo — so feasible, but it's a governance ask).

Both options are independent of the deposit-wallet creator and benefit
all multisig flows including the existing PolySafe one. **Out of scope
for this plan as currently written**, but worth pursuing as a separate
periphery improvement once the deposit-wallet creator is on the table.

#### Collapse 3 — full single-tx deploy (Collapse 1 + Collapse 2)

The "perfect" flow: one HTTP call (info-fetch), one on-chain tx that
does OLAS service registration + Safe deploy + deposit-wallet deploy +
binding, all atomic. Achievable iff:

- Path 2 holds for the deposit-wallet factory (operator-sig meta-tx
  variant), AND
- A `DepositWalletServiceFactory` wrapper exists (Option A) or a
  `ServiceManager.createAndDeploy` extension is shipped (Option B).

User experience reduces to "click deploy → wait for one tx receipt."
Same shape as today's standard ERC-4337 paymaster-sponsored
single-click flows.

**Recommendation, in priority order:**

1. **Probe the factory ABI** for an operator-sig variant (Path 2). Cheap
   — single Polygonscan read. If it exists, Collapse 1 is essentially
   free contract-wise. If it doesn't, Collapse 1 is permanently off the
   table (operator-whitelist is closed) and the parallelised default
   flow is the best on-chain shape we can ship.
2. **Scope the periphery wrapper** (Collapse 2 / Option A) as separate
   work. It improves UX for *all* OLAS service deployments, not just
   deposit-wallet ones. Don't bundle it into the deposit-wallet creator
   — the latter should stay scoped to its job.

The default (parallelised) flow above is the no-cooperation, no-extra-work
baseline. Collapse 1 (Path 2) and Collapse 2 (wrapper) are improvements
on top, layered independently.

### Target end-state — the shortest practical path

Combining Collapse 1 (Path 2 in-tx factory call) with Collapse 2
(periphery wrapper) gives a one-click, one-signing-prompt,
one-on-chain-tx flow for an OLAS service that's fully trading-ready when
the receipt lands. This is the aspirational end-state — what we'd ship
if the probe-gated unknowns resolve favorably and the periphery wrapper
is built. The operator-whitelist option is closed by assumption (treat
as "no" — see §"Why the creator can't trigger the deploy itself").

```
USER ACTION              PEARL CLIENT (off-chain)            ON-CHAIN

[Click "Deploy"]
                         1. Generate agent-instance EOA locally.
                         2. Pick saltNonce (any locally-unique value).
                         3. Compute predictedSafe + predictedDw via
                            CREATE2 (pure math, no tx).
                         4. Fetch operatorSig from Polymarket API
                            (Path 2 — required because factory is
                            onlyOperator-gated and creator can't be
                            an operator itself).
                         5. Sign agent-instance Safe-tx authorising
                            the post-deploy WALLET batch
                            (session-signer + approvals) — uses the
                            freshly-generated agent-instance key,
                            no user prompt.

[Approve tx in    ←──    6. Single signing prompt for one tx:
 wallet]                    DepositWalletServiceFactory.createAndDeploy(
                              serviceOwner = user,
                              token, configHash,
                              agentIds, agentParams,
                              threshold,
                              agentInstances = [agentInstance],
                              saltNonce, fallbackHandler,
                              operatorSig, deadline,      // Path 2 sig
                              walletBatchPayload          // pre-signed
                                                          // Safe-tx
                            )
                                                          ───────────────
                                                          ONE atomic tx:

                                                          ServiceManager:
                                                            .create
                                                            .activateReg…
                                                            .registerAg…
                                                            .deploy(…,
                                                              creator,
                                                              data)
                                                              ↓
                                                          creator.create:
                                                            - Safe deploy
                                                            - DepositWallet
                                                              deploy via
                                                              factory's
                                                              deployWith
                                                              OperatorSig
                                                              (Path 2)
                                                            - verify +
                                                              record link
                                                            - (if public
                                                              executeBatch
                                                              exists)
                                                              bootstrap:
                                                              authorize
                                                              sessionSigner
                                                              + approvals
                                                              batch
                                                            - transfer
                                                              service NFT
                                                              → user

[Tx receipt]                                              Service =
                                                          Deployed.
                                                          Deposit wallet =
                                                          bootstrapped.
                                                          Trading-ready.
```

**One click, one signing prompt, one on-chain tx, fully trading-ready
when the receipt lands** — *if* Path 2 is available. Otherwise the
parallelised default flow (Phase 2 off-chain via relayer in parallel
with Phase 1) is the best on-chain shape and the user still sees one
click but Pearl client orchestrates one HTTP call to the relayer
alongside the on-chain submission.

#### What each piece depends on (all probe-gated; no governance asks)

| Piece | Gate | Cost to verify / unlock |
|---|---|---|
| Single on-chain tx covers OLAS + Safe + DepositWallet | `DepositWalletServiceFactory.createAndDeploy` wrapper exists | ~150 LOC of new contract + tests; OLAS-internal work, no external dependency |
| Single tx triggers DepositWallet deploy in-line (no separate relayer roundtrip) | Path 2 — factory exposes `deployWithOperatorSig` (or equivalent) | Single Polygonscan ABI read. **If absent, this collapse is permanently off the table** — operator-whitelist is closed by assumption, so the relayer-deploy path remains a separate off-chain step. |
| Single tx also bootstraps session-signer + approvals | DepositWallet exposes a public on-chain `executeBatch(calls, ownerSig)` entry that accepts owner ECDSA-1271 sigs (i.e., the relayer is canonical but not the only path) | Single Polygonscan source-code read on `0x58CA52…D1eB` |

#### Graceful degradation when gates fail

The shortest path degrades cleanly to longer-but-still-acceptable paths
when individual gates fail; no all-or-nothing cliff.

| Failed gate | Effect on user experience |
|---|---|
| No public `executeBatch` on DepositWallet | Phase 4 (session-signer + approvals) reverts to off-chain relayer batch. Pearl client auto-fires the relayer call after the on-chain tx confirms. Service is "deployed" immediately and "trading-ready" ~30s later. One click, one signing prompt unchanged. |
| No Path 2 available | Phase 2 (DepositWallet deploy) goes off-chain via relayer, but Pearl client fires it in parallel with the user's signing prompt. User experience: one click, two background things resolving in parallel, one on-chain tx. **The relayer becomes a permanent hard dependency for new-user onboarding** — Pearl cannot recover the self-custody-from-minute-zero ergonomics PolySafe provides today, because the operator-whitelist option is closed. |
| No `createAndDeploy` wrapper shipped | User does the standard 4 OLAS txs sequentially (today's PolySafe UX), with the deposit-wallet pre-deploy happening off-chain in parallel with Phase 1. |

Even if every gate fails, the parallelised default flow still beats
today's PolySafe UX (because Phase 2 runs concurrently with Phase 1
rather than gating it). So there's no degraded-path scenario worse than
the current PolySafe baseline.

#### Pre-flight verification work to unlock the shortest path

In priority order, all cheap and fully self-serve (no Polymarket
cooperation required):

1. **Polygonscan probe of `DepositWalletFactory` ABI** — looking for an
   operator-sig meta-tx variant (`deployWithOperatorSig` or similar).
   <30 minutes. **This single probe determines whether Collapse 1 is
   achievable at all.** A negative answer permanently fixes Phase 2 as
   an off-chain relayer step.
2. **Polygonscan probe of `DepositWalletImplementation` source** — looking
   for a public `execute` / `executeBatch` entry that takes an owner
   signature. <30 minutes.
3. **Sandboxed `npm pack @polymarket/builder-relayer-client@0.0.9`** —
   confirms the salt scheme and factory call shape. <10 minutes.

Net: about an hour of focused probe work answers all the gates needed
to know what shipping shape Pearl can hit. Writing the periphery wrapper
(`DepositWalletServiceFactory`) is independent OLAS work that's
beneficial regardless of how the gates resolve.

### Why no on-chain `enableModule` second tx

`SafeMultisigWithRecoveryModule` enables the module via the `setup`
initializer's `to`/`data` slots — atomic. We use the same trick. No
second `execTransaction` needed, unlike `PolySafeCreatorWithRecoveryModule`
which can't pass `to`/`data` to `PolySafeProxyFactory.createProxy` (the
Polymarket factory doesn't expose those slots — it always passes `0` /
`""` / `fallbackHandler`).

### Why the Safe should NOT have agent instances as direct owners of the deposit wallet

**[SUPERSEDED — see §"Probe results" for corrected design.]** This section
argued for Safe-as-DW-owner; the 2026-05-04 source probe established that
the DW's signature path is ECDSA-only, forcing agent-EOA-as-owner. Kept
for historical context.

If we instead made the deposit wallet's owner `agentInstances[0]`
(the agent EOA), the Safe layer becomes purely ceremonial — the agent
EOA could sign CLOB orders directly via POLY_1271 + ERC-7739 against
the deposit wallet, bypassing the Safe entirely. This breaks:
- OLAS service governance (agent-instance turnover via `terminate → unbond
  → re-register` would lose access to the deposit wallet).
- Recovery (RecoveryModule transfers Safe ownership to the service owner;
  with agent-EOA-owned deposit wallet, recovery can't reach it).

The Safe MUST be the deposit wallet's owner. Order signing then becomes
a two-layer ERC-1271:
1. CLOB validates against `signer = depositWallet` via `isValidSignature(orderHash7739, sig)`.
2. Deposit wallet's `isValidSignature` delegates to `owner = Safe`, validating
   `Safe.isValidSignature(innerHash, ownerSig)`.
3. Safe's `isValidSignature` validates per Safe's standard scheme (ECDSA
   signatures from agent instances meeting threshold, or `v=1` sender-approved
   if the Safe itself is `msg.sender`).

The trader codebase has to assemble this two-layer signature. None of
this signing logic belongs in the on-chain creator — it's purely an
off-chain order-construction concern.

## Obstacles that can't be solved on-chain in the creator

These are the items that the creator cannot internalise; they belong in
the trader / wildcard / off-chain client.

| Obstacle | Why it can't live in the creator | Where it must live |
|---|---|---|
| Deposit wallet deploy is `onlyOperator` | Permission gate on the factory contract — our creator is not the operator. | Off-chain client calls Polymarket's relayer **before** `serviceManager.deploy(serviceId, creator, data)`. |
| ERC-7739 wrapping for order signatures | Off-chain order construction. Creator is only invoked at `deploy()` time, never on per-order signing. | Trader's CLOB-order-construction module. Likely a port of `@polymarket/clob-client-v2@1.0.3` (graduated to `latest` 2026-05-03)'s `signTypedDataWithSigner` flow with the Safe as the inner signer. |
| Approvals via relayer `WALLET` batch | The Safe can't `execTransaction` into the deposit wallet's approval surface — approvals are a deposit-wallet-issued ERC-20/ERC-1155 calldata batch routed through the relayer. | First-trade approval flow in trader. Replaces the existing `Safe.execTransaction(setApprovalForAll(...))` path. |
| Session-signer authorization | Optional feature; not strictly required for OLAS services where the Safe is the only signer. | If used, an off-chain ceremony where the Safe (as deposit wallet owner) signs `authorizeSessionSigner(sessionEOA, validUntil)` — purely an off-chain Safe-tx flow, no creator involvement. |

## ERC-8004 compatibility analysis

ERC-8004 compatibility hinges on `IdentityRegistryBridger.setAgentWallet(agentId, multisig, deadline, signature)`
recording the multisig as the agent's wallet. The key fact: the
**multisig** the bridger sees is whatever address `ServiceRegistryL2`
stores in `service.multisig` after `deploy()`.

In Design C, `service.multisig = the Safe`. Therefore:

- `IdentityRegistryBridger` records the Safe (not the deposit wallet) as
  the agent wallet. ✓
- The Safe is a regular Gnosis Safe v1.3.0 with module support — it can
  sign EIP-712 messages via `execTransaction` and validate them via
  `isValidSignature`. ✓
- `setAgentWallet`'s signature requirement (deadline-bound, signed by
  the agent wallet) is satisfied by the Safe signing the typed-data
  message in the standard Safe-execTransaction way. ✓

What changes for the trader:

- The trader's CLOB orders are signed by the **deposit wallet** (POLY_1271,
  sigType=3), not by the Safe.
- The trader's ERC-8004 metadata management calls (`setMetadata`, etc. via
  `IdentityRegistryBridger`) are signed by the **Safe** — same as today.

The two surfaces are independent. ERC-8004 stays compatible.

## Reading A vs Reading B contingency

(Re §"2026-05-06 PM addendum" in `CLOB_V2_FOLLOWUPS.md`.)

| Scenario | Action |
|---|---|
| **Reading A holds.** Smoke test on a fresh PolySafe + sigType=2 returns 200 OK end-to-end. CLOB API continues accepting newly-deployed PolySafes. | **No new contract needed.** This plan goes into the drawer as evergreen contingency. Existing `PolySafeCreatorWithRecoveryModule` keeps shipping new services indefinitely. |
| **Reading B holds.** Smoke test fails — `createOrDeriveApiKey` 4xx with "deposit wallet required" or `placeOrder` 4xx for sigType=2 from a new account. | **Implement Design C.** Estimate ~2 weeks: 3-5 days for the contract + tests, 5-7 days for the trader/wildcard order-signing + approvals refactor, 2-3 days for fork-test against Polygon mainnet. Plus deployment + whitelisting via `ServiceRegistryL2.changeMultisigPermission` (governance). |

**The smoke test is the gating signal.** Don't pre-build Design C until
the smoke test result is in. Ship it ready-to-go — i.e., this plan and a
PR-ready branch with the contract sketched but not deployed — only if
Reading B is a >50% probability bet.

## Pre-coding verification checklist

**Status as of 2026-05-04 EOD: all items resolved.** Both items previously
marked open are now resolved (one dissolved by design simplification, one
answered from factory source). The architecture is fully pinned and a
coding spike is unblocked.

- [x] **[RESOLVED]** `DepositWalletFactory` deploy function shape:
  ```solidity
  function deploy(address[] _owners, bytes32[] _ids) external onlyOperator
  ```
  Multiple wallets per call (one per `(_owners[i], _ids[i])` pair).
  `onlyOperator` is enforced via `hasAnyRole(msg.sender, _ROLE_1)` (solady
  OwnableRoles pattern). No return value; address is determined by
  `predictWalletAddress(_implementation, _id)`.
- [x] **[RESOLVED]** Operator-sig meta-tx variant: **does not exist**. Factory
  has only `deploy(...)` and `proxy(...)`, both `onlyOperator`. Path 2 is
  closed.
- [x] **[RESOLVED]** CREATE2 salt scheme:
  ```
  walletId      = bytes32(owner)                      // owner left-padded
  salt          = keccak256(abi.encode(factory, walletId))
  bytecodeHash  = LibClone.initCodeHashERC1967(implementation, encode(factory, walletId))
  address       = CREATE2(factory, salt, bytecodeHash)
  ```
  Verified against relayer-client `dist/builder/derive.js` and the factory's
  `predictWalletAddress(implementation, id)`. Deterministic on owner alone.
- [x] **[RESOLVED]** Owner-getter on the wallet: `owner()` exists (solady
  Ownable). Returns the address set at deploy.
- [x] **[RESOLVED]** ~~Capture `depositWalletBytecodeHash` for the creator's
  constructor immutable.~~ **Item dissolved.** The creator does not need a
  bytecode-hash immutable. The verification can use the factory's own
  `predictWalletAddress(impl, walletId)` view call:
  ```solidity
  require(dw == IDepositWalletFactory(factory).predictWalletAddress(
      impl,
      bytes32(uint256(uint160(agentInstance)))
  ), "wrong DW address");
  require(dw.code.length > 0, "DW not deployed");
  require(IDepositWallet(dw).owner() == agentInstance, "wrong DW owner");
  ```
  This is equivalent in security: if `dw` matches what the canonical
  factory would compute for `(impl, bytes32(agentInstance))`, then `dw`
  is at the canonical CREATE2 address — and CREATE2 collision rules mean
  any contract at that address must be the canonical bytecode. Cleaner
  than capturing and pinning a hash that depends on the network's specific
  factory + impl pair.
- [x] **[RESOLVED]** Session-signer ABI:
  - `authorizeSessionSigner(address, uint256) external onlySelf` (called via execute)
  - `revokeSessionSigner(address) external onlySelf` (called via execute)
  - `revokeSessionSignerEmergency(address) external onlyPaused onlyOwner` (msg.sender)
  - `sessionSignerAuthorizedUntil(address) view returns (uint256)`
- [x] **[RESOLVED]** Funding/withdrawal paths:
  - **Owner-direct (no relayer needed):** `withdrawERC20(token, to, amount)`,
    `withdrawERC1155(token, to, ids, amounts)`, `revokeAllowance(token, spender)`,
    `revokeApprovalForAll(token, operator)`. All `onlyPaused onlyOwner`. So
    fund recovery works without the relayer — owner pauses, withdraws, unpauses.
  - **Via execute (relayer needed):** any other call (transferOwnership,
    authorizeSessionSigner, approve, etc.).
  - **Recovery concern:** the wallet has no `RecoveryModule` analog. If the
    agent EOA is lost, no one can pause+withdraw. **`scripts/recover_funds_lost_agent_eoa.py`
    will need updating to capture the deposit-wallet funds before they're
    stranded** — the recovery flow can sweep the Safe, but the DW's funds are
    only recoverable while the agent EOA's key is still available. Practical
    mitigation: trader sweeps DW back to Safe daily.
- [x] **[RESOLVED from source]** ~~Empirical front-run check on Amoy.~~
  Resolved by reading the factory's `deploy()` body. Confirmed:
  - `LibClone.deployDeterministicERC1967(impl, args, keccak256(args))` —
    solady's CREATE2 deploy that reverts on existing-code at the target.
    "One owner = one wallet, ever" enforced at the factory level via
    CREATE2 collision.
  - No `owner.code.length` gate — owner can be EOA or contract (moot for
    our EOA-owner design but confirms there's no surprise).
  - Owner is set via `IDepositWallet(wallet).initialize(_owners[i])` in
    the same tx as deploy; no race window where the wallet exists with
    a different owner.
  - **`_ids` is operator-chosen.** The factory doesn't enforce
    `walletId == bytes32(owner)`; that's a relayer-side convention.
    **Implication for the design:** Pearl client should pass the
    actually-deployed DW address (returned by the relayer's
    `WALLET_CREATE` call) into `data` rather than re-deriving locally
    from `bytes32(agentInstance)`. The on-chain creator's
    `predictWalletAddress(impl, bytes32(agentInstance))` check then
    serves as a sanity assertion that the relayer used the standard
    convention; if it didn't, the call reverts and Pearl client gets
    a clean failure to retry.
- [ ] **Cheapest forward-looking re-check**: refetch
  `docs.polymarket.com/api-reference/authentication` weekly. As of the
  most recent FOLLOWUPS sweep (2026-05-07) it still lists only sigTypes
  0/1/2 and recommends sigType=2 for "any new or returning user." Adding
  a sigType=3 entry, or removing the new-user recommendation on sigType=2,
  would be the canonical canary signal that Reading B is firming.
  <30 seconds per re-check; lowest-cost forward-looking probe we have.

## Investigation log

Append-only log of what continued investigation has tightened or
re-weighted. Each entry shrinks the unverified surface a little.

### 2026-05-04 — Local SDK source probe (`clob-client-v2@1.0.0`)

The wildcard project's locally-installed pre-deposit-wallet SDK
(`/Users/kupermind/dev/wildcard/node_modules/@polymarket/clob-client-v2`,
v1.0.0) already carries the v2 order-builder skeleton. Probing it
answers four of the open questions without needing Polygonscan or a
1.0.3 install.

**Confirmed from local source:**

- **`SignatureTypeV2.POLY_1271 = 3`** is "EIP1271 signatures signed by
  smart contracts. To be used by smart contract wallets or vaults."
  (`dist/order-utils/model/signatureTypeV2.js`.) Verbatim.
- **Order's EIP-712 domain is the CTFExchange v2 contract, NOT the
  deposit wallet.** From `dist/order-utils/model/ctfExchangeV2TypedData.js`:
  ```js
  domain = { name: "Polymarket CTF Exchange", version: "2",
             chainId, verifyingContract: <CTFExchange v2 address> }
  ```
  The deposit wallet appears as the `maker` and `signer` *fields* inside
  the order struct, not as the `verifyingContract`. The signed typed-data
  hash is the standard EIP-712 hash; ERC-7739 wrapping (added in 1.0.3)
  is a separate outer envelope.
- **Order struct** (`CTF_EXCHANGE_V2_ORDER_STRUCT`):
  `{ salt, maker, signer, tokenId, makerAmount, takerAmount, side,
  signatureType, timestamp, metadata, builder }`. For deposit-wallet
  orders, `maker = signer = depositWallet` and `signatureType = 3`.
- **No ERC-7739 wrapping in 1.0.0.** `dist/order-utils/exchangeOrderBuilderV2.js`
  calls `signTypedDataWithSigner(typedData)` directly and `buildOrderHash`
  is just `hashTypedData(orderTypedData)` — no envelope. Confirms the
  plan's reading that ERC-7739 is an *outer* layer over the order's
  plain EIP-712 hash, added in 1.0.3 (PR #35), and not a domain-level
  change.

**What this tightens about the contract design:**

1. **The creator contract does not need to know about ERC-7739 at all.**
   The wrapping is purely off-chain, in the trader's order-construction
   path. Creator's only on-chain job is Safe deploy + deposit-wallet
   existence verification.
2. **Two-layer ERC-1271 model holds.** The CLOB calls
   `signer = depositWallet`'s `isValidSignature(plainOrderHash, sig)`;
   `sig` carries the ERC-7739-wrapped envelope; the deposit wallet
   unwraps + delegates to its owner (the Safe) via a second 1271 call.
   Plan's topology unchanged.
3. **Order-signing flow is layered, but each layer is independently
   testable.** Inner CTFExchange-domain typed-data → ERC-7739 envelope
   → final outer ECDSA. No on-chain creator involvement at any layer.

**Still unverified after the local probe.** Five questions remain. Three
of them are answerable from `@polymarket/builder-relayer-client@0.0.9`
(not currently installed in wildcard) without Polygonscan; two need
on-chain ABI inspection.

| Question | Answerable from `builder-relayer-client@0.0.9`? | On-chain probe needed? |
|---|---|---|
| Exact ERC-7739 envelope encoding | Partial — the trader-side construction is in `clob-client-v2@1.0.3` PR #35, not the relayer client. Need the 1.0.3 source. | No — pure off-chain. |
| `DepositWalletFactory.deploy` ABI / operator-sig variant | Partial — relayer client's `deployDepositWallet` shows the call shape it issues, including any signature in `data`. Doesn't reveal alternate factory entry points. | Yes — need full factory ABI on Polygonscan. |
| `deriveDepositWallet` salt scheme | **Yes** — the function is in `src/derive*.ts`. | No. |
| Owner-getter on DepositWalletImplementation | No — relayer client doesn't read owner. | Yes — `cast call <impl> "owner()(address)"` after deploy. |
| Session-signer signing scheme (plain EOA vs typed-data) | No — relayer client only deploys; it doesn't sign orders. | Yes — read implementation source on Polygonscan. |

**Recommended next probe — lowest-cost answer to most remaining unknowns:**

```
mkdir /tmp/poly-probe && cd /tmp/poly-probe
npm pack @polymarket/builder-relayer-client@0.0.9
tar -xzf polymarket-builder-relayer-client-0.0.9.tgz
grep -n -E "deriveDepositWallet|salt|0xff|create2" package/dist/*.js
# expected: salt scheme + factory call shape revealed in <5 minutes
```

Run this in a sandbox (not in `wildcard/node_modules`) so we don't dirty
the project's lockfile. Then the only remaining unknowns require an
on-chain probe of the deposit-wallet implementation
(`0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB` on Polygon). That probe
is cheap (Polygonscan source-code page, plus a couple of `cast call`s)
and answers the last load-bearing items.

### 2026-05-04 — Reading A vs Reading B probability re-weighting

Per `../wildcard/CLOB_V2_FOLLOWUPS.md` 2026-05-07 sweep (most recent),
Reading A's evidence has firmed materially since this plan was first
drafted on 2026-05-02:

1. **`docs.polymarket.com/api-reference/authentication`** still lists
   only sigTypes 0/1/2 and explicitly recommends sigType=2 for "any
   new or returning user." Strongest single forward-looking indicator —
   the canonical auth page would be first to change ahead of a sigType=2
   sunset, and it has not.
2. **POLY_1271 graduated `1.0.3-canary.0` → `latest 1.0.3`** silently
   on 2026-05-03, packaged with slippage-fee-math hardening
   (`Polymarket/clob-client-v2#57`) rather than as a coordinated cross-SDK
   GA wave. Shape consistent with "available, not mandatory."
3. **SDK churn since the 2026-05-01 deposit-wallet merge wave** is
   fee-math + typing fixes (`py-clob-client-v2 b0a97fac6a`) — *not* the
   coordinated polish that precedes a forced cutover.

**Effect on this plan's contingency table:**

- The smoke test (`createOrDeriveApiKey + placeOrder` against a fresh
  PolySafe + sigType=2) is **still load-bearing** for the empirical
  "what works today" question. Reading A's strengthening leans on
  indirect signals only; the smoke test is the only definitive answer.
- Probability re-weighting: pre-2026-05-07, A vs B was roughly even and
  the stance was "build-the-creator-when-needed." As of 2026-05-07,
  Reading A's weight is materially higher — but not high enough to retire
  the contingency. **Keep this plan in drawer; do not pre-build.**
- Trigger to re-open: any change to `/api-reference/authentication` (cheap
  weekly probe, see Pre-coding verification checklist) OR a partner-channel
  notification of a forced-migration timeline OR the smoke test failing.

### 2026-05-04 — SDK version-pin updates

The plan as originally drafted referenced `@polymarket/clob-client-v2@1.0.3-canary.0`
as the version that introduced POLY_1271. That tag has graduated. All
references should be read as:

| Component | Was (pre-2026-05-03) | Now |
|---|---|---|
| `@polymarket/clob-client-v2` | `1.0.3-canary.0` (canary) | `1.0.3` (latest) |
| `@polymarket/builder-relayer-client` | `0.0.9` (latest) | unchanged |
| `py-clob-client-v2` | `1.0.1rc1` (rc) | unchanged on registry; HEAD advanced to `b0a97fac6a` (typing/visibility, no logic change) |
| `py-builder-relayer-client` | `0.0.2rc1` (rc) | unchanged |
| `polymarket_client_sdk_v2` | `0.6.0-canary.1` (canary) | unchanged |

When/if we build, target stable 1.0.3 + stable 0.0.9 rather than canary.
Contract surface and behaviour are unchanged from canary; only the
dist-tag has moved.

### 2026-05-04 — Polygonscan/Sourcify source probe (load-bearing correction)

**Probes 1, 2, 3 executed against Polygon mainnet.** Sources extracted via
Sourcify (`https://sourcify.dev/server/files/any/137/<addr>`) — public, no
API key required — and verified against the relayer-client's local source.

**Targets probed:**

| Address | Role | Source obtained |
|---|---|---|
| `0x00000000000Fb5C9ADea0298D729A0CB3823Cc07` | DepositWalletFactory entry (vanity proxy) | Yes, via Sourcify proxy resolution |
| `0xb6f9c7e68a38c21bedfd873bc5a378236f7ba987` | DepositWalletFactory implementation | Yes, via Sourcify |
| `0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB` | DepositWallet implementation | Yes, via Sourcify |
| `@polymarket/builder-relayer-client@0.0.9` | Relayer client (TS source) | Yes, via `npm pack` (no project lockfile churn — installed in `/tmp/poly-probe`) |

**Findings reshaping the plan** (full detail in §"Probe results — 2026-05-04
— major design correction" near the top):

1. **Path 2 confirmed not present.** Factory has only `deploy(_owners[], _ids[])`
   and `proxy(Batch[], bytes[])`, both `onlyOperator`. **Collapse 1
   permanently off the table.**
2. **DW owner must be EOA.** Verbatim comment in
   `_erc1271IsValidSignatureNowCalldata`: `// always ECDSA, regardless of
   signer.code.length`. Underlying check is `ECDSA.tryRecoverCalldata(hash, sig) == signer`
   where signer is `owner()` or session signer. **A Safe cannot own a DW.**
   Solady's nested-EIP-712 (ERC-7739-shaped) wrapping is for cross-account
   replay defense, not for 1271 fallback.
3. **`execute()` is `onlyFactory`-gated.** All batch operations route via
   `factory.proxy(...)` which is `onlyOperator`. **Phase 4 inlining off the
   table.** Bootstrap (session signer + approvals) must go through the
   relayer.
4. **Salt scheme** = `keccak256(abi.encode(factory, bytes32(owner)))` against
   ERC-1967 minimal proxy bytecode. Fully owner-derived; no Safe-derived input.

**Findings tightening prior assumptions:**

- Wallet imports `solady ERC1271`, `Receiver`, `Initializable`,
  `UUPSUpgradeable`, `SignatureCheckerLib` (used internally for the nested
  envelope, not for 1271 fallback as we'd hoped).
- Owner-direct call surface is non-trivial: `pause`, `unpause`,
  `withdrawERC20`, `withdrawERC1155`, `revokeAllowance`,
  `revokeApprovalForAll`, `revokeSessionSignerEmergency`. These bypass
  `execute()` and work without the relayer. **Useful for fund recovery.**
- Two-step ownership handover via solady (`transferOwnership` + `completeOwnershipHandover`).
- UUPS upgradeable, `_authorizeUpgrade` is `onlyOwner`. Means a bad-actor
  owner could upgrade the wallet's logic; not a concern for OLAS services
  since the agent EOA we generate is single-purpose.
- Factory is also UUPS-upgradeable. Polymarket can change the factory's
  logic at any time. **Worth flagging as an external dependency that can
  change underneath us.**

**Practical state of the design after probes:**

- Single user click + single signing prompt + single on-chain tx for the
  Safe-deploy. Phase 2 (DW deploy via relayer) and Phase 4 (DW bootstrap
  via relayer) run as background HTTP roundtrips.
- Recovery for DW funds is materially weaker than today's PolySafe.
  Mitigation: Pearl trader sweeps DW back to Safe regularly.
- The IMultisig creator's owner-check changes from "DW owner == Safe" to
  "DW owner == agentInstances[0]" — a small one-line code change from the
  previous Design C sketch.

**Pre-coding checklist status:** 6 of 8 items resolved by these probes.
Two open items remaining (capture `depositWalletBytecodeHash`; empirical
front-run check on Amoy). Both are <30-minute tasks before a coding spike.

**Source artifacts kept for reference:** `/tmp/poly-probe/DepositWallet.sol`,
`/tmp/poly-probe/DepositWalletFactory.sol`, `/tmp/poly-probe/WalletLib.sol`,
`/tmp/poly-probe/Ownable.sol`, `/tmp/poly-probe/SessionSignerLib.sol`,
`/tmp/poly-probe/ECDSA.sol`, `/tmp/poly-probe/ERC1271.sol`,
`/tmp/poly-probe/package/dist/builder/derive.js` (relayer-client salt
derivation reference). All extracted from public sources; no secrets.

### 2026-05-04 EOD — ECDSA verification deep-dive (no escape hatch from EOA-only)

Triple-confirmed that the DepositWallet's signature path is structurally
incompatible with smart-contract owners. Recorded under §"Probe results"
Finding #2 → "Verification chain". Top-line:

- `ECDSA.tryRecoverCalldata` calls precompile `0x01` (`ecrecover`) with no
  contract handling — pure assembly, no `EXTCODESIZE`, no `IERC1271` call.
- Polymarket explicitly *overrode* solady's default
  `_erc1271IsValidSignatureNowCalldata` (which would have used
  `SignatureCheckerLib.isValidSignatureNowCalldata` and supported contract
  sigs via 1271 fallback) with a pure-ECDSA implementation. Verbatim
  comment in the override: `// always ECDSA, regardless of signer.code.length`.
- All three solady ERC1271 validation paths
  (`_erc1271IsValidSignatureViaSafeCaller`, `_erc1271IsValidSignatureViaNestedEIP712`,
  `_erc1271IsValidSignatureViaRPC`) ultimately invoke the override. No
  escape path.

**Implication that didn't change but is now firmly anchored:** the corrected
"Safe + DW as independent peers" topology is the only viable architecture.
Any future review questioning this assumption can be answered by walking
the three layers above. The `agent-instance EOA = DW owner` model is not a
preference — it's structurally required by Polymarket's contract.

**Two pre-coding items resolved at the same time:**

- **`depositWalletBytecodeHash` immutable dissolved.** The creator can use
  `factory.predictWalletAddress(impl, walletId)` for address verification
  instead of pinning a network-specific codehash. Three-line check
  (predicted-address match + code-exists + owner-matches) is equivalent in
  security via CREATE2 collision rules. Cleaner; no UUPS-upgrade surprise.
- **Amoy front-run check resolved from factory source.** Verified from
  `DepositWalletFactory.deploy()` body that `LibClone.deployDeterministicERC1967`
  reverts on existing-code at the target (CREATE2 collision), confirming
  "one owner = one wallet, ever." Owner can be EOA or contract (no
  `code.length` gate at deploy). `walletId` is operator-chosen, but the
  relayer-client convention is `bytes32(owner)` per `derive.js`.
  **Pre-coding checklist now fully resolved.**

### 2026-05-04 EOD — Ownership-handover deep-dive (Safe-as-DW-owner is permanently sealed)

Question raised: can we ever bind the Safe to the DW after deploy — i.e.,
deploy DW with agent EOA as owner, then transfer ownership to the Safe via
some handover path? **Answer: no, structurally sealed.** Three concentric
barriers, each from source:

**Barrier 1 — `transferOwnership` is `onlySelf`.**

```solidity
// DepositWallet.sol:243
function transferOwnership(address _newOwner) external onlySelf {
    _transferOwnership(_newOwner);
}
```

Step 1 of the handover (setting `pendingOwner`) requires `execute()` with
an owner-signed batch. Doable while the agent EOA is still the owner.

**Barrier 2 — `completeOwnershipHandover` requires the pending owner to ECDSA-sign.**

```solidity
// Ownable-DW.sol:135-152 (Polymarket's CUSTOM Ownable, NOT solady's standard)
function _completeOwnershipHandover(uint256 _deadline, bytes calldata _signature)
    internal virtual
{
    require(block.timestamp <= _deadline, Expired());
    address pending = pendingOwner();
    require(pending != address(0), NoPendingOwner());

    bytes32 structHash = keccak256(abi.encode(_OWNERSHIP_HANDOVER_TYPEHASH, pending, _deadline));
    bytes32 digest = _hashTypedData(structHash);
    require(ECDSA.recoverCalldata(digest, _signature) == pending, InvalidSignature());
    ...
}
```

Pure `ECDSA.recoverCalldata` — same precompile-0x01 path with no contract-sig
fallback we already documented. The pending owner (a Safe) cannot produce a
signature that ECDSA-recovers to its own address. Reverts.

**The custom Ownable's docstring spells out the intent verbatim:**

> "Two-step ownership management with EIP-712 signature-based handover.
> Ownership transfers require the new owner to sign an `OwnershipHandover`
> EIP-712 message. **This prevents accidental transfers to addresses that
> cannot interact with the wallet.**"

Polymarket replaced solady's standard `transferOwnership(newOwner)` (which
would have done an instant set with no sig requirement, allowing a Safe
target) with this two-step EIP-712-signed handover *specifically* to prevent
Safe-as-owner. It's not an oversight; it's the explicit design.

**Barrier 3 — No `renounceOwnership`, no other escape.**

The custom Ownable strips solady's `renounceOwnership`. There's no
on-chain mechanism to set the owner to anything other than via the
two-step handover. The current owner cannot abdicate; cannot transfer
to a contract; cannot transfer to address(0). Owner is **permanently
EOA-bound** for the life of the wallet.

**Architectural implication that didn't change but is now firmly anchored:**

The OLAS service-as-multisig model is partially weakened by the corrected
design. The Safe retains:

- OLAS service NFT ownership (`service.multisig` in registry)
- ERC-8004 agent wallet identity (`IdentityRegistryBridger` records it)
- Reserve fund custody (sweep target for trader)
- `RecoveryModule` recoverability (Safe ownership reset → Master Safe sole owner)
- OLAS-protocol multisig role for governance, staking, slashing

The Safe loses:

- Authority over CLOB order signing (DW's signature path is EOA-only)
- Custody of trading balance (DW holds the trading float)
- Authority over DW session-signer rotation (only DW owner = agent EOA can)
- DW fund recoverability (no module support; lost agent EOA = stranded balance)

**Scope note:** OLAS Polymarket services are single-agent (one agent
instance per service). M-of-N threshold concerns over the DW don't apply
in practice — there is exactly one agent EOA per service, and that EOA is
the DW's owner. We're not constrained by Polymarket's single-owner DW
model for the trading authority itself.

Net: the Safe becomes the service's **identity wallet**; the DW (with agent
EOA as owner) is the **trading hot wallet**. Same agent EOA bridges both.
This is a real architectural downgrade vs. the PolySafe model where the
Safe IS the trading wallet — but the practical impact is narrower than it
might appear. Today's PolySafe is also a single-agent-EOA-owned Safe;
moving to "agent EOA directly owns the DW, Safe is identity-only" loses
the RecoveryModule protection for trading funds and the
multisig-as-trading-wallet abstraction, but it doesn't change the threshold
shape — both models are 1-of-1 at the trading layer.

**Mitigations** (operational, not architectural):

1. **Sweep DW balance to Safe regularly** (e.g., every N hours or when
   DW balance > threshold). Keeps the at-risk balance close to immediate
   trading needs only.
2. **Treat the agent EOA as a load-bearing hot wallet** — hardware-backed
   key management or KMS, not a software hot wallet.
3. **Use session signers for ephemeral trading keys** if there's a need to
   rotate without exposing the long-lived agent EOA on every CLOB call.
   Owner-direct `revokeSessionSignerEmergency` (no relayer needed) gives a
   fast revocation path if a session key is compromised.
4. **Update `scripts/recover_funds_lost_agent_eoa.py`** to call DW
   `pause` → `withdrawERC20`/`withdrawERC1155` → `unpause` *before* the
   agent EOA becomes unrecoverable. Captures whatever's in the DW at
   recovery time. Doesn't help if the agent EOA is already lost; only
   helps when there's still time.
5. **Reading A remains the cleanest escape.** If the smoke test confirms
   PolySafes still work for new accounts under the rollout, this whole
   architecture is unnecessary and the existing PolySafe model preserves
   Safe-as-trading-wallet semantics intact.

**Source artifacts added:** `/tmp/poly-probe/Ownable-DW.sol` (Polymarket's
custom two-step EIP-712-signed handover, distinct from solady's standard).
The standard solady Ownable is also kept for reference at
`/tmp/poly-probe/Ownable-solady.sol` to show the diff.

### Re-verification 2026-05-09 — fresh code-side probe of CTFExchange v2 + DW stack + SDKs (no reliance on prior FOLLOWUPS entries)

Triggered by an "are these claims still accurate?" check. Re-fetched everything from primary sources today; all DW-stack findings hold; the CLOB exchange contract is verified as the place where the partner-channel rejection cannot live.

**On-chain CTFExchange v2 (`0xE111…996B`) and NegRiskCTFExchange v2 (`0xe222…0F59`) — load-bearing for "what enforces the partner-channel allowlist?".** Solidity sources are byte-identical (only `constructor-args.txt` and `creator-tx-hash.txt` differ). GitHub head still `ccc0596074` (2026-04-13 — 26 days unchanged). Critical:

- `Trading.sol::_validateOrder` (lines 46-63) does three checks total: non-zero `makerAmount`, valid signature, maker-not-paused. **No wallet-type gating, no allowlist lookup, no creation-time check.**
- `Signatures.sol::_isValidSignature` accepts all four sigTypes (EOA / POLY_GNOSIS_SAFE / POLY_1271 / POLY_PROXY) unconditionally. `_verifyPolySafeSignature` only checks ECDSA + CREATE2-derived safe address.
- **No allowlist storage of any kind anywhere in the deployed bytecode.** Exhaustive grep over `mixins/`, `libraries/`, `interfaces/` returns only `Auth.sol`'s admin/operator maps and `UserPausable`'s pause map. No `mapping(address=>bool) allowedTraders`, no `authorizedSigners`, no per-wallet policy.
- Admin functions (`pauseTrading`, `setUserPauseBlockInterval`, `setFeeReceiver`, `setMaxFeeRate`) cannot disable a sigType or maintain a per-wallet allowlist.

**Conclusion:** the rejection of new PolySafes from CLOB trading (per 2026-05-08 partner statement) is **provably enforced exclusively off-chain at Polymarket's CLOB API ingest service.** No on-chain layer could implement it without a contract upgrade, and no such upgrade has been deployed or even committed to the public repo. This *strengthens* — not weakens — Reading B: the partner statement is fully consistent with on-chain reality, and on-chain reality forecloses any alternative interpretation.

**DepositWallet stack re-verified (Sourcify full-match today):**
- `DepositWalletFactory.deploy()`/`proxy()` `onlyOperator` — re-confirmed lines 192/214. No meta-tx variant in ABI. Path 2 permanently off the table (re-confirmed against bytecode-verified source, not just commit history).
- `DepositWallet._erc1271IsValidSignatureNowCalldata` pure ECDSA with literal comment `// always ECDSA, regardless of signer.code.length` — re-confirmed lines 442-451. Safe-as-DW-owner remains structurally sealed.
- `DepositWallet.execute()` `onlyFactory` — re-confirmed line 172.

**Public-doc delta (relevant to plan).** `/trading/deposit-wallet-migration` (last-modified 2026-05-02 per Mintlify metadata) is now stronger than prior FOLLOWUPS sweeps captured. Verbatim implementation checklist: *"Use deposit wallets only for new API users in this phase. Keep existing proxy and Safe users on their current signature type."* — explicit prescription, not just permission. Public-doc-vs-partner-channel gap is narrower than the 2026-05-08 sweep concluded; the substantive policy is now in public docs even though the "allowlist"/"grandfather" mechanism vocabulary remains partner-channel-exclusive. `/api-reference/authentication` (last-modified 2026-04-28 — predates rollout) still recommends sigType=2 for new users — confirmed real docs bug, not stale-cache illusion.

**Implication for this plan.**

1. **Reading B is now triple-anchored** — partner channel (2026-05-08), public docs (2026-05-02), and on-chain code structure (rejection cannot be on-chain → must be the CLOB API service the partner named). The 2026-05-04 plan's "Reading A remains the cleanest escape" caveat is materially weaker today; the smoke test would confirm rather than potentially refute.
2. **The plan's contract design is fully validated against fresh source.** No on-chain claim in this doc has shifted under re-verification.
3. **Build trigger threshold lowered.** Previously: build on confirmed Reading B *plus* product greenlight to commit to the relayer dependency. Now: same threshold, but the "is Reading B real?" component has triple confirmation. The remaining gate is product-side (accept relayer hard-dependency + accept self-custody-from-minute-zero loss).

**Source artifact:** all on-chain findings cross-recorded in `../wildcard/CLOB_V2_FOLLOWUPS.md` §"2026-05-09 sweep — fresh code/docs/SDK re-verification" with full reconciliation table (claim ↔ public-doc ↔ partner-channel ↔ on-chain code).

### Design lock-in 2026-05-10

Confirmed with product team: implementation will follow the **corrected Design C** (a.k.a. Option B from the 2026-05-10 design discussion). Same as §"Recommended design — Design C in detail" except for the post-probe ownership correction:

```solidity
// Step 6 of create() — corrected post-probe ownership check:
require(IDepositWallet(depositWalletAddr).owner() == agentInstances[0]);
//                                                    ^^^^^^^^^^^^^^^^^^
//        NOT == newSafe (pre-probe Design C had this; the EOA-only DW
//        owner constraint forecloses Safe-as-DW-owner).
```

The contract surface, `data` payload shape, off-chain pre-flow (Pearl predicts addresses → relayer pre-deploys DW in parallel with OLAS service registration), and on-chain link-record (`mapMultisigDepositWallets` + `DepositWalletLinked` event) are unchanged from §"Recommended design — Design C in detail". The `READER NOTE` at the top of this plan still applies — read §"Probe results — 2026-05-04" and §"Corrected design — Safe + DepositWallet as independent peers" for the load-bearing topology, not the original Design C lines 850-1006.

**On-chain footprint:** **exactly 1 user transaction** (`ServiceManager.deploy` → `safeAndDWCreator.create()`). Off-chain HTTP roundtrips are unconstrained — Pearl can fire any number of relayer calls before/after. The "1 tx" property is what matters; HTTP count is not a constraint.

**Two prior load-bearing caveats explicitly accepted by product:**

1. **DW recovery weakness defused by Privy custody.** The 2026-05-04 plan flagged "lose agent EOA → DW funds stranded" as the load-bearing risk and proposed a "sweep DW balance regularly" mitigation. Under Privy's key custody for the agent-instance EOA, the EOA isn't losable in the normal sense (Privy handles MPC/social recovery on the user-experience side). RecoveryModule still recovers the Safe (governance + ERC-8004 agent wallet status) for the OLAS-side via the existing `recover_funds_lost_agent_eoa.py` flow; Privy handles the DW-owner-EOA side. **No DW-side recovery sweep mitigation needed.** The "sweep regularly" line item from the plan can be dropped.

2. **Front-running acknowledged but not a blocker.** The CREATE2 collision-revert in `LibClone.deployDeterministicERC1967` (one-owner-one-DW-ever) plus the agent-instance EOA being a Pearl-internal value (not user-visible / not contention-prone) keep the surface small. Document in the vuln-list for completeness — no on-chain countermeasure required beyond the factory's existing collision behaviour.

**What stays load-bearing (unchanged):**

- `DepositWalletFactory.deploy()` is `onlyOperator` → DW pre-deploy is HTTP-blocking. If Polymarket's relayer is down at the moment Pearl's user submits the on-chain tx, `create()` reverts on the `code.length > 0` check. Pearl must surface "deploy retry needed" UX. Unavoidable structural cost of the rollout.
- Phase 4 (session-signer auth + approvals) is `onlyFactory`-gated → cannot be inlined. Trading-ready lags service-deployed by one relayer roundtrip (~5-30s). Worth surfacing in Pearl UX.
- `agentInstance` is one of the Safe's owners *and* the DW's sole owner. Asymmetric topology — **not** "Safe owns DW" (which the source forecloses). Worth documenting in the contract NatSpec so future readers don't assume the wrong shape.
- Whitelisting the new creator in `ServiceRegistryL2.mapMultisigs` via `changeMultisigPermission` requires a governance proposal — same shape as past creator additions.

**Implementation scoping (rough):**

- New contract: `contracts/multisigs/SafeAndDepositWalletCreator.sol` (or similar — naming TBD). Fork of `SafeMultisigWithRecoveryModule.sol` plus the DW-link verification (~60-80 LoC delta). New immutables: `depositWalletFactory`, `depositWalletBytecodeHash`. New storage: `mapMultisigDepositWallets`. New event: `DepositWalletLinked`. New interface: `IDepositWallet` (just `owner()`).
- Mock contract: `contracts/test/MockDepositWalletFactory.sol`, mirroring the `MockPolySafeFactory.sol` pattern.
- Tests:
  - Unit (Hardhat or Forge): the canonical happy-path + failure modes (DW not pre-deployed, DW owner mismatch, DW codehash mismatch).
  - Forge fork-test against Polygon: end-to-end `serviceManager.deploy → creator.create()` against the live `DepositWalletFactory` with a relayer-deployed DW. Pattern: `test/StakePolySafe.sol`'s `testExternalCreatePolySafeAndStake` is the closest analogue.
- Off-chain (Pearl): new `predictDepositWalletAddress(agentInstance)` helper, relayer client integration (use `@polymarket/builder-relayer-client@0.0.9`), pre-tx orchestration of DW deploy + post-tx Phase 4 batch.
- Estimated effort: ~3-4 days for the contract + tests; ~2-3 days for off-chain orchestration; ~1 day for governance proposal + whitelisting. ~1 week of focused engineering total.

**Vuln-list items to record (acknowledged-not-blocking):**

- CREATE2 front-running on the DW pre-deploy. Mitigated by the factory's collision-revert and the agent-instance EOA being a Pearl-internal value. No on-chain countermeasure required.
- Relayer hard-dependency for new-account onboarding. Loss of the self-custody-from-minute-zero / permissionless-wallet-creation property. Architectural trade explicitly accepted by product.
- DW-side recovery: relies on Privy's EOA custody. If Privy custody is breached, DW funds at risk. Out-of-scope for this contract; tracked at the product layer.

## Out of scope for this plan

- Trader-side / wildcard-side order signing refactor. Lives in
  `valory-xyz/trader` and `valory-xyz/wildcard`. Tracked under the
  Reading-B-contingent action items in
  `../wildcard/CLOB_V2_FOLLOWUPS.md`.
- ERC-7739 helper contract for off-chain typed-data construction. May be
  worth building as a stateless `view`-only helper in this repo for
  testability, but not blocking.
- Migration tooling for existing Pearl users (PolySafe → deposit wallet).
  Public docs explicitly say no migration path is provided. If forced
  later, a separate plan covers fund sweep + new account creation.
- Recovery flow updates. The `RecoveryModule` recovers the Safe; the
  Safe's `recoverAccess` doesn't touch the deposit wallet. If the
  deposit wallet is owned by the Safe, post-recovery the new sole
  owner of the Safe (the Master Safe) can sign deposit-wallet
  withdrawals — but this needs to be explicit in
  `scripts/recover_funds_lost_agent_eoa.py` and tested.
- Deployment scripts and whitelisting governance proposal — deferred
  until Reading B is confirmed.

## Open questions (stack-rank)

1. **Salt scheme.** Without it, `predictDepositWalletAddress` can't be
   implemented. Highest priority on the verification checklist.
2. **Owner-set-at-deploy vs post-deploy initialize.** Determines deploy
   ordering (B1 vs B2).
3. **Code-gate at deploy.** Determines whether B2 is even feasible.
4. **Deposit-wallet recovery surface.** Determines whether
   `RecoveryModule` is sufficient or whether we need a deposit-wallet
   equivalent.
5. **Reading A vs Reading B itself.** Until the smoke test runs, all of
   the above is contingent. Plan stays in drawer.

## Related repo files

- `contracts/multisigs/PolySafeCreatorWithRecoveryModule.sol` — current Polymarket creator
- `contracts/multisigs/SafeMultisigWithRecoveryModule.sol` — generic Safe creator (the closer template for Design C)
- `contracts/multisigs/RecoveryModule.sol` — module enabled in the new Safe
- `contracts/multisigs/GnosisSafeSameAddressMultisig.sol` — pattern for "external creation + post-hoc registration" (referenced in `StakePolySafe.sol`'s `testExternalCreatePolySafeAndStake`); analogous shape may be useful if we want to accept already-deployed deposit-wallet pairs
- `contracts/8004/IdentityRegistryBridger.sol` — `setAgentWallet` path; multisig stays the agent wallet
- `contracts/interfaces/IMultisig.sol` — the interface contract; whitelisted via `ServiceRegistryL2.changeMultisigPermission`
- `contracts/test/MockPolySafeFactory.sol` — pattern for a mock factory test contract; we'd need a `MockDepositWalletFactory.sol` for forge/hardhat tests
- `test/PolySafeCreatorWithRecoveryModule.t.sol` — unit test pattern
- `test/StakePolySafe.sol` — fork-test pattern for `serviceManager.deploy` + creator integration
- `clob_v2_impact_polySafeCreator.md` — companion (existing PolySafeCreator unaffected by CLOB v2 itself; this plan is the deposit-wallet-specific follow-up)
- `../wildcard/CLOB_V2_FOLLOWUPS.md` — load-bearing source for deposit-wallet architecture and Reading A/B framing
