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
    console.log("17. EOA to deploy StakingNativeToken");
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");
    const StakingNativeToken = await ethers.getContractFactory("StakingNativeToken");
    console.log("You are signing the following transaction: StakingNativeToken.connect(EOA).deploy()");
    const stakingNativeToken = await StakingNativeToken.connect(EOA).deploy({ gasPrice });
    const result = await stakingNativeToken.deployed();

    // Transaction details
    console.log("Contract deployment: StakingNativeToken");
    console.log("Contract address:", stakingNativeToken.address);
    console.log("Transaction:", result.deployTransaction.hash);
    
    // Wait half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.stakingNativeTokenAddress = stakingNativeToken.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --network " + providerName + " " + stakingNativeToken.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
