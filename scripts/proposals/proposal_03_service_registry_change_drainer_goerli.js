/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    let parsedData = JSON.parse(dataFromJSON);

    const signers = await ethers.getSigners();

    // EOA address
    const EOA = signers[0];
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Get all the necessary contract addresses
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const treasuryAddress = parsedData.treasuryAddress;

    const serviceRegistry = await ethers.getContractAt("ServiceRegistry", serviceRegistryAddress);

    // Proposal preparation
    console.log("Proposal 3. ServiceRegistry to change drainer calling `changeDrainer(treasuryAddress)`");
    const targets = [serviceRegistryAddress];
    const values = [0];
    const callDatas = [serviceRegistry.interface.encodeFunctionData("changeDrainer", [treasuryAddress])];
    const description = "Change ServiceRegistry drainer";

    // Proposal details
    console.log("targets:", targets);
    console.log("values:", values);
    console.log("call datas:", callDatas);
    console.log("description:", description);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
