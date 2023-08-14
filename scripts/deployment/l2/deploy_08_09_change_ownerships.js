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
    const serviceManagerAddress = parsedData.serviceManagerAddress;

    // NOTE: Bridge Mediator for chiado network is the one with the mock timelock to facilitate testing!
    // NOTE: See autonolas-governance for the address match in bridges/gnosis/test/globals.json
    // NOTE: Use the currently setup Bridge Mediator and mock Timelock contracts to set up
    // NOTE: a corresponding testnet Bridge Mediator contract that comes from the parsedData
    let bridgeMediatorAddress = parsedData.bridgeMediatorAddress;
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
        if (!process.env.GNOSIS_CHAIN_API_KEY) {
            console.log("set GNOSIS_CHAIN_API_KEY env variable");
            return;
        }
        networkURL = "https://rpc.gnosischain.com";
    } else if (providerName === "chiado") {
        networkURL = "https://rpc.chiadochain.net";
        // Bridge mediator is deployed via a mock timelock on goerli in order to perform testing
        bridgeMediatorAddress = "0x0a50009D55Ed5700ac8FF713709d5Ad5fa843896";
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

    // Gas pricing
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");

    // Get all the contracts
    const serviceRegistry = await ethers.getContractAt("ServiceRegistryL2", serviceRegistryAddress);
    const serviceManager = await ethers.getContractAt("ServiceManager", serviceManagerAddress);

    // Transaction signing and execution
    // 8. EOA to transfer ownership rights of ServiceRegistry to FxGovernorTunnel calling `changeOwner(FxGovernorTunnel)`;
    console.log("8. You are signing the following transaction: serviceRegistry.connect(EOA).changeOwner()");
    let result = await serviceRegistry.connect(EOA).changeOwner(bridgeMediatorAddress, { gasPrice });
    // Transaction details
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);

    // 9. EOA to transfer ownership rights of ServiceManager to FxGovernorTunnel calling `changeOwner(FxGovernorTunnel)`.
    console.log("9.You are signing the following transaction: serviceManager.connect(EOA).changeOwner()");
    result = await serviceManager.connect(EOA).changeOwner(bridgeMediatorAddress, { gasPrice });
    // Transaction details
    console.log("Contract address:", serviceManagerAddress);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
