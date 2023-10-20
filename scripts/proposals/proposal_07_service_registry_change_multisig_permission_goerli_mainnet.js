/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "globals.json";
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
    console.log("Proposal 7. Change GnosisSafeSameAddressMultisig implementation addresses in ServiceRegistry");
    const targets = [serviceRegistryAddress, serviceRegistryAddress];
    const values = [0, 0];
    let oldMultisig;
    if (providerName === "mainnet") {
        oldMultisig = "0x26Ea2dC7ce1b41d0AD0E0521535655d7a94b684c";
    } else if (providerName === "goerli") {
        oldMultisig = "0x92499E80f50f06C4078794C179986907e7822Ea1";
    } else {
        console.log("Unknown network provider", providerName);
        return;
    }
    const callDatas = [serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", [oldMultisig, false]),
        serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", [parsedData.gnosisSafeSameAddressMultisigImplementationAddress, true])];
    const description = "Change GnosisSafeSameAddressMultisig implementation addresses in ServiceRegistry";

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
