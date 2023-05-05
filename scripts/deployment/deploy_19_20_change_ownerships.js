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
    const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;
    const serviceManagerTokenAddress = parsedData.serviceManagerTokenAddress;
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
    const serviceRegistryTokenUtility = await ethers.getContractAt("ServiceRegistryTokenUtility", serviceRegistryTokenUtilityAddress);
    const serviceManagerToken = await ethers.getContractAt("ServiceManagerToken", serviceManagerTokenAddress);

    // Transaction signing and execution
    // 19. EOA to transfer ownership rights of ServiceRegistryTokenUtility to Timelock calling `changeOwner(Timelock)`;
    console.log("You are signing the following transaction: ServiceRegistryTokenUtility.connect(EOA).changeOwner()");
    let result = await serviceRegistryTokenUtility.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract address:", serviceRegistryTokenUtilityAddress);
    console.log("Transaction:", result.hash);

    // EOA to transfer ownership rights of ServiceManagerToken to Timelock calling `changeOwner(Timelock)`.
    console.log("You are signing the following transaction: serviceManagerToken.connect(EOA).changeOwner()");
    result = await serviceManagerToken.connect(EOA).changeOwner(timelockAddress);
    // Transaction details
    console.log("Contract address:", serviceManagerTokenAddress);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
