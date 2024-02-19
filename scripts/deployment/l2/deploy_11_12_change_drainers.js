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

    // NOTE: Bridge Mediator for chiado network is the one with the mock timelock to facilitate testing!
    // NOTE: See autonolas-governance for the address match in bridges/gnosis/test/globals.json
    // NOTE: Use the currently setup Bridge Mediator and mock Timelock contracts to set up
    // NOTE: a corresponding testnet Bridge Mediator contract that comes from the parsedData
    let bridgeMediatorAddress = parsedData.bridgeMediatorAddress;

    let networkURL = parsedData.networkURL;
    if (providerName === "polygon") {
        if (!process.env.ALCHEMY_API_KEY_MATIC) {
            console.log("set ALCHEMY_API_KEY_MATIC env variable");
        }
        networkURL += process.env.ALCHEMY_API_KEY_MATIC;
    } else if (providerName === "polygonMumbai") {
        if (!process.env.ALCHEMY_API_KEY_MUMBAI) {
            console.log("set ALCHEMY_API_KEY_MUMBAI env variable");
            return;
        }
        networkURL += process.env.ALCHEMY_API_KEY_MUMBAI;
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

    // Get all the contracts
    const serviceRegistry = await ethers.getContractAt("ServiceRegistryL2", serviceRegistryAddress);
    const serviceRegistryTokenUtility = await ethers.getContractAt("ServiceRegistryTokenUtility", serviceRegistryTokenUtilityAddress);

    // 11. EOA to change the drainer of ServiceRegistry to BridgeMediator
    console.log("You are signing the following transaction: serviceRegistry.connect(EOA).changeDrainer(bridgeMediatorAddress)");
    let result = await serviceRegistry.connect(EOA).changeDrainer(bridgeMediatorAddress, { gasPrice });
    // Transaction details
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);

    // 12. EOA to change the drainer of ServiceRegistryTokenUtility to BridgeMediator
    console.log("You are signing the following transaction: serviceRegistryTokenUtility.connect(EOA).changeDrainer(bridgeMediatorAddress)");
    result = await serviceRegistryTokenUtility.connect(EOA).changeDrainer(bridgeMediatorAddress, { gasPrice });
    // Transaction details
    console.log("Contract address:", serviceRegistryTokenUtilityAddress);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
