/*global process*/

const { ethers } = require("hardhat");

async function main() {
    const fs = require("fs");
    const globalsFile = "scripts/deployment/l2/globals_celo_mainnet.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);
    const HashZero = ethers.constants.HashZero;

    const signers = await ethers.getSigners();

    // EOA address
    const EOA = signers[0];

    const deployer = await EOA.getAddress();
    console.log("EOA is:", deployer);

    const wormholeMessengerAddress = parsedData.wormholeMessengerAddress;
    const optimismMessengerAddress = parsedData.optimismMessengerAddress;
    const wormholeL1MessageRelayerAddress = parsedData.wormholeL1MessageRelayerAddress;
    const timelockAddress = parsedData.timelockAddress;
    const CM = "0x04C06323Fe3D53Deb7364c0055E1F68458Cc2570";

    // WormholeRelayer contract
    const wormholeRelayerJSON = "abis/bridges/wormhole/WormholeRelayer.json";
    let contractFromJSON = fs.readFileSync(wormholeRelayerJSON, "utf8");
    const wormholeRelayerABI = JSON.parse(contractFromJSON);
    const wormholeRelayer = await ethers.getContractAt(wormholeRelayerABI, wormholeL1MessageRelayerAddress);

    // Timelock contract
    const timelockJSON = "abis/governance/Timelock.json";
    contractFromJSON = fs.readFileSync(timelockJSON, "utf8");
    const timelockABI = JSON.parse(contractFromJSON);
    const timelock = await ethers.getContractAt(timelockABI["abi"], timelockAddress);

    // Celo chain Id
    const targetChain = 14;
    // Gas limit on Celo: 2M
    const minGasLimit = 2000000;
    // Get quote
    const quote = await wormholeRelayer["quoteEVMDeliveryPrice(uint16,uint256,uint256)"](targetChain, 0, minGasLimit);
    const whValue = quote.nativePriceQuote.toString();

    const contractAddresses = [
        parsedData.serviceRegistryAddress,
        parsedData.serviceRegistryTokenUtilityAddress,
        parsedData.serviceManagerAddress,
        parsedData.stakingVerifierAddress,
        parsedData.stakingFactoryAddress,
        "0xb4096d181C08DDF75f1A63918cCa0d1023C4e6C7" // WormholeTargetDispenserL2 on Celo
    ];

    // Get change owner payload which is the same for all the contracts
    // Use ServiceRegistry address from mainnet
    const serviceRegistry = await ethers.getContractAt("ServiceRegistryL2", "0x48b6af7B12C71f09e2fC8aF4855De4Ff54e775cA");
    const rawPayload = serviceRegistry.interface.encodeFunctionData("changeOwner", [optimismMessengerAddress]);
    const payload = ethers.utils.arrayify(rawPayload);

    // Pack the data into one contiguous buffer
    let data = "";
    for (let i = 0; i < contractAddresses.length; i++) {
        data += ethers.utils.solidityPack(
            ["address", "uint96", "uint32", "bytes"],
            [contractAddresses[i], 0, payload.length, payload]
        ).slice(2);
    }
    data = "0x" + data;

    console.log("Data:", data);

    // Proposal preparation
    console.log("Change contract owners on Celo");
    // Build the final payload to be called by the Timelock
    // sendPayloadToEvm selector with refund address as optimismMessengerAddress
    const sendPayloadSelector = "0x4b5ca6f4";
    const timelockPayload = wormholeRelayer.interface.encodeFunctionData(sendPayloadSelector, [targetChain,
        wormholeMessengerAddress, data, 0, minGasLimit, targetChain, optimismMessengerAddress]);

    // Proposal details
    //console.log("Target:", wormholeL1MessageRelayerAddress);
    //console.log("Value:", whValue);
    //console.log("Timelock payload for schedule and execute:", timelockPayload);

    // Schedule timelockPayload by a CM with a zero min delay
    const schedulePayload = timelock.interface.encodeFunctionData("schedule", [wormholeL1MessageRelayerAddress, whValue,
        timelockPayload, HashZero, HashZero, 0]);
    const executePayload = timelock.interface.encodeFunctionData("execute", [wormholeL1MessageRelayerAddress, whValue,
        timelockPayload, HashZero, HashZero]);

    // Schedule and execute
    console.log("\nTX1");
    console.log("to:", timelockAddress);
    console.log("value:", 0);
    console.log("Schedule payload:", schedulePayload);

    console.log("\nTX2");
    console.log("to:", timelockAddress);
    console.log("value:", whValue);
    console.log("Execute payload:", executePayload);

    const multisig = await ethers.getContractAt("GnosisSafe", "0x04C06323Fe3D53Deb7364c0055E1F68458Cc2570");
    const msPayload = multisig.interface.encodeFunctionData("setGuard", ["0x7bB7998b210cFfE10ca1e41f16341Abe53f76f3a"]);
    console.log(msPayload);

    console.log("\nTX3");
    console.log("to:", CM);
    console.log("value:", 0);
    console.log("Current guard set payload:", msPayload);

    // Multisend assembling: not possible over Safe App UI that does not allow selecting delegatecall explicityly
    //const safeContracts = require("@gnosis.pm/safe-contracts");
    //const multisig = await ethers.getContractAt("GnosisSafe", CM);
    //const multiSend = await ethers.getContractAt("MultiSendCallOnly", parsedData.multiSendCallOnlyAddress);
    //const nonce = await multisig.nonce();

    //const txs = [
    //    safeContracts.buildSafeTransaction({to: timelockAddress, data: schedulePayload, nonce: 0}),
    //    safeContracts.buildSafeTransaction({to: timelockAddress, data: executePayload, value: whValue, nonce: 0})
    //];
    //const safeTx = safeContracts.buildMultiSendSafeTx(multiSend, txs, nonce);

    //console.log("to:", safeTx.to);
    //console.log("value:", whValue);
    //console.log("payload:", safeTx.data);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
