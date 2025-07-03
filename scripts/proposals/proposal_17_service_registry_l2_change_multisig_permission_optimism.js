/*global process*/

const { ethers } = require("ethers");

async function main() {
    const fs = require("fs");
    // Mainnet globals file
    const globalsFile = "scripts/deployment/l2/globals_mode_mainnet.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    const ALCHEMY_API_KEY_MAINNET = process.env.ALCHEMY_API_KEY_MAINNET;
    const mainnetURL = "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MAINNET;
    const mainnetProvider = new ethers.providers.JsonRpcProvider(mainnetURL);
    await mainnetProvider.getBlockNumber().then((result) => {
        console.log("Current block number mainnet: " + result);
    });

    const optimismURL = parsedData.networkURL;
    const optimismProvider = new ethers.providers.JsonRpcProvider(optimismURL);
    await optimismProvider.getBlockNumber().then((result) => {
        console.log("Current block number optimism: " + result);
    });

    // CDMProxy address on mainnet
    const CDMProxyAddress = parsedData.L1CrossDomainMessengerProxyAddress;
    const CDMProxyJSON = "abis/bridges/optimism/L1CrossDomainMessenger.json";
    let contractFromJSON = fs.readFileSync(CDMProxyJSON, "utf8");
    const CDMProxyABI = JSON.parse(contractFromJSON);
    const CDMProxy = new ethers.Contract(CDMProxyAddress, CDMProxyABI, optimismProvider);

    // OptimismMessenger address on optimism
    const optimismMessengerAddress = parsedData.bridgeMediatorAddress;
    const optimismMessengerJSON = "abis/bridges/optimism/OptimismMessenger.json";
    contractFromJSON = fs.readFileSync(optimismMessengerJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const optimismMessengerABI = parsedFile["abi"];
    const optimismMessenger = new ethers.Contract(optimismMessengerAddress, optimismMessengerABI, optimismProvider);

    // ServiceRegistryL2 address on optimism
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const serviceRegistryJSON = "artifacts/contracts/ServiceRegistryL2.sol/ServiceRegistryL2.json";
    contractFromJSON = fs.readFileSync(serviceRegistryJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const serviceRegistryABI = parsedFile["abi"];
    const serviceRegistry = new ethers.Contract(serviceRegistryAddress, serviceRegistryABI, optimismProvider);

    // Whitelist new multisig implementations
    const rawPayloads = [serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", [parsedData.recoveryModuleAddress, true]),
        serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", [parsedData.safeMultisigWithRecoveryModuleAddress, true])];
    // Pack the second part of data
    const localTargets = [serviceRegistryAddress, serviceRegistryAddress];
    const localValues = [0, 0];
    // Pack the data into one contiguous buffer (to be consumed by Timelock along with a batch of unpacked L1 transactions)
    let data = "0x";
    for (let i = 0; i < rawPayloads.length; i++) {
        const payload = ethers.utils.arrayify(rawPayloads[i]);
        const encoded = ethers.utils.solidityPack(
            ["address", "uint96", "uint32", "bytes"],
            [localTargets[i], localValues[i], payload.length, payload]
        );
        data += encoded.slice(2);
    }

    // Proposal preparation
    console.log("Proposal 17. Change multisig implementation statuses in ServiceRegistryL2 on Optimism / Base / Mode / Celo\n");
    // Build the bridge payload
    const messengerPayload = await optimismMessenger.interface.encodeFunctionData("processMessageFromSource", [data]);
    const minGasLimit = "2000000";
    // Build the final payload for the Timelock
    const timelockPayload = await CDMProxy.interface.encodeFunctionData("sendMessage", [optimismMessengerAddress,
        messengerPayload, minGasLimit]);

    const targets = [CDMProxyAddress];
    const values = [0];
    const callDatas = [timelockPayload];
    const description = "Change multisig implementation statuses in ServiceRegistryL2";

    // Proposal details
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
