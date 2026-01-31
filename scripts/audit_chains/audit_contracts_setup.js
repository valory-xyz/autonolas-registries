/*global process*/

const { ethers } = require("ethers");
const { expect } = require("chai");
const fs = require("fs");

const verifyRepo = true;
const verifySetup = true;

// ===================== CSV CONFIG =====================
const WRITE_OWNERSHIP_CSV = true;
const OWNERSHIP_CSV_PATH = "scripts/audit_chains/ownable_owners.csv";

// Autonolas deployer (as per your requirement)
const AUTONOLAS_DEPLOYER = "0xEB2A22b27C7Ad5eeE424Fd90b376c745E60f914E";

// Minimal helper: normalize addresses (case-insensitive compare)
const norm = (a) => (a ? ethers.utils.getAddress(a) : a);

// Global accumulator for CSV rows (collected during setup checks)
const ownershipRows = [];

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
}

// Custom expect for contain clause that is wrapped into try / catch block
function customExpectContain(arg1, arg2, log) {
    try {
        expect(arg1).contain(arg2);
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
}

// Write ownership CSV
function writeOwnershipCsv(rows, outPath) {
    const headers = [
        "chain_id",
        "contract_name",
        "contract_address",
        "owner_address",
        "owner_category",
        "expected_dao_executor",
        "ownership_change_required",
    ];

    const escapeCsv = (v) => {
        if (v === null || v === undefined) return "";
        const s = String(v);
        if (s.includes('"') || s.includes(",") || s.includes("\n")) {
            return `"${s.replace(/"/g, '""')}"`;
        }
        return s;
    };

    const lines = [
        headers.join(","),
        ...rows.map((r) => headers.map((h) => escapeCsv(r[h])).join(",")),
    ];

    fs.writeFileSync(outPath, lines.join("\n"), "utf8");
    console.log(`\n[CSV] Wrote ${rows.length} rows to ${outPath}\n`);
}

// Push a row into the ownership CSV accumulator
function recordOwnershipRow(chainId, contractName, contractAddress, ownerInfo) {
    if (!WRITE_OWNERSHIP_CSV || !ownerInfo) return;

    ownershipRows.push({
        chain_id: String(chainId),
        contract_name: contractName,
        contract_address: norm(contractAddress),
        owner_address: ownerInfo.owner,
        owner_category: ownerInfo.owner_category,
        expected_dao_executor: ownerInfo.expected_dao_executor,
        ownership_change_required: ownerInfo.ownership_change_required,
    });
}

async function checkBytecode(provider, configContracts, contractName, log) {
    // Get the contract number from the set of configuration contracts
    for (let i = 0; i < configContracts.length; i++) {
        if (configContracts[i]["name"] === contractName) {
            // Get the contract instance
            const contractFromJSON = fs.readFileSync(configContracts[i]["artifact"], "utf8");
            const parsedFile = JSON.parse(contractFromJSON);
            // Forge JSON
            let bytecode = parsedFile["deployedBytecode"]["object"];
            if (bytecode === undefined) {
                // Hardhat JSON
                bytecode = parsedFile["deployedBytecode"];
            }
            const onChainCreationCode = await provider.getCode(configContracts[i]["address"]);
            // Bytecode DEBUG
            //if (contractName === "ContractName") {
            //    console.log("onChainCreationCode", onChainCreationCode);
            //    console.log("bytecode", bytecode);
            //}

            // Compare last 43 bytes as they reflect the deployed contract metadata hash
            // We cannot compare the full one since the repo deployed bytecode does not contain immutable variable info
            customExpectContain(onChainCreationCode, bytecode.slice(-86),
                log + ", address: " + configContracts[i]["address"] + ", failed bytecode comparison");
            return;
        }
    }
}

// Find the contract name from the configuration data
async function findContractInstance(provider, configContracts, contractName) {
    // Get the contract number from the set of configuration contracts
    for (let i = 0; i < configContracts.length; i++) {
        if (configContracts[i]["name"] === contractName) {
            // Get the contract instance
            let contractFromJSON = fs.readFileSync(configContracts[i]["artifact"], "utf8");

            // Additional step for the tokenomics proxy contract
            if (contractName === "ServiceManagerProxy") {
                // Get previous abi as it had ServiceManager implementation in it
                contractFromJSON = fs.readFileSync(configContracts[i - 1]["artifact"], "utf8");
            }
            const parsedFile = JSON.parse(contractFromJSON);
            const abi = parsedFile["abi"];

            const contractInstance = new ethers.Contract(configContracts[i]["address"], abi, provider);
            return contractInstance;
        }
    }
}

// Check the contract owner
async function checkOwner(chainId, contract, globalsInstance, log) {
    const owner = norm(await contract.owner());

    const expected =
        String(chainId) === "1"
            ? norm(globalsInstance["timelockAddress"])
            : norm(globalsInstance["bridgeMediatorAddress"]);

    // Keep existing verification behavior
    customExpect(owner, expected, log + ", function: owner()");

    // CSV purposes
    const ownerCategory =
        owner === norm(AUTONOLAS_DEPLOYER)
            ? "autonolas_deployer"
            : (owner === expected ? "dao_executor" : "other");

    const ownershipChangeRequired = owner === expected ? "no" : "yes";

    return {
        owner,
        expected_dao_executor: expected,
        owner_category: ownerCategory,
        ownership_change_required: ownershipChangeRequired,
    };
}


// Check component registry: chain Id, provider, parsed globals, configuration contracts, contract name
// Component Registry resides on L1 only
async function checkComponentRegistry(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const componentRegistry = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + componentRegistry.address;
    // Check version
    const version = await componentRegistry.VERSION();
    customExpect(version, "1.0.0", log + ", function: VERSION()");

    // Check Base URI
    const baseURI = await componentRegistry.baseURI();
    customExpect(baseURI, "https://gateway.autonolas.tech/ipfs/", log + ", function: baseURI()");

    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, componentRegistry, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, componentRegistry.address, ownerInfo);

    // Check manager
    const manager = await componentRegistry.manager();
    customExpect(manager, globalsInstance["registriesManagerAddress"], log + ", function: manager()");
}

