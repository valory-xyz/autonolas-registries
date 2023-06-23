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
    // Allocate accounts
    const deployer = loadKey("deE9943tv6GqmWRmMgf1Nqt384UpzX4FrMvKrt34mmt.json");

    const endpoint = "https://api.devnet.solana.com";

    // payer.key is setup during the setup
    process.env["ANCHOR_WALLET"] = "deE9943tv6GqmWRmMgf1Nqt384UpzX4FrMvKrt34mmt.json";

    const provider = anchor.AnchorProvider.local(endpoint);

    const programKey = loadKey("AUX6DBER9z1HyeW7g4cu6ArHRDJdSQFAvSEL7PzWBSpw.json");

    const space = 5000;
    const storage = web3.Keypair.generate();
    await createAccount(provider, storage, programKey.publicKey, space);

    console.log("Storage publicKey", storage.publicKey);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
