/*global ethers*/

const { expect } = require("chai");

module.exports = async () => {
    // Read configs from the JSON file
    const fs = require("fs");
    // Copy this file from scripts/mainnet_snapshot.json or construct one following the JSON defined structure
    const snapshotFile = "snapshot.json";
    const dataFromJSON = fs.readFileSync(snapshotFile, "utf8");
    const snapshotJSON = JSON.parse(dataFromJSON);

    const signers = await ethers.getSigners();
    const deployer = signers[0];
    const operator = signers[10];
    const agentInstances = [signers[0].address, signers[1].address, signers[2].address, signers[3].address];
    const agentInstancesPK = [
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
        "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
        "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
        "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
    ];
    const operatorPK = "0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897";

    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    // Deploying component registry
    const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
    const componentRegistry = await ComponentRegistry.deploy("Component Registry", "AUTONOLAS-COMPONENT-V1",
        "https://gateway.autonolas.tech/ipfs/");
    await componentRegistry.deployed();

    // Deploying agent registry
    const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
    const agentRegistry = await AgentRegistry.deploy("Agent Registry", "AUTONOLAS-AGENT-V1",
        "https://gateway.autonolas.tech/ipfs/", componentRegistry.address);
    await agentRegistry.deployed();

    // Deploying component / agent manager
    const RegistriesManager = await ethers.getContractFactory("RegistriesManager");
    const registriesManager = await RegistriesManager.deploy(componentRegistry.address, agentRegistry.address);
    await registriesManager.deployed();

    // For simplicity, deployer is the manager for component and agent registries
    await componentRegistry.changeManager(deployer.address);
    await agentRegistry.changeManager(deployer.address);

    // Create components from the snapshot data
    const numComponents = snapshotJSON["componentRegistry"]["hashes"].length;
    for (let i = 0; i < numComponents; i++) {
        await componentRegistry.connect(deployer).create(deployer.address,
            snapshotJSON["componentRegistry"]["hashes"][i], snapshotJSON["componentRegistry"]["dependencies"][i]);
    }

    // Create agents from the snapshot data
    const numAgents = snapshotJSON["agentRegistry"]["hashes"].length;
    for (let i = 0; i < numAgents; i++) {
        await agentRegistry.connect(deployer).create(deployer.address,
            snapshotJSON["agentRegistry"]["hashes"][i], snapshotJSON["agentRegistry"]["dependencies"][i]);
    }

    const componentBalance = await componentRegistry.balanceOf(deployer.address);
    expect(componentBalance).to.equal(numComponents);
    const agentBalance = await agentRegistry.balanceOf(deployer.address);
    expect(agentBalance).to.equal(numAgents);
    console.log("Owner of created components and agents:", deployer.address);
    console.log("Number of initial components:", Number(componentBalance));
    console.log("Number of initial agents:", Number(agentBalance));

    // Gnosis Safe deployment
    const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
    const gnosisSafe = await GnosisSafe.deploy();
    await gnosisSafe.deployed();

    const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
    const gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
    await gnosisSafeProxyFactory.deployed();

    const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
    const gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafe.address, gnosisSafeProxyFactory.address);
    await gnosisSafeMultisig.deployed();

    // Deploying service registry and service manager contracts
    const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
    const serviceRegistry = await ServiceRegistry.deploy("Service Registry", "AUTONOLAS-SERVICE-V1",
        "https://gateway.autonolas.tech/ipfs/", agentRegistry.address);
    await serviceRegistry.deployed();

    const ServiceManager = await ethers.getContractFactory("ServiceManager");
    const serviceManager = await ServiceManager.deploy(serviceRegistry.address);
    await serviceManager.deployed();

    console.log("==========================================");
    console.log("ComponentRegistry deployed to:", componentRegistry.address);
    console.log("AgentRegistry deployed to:", agentRegistry.address);
    console.log("RegistriesManager deployed to:", registriesManager.address);
    console.log("ServiceRegistry deployed to:", serviceRegistry.address);
    console.log("ServiceManager deployed to:", serviceManager.address);
    console.log("Gnosis Safe Multisig deployed to:", gnosisSafeMultisig.address);

    // Whitelist gnosis multisig implementations
    await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
    // Also whitelist multisigs from goerli and mainnet
    // Goerli
    await serviceRegistry.changeMultisigPermission("0x63C2c53c09dE534Dd3bc0b7771bf976070936bAC", true);
    // Mainnet
    await serviceRegistry.changeMultisigPermission("0x46C0D07F55d4F9B5Eed2Fc9680B5953e5fd7b461", true);

    // For simplicity, deployer is the manager for service registry
    await serviceRegistry.changeManager(deployer.address);

    // Create and deploy services based on the snapshot
    const numServices = snapshotJSON["serviceRegistry"]["configHashes"].length;
    // Agent instances cannot repeat, so each of them must be a unique address
    // TODO: With a bigger number of services, precalculate the number of agent instances first and allocate enough addresses for that
    let aCounter = 0;
    console.log("==========================================");
    for (let i = 0; i < numServices; i++) {
        // Get the agent Ids related data
        const agentIds = snapshotJSON["serviceRegistry"]["agentIds"][i];
        //console.log("agentIds", agentIds);
        let agentParams = [];
        for (let j = 0; j < agentIds.length; j++) {
            agentParams.push(snapshotJSON["serviceRegistry"]["agentParams"][i][j]);
        }
        //console.log("agentParams", agentParams);

        // Create a service
        const configHash = snapshotJSON["serviceRegistry"]["configHashes"][i];
        const threshold = snapshotJSON["serviceRegistry"]["threshold"][i];
        //console.log("configHash", configHash);
        //console.log("threshold", threshold);
        await serviceRegistry.create(deployer.address, configHash, agentIds, agentParams, threshold);

        // Activate registration
        const serviceId = i + 1;
        console.log("Service Id:", serviceId);
        await serviceRegistry.activateRegistration(deployer.address, serviceId,
            {value: snapshotJSON["serviceRegistry"]["securityDeposit"][i]});

        // Register agents with the operator
        let sumValue = ethers.BigNumber.from(0);
        let regAgentInstances = [];
        let regAgentIds = [];
        // Calculate all the agent instances and a sum of a bond value from the operator
        for (let j = 0; j < agentIds.length; j++) {
            const mult = ethers.BigNumber.from(agentParams[j][1]).mul(agentParams[j][0]);
            sumValue = sumValue.add(mult);
            for (let k = 0; k < agentParams[j][0]; k++) {
                // Agent instances to register will be as many as agent Ids multiply by the number of slots
                regAgentIds.push(agentIds[j]);
                regAgentInstances.push(agentInstances[aCounter]);
                aCounter++;
            }
        }
        //console.log("regAgentInstances", regAgentInstances);
        //console.log("regAgentIds", regAgentIds);
        //console.log("sumValue", sumValue);
        await serviceRegistry.registerAgents(operator.address, serviceId, regAgentInstances, regAgentIds, {value: sumValue});

        // Deploy the service
        const payload = "0x";
        const safe = await serviceRegistry.deploy(deployer.address, serviceId, gnosisSafeMultisig.address, payload);
        const result = await safe.wait();
        const multisig = result.events[0].address;
        console.log("Service multisig deployed to:", multisig);
        console.log("Number of agent instances:", regAgentInstances.length);

        // Verify the deployment of the created Safe: checking threshold and owners
        const proxyContract = await ethers.getContractAt("GnosisSafe", multisig);
        if (await proxyContract.getThreshold() != threshold) {
            throw new Error("incorrect threshold");
        }
        for (const aInstance of regAgentInstances) {
            const isOwner = await proxyContract.isOwner(aInstance);
            if (!isOwner) {
                throw new Error("incorrect agent instance");
            }
        }

        console.log("==========================================");
    }
    console.log("Services are created and deployed");

    // Change manager in component, agent and service registry to their corresponding manager contracts
    await componentRegistry.changeManager(registriesManager.address);
    await agentRegistry.changeManager(registriesManager.address);
    console.log("RegistriesManager is now a manager of ComponentRegistry and AgentRegistry contracts");
    await serviceRegistry.changeManager(serviceManager.address);
    console.log("ServiceManager is now a manager of ServiceRegistry contract");

    // Writing the JSON with the initial deployment data
    let initDeployJSON = {
        "componentRegistry": componentRegistry.address,
        "agentRegistry": agentRegistry.address,
        "registriesManager": registriesManager.address,
        "serviceRegistry": serviceRegistry.address,
        "serviceManager": serviceManager.address,
        "Multisig implementation": gnosisSafeMultisig.address,
        "operator": {
            "address": operator.address,
            "privateKey": operatorPK
        },
        "agentsInstances": {
            "addresses": [agentInstances[0], agentInstances[1], agentInstances[2], agentInstances[3]],
            "privateKeys": [agentInstancesPK[0], agentInstancesPK[1], agentInstancesPK[2], agentInstancesPK[3]]
        }
    };

    // Write the json file with the setup
    const initDeployFile = "initDeploy.json";
    fs.writeFileSync(initDeployFile, JSON.stringify(initDeployJSON));
};
