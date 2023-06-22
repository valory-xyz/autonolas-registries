const anchor = require("@project-serum/anchor");
const assert = require("assert");
const expect = require("expect");
const web3 = require("@solana/web3.js");
const fs = require("fs");
const spl = require("@solana/spl-token");

describe("ServiceRegistrySolana", function () {
    const baseURI = "https://localhost/service/";
    const configHash = Buffer.from("5".repeat(64), "hex");
    const regBond = new anchor.BN(1000);
    const regDeposit = new anchor.BN(1000);
    const agentIds = [1, 2];
    const slots = [2, 3];
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
    let drainerEscrow;
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

        let tx = await provider.connection.requestAirdrop(deployer.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
        tx = await provider.connection.requestAirdrop(serviceOwner.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
        tx = await provider.connection.requestAirdrop(operator.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");

        // Set the drainer escrow by the program owner
        drainerEscrow = await web3.PublicKey.createWithSeed(deployer.publicKey, "drainerEscrow", program.programId);
        let signature = await provider.connection.requestAirdrop(drainerEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        await program.methods.changeDrainerEscrow(drainerEscrow)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: deployer.publicKey, isSigner: true, isWritable: true },
                { pubkey: drainerEscrow, isSigner: false, isWritable: true },
            ])
            .signers([deployer])
            .rpc();
    });

    it("Creating a multisig", async function () {
        const owners = [web3.Keypair.generate(), web3.Keypair.generate(), web3.Keypair.generate()];
        const m = 2;
        // Create a multisig
        const multisig = await spl.createMultisig(provider.connection, deployer, owners, m);

        //const multisigBalanceBefore = await provider.connection.getBalance(multisig);
        //console.log("multisigBalanceBefore", multisigBalanceBefore);
        //let signature = await provider.connection.requestAirdrop(multisig, web3.LAMPORTS_PER_SOL);
        //await provider.connection.confirmTransaction(signature, "confirmed");
        //const multisigBalanceAfter = await provider.connection.getBalance(multisig);
        //console.log("multisigBalanceAfter", multisigBalanceAfter);

        // Get the multisig info
        const multisigAccountInfo = await provider.connection.getAccountInfo(multisig);
        //console.log(multisigAccountInfo);
        // Parse the multisig account data
        const multisigAccountData = spl.MultisigLayout.decode(multisigAccountInfo.data);
        //console.log(multisigAccountData);
        // Check the multisig data
        expect(owners[0].publicKey).toEqual(multisigAccountData.signer1);
        expect(owners[1].publicKey).toEqual(multisigAccountData.signer2);
        expect(owners[2].publicKey).toEqual(multisigAccountData.signer3);
        expect(m).toEqual(multisigAccountData.m);
        expect(owners.length).toEqual(multisigAccountData.n);
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
    
    it("Should fail when incorrectly updating a service", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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

    it("Updating a service", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storage.publicKey })
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
        expect(service.threshold).toEqual(newMaxThreshold);
        expect(service.agentIds).toEqual(newAgentIds);
        expect(service.slots).toEqual(newSlots);
        const compareBonds = service.bonds.every((value, index) => value.eq(newBonds[index]));
        expect(compareBonds).toEqual(true);
    });

    it("Creating a service and activating it", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Create an escrow account such that the program Id is its owner, and initialize it
        const serviceOwnerEscrow = await web3.PublicKey.createWithSeed(serviceOwner.publicKey, "serviceOwnerEscrow", program.programId);
        let signature = await provider.connection.requestAirdrop(serviceOwnerEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        const escrowBalanceBefore = await provider.connection.getBalance(serviceOwnerEscrow);
        //console.log("escrowBalanceBefore", escrowBalanceBefore);

        // Activate the service registration
        await program.methods.activateRegistration(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const escrowBalanceAfter = await provider.connection.getBalance(serviceOwnerEscrow);
        //console.log("escrowBalanceAfter", escrowBalanceAfter);

        // Check the obtained service
        const service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        expect(service.state).toEqual({"activeRegistration": {}});
    });

    it("Creating a service, activating it and registering agent instances", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Create an escrow account such that the program Id is its owner, and initialize it
        const serviceOwnerEscrow = await web3.PublicKey.createWithSeed(serviceOwner.publicKey, "serviceOwnerEscrow", program.programId);
        let signature = await provider.connection.requestAirdrop(serviceOwnerEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the service owner escrow balance before activation
        const escrowBalanceBefore = await provider.connection.getBalance(serviceOwnerEscrow);

        // Activate the service
        await program.methods.activateRegistration(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Check the escrow balance after the activation
        const escrowBalanceAfter = await provider.connection.getBalance(serviceOwnerEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Create an escrow account for the operator such that the program Id is its owner, and initialize it
        const operatorEscrow = await web3.PublicKey.createWithSeed(operator.publicKey, "operatorEscrow", program.programId);
        //console.log("serviceOwnerEscrow", serviceOwnerEscrow);
        tx = new web3.Transaction().add(
            web3.SystemProgram.createAccountWithSeed({
                fromPubkey: operator.publicKey, // funder
                newAccountPubkey: operatorEscrow,
                basePubkey: operator.publicKey,
                seed: "operatorEscrow",
                lamports: 1e9, // 0.1 SOL
                space: 256,
                programId: program.programId,
            })
        );
        await web3.sendAndConfirmTransaction(provider.connection, tx, [operator, operator]);

        // Get the operator escrow balance before activation
        const operatorEscrowBalanceBefore = await provider.connection.getBalance(operatorEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: operatorEscrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        const operatorEscrowBalanceAfter = await provider.connection.getBalance(operatorEscrow);
        expect(operatorEscrowBalanceAfter - operatorEscrowBalanceBefore).toEqual(Number(regBond));

        // Check the obtained service
        service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        // Get the operator bond balance
        const operatorBalance = await program.methods.getOperatorBalance(operator.publicKey, serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        // Check the operator balance
        expect(Number(operatorBalance)).toEqual(Number(regBond));

        expect(service.state).toEqual({"finishedRegistration": {}});
    });

    it("Creating a service, activating it, registering agent instances and terminating", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Create an escrow account such that the program Id is its owner, and initialize it
        const serviceOwnerEscrow = await web3.PublicKey.createWithSeed(serviceOwner.publicKey, "serviceOwnerEscrow", program.programId);
        let signature = await provider.connection.requestAirdrop(serviceOwnerEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the service owner escrow balance before activation
        const escrowBalanceBefore = await provider.connection.getBalance(serviceOwnerEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true }
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
        const escrowBalanceAfter = await provider.connection.getBalance(serviceOwnerEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Create an escrow account for the operator such that the program Id is its owner, and initialize it
        const operatorEscrow = await web3.PublicKey.createWithSeed(operator.publicKey, "operatorEscrow", program.programId);
        signature = await provider.connection.requestAirdrop(operatorEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the operator escrow balance before activation
        const operatorEscrowBalanceBefore = await provider.connection.getBalance(operatorEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: operatorEscrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        const operatorEscrowBalanceAfter = await provider.connection.getBalance(operatorEscrow);
        expect(operatorEscrowBalanceAfter - operatorEscrowBalanceBefore).toEqual(Number(regBond));

        // Get the service owner balance before the termination
        const serviceOwnerBalanceBefore = await provider.connection.getBalance(serviceOwner.publicKey);

        // Terminate the service
        //const seed = Buffer.from(encoder.encode("serviceOwnerEscrow"));
        //await program.methods.terminate(serviceId, "serviceOwnerEscrow")
        try {
            await program.methods.terminate(serviceId, "serviceOwnerEscrow")
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true },
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

        // Check the obtained service
        service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(service.state).toEqual({"terminatedBonded": {}});
    });

    it("Creating a service, activating it, registering agent instances, terminating and unbonding", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Create an escrow account such that the program Id is its owner, and initialize it
        const serviceOwnerEscrow = await web3.PublicKey.createWithSeed(serviceOwner.publicKey, "serviceOwnerEscrow", program.programId);
        let signature = await provider.connection.requestAirdrop(serviceOwnerEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the service owner escrow balance before activation
        const escrowBalanceBefore = await provider.connection.getBalance(serviceOwnerEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true }
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
        const escrowBalanceAfter = await provider.connection.getBalance(serviceOwnerEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Create an escrow account for the operator such that the program Id is its owner, and initialize it
        const operatorEscrow = await web3.PublicKey.createWithSeed(operator.publicKey, "operatorEscrow", program.programId);
        signature = await provider.connection.requestAirdrop(operatorEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the operator escrow balance before registering agents
        const operatorEscrowBalanceBefore = await provider.connection.getBalance(operatorEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: operatorEscrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        const operatorEscrowBalanceAfter = await provider.connection.getBalance(operatorEscrow);
        expect(operatorEscrowBalanceAfter - operatorEscrowBalanceBefore).toEqual(Number(regBond));

        // Get the service owner balance before the termination
        const serviceOwnerBalanceBefore = await provider.connection.getBalance(serviceOwner.publicKey);

        // Terminate the service
        try {
            await program.methods.terminate(serviceId, "serviceOwnerEscrow")
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true },
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
            await program.methods.unbond(serviceId, "operatorEscrow")
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: operatorEscrow, isSigner: false, isWritable: true },
                    { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                    { pubkey: drainerEscrow, isSigner: false, isWritable: true },
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
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(service.state).toEqual({"preRegistration": {}});
    });

    it("Creating a service, activating it, registering agent instances and deploying", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Create an escrow account such that the program Id is its owner, and initialize it
        const serviceOwnerEscrow = await web3.PublicKey.createWithSeed(serviceOwner.publicKey, "serviceOwnerEscrow", program.programId);
        let signature = await provider.connection.requestAirdrop(serviceOwnerEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the service owner escrow balance before activation
        const escrowBalanceBefore = await provider.connection.getBalance(serviceOwnerEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true }
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
        const escrowBalanceAfter = await provider.connection.getBalance(serviceOwnerEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Create an escrow account for the operator such that the program Id is its owner, and initialize it
        const operatorEscrow = await web3.PublicKey.createWithSeed(operator.publicKey, "operatorEscrow", program.programId);
        signature = await provider.connection.requestAirdrop(operatorEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the operator escrow balance before activation
        const operatorEscrowBalanceBefore = await provider.connection.getBalance(operatorEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: operatorEscrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        const operatorEscrowBalanceAfter = await provider.connection.getBalance(operatorEscrow);
        expect(operatorEscrowBalanceAfter - operatorEscrowBalanceBefore).toEqual(Number(regBond));

        // Deploy the service
        const multisig = web3.Keypair.generate();
        await program.methods.deploy(serviceId, multisig.publicKey)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Check the obtained service
        service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(service.state).toEqual({"deployed": {}});
    });

    it("Creating a service, activating it, registering agent instances, deploying and terminating", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Create an escrow account such that the program Id is its owner, and initialize it
        const serviceOwnerEscrow = await web3.PublicKey.createWithSeed(serviceOwner.publicKey, "serviceOwnerEscrow", program.programId);
        let signature = await provider.connection.requestAirdrop(serviceOwnerEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the service owner escrow balance before activation
        const escrowBalanceBefore = await provider.connection.getBalance(serviceOwnerEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true }
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
        const escrowBalanceAfter = await provider.connection.getBalance(serviceOwnerEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Create an escrow account for the operator such that the program Id is its owner, and initialize it
        const operatorEscrow = await web3.PublicKey.createWithSeed(operator.publicKey, "operatorEscrow", program.programId);
        signature = await provider.connection.requestAirdrop(operatorEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the operator escrow balance before activation
        const operatorEscrowBalanceBefore = await provider.connection.getBalance(operatorEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: operatorEscrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        const operatorEscrowBalanceAfter = await provider.connection.getBalance(operatorEscrow);
        expect(operatorEscrowBalanceAfter - operatorEscrowBalanceBefore).toEqual(Number(regBond));

        // Deploy the service
        const multisig = web3.Keypair.generate();
        await program.methods.deploy(serviceId, multisig.publicKey)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Terminate the service
        try {
            await program.methods.terminate(serviceId, "serviceOwnerEscrow")
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true },
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
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(service.state).toEqual({"terminatedBonded": {}});
    });

    it("Creating a service, activating it, registering agent instances, deploying, terminating and unbonding", async function () {
        // Create a service
        const transactionHash = await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        /****************************************************************************************************/
        // Get the transaction details and fees
        const commitment = "confirmed";
        const confirmationStatus = await provider.connection.confirmTransaction(transactionHash, commitment);

        const transaction = await provider.connection.getParsedConfirmedTransaction(transactionHash, commitment);
        //console.log("Transaction:", transaction);

        //const transactionInstance: TransactionInstruction | undefined = transaction.transaction?.message.instructions[0];
        //console.log("Transaction Instance:", transactionInstance);

        const transactionMetadata = await provider.connection.getTransaction(transactionHash, commitment);
        //console.log("Transaction Metadata:", transactionMetadata);

        const blockHash = transactionMetadata.transaction.message.recentBlockhash;
        const feeCalculator = await provider.connection.getFeeCalculatorForBlockhash(blockHash);
        //console.log("feeCalculator", feeCalculator);
        /****************************************************************************************************/

        // Create an escrow account such that the program Id is its owner, and initialize it
        const serviceOwnerEscrow = await web3.PublicKey.createWithSeed(serviceOwner.publicKey, "serviceOwnerEscrow", program.programId);
        let signature = await provider.connection.requestAirdrop(serviceOwnerEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the service owner escrow balance before activation
        const escrowBalanceBefore = await provider.connection.getBalance(serviceOwnerEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true }
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
        const escrowBalanceAfter = await provider.connection.getBalance(serviceOwnerEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Create an escrow account for the operator such that the program Id is its owner, and initialize it
        const operatorEscrow = await web3.PublicKey.createWithSeed(operator.publicKey, "operatorEscrow", program.programId);
        signature = await provider.connection.requestAirdrop(operatorEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the operator escrow balance before activation
        const operatorEscrowBalanceBefore = await provider.connection.getBalance(operatorEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: operatorEscrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        const operatorEscrowBalanceAfter = await provider.connection.getBalance(operatorEscrow);
        expect(operatorEscrowBalanceAfter - operatorEscrowBalanceBefore).toEqual(Number(regBond));

        // Deploy the service
        const multisig = web3.Keypair.generate();
        await program.methods.deploy(serviceId, multisig.publicKey)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Terminate the service
        try {
            await program.methods.terminate(serviceId, "serviceOwnerEscrow")
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true },
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
            await program.methods.unbond(serviceId, "operatorEscrow")
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: operatorEscrow, isSigner: false, isWritable: true },
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
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(service.state).toEqual({"preRegistration": {}});
    });

    it("Creating a service, activating it, registering agent instances, deploying, terminating and unbonding with two operators", async function () {
        // Create a service

        await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Create an escrow account such that the program Id is its owner, and initialize it
        const serviceOwnerEscrow = await web3.PublicKey.createWithSeed(serviceOwner.publicKey, "serviceOwnerEscrow", program.programId);
        let signature = await provider.connection.requestAirdrop(serviceOwnerEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the service owner escrow balance before activation
        const escrowBalanceBefore = await provider.connection.getBalance(serviceOwnerEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true }
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
        const escrowBalanceAfter = await provider.connection.getBalance(serviceOwnerEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Create escrow accounts for operators such that the program Id is its owner, and initialize it
        const operatorEscrow1 = await web3.PublicKey.createWithSeed(operator.publicKey, "operatorEscrow1", program.programId);
        signature = await provider.connection.requestAirdrop(operatorEscrow1, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get agent instances addresses
        const agentInstances = new Array(maxThreshold);
        for (let i = 0; i < maxThreshold; i++) {
            agentInstances[i] = web3.Keypair.generate().publicKey;
        }

        // Register agent instances by the first operator
        try {
            await program.methods.registerAgents(serviceId, [agentInstances[0], agentInstances[1]], [1, 2])
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                    { pubkey: operatorEscrow1, isSigner: false, isWritable: true }
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
        const operatorEscrow2 = await web3.PublicKey.createWithSeed(operator2.publicKey, "operatorEscrow2", program.programId);
        signature = await provider.connection.requestAirdrop(operatorEscrow2, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");
        tx = await provider.connection.requestAirdrop(operator2.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");

        // Register agent instances by the second operator
        try {
            await program.methods.registerAgents(serviceId, [agentInstances[2], agentInstances[3], agentInstances[4]], [1, 2, 2])
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: operator2.publicKey, isSigner: true, isWritable: true },
                    { pubkey: operatorEscrow2, isSigner: false, isWritable: true }
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

//        // Check the obtained service
//        service = await program.methods.getService(serviceId)
//            .accounts({ dataAccount: storage.publicKey })
//            .view();
//        console.log("service", service);

        // Deploy the service
        const multisig = web3.Keypair.generate();
        await program.methods.deploy(serviceId, multisig.publicKey)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Terminate the service
        try {
            await program.methods.terminate(serviceId, "serviceOwnerEscrow")
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true },
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
            await program.methods.unbond(serviceId, "operatorEscrow1")
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: operatorEscrow1, isSigner: false, isWritable: true },
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

        // Get the operator2 balance before unbond
        const operator2BalanceBefore = await provider.connection.getBalance(operator2.publicKey);

        // Unbond agent instances
        try {
            await program.methods.unbond(serviceId, "operatorEscrow2")
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: operatorEscrow2, isSigner: false, isWritable: true },
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
            .accounts({ dataAccount: storage.publicKey })
            .view();
//        console.log("service", service);

        expect(service.state).toEqual({"preRegistration": {}});
    });

    it.only("Creating a service, activating it, registering agent instances, slashing", async function () {
        // Create a service

        await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Create an escrow account such that the program Id is its owner, and initialize it
        const serviceOwnerEscrow = await web3.PublicKey.createWithSeed(serviceOwner.publicKey, "serviceOwnerEscrow", program.programId);
        let signature = await provider.connection.requestAirdrop(serviceOwnerEscrow, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get the service owner escrow balance before activation
        const escrowBalanceBefore = await provider.connection.getBalance(serviceOwnerEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true }
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
        const escrowBalanceAfter = await provider.connection.getBalance(serviceOwnerEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Create escrow accounts for operators such that the program Id is its owner, and initialize it
        const operatorEscrow1 = await web3.PublicKey.createWithSeed(operator.publicKey, "operatorEscrow1", program.programId);
        signature = await provider.connection.requestAirdrop(operatorEscrow1, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");

        // Get agent instances addresses
        const agentInstances = new Array(maxThreshold);
        for (let i = 0; i < maxThreshold; i++) {
            agentInstances[i] = web3.Keypair.generate().publicKey;
        }

        // Register agent instances by the first operator
        try {
            await program.methods.registerAgents(serviceId, [agentInstances[0], agentInstances[1]], [1, 2])
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                    { pubkey: operatorEscrow1, isSigner: false, isWritable: true }
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
        const operatorEscrow2 = await web3.PublicKey.createWithSeed(operator2.publicKey, "operatorEscrow2", program.programId);
        signature = await provider.connection.requestAirdrop(operatorEscrow2, web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");
        tx = await provider.connection.requestAirdrop(operator2.publicKey, 100 * web3.LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");

        // Register agent instances by the second operator
        try {
            await program.methods.registerAgents(serviceId, [agentInstances[2], agentInstances[3], agentInstances[4]], [1, 2, 2])
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: operator2.publicKey, isSigner: true, isWritable: true },
                    { pubkey: operatorEscrow2, isSigner: false, isWritable: true }
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

//        // Check the obtained service
//        service = await program.methods.getService(serviceId)
//            .accounts({ dataAccount: storage.publicKey })
//            .view();
//        console.log("service", service);

        // Deploy the service
        const multisig = web3.Keypair.generate();
        await program.methods.deploy(serviceId, multisig.publicKey)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Terminate the service
        try {
            await program.methods.terminate(serviceId, "serviceOwnerEscrow")
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwnerEscrow, isSigner: false, isWritable: true },
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
            await program.methods.unbond(serviceId, "operatorEscrow1")
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: operatorEscrow1, isSigner: false, isWritable: true },
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

        // Get the operator2 balance before unbond
        const operator2BalanceBefore = await provider.connection.getBalance(operator2.publicKey);

        // Unbond agent instances
        try {
            await program.methods.unbond(serviceId, "operatorEscrow2")
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: operatorEscrow2, isSigner: false, isWritable: true },
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
            .accounts({ dataAccount: storage.publicKey })
            .view();
//        console.log("service", service);

        expect(service.state).toEqual({"preRegistration": {}});


//        const drainerBalanceBefore = await provider.connection.getBalance(drainerEscrow);
//        console.log("drainerBalanceBefore", Number(drainerBalanceBefore));
//        const drainerBalanceAfter = await provider.connection.getBalance(drainerEscrow);
//        console.log("drainerBalanceAfter", Number(drainerBalanceAfter));
//
//        try {
//            await program.methods.drain(deployer.publicKey, "drainerEscrow")
//                .accounts({ dataAccount: storage.publicKey })
//                .remainingAccounts([
//                    { pubkey: deployer.publicKey, isSigner: true, isWritable: true },
//                    { pubkey: drainerEscrow, isSigner: false, isWritable: true },
//                ])
//                .signers([deployer])
//                .rpc();
//        } catch (error) {
//            if (error instanceof Error && "message" in error) {
//                console.error("Program Error:", error);
//                console.error("Error Message:", error.message);
//            } else {
//                console.error("Transaction Error:", error);
//            }
//        }
    });
});