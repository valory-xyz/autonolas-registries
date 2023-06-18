const anchor = require("@project-serum/anchor");
const assert = require("assert");
const expect = require("expect");
const web3 = require("@solana/web3.js");
const fs = require("fs");

describe("ServiceRegistrySolana", function () {
    const baseURI = "https://localhost/service/";
    const configHash = Buffer.from("5".repeat(64), "hex");
    const regBond = new anchor.BN(1000);
    const regDeposit = new anchor.BN(1000);
    const agentIds = [1, 2];
    const slots = [3, 4];
    const bonds = [regBond, regBond];
    const serviceId = 1;
    const agentId = 1;
    const maxThreshold = slots[0] + slots[1];
    let provider;
    let program;
    let storage;
    let deployer;
    let escrow;
    let operator;
    let serviceOwner;
    const emptyPayload = Buffer.from("", "hex");
    const encoder = new TextEncoder();

    this.timeout(500000);

    function loadKey(filename) {
        const contents = fs.readFileSync(filename).toString();
        const bs = Uint8Array.from(JSON.parse(contents));

        return web3.Keypair.fromSecretKey(bs);
    }

    async function create_account(provider, account, programId, space) {
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

        const payer = loadKey("payer.key");

        process.env["ANCHOR_WALLET"] = "payer.key";

        provider = anchor.AnchorProvider.local(endpoint);

        storage = web3.Keypair.generate();

        program_key = loadKey("ServiceRegistrySolana.key");

        const space = 20000;
        await create_account(provider, storage, program_key.publicKey, space);

        program = new anchor.Program(idl, program_key.publicKey, provider);

        await program.methods.new(deployer.publicKey, baseURI)
            .accounts({ dataAccount: storage.publicKey })
            .rpc();


        // Deploy ServiceRegistrySolana
//        const deployment = await loadContract("ServiceRegistrySolana", [deployer.publicKey, baseURI]);
//        provider = deployment.provider;
//        program = deployment.program;
//        storage = deployment.storage;

        let tx = await provider.connection.requestAirdrop(deployer.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
        tx = await provider.connection.requestAirdrop(serviceOwner.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
        tx = await provider.connection.requestAirdrop(operator.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");

        // Init program storage
        await program.methods.initProgramStorage(storage.publicKey)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: deployer.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([deployer])
            .rpc();
    });

    it("Creating a service", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

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
    });
});