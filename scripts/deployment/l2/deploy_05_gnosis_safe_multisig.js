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
    const gasPriceInGwei = parsedData.gasPriceInGwei;
    let EOA;

    let networkURL;
    if (providerName === "polygon") {
        if (!process.env.ALCHEMY_API_KEY_MATIC) {
            console.log("set ALCHEMY_API_KEY_MATIC env variable");
        }
        networkURL = "https://polygon-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MATIC;
    } else if (providerName === "polygonMumbai") {
        if (!process.env.ALCHEMY_API_KEY_MUMBAI) {
            console.log("set ALCHEMY_API_KEY_MUMBAI env variable");
            return;
        }
        networkURL = "https://polygon-mumbai.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MUMBAI;
    } else if (providerName === "gnosis") {
        if (!process.env.GNOSISSCAN_API_KEY) {
            console.log("set GNOSISSCAN_API_KEY env variable");
            return;
        }
        networkURL = "https://rpc.gnosischain.com";
    } else if (providerName === "chiado") {
        networkURL = "https://rpc.chiadochain.net";
    } else if (providerName === "arbitrumOne") {
        networkURL = "https://arb1.arbitrum.io/rpc";
    } else if (providerName === "arbitrumSepolia") {
        networkURL = "https://sepolia-rollup.arbitrum.io/rpc";
    } else {
        console.log("Unknown network provider", providerName);
        return;
    }

    const provider = new ethers.providers.JsonRpcProvider(networkURL);
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
    console.log("5. EOA to deploy GnosisSafeMultisig");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
    console.log("You are signing the following transaction: GnosisSafeMultisig.connect(EOA).deploy()");
    const gnosisSafeMultisig = await GnosisSafeMultisig.connect(EOA).deploy(parsedData.gnosisSafeAddress, parsedData.gnosisSafeProxyFactoryAddress, { gasPrice });
    const result = await gnosisSafeMultisig.deployed();

    // Transaction details
    console.log("Contract deployment: GnosisSafeMultisig");
    console.log("Contract address:", gnosisSafeMultisig.address);
    console.log("Transaction:", result.deployTransaction.hash);
    // Wait half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.gnosisSafeMultisigImplementationAddress = gnosisSafeMultisig.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --contract contracts/multisigs/GnosisSafeMultisig.sol:GnosisSafeMultisig --constructor-args scripts/deployment/l2/verify_05_gnosis_safe_multisig.js --network " + providerName + " " + gnosisSafeMultisig.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });