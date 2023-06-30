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
    const globalsFile = "globals.json";
    const dataFromJSON = fs.readFileSync(globalsFile, "utf8");
    const parsedData = JSON.parse(dataFromJSON);

    // Get the base URI
    const baseURI = parsedData.baseURI;

    // Get the deployer wallet
    deployer = loadKey(parsedData.wallet + ".json");

    // This keypair corresponds to the deployer one
    process.env["ANCHOR_WALLET"] = parsedData.wallet + ".json";

    // Get the solana endpoint
    const endpoint = parsedData.endpoint;

    const idl = JSON.parse(fs.readFileSync("ServiceRegistrySolana.json", "utf8"));

    const provider = anchor.AnchorProvider.local(endpoint);

    // Get the program Id key
    const programKey = new web3.PublicKey(parsedData.program);

    // Taken from create_data_storage_account.js output
    const storageKey = new web3.PublicKey(parsedData.storage);

    // Get the program instance
    const program = new anchor.Program(idl, programKey, provider);

    // Find a PDA account
    const [pda, bump] = await web3.PublicKey.findProgramAddress([Buffer.from("pdaEscrow", "utf-8")], program.programId);
    const pdaEscrow = pda;
    const bumpBytes = Buffer.from(new Uint8Array([bump]));

    // Initialize the program if it was not yet initialized (no record in the globals file)
    if (parsedData.pda === undefined) {
        await program.methods.new(deployer.publicKey, storageKey, pdaEscrow, bumpBytes, baseURI)
            .accounts({ dataAccount: storageKey })
            .rpc();
    }

    // Write the pda account data
    parsedData.pda = pda.toBase58();
    fs.writeFileSync(globalsFile, JSON.stringify(parsedData));

    // Check the resulting data
    const ownerOut = await program.methods.owner()
        .accounts({ dataAccount: storageKey })
        .view();
    console.log("deployer:", ownerOut.toBase58());

    const storageOut = await program.methods.programStorage()
        .accounts({ dataAccount: storageKey })
        .view();
    console.log("storage:", storageOut.toBase58());

    const pdaOut = await program.methods.pdaEscrow()
        .accounts({ dataAccount: storageKey })
        .view();
    console.log("pdaEscrow:", pdaOut.toBase58());

    const baseURIOut = await program.methods.baseUri()
        .accounts({ dataAccount: storageKey })
        .view();
    console.log("baseURI:", baseURIOut);

    // Transfer 0.1 SOL to the pda account to activate it and supply its 2 year rent
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
