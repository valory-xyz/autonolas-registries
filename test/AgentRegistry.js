/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AgentRegistry", function () {
    let componentRegistry;
    let agentRegistry;
    let signers;
    const componentHash = "0x" + "5".repeat(64);
    const agentHash = "0x" + "9".repeat(64);
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
        await componentRegistry.create(signers[0].address, componentHash, []);
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
            ).to.be.revertedWithCustomError(agentRegistry, "OwnerOnly");
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
                agentRegistry.create(user.address, agentHash, dependencies)
            ).to.be.revertedWithCustomError(agentRegistry, "ManagerOnly");
        });

        it("Should fail when creating an agent with a zero owner address", async function () {
            const mechManager = signers[1];
            await agentRegistry.changeManager(mechManager.address);
            await expect(
                agentRegistry.connect(mechManager).create(AddressZero, agentHash, dependencies)
            ).to.be.revertedWithCustomError(agentRegistry, "ZeroAddress");
        });

        it("Should fail when component number is less or equal to zero", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await expect(
                agentRegistry.connect(mechManager).create(user.address, agentHash, [0])
            ).to.be.revertedWithCustomError(agentRegistry, "ComponentNotFound");
        });

        it("Should fail when creating a non-existent component dependency", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await expect(
                agentRegistry.connect(mechManager).create(user.address, agentHash, [2])
            ).to.be.revertedWithCustomError(agentRegistry, "ComponentNotFound");
        });

        it("Token Id=1 after first successful agent creation must exist ", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const tokenId = 1;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address,
                agentHash, dependencies);
            expect(await agentRegistry.balanceOf(user.address)).to.equal(1);
            expect(await agentRegistry.exists(tokenId)).to.equal(true);
        });

        it("Catching \"Transfer\" event log after successful creation of an agent", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            const agent = await agentRegistry.connect(mechManager).create(user.address, agentHash, dependencies);
            const result = await agent.wait();
            expect(result.events[0].event).to.equal("Transfer");
        });

        it("Getting agent info after its creation", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const tokenId = 1;
            const lastDependencies = [1, 2];
            await componentRegistry.create(user.address, agentHash, []);
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address, agentHash2, lastDependencies);

            expect(await agentRegistry.ownerOf(tokenId)).to.equal(user.address);
            let agentInstance = await agentRegistry.getUnit(tokenId);
            expect(agentInstance.unitHash).to.equal(agentHash2);
            expect(agentInstance.dependencies.length).to.equal(lastDependencies.length);
            for (let i = 0; i < lastDependencies.length; i++) {
                expect(agentInstance.dependencies[i]).to.equal(lastDependencies[i]);
            }

            let agentDependencies = await agentRegistry.getDependencies(tokenId);
            expect(agentDependencies.numDependencies).to.equal(lastDependencies.length);
            for (let i = 0; i < lastDependencies.length; i++) {
                expect(agentDependencies.dependencies[i]).to.equal(lastDependencies[i]);
            }

            // Getting info about non-existent agent Id
            await expect(
                agentRegistry.ownerOf(tokenId + 1)
            ).to.be.revertedWith("NOT_MINTED");
            agentInstance = await agentRegistry.getUnit(tokenId + 1);
            expect(agentInstance.unitHash).to.equal("0x" + "0".repeat(64));
            expect(agentInstance.dependencies.length).to.equal(0);
            agentDependencies = await agentRegistry.getDependencies(tokenId + 1);
            expect(agentDependencies.numDependencies).to.equal(0);
        });

        it("Should fail when creating an agent without a single component dependency", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await expect(
                agentRegistry.connect(mechManager).create(user.address, agentHash, [])
            ).to.be.revertedWithCustomError(agentRegistry, "ZeroValue");
        });
    });

    context("Updating hashes", async function () {
        it("Should fail when the agent does not belong to the owner or IPFS hash is invalid", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const user2 = signers[3];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address,
                agentHash, dependencies);
            await agentRegistry.connect(mechManager).create(user2.address,
                agentHash1, dependencies);
            await expect(
                agentRegistry.connect(mechManager).updateHash(user2.address, 1, agentHash2)
            ).to.be.revertedWithCustomError(agentRegistry, "AgentNotFound");
            await expect(
                agentRegistry.connect(mechManager).updateHash(user.address, 2, agentHash2)
            ).to.be.revertedWithCustomError(agentRegistry, "AgentNotFound");
            await agentRegistry.connect(mechManager).updateHash(user.address, 1, agentHash2);
        });

        it("Should return zeros when getting hashes of non-existent agent", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address, agentHash, dependencies);

            const hashes = await agentRegistry.getUpdatedHashes(2);
            expect(hashes.numHashes).to.equal(0);
        });

        it("Update hash, get component hashes", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(user.address,
                agentHash, dependencies);
            await agentRegistry.connect(mechManager).updateHash(user.address, 1, agentHash1);
            await agentRegistry.connect(mechManager).updateHash(user.address, 1, agentHash2);

            const hashes = await agentRegistry.getUpdatedHashes(1);
            expect(hashes.numHashes).to.equal(2);
            expect(hashes.unitHashes[0]).to.equal(agentHash1);
            expect(hashes.unitHashes[1]).to.equal(agentHash2);
        });
    });

    context("Subcomponents", async function () {
        it("Get the list of subcomponents for each created component dependent on exactly a previous one", async function () {
            const mechManager = signers[0];
            const user = signers[1];
            await componentRegistry.changeManager(mechManager.address);
            await agentRegistry.changeManager(mechManager.address);
            // Maximum number of components
            const numComponents = 20;
            let salt = "0x";
            let hash;
            // For each component, create a new one based on all the previously created components
            // Note that one component already exists (defined in beforeEach())
            for (let i = 1; i < numComponents; i++) {
                salt += "00";
                hash = ethers.utils.keccak256(salt);
                // Create a component based on a previously created component
                await componentRegistry.create(user.address, hash, [i]);
                // Create an agent based on a previously created component
                await agentRegistry.create(user.address, hash, [i + 1]);
                // Check for the obtained subcomponents for a created component
                let regSubComponents = await agentRegistry.getLocalSubComponents(i);
                expect(regSubComponents.numSubComponents).to.equal(i + 1);
                // Check all the subcomponents
                for (let j = 0; j < regSubComponents.numSubComponents; j++) {
                    expect(regSubComponents.subComponentIds[j]).to.equal(j + 1);
                }
            }
        });

        it("Get the list of subcomponents for each two components dependent on a corresponding previous one", async function () {
            const mechManager = signers[0];
            const user = signers[1];
            await componentRegistry.changeManager(mechManager.address);
            await agentRegistry.changeManager(mechManager.address);
            // Maximum number of components
            const numComponents = 50;
            let salt = "0x";
            let hash = ethers.utils.keccak256(salt);
            // Creating one more component without dependencies
            // Note that one component already exists (defined in beforeEach())
            await componentRegistry.create(user.address, hash, []);
            // For each 2 components, create a new one based on all the correspondent previously created components
            // c1 => [c1]; c2 => [c2]; c3 => [c1, c3]; c4 => [c2, c4]; etc
            for (let i = 1; i < numComponents; i += 2) {
                for (let j = 0; j < 2; j++) {
                    salt += "00";
                    hash = ethers.utils.keccak256(salt);
                    // Create a component based on a previously created component
                    await componentRegistry.create(user.address, hash, [i + j]);
                    // Create an agent based on a previously created component
                    await agentRegistry.create(user.address, hash, [i + j]);
                    // Check for the obtained subcomponents for a created component
                    let regSubComponents = await agentRegistry.getLocalSubComponents(i + j);
                    expect(regSubComponents.numSubComponents).to.equal((i + 1) / 2);
                    // Check all the subcomponents
                    for (let k = 0; k < regSubComponents.numSubComponents; k++) {
                        expect(regSubComponents.subComponentIds[k]).to.equal(2 * k + j + 1);
                    }
                }
            }
        });
    });
});
