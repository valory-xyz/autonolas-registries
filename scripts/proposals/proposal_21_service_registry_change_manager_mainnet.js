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
    const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;
    const serviceRegistry = await ethers.getContractAt("ServiceRegistry", serviceRegistryAddress); 
    const serviceRegistryTokenUtility = await ethers.getContractAt("ServiceRegistryTokenUtility", serviceRegistryTokenUtilityAddress);

    // Proposal preparation
    console.log("Proposal 21. Change manager in ServiceRegistry and in serviceRegistryTokenUtility");
    const target1 = serviceRegistryAddress;
    const target2 = serviceRegistryTokenUtilityAddress;
    const values = [0,0];
    const callData1 = serviceRegistry.interface.encodeFunctionData("changeManager", [parsedData.serviceManagerProxyAddress]);
    const callData2 = serviceRegistryTokenUtility.interface.encodeFunctionData("changeManager", [parsedData.serviceManagerProxyAddress]);
    const description = "Change manager in ServiceRegistry and in serviceRegistryTokenUtility";

    // Proposal details
    console.log("targets:", [target1,target2]);
    console.log("value:", values);
    console.log("call data:", [callData1,callData2]);
    console.log("description:", description);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
