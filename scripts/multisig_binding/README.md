# Multisig binding (Immunefi 81064 remediation)

Operational tooling for the 1:1 multisig↔service binding introduced in `ServiceManager` (see
[Vulnerabilities list #23](../../docs/Vulnerabilities_list_registries.md#23-deploy-same-address-multisig-takeover-recoverymodule)).
After the fixed `ServiceManager` implementation is live behind a `ServiceManagerProxy`, these scripts claim and
audit the canonical `mapMultisigServiceIds[multisig] = serviceId` binding for already-deployed services.

## `bind_fix.js` — back-fill runner

Calls the permissionless, idempotent `bindMultisig(uint256[] serviceIds)` for every service `1..totalSupply()`
(Gnosis binds an embedded immediately-drainable set first). It confirms the proxy is on the fixed impl, sizes
batches from a real `estimateGas` of each slice (kept under the block gas limit with EIP-150 1/64 headroom), and
splits/retries on a mined revert. Idempotent — `bindMultisig` skips `multisig==0` and already-bound entries, so
re-running is safe.

```bash
node bind_fix.js <plan|fork|execute> <chain|all> [--chainId N]
```
- `plan` — print the batch plan, no send. `fork` — exercise it against an anvil fork (`FORK_URL=...`).
- `execute` — real send, signed with `PRIVATE_KEY` (env) if set, otherwise a Ledger (path `m/44'/60'/2'/0/0`,
  override `DERIVATION_PATH=...`). `bindMultisig` is permissionless, so the signer only needs gas on the chain.
- `<chain>`: a name, a numeric chainId, or `all`. Each chain has fallback RPCs; override with `RPC_URL=...`.

## `check_coverage.js` — coverage audit (read-only)

For each chain reads every service's multisig `1..totalSupply()` (via Multicall3) and confirms it is claimed in
`mapMultisigServiceIds`; reports any still-unbound serviceIds. A service is covered when its multisig is `0`
(nothing to bind) or already claimed.

```bash
node check_coverage.js [chain]
```

After the back-fill, all supported chains report 0 unbound.
