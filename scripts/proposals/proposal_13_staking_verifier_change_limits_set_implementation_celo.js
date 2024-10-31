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

    const celoURL = "https://forno.celo.org";
    const celoProvider = new ethers.providers.JsonRpcProvider(celoURL);
    await celoProvider.getBlockNumber().then((result) => {
        console.log("Current block number celo: " + result);
    });

    const wormholeMessengerAddress = parsedData.wormholeMessengerAddress;

    // WormholeRelayer address on mainnet
    const wormholeRelayerAddress = parsedData.wormholeL1MessageRelayerAddress;
    const wormholeRelayerJSON = "abis/bridges/wormhole/WormholeRelayer.json";
    let contractFromJSON = fs.readFileSync(wormholeRelayerJSON, "utf8");
    const wormholeRelayerABI = JSON.parse(contractFromJSON);
    const wormholeRelayer = new ethers.Contract(wormholeRelayerAddress, wormholeRelayerABI, mainnetProvider);

    // StakingVerifier address on celo
    const stakingVerifierAddress = parsedData.stakingVerifierAddress;
    const stakingVerifierJSON = "artifacts/contracts/staking/StakingVerifier.sol/StakingVerifier.json";
    contractFromJSON = fs.readFileSync(stakingVerifierJSON, "utf8");
    const parsedFile = JSON.parse(contractFromJSON);
    const stakingVerifierABI = parsedFile["abi"];
    const stakingVerifier = new ethers.Contract(stakingVerifierAddress, stakingVerifierABI, celoProvider);

    // Timelock contract across the bridge must change staking limits
    const target = stakingVerifierAddress;
    const value = 0;
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

    const targetChain = 14; // celo
    const minGasLimit = "2000000";
    const transferCost = await wormholeRelayer["quoteEVMDeliveryPrice(uint16,uint256,uint256)"](targetChain, 0, minGasLimit);

    // Proposal preparation
    console.log("Proposal 13. Change staking limits on celo in StakingVerifier and whitelist StakingTokenImplementation in StakingFactory\n");
    // Build the final payload for the Timelock
    const sendPayloadSelector = "0x4b5ca6f4";
    const timelockPayload = await wormholeRelayer.interface.encodeFunctionData(sendPayloadSelector, [targetChain,
        wormholeMessengerAddress, data, 0, minGasLimit, targetChain, wormholeMessengerAddress]);

    const targets = [wormholeRelayerAddress];
    const values = [transferCost.nativePriceQuote.toString()];
    const callDatas = [timelockPayload];
    const description = "Change staking limits on celo in StakingVerifier and whitelist StakingTokenImplementation in StakingFactory";

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
