/*global process*/

const { ethers } = require("hardhat");

async function main() {
    // This script is designed specifically for the mainnet deployment
    // Getting the registry contracts
    const componentRegistry = await ethers.getContractAt("ComponentRegistry", "0x15bd56669F57192a97dF41A2aa8f4403e9491776");
    const agentRegistry = await ethers.getContractAt("AgentRegistry", "0x2F1f7D38e4772884b88f3eCd8B6b9faCdC319112");
    const serviceRegistry = await ethers.getContractAt("ServiceRegistry", "0x48b6af7B12C71f09e2fC8aF4855De4Ff54e775cA");

    // Initialize the snapshot structure
    let snapshotJSON = {
        "componentRegistry": {
            "dependencies": [],
            "hashes": []
        },
        "agentRegistry": {
            "dependencies": [],
            "hashes": []
        },
        "serviceRegistry": {
            "securityDeposit": [],
            "multisig": [],
            "configHashes": [],
            "threshold": [],
            "maxNumAgentInstances": [],
            "numAgentInstances": [],
            "state": [],
            "agentIds": [],
            "agentParams": []
        }
    };

    console.log("Pulling registries snapshot with the following numbers.");
    const numComponents = Number(await componentRegistry.totalSupply());
    const numAgents = Number(await agentRegistry.totalSupply());
    const numServices = Number(await serviceRegistry.totalSupply());
    console.log("Number of components:", numComponents);
    console.log("Number of agents:", numAgents);
    console.log("Number of services:", numServices);

    // Get the component data
    for (let i = 1; i <= numComponents; i++) {
        const unit = await componentRegistry.getUnit(i);
        snapshotJSON["componentRegistry"]["dependencies"].push(unit.dependencies);
        snapshotJSON["componentRegistry"]["hashes"].push(unit.unitHash);
        //console.log("component hash", unit.unitHash);
    }

    // Get the agent data
    for (let i = 1; i <= numAgents; i++) {
        const unit = await agentRegistry.getUnit(i);
        snapshotJSON["agentRegistry"]["dependencies"].push(unit.dependencies);
        snapshotJSON["agentRegistry"]["hashes"].push(unit.unitHash);
    }

    // Get the service data
    for (let i = 1; i <= numServices; i++) {
        const service = await serviceRegistry.getService(i);
        snapshotJSON["serviceRegistry"]["securityDeposit"].push((service.securityDeposit).toString());
        snapshotJSON["serviceRegistry"]["multisig"].push(service.multisig);
        snapshotJSON["serviceRegistry"]["configHashes"].push(service.configHash);
        snapshotJSON["serviceRegistry"]["threshold"].push(service.threshold);
        snapshotJSON["serviceRegistry"]["maxNumAgentInstances"].push(service.threshold);
        snapshotJSON["serviceRegistry"]["numAgentInstances"].push(service.numAgentInstances);
        snapshotJSON["serviceRegistry"]["state"].push(service.state);
        snapshotJSON["serviceRegistry"]["agentIds"].push(service.agentIds);

        // Get the agent Ids related data
        const agentParams = await serviceRegistry.getAgentParams(i);
        let apConverted = [];
        for (let j = 0; j < agentParams.numAgentIds; j++) {
            apConverted.push([agentParams.agentParams[j].slots,     (agentParams.agentParams[j].bond).toString()]);
        }
        snapshotJSON["serviceRegistry"]["agentParams"].push(apConverted);
    }

    // Write the json file with the mainnet snapshot to simulate it later on a local node
    const fs = require("fs");
    const snapshotFile = "scripts/mainnet_snapshot.json";
    fs.writeFileSync(snapshotFile, JSON.stringify(snapshotJSON));

    console.log("Snapshot is complete and written to:", snapshotFile);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
