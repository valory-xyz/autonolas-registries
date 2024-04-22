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
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;
    const operatorWhitelistAddress = parsedData.operatorWhitelistAddress;

    let networkURL = parsedData.networkURL;
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

    // Gas pricing
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");

    // Transaction signing and execution
    console.log("4. EOA to deploy ServiceManagerToken");
    const ServiceManagerToken = await ethers.getContractFactory("ServiceManagerToken");
    console.log("You are signing the following transaction: ServiceManagerToken.connect(EOA).deploy()");
    const serviceManagerToken = await ServiceManagerToken.connect(EOA).deploy(serviceRegistryAddress,
        serviceRegistryTokenUtilityAddress, operatorWhitelistAddress, { gasPrice });
    const result = await serviceManagerToken.deployed();

    // Transaction details
    console.log("Contract deployment: ServiceManagerToken");
    console.log("Contract address:", serviceManagerToken.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Wait half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.serviceManagerTokenAddress = serviceManagerToken.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/l2/verify_04_service_manager_token.js --network " + providerName + " " + serviceManagerToken.address, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
