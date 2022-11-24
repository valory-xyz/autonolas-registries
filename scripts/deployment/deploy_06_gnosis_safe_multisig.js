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

    // Multisig implementation contract parameters supplied via multisigImplementation.json file
    const multisigDataFromJSON = fs.readFileSync("multisigImplementation.json", "utf8");
    const parsedMultisigData = JSON.parse(multisigDataFromJSON);
    let multisigImplementationContractName = parsedMultisigData.multisigContractName;

    // Transaction signing and execution
    console.log("6. EOA to deploy " + multisigImplementationContractName);
    const GnosisSafeMultisig = await ethers.getContractFactory(multisigImplementationContractName);
    console.log("You are signing the following transaction: " + multisigImplementationContractName + ".connect(EOA).deploy()");

    // Verify the construct parameters and add them here, if needed
    const gnosisSafeMultisig = await GnosisSafeMultisig.connect(EOA).deploy();
    const result = await gnosisSafeMultisig.deployed();

    // Transaction details
    console.log("Contract deployment: " + multisigImplementationContractName);
    console.log("Contract address:", gnosisSafeMultisig.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        let verifyString = "npx hardhat verify";
        // Supply the verifyScript as a .js file name, if verification needs to account for constructor arguments
        if (parsedMultisigData.verifyScript) {
            verifyString += " --constructor-args " + parsedMultisigData.verifyScript;
        }
        verifyString += " --network " + providerName + " " + gnosisSafeMultisig.address;
        execSync(verifyString, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    let multisigJSONName = multisigImplementationContractName.charAt(0).toLowerCase() +
        multisigImplementationContractName.slice(1) + "Address";
    parsedData[multisigJSONName] = gnosisSafeMultisig.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