// Check agent registry: chain Id, provider, parsed globals, configuration contracts, contract name
// Agent Registry resides on L1 only
async function checkAgentRegistry(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const agentRegistry = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + agentRegistry.address;
    // Check version
    const version = await agentRegistry.VERSION();
    customExpect(version, "1.0.0", log + ", function: VERSION()");

    // Check Base URI
    const baseURI = await agentRegistry.baseURI();
    customExpect(baseURI, "https://gateway.autonolas.tech/ipfs/", log + ", function: baseURI()");

    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, agentRegistry, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, agentRegistry.address, ownerInfo);

    // Check manager
    const manager = await agentRegistry.manager();
    customExpect(manager, globalsInstance["registriesManagerAddress"], log + ", function: manager()");

    // Check component registry for L1 only
    const componentRegistry = await agentRegistry.componentRegistry();
    customExpect(componentRegistry, globalsInstance["componentRegistryAddress"], log + ", function: componentRegistry()");
}

// Check service registry: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkServiceRegistry(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const serviceRegistry = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + serviceRegistry.address;
    // Check version
    const version = await serviceRegistry.VERSION();
    customExpect(version, "1.0.0", log + ", function: VERSION()");

    // Check Base URI
    const baseURI = await serviceRegistry.baseURI();
    customExpect(baseURI, "https://gateway.autonolas.tech/ipfs/", log + ", function: baseURI()");

    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, serviceRegistry, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, serviceRegistry.address, ownerInfo);

    // Check manager
    const manager = await serviceRegistry.manager();
    // ServiceRegistryManagerToken
    customExpect(manager, globalsInstance["serviceManagerProxyAddress"], log + ", function: manager()");

    // Check drainer
    const drainer = await serviceRegistry.drainer();
    if (chainId === "1") {
        // Treasury for L1
        customExpect(drainer, globalsInstance["treasuryAddress"], log + ", function: drainer()");
    } else {
        // BridgeMediator for L2-s
        // Note that for chiado bridgeMediatorAddress is the one with the mock Timelock (bridgeMediatorMockTimelockAddress)
        // See the detailed explanation above
        customExpect(drainer, globalsInstance["bridgeMediatorAddress"], log + ", function: drainer()");
    }

    // Check agent registry for L1 only
    if (chainId === "1") {
        const agentRegistry = await serviceRegistry.agentRegistry();
        customExpect(agentRegistry, globalsInstance["agentRegistryAddress"], log + ", function: agentRegistry()");
    }

    // Check enabled multisig implementations
    let res = await serviceRegistry.mapMultisigs(globalsInstance["gnosisSafeMultisigImplementationAddress"]);
    customExpect(res, true, log + ", function: mapMultisigs(safeMultisig)");
    res = await serviceRegistry.mapMultisigs(globalsInstance["gnosisSafeSameAddressMultisigImplementationAddress"]);
    customExpect(res, true, log + ", function: mapMultisigs(safeSameAddressMultisig)");
    res = await serviceRegistry.mapMultisigs(globalsInstance["recoveryModuleAddress"]);
    customExpect(res, true, log + ", function: mapMultisigs(recoveryModule)");
    res = await serviceRegistry.mapMultisigs(globalsInstance["safeMultisigWithRecoveryModuleAddress"]);
    customExpect(res, true, log + ", function: mapMultisigs(safeMultisigWithRecoveryModule)");
}

