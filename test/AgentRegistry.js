/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AgentRegistry", function () {
    let componentRegistry;
    let agentRegistry;
    let signers;
    const description = ethers.utils.formatBytes32String("agent description");
    const componentHash = "0x" + "5".repeat(64);
    const agentHash = "0x" + "0".repeat(64);
    const agentHash1 = "0x" + "1".repeat(64);
    const agentHash2 = "0x" + "2".repeat(64);
    const dependencies = [1];
    const AddressZero = "0x" + "0".repeat(40);
    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
            componentRegistry.address);
        await agentRegistry.deployed();
        signers = await ethers.getSigners();

        await componentRegistry.changeManager(signers[0].address);
        await componentRegistry.create(signers[0].address, signers[0].address, componentHash, description, []);
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            expect(await agentRegistry.name()).to.equal("agent");
            expect(await agentRegistry.symbol()).to.equal("MECH");
            expect(await agentRegistry.baseURI()).to.equal("https://localhost/agent/");
        });

        it("Should fail when checking for the token id existence", async function () {
            const tokenId = 0;
            expect(await agentRegistry.exists(tokenId)).to.equal(false);
        });

        it("Should fail when trying to change the mechManager from a different address", async function () {
            await expect(
                agentRegistry.connect(signers[1]).changeManager(signers[1].address)
            ).to.be.revertedWith("OwnerOnly");
        });

        it("Setting the base URI", async function () {
            await agentRegistry.setBaseURI("https://localhost2/agent/");
            expect(await agentRegistry.baseURI()).to.equal("https://localhost2/agent/");
        });
    });

    context("Agent creation", async function () {
        it("Should fail when creating an agent without a mechManager", async function () {
            const user = signers[2];
            await expect(
                agentRegistry.create(user.address, user.address, agentHash, description, dependencies)
            ).to.be.revertedWith("ManagerOnly");
        });

        it("Should fail when creating an agent with a zero address of owner and / or developer", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await expect(
                agentRegistry.connect(mechManager).create(AddressZero, user.address, agentHash, description,
                    dependencies)
            ).to.be.revertedWith("ZeroAddress");
            await expect(
                agentRegistry.connect(mechManager).create(user.address, AddressZero, agentHash, description,
                    dependencies)
            ).to.be.revertedWith("ZeroAddress");
            await expect(
                agentRegistry.connect(mechManager).create(AddressZero, AddressZero, agentHash, description,
                    dependencies)
            ).to.be.revertedWith("ZeroAddress");
        });

        it("Should fail when creating an agent with an empty description", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await expect(
                agentRegistry.connect(mechManager).create(user.address, user.address, agentHash, "0x" + "0".repeat(64),
                    dependencies)
            ).to.be.revertedWith("ZeroValue");
        });

        it("Should fail when creating a second agent with the same hash", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address, user.address, agentHash,
                description, dependencies);
            await expect(
                agentRegistry.connect(mechManager).create(user.address, user.address, agentHash,
                    description, dependencies)
            ).to.be.revertedWith("HashExists");
        });

        it("Should fail when component number is less or equal to zero", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await expect(
                agentRegistry.connect(mechManager).create(user.address, user.address, agentHash,
                    description, [0])
            ).to.be.revertedWith("ComponentNotFound");
        });

        it("Should fail when creating a non-existent component dependency", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await expect(
                agentRegistry.connect(mechManager).create(user.address, user.address, agentHash,
                    description, [2])
            ).to.be.revertedWith("ComponentNotFound");
        });

        it("Token Id=1 after first successful agent creation must exist ", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const tokenId = 1;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address, user.address,
                agentHash, description, dependencies);
            expect(await agentRegistry.balanceOf(user.address)).to.equal(1);
            expect(await agentRegistry.exists(tokenId)).to.equal(true);
        });

        it("Catching \"Transfer\" event log after successful creation of an agent", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            const agent = await agentRegistry.connect(mechManager).create(user.address, user.address,
                agentHash, description, dependencies);
            const result = await agent.wait();
            expect(result.events[0].event).to.equal("Transfer");
        });

        it("Getting agent info after its creation", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const tokenId = 1;
            const lastDependencies = [1, 2];
            await componentRegistry.create(user.address, user.address, agentHash, description, []);
            await agentRegistry.changeManager(mechManager.address);
            const description2 = ethers.utils.id("component description2");
            await agentRegistry.connect(mechManager).create(user.address, user.address,
                agentHash2, description2, lastDependencies);

            let agentInfo = await agentRegistry.getInfo(tokenId);
            expect(agentInfo.unitOwner).to.equal(user.address);
            expect(agentInfo.developer).to.equal(user.address);
            expect(agentInfo.unitHash.hash).to.equal(agentHash2.hash);
            expect(agentInfo.description).to.equal(description2);
            expect(agentInfo.numDependencies).to.equal(lastDependencies.length);
            for (let i = 0; i < lastDependencies.length; i++) {
                expect(agentInfo.dependencies[i]).to.equal(lastDependencies[i]);
            }
            // Getting info about non-existent agent Id
            agentInfo = await agentRegistry.getInfo(tokenId + 1);
            expect(agentInfo.unitOwner).to.equal(AddressZero);

            let agentDependencies = await agentRegistry.getDependencies(tokenId);
            expect(agentDependencies.numDependencies).to.equal(lastDependencies.length);
            for (let i = 0; i < lastDependencies.length; i++) {
                expect(agentDependencies.dependencies[i]).to.equal(lastDependencies[i]);
            }
            agentDependencies = await agentRegistry.getDependencies(tokenId + 1);
            expect(agentDependencies.numDependencies).to.equal(0);
        });

        //        it("Should fail when creating an agent without a single component dependency", async function () {
        //            const mechManager = signers[1];
        //            const user = signers[2];
        //            await agentRegistry.changeManager(mechManager.address);
        //            await expect(
        //                agentRegistry.connect(mechManager).create(user.address, user.address, agentHash, description,
        //                dependencies)
        //            ).to.be.revertedWith("Agent must have at least one component dependency");
        //        });
    });

    context("Updating hashes", async function () {
        it("Should fail when the agent does not belong to the owner or IPFS hash is invalid", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const user2 = signers[3];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address, user.address,
                agentHash, description, dependencies);
            await agentRegistry.connect(mechManager).create(user2.address, user2.address,
                agentHash1, description, dependencies);
            await expect(
                agentRegistry.connect(mechManager).updateHash(user2.address, 1, agentHash2)
            ).to.be.revertedWith("AgentNotFound");
            await expect(
                agentRegistry.connect(mechManager).updateHash(user.address, 2, agentHash2)
            ).to.be.revertedWith("AgentNotFound");
            await agentRegistry.connect(mechManager).updateHash(user.address, 1, agentHash2);
        });

        it("Should fail when the updated hash already exists", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const user2 = signers[3];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address, user.address,
                agentHash, description, dependencies);
            await agentRegistry.connect(mechManager).create(user2.address, user2.address,
                agentHash1, description, dependencies);
            await expect(
                agentRegistry.connect(mechManager).updateHash(user.address, 1, agentHash1)
            ).to.be.revertedWith("HashExists");
            await agentRegistry.connect(mechManager).updateHash(user.address, 1, agentHash2);
        });

        it("Should return zeros when getting hashes of non-existent agent", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address, user.address,
                agentHash, description, dependencies);

            const hashes = await agentRegistry.getUpdatedHashes(2);
            expect(hashes.numHashes).to.equal(0);
        });

        it("Update hash, get component hashes", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address, user.address,
                agentHash, description, dependencies);
            await agentRegistry.connect(mechManager).updateHash(user.address, 1, agentHash1);
            await agentRegistry.connect(mechManager).updateHash(user.address, 1, agentHash2);

            const hashes = await agentRegistry.getUpdatedHashes(1);
            expect(hashes.numHashes).to.equal(2);
            expect(hashes.unitHashes[0].hash).to.equal(agentHash1.hash);
            expect(hashes.unitHashes[1].hash).to.equal(agentHash2.hash);
        });
    });
});
