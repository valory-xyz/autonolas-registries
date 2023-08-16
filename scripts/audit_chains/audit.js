/*global ethers*/

const { expect } = require("chai");

async function main() {
    // Read configs from the JSON file
    const fs = require("fs");
    // Get the configuration file
    const configFile = "docs/configuration.json";
    const dataFromJSON = fs.readFileSync(configFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    // For now gnosis chains are not supported
    const networks = {
        "mainnet": "etherscan",
        "goerli": "goerli.etherscan",
        "polygon": "polygonscan",
        "polygonMumbai": "testnet.polygonscan"
    }

    console.log("\nVerifying the contracts... If no error is output, then the contracts are correct.");

    // Traverse all chains
    for (let i = 0; i < parsedData.length; i++) {
        // Skip gnosis chains
        if (!networks[parsedData[i]["name"]]) {
            continue;
        }

        console.log("\n\nNetwork:", parsedData[i]["name"]);
        const network = networks[parsedData[i]["name"]];
        const contracts = parsedData[i]["contracts"];

        // Verify contracts
        for (let j = 0; j < contracts.length; j++) {
            console.log("Checking " + contracts[j]["name"]);
            const execSync = require("child_process").execSync;
            execSync("scripts/audit_chains/audit_short.sh " + network + " " + contracts[j]["name"] + " " + contracts[j]["address"]);
        }
    }
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });