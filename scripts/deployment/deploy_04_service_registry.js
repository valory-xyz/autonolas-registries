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
    const serviceRegistryName = parsedData.serviceRegistryName;
    const serviceRegistrySymbol = parsedData.serviceRegistrySymbol;
    const baseURI = parsedData.baseURI;
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
    console.log("4. EOA to deploy ServiceRegistry");
    const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
    console.log("You are signing the following transaction: ServiceRegistry.connect(EOA).deploy()");
    const serviceRegistry = await ServiceRegistry.connect(EOA).deploy(serviceRegistryName, serviceRegistrySymbol,
        baseURI, agentRegistryAddress);
    const result = await serviceRegistry.deployed();

    // Transaction details
    console.log("Contract deployment: ServiceRegistry");
    console.log("Contract address:", serviceRegistry.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_04_service_registry.js --network " + providerName + " " + serviceRegistry.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.serviceRegistryAddress = serviceRegistry.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
