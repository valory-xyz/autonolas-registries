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
    const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;
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
    const serviceRegistryTokenUtility = await ethers.getContractAt("ServiceRegistryTokenUtility", serviceRegistryTokenUtilityAddress);
    const registriesManager = await ethers.getContractAt("RegistriesManager", registriesManagerAddress);
    const serviceManager = await ethers.getContractAt("ServiceManager", serviceManagerAddress);

    // Transaction signing and execution
    // 15. EOA to transfer ownership rights of ComponentRegistry to Timelock calling `changeOwner(Timelock)`;
    console.log("You are signing the following transaction: componentRegistry.connect(EOA).changeOwner()");
    let result = await componentRegistry.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract name: ComponentRegistry");
    console.log("Contract address:", componentRegistryAddress);
    console.log("Transaction:", result.hash);

    // 16. EOA to transfer ownership rights of AgentRegistry to Timelock calling `changeOwner(Timelock)`;
    console.log("You are signing the following transaction: agentRegistry.connect(EOA).changeOwner()");
    result = await agentRegistry.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract name: AgentRegistry");
    console.log("Contract address:", agentRegistryAddress);
    console.log("Transaction:", result.hash);

    // 17. EOA to transfer ownership rights of ServiceRegistry to Timelock calling `changeOwner(Timelock)`;
    console.log("You are signing the following transaction: serviceRegistry.connect(EOA).changeOwner()");
    result = await serviceRegistry.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract name: ServiceRegistry");
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);

    // 18. EOA to transfer ownership rights of ServiceRegistryTokenUtility to Timelock calling `changeOwner(Timelock)`;
    console.log("You are signing the following transaction: ServiceRegistryTokenUtility.connect(EOA).changeOwner()");
    result = await serviceRegistryTokenUtility.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract name: ServiceRegistryTokenUtility");
    console.log("Contract address:", serviceRegistryTokenUtilityAddress);
    console.log("Transaction:", result.hash);

    // 19. EOA to transfer ownership rights of RegistriesManager to Timelock calling `changeOwner(Timelock)`;
    console.log("You are signing the following transaction: registriesManager.connect(EOA).changeOwner()");
    result = await registriesManager.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract name: RegistriesManager");
    console.log("Contract address:", registriesManagerAddress);
    console.log("Transaction:", result.hash);

    // 20. EOA to transfer ownership rights of ServiceManager to Timelock calling `changeOwner(Timelock)`.
    console.log("You are signing the following transaction: serviceManager.connect(EOA).changeOwner()");
    result = await serviceManager.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract name: ServiceManager");
    console.log("Contract address:", serviceManagerAddress);
    console.log("Transaction:", result.hash);

    // Data verification
    expect(await componentRegistry.owner()).to.equal(timelockAddress);
    expect(await agentRegistry.owner()).to.equal(timelockAddress);
    expect(await serviceRegistry.owner()).to.equal(timelockAddress);
    expect(await registriesManager.owner()).to.equal(timelockAddress);
    expect(await serviceManager.owner()).to.equal(timelockAddress);

    console.log("Successful verification");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
