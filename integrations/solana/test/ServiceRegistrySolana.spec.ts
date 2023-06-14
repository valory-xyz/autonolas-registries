// SPDX-License-Identifier: Apache-2.0

// DISCLAIMER: This file is an example of how to mint and transfer NFTs on Solana. It is not production ready and has not been audited for security.
// Use it at your own risk.

import { loadContract, newConnectionAndPayer } from "./setup";
import { Keypair } from "@solana/web3.js";
import BN from "bn.js";
import { createMint, getOrCreateAssociatedTokenAccount, TOKEN_PROGRAM_ID } from "@solana/spl-token";
import expect from "expect";

describe("ServiceRegistrySolana", function () {
    const configHash = Buffer.from("5".repeat(64), "hex");
    const regBond = 1000;
    const regDeposit = 1000;
    const agentIds = [1, 2];
    const slots = [3, 4];
    const bonds = [regBond, regBond];
    const agentParams = [[3, regBond], [4, regBond]];
    const serviceId = 1;
    const agentId = 1;
    const maxThreshold = agentParams[0][0] + agentParams[1][0];

    this.timeout(500000);

    it("Creating a service", async function mint_nft() {
        const [connection, payer] = newConnectionAndPayer();
        const mint_authority = Keypair.generate();
        const freezeAuthority = Keypair.generate();

        // Create and initialize a new mint based on the funding account and a mint authority
        const mint = await createMint(
            connection,
            payer,
            mint_authority.publicKey,
            freezeAuthority.publicKey,
            0
        );

        const nft_owner = Keypair.generate();
        const metadata_authority = Keypair.generate();
        const manager = Keypair.generate();

        // On Solana, an account must have an associated token account to save information about how many tokens
        // the owner account owns. The associated account depends on both the mint account and the owner
        const owner_token_account = await getOrCreateAssociatedTokenAccount(
            connection,
            payer,
            mint, // Mint account
            nft_owner.publicKey // Owner account
        );

        const baseURI = "https://localhost/service/";
        const locked = new BN(1);

        // Each contract in this example is a unique NFT
        const { provider, program, storage } = await loadContract("ServiceRegistrySolana", [metadata_authority.publicKey, baseURI]);

//        try {
//        } catch (error) {
//              //console.error("Error:", error);
//        }

        // Create a service
        await program.methods.create(mint_authority.publicKey, configHash, agentIds, slots, bonds, maxThreshold)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: mint_authority.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([mint_authority])
            .rpc();

        let result = await program.methods.tokenUri(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();
        console.log(result);

        result = await program.methods.getService(serviceId)
            .accounts({ dataAccount: storage.publicKey })
            .view();
        console.log(result);
        return;

        // Create a service
        await program.methods.create(
            mint_authority.publicKey,
            configHash,
            agentIds,
            agentParams,
            maxThreshold)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: mint_authority.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([mint_authority])
            .rpc();
        return;

        // Create a collectible for an owner given a mint authority.
        await program.methods.createCollectible(
            mint_authority.publicKey,
            owner_token_account.address)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: mint, isSigner: false, isWritable: true },
                { pubkey: owner_token_account.address, isSigner: false, isWritable: true },
                { pubkey: mint_authority.publicKey, isSigner: true, isWritable: true }
            ])
            .signers([mint_authority])
            .rpc();
        return;

        const new_owner = Keypair.generate();

        // A new owner must have an associated token account
        const new_owner_token_account = await getOrCreateAssociatedTokenAccount(
            connection,
            payer,
            mint, // Mint account associated to the NFT
            new_owner.publicKey // New owner account
        );


        // Transfer ownership to another owner
        await program.methods.transferOwnership(
            owner_token_account.address,
            new_owner_token_account.address)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: new_owner_token_account.address, isSigner: false, isWritable: true },
                { pubkey: owner_token_account.address, isSigner: false, isWritable: true },
                { pubkey: nft_owner.publicKey, isSigner: true, isWritable: true },
            ])
            .signers([nft_owner])
            .rpc();

        // Confirm that the ownership transference worked
        const verify_transfer_result = await program.methods.isOwner(
            new_owner.publicKey,
            new_owner_token_account.address)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: new_owner_token_account.address, isSigner: false, isWritable: false },
            ])
            .view();

        expect(verify_transfer_result).toBe(true);

        // Retrieve information about the NFT
        const token_uri = await program.methods.getNftUri()
            .accounts({ dataAccount: storage.publicKey })
            .view();

        //expect(token_uri).toBe(nft_uri);

        // Update the NFT URI
        const new_uri = "www.token.com";
        await program.methods.updateNftUri(new_uri)
            .accounts({ dataAccount: storage.publicKey })
            .remainingAccounts([
                { pubkey: metadata_authority.publicKey, isSigner: true, isWritable: true },
            ])
            .signers([metadata_authority])
            .rpc();

        const new_uri_saved = await program.methods.getNftUri()
            .accounts({ dataAccount: storage.publicKey })
            .view();
        expect(new_uri_saved).toBe(new_uri);
    });
});
