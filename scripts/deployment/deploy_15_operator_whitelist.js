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
    console.log("15. EOA to deploy OperatorWhitelist");
    const OperatorWhitelist = await ethers.getContractFactory("OperatorWhitelist");
    console.log("You are signing the following transaction: OperatorWhitelist.connect(EOA).deploy(serviceRegistryAddress)");
    const operatorWhitelist = await OperatorWhitelist.connect(EOA).deploy(serviceRegistryAddress);
    const result = await operatorWhitelist.deployed();

    // Transaction details
    console.log("Contract deployment: OperatorWhitelist");
    console.log("Contract address:", operatorWhitelist.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // If on goerli, wait for half a minute for the transaction completion
    if (providerName === "goerli") {
        await new Promise(r => setTimeout(r, 30000));
    }

    // Writing updated parameters back to the JSON file
    parsedData.operatorWhitelistAddress = operatorWhitelist.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_15_operator_whitelist.js --network " + providerName + " " + operatorWhitelist.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
