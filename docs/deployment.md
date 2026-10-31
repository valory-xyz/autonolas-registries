# ServiceManager and Safe wrapper replacements

Use this procedure for replacements on an existing deployment, before the historical full-deployment
steps below. Keep the current manager proxy, registries, token utility and service Safes.

Select the chain configuration and reviewed build, enable `contractVerification`, and record the old
proxy implementation/version and wrapper address. Deploy only the replacement required:

| Contract / chain | Deployment command | Updated globals |
|---|---|---|
| ServiceManager / Ethereum | `bash scripts/deployment/deploy_07_service_manager.sh mainnet` | `scripts/deployment/globals_mainnet.json` |
| ServiceManager / L2 | `bash scripts/deployment/l2/deploy_04_service_manager.sh <chain>_mainnet` | `scripts/deployment/l2/globals_<chain>_mainnet.json` |
| GnosisSafeMultisig / Ethereum | Copy the current Ethereum globals to root `globals.json`, then run `npx hardhat run scripts/deployment/deploy_09a_gnosis_safe_multisig.js --network mainnet` | Root `globals.json`; copy the updated contents back to `scripts/deployment/globals_mainnet.json` before auditing |
| GnosisSafeMultisig / L2 | `bash scripts/deployment/l2/deploy_06a_gnosis_safe_multisig.sh <chain>_mainnet` | `scripts/deployment/l2/globals_<chain>_mainnet.json` |

Use `forge build` for shell deployments and `npx hardhat compile` for Hardhat deployments from the
reviewed revision. Confirm explorer verification for the deployed address before governance.

For a replacement ServiceManager or GnosisSafeMultisig, audit the candidate from the updated globals
before governance activation. Run commands from the repository root. Keep `docs/configuration.json`
on the live contracts for the existing audit.
Use the reviewed revision and the **same artifact/build settings used for deployment** (Forge or Hardhat);
compile it first. The candidate audit uses read-only `eth_call` to simulate constructor execution and
compares the complete runtime, including constructor bindings and metadata, at one recorded block.
No signer or private key is used. Mismatches report expected/observed values; unreadable checks are
labelled `check unavailable`. Both count as failures in the final summary. Remaining checks continue,
then any failures cause a nonzero exit. Invalid initial
inputs or a wrong RPC chain stop the audit before contract checks.

```bash
# Set AUDIT_RPC_URL to the intended chain's RPC endpoint in your environment.
node scripts/audit_chains/audit_contracts_setup.js --candidate ServiceManager \
  --globals scripts/deployment/globals_mainnet.json --artifact out/ServiceManager.sol/ServiceManager.json
node scripts/audit_chains/audit_contracts_setup.js --candidate GnosisSafeMultisig \
  --globals scripts/deployment/globals_mainnet.json --artifact artifacts/contracts/multisigs/GnosisSafeMultisig.sol/GnosisSafeMultisig.json
```

Select the chain's globals/artifact paths as appropriate. The manager audit always checks the proxy
implementation/version against the new values; use the same command before and after governance.
For wrapper permission checks, append `--activated --previous-wrapper <old-address>` to the wrapper
command **both before and after governance**. Despite its name, this flag only selects the expected
permission checks; it performs no activation. Without it, the wrapper candidate audit checks only code
and constructor bindings. Record the old proxy implementation/version and wrapper address before deployment overwrites globals.

**Deploy and verify → audit → consumer readiness → governance → audit again.** The new candidate's
code, version and constructor bindings must already match before governance. These are the specific
state differences that may remain while the corresponding governance actions are outstanding:

| Check | Expected (after governance) | What we will see before governance |
|---|---|---|
| Manager proxy `getImplementation()` | New `globals.serviceManagerAddress` | Recorded old implementation |
| Manager proxy `VERSION()` | `1.3.0` | Old version, if different |
| Registry `mapMultisigs(newWrapper)` | `true` | `false` until the grant executes |
| Registry `mapMultisigs(previousWrapper)` | `false` | `true` until the revoke executes |

