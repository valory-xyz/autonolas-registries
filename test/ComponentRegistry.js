/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ComponentRegistry", function () {
    let componentRegistry;
    let reentrancyAttacker;
    let signers;
    const componentHash = "0x" + "5".repeat(64);
    const componentHash1 = "0x" + "a".repeat(64);
    const componentHash2 = "0x" + "2".repeat(64);
    const dependencies = [];
    const AddressZero = "0x" + "0".repeat(40);

    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const ReentrancyAttacker = await ethers.getContractFactory("ReentrancyAttacker");
        reentrancyAttacker = await ReentrancyAttacker.deploy(componentRegistry.address, AddressZero);
        await reentrancyAttacker.deployed();

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
            ).to.be.revertedWithCustomError(componentRegistry, "OwnerOnly");
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
                componentRegistry.create(user.address, componentHash, dependencies)
            ).to.be.revertedWithCustomError(componentRegistry, "ManagerOnly");
        });

        it("Should fail when creating a component with a zero owner address", async function () {
            const mechManager = signers[1];
            await componentRegistry.changeManager(mechManager.address);
            await expect(
                componentRegistry.connect(mechManager).create(AddressZero, componentHash, dependencies)
            ).to.be.revertedWithCustomError(componentRegistry, "ZeroAddress");
        });

        it("Should fail when creating a component with an empty hash", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, "0x" + "0".repeat(64),
                    dependencies)
            ).to.be.revertedWithCustomError(componentRegistry, "ZeroValue");
        });

        it("Should fail when creating a non-existent component dependency", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, componentHash, [0])
            ).to.be.revertedWithCustomError(componentRegistry, "ComponentNotFound");
            await expect(
                componentRegistry.connect(mechManager).create(user.address, componentHash, [1])
            ).to.be.revertedWithCustomError(componentRegistry, "ComponentNotFound");
        });

        it("Create a components with duplicate dependencies in the list of dependencies", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, componentHash, []);
            await componentRegistry.connect(mechManager).create(user.address, componentHash1, [1]);
            await expect(
                componentRegistry.connect(mechManager).create(user.address, componentHash2, [1, 1, 1])
            ).to.be.revertedWithCustomError(componentRegistry, "ComponentNotFound");
            await expect(
                componentRegistry.connect(mechManager).create(user.address, componentHash2, [2, 1, 2, 1, 1, 1, 2])
            ).to.be.revertedWithCustomError(componentRegistry, "ComponentNotFound");
        });

        it("Token Id=1 after first successful component creation must exist", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const tokenId = 1;
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, componentHash, dependencies);
            expect(await componentRegistry.balanceOf(user.address)).to.equal(1);
            expect(await componentRegistry.exists(tokenId)).to.equal(true);
        });

        it("Catching \"Transfer\" event log after successful creation of a component", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            const component = await componentRegistry.connect(mechManager).create(user.address,
                componentHash, dependencies);
            const result = await component.wait();
            expect(result.events[0].event).to.equal("Transfer");
        });

        it("Getting component info after its creation", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const tokenId = 3;
            const lastDependencies = [1, 2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, componentHash, dependencies);
            await componentRegistry.connect(mechManager).create(user.address, componentHash1, dependencies);
            await componentRegistry.connect(mechManager).create(user.address, componentHash2, lastDependencies);

            expect(await componentRegistry.ownerOf(tokenId)).to.equal(user.address);
            let compInstance = await componentRegistry.getUnit(tokenId);
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
            expect(compInstance.unitHash).to.equal("0x" + "0".repeat(64));
            expect(compInstance.dependencies.length).to.equal(0);
            componentDependencies = await componentRegistry.getDependencies(tokenId + 1);
            expect(componentDependencies.numDependencies).to.equal(0);

            // Check the token URI
            const baseURI = "https://localhost/ipfs/";
            const cidPrefix = "f01701220";
            await componentRegistry.setBaseURI(baseURI);
            expect(await componentRegistry.tokenURI(1)).to.equal(baseURI + cidPrefix + "5".repeat(64));
            expect(await componentRegistry.tokenURI(2)).to.equal(baseURI + cidPrefix + "a".repeat(64));
            expect(await componentRegistry.tokenURI(3)).to.equal(baseURI + cidPrefix + "2".repeat(64));

            const etherscanHash1 = "0xb78ce02d6ccebb1bfd206da0f79e91ff39981592d4a36e8d2900ad46017cae35";
            await componentRegistry.connect(mechManager).create(user.address, etherscanHash1, dependencies);
            expect(await componentRegistry.tokenURI(4)).to.equal(baseURI + cidPrefix + "b78ce02d6ccebb1bfd206da0f79e91ff39981592d4a36e8d2900ad46017cae35");

            const etherscanHash2 = "0xaa501c4339842b489298e8548b1a5595bddb41ad7710a307c56fdc3947646ced";
            await componentRegistry.connect(mechManager).create(user.address, etherscanHash2, dependencies);
            expect(await componentRegistry.tokenURI(5)).to.equal(baseURI + cidPrefix + "aa501c4339842b489298e8548b1a5595bddb41ad7710a307c56fdc3947646ced");

            const etherscanHash3 = "0x10f31eb1b13df79ccccee77d7ed36d312474681dd99f8932adabe3aaaff74885";
            await componentRegistry.connect(mechManager).create(user.address, etherscanHash3, dependencies);
            expect(await componentRegistry.tokenURI(6)).to.equal(baseURI + cidPrefix + "10f31eb1b13df79ccccee77d7ed36d312474681dd99f8932adabe3aaaff74885");

            const extremeHash1 = "0x" + "0".repeat(63) + "1";
            await componentRegistry.connect(mechManager).create(user.address, extremeHash1, dependencies);
            expect(await componentRegistry.tokenURI(7)).to.equal(baseURI + cidPrefix + "0".repeat(63) + "1");

            const extremeHash2 = "0x" + "f".repeat(64);
            await componentRegistry.connect(mechManager).create(user.address, extremeHash2, dependencies);
            expect(await componentRegistry.tokenURI(8)).to.equal(baseURI + cidPrefix + "f".repeat(64));

            // Compare several hashes with the test contract
            const ComponentRegistryTest = await ethers.getContractFactory("ComponentRegistryTest");
            const componentRegistryTest = await ComponentRegistryTest.deploy("Components Test", "MECHCOMPTEST",
                "https://localhost/test/");
            await componentRegistryTest.deployed();
            await componentRegistryTest.changeManager(mechManager.address);
            await componentRegistryTest.connect(mechManager).create(user.address, componentHash, dependencies);
            await componentRegistryTest.checkTokenURI(1);
            await componentRegistryTest.connect(mechManager).create(user.address, componentHash1, dependencies);
            await componentRegistryTest.checkTokenURI(2);
            await componentRegistryTest.connect(mechManager).create(user.address, componentHash2, lastDependencies);
            await componentRegistryTest.checkTokenURI(3);
        });
    });

    context("Updating hashes", async function () {
        it("Should fail when the component does not belong to the owner or IPFS hash is invalid", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            const user2 = signers[3];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, componentHash, dependencies);
            await componentRegistry.connect(mechManager).create(user2.address, componentHash1, dependencies);
            await expect(
                componentRegistry.connect(mechManager).updateHash(user2.address, 1, componentHash2)
            ).to.be.revertedWithCustomError(componentRegistry, "ComponentNotFound");
            await expect(
                componentRegistry.connect(mechManager).updateHash(user.address, 2, componentHash2)
            ).to.be.revertedWithCustomError(componentRegistry, "ComponentNotFound");
            await componentRegistry.connect(mechManager).updateHash(user.address, 1, componentHash2);
        });

        it("Should return zeros when getting hashes of non-existent component", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, componentHash, dependencies);

            const hashes = await componentRegistry.getUpdatedHashes(2);
            expect(hashes.numHashes).to.equal(0);
        });

        it("Update hash, get new component hashes", async function () {
            const mechManager = signers[1];
            const user = signers[2];
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(user.address, componentHash, dependencies);

            // Try to update hash not via a manager
            await expect(
                componentRegistry.connect(user).updateHash(user.address, 1, componentHash1)
            ).to.be.revertedWithCustomError(componentRegistry, "ManagerOnly");

            // Try to update to a zero value hash
            await expect(
                componentRegistry.connect(mechManager).updateHash(user.address, 1, "0x" + "0".repeat(64))
            ).to.be.revertedWithCustomError(componentRegistry, "ZeroValue");

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
            await componentRegistry.create(user.address, hash, []);
            let subComponents = await componentRegistry.getLocalSubComponents(1);
            expect(subComponents.numSubComponents).to.equal(1);
            // c2
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(user.address, hash, []);
            subComponents = await componentRegistry.getLocalSubComponents(2);
            expect(subComponents.numSubComponents).to.equal(1);
            // c3
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(user.address, hash, [1]);
            subComponents = await componentRegistry.getLocalSubComponents(3);
            expect(subComponents.numSubComponents).to.equal(2);
            // c4
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(user.address, hash, [2]);
            subComponents = await componentRegistry.getLocalSubComponents(4);
            expect(subComponents.numSubComponents).to.equal(2);
            // c5
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(user.address, hash, [3, 4]);
            subComponents = await componentRegistry.getLocalSubComponents(5);
            expect(subComponents.numSubComponents).to.equal(5);
            for (let i = 0; i < subComponents.numSubComponents; i++) {
                expect(subComponents.subComponentIds[i]).to.equal(i + 1);
            }
        });

        it("Get the list of subcomponents for each created component dependent on previous ones", async function () {
            const mechManager = signers[0];
            const user = signers[1];
            await componentRegistry.changeManager(mechManager.address);
            // Maximum number of components
            const numComponents = 20;
            let salt = "0x";
            let hash;
            // For each component, create a new one based on all the previously created components
            for (let i = 0; i < numComponents; i++) {
                salt += "00";
                hash = ethers.utils.keccak256(salt);
                // Get the array of consecutive integers from 1 to i
                let origSubComponents = Array.from({length: i}, (_, j) => j + 1);
                await componentRegistry.create(user.address, hash, origSubComponents);
                // Check for the obtained subcomponents for a created component
                let regSubComponents = await componentRegistry.getLocalSubComponents(i + 1);
                expect(regSubComponents.numSubComponents).to.equal(i + 1);
                // Check all the first subcomponents until the very last one (self)
                for (let j = 0; j < regSubComponents.numSubComponents - 1; j++) {
                    expect(regSubComponents.subComponentIds[j]).to.equal(origSubComponents[j]);
                }
                // Check the last subcomponent
                expect(regSubComponents.subComponentIds[regSubComponents.numSubComponents - 1]).to.equal(regSubComponents.numSubComponents);
            }
        });

        it("Get the list of subcomponents for each component dependent on exactly a previous one", async function () {
            const mechManager = signers[0];
            const user = signers[1];
            await componentRegistry.changeManager(mechManager.address);
            // Maximum number of components
            const numComponents = 50;
            let salt = "0x";
            let hash = ethers.utils.keccak256(salt);
            // Create a first component
            await componentRegistry.create(user.address, hash, []);
            // For each component, create a new one based on all the previously created components
            for (let i = 1; i < numComponents; i++) {
                salt += "00";
                hash = ethers.utils.keccak256(salt);
                // Create a component based on the previous one
                await componentRegistry.create(user.address, hash, [i]);
                // Check for the obtained subcomponents for a created component
                let regSubComponents = await componentRegistry.getLocalSubComponents(i + 1);
                expect(regSubComponents.numSubComponents).to.equal(i + 1);
                // Check all the subcomponents
                for (let j = 0; j < regSubComponents.numSubComponents; j++) {
                    expect(regSubComponents.subComponentIds[j]).to.equal(j + 1);
                }
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
            await componentRegistry.connect(mechManager).create(user1.address, componentHash, dependencies);

            // Transfer a component to user2
            await componentRegistry.connect(user1).transferFrom(user1.address, user2.address, 1);

            // Checking the new owner
            expect(await componentRegistry.ownerOf(1)).to.equal(user2.address);
        });
    });

    context("Reentrancy attack", async function () {
        it("Reentrancy attack by the manager during the service creation", async function () {
            // Change the manager to the attacker contract address
            await componentRegistry.changeManager(reentrancyAttacker.address);

            // Simulate the reentrancy attack
            await reentrancyAttacker.setAttackOnCreate(true);
            await expect(
                reentrancyAttacker.createBadComponent(reentrancyAttacker.address, componentHash, [])
            ).to.be.revertedWithCustomError(componentRegistry, "ReentrancyGuard");
        });
    });

    context("Contract transfers", async function () {
        it("Should fail when sending funds directly to the contract", async function () {
            await expect(
                signers[0].sendTransaction({to: componentRegistry.address, value: ethers.utils.parseEther("1000"), data: "0x12"})
            ).to.be.reverted;
        });
    });
});
