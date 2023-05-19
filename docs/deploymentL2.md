# Deployment of the light protocol contracts
## Steps for deploying original contracts.
1. EOA to deploy ServiceRegistry;
2. EOA to deploy ServiceManager pointed to ServiceRegistry;
3. EOA to deploy GnosisSafeMultisig;
4. EOA to deploy GnosisSafeMultisigSameAddress;
5. EOA to change the manager of ServiceRegistry to ServiceManager calling `changeManager(ServiceManager)`;
6. EOA to whitelist GnosisSafeMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeMultisig)`;
7. EOA to whitelist GnosisSafeSameAddressMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeSameAddressMultisig)`;
8. EOA to transfer ownership rights of ServiceRegistry to BridgeMediator calling `changeOwner(BridgeMediator)`;
9. EOA to transfer ownership rights of ServiceManager to BridgeMediator calling `changeOwner(BridgeMediator)`.

## Steps for deploying supplemental contracts.
10. EOA to deploy OperatorWhitelist;
11. EOA to deploy ServiceRegistryTokenUtility;
12. EOA to deploy ServiceManagerToken pointed to ServiceRegistry, ServiceRegistryTokenUtility and OperatorWhitelist;
13. EOA to change the manager of ServiceRegistryTokenUtility to ServiceManagerToken calling `changeManager(ServiceManagerToken)`;
14. EOA to transfer ownership rights of ServiceRegistryTokenUtility to BridgeMediator calling `changeOwner(BridgeMediator)`;
15. EOA to transfer ownership rights of ServiceManagerToken to BridgeMediator calling `changeOwner(BridgeMediator)`.