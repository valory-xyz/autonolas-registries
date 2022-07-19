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
    const componentRegistryName = parsedData.componentRegistryName;
    const componentRegistrySymbol = parsedData.componentRegistrySymbol;
    const baseURI = parsedData.baseURI;
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
    console.log("1. EOA to deploy ComponentRegistry");
    const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
    console.log("You are signing the following transaction: ComponentRegistry.connect(EOA).deploy()");
    const componentRegistry = await ComponentRegistry.connect(EOA).deploy(componentRegistryName, componentRegistrySymbol,
        baseURI);
    const result = await componentRegistry.deployed();

    // Transaction details
    console.log("Contract deployment: ComponentRegistry");
    console.log("Contract address:", componentRegistry.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_01_component_registry.js --network " + providerName + " " + componentRegistry.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.componentRegistryAddress = componentRegistry.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