// Check service manager proxy: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkServiceManagerProxy(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const serviceManager = await findContractInstance(provider, configContracts, contractName);

    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, serviceManager, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, serviceManager.address, ownerInfo);

    log += ", address: " + serviceManager.address;

    // Check that the manager is not paused
    const paused = await serviceManager.paused();
    customExpect(paused, false, log + ", function: paused()");

    // Check service registry
    const serviceRegistry = await serviceManager.serviceRegistry();
    customExpect(serviceRegistry, globalsInstance["serviceRegistryAddress"], log + ", function: serviceRegistry()");

    // ServiceRegistryTokenUtility
    const serviceRegistryTokenUtility = await serviceManager.serviceRegistryTokenUtility();
    customExpect(serviceRegistryTokenUtility, globalsInstance["serviceRegistryTokenUtilityAddress"],
        log + ", function: serviceRegistryTokenUtility()");

    // OperatorWhitelist
    const operatorWhitelist = await serviceManager.operatorWhitelist();
    customExpect(operatorWhitelist, globalsInstance["operatorWhitelistAddress"], log + ", function: operatorWhitelist()");
}

// Check service registry token utility: chain Id, provider, parsed globals, configuration contracts, contract name
// At the moment the check is applicable to L1 only
async function checkServiceRegistryTokenUtility(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const serviceRegistryTokenUtility = await findContractInstance(provider, configContracts, contractName);

    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, serviceRegistryTokenUtility, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, serviceRegistryTokenUtility.address, ownerInfo);

    log += ", address: " + serviceRegistryTokenUtility.address;
    // Check manager
    const manager = await serviceRegistryTokenUtility.manager();
    customExpect(manager, globalsInstance["serviceManagerProxyAddress"], log + ", function: manager()");

    // Check drainer
    const drainer = await serviceRegistryTokenUtility.drainer();
    if (chainId === "1") {
        customExpect(drainer, globalsInstance["timelockAddress"], log + ", function: drainer()");
    } else {
        customExpect(drainer, globalsInstance["bridgeMediatorAddress"], log + ", function: drainer()");
    }

    // Check service registry
    const serviceRegistry = await serviceRegistryTokenUtility.serviceRegistry();
    customExpect(serviceRegistry, globalsInstance["serviceRegistryAddress"], log + ", function: serviceRegistry()");
}

// Check operator whitelist: chain Id, provider, parsed globals, configuration contracts, contract name
// At the moment the check is applicable to L1 only
async function checkOperatorWhitelist(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const operatorWhitelist = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + operatorWhitelist.address;
    // Check service registry
    const serviceRegistry = await operatorWhitelist.serviceRegistry();
    customExpect(serviceRegistry, globalsInstance["serviceRegistryAddress"], log + ", function: serviceRegistry()");
}

// Check gnosis safe implementation: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkGnosisSafeMultisig(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const gnosisSafeMultisig = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + gnosisSafeMultisig.address;
    // Check default data length
    const defaultDataLength = Number(await gnosisSafeMultisig.DEFAULT_DATA_LENGTH());
    customExpect(defaultDataLength, 144, log + ", function: DEFAULT_DATA_LENGTH()");

    // Check Gnosis Safe setup selector
    const setupSelector = await gnosisSafeMultisig.GNOSIS_SAFE_SETUP_SELECTOR();
    customExpect(setupSelector, "0xb63e800d", log + ", function: GNOSIS_SAFE_SETUP_SELECTOR()");
}

