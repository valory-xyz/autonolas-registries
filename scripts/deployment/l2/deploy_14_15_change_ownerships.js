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
    const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;
    const serviceManagerTokenAddress = parsedData.serviceManagerTokenAddress;
    const fxGovernorTunnelAddress = parsedData.fxGovernorTunnelAddress;
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

    // Get all the contracts
    const serviceRegistryTokenUtility = await ethers.getContractAt("ServiceRegistryTokenUtility", serviceRegistryTokenUtilityAddress);
    const serviceManagerToken = await ethers.getContractAt("ServiceManagerToken", serviceManagerTokenAddress);

    // Gas pricing
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");

    // Transaction signing and execution
    // 14. EOA to transfer ownership rights of ServiceRegistryTokenUtility to FxGovernorTunnel calling `changeOwner(FxGovernorTunnel)`;
    console.log("You are signing the following transaction: ServiceRegistryTokenUtility.connect(EOA).changeOwner()");
    let result = await serviceRegistryTokenUtility.connect(EOA).changeOwner(fxGovernorTunnelAddress, { gasPrice });
    // Transaction details
    console.log("Contract address:", serviceRegistryTokenUtilityAddress);
    console.log("Transaction:", result.hash);

    // 15. EOA to transfer ownership rights of ServiceManagerToken to FxGovernorTunnel calling `changeOwner(FxGovernorTunnel)`.
    console.log("You are signing the following transaction: serviceManagerToken.connect(EOA).changeOwner()");
    result = await serviceManagerToken.connect(EOA).changeOwner(fxGovernorTunnelAddress, { gasPrice });
    // Transaction details
    console.log("Contract address:", serviceManagerTokenAddress);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
