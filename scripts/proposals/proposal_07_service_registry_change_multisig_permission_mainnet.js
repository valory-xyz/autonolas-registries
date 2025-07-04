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
    console.log("Proposal 7. Change multisig implementation statuses in ServiceRegistry");
    const targets = [serviceRegistryAddress, serviceRegistryAddress];
    const values = [0, 0];
    const callDatas = [serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", [parsedData.recoveryModuleAddress, true]),
        serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", [parsedData.safeMultisigWithRecoveryModuleAddress, true])];
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
