/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ComponentRegistry", function () {
    let componentRegistry;
    let signers;
    const description = ethers.utils.formatBytes32String("component description");
    const componentHash = "0x" + "9".repeat(64);
    const componentHash1 = "0x" + "1".repeat(64);
    const componentHash2 = "0x" + "2".repeat(64);
    const dependencies = [];
    const AddressZero = "0x" + "0".repeat(40);

    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();
        signers = await ethers.getSigners();
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            expect(await componentRegistry.name()).to.equal("agent components");
            expect(await componentRegistry.symbol()).to.equal("MECHCOMP");
            expect(await componentRegistry.baseURI()).to.equal("https://localhost/component/");
        });

        it("Should fail when checking for the token id existence", async function () {
            const tokenId = 0;
            expect(await componentRegistry.exists(tokenId)).to.equal(false);
        });

        it("Should fail when trying to change the mechManager from a different address", async function () {
            await expect(
                componentRegistry.connect(signers[1]).changeManager(signers[1].address)
            ).to.be.revertedWith("OwnerOnly");
        });

        it("Setting the base URI", async function () {
            await componentRegistry.setBaseURI("https://localhost2/component/");
            expect(await componentRegistry.baseURI()).to.equal("https://localhost2/component/");
        });
    });

    context("Component creation", async function () {
        it("Should fail when creating a component without a mechManager", async function () {
            const user = signers[2];
            await expect(
                componentRegistry.create(user.address, description, componentHash, dependencies)
            ).to.be.revertedWith("ManagerOnly");
        });

        it("Should fail when creating a component with a zero owner address", async function () {
            const mechManager = signers[1];
            await componentRegistry.changeManager(mechManager.address);
            await expect(
                componentRegistry.connect(mechManager).create(AddressZero, description, componentHash, dependencies)
            ).to.be.revertedWith("ZeroAddress");
        });

        it("Should fail when creating a component with an empty description", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, "0x" + "0".repeat(64), componentHash,
                    dependencies)
            ).to.be.revertedWith("ZeroValue");
        });

        it("Should fail when creating a component with an empty hash", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, description, "0x" + "0".repeat(64),
                    dependencies)
            ).to.be.revertedWith("ZeroValue");
        });

        it("Should fail when creating a second component with the same hash", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, description, componentHash, dependencies);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, description, componentHash, dependencies)
            ).to.be.revertedWith("HashExists");
        });

        it("Should fail when creating a non-existent component dependency", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, description, componentHash, [0])
            ).to.be.revertedWith("ComponentNotFound");
            await expect(
                componentRegistry.connect(mechManager).create(user.address, description, componentHash, [1])
            ).to.be.revertedWith("ComponentNotFound");
        });

        it("Create a components with duplicate dependencies in the list of dependencies", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, description, componentHash, []);
            await componentRegistry.connect(mechManager).create(user.address, description, componentHash1, [1]);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, description, componentHash2, [1, 1, 1])
            ).to.be.revertedWith("ComponentNotFound");
            await expect(
                componentRegistry.connect(mechManager).create(user.address, description, componentHash2, [2, 1, 2, 1, 1, 1, 2])
            ).to.be.revertedWith("ComponentNotFound");
        });

        it("Token Id=1 after first successful component creation must exist", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const tokenId = 1;
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, description, componentHash, dependencies);
            expect(await componentRegistry.balanceOf(user.address)).to.equal(1);
            expect(await componentRegistry.exists(tokenId)).to.equal(true);
        });

        it("Catching \"Transfer\" event log after successful creation of a component", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            const component = await componentRegistry.connect(mechManager).create(user.address,
                description, componentHash, dependencies);
            const result = await component.wait();
            expect(result.events[0].event).to.equal("Transfer");
        });

        it("Getting component info after its creation", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const tokenId = 3;
            const lastDependencies = [1, 2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, description, componentHash, dependencies);
            await componentRegistry.connect(mechManager).create(user.address, description, componentHash1, dependencies);
            const description2 = ethers.utils.id("component description2");
            await componentRegistry.connect(mechManager).create(user.address, description2, componentHash2, lastDependencies);

            expect(await componentRegistry.ownerOf(tokenId)).to.equal(user.address);
            let compInstance = await componentRegistry.getUnit(tokenId);
            expect(compInstance.description).to.equal(description2);
            expect(compInstance.unitHash).to.equal(componentHash2);
            expect(compInstance.dependencies.length).to.equal(lastDependencies.length);
            for (let i = 0; i < lastDependencies.length; i++) {
                expect(compInstance.dependencies[i]).to.equal(lastDependencies[i]);
            }

            let componentDependencies = await componentRegistry.getDependencies(tokenId);
            expect(componentDependencies.numDependencies).to.equal(lastDependencies.length);
            for (let i = 0; i < lastDependencies.length; i++) {
                expect(componentDependencies.dependencies[i]).to.equal(lastDependencies[i]);
            }

            // Getting info about non-existent agent Id
            await expect(
                componentRegistry.ownerOf(tokenId + 1)
            ).to.be.revertedWith("NOT_MINTED");
            compInstance = await componentRegistry.getUnit(tokenId + 1);
            expect(compInstance.description).to.equal("0x" + "0".repeat(64));
            expect(compInstance.unitHash).to.equal("0x" + "0".repeat(64));
            expect(compInstance.dependencies.length).to.equal(0);
            componentDependencies = await componentRegistry.getDependencies(tokenId + 1);
            expect(componentDependencies.numDependencies).to.equal(0);
        });
    });

    context("Updating hashes", async function () {
        it("Should fail when the component does not belong to the owner or IPFS hash is invalid", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const user2 = signers[3];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, description, componentHash, dependencies);
            await componentRegistry.connect(mechManager).create(user2.address, description, componentHash1, dependencies);
            await expect(
                componentRegistry.connect(mechManager).updateHash(user2.address, 1, componentHash2)
            ).to.be.revertedWith("ComponentNotFound");
            await expect(
                componentRegistry.connect(mechManager).updateHash(user.address, 2, componentHash2)
            ).to.be.revertedWith("ComponentNotFound");
            await componentRegistry.connect(mechManager).updateHash(user.address, 1, componentHash2);
        });

        it("Should fail when the updated hash already exists", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const user2 = signers[3];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address,
                description, componentHash, dependencies);
            await componentRegistry.connect(mechManager).create(user2.address, description, componentHash1, dependencies);
            await expect(
                componentRegistry.connect(mechManager).updateHash(user.address, 1, componentHash1)
            ).to.be.revertedWith("HashExists");
            await componentRegistry.connect(mechManager).updateHash(user.address, 1, componentHash2);
        });

        it("Should return zeros when getting hashes of non-existent component", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, description, componentHash, dependencies);

            const hashes = await componentRegistry.getUpdatedHashes(2);
            expect(hashes.numHashes).to.equal(0);
        });

        it("Update hash, get new component hashes", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, description, componentHash, dependencies);

            // Try to update hash not via a manager
            await expect(
                componentRegistry.connect(user).updateHash(user.address, 1, componentHash1)
            ).to.be.revertedWith("ManagerOnly");

            // Try to update to a zero value hash
            await expect(
                componentRegistry.connect(mechManager).updateHash(user.address, 1, "0x" + "0".repeat(64))
            ).to.be.revertedWith("ZeroValue");

            // Proceed with hash updates
            await componentRegistry.connect(mechManager).updateHash(user.address, 1, componentHash1);
            await componentRegistry.connect(mechManager).updateHash(user.address, 1, componentHash2);

            const hashes = await componentRegistry.getUpdatedHashes(1);
            expect(hashes.numHashes).to.equal(2);
            expect(hashes.unitHashes[0]).to.equal(componentHash1);
            expect(hashes.unitHashes[1]).to.equal(componentHash2);
        });
    });

    context("Subcomponents", async function () {
        it("Get the list of subcomponents", async function () {
            const mechManager = signers[0];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            let salt = "0x";
            // Component 1 (c1)
            salt += "00";
            let hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(user.address, description, hash, []);
            let subComponents = await componentRegistry.getLocalSubComponents(1);
            expect(subComponents.numSubComponents).to.equal(1);
            // c2
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(user.address, description, hash, []);
            subComponents = await componentRegistry.getLocalSubComponents(2);
            expect(subComponents.numSubComponents).to.equal(1);
            // c3
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(user.address, description, hash, [1]);
            subComponents = await componentRegistry.getLocalSubComponents(3);
            expect(subComponents.numSubComponents).to.equal(2);
            // c4
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(user.address, description, hash, [2]);
            subComponents = await componentRegistry.getLocalSubComponents(4);
            expect(subComponents.numSubComponents).to.equal(2);
            // c5
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(user.address, description, hash, [3, 4]);
            subComponents = await componentRegistry.getLocalSubComponents(5);
            expect(subComponents.numSubComponents).to.equal(5);
            for (let i = 0; i < subComponents.numSubComponents; i++) {
                expect(subComponents.subComponentIds[i]).to.equal(i + 1);
            }
        });
    });

    context("ERC721 transfer", async function () {
        it("Transfer of a component", async function () {
            const mechManager = signers[0];
            const user1 = signers[1];
            const user2 = signers[2];
            await componentRegistry.changeManager(mechManager.address);

            // Create a component with user1 being its owner
            await componentRegistry.connect(mechManager).create(user1.address, description, componentHash, dependencies);

            // Transfer a component to user2
            await componentRegistry.connect(user1).transferFrom(user1.address, user2.address, 1);

            // Checking the new owner
            expect(await componentRegistry.ownerOf(1)).to.equal(user2.address);
        });
    });
});
