# Deployment of the light protocol contracts
## Steps for deploying original contracts.
1. EOA to deploy ServiceRegistry;
2. EOA to deploy OperatorWhitelist;
3. EOA to deploy ServiceRegistryTokenUtility;
4. EOA to deploy ServiceManagerToken pointed to ServiceRegistry, ServiceRegistryTokenUtility and OperatorWhitelist;
5. EOA to deploy GnosisSafeMultisig;
6. EOA to deploy GnosisSafeSameAddressMultisig;
7. EOA to change the manager of ServiceRegistry to ServiceManagerToken calling `changeManager(ServiceManagerToken)`;
8. EOA to change the manager of ServiceRegistryTokenUtility to ServiceManagerToken calling `changeManager(ServiceManagerToken)`;
9. EOA to whitelist GnosisSafeMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeMultisig)`;
10. EOA to whitelist GnosisSafeSameAddressMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeSameAddressMultisig)`;
11. EOA to change the drainer of ServiceRegistry to BridgeMediator calling `changeManager(BridgeMediator)`;
12. EOA to change the drainer of ServiceRegistryTokenUtility to BridgeMediator calling `changeManager(BridgeMediator)`;
13. EOA to transfer ownership rights of ServiceRegistry to BridgeMediator calling `changeOwner(BridgeMediator)`;
14. EOA to transfer ownership rights of ServiceRegistryTokenUtility to BridgeMediator calling `changeOwner(BridgeMediator)`;
15. EOA to transfer ownership rights of ServiceManagerToken to BridgeMediator calling `changeOwner(BridgeMediator)`.