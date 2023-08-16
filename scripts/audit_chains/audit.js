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

// Check service registry: network number, provider, parsed globals, configuration contracts, contract name
async function checkServiceRegistry(i, provider, globalsInstance, configContracts, contractName, log) {
    const serviceRegistry = await findContractInstance(provider, configContracts, contractName);

    // Check version
    const version = await serviceRegistry.VERSION();
    customExpect(version, "1.0.0", log + ", function: VERSION()");

    // Check Base URI
    const baseURI = await serviceRegistry.baseURI();
    customExpect(baseURI, "https://gateway.autonolas.tech/ipfs/", log + ", function: baseURI()");

    // Check owner
    const owner = await serviceRegistry.owner();
    if (contractName === "ServiceRegistry") {
        // Timelock for L1
        customExpect(owner, globalsInstance["timelockAddress"], log + ", function: owner()");
    } else {
        // BridgeMediator for L2-s
        // Note that for chiado bridgeMediatorAddress is the one with the mock Timelock, such that it is possible to
        // test cross-chain transactions. There is also a bridgeMediatorRealTimelockAddress for references to the
        // bridgeMediator contract with the real Timelock on goerli. This can be changed, but for now the setup is good for testing.
        customExpect(owner, globalsInstance["bridgeMediatorAddress"], log + ", function: owner()");
    }

    // Check manager
    const manager = await serviceRegistry.manager();
    if (contractName === "ServiceRegistry") {
        // ServiceRegistryManagerToken for L1
        customExpect(manager, globalsInstance["serviceManagerTokenAddress"], log + ", function: manager()");
    } else {
        // ServiceRegistryManager for L2
        customExpect(manager, globalsInstance["serviceManagerAddress"], log + ", function: manager()");
    }

    // Check drainer
    const drainer = await serviceRegistry.drainer();
    if (contractName === "ServiceRegistry") {
        // Timelock for L1
        customExpect(drainer, globalsInstance["treasuryAddress"], log + ", function: drainer()");
    } else {
        // BridgeMediator for L2-s
        // Note that for chiado bridgeMediatorAddress is the one with the mock Timelock, such that it is possible to
        // test cross-chain transactions. There is also a bridgeMediatorRealTimelockAddress for references to the
        // bridgeMediator contract with the real Timelock on goerli. This can be changed, but for now the setup is good for testing.
        customExpect(drainer, globalsInstance["bridgeMediatorAddress"], log + ", function: drainer()");
    }

    // Check agent registry for L1 only
    if (contractName === "ServiceRegistry") {
        const agentRegistry = await serviceRegistry.agentRegistry();
        customExpect(agentRegistry, globalsInstance["agentRegistryAddress"], log + ", function: agentRegistry()");
    }

    // Check enabled multisig implementations
    let res = await serviceRegistry.mapMultisigs(globalsInstance["gnosisSafeMultisigImplementationAddress"]);
    customExpect(res, true, log + ", function: mapMultisigs(safeMultisig)");
    res = await serviceRegistry.mapMultisigs(globalsInstance["gnosisSafeSameAddressMultisigImplementationAddress"]);
    customExpect(res, true, log + ", function: mapMultisigs(safeSameAddressMultisig)");

    //console.log(await serviceRegistry.name());
};

async function main() {
    // Read configuration from the JSON file
    const configFile = "docs/configuration.json";
    const dataFromJSON = fs.readFileSync(configFile, "utf8");
    const configs = JSON.parse(dataFromJSON);

    const numChains = configs.length;
//    // ################################# VERIFY CONTRACTS WITH REPO #################################
//    // For now gnosis chains are not supported
//    const networks = {
//        "mainnet": "etherscan",
//        "goerli": "goerli.etherscan",
//        "polygon": "polygonscan",
//        "polygonMumbai": "testnet.polygonscan"
//    }
//
//    console.log("\nVerifying the contracts... If no error is output, then the contracts are correct.");
//
//    // Traverse all chains
//    for (let i = 0; i < numChains; i++) {
//        // Skip gnosis chains
//        if (!networks[configs[i]["name"]]) {
//            continue;
//        }
//
//        console.log("\n\nNetwork:", configs[i]["name"]);
//        const network = networks[configs[i]["name"]];
//        const contracts = configs[i]["contracts"];
//
//        // Verify contracts
//        for (let j = 0; j < contracts.length; j++) {
//            console.log("Checking " + contracts[j]["name"]);
//            const execSync = require("child_process").execSync;
//            execSync("scripts/audit_chains/audit_short.sh " + network + " " + contracts[j]["name"] + " " + contracts[j]["address"]);
//        }
//    }
//    // ################################# /VERIFY CONTRACTS WITH REPO #################################

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

    //console.log(globals);
    //console.log(providers);

    // L1 contracts
    for (let i = 0; i < 2; i++) {
        let log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "ServiceRegistry";
        await checkServiceRegistry(i, providers[i], globals[i], configs[i]["contracts"], "ServiceRegistry", log);
    }

    // L2 contracts
    for (let i = 2; i < numChains; i++) {
        let log = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"] + ", contract: " + "ServiceRegistryL2";
        await checkServiceRegistry(i, providers[i], globals[i], configs[i]["contracts"], "ServiceRegistryL2", log);
    }

    // ################################# /VERIFY CONTRACTS SETUP #################################
};

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });