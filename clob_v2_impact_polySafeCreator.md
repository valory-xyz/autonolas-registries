# CLOB v2 Migration — Impact on `PolySafeCreatorWithRecoveryModule.sol`

**Date:** 2026-04-23
**Source notes:** `../wildcard/CLOB_V2_MIGRATION_NOTES.md`
**Cutover:** 2026-04-28 ~11:00 UTC (Polygon stays)

## TL;DR

`contracts/multisigs/PolySafeCreatorWithRecoveryModule.sol` is **not affected**. No code or redeployment required.

## Why it's unaffected

The CLOB v2 changes all live above the Safe layer. This contract's scope is strictly:

1. `createProxy()` on Polymarket's Proxy Factory `0xaacfeea03eb1561c4e67d661e40682bd20e3541b`
2. Verify bytecode hash, owners, threshold
3. `execTransaction(enableModule(recoveryModule))` on the new Safe

| CLOB v2 change | Touches this contract? |
|---|---|
| New `CTFExchange` / `NegRiskCTFExchange` addresses | No — contract never references exchanges |
| Collateral swap USDC.e → pUSD | No — contract never touches collateral/ERC20s |
| EIP-712 Order domain version `"1"` → `"2"` | No — contract's EIP-712 hashes are the **Safe's** `SafeTx` + the **proxy factory's** `CreateProxy`, not the Exchange's `Order` |
| SDK struct mutations (`timestamp`, `metadata`, `builder`, etc.) | No — off-chain client concern |
| EIP-1271 added for smart-contract wallet order signing | No — signing path used by the Safe *owner* when placing orders. Safe creation is unrelated; the created Safe v1.3.0 already implements `isValidSignature` natively |
| `POLY_GNOSIS_SAFE` signature type survival | No — client-SDK signing path, not creation |

The migration notes confirm the chain stays Polygon, `ConditionalTokens` is unchanged, and there is no hint of a new Safe singleton, a new Proxy Factory, or a new Safe bytecode hash. The Safe infrastructure sits at the same level as CTF — below the exchange layer that's being replaced.

## The one scenario that would change the answer

**Polymarket swaps the Proxy Factory or upgrades the Safe singleton (e.g., v1.3.0 → v1.4.x).**

That would change:
- `polySafeProxyBytecodeHash` (bytecode hash check at line 175 would fail)
- the factory's `domainSeparator()` (cached at line 141)

…and would require redeployment of `PolySafeCreatorWithRecoveryModule` with new constructor args. `CREATE_PROXY_TYPEHASH` and `SAFE_TX_TYPEHASH` would still be valid under v1.4.x, so only the immutables would differ. Nothing in the CLOB v2 notes implies this is happening.

## Not this repo's problem

The approval/trading changes in the Wildcard notes (pUSD approvals, `CollateralOnramp.wrap()`, new Exchange `setApprovalForAll`, v2 order signing) belong in the **consumer** of these Safes — Wildcard's `src/core/safe/multisend.ts` and `trading.ts`.

A grep of this repo for CLOB/exchange/collateral touchpoints (`CTFExchange`, `NegRiskCTFExchange`, `NegRiskAdapter`, `ConditionalTokens`, `USDC.e`, `pUSD`, `clob`, etc.) found no hits outside the `PolySafeCreator*` / `StakePolySafe` / `recover_funds_lost_agent_eoa` files. The Polymarket surface here is strictly Safe creation + `RecoveryModule` + a fork-test on `StakePolySafe`.

## Recommended verification on cutover day (belt-and-suspenders)

Run on Polygon post-cutover and confirm values still match the deployed `PolySafeCreatorWithRecoveryModule` immutables:

```bash
cast call 0xaacfeea03eb1561c4e67d661e40682bd20e3541b "domainSeparator()(bytes32)" --rpc-url $POLYGON_RPC
# compare to polySafeCreatorWithRecoveryModule.polySafeProxyFactoryDomainSeparator()

# Confirm a freshly computed Safe-proxy has the same codehash as polySafeProxyBytecodeHash
```

If both match, no action required.

## Related repo files (reference)

- `contracts/multisigs/PolySafeCreatorWithRecoveryModule.sol` — the contract in question
- `contracts/multisigs/RecoveryModule.sol` — module being enabled
- `contracts/test/MockPolySafeFactory.sol` — mock factory for tests
- `test/PolySafeCreatorWithRecoveryModule.t.sol` — unit tests
- `test/StakePolySafe.sol` — fork test (`forge test -f $FORK_NODE_URL --match-contract StakePolySafe`)
- `scripts/recover_funds_lost_agent_eoa.py` / `docs/recover_funds_lost_agent_eoa.md` — recovery flow docs
