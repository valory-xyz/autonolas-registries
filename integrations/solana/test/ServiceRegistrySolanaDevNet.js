/* global describe, beforeEach, it, process, Buffer */

const anchor = require("@project-serum/anchor");
const expect = require("expect");
const web3 = require("@solana/web3.js");
const fs = require("fs");
const spl = require("@solana/spl-token");

describe("ServiceRegistrySolanaDevNet", function () {
    const baseURI = "https://localhost/service/";
    const configHash = Buffer.from("5".repeat(64), "hex");
    const regBond = new anchor.BN(1000);
    const regDeposit = new anchor.BN(1000);
    const regFine = new anchor.BN(500);
    const agentIds = [1, 2];
    const slots = [2, 3];
    const bonds = [regBond, regBond];
    const serviceId = 1;
    const maxThreshold = slots[0] + slots[1];
    let provider;
    let program;
    let storageKey;
    let deployer;
    let pdaEscrow;
    let bumpBytes;
    let operator;
    let serviceOwner;

    this.timeout(500000);

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

    beforeEach(async function () {
        // Allocate accounts
        deployer = web3.Keypair.generate();
        operator = web3.Keypair.generate();
        serviceOwner = web3.Keypair.fromSecretKey(
            Uint8Array.from([
                136,  71,  29, 144, 109, 194, 157, 172, 101, 185, 252,
                103,  95,   0,  40,  10, 235, 155, 114, 237,   3, 107,
                 30,  19,   1, 217, 180,   9, 136, 227,   6,  22, 235,
                 64, 174, 106, 123,  15, 232, 250,   0, 236, 132,  73,
                117,  92, 111, 123,  10, 126,  59, 205, 220, 106, 253,
                179, 139, 146, 233,  10,  93,   1,  87, 167
            ]));
        operator = web3.Keypair.fromSecretKey(
            Uint8Array.from([
                233, 199, 113, 183,  99,  90, 245, 243, 207, 112,  25,
                 32, 114,  98, 193, 213,  61,   4, 156,  98, 171, 130,
                164, 141, 189,  63, 156, 106, 227,  91,   2, 249, 254,
                175, 239, 250,  30,  49,  76, 122, 247,  24,  31, 247,
                138, 114, 107, 153, 129,  22,  73, 165,  34,  13, 241,
                 89,  54,  38, 196, 150, 102, 160, 134, 139
            ]));

        const endpoint = process.env.RPC_URL || "https://api.devnet.solana.com";
        const idl = JSON.parse(fs.readFileSync("ServiceRegistrySolana.json", "utf8"));

        // payer.key is setup during the setup
        process.env["ANCHOR_WALLET"] = "deE9943tv6GqmWRmMgf1Nqt384UpzX4FrMvKrt34mmt.json";

        provider = anchor.AnchorProvider.local(endpoint);

        storageKey = new web3.PublicKey("7uiPSypNbSLeMopSU7VSEgoKUHr7yBAWU6nPsBUEpVD");

        //const programKey = loadKey("ServiceRegistrySolana.key");
        // defined publicKey (program id)
        programKey = loadKey("AUtGCjdye7nFRe7Zn3i2tU86WCpw2pxSS5gty566HWT6.json");
        
        //const space = 5000;
        //await createAccount(provider, storage, programKey.publicKey, space);

        //program = new anchor.Program(idl, programKey.publicKey, provider);
        program = new anchor.Program(idl, programKey.publicKey, provider);

        // Find a PDA account
        const [pda, bump] = await web3.PublicKey.findProgramAddress([Buffer.from("pdaEscrow", "utf-8")], program.programId);
        pdaEscrow = pda;
        bumpBytes = Buffer.from(new Uint8Array([bump]));

        console.log("pda findProgramAddress()",pdaEscrow);
        console.log("pda init script: 97f9214h4vLdH9P7tmHBAcxMc8auofGqxS5cAFiMkZT3");
        // AUbXARyxJiDhGKgNvii6YkXT92AQZxFrZvFuGTkRtisa
        console.log("program.programId",program.programId);
        // GqL1nG7Aj6FdiUWnkdCsK7pEeyE5nm3T2aaMkGTNvMWn
        console.log("serviceOwner pubKey",serviceOwner.publicKey);
        // J9C9zzJvxBWBKH2Tc8QR4ed2iTH1V7UTTzJZdcZcpkKc
        console.log("operator pubKey",operator.publicKey);

        const infoStorageKey = await provider.connection.getAccountInfo(storageKey);
        console.log("storageKey info",infoStorageKey);

        //await program.methods.new(deployer.publicKey, storage.publicKey, pdaEscrow, bumpBytes, baseURI)
        //    .accounts({ dataAccount: storage.publicKey })
        //    .rpc();

        //let tx = await provider.connection.requestAirdrop(pdaEscrow, 100 * web3.LAMPORTS_PER_SOL);
        //await provider.connection.confirmTransaction(tx, "confirmed");
        //tx = await provider.connection.requestAirdrop(deployer.publicKey, 1 * web3.LAMPORTS_PER_SOL);
        //await provider.connection.confirmTransaction(tx, "confirmed");
        // try airdrop
        try {
            // tx = await provider.connection.requestAirdrop(serviceOwner.publicKey, 1 * web3.LAMPORTS_PER_SOL);
            // await provider.connection.confirmTransaction(tx, "confirmed");
            // tx = await provider.connection.requestAirdrop(operator.publicKey, 1 * web3.LAMPORTS_PER_SOL);
            // await provider.connection.confirmTransaction(tx, "confirmed");
        } catch (error) {
            // console.error("Transaction Error:", error);
        }

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
        // manual
        //solana transfer --from /home/andrey/.config/solana/id.json GqL1nG7Aj6FdiUWnkdCsK7pEeyE5nm3T2aaMkGTNvMWn 1.0 --allow-unfunded-recipient
        //solana transfer --from /home/andrey/.config/solana/id.json J9C9zzJvxBWBKH2Tc8QR4ed2iTH1V7UTTzJZdcZcpkKc 1.0 --allow-unfunded-recipien
    });


    it("Creating a service", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Check the obtained service
        const service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();

        console.log(service);
        
        expect(service.serviceOwner).toEqual(serviceOwner.publicKey);
        //expect(service.configHash).toEqual(configHash);
        expect(service.threshold).toEqual(maxThreshold);
        expect(service.agentIds).toEqual(agentIds);
        expect(service.slots).toEqual(slots);
        const compareBonds = service.bonds.every((value, index) => value.eq(bonds[index]));
        expect(compareBonds).toEqual(true);
    });
});