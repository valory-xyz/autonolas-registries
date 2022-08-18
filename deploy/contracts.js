/*global ethers*/

module.exports = async () => {
    // Common parameters
    const AddressZero = "0x" + "0".repeat(40);

    // Test address, IPFS hashes and descriptions for components and agents
    const compHs = ["0x" + "9".repeat(64), "0x" + "1".repeat(64), "0x" + "2".repeat(64)];
    const agentHs = ["0x" + "3".repeat(62) + "11", "0x" + "4".repeat(62) + "11"];

    // Read configs from the JSON file
    const fs = require("fs");
    const globalsFile = "scripts/node_globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);
    const configHash = parsedData.configHash;

    // Safe related
    const safeThreshold = 7;
    const nonce =  0;
    const payload = "0x";

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

    // Deploying minter
    const RegistriesManager = await ethers.getContractFactory("RegistriesManager");
    const registriesManager = await RegistriesManager.deploy(componentRegistry.address, agentRegistry.address);
    await registriesManager.deployed();

    console.log("ComponentRegistry deployed to:", componentRegistry.address);
    console.log("AgentRegistry deployed to:", agentRegistry.address);
    console.log("RegistriesManager deployed to:", registriesManager.address);

    // Whitelisting minter in component and agent registry
    await componentRegistry.changeManager(registriesManager.address);
    await agentRegistry.changeManager(registriesManager.address);
    console.log("Whitelisted RegistriesManager addresses to both ComponentRegistry and AgentRegistry contract instances");

    // Create 3 components and two agents based on defined component and agent hashes
    // 0 for component, 1 for agent
    await registriesManager.create(0, deployer.address, compHs[0], []);
    await registriesManager.create(1, deployer.address, agentHs[0], [1]);
    await registriesManager.create(0, deployer.address, compHs[1], [1]);
    await registriesManager.create(0, deployer.address, compHs[2], [1, 2]);
    await registriesManager.create(1, deployer.address, agentHs[1], [1, 2, 3]);
    const componentBalance = await componentRegistry.balanceOf(deployer.address);
    const agentBalance = await agentRegistry.balanceOf(deployer.address);
    console.log("Owner of minted components and agents:", deployer.address);
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
    console.log("Gnosis Safe Multisig deployed to:", gnosisSafeMultisig.address);

    // Creating and updating a service
    const regBond = 1000;
    const regDeposit = 1000;
    const agentIds = [1];
    const agentParams = [[4, regBond]];
    const maxThreshold = agentParams[0][0];
    const serviceId = 1;

    const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
    const serviceRegistry = await ServiceRegistry.deploy("Service Registry", "AUTONOLAS-SERVICE-V1",
        "https://gateway.autonolas.tech/ipfs/", agentRegistry.address);
    await serviceRegistry.deployed();

    const ServiceManager = await ethers.getContractFactory("ServiceManager");
    // Treasury address is irrelevant at the moment
    const serviceManager = await ServiceManager.deploy(serviceRegistry.address);
    await serviceManager.deployed();

    console.log("ServiceRegistry deployed to:", serviceRegistry.address);
    console.log("ServiceManager deployed to:", serviceManager.address);

    // Create a service
    await serviceRegistry.changeManager(deployer.address);
    await serviceRegistry.create(deployer.address, configHash, agentIds, agentParams, maxThreshold);
    console.log("Service is created");

    // Register agents
    await serviceRegistry.activateRegistration(deployer.address, serviceId, {value: regDeposit});
    // Owner / deployer is the operator of agent instances as well
    await serviceRegistry.registerAgents(operator.address, serviceId, agentInstances, [1, 1, 1, 1], {value: 4 * regBond});

    // Whitelist gnosis multisig implementation
    await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
    // Also whitelist multisigs from goerli and mainnet
    // Goerli
    await serviceRegistry.changeMultisigPermission("0x63C2c53c09dE534Dd3bc0b7771bf976070936bAC", true);
    // Mainnet
    await serviceRegistry.changeMultisigPermission("0x46C0D07F55d4F9B5Eed2Fc9680B5953e5fd7b461", true);
    // Deploy the service
    const safe = await serviceRegistry.deploy(deployer.address, serviceId, gnosisSafeMultisig.address, payload);
    const result = await safe.wait();
    const multisig = result.events[0].address;
    console.log("Service multisig deployed to:", multisig);
    console.log("Number of agent instances:", agentInstances.length);

    // Verify the deployment of the created Safe: checking threshold and owners
    const proxyContract = await ethers.getContractAt("GnosisSafe", multisig);
    if (await proxyContract.getThreshold() != maxThreshold) {
        throw new Error("incorrect threshold");
    }
    for (const aInstance of agentInstances) {
        const isOwner = await proxyContract.isOwner(aInstance);
        if (!isOwner) {
            throw new Error("incorrect agent instance");
        }
    }

    // Give service manager rights to the corresponding contract
    await serviceRegistry.changeManager(serviceManager.address);

    // Deploy safe multisig for the governance
    const safeSigners = signers.slice(11, 20).map(
        function (currentElement) {
            return currentElement.address;
        }
    );
    const setupData = gnosisSafe.interface.encodeFunctionData(
        "setup",
        // signers, threshold, to_address, data, fallback_handler, payment_token, payment, payment_receiver
        [safeSigners, safeThreshold, AddressZero, "0x", AddressZero, AddressZero, 0, AddressZero]
    );
    const safeContracts = require("@gnosis.pm/safe-contracts");
    const proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafe.address,
        setupData, nonce);
    await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafe.address, setupData, nonce).then((tx) => tx.wait());

    // Writing the JSON with the initial deployment data
    let initDeployJSON = {
        "componentRegistry": componentRegistry.address,
        "agentRegistry": agentRegistry.address,
        "registriesManager": registriesManager.address,
        "serviceRegistry": serviceRegistry.address,
        "serviceManager": serviceManager.address,
        "Multisig implementation": gnosisSafeMultisig.address,
        "Service multisig": multisig,
        "agents": {
            "addresses": [agentInstances[0], agentInstances[1], agentInstances[2], agentInstances[3]],
            "privateKeys": [agentInstancesPK[0], agentInstancesPK[1], agentInstancesPK[2], agentInstancesPK[3]]
        }
    };

    // Write the json file with the setup
    const initDeployFile = "initDeploy.json";
    fs.writeFileSync(initDeployFile, JSON.stringify(initDeployJSON));
};
