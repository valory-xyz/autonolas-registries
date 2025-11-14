/*global process*/

const { ethers } = require("hardhat");
const { LedgerSigner } = require("@anders-t/ethers-ledger");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const useLedger = parsedData.useLedger;
    const derivationPath = parsedData.derivationPath;
    const providerName = parsedData.providerName;
    const componentRegistryAddress = parsedData.componentRegistryAddress;
    const agentRegistryAddress = parsedData.agentRegistryAddress;
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;
    const registriesManagerAddress = parsedData.registriesManagerAddress;
    const serviceManagerProxyAddress = parsedData.serviceManagerProxyAddress;
    const gnosisSafeMultisigImplementationAddress = parsedData.gnosisSafeMultisigImplementationAddress;
    const gnosisSafeSameAddressMultisigImplementationAddress = parsedData.gnosisSafeSameAddressMultisigImplementationAddress;
    let EOA;

    const provider = await ethers.providers.getDefaultProvider(providerName);
    const signers = await ethers.getSigners();

    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Get all the contracts
    const componentRegistry = await ethers.getContractAt("ComponentRegistry", componentRegistryAddress);
    const agentRegistry = await ethers.getContractAt("AgentRegistry", agentRegistryAddress);
    const serviceRegistry = await ethers.getContractAt("ServiceRegistry", serviceRegistryAddress);
    const serviceRegistryTokenUtility = await ethers.getContractAt("ServiceRegistryTokenUtility", serviceRegistryTokenUtilityAddress);

    // Transaction signing and execution
    // 10. EOA to change the manager of ComponentRegistry and AgentRegistry to RegistriesManager via `changeManager(RegistriesManager)`;
    console.log("You are signing the following transaction: componentRegistry.connect(EOA).changeManager()");
    let result = await componentRegistry.connect(EOA).changeManager(registriesManagerAddress);
    // Transaction details
    console.log("Contract name: ComponentRegistry");
    console.log("Contract address:", componentRegistryAddress);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: agentRegistry.connect(EOA).changeManager()");
    result = await agentRegistry.connect(EOA).changeManager(registriesManagerAddress);
    // Transaction details
    console.log("Contract name: AgentRegistry");
    console.log("Contract address:", agentRegistryAddress);
    console.log("Transaction:", result.hash);

    // 11. EOA to change the manager of ServiceRegistry to ServiceManager calling `changeManager(ServiceManager)`;
    console.log("You are signing the following transaction: serviceRegistry.connect(EOA).changeManager()");
    result = await serviceRegistry.connect(EOA).changeManager(serviceManagerProxyAddress);
    // Transaction details
    console.log("Contract name: ServiceRegistry");
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);

    // 12. EOA to change the manager of ServiceRegistryTokenUtility to ServiceManager calling `changeManager(ServiceManager)`;
    console.log("You are signing the following transaction: serviceRegistryTokenUtility.connect(EOA).changeManager(serviceManagerProxyAddress)");
    result = await serviceRegistryTokenUtility.connect(EOA).changeManager(serviceManagerProxyAddress);
    // Transaction details
    console.log("Contract name: ServiceRegistryTokenUtility");
    console.log("Contract address:", serviceRegistryTokenUtilityAddress);
    console.log("Transaction:", result.hash);

    // 13. EOA to whitelist GnosisSafeMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeMultisig)`;
    console.log("9. You are signing the following transaction: serviceRegistry.connect(EOA).changeMultisigPermission()");
    result = await serviceRegistry.connect(EOA).changeMultisigPermission(gnosisSafeMultisigImplementationAddress, true);
    // Transaction details
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);

    // 14. EOA to whitelist GnosisSafeSameAddressMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeSameAddressMultisig)`;
    console.log("10. You are signing the following transaction: serviceRegistry.connect(EOA).changeMultisigPermission()");
    result = await serviceRegistry.connect(EOA).changeMultisigPermission(gnosisSafeSameAddressMultisigImplementationAddress, true);
    // Transaction details
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
