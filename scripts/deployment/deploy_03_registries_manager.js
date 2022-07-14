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

    // Transaction signing and execution
    console.log("3. EOA to deploy RegistriesManager pointed to ComponentRegistry and AgentRegistry");
    const RegistriesManager = await ethers.getContractFactory("RegistriesManager");
    console.log("You are signing the following transaction: RegistriesManager.connect(EOA).deploy()");
    const registriesManager = await RegistriesManager.connect(EOA).deploy(componentRegistryAddress, agentRegistryAddress);
    const result = await registriesManager.deployed();

    // Transaction details
    console.log("Contract deployment: RegistriesManager");
    console.log("Contract address:", registriesManager.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_03_registries_manager.js --network " + providerName + " " + registriesManager.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.registriesManagerAddress = registriesManager.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
