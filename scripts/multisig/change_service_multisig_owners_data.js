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
    // Resulting threshold
    const threshold = parsedFile["threshold"];
    // Current service multisig nonce
    const nonce = parsedFile["nonce"];
    // Chain Id
    const chainId = parsedFile["chainId"];
    // If true, the safeTx hash is already approved in the service multisig
    // If false, the safeTx hash needs to be signed by the service multisig owner
    const approvedHash = parsedFile["approvedHash"];
    const sentinelOwners = "0x" + "0".repeat(39) + "1";

    // Sanity check
    if (!agentInstances || agentInstances.length == 0 || !serviceMultisigAddress || !serviceOwnerAddress ||
        !multisendAddress || !threshold || !nonce || !chainId) {
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
        // Add the addresses skipping the first one, but keep the threshold the same
        for (let i = 0; i < agentInstances.length - 1; i++) {
            callData[i] = gnosisSafe.interface.encodeFunctionData("addOwnerWithThreshold", [agentInstances[i+1], 1]);
            txs[i] = safeContracts.buildSafeTransaction({to: serviceMultisigAddress, data: callData[i], nonce: 0});
        }
        // Swap the original multisig owner with the first provided agent instance, and change the threshold separately
        // Note that the prevOwner is the very first added address as it corresponds to the reverse order of added addresses
        // The order in the gnosis safe multisig is as follows: sentinelOwners => agentInstances[last].address => ... =>
        // => newOwnerAddresses[1].address => serviceOwnerAddress
        callData.push(gnosisSafe.interface.encodeFunctionData("swapOwner", [agentInstances[1], serviceOwnerAddress, agentInstances[0]]));
        txs.push(safeContracts.buildSafeTransaction({to: serviceMultisigAddress, data: callData[callData.length - 1], nonce: 0}));
    } else {
        // Special case for swapping one multisig address owner to another
        // Just swap using the sentinel address as the previous one
        callData.push(gnosisSafe.interface.encodeFunctionData("swapOwner", [sentinelOwners, serviceOwnerAddress, agentInstances[0]]));
        txs.push(safeContracts.buildSafeTransaction({to: serviceMultisigAddress, data: callData[callData.length - 1], nonce: 0}));
    }
    // Change threshold
    callData.push(gnosisSafe.interface.encodeFunctionData("changeThreshold", [threshold]));
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
    console.log("\nsafeTx hash to sign by the service owner:");
    console.log(hash);

    // Get the signature string mock
    let signatureBytes = "0x" + "bb".repeat(65);
    // Check if the hash is already approved in the multisig, then get the signature for the approvedHash case
    if (approvedHash == true) {
        // Since the hash is approved, it's enough to base one on the service owner address
        signatureBytes = "0x000000000000000000000000" + serviceOwnerAddress.slice(2) +
            "0000000000000000000000000000000000000000000000000000000000000000" + "01";
        console.log("\nApproved hash signatureBytes value (without initial \"0x\")");
    } else {
        console.log("\nsafeTx hash needs to be signed, and the resulting signature has to be assigned to the signatureBytes variable.");
        console.log("The mock signatureBytes is set to 65 bytes of repeating \"bb\". Substitute it with the real signature string in the final safeTx bytecode.");
    }
    console.log(signatureBytes.slice(2));

    // Forming Gnosis Safe transaction bytes data: the multisig address itself plus the execTransaction() data
    // that forms the multisend data with the signature bytes to be executed by the multisig proxy
    const safeExecData = gnosisSafe.interface.encodeFunctionData("execTransaction", [safeTx.to, safeTx.value,
        safeTx.data, safeTx.operation, safeTx.safeTxGas, safeTx.baseGas, safeTx.gasPrice, safeTx.gasToken,
        safeTx.refundReceiver, signatureBytes]);
    console.log("\nFinal safeTx bytecode (please verify the signatureBytes)");
    console.log(safeExecData);

    // Add the multisig address on top of the multisig exec transaction data
    const packedData = ethers.utils.solidityPack(["address", "bytes"], [serviceMultisigAddress, safeExecData]);
    console.log("\nServiceRegistry deploy() function bytes data (payload)");
    console.log(packedData);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
