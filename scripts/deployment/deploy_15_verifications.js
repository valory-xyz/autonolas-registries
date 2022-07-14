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

    // Data verification
    expect(await serviceRegistry.mapMultisigs(gnosisSafeMultisigImplementationAddress)).to.equal(true);
    expect(await componentRegistry.owner()).to.equal(timelockAddress);
    expect(await agentRegistry.owner()).to.equal(timelockAddress);
    expect(await serviceRegistry.owner()).to.equal(timelockAddress);
    expect(await registriesManager.owner()).to.equal(timelockAddress);
    expect(await serviceManager.owner()).to.equal(timelockAddress);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
