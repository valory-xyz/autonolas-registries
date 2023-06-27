/* global describe, beforeEach, it, process, Buffer */

const anchor = require("@project-serum/anchor");
const expect = require("expect");
const web3 = require("@solana/web3.js");
const fs = require("fs");
const spl = require("@solana/spl-token");

describe("ServiceRegistrySolana", function () {
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

        expect(service.serviceOwner).toEqual(serviceOwner.publicKey);
        //expect(service.configHash).toEqual(configHash);
        expect(service.threshold).toEqual(maxThreshold);
        expect(service.agentIds).toEqual(agentIds);
        expect(service.slots).toEqual(slots);
        const compareBonds = service.bonds.every((value, index) => value.eq(bonds[index]));
        expect(compareBonds).toEqual(true);
    });
    
    it("Should fail when incorrectly updating a service", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Update the service
        const newAgentIds = [1, 0, 4];
        const newSlots = [2, 1, 5];
        const newBonds = [regBond, regBond, regBond];
        const newMaxThreshold = newSlots[0] + newSlots[1] + newSlots[2];
        try {
            await program.methods.update(configHash, newAgentIds, newSlots, newBonds, newMaxThreshold, serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                //console.error("Program Error:", error);
                //console.error("Error Message:", error.message);
            } else {
                //console.error("Transaction Error:", error);
            }
        }
    });

    it.only("Updating a service", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Update the service
        const newAgentIds = [1, 2, 4];
        const newSlots = [2, 1, 5];
        const newBonds = [regBond, regBond, regBond];
        const newMaxThreshold = newSlots[0] + newSlots[1] + newSlots[2];
        await program.methods.update(configHash, newAgentIds, newSlots, newBonds, newMaxThreshold, serviceId)
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

        expect(service.serviceOwner).toEqual(serviceOwner.publicKey);
        //expect(service.configHash).toEqual(configHash);
        expect(service.threshold).toEqual(newMaxThreshold);
        expect(service.agentIds).toEqual(newAgentIds);
        expect(service.slots).toEqual(newSlots);
        const compareBonds = service.bonds.every((value, index) => value.eq(newBonds[index]));
        expect(compareBonds).toEqual(true);
    });

    it("Creating a service and activating it", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);
        //console.log("escrowBalanceBefore", escrowBalanceBefore);

        // Activate the service registration
        await program.methods.activateRegistration(serviceId)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: pdaEscrow, isSigner: false, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        let escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        //console.log("escrowBalanceAfter", escrowBalanceAfter);

        // Check the obtained service
        const service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();

        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        expect(service.state).toEqual({"activeRegistration": {}});
    });

    //1) ServiceRegistrySolana
    //   Creating a service, activating it and registering agent instances:
    // Error: failed to send transaction: Transaction simulation failed: Error processing Instruction 0: account data too small for instruction
 
    it("Creating a service, activating it and registering agent instances", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Get the service owner escrow balance before activation
        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Activate the service
        await program.methods.activateRegistration(serviceId)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: pdaEscrow, isSigner: false, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Check the escrow balance after the activation
        let escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get the operator escrow balance before activation
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);
        return;

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: pdaEscrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(regBond));

        // Check the obtained service
        service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();

        // Get the operator bond balance
        const operatorBalance = await program.methods.getOperatorBalance(operator.publicKey, serviceId)
            .accounts({ dataAccount: storageKey })
            .view();

        // Check the operator balance
        expect(Number(operatorBalance)).toEqual(Number(regBond));

        expect(service.state).toEqual({"finishedRegistration": {}});
    });

    it("Creating a service, activating it, registering agent instances and terminating", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Activate the service registration
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        try {
            await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                ])
                .signers([operator])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get the service owner balance before the termination
        const serviceOwnerBalanceBefore = await provider.connection.getBalance(serviceOwner.publicKey);

        // Terminate the service
        try {
            await program.methods.terminate(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get the service owner balance before the termination
        const serviceOwnerBalanceAfter = await provider.connection.getBalance(serviceOwner.publicKey);
        expect(serviceOwnerBalanceAfter - serviceOwnerBalanceBefore).toEqual(Number(regDeposit));

        // Check the obtained service
        const service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();

        expect(service.state).toEqual({"terminatedBonded": {}});
    });

    it("Creating a service, activating it, registering agent instances, terminating and unbonding", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storageKeyy })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Get the service owner escrow balance before activation
        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Check the escrow balance after the activation
        let escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get the operator escrow balance before registering agents
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: pdaEscrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(regBond));

        // Get the service owner balance before the termination
        const serviceOwnerBalanceBefore = await provider.connection.getBalance(serviceOwner.publicKey);

        // Terminate the service
        try {
            await program.methods.terminate(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get the service owner balance after the termination
        const serviceOwnerBalanceAfter = await provider.connection.getBalance(serviceOwner.publicKey);
        expect(serviceOwnerBalanceAfter - serviceOwnerBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get the operator balance before unbond
        const operatorBalanceBefore = await provider.connection.getBalance(operator.publicKey);

        // Unbond agent instances
        try {
            await program.methods.unbond(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                ])
                .signers([operator])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get the operator balance after unbond
        const operatorBalanceAfter = await provider.connection.getBalance(operator.publicKey);
        expect(operatorBalanceAfter - operatorBalanceBefore).toEqual(Number(regBond));

        // Check the obtained service
        service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();

        expect(service.state).toEqual({"preRegistration": {}});
    });

    it("Creating a service, activating it, registering agent instances and deploying", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Get the service owner escrow balance before activation
        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Check the escrow balance after the activation
        let escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get the operator escrow balance before activation
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: pdaEscrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(regBond));

        // Deploy the service
        const multisig = web3.Keypair.generate();
        await program.methods.deploy(serviceId, multisig.publicKey)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Check the obtained service
        service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();

        expect(service.state).toEqual({"deployed": {}});
    });

    it("Creating a service, activating it, registering agent instances, deploying and terminating", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Get the service owner escrow balance before activation
        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Check the escrow balance after the activation
        let escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get the operator escrow balance before activation
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: pdaEscrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(regBond));

        // Deploy the service
        const multisig = web3.Keypair.generate();
        await program.methods.deploy(serviceId, multisig.publicKey)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Terminate the service
        try {
            await program.methods.terminate(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Check the obtained service
        service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();

        expect(service.state).toEqual({"terminatedBonded": {}});
    });

    it("Creating a service, activating it, registering agent instances, deploying, terminating and unbonding", async function () {
        // Create a service
        const transactionHash = await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        /****************************************************************************************************/
        // Get the transaction details and fees
        const commitment = "confirmed";
        await provider.connection.confirmTransaction(transactionHash, commitment);

        //const transaction = await provider.connection.getParsedConfirmedTransaction(transactionHash, commitment);
        //console.log("Transaction:", transaction);

        //const transactionInstance: TransactionInstruction | undefined = transaction.transaction?.message.instructions[0];
        //console.log("Transaction Instance:", transactionInstance);

        //const transactionMetadata = await provider.connection.getTransaction(transactionHash, commitment);
        //console.log("Transaction Metadata:", transactionMetadata);

        //const blockHash = transactionMetadata.transaction.message.recentBlockhash;
        //const feeCalculator = await provider.connection.getFeeCalculatorForBlockhash(blockHash);
        //console.log("feeCalculator", feeCalculator);
        /****************************************************************************************************/

        // Get the service owner escrow balance before activation
        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Check the escrow balance after the activation
        let escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get the operator escrow balance before activation
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: pdaEscrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(regBond));

        // Deploy the service
        const multisig = web3.Keypair.generate();
        await program.methods.deploy(serviceId, multisig.publicKey)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Terminate the service
        try {
            await program.methods.terminate(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get the operator balance before unbond
        const operatorBalanceBefore = await provider.connection.getBalance(operator.publicKey);

        // Unbond agent instances
        try {
            await program.methods.unbond(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                    { pubkey: operator.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([operator])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get the operator balance after unbond
        const operatorBalanceAfter = await provider.connection.getBalance(operator.publicKey);
        expect(operatorBalanceAfter - operatorBalanceBefore).toEqual(Number(regBond));

        // Check the obtained service
        service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();

        expect(service.state).toEqual({"preRegistration": {}});
    });

    it("Creating a service, activating it, registering agent instances, deploying, terminating and unbonding with two operators", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Get the service owner escrow balance before activation
        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Check the escrow balance after the activation
        let escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get agent instances addresses
        const agentInstances = new Array(maxThreshold);
        for (let i = 0; i < maxThreshold; i++) {
            agentInstances[i] = web3.Keypair.generate().publicKey;
        }

        // Register agent instances by the first operator
        try {
            await program.methods.registerAgents(serviceId, [agentInstances[0], agentInstances[1]], [1, 2])
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true }
                ])
                .signers([operator])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get one more operator and operator bonding
        const operator2 = web3.Keypair.generate();
        let tx = await provider.connection.requestAirdrop(operator2.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");

        // Register agent instances by the second operator
        try {
            await program.methods.registerAgents(serviceId, [agentInstances[2], agentInstances[3], agentInstances[4]], [1, 2, 2])
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: operator2.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true }
                ])
                .signers([operator2])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Check the obtained service
        service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();
        expect(service.agentInstances.length).toEqual(agentInstances.length);
        for (let i = 0; i < agentInstances.length; i++) {
            expect(service.agentInstances[i]).toEqual(agentInstances[i]);
        }

        // Deploy the service
        const multisig = web3.Keypair.generate();
        await program.methods.deploy(serviceId, multisig.publicKey)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Terminate the service
        try {
            await program.methods.terminate(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get the operator balance before unbond
        const operatorBalanceBefore = await provider.connection.getBalance(operator.publicKey);

        // Unbond agent instances by the operator
        try {
            await program.methods.unbond(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                    { pubkey: operator.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([operator])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get the operator balance after unbond
        const operatorBalanceAfter = await provider.connection.getBalance(operator.publicKey);
        expect(operatorBalanceAfter - operatorBalanceBefore).toEqual(2 * Number(regBond));

        // Check the obtained service
        service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();
        expect(service.agentInstances.length).toEqual(agentInstances.length);
        expect(service.agentIdForAgentInstances[0]).toEqual(0);
        expect(service.agentIdForAgentInstances[1]).toEqual(0);

        // Get the operator2 balance before unbond
        const operator2BalanceBefore = await provider.connection.getBalance(operator2.publicKey);

        // Unbond agent instances by operator2
        try {
            await program.methods.unbond(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                    { pubkey: operator2.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([operator2])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get the operator balance after unbond
        const operator2BalanceAfter = await provider.connection.getBalance(operator2.publicKey);
        expect(operator2BalanceAfter - operator2BalanceBefore).toEqual(3 * Number(regBond));

        // Check the obtained service
        service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();

        expect(service.operators.length).toEqual(0);
        expect(service.agentInstances.length).toEqual(0);
        expect(service.agentIdForAgentInstances.length).toEqual(0);

        expect(service.state).toEqual({"preRegistration": {}});
    });

    it("Creating a service, activating it, registering agent instances, slashing", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [4], [regBond], 4)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Get the service owner escrow balance before activation
        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Check the escrow balance after the activation
        let escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get agent instances addresses
        const agentInstances = new Array(4);
        for (let i = 0; i < 4; i++) {
            agentInstances[i] = web3.Keypair.generate().publicKey;
        }

        // Register agent instances by the first operator
        try {
            await program.methods.registerAgents(serviceId, agentInstances, [1, 1, 1, 1])
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true }
                ])
                .signers([operator])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Create the multisig based on agent instances
        const multisig = web3.Keypair.generate();
        let tx = await provider.connection.requestAirdrop(multisig.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");

        // Deploy the service
        await program.methods.deploy(serviceId, multisig.publicKey)
            .accounts({ dataAccount: storageKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Slash the operator
        try {
            await program.methods.slash([agentInstances[0]], [regFine], serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: multisig.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([multisig])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Terminate the service
        try {
            await program.methods.terminate(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get the operator balance before unbond
        const operatorBalanceBefore = await provider.connection.getBalance(operator.publicKey);
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Unbond agent instances
        try {
            await program.methods.unbond(serviceId)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                    { pubkey: operator.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([operator])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get the operator balance after unbond
        const operatorBalanceAfter = await provider.connection.getBalance(operator.publicKey);
        expect(operatorBalanceAfter - operatorBalanceBefore).toEqual(4 * Number(regBond) - Number(regFine));
        // Get the pda escrow balance after unbond
        escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        expect(escrowBalanceBefore - escrowBalanceAfter).toEqual(4 * Number(regBond) - Number(regFine));

        // Check the obtained service
        service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storageKey })
            .view();

        expect(service.state).toEqual({"preRegistration": {}});

        // Get the escrow balance before drain
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Drain slashed funds
        try {
            await program.methods.drain(deployer.publicKey)
                .accounts({ dataAccount: storageKey })
                .remainingAccounts([
                    { pubkey: deployer.publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                ])
                .signers([deployer])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Get the pda escrow balance after drain
        escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        expect(escrowBalanceBefore - escrowBalanceAfter).toEqual(Number(regFine));
    });
});