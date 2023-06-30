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
    const configHash = Buffer.from("5".repeat(64), "hex");
    const regBond = new anchor.BN(1000);
    const regDeposit = new anchor.BN(1000);
    const agentIds = [1, 2];
    const slots = [2, 3];
    const bonds = [regBond, regBond];
    const serviceId = 1;
    const maxThreshold = slots[0] + slots[1];

    const serviceOwner = web3.Keypair.fromSecretKey(
        Uint8Array.from([
            136,  71,  29, 144, 109, 194, 157, 172, 101, 185, 252,
            103,  95,   0,  40,  10, 235, 155, 114, 237,   3, 107,
             30,  19,   1, 217, 180,   9, 136, 227,   6,  22, 235,
             64, 174, 106, 123,  15, 232, 250,   0, 236, 132,  73,
            117,  92, 111, 123,  10, 126,  59, 205, 220, 106, 253,
            179, 139, 146, 233,  10,  93,   1,  87, 167
        ]));

    const operator = web3.Keypair.fromSecretKey(
        Uint8Array.from([
            233, 199, 113, 183,  99,  90, 245, 243, 207, 112,  25,
             32, 114,  98, 193, 213,  61,   4, 156,  98, 171, 130,
            164, 141, 189,  63, 156, 106, 227,  91,   2, 249, 254,
            175, 239, 250,  30,  49,  76, 122, 247,  24,  31, 247,
            138, 114, 107, 153, 129,  22,  73, 165,  34,  13, 241,
             89,  54,  38, 196, 150, 102, 160, 134, 139
        ]));

    const pdaEscrow = new web3.PublicKey(parsedData.pda);

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
    return;

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

    // Get agent instances
    const agentInstances = new Array(maxThreshold);
    for (let i = 0; i < maxThreshold; i++) {
        agentInstances[i] = web3.Keypair.generate().publicKey;
    }

    // Register agent instances
    await program.methods.registerAgents(serviceId, agentInstances, [1, 1, 2, 2, 2])
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
    const multisig = web3.Keypair.generate();
    await program.methods.deploy(serviceId, multisig.publicKey)
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

    // Terminate the service
    await program.methods.terminate(serviceId)
        .accounts({ dataAccount: storageKey })
        .remainingAccounts([
            { pubkey: pdaEscrow, isSigner: false, isWritable: true },
            { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
        ])
        .signers([serviceOwner])
        .rpc();

    // Check the service
    service = await program.methods.getService(serviceId)
        .accounts({ dataAccount: storageKey })
        .view();
    expect(service.state).toEqual({"terminatedBonded": {}});

    // Unbond agent instances
    await program.methods.unbond(serviceId)
        .accounts({ dataAccount: storageKey })
        .remainingAccounts([
            { pubkey: pdaEscrow, isSigner: false, isWritable: true },
            { pubkey: operator.publicKey, isSigner: true, isWritable: true }
        ])
        .signers([operator])
        .rpc();

    // Check the service
    service = await program.methods.getService(serviceId)
        .accounts({ dataAccount: storageKey })
        .view();
    expect(service.state).toEqual({"preRegistration": {}});
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
