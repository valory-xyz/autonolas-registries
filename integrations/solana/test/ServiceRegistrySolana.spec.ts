// SPDX-License-Identifier: Apache-2.0

// DISCLAIMER: This file is an example of how to mint and transfer NFTs on Solana. It is not production ready and has not been audited for security.
// Use it at your own risk.

import { loadContract, newConnectionAndPayer } from "./setup";
import { Connection, Commitment, Transaction, TransactionInstruction, Keypair, LAMPORTS_PER_SOL } from "@solana/web3.js";
import BN from "bn.js";
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
    let escrow : Keypair;
    let serviceOwner : Keypair;
    const emptyPayload = Buffer.from("", "hex");

    this.timeout(500000);

    beforeEach(async function () {
        // Allocate accounts
        deployer = Keypair.generate();
        serviceOwner = Keypair.generate();
        escrow = Keypair.generate();

        // Deploy ServiceRegistrySolana
        const deployment = await loadContract("ServiceRegistrySolana", [deployer.publicKey, baseURI, escrow.publicKey]);
        provider = deployment.provider;
        program = deployment.program;
        storage = deployment.storage;

        let tx = await provider.connection.requestAirdrop(serviceOwner.publicKey, LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
        tx = await provider.connection.requestAirdrop(escrow.publicKey, LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(tx, "confirmed");
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
        const result = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(result.serviceOwner).toEqual(serviceOwner.publicKey);
        //expect(result.configHash).toEqual(configHash);
        expect(result.threshold).toEqual(maxThreshold);
        expect(result.agentIds).toEqual(agentIds);
        expect(result.slots).toEqual(slots);
        const compareBonds = result.bonds.every((value: BN, index: number) => value.eq(bonds[index]));
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
        const result = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(result.serviceOwner).toEqual(serviceOwner.publicKey);
        //expect(result.configHash).toEqual(configHash);
        expect(result.threshold).toEqual(newMaxThreshold);
        expect(result.agentIds).toEqual(newAgentIds);
        expect(result.slots).toEqual(newSlots);
        const compareBonds = result.bonds.every((value: BN, index: number) => value.eq(newBonds[index]));
        expect(compareBonds).toEqual(true);
    });

    it.only("Crating a service and activating it", async function () {
        // Create a service
        await program.methods.create(serviceOwner.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        await program.methods.activateRegistration(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: escrow.publicKey, isSigner: false, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const balance = await provider.connection.getBalance(escrow.publicKey);
        console.log(balance);

        // Check the obtained service
        const result = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(result.state).toEqual({"activeRegistration": {}});
    });

    it("Crating a service and activating it", async function () {
        const signature = await provider.connection.requestAirdrop(serviceOwner.publicKey, LAMPORTS_PER_SOL);
        await provider.connection.confirmTransaction(signature, "confirmed");
        const balance1 = await provider.connection.getBalance(serviceOwner.publicKey);
        console.log("Blanace serviceOwner.publicKey before:",balance1);
        await program.methods.aaa(serviceOwner.publicKey,escrow.publicKey,new BN(100000000))
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true },
                { pubkey: escrow.publicKey, isSigner: false, isWritable: true },
            ])
            .signers([serviceOwner])
            .rpc();
        const balance2 = await provider.connection.getBalance(serviceOwner.publicKey);
        console.log("Balance serviceOwner.publicKey after:",balance2);
        const balance3 = await provider.connection.getBalance(escrow.publicKey);
        console.log("Balance escrow.publicKey after:",balance3);
    });

    it("Crating a service, activating it and registering agent instances", async function () {
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
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const operator = Keypair.generate();
        const agentInstance = Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(operator.publicKey, serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        // Check the obtained service
        const result = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(result.state).toEqual({"finishedRegistration": {}});
    });

    it("Crating a service, activating it, registering agent instances and terminating", async function () {
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
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const operator = Keypair.generate();
        const agentInstance = Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(operator.publicKey, serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true }
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
        const result = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(result.state).toEqual({"terminatedBonded": {}});
    });

    it("Crating a service, activating it, registering agent instances, terminating and unbonding", async function () {
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
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const operator = Keypair.generate();
        const agentInstance = Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(operator.publicKey, serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true }
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
        await program.methods.unbond(operator.publicKey, serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        // Check the obtained service
        const result = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(result.state).toEqual({"preRegistration": {}});
    });

    it("Crating a service, activating it, registering agent instances and deploying", async function () {
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
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const operator = Keypair.generate();
        const agentInstance = Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(operator.publicKey, serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true }
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
        const result = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(result.state).toEqual({"deployed": {}});
    });

    it("Crating a service, activating it, registering agent instances, deploying and terminating", async function () {
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
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const operator = Keypair.generate();
        const agentInstance = Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(operator.publicKey, serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true }
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
        const result = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(result.state).toEqual({"terminatedBonded": {}});
    });

    it("Crating a service, activating it, registering agent instances, deploying, terminating and unbonding", async function () {
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
                { pubkey: serviceOwner.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceOwner])
            .rpc();

        const operator = Keypair.generate();
        const agentInstance = Keypair.generate();
        // Register agent instance
        await program.methods.registerAgents(operator.publicKey, serviceId, [agentInstance.publicKey], [1])
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true }
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
        await program.methods.unbond(operator.publicKey, serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: operator.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([operator])
            .rpc();

        // Check the obtained service
        const result = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(result.state).toEqual({"preRegistration": {}});
    });
});
