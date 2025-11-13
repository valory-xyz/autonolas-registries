/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "scripts/deployment/globals_mainnet.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);
    const providerName = parsedData.providerName;

    const signers = await ethers.getSigners();

    // EOA address
    const EOA = signers[0];
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Get all the necessary contract addresses
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;

    const serviceRegistry = await ethers.getContractAt("ServiceRegistry", serviceRegistryAddress);

    // Proposal preparation
    console.log("Proposal 21. Change manager in ServiceRegistry");
    const targets = serviceRegistryAddress;
    const values = 0;
    // TODO: replace serviceManagerTokenAddress with serviceManagerProxyAddress
    const callDatas = serviceRegistry.interface.encodeFunctionData("changeManager", parsedData.serviceManagerTokenAddress);
    const description = "Change manager in ServiceRegistry";

    // Proposal details
    console.log("target:", target);
    console.log("value:", value);
    console.log("call data:", callData);
    console.log("description:", description);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
