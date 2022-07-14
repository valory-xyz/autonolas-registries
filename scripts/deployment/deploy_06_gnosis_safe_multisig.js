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
    const gnosisSafeL2Address = parsedData.gnosisSafeL2Address;
    const gnosisSafeProxyFactoryAddress = parsedData.gnosisSafeProxyFactoryAddress;
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
    console.log("6. EOA to deploy GnosisSafeMultisig");
    const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
    console.log("You are signing the following transaction: GnosisSafeMultisig.connect(EOA).deploy()");
    const gnosisSafeMultisig = await GnosisSafeMultisig.connect(EOA).deploy(gnosisSafeL2Address,
        gnosisSafeProxyFactoryAddress);
    const result = await gnosisSafeMultisig.deployed();

    // Transaction details
    console.log("Contract deployment: GnosisSafeMultisig");
    console.log("Contract address:", gnosisSafeMultisig.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_06.js --network " + providerName + " " + gnosisSafeMultisig.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.gnosisSafeMultisigImplementationAddress = gnosisSafeMultisig.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
