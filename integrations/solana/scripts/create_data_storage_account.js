/* global process */
const anchor = require("@project-serum/anchor");
const web3 = require("@solana/web3.js");
const fs = require("fs");

function loadKey(filename) {
    const contents = fs.readFileSync(filename).toString();
    const bs = Uint8Array.from(JSON.parse(contents));

    return web3.Keypair.fromSecretKey(bs);
}

async function createAccount(provider, account, programId, space) {
    const lamports = await provider.connection.getMinimumBalanceForRentExemption(space);

    const transaction = new web3.Transaction();

    transaction.add(
        web3.SystemProgram.createAccount({
            fromPubkey: provider.wallet.publicKey,
            newAccountPubkey: account.publicKey,
            lamports,
            space,
            programId,
        }));

    await provider.sendAndConfirm(transaction, [account]);
}

async function main() {
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    // Get the solana endpoint
    const endpoint = parsedData.endpoint;

    // This keypair corresponds to the deployer one
    process.env["ANCHOR_WALLET"] = parsedData.wallet + ".json";

    const provider = anchor.AnchorProvider.local(endpoint);

    // Get the program Id key
    const programKey = loadKey(parsedData.program + ".json");

    // Check if the storage account already exists, and create it if it does not
    let storage;
    if (parsedData.storage === undefined) {
        const space = 500000;
        storage = web3.Keypair.generate();
        // Create a storage account
        await createAccount(provider, storage, programKey.publicKey, space);
    }

    // Write the storage account data
    parsedData.storage = storage.publicKey.toBase58();
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));
    console.log("Storage publicKey:", parsedData.storage);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