// Check gnosis safe same address implementation: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkGnosisSafeSameAddressMultisig(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const gnosisSafeSameAddressMultisig = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + gnosisSafeSameAddressMultisig.address;
    // Check default data length
    const defaultDataLength = Number(await gnosisSafeSameAddressMultisig.DEFAULT_DATA_LENGTH());
    customExpect(defaultDataLength, 20, log + ", function: DEFAULT_DATA_LENGTH()");
}

// Check staking verifier: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkStakingVerifier(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const serviceVerifier = await findContractInstance(provider, configContracts, contractName);

    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, serviceVerifier, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, serviceVerifier.address, ownerInfo);

    log += ", address: " + serviceVerifier.address;
    // Check OLAS
    const olas = await serviceVerifier.olas();
    customExpect(olas, globalsInstance["olasAddress"], log + ", function: olas()");

    // Check service registry
    const serviceRegistry = await serviceVerifier.serviceRegistry();
    customExpect(serviceRegistry, globalsInstance["serviceRegistryAddress"], log + ", function: serviceRegistry()");

    // Check service registry token utility
    const serviceRegistryTokenUtility = await serviceVerifier.serviceRegistryTokenUtility();
    customExpect(serviceRegistryTokenUtility, globalsInstance["serviceRegistryTokenUtilityAddress"], log + ", function: serviceRegistryTokenUtility()");

    // Check min staking deposit limit
    const minStakingDepositLimit = await serviceVerifier.minStakingDepositLimit();
    customExpect(minStakingDepositLimit.toString(), globalsInstance["minStakingDepositLimit"], log + ", function: minStakingDepositLimit()");

    // Check time for emissions limit
    const timeForEmissionsLimit = await serviceVerifier.timeForEmissionsLimit();
    customExpect(timeForEmissionsLimit.toString(), globalsInstance["timeForEmissionsLimit"], log + ", function: timeForEmissionsLimit()");

    // Check num services limit
    const numServicesLimit = await serviceVerifier.numServicesLimit();
    customExpect(numServicesLimit.toString(), globalsInstance["numServicesLimit"], log + ", function: numServicesLimit()");

    // Check APY limit
    const apyLimit = await serviceVerifier.apyLimit();
    customExpect(apyLimit.toString(), globalsInstance["apyLimit"], log + ", function: apyLimit()");

    // Check implementations check
    const implementationsCheck = await serviceVerifier.implementationsCheck();
    customExpect(implementationsCheck, true, log + ", function: implementationsCheck()");
}

// Check staking factory: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkStakingFactory(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const stakingFactory = await findContractInstance(provider, configContracts, contractName);

    // Check owner + record CSV
    const ownerInfo = await checkOwner(chainId, stakingFactory, globalsInstance, log);
    recordOwnershipRow(chainId, contractName, stakingFactory.address, ownerInfo);

    log += ", address: " + stakingFactory.address;
    // Check staking verifier
    const verifier = await stakingFactory.verifier();
    customExpect(verifier, globalsInstance["stakingVerifierAddress"], log + ", function: verifier()");
}

// Check RecoveryModule: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkRecoveryModule(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const recoveryModule = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + recoveryModule.address;
    // Check default data length
    const defaultDataLength = Number(await recoveryModule.DEFAULT_DATA_LENGTH());
    customExpect(defaultDataLength, 32, log + ", function: DEFAULT_DATA_LENGTH()");

    // Check recover threshold
    const recoverThreshold = Number(await recoveryModule.RECOVER_THRESHOLD());
    customExpect(recoverThreshold, 1, log + ", function: RECOVER_THRESHOLD()");

    // Check MultiSend address
    const multiSend = await recoveryModule.multiSend();
    customExpect(multiSend, globalsInstance["multiSendCallOnlyAddress"], log + ", function: multiSend()");

    // Check ServiceRegistry address
    const serviceRegistry = await recoveryModule.serviceRegistry();
    customExpect(serviceRegistry, globalsInstance["serviceRegistryAddress"], log + ", function: serviceRegistry()");
}

