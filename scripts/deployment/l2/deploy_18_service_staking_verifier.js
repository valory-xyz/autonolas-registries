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
    const olasAddress = parsedData.olasAddress;
    const minStakingDepositLimit = parsedData.minStakingDepositLimit;
    const timeForEmissionsLimit = parsedData.timeForEmissionsLimit;
    const numServicesLimit = parsedData.numServicesLimit;
    const apyLimit = parsedData.apyLimit;
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;

    let networkURL = parsedData.networkURL;
    if (providerName === "mainnet") {
        if (!process.env.ALCHEMY_API_KEY_MAINNET) {
            console.log("set ALCHEMY_API_KEY_MAINNET env variable");
        }
        networkURL += process.env.ALCHEMY_API_KEY_MAINNET;
    } else if (providerName === "sepolia") {
        if (!process.env.ALCHEMY_API_KEY_SEPOLIA) {
            console.log("set ALCHEMY_API_KEY_SEPOLIA env variable");
            return;
        }
        networkURL += process.env.ALCHEMY_API_KEY_SEPOLIA;
    } else if (providerName === "polygon") {
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

    // Transaction signing and execution
    console.log("18. EOA to deploy StakingVerifier");
    const StakingVerifier = await ethers.getContractFactory("StakingVerifier");
    console.log("You are signing the following transaction: StakingVerifier.connect(EOA).deploy()");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const stakingVerifier = await StakingVerifier.connect(EOA).deploy(olasAddress, serviceRegistryAddress,
        serviceRegistryTokenUtilityAddress, minStakingDepositLimit, timeForEmissionsLimit, numServicesLimit, apyLimit, { gasPrice });
    const result = await stakingVerifier.deployed();

    // Transaction details
    console.log("Contract deployment: StakingVerifier");
    console.log("Contract address:", stakingVerifier.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.stakingVerifierAddress = stakingVerifier.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/l2/verify_18_service_staking_verifier.js --network " + providerName + " " + stakingVerifier.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
