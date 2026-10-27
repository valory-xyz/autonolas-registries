# Pre-deployment steps
1. Release version of all contracts in `autonolas-registries` with the final bytecode;
2. Test the deployment flow with closest to real environment;
3. Contract Timelock is already deployed on the mainnet during the `autonolas-governance` deployment.

The steps of deploying the contracts in this repository are as follows:
# Deployment steps
## Steps for deploying original contracts.
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

## Steps for deploying supplemental contracts.
15. EOA to deploy OperatorWhitelist;
16. EOA to deploy ServiceRegistryTokenUtility;
17. EOA to deploy ServiceManagerToken pointed to ServiceRegistry, ServiceRegistryTokenUtility and OperatorWhitelist;
18. EOA to change the manager of ServiceRegistryTokenUtility to ServiceManagerToken calling `changeManager(ServiceManagerToken)`;
19. EOA to transfer ownership rights of ServiceRegistryTokenUtility to Timelock calling `changeOwner(Timelock)`;
20. EOA to transfer ownership rights of ServiceManagerToken to Timelock calling `changeOwner(Timelock)`.

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
