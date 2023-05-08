/*global process*/

const { ethers } = require("hardhat");

async function main() {
    // Get the multisig data from file
    const fs = require("fs");
    // "multisig_info.json" test file is located in the same folder of this script
    const dataJSON = "multisig_info.json";
    const dataFromJSON = fs.readFileSync(dataJSON, "utf8");
    const parsedFile = JSON.parse(dataFromJSON);

    // Set of updated service multisig owners
    const agentInstances = parsedFile["agentInstances"];
    // Service multisig address
    const serviceMultisigAddress = parsedFile["serviceMultisigAddress"];
    // Service owner address (current multisig owner)
    const serviceOwnerAddress = parsedFile["serviceOwnerAddress"];
    // Safe MultisendCallOnly contract address
    const multisendAddress = parsedFile["multisendAddress"];
    // Resulting threshold is always one
    const threshold = 1;
    // Current service multisig nonce
    const nonce = parsedFile["nonce"];
    // Chain Id
    const chainId = parsedFile["chainId"];
    const sentinelOwners = "0x" + "0".repeat(39) + "1";

    // Sanity check
    if (!agentInstances || agentInstances.length == 0 || !serviceMultisigAddress || !serviceOwnerAddress ||
        !multisendAddress || !nonce || !chainId) {
        return;
    }

    // Get the Safe master contract and multiSend one for ABI purposes
    const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
    const gnosisSafe = await GnosisSafe.deploy();
    await gnosisSafe.deployed();

    const MultiSend = await ethers.getContractFactory("MultiSendCallOnly");
    const multiSend = await MultiSend.deploy();
    await multiSend.deployed();

    const safeContracts = require("@gnosis.pm/safe-contracts");

    // Change existent multisig owners and a threshold in a multisend transaction using the service owner access
    let callData = [];
    let txs = [];
    // In case of more than one agent instances we need to add all of them except for the first one,
    // after which swap the first agent instance with the current service owner, and then update the threshold
    if (agentInstances.length > 1) {
        // Remove agent instances as original multisig owners from the last one and leave only the first one
        // Note that the prevOwner is the very first added address as it corresponds to the reverse order of added addresses
        // The order in the gnosis safe multisig is as follows: sentinelOwners => agentInstances[last].address => ... =>
        // => newOwnerAddresses[1].address => serviceOwnerAddress
        for (let i = 0; i < agentInstances.length - 1; i++) {
            const agentIdx = agentInstances.length - i - 1;
            callData[i] = gnosisSafe.interface.encodeFunctionData("removeOwner", [sentinelOwners, agentInstances[agentIdx], threshold]);
            txs[i] = safeContracts.buildSafeTransaction({to: serviceMultisigAddress, data: callData[i], nonce: 0});
        }
    }

    // Swap the first agent instance address with the service owner address using the sentinel address as the previous one
    callData.push(gnosisSafe.interface.encodeFunctionData("swapOwner", [sentinelOwners, agentInstances[0], serviceOwnerAddress]));
    txs.push(safeContracts.buildSafeTransaction({to: serviceMultisigAddress, data: callData[callData.length - 1], nonce: 0}));

    // Build a multisend transaction to be executed by the multisig
    const safeTx = safeContracts.buildMultiSendSafeTx(multiSend, txs, nonce);
    safeTx.to = multisendAddress;
    const EIP712_SAFE_TX_TYPE = {
        // "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
        SafeTx: [
            { type: "address", name: "to" },
            { type: "uint256", name: "value" },
            { type: "bytes", name: "data" },
            { type: "uint8", name: "operation" },
            { type: "uint256", name: "safeTxGas" },
            { type: "uint256", name: "baseGas" },
            { type: "uint256", name: "gasPrice" },
            { type: "address", name: "gasToken" },
            { type: "address", name: "refundReceiver" },
            { type: "uint256", name: "nonce" },
        ]
    };
    // Hash the Safe transaction
    const hash = ethers.utils._TypedDataEncoder.hash({ verifyingContract: serviceMultisigAddress, chainId }, EIP712_SAFE_TX_TYPE, safeTx);
    console.log("\nFull unsigned safeTx:");
    console.log(safeTx);
    console.log("\nsafeTx hash to be signed by agent instances:");
    console.log(hash);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
