# Deployment of the light protocol contracts
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
