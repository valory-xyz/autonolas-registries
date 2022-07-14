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
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
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
    console.log("5. EOA to deploy ServiceManager");
    const ServiceManager = await ethers.getContractFactory("ServiceManager");
    console.log("You are signing the following transaction: ServiceManager.connect(EOA).deploy()");
    const serviceManager = await ServiceManager.connect(EOA).deploy(serviceRegistryAddress);
    const result = await serviceManager.deployed();

    // Transaction details
    console.log("Contract deployment: ServiceManager");
    console.log("Contract address:", serviceManager.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_05_service_manager.js --network " + providerName + " " + serviceManager.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.serviceManagerAddress = serviceManager.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
