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
    console.log("Proposal 6. Change GnosisSafeSameAddressMultisig implementation addresses in ServiceRegistryL2 on polygon\n");
    // De-whitelist old multisig implementation and whitelist the new one
    const rawPayloads = [serviceRegistry.interface.encodeFunctionData("changeMultisigPermission", ["0x34C895f302D0b5cf52ec0Edd3945321EB0f83dd5", false]),
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

    // fxChild address polygon mainnet: 0x8397259c983751DAf40400790063935a11afa28a
    // Function to call by fxGovernorTunnelAddress: processMessageFromRoot
    // state Id: any; rootMessageSender = timelockAddress
    console.log("Polygon side payload from the fxChild to check on the fxGovernorTunnelAddress in processMessageFromRoot function:", data);

    // Send the message to mumbai receiver from the timelock
    const timelockPayload = await fxRoot.interface.encodeFunctionData("sendMessageToChild", [fxGovernorTunnelAddress, data]);

    const targets = [fxRootAddress];
    const values = [0];
    const callDatas = [timelockPayload];
    const description = "Change GnosisSafeSameAddressMultisig implementation addresses in ServiceRegistryL2 on polygon";

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
