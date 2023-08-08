/*global ethers*/

const { expect } = require("chai");

module.exports = async () => {
    // Read configs from the JSON file
    const fs = require("fs");
    // Account for the default docker-originated behavior
    let snapshotFile = "/base/scripts/mainnet_snapshot.json";
    if (!fs.existsSync(snapshotFile)) {
        // If the file does not exist, take the original snapshot file
        snapshotFile = "./scripts/mainnet_snapshot.json";
    }
    const dataFromJSON = fs.readFileSync(snapshotFile, "utf8");
    const snapshotJSON = JSON.parse(dataFromJSON);

    const signers = await ethers.getSigners();
    const deployer = signers[0];
    const operator = signers[10];
    const agentInstances = [signers[0].address, signers[1].address, signers[2].address, signers[3].address, signers[4].address];
    const agentInstancesPK = [
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
        "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
        "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a",
        "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6",
        "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"
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

    // Deploying service registry and service manager contracts
    const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
    const serviceRegistry = await ServiceRegistry.deploy("Service Registry", "AUTONOLAS-SERVICE-V1",
        "https://gateway.autonolas.tech/ipfs/", agentRegistry.address);
    await serviceRegistry.deployed();

    const ServiceManager = await ethers.getContractFactory("ServiceManager");
    const serviceManager = await ServiceManager.deploy(serviceRegistry.address);
    await serviceManager.deployed();

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

    const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
    const gnosisSafeSameAddressMultisig = await GnosisSafeSameAddressMultisig.deploy();
    await gnosisSafeSameAddressMultisig.deployed();

    const MultiSend = await ethers.getContractFactory("MultiSendCallOnly");
    const multiSend = await MultiSend.deploy();
    await multiSend.deployed();

    const ServiceRegistryL2 = await ethers.getContractFactory("ServiceRegistryL2");
    const serviceRegistryL2 = await ServiceRegistryL2.deploy("Service Registry L2", "AUTONOLAS-SERVICE-L2-V1",
        "https://gateway.autonolas.tech/ipfs/");
    await serviceRegistryL2.deployed();

    // Deploying service registry and service registry token utility along with the service manager token contracts
    const ServiceRegistryTokenUtility = await ethers.getContractFactory("ServiceRegistryTokenUtility");
    const serviceRegistryTokenUtility = await ServiceRegistryTokenUtility.deploy(serviceRegistry.address);
    await serviceRegistryTokenUtility.deployed();

    const OperatorWhitelist = await ethers.getContractFactory("OperatorWhitelist");
    const operatorWhitelist = await OperatorWhitelist.deploy(serviceRegistry.address);
    await operatorWhitelist.deployed();

    const ServiceManagerToken = await ethers.getContractFactory("ServiceManagerToken");
    const serviceManagerToken = await ServiceManagerToken.deploy(serviceRegistry.address,
        serviceRegistryTokenUtility.address, operatorWhitelist.address);
    await serviceManagerToken.deployed();

    const Token = await ethers.getContractFactory("ERC20Token");
    const token = await Token.deploy();
    await token.deployed();

    console.log("==========================================");
    console.log("ComponentRegistry deployed to:", componentRegistry.address);
    console.log("AgentRegistry deployed to:", agentRegistry.address);
    console.log("RegistriesManager deployed to:", registriesManager.address);
    console.log("ServiceRegistry deployed to:", serviceRegistry.address);
    console.log("ServiceRegistryTokenUtility deployed to:", serviceRegistryTokenUtility.address);
    console.log("ServiceManagerToken deployed to:", serviceManagerToken.address);
    console.log("ServiceRegistryL2 deployed to:", serviceRegistryL2.address);
    console.log("ServiceManager deployed to:", serviceManager.address);
    console.log("OperatorWhitelist deployed to:", operatorWhitelist.address);
    console.log("ERC20Token deployed to:", token.address);
    console.log("Gnosis Safe master copy deployed to:", gnosisSafe.address);
    console.log("Gnosis Safe proxy factory deployed to:", gnosisSafeProxyFactory.address);
    console.log("Gnosis Safe Multisig deployed to:", gnosisSafeMultisig.address);
    console.log("Gnosis Safe Multisig with same address deployed to:", gnosisSafeSameAddressMultisig.address);
    console.log("Gnosis Safe Multisend deployed to:", multiSend.address);

    // Whitelist gnosis multisig implementations
    await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
    await serviceRegistry.changeMultisigPermission(gnosisSafeSameAddressMultisig.address, true);
    await serviceRegistryL2.changeMultisigPermission(gnosisSafeMultisig.address, true);
    await serviceRegistryL2.changeMultisigPermission(gnosisSafeSameAddressMultisig.address, true);

    // Also whitelist multisigs for all the other networks
    // ETH Goerli
    // Multisig implementation that creates a new multisig
    await serviceRegistry.changeMultisigPermission("0x65dD51b02049ad1B6FF7fa9Ea3322E1D2CAb1176", true);
    // Multisig implementation that changes the existent multisig
    await serviceRegistry.changeMultisigPermission("0x92499E80f50f06C4078794C179986907e7822Ea1", true);

    // EHT Mainnet
    // Multisig implementation that creates a new multisig
    await serviceRegistry.changeMultisigPermission("0x46C0D07F55d4F9B5Eed2Fc9680B5953e5fd7b461", true);
    // Multisig implementation that changes the existent multisig
    await serviceRegistry.changeMultisigPermission("0x26Ea2dC7ce1b41d0AD0E0521535655d7a94b684c", true);

    // Polygon Mumbai
    await serviceRegistryL2.changeMultisigPermission("0x9dEc6B62c197268242A768dc3b153AE7a2701396", true);
    await serviceRegistryL2.changeMultisigPermission("0xB575dd20281c63288428DD58e5f579CC7d6aae4d", true);

    // Polygon Mainnet
    await serviceRegistryL2.changeMultisigPermission("0x3d77596beb0f130a4415df3D2D8232B3d3D31e44", true);
    await serviceRegistryL2.changeMultisigPermission("0x34C895f302D0b5cf52ec0Edd3945321EB0f83dd5", true);

    // Gnosis Chiado
    await serviceRegistryL2.changeMultisigPermission("0xeB49bE5DF00F74bd240DE4535DDe6Bc89CEfb994", true);
    await serviceRegistryL2.changeMultisigPermission("0x5BA58970c2Ae16Cf6218783018100aF2dCcFc915", true);

    // Gnosis Mainnet
    await serviceRegistryL2.changeMultisigPermission("0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE", true);
    await serviceRegistryL2.changeMultisigPermission("0x3d77596beb0f130a4415df3D2D8232B3d3D31e44", true);

    // For simplicity, deployer is the manager for service registry
    await serviceRegistry.changeManager(deployer.address);

    // Create a first service with 4 agent instances
    const defaultConfigHash = "0x" + "5".repeat(64);
    const defaultAgentIds = [1];
    const defaultBond = "10000000000000000";
    const defaultBond4 = "40000000000000000";
    const defaultAgentParams = [[4, defaultBond]];
    const defaultThreshold = 3;
    await serviceRegistry.create(deployer.address, defaultConfigHash, defaultAgentIds, defaultAgentParams, defaultThreshold);

    // Activate registration
    const defaultServiceId = 1;
    await serviceRegistry.activateRegistration(deployer.address, defaultServiceId, {value: defaultBond});

    // Register agents with the operator
    await serviceRegistry.registerAgents(operator.address, defaultServiceId, agentInstances.slice(0, 4), [1, 1, 1, 1], {value: defaultBond4});

    // Deploy the service
    const defaultPayload = "0x";
    const defaultServiceSafe = await serviceRegistry.deploy(deployer.address, defaultServiceId, gnosisSafeMultisig.address, defaultPayload);
    const sResult = await defaultServiceSafe.wait();
    const defaultServiceMultisig = sResult.events[0].address;

    console.log("==========================================");
    console.log("Service Id:", defaultServiceId);
    console.log("Service multisig deployed to:", defaultServiceMultisig);
    console.log("Number of agent instances:", 4);

    // Create and deploy services based on the snapshot
    const numServices = snapshotJSON["serviceRegistry"]["configHashes"].length;
    // Agent instances cannot repeat, so each of them must be a unique address
    // TODO: With a bigger number of services, precalculate the number of agent instances first and allocate enough addresses for that
    let aCounter = 4;
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
        const serviceId = i + 2; // shift by 2 since the first service is created earlier (otherwise would be i + 1)
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
    await serviceRegistry.changeManager(serviceManagerToken.address);
    console.log("ServiceManagerToken is now a manager of ServiceRegistry contract");
    await serviceRegistryTokenUtility.changeManager(serviceManagerToken.address);
    console.log("ServiceManagerToken is now a manager of ServiceRegistryTokenUtility contract");
    await serviceRegistryL2.changeManager(serviceManager.address);
    console.log("ServiceManager is now a manager of ServiceRegistryL2 contract");

    // Writing the JSON with the initial deployment data
    let initDeployJSON = {
        "componentRegistry": componentRegistry.address,
        "agentRegistry": agentRegistry.address,
        "registriesManager": registriesManager.address,
        "serviceRegistry": serviceRegistry.address,
        "serviceManager": serviceManager.address,
        "serviceRegistryL2": serviceRegistryL2.address,
        "serviceRegistryTokenUtility": serviceRegistryTokenUtility.address,
        "serviceManagerToken": serviceManagerToken.address,
        "operatorWhitelist": operatorWhitelist.address,
        "ERC20Token": token.address,
        "gnosisSafe": gnosisSafe.address,
        "gnosisSafeProxyFactory": gnosisSafeProxyFactory.address,
        "Multisig implementation": gnosisSafeMultisig.address,
        "Multisig implementation with same address": gnosisSafeSameAddressMultisig.address,
        "multiSend": multiSend.address,
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
