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
    const agentRegistryName = parsedData.agentRegistryName;
    const agentRegistrySymbol = parsedData.agentRegistrySymbol;
    const baseURI = parsedData.baseURI;
    const componentRegistryAddress = parsedData.componentRegistryAddress;
    let EOA;

    const provider = await ethers.providers.getDefaultProvider(providerName);
    const signers = await ethers.getSigners();

    if (useLedger) {
        EOA = new LedgerSigner(provider, derivationPath);
    } else {
        EOA = signers[0];
    }
    // EOA address
    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    // Transaction signing and execution
    console.log("2. EOA to deploy AgentRegistry");
    const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
    console.log("You are signing the following transaction: AgentRegistry.connect(EOA).deploy()");
    const agentRegistry = await AgentRegistry.connect(EOA).deploy(agentRegistryName, agentRegistrySymbol,
        baseURI, componentRegistryAddress);
    const result = await agentRegistry.deployed();

    // Transaction details
    console.log("Contract deployment: AgentRegistry");
    console.log("Contract address:", agentRegistry.address);
    console.log("Transaction:", result.deployTransaction.hash);

    // Contract verification
    if (parsedData.contractVerification) {
        const execSync = require("child_process").execSync;
        execSync("npx hardhat verify --constructor-args scripts/deployment/verify_02_agent_registry.js --network " + providerName + " " + agentRegistry.address, { encoding: "utf-8" });
    }

    // Writing updated parameters back to the JSON file
    parsedData.agentRegistryAddress = agentRegistry.address;
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