These differences are reported as mismatches and make the candidate audit exit nonzero after all checks.
They are acceptable before governance only when they match the recorded old state and planned actions;
none may remain after those actions execute. A code/binding mismatch or unreadable check is not explained
by pending governance. The existing general state audit also checks deprecated adapters: an enabled
adapter is an outstanding mismatch until its planned revoke executes, not a candidate-deployment failure.

Governance calls `changeImplementation(newImplementation)` through the existing manager proxy.
For wrappers, governance calls `changeMultisigPermission(newWrapper, true)` on the registry before
`changeMultisigPermission(previousWrapper, false)`.
Only on Arbitrum/Robinhood, confirm the grant executed on L2 before the revoke; L1 submission alone is insufficient.
Rerun the candidate checks and existing state audit after execution to confirm owners, manager/utility
bindings and the complete multisig permission set, including deprecated-adapter revocations.

For deployment, enable `contractVerification` and require successful explorer verification against the
reviewed build before governance. The manager and L2 wrapper shell scripts wait for verification and
exit nonzero on failure. If verification fails after deployment, verify the already-deployed address;
do not rerun deployment just to retry verification. Candidate audit regression tests:
`npx hardhat test test/DeploymentCandidateAudit.js`.

# Initial full-protocol deployment

The historical steps below describe deployment from scratch. For replacements on an existing
deployment, follow [ServiceManager and Safe wrapper replacements](#servicemanager-and-safe-wrapper-replacements) above.

## Pre-deployment steps
1. Release version of all contracts in `autonolas-registries` with the final bytecode;
2. Test the deployment flow with closest to real environment;
3. Contract Timelock is already deployed on the mainnet during the `autonolas-governance` deployment.

The steps of deploying the contracts in this repository are as follows:
## Deployment steps

### Steps for deploying original contracts.
1. EOA to deploy ComponentRegistry;
2. EOA to deploy AgentRegistry pointed to ComponentRegistry;
3. EOA to deploy RegistriesManager pointed to ComponentRegistry and AgentRegistry;
4. EOA to deploy ServiceRegistry;
5. EOA to deploy ServiceManager pointed to ServiceRegistry;
6. EOA to deploy GnosisSafeMultisig;
7. EOA to change the manager of ServiceRegistry to ServiceManager calling `changeManager(ServiceManager)`;
8. EOA to change the manager of ComponentRegistry and AgentRegistry to RegistriesManager via `changeManager(RegistriesManager)`;
9. EOA to whitelist GnosisSafeMultisigs in ServiceRegistry via `changeMultisigPermission(GnosisSafeMultisig)`;
10. EOA to transfer ownership rights of ComponentRegistry to Timelock calling `changeOwner(Timelock)`;
11. EOA to transfer ownership rights of AgentRegistry to Timelock calling `changeOwner(Timelock)`;
12. EOA to transfer ownership rights of ServiceRegistry to Timelock calling `changeOwner(Timelock)`;
13. EOA to transfer ownership rights of RegistriesManager to Timelock calling `changeOwner(Timelock)`;
14. EOA to transfer ownership rights of ServiceManager to Timelock calling `changeOwner(Timelock)`.

### Steps for deploying supplemental contracts.
15. EOA to deploy OperatorWhitelist;
16. EOA to deploy ServiceRegistryTokenUtility;
17. EOA to deploy ServiceManagerToken pointed to ServiceRegistry, ServiceRegistryTokenUtility and OperatorWhitelist;
18. EOA to change the manager of ServiceRegistryTokenUtility to ServiceManagerToken calling `changeManager(ServiceManagerToken)`;
19. EOA to transfer ownership rights of ServiceRegistryTokenUtility to Timelock calling `changeOwner(Timelock)`;
20. EOA to transfer ownership rights of ServiceManagerToken to Timelock calling `changeOwner(Timelock)`.

# Manual permission review
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
