/* global process, Buffer */
const anchor = require("@project-serum/anchor");
const web3 = require("@solana/web3.js");
const fs = require("fs");
const expect = require("expect");

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
    const deployer = loadKey(parsedData.wallet + ".json");

    // Get the solana endpoint
    const endpoint = parsedData.endpoint;

    const idl = JSON.parse(fs.readFileSync("ServiceRegistrySolana.json", "utf8"));

    // This keypair corresponds to the deployer one
    process.env["ANCHOR_WALLET"] = parsedData.wallet + ".json";

    const provider = anchor.AnchorProvider.local(endpoint);

    // Get the program Id key
    const programKey = loadKey(parsedData.program + ".json");

    // Taken from create_data_storage_account.js output
    const storageKey = new web3.PublicKey(parsedData.storage);

    // Get the program instance
    const program = new anchor.Program(idl, programKey.publicKey, provider);

    // Create a service
    const configHash = Buffer.from("e6f8cef4ad8081cb29c449e8a42f094dd15efcc06027e2a13e5b5de770bd0a77", "hex");
    const regBond = new anchor.BN(1);
    const agentIds = [5];
    const numAgentInstances = 4;
    const slots = [numAgentInstances];
    const bonds = [regBond];
    const serviceId = 1;
    const maxThreshold = 3;

    const serviceOwner = deployer;
    const operator = deployer;

    const pdaEscrow = new web3.PublicKey(parsedData.pda);

    // Get agent instances
    const agentInstances = new Array(numAgentInstances);
    agentInstances[0] = new web3.PublicKey("21tJtPPDAQX2N94UmtmGq3n7L1xkqaL1sFdkK1y68VwJ");
    agentInstances[1] = new web3.PublicKey("A22Gr2vbqhJ7v5vhy9qnqsmW2hwFM2ManfwrNma6MRp4");
    agentInstances[2] = new web3.PublicKey("CXGsMvPXYPpjpXtmEE8orTtsphtrpxcYAaAcc7SH7K5h");
    agentInstances[3] = new web3.PublicKey("Df7a7tTH7H4ZrSgwx2sE7cFLU6BGTgixT2qkPx5jtNa8");

    // Get the multisig
    const multisig = new web3.PublicKey("94jZ2qasXkguDKLWtetTQcZg4rGTpRDPrsR7v2iKDRGt");

    // This return is placed here such that no new service is not accidentally created
    return;

    // Create a service
    await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
        .accounts({ dataAccount: storageKey })
        .remainingAccounts([
            { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
        ])
        .signers([serviceOwner])
        .rpc();

    // Check the obtained service
    let service = await program.methods.getService(serviceId)
        .accounts({ dataAccount: storageKey })
        .view();
    expect(service.state).toEqual({"preRegistration": {}});

    // Activate the service registration
    await program.methods.activateRegistration(serviceId)
        .accounts({ dataAccount: storageKey })
        .remainingAccounts([
            { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
            { pubkey: pdaEscrow, isSigner: false, isWritable: true }
        ])
        .signers([serviceOwner])
        .rpc();

    // Check the service
    service = await program.methods.getService(serviceId)
        .accounts({ dataAccount: storageKey })
        .view();
    expect(service.state).toEqual({"activeRegistration": {}});

    // Register agent instances
    await program.methods.registerAgents(serviceId, agentInstances, [5, 5, 5, 5])
        .accounts({ dataAccount: storageKey })
        .remainingAccounts([
            { pubkey: operator.publicKey, isSigner: true, isWritable: true },
            { pubkey: pdaEscrow, isSigner: false, isWritable: true }
        ])
        .signers([operator])
        .rpc();

    // Check the service
    service = await program.methods.getService(serviceId)
        .accounts({ dataAccount: storageKey })
        .view();
    expect(service.state).toEqual({"finishedRegistration": {}});

    // Deploy the service
    await program.methods.deploy(serviceId, multisig)
        .accounts({ dataAccount: storageKey })
        .remainingAccounts([
            { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
        ])
        .signers([serviceOwner])
        .rpc();

    // Check the service
    service = await program.methods.getService(serviceId)
        .accounts({ dataAccount: storageKey })
        .view();
    expect(service.state).toEqual({"deployed": {}});
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
