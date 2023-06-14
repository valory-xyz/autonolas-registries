// SPDX-License-Identifier: Apache-2.0

// DISCLAIMER: This file is an example of how to mint and transfer NFTs on Solana. It is not production ready and has not been audited for security.
// Use it at your own risk.

import { loadContract, newConnectionAndPayer } from "./setup";
import { Keypair } from "@solana/web3.js";
import BN from "bn.js";
import { createMint, getOrCreateAssociatedTokenAccount, TOKEN_PROGRAM_ID } from "@solana/spl-token";
import expect from "expect";

describe("ServiceRegistrySolana", function () {
    const baseURI = "https://localhost/service/";
    const configHash = Buffer.from("5".repeat(64), "hex");
    const regBond = 1000;
    const regDeposit = 1000;
    const agentIds = [1, 2];
    const slots = [3, 4];
    const bonds = [regBond, 2 * regBond];
    const serviceId = 1;
    const agentId = 1;
    const maxThreshold = slots[0] + slots[1];
    let provider : any;
    let program : any;
    let storage : Keypair;
    let metadataAuthority : Keypair;
    let serviceAuthority : Keypair;

    this.timeout(500000);

    beforeEach(async function () {
        // Allocate accounts
        metadataAuthority = Keypair.generate();
        serviceAuthority = Keypair.generate();

        // Deploy ServiceRegistrySolana
        const deployment = await loadContract("ServiceRegistrySolana", [metadataAuthority.publicKey, baseURI]);
        provider = deployment.provider;
        program = deployment.program;
        storage = deployment.storage;

    });

    it("Creating a service", async function () {
        // Create a service
        await program.methods.create(serviceAuthority.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceAuthority.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceAuthority])
            .rpc();

        // Check the obtained service
        const result = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(result.serviceOwner).toEqual(serviceAuthority.publicKey);
        //expect(result.configHash).toEqual(configHash);
        expect(result.threshold).toEqual(maxThreshold);
        expect(result.agentIds).toEqual(agentIds);
        expect(result.slots).toEqual(slots);
        expect(result.bonds).toEqual(bonds);
    });

    it("Updating a service", async function () {
//        try {
//        } catch (error) {
//              //console.error("Error:", error);
//        }

        // Create a service
        await program.methods.create(serviceAuthority.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceAuthority.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceAuthority])
            .rpc();

        // Update the service
        const newAgentIds = [1, 2, 4];
        const newSlots = [2, 1, 5];
        const newBonds = [regBond, regBond, regBond];
        const newMaxThreshold = newSlots[0] + newSlots[1] + newSlots[2];
        await program.methods.update(configHash, newAgentIds, newSlots, newBonds, newMaxThreshold, serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: serviceAuthority.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([serviceAuthority])
            .rpc();

        // Check the obtained service
        const result = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();

        expect(result.serviceOwner).toEqual(serviceAuthority.publicKey);
        //expect(result.configHash).toEqual(configHash);
        expect(result.threshold).toEqual(newMaxThreshold);
        expect(result.agentIds).toEqual(newAgentIds);
        expect(result.slots).toEqual(newSlots);
        expect(result.bonds).toEqual(newBonds);
    });
});
