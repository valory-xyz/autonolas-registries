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

    // StakingVerifier address on celo
    const stakingVerifierAddress = parsedData.stakingVerifierAddress;
    const stakingVerifierJSON = "artifacts/contracts/staking/StakingVerifier.sol/StakingVerifier.json";
    let contractFromJSON = fs.readFileSync(stakingVerifierJSON, "utf8");
    const parsedFile = JSON.parse(contractFromJSON);
    const stakingVerifierABI = parsedFile["abi"];
    const stakingVerifier = new ethers.Contract(stakingVerifierAddress, stakingVerifierABI, mainnetProvider);

    // Proposal preparation
    console.log("Proposal 14. Change staking limits on mainnet in StakingVerifier and whitelist StakingTokenImplementation in StakingFactory\n");
    // Timelock to change staking limits
    const timelockPayload = stakingVerifier.interface.encodeFunctionData("changeStakingLimits",
        [parsedData.minStakingDepositLimit, parsedData.timeForEmissionsLimit, parsedData.numServicesLimit,
            parsedData.apyLimit]);

    const timelockPayload2 = stakingVerifier.interface.encodeFunctionData("setImplementationsStatuses",
        [[parsedData.stakingTokenAddress], [true], true]);

    const targets = [stakingVerifierAddress, stakingVerifierAddress];
    const values = [0, 0];
    const callDatas = [timelockPayload, timelockPayload2];
    const description = "Change staking limits on mainnet in StakingVerifier and whitelist StakingTokenImplementation in StakingFactory";

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
