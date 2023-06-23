/* global describe, beforeEach, it, process, Buffer */
const anchor = require("@project-serum/anchor");
const expect = require("expect");
const web3 = require("@solana/web3.js");
const fs = require("fs");
const spl = require("@solana/spl-token");

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
    const baseURI = "https://gateway.autonolas.tech/ipfs/";
    const space = 5000;
    let provider;
    let program;
    let storage;
    let deployer;
    let pdaEscrow;
    let bumpBytes;

    // Allocate accounts
    deployer = loadKey("deE9943tv6GqmWRmMgf1Nqt384UpzX4FrMvKrt34mmt.json");

    const endpoint = "https://api.devnet.solana.com";
    const connection = new web3.Connection(endpoint, {
        commitment: "confirmed",
        confirmTransactionInitialTimeout: 1e6,
    });

    const idl = JSON.parse(fs.readFileSync("ServiceRegistrySolana.json", "utf8"));

    // payer.key is setup during the setup
    process.env["ANCHOR_WALLET"] = "deE9943tv6GqmWRmMgf1Nqt384UpzX4FrMvKrt34mmt.json";

    provider = anchor.AnchorProvider.local(endpoint);

    const programKey = loadKey("AUTKLetujLAesSKRzPiPzNiCbxfYV423h1sWPfhnFMNj.json");

//    const program_so = fs.readFileSync("ServiceRegistrySolana.so");
//    for (let retries = 5; retries > 0; retries -= 1) {
//        try {
//            await web3.BpfLoader.load(provider.connection, deployer, programKey, program_so, web3.BPF_LOADER_PROGRAM_ID);
//            break;
//        } catch (e) {
//            if (e instanceof web3.TransactionExpiredBlockheightExceededError) {
//                console.log(e);
//                console.log("retrying...");
//                connection = new web3.Connection(endpoint, {
//                    commitment: "confirmed",
//                    confirmTransactionInitialTimeout: 1e6,
//                });
//            } else {
//                throw e;
//            }
//        }
//    }
//
//    storage = web3.Keypair.generate();
//    await createAccount(provider, storage, programKey.publicKey, space);

    const storageKey = new web3.PublicKey("4gSgiAZSAWXjhg2oUXM8MYByayTJkKo9FujYPbLwhKNH");
    //console.log("storage", storage.publicKey);
    const storageInfo = await connection.getAccountInfo(storageKey);
    console.log("storageInfo", storageInfo);

    program = new anchor.Program(idl, programKey.publicKey, provider);

    // Find a PDA account
    const [pda, bump] = await web3.PublicKey.findProgramAddress([Buffer.from("pdaEscrow", "utf-8")], program.programId);
    pdaEscrow = pda;
    bumpBytes = Buffer.from(new Uint8Array([bump]));

    console.log("pda", pda);
    console.log("bumpBytes", bumpBytes);

    const txHash = await program.methods.new(deployer.publicKey, storageKey, pdaEscrow, bumpBytes, baseURI)
        .accounts({ dataAccount: storageKey })
        .rpc();

    //let tx = await provider.connection.requestAirdrop(pdaEscrow, 100 * web3.LAMPORTS_PER_SOL);
    //await provider.connection.confirmTransaction(tx, "confirmed");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
