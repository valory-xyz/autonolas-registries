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
    const stakingTokenAddress = parsedData.stakingTokenAddress;
    const stakingNativeTokenAddress = parsedData.stakingNativeTokenAddress;
    const stakingVerifierAddress = parsedData.stakingVerifierAddress;

    let networkURL = parsedData.networkURL;
    if (providerName === "mainnet") {
        if (!process.env.ALCHEMY_API_KEY_MAINNET) {
            console.log("set ALCHEMY_API_KEY_MAINNET env variable");
        }
        networkURL += process.env.ALCHEMY_API_KEY_MAINNET;
    }
    if (providerName === "polygon") {
        if (!process.env.ALCHEMY_API_KEY_MATIC) {
            console.log("set ALCHEMY_API_KEY_MATIC env variable");
        }
        networkURL += process.env.ALCHEMY_API_KEY_MATIC;
    } else if (providerName === "polygonAmoy") {
        if (!process.env.ALCHEMY_API_KEY_AMOY) {
            console.log("set ALCHEMY_API_KEY_AMOY env variable");
            return;
        }
        networkURL += process.env.ALCHEMY_API_KEY_AMOY;
    }

    const provider = new ethers.providers.JsonRpcProvider(networkURL);
    const signers = await ethers.getSigners();

    let EOA;
    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Get the verifier contracts
    const stakingVerifier = await ethers.getContractAt("StakingVerifier", stakingVerifierAddress);

    // Gas pricing
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");

    // Transaction signing and execution
    console.log("20. You are signing the following transaction: StakingVerifier.connect(EOA).setImplementationsStatuses()");
    let result = await stakingVerifier.connect(EOA).setImplementationsStatuses([stakingTokenAddress, stakingNativeTokenAddress],
        [true, true], true, { gasPrice });
    // Transaction details
    console.log("Contract address:", stakingVerifierAddress);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
