/*global process*/

const { ethers } = require("ethers");

async function main() {
    const fs = require("fs");
    // Polygon mainnet globals file
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    const ALCHEMY_API_KEY_MAINNET = process.env.ALCHEMY_API_KEY_MAINNET;
    const mainnetURL = "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MAINNET;
    const mainnetProvider = new ethers.providers.JsonRpcProvider(mainnetURL);
    await mainnetProvider.getBlockNumber().then((result) => {
        console.log("Current block number mainnet: " + result);
    });

    const gnosisURL = "https://rpc.gnosischain.com";
    const gnosisProvider = new ethers.providers.JsonRpcProvider(gnosisURL);
    await gnosisProvider.getBlockNumber().then((result) => {
        console.log("Current block number gnosis: " + result);
    });
    

    // AMBProxy address on mainnet
    const AMBProxyAddress = parsedData.AMBContractProxyForeignAddress;
    const AMBProxyJSON = "abis/bridges/gnosis/EternalStorageProxy.json";
    let contractFromJSON = fs.readFileSync(AMBProxyJSON, "utf8");
    const AMBProxyABI = JSON.parse(contractFromJSON);
    const AMBProxy = new ethers.Contract(AMBProxyAddress, AMBProxyABI, mainnetProvider);

    // Test deployed HomeMediator address on chiado
    const homeMediatorAddress = parsedData.bridgeMediatorAddress;
    const homeMediatorJSON = "abis/bridges/gnosis/HomeMediator.json";
    contractFromJSON = fs.readFileSync(homeMediatorJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const homeMediatorABI = parsedFile["abi"];
    const homeMediator = new ethers.Contract(homeMediatorAddress, homeMediatorABI, gnosisProvider);

    // ServiceRegistryL2 address on gnosis
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const serviceRegistryJSON = "artifacts/contracts/ServiceRegistryL2.sol/ServiceRegistryL2.json";
    contractFromJSON = fs.readFileSync(serviceRegistryJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const serviceRegistryABI = parsedFile["abi"];
    const serviceRegistry = new ethers.Contract(serviceRegistryAddress, serviceRegistryABI, gnosisProvider);

    // De-whitelist old multisig implementation and whitelist the new one
    const rawPayloads = [serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", ["0x3d77596beb0f130a4415df3D2D8232B3d3D31e44", false]),
        serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", [parsedData.gnosisSafeSameAddressMultisigImplementationAddress, true])];
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
    console.log("Proposal 5. Change GnosisSafeSameAddressMultisig implementation addresses in ServiceRegistryL2 on gnosis\n");
    const mediatorPayload = await homeMediator.interface.encodeFunctionData("processMessageFromForeign", [data]);

    // AMBContractProxyHomeAddress on gnosis mainnet: 0x75Df5AF045d91108662D8080fD1FEFAd6aA0bb59
    // Function to call by homeMediator: processMessageFromForeign
    console.log("AMBContractProxyHomeAddress to call homeMediator's processMessageFromForeign function with the data:", data);

    const requestGasLimit = "2000000";
    const timelockPayload = await AMBProxy.interface.encodeFunctionData("requireToPassMessage", [homeMediatorAddress,
        mediatorPayload, requestGasLimit]);

    const targets = [AMBProxyAddress];
    const values = [0];
    const callDatas = [timelockPayload];
    const description = "Change GnosisSafeSameAddressMultisig implementation addresses in ServiceRegistryL2 on gnosis";

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
