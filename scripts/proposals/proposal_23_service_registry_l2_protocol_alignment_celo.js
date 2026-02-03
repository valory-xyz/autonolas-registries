/*global process*/

const { ethers } = require("ethers");

async function main() {
    const fs = require("fs");
    // Mainnet globals file
    const globalsFile = "scripts/deployment/l2/globals_celo_mainnet.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    const ALCHEMY_API_KEY_MAINNET = process.env.ALCHEMY_API_KEY_MAINNET;
    const mainnetURL = "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MAINNET;
    const mainnetProvider = new ethers.providers.JsonRpcProvider(mainnetURL);
    await mainnetProvider.getBlockNumber().then((result) => {
        console.log("Current block number mainnet: " + result);
    });

    const celoURL = parsedData.networkURL;
    const celoProvider = new ethers.providers.JsonRpcProvider(celoURL);
    await celoProvider.getBlockNumber().then((result) => {
        console.log("Current block number celo: " + result);
    });

    // CDMProxy address on mainnet
    const CDMProxyAddress = parsedData.L1CrossDomainMessengerProxyAddress;
    const CDMProxyJSON = "abis/bridges/optimism/L1CrossDomainMessenger.json";
    let contractFromJSON = fs.readFileSync(CDMProxyJSON, "utf8");
    const CDMProxyABI = JSON.parse(contractFromJSON);
    const CDMProxy = new ethers.Contract(CDMProxyAddress, CDMProxyABI, celoProvider);

    // OptimismMessenger address on celo
    const optimismMessengerAddress = parsedData.bridgeMediatorAddress;
    const optimismMessengerJSON = "abis/bridges/optimism/OptimismMessenger.json";
    contractFromJSON = fs.readFileSync(optimismMessengerJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const optimismMessengerABI = parsedFile["abi"];
    const optimismMessenger = new ethers.Contract(optimismMessengerAddress, optimismMessengerABI, celoProvider);

    // ServiceRegistryL2 address on celo
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const serviceRegistryJSON = "artifacts/contracts/ServiceRegistryL2.sol/ServiceRegistryL2.json";
    contractFromJSON = fs.readFileSync(serviceRegistryJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const serviceRegistryABI = parsedFile["abi"];
    const serviceRegistry = new ethers.Contract(serviceRegistryAddress, serviceRegistryABI, celoProvider);

    // StakingVerifier on celo
    const stakingVerifierAddress = parsedData.stakingVerifierAddress;
    const stakingVerifierJSON = "artifacts/contracts/staking/StakingVerifier.sol/StakingVerifier.json";
    contractFromJSON = fs.readFileSync(stakingVerifierJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const stakingVerifierABI = parsedFile["abi"];
    const stakingVerifier = new ethers.Contract(stakingVerifierAddress, stakingVerifierABI, celoProvider);

    // StakingFactory on celo
    const stakingFactoryAddress = parsedData.stakingFactoryAddress;
    const stakingFactoryJSON = "artifacts/contracts/staking/StakingFactory.sol/StakingFactory.json";
    contractFromJSON = fs.readFileSync(stakingFactoryJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const stakingFactoryABI = parsedFile["abi"];
    const stakingFactory = new ethers.Contract(stakingFactoryAddress, stakingFactoryABI, celoProvider);

    // Whitelist new multisig implementations
    let rawPayloads = [serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", [parsedData.recoveryModuleAddress, true]),
        serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", [parsedData.safeMultisigWithRecoveryModuleAddress, true])];
    // Pack the second part of data
    let localTargets = [serviceRegistryAddress, serviceRegistryAddress];
    let localValues = [0, 0];
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

    // Change manager in registries
    const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;
    rawPayloads = [serviceRegistry.interface.encodeFunctionData("changeManager", [parsedData.serviceManagerProxyAddress]),
        serviceRegistry.interface.encodeFunctionData("changeManager", [parsedData.serviceManagerProxyAddress])];
    localTargets = [serviceRegistryAddress, serviceRegistryTokenUtilityAddress];
    for (let i = 0; i < rawPayloads.length; i++) {
        const payload = ethers.utils.arrayify(rawPayloads[i]);
        const encoded = ethers.utils.solidityPack(
            ["address", "uint96", "uint32", "bytes"],
            [localTargets[i], localValues[i], payload.length, payload]
        );
        data += encoded.slice(2);
    }

    // Change StakingVerifier in StakingFactory
    let rawPayload = stakingFactory.interface.encodeFunctionData("changeVerifier", [stakingVerifierAddress]);
    let target = stakingFactoryAddress;
    let value = 0;
    let payload = ethers.utils.arrayify(rawPayload);
    let encoded = ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    );
    data += encoded.slice(2);

    // Whitelist StakingToken in StakingVerifier
    rawPayload = stakingVerifier.interface.encodeFunctionData("setImplementationsStatuses",
        [[parsedData.stakingTokenAddress], [true], true]);
    target = stakingVerifierAddress;
    payload = ethers.utils.arrayify(rawPayload);
    encoded = ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    );
    data += encoded.slice(2);

    console.log("\nRaw data:", data);

    // Proposal preparation
    console.log("\nProposal 23. Protocol alignment on Celo");
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
