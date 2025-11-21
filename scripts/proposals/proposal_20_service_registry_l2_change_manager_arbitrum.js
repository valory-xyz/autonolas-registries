/*global process*/

const { ethers } = require("hardhat");
const { L1ToL2MessageGasEstimator } = require("@arbitrum/sdk/dist/lib/message/L1ToL2MessageGasEstimator");
const { EthBridger, getL2Network } = require("@arbitrum/sdk");
const { getBaseFee } = require("@arbitrum/sdk/dist/lib/utils/lib");

async function main() {
    const AddressZero = ethers.constants.AddressZero;
    const fs = require("fs");
    // Mainnet globals file
    const globalsFile = "scripts/deployment/l2/globals_arbitrum_mainnet.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    const ALCHEMY_API_KEY_MAINNET = process.env.ALCHEMY_API_KEY_MAINNET;
    const mainnetURL = "https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MAINNET;
    const mainnetProvider = new ethers.providers.JsonRpcProvider(mainnetURL);
    await mainnetProvider.getBlockNumber().then((result) => {
        console.log("Current block number mainnet: " + result);
    });

    const arbitrumURL = "https://arb1.arbitrum.io/rpc";
    const arbitrumProvider = new ethers.providers.JsonRpcProvider(arbitrumURL);
    await arbitrumProvider.getBlockNumber().then((result) => {
        console.log("Current block number arbitrum: " + result);
    });

    const timelockAddress = parsedData.timelockAddress;
    const arbitrumTimelockAddress = parsedData.bridgeMediatorAddress;

    // Registries address
    const serviceRegistryTokenUtilityAddress = parsedData.serviceRegistryTokenUtilityAddress;
    const serviceRegistryAddress = parsedData.serviceRegistryAddress;
    const serviceRegistryJSON = "artifacts/contracts/ServiceRegistryL2.sol/ServiceRegistryL2.json";
    const contractFromJSON = fs.readFileSync(serviceRegistryJSON, "utf8");
    const parsedFile = JSON.parse(contractFromJSON);
    const serviceRegistryABI = parsedFile["abi"];
    const serviceRegistry = new ethers.Contract(serviceRegistryAddress, serviceRegistryABI, arbitrumProvider);

    // Use l2Network to create an Arbitrum SDK EthBridger instance
    // We'll use EthBridger to retrieve the Inbox address
    const l2Network = await getL2Network(arbitrumProvider);
    const ethBridger = new EthBridger(l2Network);
    const inboxAddress = ethBridger.l2Network.ethBridge.inbox;
    //console.log(inboxAddress);

    // Query the required gas params using the estimateAll method in Arbitrum SDK
    const l1ToL2MessageGasEstimate = new L1ToL2MessageGasEstimator(arbitrumProvider);
    //console.log(l1ToL2MessageGasEstimate);

    // Proposal preparation
    console.log("Proposal 20. Change manager in ServiceRegistryL2 and ServiceRegistryTokenUtility on Arbitrum\n");
    // To be able to estimate the gas related params to our L1-L2 message, we need to know how many bytes of calldata out
    // retryable ticket will require
    const calldata = serviceRegistry.interface.encodeFunctionData("changeManager", [parsedData.serviceManagerProxyAddress]);

    // Users can override the estimated gas params when sending an L1-L2 message
    // Note that this is totally optional
    // Here we include and example for how to provide these overriding values
    const RetryablesGasOverrides = {
        gasLimit: {
            base: undefined, // when undefined, the value will be estimated from rpc
            min: ethers.BigNumber.from(2000000), // set a minimum gas limit, using 2M as an example
            percentIncrease: ethers.BigNumber.from(30), // how much to increase the base for buffer
        },
        maxSubmissionFee: {
            base: undefined,
            percentIncrease: ethers.BigNumber.from(1000),
        },
        maxFeePerGas: {
            base: undefined,
            percentIncrease: ethers.BigNumber.from(1000),
        },
    };

    // The estimateAll method gives us the following values for sending an L1->L2 message
    // (1) maxSubmissionCost: The maximum cost to be paid for submitting the transaction
    // (2) gasLimit: The L2 gas limit
    // (3) deposit: The total amount to deposit on L1 to cover L2 gas and L2 call value
    const l2CallValue = 0;
    const L1ToL2MessageGasParams = await l1ToL2MessageGasEstimate.estimateAll(
        {
            from: timelockAddress,
            to: serviceRegistryAddress,
            l2CallValue,
            excessFeeRefundAddress: arbitrumTimelockAddress,
            callValueRefundAddress: AddressZero,
            data: calldata,
        },
        await getBaseFee(mainnetProvider),
        mainnetProvider,
        RetryablesGasOverrides
    );
    //console.log("Current retryable base submission price is:", L1ToL2MessageGasParams.maxSubmissionCost.toString());

    // For the L2 gas price, we simply query it from the L2 provider, as we would when using L1
    const gasPriceBid = await arbitrumProvider.getGasPrice();
    console.log("L2 gas price:", gasPriceBid.toString());

    // ABI to send message to inbox
    const inboxABI = ["function createRetryableTicket(address to, uint256 l2CallValue, uint256 maxSubmissionCost, address excessFeeRefundAddress, address callValueRefundAddress, uint256 gasLimit, uint256 maxFeePerGas, bytes calldata data)"];
    const iface = new ethers.utils.Interface(inboxABI);
    const timelockCalldata = iface.encodeFunctionData("createRetryableTicket", [serviceRegistryAddress, l2CallValue,
        L1ToL2MessageGasParams.maxSubmissionCost, arbitrumTimelockAddress, AddressZero,
        L1ToL2MessageGasParams.gasLimit, gasPriceBid, calldata]);

    const L1ToL2MessageGasParams2 = await l1ToL2MessageGasEstimate.estimateAll(
        {
            from: timelockAddress,
            to: serviceRegistryTokenUtilityAddress,
            l2CallValue,
            excessFeeRefundAddress: arbitrumTimelockAddress,
            callValueRefundAddress: AddressZero,
            data: calldata,
        },
        await getBaseFee(mainnetProvider),
        mainnetProvider,
        RetryablesGasOverrides
    );

    const timelockCalldata2 = iface.encodeFunctionData("createRetryableTicket", [serviceRegistryTokenUtilityAddress, l2CallValue,
        L1ToL2MessageGasParams.maxSubmissionCost, arbitrumTimelockAddress, AddressZero,
        L1ToL2MessageGasParams.gasLimit, gasPriceBid, calldata]);

    const targets = [inboxAddress, inboxAddress];
    const values = [L1ToL2MessageGasParams.deposit.mul(10), L1ToL2MessageGasParams2.deposit.mul(10)];
    const callDatas = [timelockCalldata, timelockCalldata2];
    const description = "Change manager in ServiceRegistryL2 and ServiceRegistryTokenUtility on arbitrum";

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
