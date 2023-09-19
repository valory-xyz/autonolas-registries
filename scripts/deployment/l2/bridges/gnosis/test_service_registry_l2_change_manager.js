/*global process*/

const { ethers } = require("ethers");

async function main() {
    const ALCHEMY_API_KEY_GOERLI = process.env.ALCHEMY_API_KEY_GOERLI;
    const goerliURL = "https://eth-goerli.g.alchemy.com/v2/" + ALCHEMY_API_KEY_GOERLI;
    const goerliProvider = new ethers.providers.JsonRpcProvider(goerliURL);
    await goerliProvider.getBlockNumber().then((result) => {
        console.log("Current block number goerli: " + result);
    });

    const chiadoURL = "https://rpc.chiadochain.net";
    const chiadoProvider = new ethers.providers.JsonRpcProvider(chiadoURL);
    await chiadoProvider.getBlockNumber().then((result) => {
        console.log("Current block number chiado: " + result);
    });

    const fs = require("fs");
    // AMBProxy address on goerli
    const AMBProxyAddress = "0x87A19d769D875964E9Cd41dDBfc397B2543764E6";
    const AMBProxyJSON = "abis/bridges/gnosis/EternalStorageProxy.json";
    let contractFromJSON = fs.readFileSync(AMBProxyJSON, "utf8");
    const AMBProxyABI = JSON.parse(contractFromJSON);
    const AMBProxy = new ethers.Contract(AMBProxyAddress, AMBProxyABI, goerliProvider);

    // Test deployed HomeMediator address on chiado
    const homeMediatorAddress = "0x0a50009D55Ed5700ac8FF713709d5Ad5fa843896";
    const homeMediatorJSON = "abis/bridges/gnosis/HomeMediator.json";
    contractFromJSON = fs.readFileSync(homeMediatorJSON, "utf8");
    let parsedFile = JSON.parse(contractFromJSON);
    const homeMediatorABI = parsedFile["abi"];
    const homeMediator = new ethers.Contract(homeMediatorAddress, homeMediatorABI, chiadoProvider);

    // Mock Timelock contract address on goerli (has AMBProxy address in it already)
    const mockTimelockAddress = "0x5b03476a21e9c7cEB8dB1Bd9F24664e480FDcc43";
    const mockTimelockJSON = "abis/bridges/gnosis/test/MockTimelock.json";
    contractFromJSON = fs.readFileSync(mockTimelockJSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const mockTimelockABI = parsedFile["abi"];
    const mockTimelock = new ethers.Contract(mockTimelockAddress, mockTimelockABI, goerliProvider);

    // ServiceRegistryL2 address on chiado
    const serviceRegistryL2Address = "0x31D3202d8744B16A120117A053459DDFAE93c855";
    const serviceRegistryL2JSON = "artifacts/contracts/ServiceRegistryL2.sol/ServiceRegistryL2.json";
    contractFromJSON = fs.readFileSync(serviceRegistryL2JSON, "utf8");
    parsedFile = JSON.parse(contractFromJSON);
    const serviceRegistryL2ABI = parsedFile["abi"];
    const serviceRegistryL2 = new ethers.Contract(serviceRegistryL2Address, serviceRegistryL2ABI, chiadoProvider);

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAgoerli = new ethers.Wallet(account, goerliProvider);
    const EOAchiado = new ethers.Wallet(account, chiadoProvider);
    console.log("EOA address",EOAgoerli.address);
    if (EOAchiado.address == EOAgoerli.address) {
        console.log("Correct wallet setup");
    }

    // Mock Timelock contract across the bridge must change the manager address
    const globalsFile = fs.readFileSync("globals.json", "utf8");
    parsedFile = JSON.parse(globalsFile);
    const rawPayload = serviceRegistryL2.interface.encodeFunctionData("changeManager", [parsedFile.serviceManagerTokenAddress]);
    // Pack the second part of data
    const target = serviceRegistryL2Address;
    const value = 0;
    const payload = ethers.utils.arrayify(rawPayload);
    const data = ethers.utils.solidityPack(
        ["address", "uint96", "uint32", "bytes"],
        [target, value, payload.length, payload]
    );

    // Build the final payload to be passed from the imaginary Timelock
    const mediatorPayload = await homeMediator.interface.encodeFunctionData("processMessageFromForeign", [data]);
    const requestGasLimit = "2000000";
    const timelockPayload = await AMBProxy.interface.encodeFunctionData("requireToPassMessage", [homeMediatorAddress,
        mediatorPayload, requestGasLimit]);

    // Send the message to chiado receiver
    const tx = await mockTimelock.connect(EOAgoerli).execute(timelockPayload);
    console.log("Timelock data execution hash", tx.hash);
    await tx.wait();

    // Wait for the event of a processed data on chiado
    // catch NewFxMessage event from serviceRegistryL2 and MessageReceived event from homeMediator
    // Compare the data sent and the data from the NewFxMessage event that must match
    // MessageReceived(uint256 indexed stateId, address indexed sender, bytes message)
    let waitForEvent = true;
    while (waitForEvent) {
        // Check for the last 100 blocks in order to catch the event
        const events = await homeMediator.queryFilter("MessageReceived", -200);
        events.forEach((item) => {
            const msg = item["args"]["data"];
            if (msg == data) {
                console.log("Event MessageReceived. Message in chiado:", msg);
                waitForEvent = false;
            }
        });
        // Continue waiting for the event if none was received
        if (waitForEvent) {
            console.log("Waiting for the receive event, next update in 5 minutes ...");
            // Sleep for a minute
            await new Promise(r => setTimeout(r, 300000));
        }
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
