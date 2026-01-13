/*global process*/

const { ethers } = require("ethers");

async function main() {
    const fs = require("fs");
    // Mainnet globals file
    const globalsFile = "scripts/deployment/l2/globals_polygon_mainnet.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    const ALCHEMY_API_KEY_MAINNET = process.env.ALCHEMY_API_KEY_MAINNET;
    const mainnetURL = "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MAINNET;
    const mainnetProvider = new ethers.providers.JsonRpcProvider(mainnetURL);
    await mainnetProvider.getBlockNumber().then((result) => {
        console.log("Current block number mainnet: " + result);
    });

    const ALCHEMY_API_KEY_MATIC = process.env.ALCHEMY_API_KEY_MATIC;
    const polygonURL = "https://polygon-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MATIC;
    const polygonProvider = new ethers.providers.JsonRpcProvider(polygonURL);
    await polygonProvider.getBlockNumber().then((result) => {
        console.log("Current block number polygon: " + result);
    });

    // FxRoot address on mainnet
    const fxRootAddress = parsedData.fxRootAddress;
    const fxRootJSON = "abis/bridges/polygon/FxRoot.json";
    let contractFromJSON = fs.readFileSync(fxRootJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const fxRootABI = parsedFile["abi"];
    const fxRoot = new ethers.Contract(fxRootAddress, fxRootABI, mainnetProvider);

    // StakingVerifier address on polygon
    const stakingVerifierAddress = parsedData.stakingVerifierAddress;
    const stakingVerifierJSON = "artifacts/contracts/staking/StakingVerifier.sol/StakingVerifier.json";
    contractFromJSON = fs.readFileSync(stakingVerifierJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const stakingVerifierABI = parsedFile["abi"];
    const stakingVerifier = new ethers.Contract(stakingVerifierAddress, stakingVerifierABI, polygonProvider);

    // serviceRegistry address on polygon
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const serviceRegistryJSON = "artifacts/contracts/ServiceRegistryL2.sol/ServiceRegistryL2.json";
    contractFromJSON = fs.readFileSync(serviceRegistryJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const serviceRegistryABI = parsedFile["abi"];
    const serviceRegistry = new ethers.Contract(serviceRegistryAddress, serviceRegistryABI, polygonProvider);

    // FxGovernorTunnel address on polygon
    const fxGovernorTunnelAddress = parsedData.bridgeMediatorAddress;

    // Proposal preparation
    console.log("Proposal 22. Change staking limits on polygon in StakingVerifier and whitelist PolySafe creator implementation addresses in ServiceRegistryL2 on polygon\n");
    const value = 0;
    const target = stakingVerifierAddress;
    let rawPayload = stakingVerifier.interface.encodeFunctionData("changeStakingLimits",
        [parsedData.minStakingDepositLimit, parsedData.timeForEmissionsLimit, parsedData.numServicesLimit,
            parsedData.apyLimit]);
    // Pack the second part of data
    let payload = ethers.utils.arrayify(rawPayload);
    let data = ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    );

    const rawPayloads = [serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", [parsedData.polySafeCreatorWithRecoveryModuleAddress, true]),
        serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", [parsedData.polySafeSameAddressMultisigAddress, true])];
    // Pack the second part of data
    const localTargets = [serviceRegistryAddress, serviceRegistryAddress];
    const localValues = [0, 0];
    // Pack the data into one contiguous buffer (to be consumed by Timelock along with a batch of unpacked L1 transactions)
    for (let i = 0; i < rawPayloads.length; i++) {
        payload = ethers.utils.arrayify(rawPayloads[i]);
        const encoded = ethers.utils.solidityPack(
            ["address", "uint96", "uint32", "bytes"],
            [localTargets[i], localValues[i], payload.length, payload]
        );
        data += encoded.slice(2);
    }


    // fxChild address polygon mainnet: 0x8397259c983751DAf40400790063935a11afa28a
    // Function to call by fxGovernorTunnelAddress: processMessageFromRoot
    // state Id: any; rootMessageSender = timelockAddress
    console.log("Polygon side payload from the fxChild to check on the fxGovernorTunnelAddress in processMessageFromRoot function:", data);

    // Send the message to mumbai receiver from the timelock
    const timelockPayload = await fxRoot.interface.encodeFunctionData("sendMessageToChild", [fxGovernorTunnelAddress, data]);

    const targets = [fxRootAddress];
    const values = [0];
    const callDatas = [timelockPayload];
    const description = "Change staking limits on polygon in StakingVerifier and whitelist PolySafe creator implementation addresses in ServiceRegistryL2 on polygon";

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
