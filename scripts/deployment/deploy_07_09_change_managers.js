/*global process*/

const { expect } = require("chai");
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

    // Transaction signing and execution
    // 7. EOA to change the manager of ComponentRegistry and AgentRegistry to RegistriesManager via `changeManager(RegistriesManager)`;
    console.log("You are signing the following transaction: componentRegistry.connect(EOA).changeManager()");
    let result = await componentRegistry.connect(EOA).changeManager(registriesManagerAddress);
    // Transaction details
    console.log("Contract deployment: ComponentRegistry");
    console.log("Contract address:", componentRegistryAddress);
    console.log("Transaction:", result.hash);

    console.log("You are signing the following transaction: agentRegistry.connect(EOA).changeManager()");
    result = await agentRegistry.connect(EOA).changeManager(registriesManagerAddress);
    // Transaction details
    console.log("Contract deployment: AgentRegistry");
    console.log("Contract address:", agentRegistryAddress);
    console.log("Transaction:", result.hash);

    // 8. EOA to change the manager of ServiceRegistry to ServiceManager calling `changeManager(ServiceManager)`;
    console.log("You are signing the following transaction: serviceRegistry.connect(EOA).changeManager()");
    result = await serviceRegistry.connect(EOA).changeManager(serviceManagerAddress);
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

    // Data verification
    expect(await serviceRegistry.mapMultisigs(gnosisSafeMultisigImplementationAddress)).to.equal(true);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
