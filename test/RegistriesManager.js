/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RegistriesManager", function () {
    let componentRegistry;
    let agentRegistry;
    let registriesManager;
    let signers;
    const description = ethers.utils.formatBytes32String("unit description");
    const componentHashes = ["0x" + "0".repeat(64), "0x" + "1".repeat(64), "0x" + "2".repeat(64)];
    const agentHashes = ["0x" + "5".repeat(64), "0x" + "6".repeat(64), "0x" + "7".repeat(64)];
    const dependencies = [];
    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
            componentRegistry.address);
        await agentRegistry.deployed();

        const RegistriesManager = await ethers.getContractFactory("RegistriesManager");
        registriesManager = await RegistriesManager.deploy(componentRegistry.address, agentRegistry.address);
        await registriesManager.deployed();

        signers = await ethers.getSigners();
    });

    context("Initialization", async function () {
        it("Checking for arguments passed to the constructor", async function () {
            expect(await registriesManager.componentRegistry()).to.equal(componentRegistry.address);
            expect(await registriesManager.agentRegistry()).to.equal(agentRegistry.address);
        });

        it("Pausing and unpausing", async function () {
            const user = signers[3];

            // Try to pause not from the owner of the service manager
            await expect(
                serviceManager.connect(user).pause()
            ).to.be.revertedWith("OwnerOnly");

            // Pause the contract
            await registriesManager.pause();

            // Try minting when paused
            // 0 is component, 1 is agent
            await expect(
                registriesManager.create(0, user.address, description, componentHashes[0], dependencies)
            ).to.be.revertedWith("Paused");

            await expect(
                registriesManager.create(1, user.address, description, componentHashes[0], dependencies)
            ).to.be.revertedWith("Paused");

            // Try to unpause not from the owner of the service manager
            await expect(
                serviceManager.connect(user).unpause()
            ).to.be.revertedWith("OwnerOnly");

            // Unpause the contract
            await registriesManager.unpause();

            // Mint component and agent
            await componentRegistry.changeManager(registriesManager.address);
            await agentRegistry.changeManager(registriesManager.address);
            // 0 is component, 1 is agent
            await registriesManager.create(0, user.address, description, componentHashes[0], dependencies);
            await registriesManager.create(1, user.address, description, componentHashes[1], [1]);
        });
    });

    context("Updating hashes", async function () {
        it("Update hash, get component hashes", async function () {
            const user = signers[1];
            await componentRegistry.changeManager(registriesManager.address);
            await agentRegistry.changeManager(registriesManager.address);
            // 0 is component, 1 is agent
            await registriesManager.create(0, user.address, description, componentHashes[0],
                dependencies);
            await registriesManager.connect(user).updateHash(0, 1, componentHashes[1]);
            await registriesManager.connect(user).updateHash(0, 1, componentHashes[2]);

            // 0 is component, 1 is agent
            await registriesManager.create(1, user.address, agentHashes[0], description, [1]);
            await registriesManager.connect(user).updateHash(1, 1, agentHashes[1]);
            await registriesManager.connect(user).updateHash(1, 1, agentHashes[2]);

            const cHashes = await componentRegistry.getUpdatedHashes(1);
            expect(cHashes.numHashes).to.equal(2);
            expect(cHashes.unitHashes[0].hash).to.equal(componentHashes[1].hash);
            expect(cHashes.unitHashes[1].hash).to.equal(componentHashes[2].hash);

            const aHashes = await agentRegistry.getUpdatedHashes(1);
            expect(aHashes.numHashes).to.equal(2);
            expect(aHashes.unitHashes[0].hash).to.equal(agentHashes[1].hash);
            expect(aHashes.unitHashes[1].hash).to.equal(agentHashes[2].hash);
        });
    });
});
