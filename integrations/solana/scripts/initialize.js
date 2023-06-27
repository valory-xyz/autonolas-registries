/* global process, Buffer */
const anchor = require("@project-serum/anchor");
const web3 = require("@solana/web3.js");
const fs = require("fs");

function loadKey(filename) {
    const contents = fs.readFileSync(filename).toString();
    const bs = Uint8Array.from(JSON.parse(contents));

    return web3.Keypair.fromSecretKey(bs);
}

async function main() {
    const baseURI = "https://gateway.autonolas.tech/ipfs/";

    // Allocate accounts
    const deployer = loadKey("deE9943tv6GqmWRmMgf1Nqt384UpzX4FrMvKrt34mmt.json");

    const endpoint = "https://api.devnet.solana.com";

    const idl = JSON.parse(fs.readFileSync("ServiceRegistrySolana.json", "utf8"));

    // payer.key is setup during the setup
    process.env["ANCHOR_WALLET"] = "deE9943tv6GqmWRmMgf1Nqt384UpzX4FrMvKrt34mmt.json";

    const provider = anchor.AnchorProvider.local(endpoint);

    const programKey = loadKey("AUtGCjdye7nFRe7Zn3i2tU86WCpw2pxSS5gty566HWT6.json");

    // Taken from create_data_storage_account.js output
    const storageKey = new web3.PublicKey("7uiPSypNbSLeMopSU7VSEgoKUHr7yBAWU6nPsBUEpVD");

    const program = new anchor.Program(idl, programKey.publicKey, provider);

    // Find a PDA account
    const [pda, bump] = await web3.PublicKey.findProgramAddress([Buffer.from("pdaEscrow", "utf-8")], program.programId);
    const pdaEscrow = pda;
    const bumpBytes = Buffer.from(new Uint8Array([bump]));

    console.log("pda", pda);
    // PDA 97f9214h4vLdH9P7tmHBAcxMc8auofGqxS5cAFiMkZT3

    // Initialize the program
    await program.methods.new(deployer.publicKey, storageKey, pdaEscrow, bumpBytes, baseURI)
        .accounts({ dataAccount: storageKey })
        .rpc();

    // Check the resulting data
    const ownerOut = await program.methods.owner()
        .accounts({ dataAccount: storageKey })
        .view();
    console.log("deployer", ownerOut);

    const storageOut = await program.methods.programStorage()
        .accounts({ dataAccount: storageKey })
        .view();
    console.log("storage", storageOut);

    const pdaOut = await program.methods.pdaEscrow()
        .accounts({ dataAccount: storageKey })
        .view();
    console.log("pdaEscrow", pdaOut);

    const baseURIOut = await program.methods.baseUri()
        .accounts({ dataAccount: storageKey })
        .view();
    console.log("baseURI", baseURIOut);

    //let tx = await provider.connection.requestAirdrop(pdaEscrow, 100 * web3.LAMPORTS_PER_SOL);
    //await provider.connection.confirmTransaction(tx, "confirmed");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
