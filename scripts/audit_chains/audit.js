/*global ethers*/

const { ethers } = require("ethers");
const { expect } = require("chai");
const fs = require("fs");

// Custom expect that is wrapped into try / catch block
function customExpect(arg1, arg2, log) {
    try {
        expect(arg1).to.equal(arg2);
    } catch (error) {
        console.log(log);
        if (error.status) {
            console.error(error.status);
            console.log("\n");
        } else {
            console.error(error);
            console.log("\n");
        }
    }
};

// Find the contract name from the configuration data
async function findContractInstance(provider, configContracts, contractName) {
    // Get the contract number from the set of configuration contracts
    for (let i = 0; i < configContracts.length; i++) {
        if (configContracts[i]["name"] === contractName) {
            // Get the contract instance
            contractFromJSON = fs.readFileSync(configContracts[i]["abi"], "utf8");
            parsedFile = JSON.parse(contractFromJSON);
            const abi = parsedFile["abi"];
            const contractInstance = new ethers.Contract(configContracts[i]["address"], abi, provider);
            return contractInstance;
        }
    }
};

// Check the contract owner
async function checkOwner(chainId, contract, globalsInstance, log) {
    const owner = await contract.owner();
    if (chainId === "1" || chainId === "5") {
        // Timelock for L1
        customExpect(owner, globalsInstance["timelockAddress"], log + ", function: owner()");
    } else {
        // BridgeMediator for L2-s
        // Note that for chiado bridgeMediatorAddress is the one with the mock Timelock (bridgeMediatorMockTimelockAddress)
        // This is done in such a way because it is easier to test cross-chain transactions, as it's not possible via tenderly.
        // This can be changed at any time for the bridgeMediator contract with the real Timelock on goerli.
        customExpect(owner, globalsInstance["bridgeMediatorAddress"], log + ", function: owner()");
    }
}

// Check component registry: chain Id, provider, parsed globals, configuration contracts, contract name
// Component Registry resides on L1 only
async function checkComponentRegistry(chainId, provider, globalsInstance, configContracts, contractName, log) {
    const componentRegistry = await findContractInstance(provider, configContracts, contractName);

    // Check version
    const version = await componentRegistry.VERSION();
    customExpect(version, "1.0.0", log + ", function: VERSION()");

    // Check Base URI
    const baseURI = await componentRegistry.baseURI();
    customExpect(baseURI, "https://gateway.autonolas.tech/ipfs/", log + ", function: baseURI()");

    // Check owner
    checkOwner(chainId, componentRegistry, globalsInstance, log);

    // Check manager
    const manager = await componentRegistry.manager();
    customExpect(manager, globalsInstance["registriesManagerAddress"], log + ", function: manager()");
};

// Check agent registry: chain Id, provider, parsed globals, configuration contracts, contract name
// Agent Registry resides on L1 only
async function checkAgentRegistry(chainId, provider, globalsInstance, configContracts, contractName, log) {
    const agentRegistry = await findContractInstance(provider, configContracts, contractName);

    // Check version
    const version = await agentRegistry.VERSION();
    customExpect(version, "1.0.0", log + ", function: VERSION()");

    // Check Base URI
    const baseURI = await agentRegistry.baseURI();
    customExpect(baseURI, "https://gateway.autonolas.tech/ipfs/", log + ", function: baseURI()");

    // Check owner
    checkOwner(chainId, agentRegistry, globalsInstance, log);

    // Check manager
    const manager = await agentRegistry.manager();
    customExpect(manager, globalsInstance["registriesManagerAddress"], log + ", function: manager()");

    // Check component registry for L1 only
    const componentRegistry = await agentRegistry.componentRegistry();
    customExpect(componentRegistry, globalsInstance["componentRegistryAddress"], log + ", function: componentRegistry()");
};

// Check service registry: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkServiceRegistry(chainId, provider, globalsInstance, configContracts, contractName, log) {
    const serviceRegistry = await findContractInstance(provider, configContracts, contractName);

    // Check version
    const version = await serviceRegistry.VERSION();
    customExpect(version, "1.0.0", log + ", function: VERSION()");

    // Check Base URI
    const baseURI = await serviceRegistry.baseURI();
    customExpect(baseURI, "https://gateway.autonolas.tech/ipfs/", log + ", function: baseURI()");

    // Check owner
    checkOwner(chainId, serviceRegistry, globalsInstance, log);

    // Check manager
    const manager = await serviceRegistry.manager();
    if (chainId === "1" || chainId === "5") {
        // ServiceRegistryManagerToken for L1
        customExpect(manager, globalsInstance["serviceManagerTokenAddress"], log + ", function: manager()");
    } else {
        // ServiceRegistryManager for L2
        customExpect(manager, globalsInstance["serviceManagerAddress"], log + ", function: manager()");
    }

    // Check drainer
    const drainer = await serviceRegistry.drainer();
    if (chainId === "1" || chainId === "5") {
        // Treasury for L1
        customExpect(drainer, globalsInstance["treasuryAddress"], log + ", function: drainer()");
    } else {
        // BridgeMediator for L2-s
        // Note that for chiado bridgeMediatorAddress is the one with the mock Timelock (bridgeMediatorMockTimelockAddress)
        // See the detailed explanation above
        customExpect(drainer, globalsInstance["bridgeMediatorAddress"], log + ", function: drainer()");
    }

    // Check agent registry for L1 only
    if (chainId === "1" || chainId === "5") {
        const agentRegistry = await serviceRegistry.agentRegistry();
        customExpect(agentRegistry, globalsInstance["agentRegistryAddress"], log + ", function: agentRegistry()");
    }

    // Check enabled multisig implementations
    let res = await serviceRegistry.mapMultisigs(globalsInstance["gnosisSafeMultisigImplementationAddress"]);
    customExpect(res, true, log + ", function: mapMultisigs(safeMultisig)");
    res = await serviceRegistry.mapMultisigs(globalsInstance["gnosisSafeSameAddressMultisigImplementationAddress"]);
    customExpect(res, true, log + ", function: mapMultisigs(safeSameAddressMultisig)");
};

