/* global describe, beforeEach, it, process, Buffer */

const anchor = require("@project-serum/anchor");
const expect = require("expect");
const web3 = require("@solana/web3.js");
const fs = require("fs");
const spl = require("@solana/spl-token");

describe("ServiceRegistrySolanaFull", function () {
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
    let storage;
    let deployer;
    let pdaEscrow;
    let bumpBytes;
    let operator;
    let serviceOwner;
    let space;

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
        serviceOwner = web3.Keypair.generate();
        operator = web3.Keypair.generate();

        const endpoint = process.env.RPC_URL || "http://127.0.0.1:8899";
        const idl = JSON.parse(fs.readFileSync("ServiceRegistrySolana.json", "utf8"));

        // payer.key is setup during the setup
        process.env["ANCHOR_WALLET"] = "payer.key";

        provider = anchor.AnchorProvider.local(endpoint);

        storage = web3.Keypair.generate();

        const programKey = loadKey("ServiceRegistrySolana.key");

        //space = 50000; // step 153
        //space = 100000; // step 318
        space = 1000000; // step
        await createAccount(provider, storage, programKey.publicKey, space);

        program = new anchor.Program(idl, programKey.publicKey, provider);

        // Find a PDA account
        const [pda, bump] = await web3.PublicKey.findProgramAddress([Buffer.from("pdaEscrow", "utf-8")], program.programId);
        pdaEscrow = pda;
        bumpBytes = Buffer.from(new Uint8Array([bump]));

        await program.methods.new(deployer.publicKey, storage.publicKey, pdaEscrow, bumpBytes, baseURI)
            .accounts({ dataAccount: storage.publicKey })
            .rpc();

        let tx = await provider.connection.requestAirdrop(pdaEscrow, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
        tx = await provider.connection.requestAirdrop(deployer.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
        tx = await provider.connection.requestAirdrop(serviceOwner.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
        tx = await provider.connection.requestAirdrop(operator.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
    });

    it("Creating a 3200 services. Storage space", async function () {
        // Create a service
        console.log("space:",space);
        let passed = true;
        let step = 0;
        const maxSteps = 3200;
        for (let i = 0; i < maxSteps; i++) {
            try {
                await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
                    .accounts({ dataAccount: storage.publicKey })
                    .remainingAccounts([
                        { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
                    ])
                    .signers([serviceOwner])
                    .rpc();
            } catch (error) {
                console.log("out of memory",error);
                step = i;
                console.log("step",step);
                passed = false;
                break;
            }
        }
        // passed
        if (step == 0) {
            step = maxSteps;
        }    
        // Check the obtained service
        const service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(service.serviceOwner).toEqual(serviceOwner.publicKey);
        //expect(service.configHash).toEqual(configHash);
        expect(service.threshold).toEqual(maxThreshold);
        expect(service.agentIds).toEqual(agentIds);
        expect(service.slots).toEqual(slots);
        const compareBonds = service.bonds.every((value, index) => value.eq(bonds[index]));
        expect(compareBonds).toEqual(true);

        const infoStorageKey = await provider.connection.getAccountInfo(storage.publicKey);
        const buff = infoStorageKey.data;
        console.log("passed:",passed);
        console.log("step:",step);
        // console.log("buff:",buff.toString('hex')); 
        console.log("storageKey info:",infoStorageKey);
    });
});