// Check SafeMultisigWithRecoveryModule: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkSafeMultisigWithRecoveryModule(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const safeMultisigWithRecoveryModule = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + safeMultisigWithRecoveryModule.address;
    // Check default data length
    const defaultDataLength = Number(await safeMultisigWithRecoveryModule.DEFAULT_DATA_LENGTH());
    customExpect(defaultDataLength, 64, log + ", function: DEFAULT_DATA_LENGTH()");

    // Check Safe setup selector
    const setupSelector = await safeMultisigWithRecoveryModule.SAFE_SETUP_SELECTOR();
    customExpect(setupSelector, "0xb63e800d", log + ", function: SAFE_SETUP_SELECTOR()");

    // Check enable module selector
    const enableModuleSelector = await safeMultisigWithRecoveryModule.ENABLE_MODULE_SELECTOR();
    customExpect(enableModuleSelector, "0x24292962", log + ", function: ENABLE_MODULE_SELECTOR()");

    // Check Safe master address
    const safe = await safeMultisigWithRecoveryModule.safe();
    customExpect(safe, globalsInstance["gnosisSafeAddress"], log + ", function: safe()");

    // Check Safe Factory address
    const safeProxyFactory = await safeMultisigWithRecoveryModule.safeProxyFactory();
    customExpect(safeProxyFactory, globalsInstance["gnosisSafeProxyFactoryAddress"], log + ", function: safeProxyFactory()");

    // Check Recovery Module address
    const recoveryModule = await safeMultisigWithRecoveryModule.recoveryModule();
    customExpect(recoveryModule, globalsInstance["recoveryModuleAddress"], log + ", function: safe()");
}

// Check checkPolySafeCreatorWithRecoveryModule: chain Id, provider, parsed globals, configuration contracts, contract name
async function checkPolySafeCreatorWithRecoveryModule(chainId, provider, globalsInstance, configContracts, contractName, log) {
    // Check the bytecode
    await checkBytecode(provider, configContracts, contractName, log);

    // Get the contract instance
    const polySafeCreatorWithRecoveryModule = await findContractInstance(provider, configContracts, contractName);

    log += ", address: " + polySafeCreatorWithRecoveryModule.address;
    // Check Safe master address
    const polySafeProxyFactory = await polySafeCreatorWithRecoveryModule.polySafeProxyFactory();
    customExpect(polySafeProxyFactory, globalsInstance["polySafeProxyFactoryAddress"], log + ", function: polySafeProxyFactory()");

    // Check Safe Factory address
    const polySafeProxyBytecodeHash = await polySafeCreatorWithRecoveryModule.polySafeProxyBytecodeHash();
    customExpect(polySafeProxyBytecodeHash, globalsInstance["polySafeProxyBytecodeHash"], log + ", function: polySafeProxyBytecodeHash()");

    // Check Recovery Module address
    const recoveryModule = await polySafeCreatorWithRecoveryModule.recoveryModule();
    customExpect(recoveryModule, globalsInstance["recoveryModuleAddress"], log + ", function: safe()");
}


