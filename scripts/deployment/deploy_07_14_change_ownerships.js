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
    const registriesManagerAddress = parsedData.registriesManagerAddress;
    const serviceManagerAddress = parsedData.serviceManagerAddress;
    const gnosisSafeMultisigImplementationAddress = parsedData.gnosisSafeMultisigImplementationAddress;
    const timelockAddress = parsedData.timelockAddress;
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
    const registriesManager = await ethers.getContractAt("RegistriesManager", registriesManagerAddress);
    const serviceManager = await ethers.getContractAt("ServiceManager", serviceManagerAddress);

    // Transaction signing and execution
    // 7. EOA to change the manager of ComponentRegistry and AgentRegistry to RegistriesManager via `changeManager(RegistriesManager)`;
    console.log("You are signing the following transaction: componentRegistry.connect(EOA).changeManager()");
    let result = await componentRegistry.connect(EOA).changeManager(registriesManager.address);
    // Transaction details
    console.log("Contract deployment: ComponentRegistry");
    console.log("Contract address:", componentRegistryAddress);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: agentRegistry.connect(EOA).changeManager()");
    result = await agentRegistry.connect(EOA).changeManager(registriesManager.address);
    // Transaction details
    console.log("Contract deployment: AgentRegistry");
    console.log("Contract address:", agentRegistryAddress);
    console.log("Transaction:", result.hash);

    // 8. EOA to change the manager of ServiceRegistry to ServiceManager calling `changeManager(ServiceManager)`;
    console.log("You are signing the following transaction: serviceRegistry.connect(EOA).changeManager()");
    result = await serviceRegistry.connect(EOA).changeManager(serviceManager.address);
    // Transaction details
    console.log("Contract deployment: ServiceRegistry");
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);

    // 9. EOA to whitelist GnosisSafeMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeMultisig)`;
    console.log("You are signing the following transaction: serviceRegistry.connect(EOA).changeMultisigPermission()");
    result = await serviceRegistry.connect(EOA).changeMultisigPermission(gnosisSafeMultisigImplementationAddress, true);
    // Transaction details
    console.log("Contract deployment: ServiceRegistry");
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);

    // 10. EOA to transfer ownership rights of ComponentRegistry to Timelock calling `changeOwner(Timelock)`;
    console.log("You are signing the following transaction: componentRegistry.connect(EOA).changeOwner()");
    result = await componentRegistry.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract deployment: ComponentRegistry");
    console.log("Contract address:", componentRegistryAddress);
    console.log("Transaction:", result.hash);

    // 11. EOA to transfer ownership rights of AgentRegistry to Timelock calling `changeOwner(Timelock)`;
    console.log("You are signing the following transaction: agentRegistry.connect(EOA).changeOwner()");
    result = await agentRegistry.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract deployment: AgentRegistry");
    console.log("Contract address:", agentRegistryAddress);
    console.log("Transaction:", result.hash);

    // 12. EOA to transfer ownership rights of ServiceRegistry to Timelock calling `changeOwner(Timelock)`;
    console.log("You are signing the following transaction: serviceRegistry.connect(EOA).changeOwner()");
    result = await serviceRegistry.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract deployment: ServiceRegistry");
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);

    // 13. EOA to transfer ownership rights of RegistriesManager to Timelock calling `changeOwner(Timelock)`;
    console.log("You are signing the following transaction: registriesManager.connect(EOA).changeOwner()");
    result = await registriesManager.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract deployment: RegistriesManager");
    console.log("Contract address:", registriesManagerAddress);
    console.log("Transaction:", result.hash);

    // 14. EOA to transfer ownership rights of ServiceManager to Timelock calling `changeOwner(Timelock)`.
    console.log("You are signing the following transaction: serviceManager.connect(EOA).changeOwner()");
    result = await serviceManager.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract deployment: ServiceManager");
    console.log("Contract address:", serviceManagerAddress);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
