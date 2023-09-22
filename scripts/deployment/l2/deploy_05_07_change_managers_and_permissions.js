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
    const gnosisSafeMultisigImplementationAddress = parsedData.gnosisSafeMultisigImplementationAddress;
    const gnosisSafeSameAddressMultisigImplementationAddress = parsedData.gnosisSafeSameAddressMultisigImplementationAddress;
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
        if (!process.env.GNOSISSCAN_API_KEY) {
            console.log("set GNOSISSCAN_API_KEY env variable");
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
    const serviceRegistry = await ethers.getContractAt("ServiceRegistryL2", serviceRegistryAddress);

    // Gas pricing
    const gasPrice = ethers.utils.parseUnits(gasPriceInGwei, "gwei");

    // Transaction signing and execution
    // 5. EOA to change the manager of ServiceRegistry to ServiceManager calling `changeManager(ServiceManager)`;
    console.log("5. You are signing the following transaction: serviceRegistry.connect(EOA).changeManager()");
    let result = await serviceRegistry.connect(EOA).changeManager(serviceManagerAddress, { gasPrice });
    // Transaction details
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);

    // 6. EOA to whitelist GnosisSafeMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeMultisig)`;
    console.log("6. You are signing the following transaction: serviceRegistry.connect(EOA).changeMultisigPermission()");
    result = await serviceRegistry.connect(EOA).changeMultisigPermission(gnosisSafeMultisigImplementationAddress, true, { gasPrice });
    // Transaction details
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);

    // 7. EOA to whitelist GnosisSafeSameAddressMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeSameAddressMultisig)`;
    console.log("7. You are signing the following transaction: serviceRegistry.connect(EOA).changeMultisigPermission()");
    result = await serviceRegistry.connect(EOA).changeMultisigPermission(gnosisSafeSameAddressMultisigImplementationAddress, true, { gasPrice });
    // Transaction details
    console.log("Contract address:", serviceRegistryAddress);
    console.log("Transaction:", result.hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
