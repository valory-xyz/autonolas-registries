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
    const endpoint = "https://api.devnet.solana.com";

    // This keypair corresponds to the deployer one
    process.env["ANCHOR_WALLET"] = "deE9943tv6GqmWRmMgf1Nqt384UpzX4FrMvKrt34mmt.json";

    const provider = anchor.AnchorProvider.local(endpoint);

    const programKey = loadKey("AUqjSeMFhp15BvKUHsg8SRrpNZ3goKc6Zoo1mbzkjt1g.json");

    const space = 500000;
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
