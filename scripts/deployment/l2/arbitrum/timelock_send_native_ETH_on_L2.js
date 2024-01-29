/*global process*/

const { ethers } = require("hardhat");
const { L1ToL2MessageGasEstimator } = require("@arbitrum/sdk/dist/lib/message/L1ToL2MessageGasEstimator");
const { EthBridger, getL2Network } = require("@arbitrum/sdk");
const { getBaseFee } = require("@arbitrum/sdk/dist/lib/utils/lib");

const main = async () => {
    // Setting up providers and wallets
    const ALCHEMY_API_KEY_SEPOLIA = process.env.ALCHEMY_API_KEY_SEPOLIA;
    const sepoliaURL = "https://eth-sepolia.g.alchemy.com/v2/" + ALCHEMY_API_KEY_SEPOLIA;
    const sepoliaProvider = new ethers.providers.JsonRpcProvider(sepoliaURL);
    await sepoliaProvider.getBlockNumber().then((result) => {
        console.log("Current block number sepolia: " + result);
    });

    const arbitrumSepoliaURL = "https://sepolia-rollup.arbitrum.io/rpc";
    const arbitrumSepoliaProvider = new ethers.providers.JsonRpcProvider(arbitrumSepoliaURL);
    await arbitrumSepoliaProvider.getBlockNumber().then((result) => {
        console.log("Current block number arbitrum sepolia: " + result);
    });

    // Get the EOA
    const account = ethers.utils.HDNode.fromMnemonic(process.env.TESTNET_MNEMONIC).derivePath("m/44'/60'/0'/0/0");
    const EOAsepolia = new ethers.Wallet(account, sepoliaProvider);
    const EOAarbitrumSepolia = new ethers.Wallet(account, arbitrumSepoliaProvider);
    console.log("EOA", EOAsepolia.address);
    if (EOAarbitrumSepolia.address == EOAsepolia.address) {
        console.log("Correct wallet setup");
    }

    const mockTimelockAddress = "0x31D3202d8744B16A120117A053459DDFAE93c855";
    const mockTimelock = (await ethers.getContractAt("MockTimelock", mockTimelockAddress)).connect(EOAsepolia);
    //console.log(mockTimelock.address);

    // Use l2Network to create an Arbitrum SDK EthBridger instance
    // We'll use EthBridger to retrieve the Inbox address
    const l2Network = await getL2Network(arbitrumSepoliaProvider);
    const ethBridger = new EthBridger(l2Network);
    const inboxAddress = ethBridger.l2Network.ethBridge.inbox;
    console.log(inboxAddress);

    // Query the required gas params using the estimateAll method in Arbitrum SDK
    const l1ToL2MessageGasEstimate = new L1ToL2MessageGasEstimator(arbitrumSepoliaProvider);
    //console.log(l1ToL2MessageGasEstimate);

    // Users can override the estimated gas params when sending an L1-L2 message
    // Note that this is totally optional
    // Here we include and example for how to provide these overriding values
    const RetryablesGasOverrides = {
        gasLimit: {
            base: undefined, // when undefined, the value will be estimated from rpc
            min: ethers.BigNumber.from(10000), // set a minimum gas limit, using 10000 as an example
            percentIncrease: ethers.BigNumber.from(30), // how much to increase the base for buffer
        },
        maxSubmissionFee: {
            base: undefined,
            percentIncrease: ethers.BigNumber.from(30),
        },
        maxFeePerGas: {
            base: undefined,
            percentIncrease: ethers.BigNumber.from(30),
        },
    };

    // This calldata is just to send funds
    const calldata = "0x";

    // The estimateAll method gives us the following values for sending an L1->L2 message
    // (1) maxSubmissionCost: The maximum cost to be paid for submitting the transaction
    // (2) gasLimit: The L2 gas limit
    // (3) deposit: The total amount to deposit on L1 to cover L2 gas and L2 call value
    let l2CallValue = 0;
    l2CallValue = ethers.utils.parseUnits("0.005");
    // console.log("l2CallValue", l2CallValue);

    // The estimate itself does not provide any ETH l2CallValue, as the value is supposed to be sitting on L2 side already
    const L1ToL2MessageGasParams = await l1ToL2MessageGasEstimate.estimateAll(
        {
            from: await mockTimelock.address,
            to: await EOAarbitrumSepolia.address,
            l2CallValue: 0,
            excessFeeRefundAddress: await EOAarbitrumSepolia.address,
            callValueRefundAddress: await EOAarbitrumSepolia.address,
            data: calldata,
        },
        await getBaseFee(sepoliaProvider),
        sepoliaProvider,
        RetryablesGasOverrides //if provided, it will override the estimated values. Note that providing "RetryablesGasOverrides" is totally optional.
    );
    console.log("Current retryable base submission price is:", L1ToL2MessageGasParams.maxSubmissionCost.toString());

    // For the L2 gas price, we simply query it from the L2 provider, as we would when using L1
    const gasPriceBid = await arbitrumSepoliaProvider.getGasPrice();
    console.log("L2 gas price:", gasPriceBid.toString());

    // ABI to send message to inbox
    // Unsafe version of sending messages to inbox, without full value verification
    // for example, for just collecting funds from the mapped address on L2
    const inboxABI = ["function unsafeCreateRetryableTicket(address to, uint256 l2CallValue, uint256 maxSubmissionCost, address excessFeeRefundAddress, address callValueRefundAddress, uint256 gasLimit, uint256 maxFeePerGas, bytes calldata data)"];
    const iface = new ethers.utils.Interface(inboxABI);
    const timeloclCalldata = iface.encodeFunctionData("unsafeCreateRetryableTicket", [EOAarbitrumSepolia.address, l2CallValue,
        L1ToL2MessageGasParams.maxSubmissionCost, EOAarbitrumSepolia.address, EOAarbitrumSepolia.address,
        L1ToL2MessageGasParams.gasLimit, gasPriceBid, calldata]);
    const value = L1ToL2MessageGasParams.deposit;
    // console.log(timeloclCalldata);
    // console.log("value", value);

    // Hardcode the gas limit in order to make sure the tx goes through
    const gasLimit = 200000;
    const tx = await mockTimelock.execute(inboxAddress, value, timeloclCalldata, {value: value, gasLimit: gasLimit});

    console.log(tx.hash);
    await tx.wait();
};

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
