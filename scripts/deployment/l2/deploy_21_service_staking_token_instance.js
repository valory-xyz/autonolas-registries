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
    const stakingParams = parsedData.stakingParams;
    const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;
    const olasAddress = parsedData.olasAddress;
    const stakingTokenAddress = parsedData.stakingTokenAddress;
    const stakingFactoryAddress = parsedData.stakingFactoryAddress;

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

    // Get StakingFactory contract instance
    const stakingFactory = await ethers.getContractAt("StakingFactory", stakingFactoryAddress);
    // Get StakingToken implementation contract instance
    const stakingToken = await ethers.getContractAt("StakingToken", stakingTokenAddress);

    // Transaction signing and execution
    console.log("21. EOA to deploy StakingTokenInstance via the StakingFactory");
    console.log("You are signing the following transaction: StakingFactory.connect(EOA).createStakingInstance()");
    const initPayload = stakingToken.interface.encodeFunctionData("initialize", [stakingParams,
        serviceRegistryTokenUtilityAddress, olasAddress]);
    const stakingTokenInstanceAddress = await stakingFactory.callStatic.createStakingInstance(stakingTokenAddress,
        initPayload);
    const result = await stakingFactory.createStakingInstance(stakingTokenAddress, initPayload);

    // Transaction details
    console.log("Contract deployment: StakingProxy");
    console.log("Contract address:", stakingTokenInstanceAddress);
    console.log("Transaction:", result.hash);

    // Wait half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.stakingTokenInstanceAddress = stakingTokenInstanceAddress;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/l2/verify_21_service_staking_token_instance.js --network " + providerName + " " + stakingTokenInstanceAddress, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