// Check service manager: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkServiceManager(chainId, provider, globalsInstance, configContracts, contractName, log) {
    const serviceManager = await findContractInstance(provider, configContracts, contractName);

    // Check owner
    checkOwner(chainId, serviceManager, globalsInstance, log);

    // Check service registry
    const serviceRegistry = await serviceManager.serviceRegistry();
    customExpect(serviceRegistry, globalsInstance["serviceRegistryAddress"], log + ", function: serviceRegistry()");

    // Check that the manager is not paused
    const paused = await serviceManager.paused();
    customExpect(paused, false, log + ", function: paused()");

    // Checks for L1 only
    if (chainId === "1" || chainId === "5") {
        // Version
        const version = await serviceManager.version();
        customExpect(version, "1.1.1", log + ", function: version()");

        // ServiceRegistryTokenUtility
        const serviceRegistryTokenUtility = await serviceManager.serviceRegistryTokenUtility();
        customExpect(serviceRegistryTokenUtility, globalsInstance["serviceRegistryTokenUtilityAddress"],
            log + ", function: serviceRegistryTokenUtility()");

        // OperatorWhitelist
        const operatorWhitelist = await serviceManager.operatorWhitelist();
        customExpect(operatorWhitelist, globalsInstance["operatorWhitelistAddress"], log + ", function: operatorWhitelist()");
    }
};

// Check service registry token utility: chain Id, provider, parsed globals, configuration contracts, contract name
// At the moment the check is applicable to L1 only
async function checkServiceRegistryTokenUtility(chainId, provider, globalsInstance, configContracts, contractName, log) {
    const serviceRegistryTokenUtility = await findContractInstance(provider, configContracts, contractName);

    // Check owner
    checkOwner(chainId, serviceRegistryTokenUtility, globalsInstance, log);

    // Check manager
    const manager = await serviceRegistryTokenUtility.manager();
    customExpect(manager, globalsInstance["serviceManagerTokenAddress"], log + ", function: manager()");

    // Check drainer
    const drainer = await serviceRegistryTokenUtility.drainer();
    customExpect(drainer, globalsInstance["treasuryAddress"], log + ", function: drainer()");

    // Check service registry
    const serviceRegistry = await serviceRegistryTokenUtility.serviceRegistry();
    customExpect(serviceRegistry, globalsInstance["serviceRegistryAddress"], log + ", function: serviceRegistry()");
};

// Check operator whitelist: chain Id, provider, parsed globals, configuration contracts, contract name
// At the moment the check is applicable to L1 only
async function checkOperatorWhitelist(chainId, provider, globalsInstance, configContracts, contractName, log) {
    const operatorWhitelist = await findContractInstance(provider, configContracts, contractName);

    // Check service registry
    const serviceRegistry = await operatorWhitelist.serviceRegistry();
    customExpect(serviceRegistry, globalsInstance["serviceRegistryAddress"], log + ", function: serviceRegistry()");
};

// Check gnosis safe implementation: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkGnosisSafeImplementation(chainId, provider, globalsInstance, configContracts, contractName, log) {
    const gnosisSafeImplementation = await findContractInstance(provider, configContracts, contractName);

    // Check default data length
    const defaultDataLength = Number(await gnosisSafeImplementation.DEFAULT_DATA_LENGTH());
    customExpect(defaultDataLength, 144, log + ", function: DEFAULT_DATA_LENGTH()");

    // Check Gnosis Sage setup selector
    const setupSelector = await gnosisSafeImplementation.GNOSIS_SAFE_SETUP_SELECTOR();
    customExpect(setupSelector, "0xb63e800d", log + ", function: GNOSIS_SAFE_SETUP_SELECTOR()");
};

// Check gnosis safe same address implementation: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkGnosisSafeSameAddressImplementation(chainId, provider, globalsInstance, configContracts, contractName, log) {
    const gnosisSafeSameAddressImplementation = await findContractInstance(provider, configContracts, contractName);

    // Check default data length
    const defaultDataLength = Number(await gnosisSafeSameAddressImplementation.DEFAULT_DATA_LENGTH());
    customExpect(defaultDataLength, 20, log + ", function: DEFAULT_DATA_LENGTH()");
};

