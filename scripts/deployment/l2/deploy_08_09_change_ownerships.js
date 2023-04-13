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
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const serviceManagerAddress = parsedData.serviceManagerAddress;
    const fxGovernorTunnelAddress = parsedData.fxGovernorTunnelAddress;
    let EOA;

    let networkURL;
    if (providerName === "polygon") {
        if (!process.env.ALCHEMY_API_KEY_MATIC) {
            console.log("set ALCHEMY_API_KEY_MATIC env variable");
        }
        networkURL = "https://polygon-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MATIC;
    } else {
        if (!process.env.ALCHEMY_API_KEY_MUMBAI) {
            console.log("set ALCHEMY_API_KEY_MUMBAI env variable");
            return;
        }
        networkURL = "https://polygon-mumbai.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MUMBAI;
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

    // Get all the contracts
    const serviceRegistry = await ethers.getContractAt("ServiceRegistryL2", serviceRegistryAddress);
    const serviceManager = await ethers.getContractAt("ServiceManager", serviceManagerAddress);

    // Transaction signing and execution
    // 8. EOA to transfer ownership rights of ServiceRegistry to FxGovernorTunnel calling `changeOwner(FxGovernorTunnel)`;
    console.log("8. You are signing the following transaction: serviceRegistry.connect(EOA).changeOwner()");
    let result = await serviceRegistry.connect(EOA).changeOwner(fxGovernorTunnelAddress);
    // Transaction details
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);

    // 9. EOA to transfer ownership rights of ServiceManager to FxGovernorTunnel calling `changeOwner(FxGovernorTunnel)`.
    console.log("9.You are signing the following transaction: serviceManager.connect(EOA).changeOwner()");
    result = await serviceManager.connect(EOA).changeOwner(fxGovernorTunnelAddress);
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