async function main() {
    // Check for the API keys
    if (!process.env.ALCHEMY_API_KEY_MAINNET || !process.env.ALCHEMY_API_KEY_MATIC) {
        console.log("Check API keys!");
        return;
    }

    // Read configuration from the JSON file
    const configFile = "docs/configuration.json";
    const dataFromJSON = fs.readFileSync(configFile, "utf8");
    const configs = JSON.parse(dataFromJSON);

    const numChains = configs.length;

    // ################################# VERIFY CONTRACTS WITH REPO #################################
    if (verifyRepo) {
        console.log("\nVerifying deployed contracts vs the repo... If no error is output, then the contracts are correct.");

        // TODO Study https://playground.sourcify.dev/

        // Traverse all chains
        for (let i = 0; i < numChains; i++) {
            console.log("\n\nNetwork:", configs[i]["name"]);
            const contracts = configs[i]["contracts"];
            const chainId = configs[i]["chainId"];
            console.log("chainId", chainId);

            // Verify contracts
            for (let j = 0; j < contracts.length; j++) {
                console.log("Checking " + contracts[j]["name"]);
                const execSync = require("child_process").execSync;
                try {
                    execSync("scripts/audit_chains/audit_repo_contract.sh " + chainId + " " + contracts[j]["name"] + " " + contracts[j]["address"]);
                } catch (err) {
                    err.stderr.toString();
                }
            }
        }
    }
    // ################################# /VERIFY CONTRACTS WITH REPO #################################

    // ################################# VERIFY CONTRACTS SETUP #################################
    if (verifySetup) {
        const globalNames = {
            "mainnet": "scripts/deployment/globals_mainnet.json",
            "polygon": "scripts/deployment/l2/globals_polygon_mainnet.json",
            "gnosis": "scripts/deployment/l2/globals_gnosis_mainnet.json",
            "arbitrumOne": "scripts/deployment/l2/globals_arbitrum_mainnet.json",
            "optimism": "scripts/deployment/l2/globals_optimism_mainnet.json",
            "base": "scripts/deployment/l2/globals_base_mainnet.json",
            "celo": "scripts/deployment/l2/globals_celo_mainnet.json",
            "mode": "scripts/deployment/l2/globals_mode_mainnet.json"
        };

        const providerLinks = {
            "mainnet": "https://eth-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MAINNET,
            "polygon": "https://polygon-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_API_KEY_MATIC,
            "gnosis": "https://rpc.gnosischain.com",
            "arbitrumOne": "https://arb1.arbitrum.io/rpc",
            "optimism": "https://optimism.drpc.org",
            "base": "https://mainnet.base.org",
            "celo": "https://forno.celo.org",
            "mode": "https://mainnet.mode.network"
        };

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

        for (let i = 0; i < numChains; i++) {
            console.log("\n######## Verifying setup on CHAIN ID", configs[i]["chainId"]);

            const initLog = "ChainId: " + configs[i]["chainId"] + ", network: " + configs[i]["name"];
            let log;

            // L1 only contracts
            if (i == 0) {
                log = initLog + ", contract: " + "ComponentRegistry";
                await checkComponentRegistry(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "ComponentRegistry", log);

                log = initLog + ", contract: " + "AgentRegistry";
                await checkAgentRegistry(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "AgentRegistry", log);
            }

            log = initLog + ", contract: " + "ServiceRegistry";
            if (i == 0) {
                await checkServiceRegistry(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "ServiceRegistry", log);
            } else {
                // L2 contracts addition
                log += "L2";
                await checkServiceRegistry(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "ServiceRegistryL2", log);
            }

            // Skip celo for now
            if (i != 6) {
                log = initLog + ", contract: " + "ServiceManagerProxy";
                await checkServiceManagerProxy(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "ServiceManagerProxy", log);
            }

            log = initLog + ", contract: " + "ServiceRegistryTokenUtility";
            await checkServiceRegistryTokenUtility(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "ServiceRegistryTokenUtility", log);

            log = initLog + ", contract: " + "OperatorWhitelist";
            await checkOperatorWhitelist(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "OperatorWhitelist", log);

            log = initLog + ", contract: " + "GnosisSafeMultisig";
            await checkGnosisSafeMultisig(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "GnosisSafeMultisig", log);

            log = initLog + ", contract: " + "GnosisSafeSameAddressMultisig";
            await checkGnosisSafeSameAddressMultisig(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "GnosisSafeSameAddressMultisig", log);

            log = initLog + ", contract: " + "StakingVerifier";
            await checkStakingVerifier(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "StakingVerifier", log);

            log = initLog + ", contract: " + "StakingFactory";
            await checkStakingFactory(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "StakingFactory", log);

            log = initLog + ", contract: " + "RecoveryModule";
            await checkRecoveryModule(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "RecoveryModule", log);

            log = initLog + ", contract: " + "SafeMultisigWithRecoveryModule";
            await checkSafeMultisigWithRecoveryModule(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "SafeMultisigWithRecoveryModule", log);

            if (configs[i]["name"] === "polygon") {
                log = initLog + ", contract: " + "PolySafeCreatorWithRecoveryModule";
                await checkPolySafeCreatorWithRecoveryModule(configs[i]["chainId"], providers[i], globals[i], configs[i]["contracts"], "PolySafeCreatorWithRecoveryModule", log);
            }
        }

        // Write CSV once at the end of setup verification
        if (WRITE_OWNERSHIP_CSV) {
            writeOwnershipCsv(ownershipRows, OWNERSHIP_CSV_PATH);
        }
    }
    // ################################# /VERIFY CONTRACTS SETUP #################################
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });