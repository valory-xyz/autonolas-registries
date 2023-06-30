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
    let storage;
    let deployer;
    let pdaEscrow;
    let bumpBytes;
    let operator;
    let serviceOwner;

    let init = false;

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

        const programKey = loadKey("ServiceRegistrySolana.key");

        storage = web3.Keypair.generate();
        const space = 500000;
        await createAccount(provider, storage, programKey.publicKey, space);
        init = true;
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

    it.skip("Creating a 100 services. Storage usage ...", async function () {
        // Create a service
        for (let step = 0; step < 100; step++) {
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
                console.log("step",step);
                break;
            }
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
        console.log("buff:",buff.toString('hex')); 
        console.log("storageKey info:",infoStorageKey);
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

    it("Changing ownership of the program", async function () {
        // Trying to change the owner not by the owner
        try {
            await program.methods.changeOwner(serviceOwner.publicKey)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([serviceOwner])
                .rpc();
        } catch (error) {}

        // Change the owner to the serviceOwner
        await program.methods.changeOwner(serviceOwner.publicKey)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: deployer.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([deployer])
            .rpc();

        // Check the updated program owner
        let owner = await program.methods.owner()
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(owner).toEqual(serviceOwner.publicKey);

        // Trying to change the owner back but not by the owner
        try {
            await program.methods.changeOwner(deployer.publicKey)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: deployer.publicKey, isSigner: true, isWritable: true }
                ])
                .signers([deployer])
                .rpc();
        } catch (error) {}

        // Change the owner back to the deployer
        await program.methods.changeOwner(deployer.publicKey)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        owner = await program.methods.owner()
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(owner).toEqual(deployer.publicKey);
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

        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);
        //console.log("escrowBalanceBefore", escrowBalanceBefore);

        // Activate the service registration
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
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

        let escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
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

        // Get the service owner escrow balance before activation
        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Activate the service
        await program.methods.activateRegistration(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: pdaEscrow, isSigner: false, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Check the escrow balance after the activation
        let escrowBalanceAfter = await provider.connection.getBalance(pdaEscrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get the operator escrow balance before activation
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
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

        // Activate the service registration
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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

        // Get the service owner escrow balance before activation
        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get the operator escrow balance before registering agents
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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

        // Get the service owner escrow balance before activation
        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get the operator escrow balance before activation
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
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

        // Get the service owner escrow balance before activation
        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get the operator escrow balance before activation
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Terminate the service
        try {
            await program.methods.terminate(serviceId)
                .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

        // Get the operator escrow balance before activation
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        const agentInstance = web3.Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Terminate the service
        try {
            await program.methods.terminate(serviceId)
                .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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

        // Get the service owner escrow balance before activation
        let escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Activate the service
        try {
            await program.methods.activateRegistration(serviceId)
                .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(service.agentInstances.length).toEqual(agentInstances.length);
        for (let i = 0; i < agentInstances.length; i++) {
            expect(service.agentInstances[i]).toEqual(agentInstances[i]);
        }

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
            await program.methods.terminate(serviceId)
                .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(service.agentInstances.length).toEqual(agentInstances.length);
        expect(service.agentIdForAgentInstances[0]).toEqual(0);
        expect(service.agentIdForAgentInstances[1]).toEqual(0);

        // Get the operator2 balance before unbond
        const operator2BalanceBefore = await provider.connection.getBalance(operator2.publicKey);

        // Unbond agent instances by operator2
        try {
            await program.methods.unbond(serviceId)
                .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(service.operators.length).toEqual(0);
        expect(service.agentInstances.length).toEqual(0);
        expect(service.agentIdForAgentInstances.length).toEqual(0);

        expect(service.state).toEqual({"preRegistration": {}});
    });

    it("Creating a service, activating it, registering agent instances, slashing", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [4], [regBond], 4)
            .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Slash the operator
        try {
            await program.methods.slash([agentInstances[0]], [regFine], serviceId)
                .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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
                .accounts({ dataAccount: storage.publicKey })
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
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(service.state).toEqual({"preRegistration": {}});

        // Get the escrow balance before drain
        escrowBalanceBefore = await provider.connection.getBalance(pdaEscrow);

        // Drain slashed funds
        try {
            await program.methods.drain(deployer.publicKey)
                .accounts({ dataAccount: storage.publicKey })
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

    it("Managing services in different states", async function () {
        // Get different service owners
        const serviceOwners = new Array(3);
        for (let i = 0; i < 3; i++) {
            serviceOwners[i] = web3.Keypair.generate();
            const tx = await provider.connection.requestAirdrop(serviceOwners[i].publicKey, 100 * web3.LAMPORTS_PER_SOL);
            await provider.connection.confirmTransaction(tx, "confirmed");
        }

        // Creating 3 services and activating them
        for (let i = 0; i < 3; i++) {
            await program.methods.create(serviceOwners[i].publicKey, configHash, agentIds, slots, bonds, maxThreshold)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwners[i].publicKey, isSigner: true, isWritable: true }
                ])
                .signers([serviceOwners[i]])
                .rpc();

            await program.methods.activateRegistration(serviceId + i)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwners[i].publicKey, isSigner: true, isWritable: true },
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true }
                ])
                .signers([serviceOwners[i]])
                .rpc();
        }

        // Get agent instances addresses
        const agentInstancesFull = new Array(3);
        for (let i = 0; i < 3; i++) {
            const agentInstances = new Array(maxThreshold);
            for (let j = 0; j < maxThreshold; j++) {
                agentInstances[j] = web3.Keypair.generate().publicKey;
            }
            agentInstancesFull[i] = agentInstances;
        }

        const operators = new Array(3);
        for (let i = 0; i < 3; i++) {
            operators[i] = web3.Keypair.generate();
            const tx = await provider.connection.requestAirdrop(operators[i].publicKey, 100 * web3.LAMPORTS_PER_SOL);
            await provider.connection.confirmTransaction(tx, "confirmed");
        }

        // Register agent instances by three different operators
        for (let i = 0; i < 3; i++) {
            try {
                await program.methods.registerAgents(serviceId + i, agentInstancesFull[i], [1, 1, 2, 2, 2])
                    .accounts({ dataAccount: storage.publicKey })
                    .remainingAccounts([
                        { pubkey: operators[i].publicKey, isSigner: true, isWritable: true },
                        { pubkey: pdaEscrow, isSigner: false, isWritable: true }
                    ])
                    .signers([operators[i]])
                    .rpc();
            } catch (error) {
                if (error instanceof Error && "message" in error) {
                    console.error("Program Error:", error);
                    console.error("Error Message:", error.message);
                } else {
                    console.error("Transaction Error:", error);
                }
            }
        }

        // Deploy services
        for (let i = 0; i < 3; i++) {
            const multisig = web3.Keypair.generate();
            await program.methods.deploy(serviceId + i, multisig.publicKey)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: serviceOwners[i].publicKey, isSigner: true, isWritable: true }
                ])
                .signers([serviceOwners[i]])
                .rpc();
        }

        // Terminate last two services
        for (let i = 1; i < 3; i++) {
            try {
                await program.methods.terminate(serviceId + i)
                    .accounts({ dataAccount: storage.publicKey })
                    .remainingAccounts([
                        { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                        { pubkey: serviceOwners[i].publicKey, isSigner: true, isWritable: true }
                    ])
                    .signers([serviceOwners[i]])
                    .rpc();
            } catch (error) {
                if (error instanceof Error && "message" in error) {
                    console.error("Program Error:", error);
                    console.error("Error Message:", error.message);
                } else {
                    console.error("Transaction Error:", error);
                }
            }
        }

        // Unbond all the agent instances by the operator of the last service
        try {
            await program.methods.unbond(serviceId + 2)
                .accounts({ dataAccount: storage.publicKey })
                .remainingAccounts([
                    { pubkey: pdaEscrow, isSigner: false, isWritable: true },
                    { pubkey: operators[2].publicKey, isSigner: true, isWritable: true }
                ])
                .signers([operators[2]])
                .rpc();
        } catch (error) {
            if (error instanceof Error && "message" in error) {
                console.error("Program Error:", error);
                console.error("Error Message:", error.message);
            } else {
                console.error("Transaction Error:", error);
            }
        }

        // Check obtained services
        const services = new Array(3);
        for (let i = 0; i < 3; i++) {
            services[i] = await program.methods.getService(serviceId + i)
                .accounts({ dataAccount: storage.publicKey })
                .view();
        }
        expect(services[0].state).toEqual({"deployed": {}});
        expect(services[1].state).toEqual({"terminatedBonded": {}});
        expect(services[2].state).toEqual({"preRegistration": {}});
    });
});