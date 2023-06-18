// SPDX-License-Identifier: Apache-2.0

// DISCLAIMER: This file is an example of how to mint and transfer NFTs on Solana. It is not production ready and has not been audited for security.
// Use it at your own risk.

import { loadContract, newConnectionAndPayer } from "./setup";
import { Connection, Commitment, Transaction, TransactionInstruction, PublicKey, Keypair, LAMPORTS_PER_SOL, SystemProgram, sendAndConfirmTransaction } from "@solana/web3.js";
import BN from "bn.js";
import { TextEncoder } from "text-encoding-utf-8";
import { createMint, getOrCreateAssociatedTokenAccount, TOKEN_PROGRAM_ID } from "@solana/spl-token";
import expect from "expect";

describe("ServiceRegistrySolana", function () {
    const baseURI = "https://localhost/service/";
    const configHash = Buffer.from("5".repeat(64), "hex");
    const regBond = new BN(1000);
    const regDeposit = new BN(1000);
    const agentIds = [1, 2];
    const slots = [3, 4];
    const bonds = [regBond, regBond];
    const serviceId = 1;
    const agentId = 1;
    const maxThreshold = slots[0] + slots[1];
    let provider : any;
    let program : any;
    let storage : Keypair;
    let deployer : Keypair;
    let escrow : PublicKey;
    let operator: Keypair
    let serviceOwner : Keypair;
    const emptyPayload = Buffer.from("", "hex");
    const encoder = new TextEncoder();

    this.timeout(500000);

    beforeEach(async function () {
        // Allocate accounts
        deployer = Keypair.generate();
        serviceOwner = Keypair.generate();
        operator = Keypair.generate();

        // Deploy ServiceRegistrySolana
        const deployment = await loadContract("ServiceRegistrySolana", [deployer.publicKey, baseURI]);
        provider = deployment.provider;
        program = deployment.program;
        storage = deployment.storage;

        let tx = await provider.connection.requestAirdrop(deployer.publicKey, 100 * LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
        tx = await provider.connection.requestAirdrop(serviceOwner.publicKey, 100 * LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
        tx = await provider.connection.requestAirdrop(operator.publicKey, 100 * LAMPORTS_PER_SOL);
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

    it.only("Creating a service", async function () {
        // Create a service
        const tx = await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
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
        const compareBonds = service.bonds.every((value: BN, index: number) => value.eq(bonds[index]));
        expect(compareBonds).toEqual(true);
    });

    it("Shoudl fail when incorrectly updating a service", async function () {
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
        const compareBonds = service.bonds.every((value: BN, index: number) => value.eq(newBonds[index]));
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
        const serviceOwnerEscrow = await PublicKey.createWithSeed(serviceOwner.publicKey, "escrow", program.programId);
        //console.log("serviceOwnerEscrow", serviceOwnerEscrow);
        const tx = new Transaction().add(
            SystemProgram.createAccountWithSeed({
                fromPubkey: serviceOwner.publicKey, // funder
                newAccountPubkey: serviceOwnerEscrow,
                basePubkey: serviceOwner.publicKey,
                seed: "escrow",
                lamports: 1e9, // 0.1 SOL
                space: 256,
                programId: program.programId,
            })
        );
        await sendAndConfirmTransaction(provider.connection, tx, [serviceOwner, serviceOwner]);

        const escrowBalanceBefore = await provider.connection.getBalance(serviceOwnerEscrow);
        console.log("escrowBalanceBefore", escrowBalanceBefore);

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
        console.log("escrowBalanceAfter", escrowBalanceAfter);

        const curEscrow = await program.methods.escrow()
            .accounts({ dataAccount: storage.publicKey })
            .view();
        console.log("curEscrow", curEscrow);
        console.log("serviceOwnerEscrow", serviceOwnerEscrow);
        return;

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
        const serviceOwnerEscrow = await PublicKey.createWithSeed(serviceOwner.publicKey, "serviceOwnerEscrow", program.programId);
        //console.log("serviceOwnerEscrow", serviceOwnerEscrow);
        let tx = new Transaction().add(
            SystemProgram.createAccountWithSeed({
                fromPubkey: serviceOwner.publicKey, // funder
                newAccountPubkey: serviceOwnerEscrow,
                basePubkey: serviceOwner.publicKey,
                seed: "serviceOwnerEscrow",
                lamports: 1e9, // 0.1 SOL
                space: 256,
                programId: program.programId,
            })
        );
        await sendAndConfirmTransaction(provider.connection, tx, [serviceOwner, serviceOwner]);

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
        const operatorEscrow = await PublicKey.createWithSeed(operator.publicKey, "operatorEscrow", program.programId);
        //console.log("serviceOwnerEscrow", serviceOwnerEscrow);
        tx = new Transaction().add(
            SystemProgram.createAccountWithSeed({
                fromPubkey: operator.publicKey, // funder
                newAccountPubkey: operatorEscrow,
                basePubkey: operator.publicKey,
                seed: "operatorEscrow",
                lamports: 1e9, // 0.1 SOL
                space: 256,
                programId: program.programId,
            })
        );
        await sendAndConfirmTransaction(provider.connection, tx, [operator, operator]);

        // Get the operator escrow balance before activation
        const operatorEscrowBalanceBefore = await provider.connection.getBalance(operatorEscrow);

        const agentInstance = Keypair.generate();
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

    it('transfer with seed', async function transfer_with_seed() {
        //const payer = new Keypair();
        //const dest = new Keypair();
        const seed = "seed";
        //const assign_account = new PublicKey('AddressLookupTab1e1111111111111111111111111');
        const operatorEscrow = await PublicKey.createWithSeed(operator.publicKey, seed, program.programId);

        //let signature = await provider.connection.requestAirdrop(operatorEscrow, LAMPORTS_PER_SOL);
        //await provider.connection.confirmTransaction(signature, 'confirmed');

        await program.methods.transfer(
            operator.publicKey, // from
            operatorEscrow, // to
            new BN(100000000))
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: operatorEscrow, isSigner: false, isWritable: true },
            ])
            .accounts({ dataAccount: storage.publicKey })
            .signers([operator]).rpc();

        await program.methods.transferWithSeed(
            operatorEscrow, // from_pubkey
            operator.publicKey, // from_base
            seed, // seed
            program.programId, // from_owner
            operator.publicKey, // to_pubkey
            new BN(100000000))
            .remainingAccounts([
                { pubkey: operatorEscrow, isSigner: false, isWritable: true },
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
            ])
            .accounts({ dataAccount: storage.publicKey })
            .signers([operator]).rpc();
    });

    it("Creating a service, activating it, registering agent instances and terminating", async function () {
//        const accountInfo = await provider.connection.getAccountInfo(escrow);
//        console.log(accountInfo);
//        return;

        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, [1], [1], [regBond], 1)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Create an escrow account such that the program Id is its owner, and initialize it
        const serviceOwnerEscrow = await PublicKey.createWithSeed(serviceOwner.publicKey, "serviceOwnerEscrow", program.programId);
        let signature = await provider.connection.requestAirdrop(serviceOwnerEscrow, LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");
        //console.log("serviceOwnerEscrow", serviceOwnerEscrow);
//        let tx = new Transaction().add(
//            SystemProgram.createAccountWithSeed({
//                fromPubkey: serviceOwner.publicKey, // funder
//                newAccountPubkey: serviceOwnerEscrow,
//                basePubkey: serviceOwner.publicKey,
//                seed: "serviceOwnerEscrow",
//                lamports: 1e9, // 0.1 SOL
//                space: 0,
//                programId: program.programId,
//            })
//        );
//        await sendAndConfirmTransaction(provider.connection, tx, [serviceOwner, serviceOwner]);

        // Get the service owner escrow balance before activation
        const escrowBalanceBefore = await provider.connection.getBalance(serviceOwnerEscrow);

        // Activate the service
        try{
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
        const operatorEscrow = await PublicKey.createWithSeed(operator.publicKey, "operatorEscrow", program.programId);
        signature = await provider.connection.requestAirdrop(operatorEscrow, LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");
        //console.log("serviceOwnerEscrow", serviceOwnerEscrow);
//        let tx = new Transaction().add(
//            SystemProgram.createAccountWithSeed({
//                fromPubkey: operator.publicKey, // funder
//                newAccountPubkey: operatorEscrow,
//                basePubkey: operator.publicKey,
//                seed: "operatorEscrow",
//                lamports: 1e9, // 0.1 SOL
//                space: 0,
//                programId: program.programId,
//            })
//        );
//        await sendAndConfirmTransaction(provider.connection, tx, [operator, operator]);

        // Get the operator escrow balance before activation
        const operatorEscrowBalanceBefore = await provider.connection.getBalance(operatorEscrow);

        const agentInstance = Keypair.generate();
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
        try{
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

        // Activate the service
        await program.methods.activateRegistration(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: escrow, isSigner: false, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const agentInstance = Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: escrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        // Terminate the service
        await program.methods.terminate(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Unbond agent instances
        await program.methods.unbond(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        // Check the obtained service
        const service = await program.methods.getService(serviceId)
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

        // Whitelist the multisig implementation
        const multisigImplementation = Keypair.generate();
        await program.methods.changeMultisigPermission(multisigImplementation.publicKey, true)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: deployer.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([deployer])
            .rpc();

        // Activate the service
        await program.methods.activateRegistration(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: escrow, isSigner: false, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const agentInstance = Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: escrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        // Deploy the service
        await program.methods.deploy(serviceId, multisigImplementation.publicKey, emptyPayload)
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

        // Whitelist the multisig implementation
        const multisigImplementation = Keypair.generate();
        await program.methods.changeMultisigPermission(multisigImplementation.publicKey, true)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: deployer.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([deployer])
            .rpc();

        // Activate the service
        await program.methods.activateRegistration(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: escrow, isSigner: false, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const agentInstance = Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: escrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        // Deploy the service
        await program.methods.deploy(serviceId, multisigImplementation.publicKey, emptyPayload)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Terminate the service
        await program.methods.terminate(serviceId)
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
        const commitment: Commitment = "confirmed";
        const confirmationStatus = await provider.connection.confirmTransaction(transactionHash, commitment);

        const transaction = await provider.connection.getParsedConfirmedTransaction(transactionHash, commitment);
        //console.log("Transaction:", transaction);

        const transactionInstance: TransactionInstruction | undefined = transaction.transaction?.message.instructions[0];
        //console.log("Transaction Instance:", transactionInstance);

        const transactionMetadata = await provider.connection.getTransaction(transactionHash, commitment);
        //console.log("Transaction Metadata:", transactionMetadata);

        const blockHash = transactionMetadata.transaction.message.recentBlockhash;
        const feeCalculator = await provider.connection.getFeeCalculatorForBlockhash(blockHash);
        //console.log("feeCalculator", feeCalculator);
        /****************************************************************************************************/

        // Whitelist the multisig implementation
        const multisigImplementation = Keypair.generate();
        await program.methods.changeMultisigPermission(multisigImplementation.publicKey, true)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: deployer.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([deployer])
            .rpc();

        // Activate the service
        await program.methods.activateRegistration(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: escrow, isSigner: false, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const agentInstance = Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true },
                { pubkey: escrow, isSigner: false, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        // Deploy the service
        await program.methods.deploy(serviceId, multisigImplementation.publicKey, emptyPayload)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Terminate the service
        await program.methods.terminate(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Unbond agent instances
        await program.methods.unbond(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        // Check the obtained service
        const service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(service.state).toEqual({"preRegistration": {}});
    });
});