async function main() {
    // Check for the API keys
    if (!process.env.ALCHEMY_API_KEY_MAINNET || !process.env.ALCHEMY_API_KEY_GOERLI ||
        !process.env.ALCHEMY_API_KEY_MATIC || !process.env.ALCHEMY_API_KEY_MUMBAI) {
        console.log("Check API keys!");
        return;
    }

    // Read configuration from the JSON file
    const configFile = "docs/configuration.json";
    const dataFromJSON = fs.readFileSync(configFile, "utf8");
    const configs = JSON.parse(dataFromJSON);

    const numChains = configs.length;
    // ################################# VERIFY CONTRACTS WITH REPO #################################
    // For now gnosis chains are not supported
    const networks = {
        "mainnet": "etherscan",
        "goerli": "goerli.etherscan",
        "polygon": "polygonscan",
        "polygonMumbai": "testnet.polygonscan"
    }

    console.log("\nVerifying deployed contracts vs the repo... If no error is output, then the contracts are correct.");

    // Traverse all chains
    for (let i = 0; i < numChains; i++) {
        // Skip gnosis chains
        if (!networks[configs[i]["name"]]) {
            continue;
        }

        console.log("\n\nNetwork:", configs[i]["name"]);
        const network = networks[configs[i]["name"]];
        const contracts = configs[i]["contracts"];

        // Verify contracts
        for (let j = 0; j < contracts.length; j++) {
            console.log("Checking " + contracts[j]["name"]);
            const execSync = require("child_process").execSync;
            execSync("scripts/audit_chains/audit_short.sh " + network + " " + contracts[j]["name"] + " " + contracts[j]["address"]);
        }
    }
    // ################################# /VERIFY CONTRACTS WITH REPO #################################

    // ################################# VERIFY CONTRACTS SETUP #################################
    const globalNames = {
        "mainnet": "scripts/deployment/globals_mainnet.json",
        "goerli": "scripts/deployment/globals_goerli.json",
        "polygon": "scripts/deployment/l2/globals_polygon_mainnet.json",
        "polygonMumbai": "scripts/deployment/l2/globals_polygon_mumbai.json",
        "gnosis": "scripts/deployment/l2/globals_gnosis_mainnet.json",
        "chiado": "scripts/deployment/l2/globals_gnosis_chiado.json"
    }

    const providerLinks = {
        "mainnet": "https://eth-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MAINNET,
        "goerli": "https://eth-goerli.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_GOERLI,
        "polygon": "https://polygon-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MATIC,
        "polygonMumbai": "https://polygon-mumbai.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MUMBAI,
        "gnosis": "https://rpc.gnosischain.com",
        "chiado": "https://rpc.chiadochain.net"
    }

    // Get all the globals processed
    const globals = new Array();
    const providers = new Array();
    for (let i = 0; i < numChains; i++) {
        const dataJSON = fs.readFileSync(globalNames[configs[i]["name"]], "utf8");
        globals.push(JSON.parse(dataJSON));
        const provider = new ethers.providers.JsonRpcProvider(providerLinks[configs[i]["name"]]);
        providers.push(provider);
    }

    console.log("\nVerifying deployed contracts setup... If no error is output, then the contracts are correct.");

    // L1 contracts
    for (let i = 0; i < 2; i++) {
        console.log("\n######## Verifying setup on CHAIN ID", configs[i]["chainId"]);

        let log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "ComponentRegistry";
        await checkComponentRegistry(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "ComponentRegistry", log);

        log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "AgentRegistry";
        await checkAgentRegistry(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "AgentRegistry", log);

        log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "ServiceRegistry";
        await checkServiceRegistry(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "ServiceRegistry", log);

        log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "ServiceManagerToken";
        await checkServiceManager(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "ServiceManagerToken", log);

        log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "ServiceRegistryTokenUtility";
        await checkServiceRegistryTokenUtility(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "ServiceRegistryTokenUtility", log);

        log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "OperatorWhitelist";
        await checkOperatorWhitelist(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "OperatorWhitelist", log);

        log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "GnosisSafeMultisig";
        await checkGnosisSafeImplementation(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "GnosisSafeMultisig", log);

        log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "GnosisSafeSameAddressMultisig";
        await checkGnosisSafeSameAddressImplementation(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "GnosisSafeSameAddressMultisig", log);
    }

    // L2 contracts
    for (let i = 2; i < numChains; i++) {
        console.log("\n######## Verifying setup on CHAIN ID", configs[i]["chainId"]);

        let log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "ServiceRegistryL2";
        await checkServiceRegistry(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "ServiceRegistryL2", log);

        log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "ServiceManager";
        await checkServiceManager(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "ServiceManager", log);

        log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "GnosisSafeMultisig";
        await checkGnosisSafeImplementation(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "GnosisSafeMultisig", log);

        log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "GnosisSafeSameAddressMultisig";
        await checkGnosisSafeSameAddressImplementation(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "GnosisSafeSameAddressMultisig", log);
    }

    // ################################# /VERIFY CONTRACTS SETUP #################################
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });