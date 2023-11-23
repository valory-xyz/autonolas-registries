/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("HashCheckpoint", function () {
    let hashCheckpoint;
    let signers;
    const defaultHash = "0x" + "9".repeat(64);
    // const dependencies = [1];
    // const AddressZero = "0x" + "0".repeat(40);
    beforeEach(async function () {
        const HashCheckpoint = await ethers.getContractFactory("HashCheckpoint");
        hashCheckpoint = await HashCheckpoint.deploy("https://localhost/agent/");
        await hashCheckpoint.deployed();
        signers = await ethers.getSigners();
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            expect(await hashCheckpoint.baseURI()).to.equal("https://localhost/agent/");
        });

        it("Should return emtpy hash when checking for some hash", async function () {
            expect(await hashCheckpoint.latestHashes(signers[1].address)).to.equal("0x0000000000000000000000000000000000000000000000000000000000000000");
        });

        it("Should return empty hash with prefix when checking for some hash", async function () {
            expect(await hashCheckpoint.latestHash(signers[1].address)).to.equal("f017012200000000000000000000000000000000000000000000000000000000000000000");
        });

        it("Should return empty hash uri when checking for some hash", async function () {
            expect(await hashCheckpoint.latestHashURI(signers[1].address)).to.equal("https://localhost/agent/f017012200000000000000000000000000000000000000000000000000000000000000000");
        });

        it("Setting the base URI", async function () {
            await hashCheckpoint.setBaseURI("https://localhost2/agent/");
            expect(await hashCheckpoint.baseURI()).to.equal("https://localhost2/agent/");
        });
    });

    context("Checkpointing hashes", async function () {
        it("Should update latest hash correctly and emit event", async function () {
            const tx = await hashCheckpoint.connect(signers[2]).checkpoint(defaultHash);
            const result = await tx.wait();
            expect(result.events[0].args.emitter).to.equal(signers[2].address);
            expect(result.events[0].args.hash).to.equal(defaultHash);
            expect(await hashCheckpoint.latestHashes(signers[2].address)).to.equal(defaultHash);
        });

    });
});
