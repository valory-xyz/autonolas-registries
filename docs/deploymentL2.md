# Deployment of the light protocol contracts

For ServiceManager and Safe-wrapper replacements on existing deployments, follow the shared
[replacement deployment and audit procedure](deployment.md#servicemanager-and-safe-wrapper-replacements),
including L2 scripts, expected pre-governance mismatches and checks after bridge execution.
The original deployment sequence below is not the replacement flow.

## StakingToken implementation

This deploys an implementation; programme creation and migration are separate. Reuse the existing
factory and verifier. Select and validate the verifier limits before deployment;
keep the other limits unchanged unless governance explicitly changes them.

1. Select `scripts/deployment/l2/globals_<chain>_mainnet.json` (`eth_mainnet` for Ethereum); confirm
   `chainId`, RPC and verification settings. Build the reviewed revision with `forge build`.
2. Run `bash scripts/deployment/l2/deploy_16_service_staking_token.sh <chain>_mainnet` with
   `contractVerification` enabled. It takes no constructor arguments, writes `stakingTokenAddress`,
   and waits for explorer verification. Retry failed verification against that address, without redeploying.
3. Set `AUDIT_RPC_URL` and audit the deployed code and version; Ethereum example:

   ```bash
   node scripts/audit_chains/audit_contracts_setup.js --candidate StakingToken \
     --globals scripts/deployment/l2/globals_eth_mainnet.json --artifact out/StakingToken.sol/StakingToken.json
   ```

   The candidate must match the reviewed build and report `VERSION() == "0.4.0"`. Programme bindings
   are set when creating instances, so they are not checked on the uninitialized implementation.
4. Governance applies the validated limits before enabling the implementation, or first in the same
   atomic batch; then enables the new token implementation and disables the selected superseded token
   implementations in `setImplementationsStatuses`. Do not include the native-token implementation in
   this replacement. The existing JavaScript helper 20 sends transactions directly and includes both
   types; its call is not the governance payload for this procedure.
5. Rerun the candidate audit and existing state audit. Read the verifier's individual implementation
   permissions and all four limits against the approved values; the existing state audit does not check
   individual implementation permissions. Prepare programme-specific checker, consumer and migration
   readiness separately before launching new programmes.

For checkpoint gas validation, reuse `test/ServiceStakingGasLimit.t.sol` with Foundry v1.7.1,
Solidity 0.8.30 and the repository build settings:

```bash
CHECKPOINT_SERVICE_COUNT=44 CHECKPOINT_GAS_BUDGET=15000000 \
  forge test --isolate --match-contract StakingTokenCheckpointGas -vv
```

`--isolate` is required for cold transaction state. Set `CHECKPOINT_EVM_VERSION=prague` or `osaka`
to execute the same reviewed bytecode under either rule set without changing compilation.
The budget includes intrinsic gas and bounds the
call through the real staking proxy. The synthetic checker returns four counters and consumes nearly
the full per-call allowance; tests cover first/steady rewards, failed reads/recovery, failed ratios/eviction
and refill re-baselining. Defaults are 44 services and a 15,000,000-gas budget, leaving more than 10%
below the [EIP-7825 transaction cap](https://eips.ethereum.org/EIPS/eip-7825). A 50-service comparison
at 16,777,216 gas fails the first-reward and reserve-exhaustion cases. Change the environment
variables to compare counts or diagnose with a higher budget; a diagnostic budget is not a deployment
approval. Validate each destination chain's transaction limit, execution rules and required margin before
selecting a service limit. Passing these synthetic scenarios does not validate every programme checker.

## Steps for deploying original contracts.
1. EOA to deploy ServiceRegistry;
2. EOA to deploy OperatorWhitelist;
3. EOA to deploy ServiceRegistryTokenUtility;
4. EOA to deploy ServiceManagerToken pointed to ServiceRegistry, ServiceRegistryTokenUtility and OperatorWhitelist;
5. EOA to deploy GnosisSafeMultisig;
6. Skipped (no script): the deprecated GnosisSafeSameAddressMultisig is no longer deployed;
7. EOA to change the manager of ServiceRegistry to ServiceManagerToken calling `changeManager(ServiceManagerToken)`;
8. EOA to change the manager of ServiceRegistryTokenUtility to ServiceManagerToken calling `changeManager(ServiceManagerToken)`;
9. EOA to whitelist GnosisSafeMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeMultisig)`;
10. Skipped (no script): the deprecated GnosisSafeSameAddressMultisig is no longer whitelisted;
11. EOA to change the drainer of ServiceRegistry to BridgeMediator calling `changeDrainer(BridgeMediator)`;
12. EOA to change the drainer of ServiceRegistryTokenUtility to BridgeMediator calling `changeDrainer(BridgeMediator)`;
13. EOA to transfer ownership rights of ServiceRegistry to BridgeMediator calling `changeOwner(BridgeMediator)`;
14. EOA to transfer ownership rights of ServiceRegistryTokenUtility to BridgeMediator calling `changeOwner(BridgeMediator)`;
15. EOA to transfer ownership rights of ServiceManagerToken to BridgeMediator calling `changeOwner(BridgeMediator)`.

## Manual permission review
`GnosisSafeSameAddressMultisig` and `PolySafeSameAddressMultisig` are deprecated. The deployment scripts do not deploy them
and do not whitelist them; they still whitelist the supported multisig implementations. Running the scripts does not change,
and does not check, the existing `ServiceRegistry` permission of any deprecated adapter that is already deployed.

The permission of the deprecated adapters is therefore reviewed manually, at two points:
1. After deployment: the deployment operator reviews the deprecated-adapter permissions on the chain that was deployed or changed;
2. Before a governance proposal that affects multisig permissions proceeds: the proposal reviewer repeats the review, since the on-chain state may have changed since the previous one.

For each review, read `mapMultisigs(adapter)` on the `ServiceRegistry` for every deployed deprecated adapter across the current chain inventory
(`docs/configuration.json`), including `PolySafeSameAddressMultisig` where it is deployed. Record the chain, registry, adapter, block, result and
decision in a private internal review record. Do not put this record in a public proposal or in this repository.

This review is a manual procedure. The deployment scripts do not enforce it, and deployment completion does not replace it.
The standalone audit script `scripts/audit_chains/audit_contracts_setup.js` can assist the review. It is not part of deployment.
