/*global process*/
// One-off estimator for proposal 24's Arbitrum de-whitelist retryable (mirrors proposal_15's method:
// SDK estimateAll with default base + big buffers, then value = deposit * 10). Prints concrete numbers to
// bake into the staging builder. Run: npx hardhat run scripts/proposals/proposal_24_dewhitelist_sameaddr_and_unnominate/estimate_arb_submission_cost.js
const { ethers } = require("hardhat");
const { L1ToL2MessageGasEstimator } = require("@arbitrum/sdk/dist/lib/message/L1ToL2MessageGasEstimator");
const { EthBridger, getL2Network } = require("@arbitrum/sdk");
const { getBaseFee } = require("@arbitrum/sdk/dist/lib/utils/lib");

async function main() {
    const AddressZero = ethers.constants.AddressZero;
    const TIMELOCK = "0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE";
    const ARB_MEDIATOR_L2 = "0x4d30F68F5AA342d296d4deE4bB1Cacca912dA70F"; // aliased L1 Timelock on L2
    const SRL2_ARBITRUM = "0xE3607b00E75f6405248323A9417ff6b39B244b50";
    const SAME_ARBITRUM = "0xBb7e1D6Cb6F243D6bdE81CE92a9f2aFF7Fbe7eac";

    const ALCHEMY_API_KEY_MAINNET = process.env.ALCHEMY_API_KEY_MAINNET;
    const mainnetProvider = new ethers.providers.JsonRpcProvider(
        ALCHEMY_API_KEY_MAINNET ? ("https://eth-mainnet.g.alchemy.com/v2/" + ALCHEMY_API_KEY_MAINNET)
            : "https://ethereum-rpc.publicnode.com");
    const arbitrumProvider = new ethers.providers.JsonRpcProvider("https://arb1.arbitrum.io/rpc");

    // inner L2 call: ServiceRegistryL2.changeMultisigPermission(SAME_ARBITRUM, false)
    const iReg = new ethers.utils.Interface(["function changeMultisigPermission(address,bool)"]);
    const calldata = iReg.encodeFunctionData("changeMultisigPermission", [SAME_ARBITRUM, false]);

    const l2Network = await getL2Network(arbitrumProvider);
    const ethBridger = new EthBridger(l2Network);
    const inboxAddress = ethBridger.l2Network.ethBridge.inbox;
    const est = new L1ToL2MessageGasEstimator(arbitrumProvider);

    const overrides = {
        gasLimit: { base: undefined, min: ethers.BigNumber.from(2000000), percentIncrease: ethers.BigNumber.from(30) },
        maxSubmissionFee: { base: undefined, percentIncrease: ethers.BigNumber.from(1000) },
        maxFeePerGas: { base: undefined, percentIncrease: ethers.BigNumber.from(1000) },
    };

    const p = await est.estimateAll(
        { from: TIMELOCK, to: SRL2_ARBITRUM, l2CallValue: 0,
            excessFeeRefundAddress: ARB_MEDIATOR_L2, callValueRefundAddress: AddressZero, data: calldata },
        await getBaseFee(mainnetProvider), mainnetProvider, overrides);

    // Bake the SDK's BUFFERED maxFeePerGas (the maxFeePerGas override above is +1000%), NOT the raw current
    // L2 gas price: msg.value being overfunded does not change the ticket's gas bid, so the explicit
    // maxFeePerGas argument must itself carry headroom or the retryable can fail to auto-redeem if L2 gas rises.
    const gasPriceBid = await arbitrumProvider.getGasPrice(); // raw, for reference only
    const value = p.deposit.mul(10); // deposit already uses the buffered maxFeePerGas

    console.log("inbox:", inboxAddress);
    console.log("ARB_MAX_SUBMISSION_COST =", p.maxSubmissionCost.toString());
    console.log("ARB_GAS_LIMIT          =", p.gasLimit.toString());
    console.log("ARB_MAX_FEE_PER_GAS    =", p.maxFeePerGas.toString(), "(buffered; raw gasPrice =", gasPriceBid.toString() + ")");
    console.log("deposit                =", p.deposit.toString());
    console.log("ARB_RETRYABLE_VALUE    = deposit*10 =", value.toString());
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
