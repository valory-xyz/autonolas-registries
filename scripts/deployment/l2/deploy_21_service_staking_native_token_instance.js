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
    const serviceStakingParams = parsedData.serviceStakingParams;
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const multisigProxyHash130 = parsedData.multisigProxyHash130;
    const serviceStakingNativeTokenAddress = parsedData.serviceStakingNativeTokenAddress;
    const serviceStakingFactoryAddress = parsedData.serviceStakingFactoryAddress;

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

    // Get ServiceStakingFactory contract instance
    const serviceStakingFactory = await ethers.getContractAt("ServiceStakingFactory", serviceStakingFactoryAddress);
    // Get ServiceStakingToken omplementation contract instance
    const serviceStakingNativeToken = await ethers.getContractAt("ServiceStakingToken", serviceStakingNativeTokenAddress);

    // Transaction signing and execution
    console.log("21. EOA to deploy ServiceStakingNativeTokenInstance via the ServiceStakingFactory");
    console.log("You are signing the following transaction: ServiceStakingFactory.connect(EOA).createServiceStakingInstance()");
    const initPayload = serviceStakingNativeToken.interface.encodeFunctionData("initialize", [serviceStakingParams,
        serviceRegistryAddress, multisigProxyHash130]);
    const serviceStakingNativeTokenInstanceAddress = await serviceStakingFactory.callStatic.createServiceStakingInstance(
        serviceStakingNativeTokenAddress, initPayload);
    const result = await serviceStakingFactory.createServiceStakingInstance(serviceStakingNativeTokenAddress, initPayload);

    // Transaction details
    console.log("Contract deployment: ServiceStakingProxy");
    console.log("Contract address:", serviceStakingNativeTokenInstanceAddress);
    console.log("Transaction:", result.hash);

    // Wait half a minute for the transaction completion
    await new Promise(r => setTimeout(r, 30000));

    // Writing updated parameters back to the JSON file
    parsedData.serviceStakingNativeTokenInstanceAddress = serviceStakingNativeTokenInstanceAddress;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/l2/verify_21_service_staking_native_token_instance.js --network " + providerName + " " + serviceStakingNativeTokenInstanceAddress, { encoding: "utf-8" });
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
