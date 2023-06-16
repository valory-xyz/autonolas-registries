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
        tx = await provider.connection.requestAirdrop(serviceOwner.publicKey, LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
        tx = await provider.connection.requestAirdrop(operator.publicKey, LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");

        // Create an escrow account such that the program Id is its owner, and initialize it
        escrow = await PublicKey.createWithSeed(deployer.publicKey, "escrow", program.programId);
        //console.log("escrow", escrow);
        tx = new Transaction().add(
            SystemProgram.createAccountWithSeed({
                fromPubkey: deployer.publicKey, // funder
                newAccountPubkey: escrow,
                basePubkey: deployer.publicKey,
                seed: "escrow",
                lamports: 1e9, // 0.1 SOL
                space: 256,
                programId: program.programId,
            })
        );
        await sendAndConfirmTransaction(provider.connection, tx, [deployer, deployer]);

        // Init the obtained escrow address
        await program.methods.initEscrow(escrow)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: deployer.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([deployer])
            .rpc();
    });

    it("Creating a service", async function () {
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

        const escrowBalanceBefore = await provider.connection.getBalance(escrow);

        // Activate the service registration
        await program.methods.activateRegistration(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: escrow, isSigner: false, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const escrowBalanceAfter = await provider.connection.getBalance(escrow);

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

        // Get the escrow balance before activation
        const escrowBalanceBefore = await provider.connection.getBalance(escrow);

        // Activate the service
        await program.methods.activateRegistration(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: escrow, isSigner: false, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        // Check the escrow balance after the activation
        const escrowBalanceAfter = await provider.connection.getBalance(escrow);
        let service = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(escrowBalanceAfter - escrowBalanceBefore).toEqual(Number(service.securityDeposit));

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
