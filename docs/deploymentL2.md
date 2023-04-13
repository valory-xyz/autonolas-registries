The steps of deploying the light protocol contracts are as follows:

1. EOA to deploy ServiceRegistry;
2. EOA to deploy ServiceManager pointed to ServiceRegistry;
3. EOA to deploy GnosisSafeMultisig;
4. EOA to deploy GnosisSafeMultisigSameAddress;
5. EOA to change the manager of ServiceRegistry to ServiceManager calling `changeManager(ServiceManager)`;
6. EOA to whitelist GnosisSafeMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeMultisig)`;
7. EOA to whitelist GnosisSafeSameAddressMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeSameAddressMultisig)`;
8. EOA to transfer ownership rights of ServiceRegistry to FxGovernorTunnel calling `changeOwner(FxGovernorTunnel)`;
9. EOA to transfer ownership rights of ServiceManager to FxGovernorTunnel calling `changeOwner(FxGovernorTunnel)`.