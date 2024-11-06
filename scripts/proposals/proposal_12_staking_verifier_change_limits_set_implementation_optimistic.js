/*global process*/

const { ethers } = require("ethers");

async function main() {
    const fs = require("fs");
    // Mainnet globals file
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    const ALCHEMY_API_KEY_MAINNET = process.env.ALCHEMY_API_KEY_MAINNET;
    const mainnetURL = "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MAINNET;
    const mainnetProvider = new ethers.providers.JsonRpcProvider(mainnetURL);
    await mainnetProvider.getBlockNumber().then((result) => {
        console.log("Current block number mainnet: " + result);
    });

    const optimisticURL = parsedData.networkURL;
    const optimisticProvider = new ethers.providers.JsonRpcProvider(optimisticURL);
    await optimisticProvider.getBlockNumber().then((result) => {
        console.log("Current block number optimistic: " + result);
    });

    // CDMProxy address on mainnet
    const CDMProxyAddress = parsedData.L1CrossDomainMessengerProxyAddress;
    const CDMProxyJSON = "abis/bridges/optimism/L1CrossDomainMessenger.json";
    let contractFromJSON = fs.readFileSync(CDMProxyJSON, "utf8");
    const CDMProxyABI = JSON.parse(contractFromJSON);
    const CDMProxy = new ethers.Contract(CDMProxyAddress, CDMProxyABI, optimisticProvider);

    // OptimismMessenger address on optimism
    const optimismMessengerAddress = parsedData.bridgeMediatorAddress;
    const optimismMessengerJSON = "abis/bridges/optimism/OptimismMessenger.json";
    contractFromJSON = fs.readFileSync(optimismMessengerJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const optimismMessengerABI = parsedFile["abi"];
    const optimismMessenger = new ethers.Contract(optimismMessengerAddress, optimismMessengerABI, optimisticProvider);

    // StakingVerifier address on optimism
    const stakingVerifierAddress = parsedData.stakingVerifierAddress;
    const stakingVerifierJSON = "artifacts/contracts/staking/StakingVerifier.sol/StakingVerifier.json";
    contractFromJSON = fs.readFileSync(stakingVerifierJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const stakingVerifierABI = parsedFile["abi"];
    const stakingVerifier = new ethers.Contract(stakingVerifierAddress, stakingVerifierABI, optimisticProvider);

    // ServiceRegistryL2 address on optimism
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const serviceRegistryJSON = "artifacts/contracts/ServiceRegistryL2.sol/ServiceRegistryL2.json";
    contractFromJSON = fs.readFileSync(serviceRegistryJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const serviceRegistryABI = parsedFile["abi"];
    const serviceRegistry = new ethers.Contract(serviceRegistryAddress, serviceRegistryABI, optimisticProvider);

    // Timelock contract across the bridge must change staking limits
    const value = 0;
    let target = stakingVerifierAddress;
    let rawPayload = stakingVerifier.interface.encodeFunctionData("changeStakingLimits",
        [parsedData.minStakingDepositLimit, parsedData.timeForEmissionsLimit, parsedData.numServicesLimit,
            parsedData.apyLimit]);
    // Pack the second part of data
    let payload = ethers.utils.arrayify(rawPayload);
    let data = ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    );

    rawPayload = stakingVerifier.interface.encodeFunctionData("setImplementationsStatuses",
        [[parsedData.stakingTokenAddress], [true], true]);
    payload = ethers.utils.arrayify(rawPayload);
    data += ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    ).slice(2);

    target = serviceRegistryAddress;
    // Optimism
    const oldMultisigImplementationAddress = "0xE43d4F4103b623B61E095E8bEA34e1bc8979e168";
    // Base
    //const oldMultisigImplementationAddress = "0xBb7e1D6Cb6F243D6bdE81CE92a9f2aFF7Fbe7eac";
    rawPayload = serviceRegistry.interface.encodeFunctionData("changeMultisigPermission",
        [oldMultisigImplementationAddress, false]);
    payload = ethers.utils.arrayify(rawPayload);
    data += ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    ).slice(2);

    const multisigImplementationAddress = parsedData.gnosisSafeMultisigImplementationAddress;
    rawPayload = serviceRegistry.interface.encodeFunctionData("changeMultisigPermission",
        [multisigImplementationAddress, true]);
    payload = ethers.utils.arrayify(rawPayload);
    data += ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    ).slice(2);

    // Proposal preparation
    console.log("Proposal 12. Change staking limits on optimism in StakingVerifier and whitelist StakingTokenImplementation in StakingFactory\n");
    // Build the bridge payload
    const messengerPayload = await optimismMessenger.interface.encodeFunctionData("processMessageFromSource", [data]);
    const minGasLimit = "2000000";
    // Build the final payload for the Timelock
    const timelockPayload = await CDMProxy.interface.encodeFunctionData("sendMessage", [optimismMessengerAddress,
        messengerPayload, minGasLimit]);

    const targets = [CDMProxyAddress];
    const values = [0];
    const callDatas = [timelockPayload];
    const description = "Change staking limits on optimism in StakingVerifier and whitelist StakingTokenImplementation in StakingFactory";

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
