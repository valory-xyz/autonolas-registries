/* global process */

const { ethers } = require("ethers");
const fs = require("fs");

async function buildCalldataForChain({ globalsFile, mainnetProvider, l2Label }) {
    // Load per-chain globals
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    // L2 provider
    const l2URL = parsedData.networkURL;
    const l2Provider = new ethers.providers.JsonRpcProvider(l2URL);
    await l2Provider.getBlockNumber().then((n) =>
        console.log(`Current block number ${l2Label}: ${n}`)
    );

    // L1 CrossDomainMessenger proxy (on mainnet/L1)
    const CDMProxyAddress = parsedData.L1CrossDomainMessengerProxyAddress;
    const CDMProxyJSON = "abis/bridges/optimism/L1CrossDomainMessenger.json";
    const CDMProxyABI = JSON.parse(fs.readFileSync(CDMProxyJSON, "utf8"));
    const CDMProxy = new ethers.Contract(CDMProxyAddress, CDMProxyABI, mainnetProvider);

    // L2 messenger (bridge mediator) on the target L2
    const optimismMessengerAddress = parsedData.bridgeMediatorAddress;
    const optimismMessengerJSON = "abis/bridges/optimism/OptimismMessenger.json";
    const optimismMessengerABI = JSON.parse(fs.readFileSync(optimismMessengerJSON, "utf8")).abi;
    const optimismMessenger = new ethers.Contract(
        optimismMessengerAddress,
        optimismMessengerABI,
        l2Provider
    );

    // ServiceRegistryL2 on the target L2
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const serviceRegistryJSON = "artifacts/contracts/ServiceRegistryL2.sol/ServiceRegistryL2.json";
    const serviceRegistryABI = JSON.parse(fs.readFileSync(serviceRegistryJSON, "utf8"))["abi"];
    const serviceRegistry = new ethers.Contract(
        serviceRegistryAddress,
        serviceRegistryABI,
        l2Provider
    );

    // Encode the local L2 call: ServiceRegistryL2.changeManager(serviceManagerAddress)
    //TODO: replace serviceManagerTokenAddress with serviceManagerProxyAddress
    const rawPayload = serviceRegistry.interface.encodeFunctionData("changeManager", [
        parsedData.serviceManagerTokenAddress
    ]);

    // Pack data for Timelock’s L2 batch format (address, uint96 value, uint32 len, bytes payload)
    const target = serviceRegistryAddress;
    const value = 0;
    const payload = ethers.utils.arrayify(rawPayload);
    const packedData = ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    );

    // Wrap in L2 messenger call
    const messengerPayload = optimismMessenger.interface.encodeFunctionData(
        "processMessageFromSource",
        [packedData]
    );

    // Wrap in L1 messenger sendMessage
    const minGasLimit = "2000000";
    const timelockPayload = CDMProxy.interface.encodeFunctionData("sendMessage", [
        optimismMessengerAddress,
        messengerPayload,
        minGasLimit
    ]);

    return {
        l2Label,
        targetL1: CDMProxyAddress,
        valueL1: 0,
        callDataL1: timelockPayload,
        descriptionPart: `Change manager in ServiceRegistryL2 on ${l2Label}`
    };
}

async function main() {
    // --- L1 mainnet provider ---
    const ALCHEMY_API_KEY_MAINNET = process.env.ALCHEMY_API_KEY_MAINNET;
    const mainnetURL = `https://eth-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY_MAINNET}`;
    const mainnetProvider = new ethers.providers.JsonRpcProvider(mainnetURL);
    await mainnetProvider.getBlockNumber().then((n) =>
        console.log(`Current block number mainnet: ${n}`)
    );

    // --- Build per-chain call datas ---

    // 1) Optimism
    const op = await buildCalldataForChain({
        globalsFile: "scripts/deployment/l2/globals_optimism_mainnet.json",
        mainnetProvider,
        l2Label: "Optimism"
    });

    // 2) Base
    const base = await buildCalldataForChain({
        globalsFile: "scripts/deployment/l2/globals_base_mainnet.json",
        mainnetProvider,
        l2Label: "Base"
    });

    // 3) Mode
    const mode = await buildCalldataForChain({
        globalsFile: "scripts/deployment/l2/globals_mode_mainnet.json",
        mainnetProvider,
        l2Label: "Mode"
    });

    // 4) Celo Cannot be done now

    // --- Print individual proposal details ---
    for (const entry of [op, base, mode]) {
        console.log(
            `\nProposal 17. ${entry.descriptionPart}\n` +
                `target: ${entry.targetL1}\nvalue: ${entry.valueL1}\ncallData: ${entry.callDataL1}\n`
        );
    }

    // --- Aggregate for a single batched proposal (targets/values/callDatas match order: OP, Base, Mode) ---
    const targets = [op.targetL1, base.targetL1, mode.targetL1];
    const values = [op.valueL1, base.valueL1, mode.valueL1];
    const callDatas = [op.callDataL1, base.callDataL1, mode.callDataL1];
    const description = "Change manager in ServiceRegistryL2 on Optimism / Base / Mode / Celo";

    console.log("\n=== Aggregated Proposal ===");
    console.log("targets:", targets);
    console.log("values:", values);
    console.log("call datas:", callDatas);
    console.log("description:", description);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
