/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ServiceRegistry", function () {
    let componentRegistry;
    let agentRegistry;
    let serviceRegistry;
    let gnosisSafeMultisig;
    let signers;

    let reentrancyAttack;

    const description = ethers.utils.formatBytes32String("unit description");
    const configHash = "0x" + "5".repeat(64);
    const configHash1 = "0x" + "6".repeat(64);
    const regBond = 1000;
    const regDeposit = 1000;
    const regFine = 500;
    const agentIds = [1, 2];
    const agentParams = [[3, regBond], [4, regBond]];
    const serviceId = 1;
    const agentId = 1;
    const threshold = 1;
    const maxThreshold = agentParams[0][0] + agentParams[1][0];
    const ZeroBytes32 = "0x" + "0".repeat(64);
    const componentHash = "0x" + "0".repeat(64);
    const componentHash1 = "0x" + "1".repeat(64);
    const componentHash2 = "0x" + "2".repeat(64);
    const agentHash = "0x" + "7".repeat(64);
    const agentHash1 = "0x" + "8".repeat(64);
    const agentHash2 = "0x" + "9".repeat(64);
    const AddressZero = "0x" + "0".repeat(40);
    const payload = "0x";
    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
            componentRegistry.address);
        await agentRegistry.deployed();

        const GnosisSafeL2 = await ethers.getContractFactory("GnosisSafeL2");
        const gnosisSafeL2 = await GnosisSafeL2.deploy();
        await gnosisSafeL2.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        const gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy("service registry", "SERVICE", agentRegistry.address);
        await serviceRegistry.deployed();

        const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
        gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafeL2.address, gnosisSafeProxyFactory.address);
        await gnosisSafeMultisig.deployed();

        const ReentrancyAttack = await ethers.getContractFactory("ReentrancyAttacker");
        reentrancyAttack = await ReentrancyAttack.deploy(serviceRegistry.address); 

        signers = await ethers.getSigners();

        await componentRegistry.changeManager(signers[0].address);
        await componentRegistry.create(signers[0].address, description, componentHash2, []);
    });

    context("Initialization", async function () {
        it("Should fail when checking for the service id existence", async function () {
            const tokenId = 0;
            expect(await serviceRegistry.exists(tokenId)).to.equal(false);
        });

        it("Should fail when trying to change the serviceManager from a different address", async function () {
            await expect(
                serviceRegistry.connect(signers[3]).changeManager(signers[3].address)
            ).to.be.revertedWith("OwnerOnly");
        });

        it("Setting the base URI", async function () {
            await agentRegistry.setBaseURI("https://localhost2/service/");
            expect(await agentRegistry.baseURI()).to.equal("https://localhost2/service/");
        });
    });

    context("Service creation", async function () {
        it("Should fail when creating a service without a serviceManager", async function () {
            const owner = signers[3].address;
            await expect(
                serviceRegistry.create(owner, description, configHash, agentIds, agentParams, threshold)
            ).to.be.revertedWith("ManagerOnly");
        });

        it("Should fail when the owner of a service has zero address", async function () {
            const serviceManager = signers[3];
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).create(AddressZero, description, configHash, agentIds,
                    agentParams, threshold)
            ).to.be.revertedWith("ZeroAddress");
        });

        it("Should fail when creating a service with an empty description", async function () {
            const serviceManager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).create(owner, ZeroBytes32, configHash, agentIds, agentParams,
                    threshold)
            ).to.be.revertedWith("ZeroValue");
        });

        it("Should fail when creating a service with incorrect agent slots values", async function () {
            const serviceManager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).create(owner, description, configHash, [], [], threshold)
            ).to.be.revertedWith("WrongArrayLength");
            await expect(
                serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1], [], threshold)
            ).to.be.revertedWith("WrongArrayLength");
            await expect(
                serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1, 3], [[2, regBond]],
                    threshold)
            ).to.be.revertedWith("WrongArrayLength");
        });

        it("Should fail when creating a service with non existent canonical agent", async function () {
            const serviceManager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                    agentParams, threshold)
            ).to.be.revertedWith("WrongAgentId");
        });

        it("Should fail when creating a service with duplicate canonical agents in agent slots", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1, 1],
                    [[2, regBond], [2, regBond]], threshold)
            ).to.be.revertedWith("WrongAgentId");
        });

        it("Should fail when creating a service with incorrect input parameter", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1, 0],
                    [[2, regBond], [2, regBond]], threshold)
            ).to.be.revertedWith("WrongAgentId");
        });

        it("Should fail when trying to set empty agent slots", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                    [[3, regBond], [0, regBond]], threshold)
            ).to.be.revertedWith("ZeroValue");
        });

        it("Checking for different signers threshold combinations", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const minThreshold = Math.floor(maxThreshold * 2 / 3 + 1);
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                    agentParams, minThreshold - 1)
            ).to.be.revertedWith("WrongThreshold");
            await expect(
                serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                    agentParams, maxThreshold + 1)
            ).to.be.revertedWith("WrongThreshold");
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, minThreshold);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
        });

        it("Catching \"CreateService\" event log after registration of a service", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            const service = await serviceRegistry.connect(serviceManager).create(owner, description, configHash,
                agentIds, agentParams, maxThreshold);
            const result = await service.wait();
            expect(result.events[1].event).to.equal("CreateService");
        });

        it.only("Catching Reentrancy attack to create a service", async function () {
            const mechManager = signers[3];
            // const serviceManager = signers[4];
            let owner = signers[5].address;
            // const owner = reentrancyAttack.address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            // await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.changeManager(reentrancyAttack.address);
            owner = reentrancyAttack.address;
            const service = await reentrancyAttack.create(owner, description, configHash,
                agentIds, agentParams, maxThreshold);
            const result = await service.wait();
            console.log("js result", result.status);
            //expect(result.events[1].event).to.equal("CreateService");
        });

        it("Service Id=1 after first successful service registration must exist", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            expect(await serviceRegistry.exists(1)).to.equal(true);
        });



    });

    context("Service update", async function () {
        it("Should fail when creating a service without a serviceManager", async function () {
            const owner = signers[3].address;
            await expect(
                serviceRegistry.create(owner, description, configHash, agentIds, agentParams, threshold)
            ).to.be.revertedWith("ManagerOnly");
        });

        it("Should fail when the owner of a service has zero address", async function () {
            const serviceManager = signers[3];
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).update(AddressZero, description, configHash, agentIds,
                    agentParams, threshold, 0)
            ).to.be.revertedWith("ServiceNotFound");
        });

        it("Should fail when trying to update a non-existent service", async function () {
            const serviceManager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).update(owner, description, configHash, agentIds,
                    agentParams, threshold, 0)
            ).to.be.revertedWith("ServiceNotFound");
        });

        it("Catching \"UpdateService\" event log after update of a service", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            const service = await serviceRegistry.connect(serviceManager).update(owner, description, configHash,
                agentIds, agentParams, maxThreshold, 1);
            const result = await service.wait();
            expect(result.events[0].event).to.equal("UpdateService");
            expect(await serviceRegistry.exists(1)).to.equal(true);
            expect(await serviceRegistry.exists(2)).to.equal(false);
        });

        it("Should fail when trying to update the service with already active registration", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});
            await expect(
                serviceRegistry.connect(serviceManager).update(owner, description, configHash, agentIds,
                    agentParams, maxThreshold, 1)
            ).to.be.revertedWith("WrongServiceState");
        });

        it("Update specifically for hashes, then get service hashes", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);

            // If we update with the same config hash as previous one, it must not be added
            await serviceRegistry.connect(serviceManager).update(owner, description, configHash, agentIds,
                agentParams, maxThreshold, 1);
            let hashes = await serviceRegistry.getPreviousHashes(serviceId);
            expect(hashes.numHashes).to.equal(0);

            // Now we are going to have two config hashes
            await serviceRegistry.connect(serviceManager).update(owner, description, configHash1, agentIds,
                agentParams, maxThreshold, 1);
            hashes = await serviceRegistry.getPreviousHashes(serviceId);
            expect(hashes.numHashes).to.equal(1);
            expect(hashes.configHashes[0].hash).to.equal(configHash.hash);
        });
    });

    context("Register agent instance", async function () {
        it("Should fail when registering an agent instance without a serviceManager", async function () {
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            await expect(
                serviceRegistry.registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond})
            ).to.be.revertedWith("ManagerOnly");
        });

        it("Should fail when registering an agent instance with a non-existent service", async function () {
            const serviceManager = signers[4];
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond})
            ).to.be.revertedWith("WrongServiceState");
        });

        it("Should fail when registering an agent instance for the inactive service", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;

            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            await expect(
                serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond})
            ).to.be.revertedWith("WrongServiceState");
        });

        it("Should fail when registering an agent instance that is already registered", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});
            await expect(
                serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond})
            ).to.be.revertedWith("AgentInstanceRegistered");
        });

        it("Should fail when registering an agent instance for non existent canonical agent Id", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await expect(
                serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [0])
            ).to.be.revertedWith("AgentNotInService");
        });

        it("Should fail when registering an agent instance for the service with no available slots", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstances = [signers[7].address, signers[8].address, signers[9].address, signers[10].address];
            const regAgentIds = [agentId, agentId, agentId, agentId];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await expect(
                serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, agentInstances, regAgentIds, {value: 4*regBond})
            ).to.be.revertedWith("AgentInstancesSlotsFilled");
        });

        it("Catching \"RegisterInstance\" event log after agent instance registration", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            const regAgent = await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId,
                [agentInstance], [agentId], {value: regBond});
            const result = await regAgent.wait();
            expect(result.events[0].event).to.equal("RegisterInstance");
        });

        it("Registering several agent instances in different services by the same operator", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = [signers[7].address, signers[8].address, signers[9].address];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId + 1, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance[0]],
                [agentId], {value: regBond});
            const regAgent = await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId + 1,
                [agentInstance[1], agentInstance[2]], [agentId, agentId], {value: 2*regBond});
            const result = await regAgent.wait();
            expect(result.events[0].event).to.equal("RegisterInstance");
        });

        it("Should fail when registering an agent instance with the same address as operator", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstances = [signers[7].address, signers[8].address];
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await expect(
                serviceRegistry.connect(serviceManager).registerAgents(agentInstances[0], serviceId, [agentInstances[0]],
                    [agentId], {value: regBond})
            ).to.be.revertedWith("WrongOperator");
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstances[0]],
                [agentId], {value: regBond});
            await expect(
                serviceRegistry.connect(serviceManager).registerAgents(agentInstances[0], serviceId, [agentInstances[1]],
                    [agentId], {value: regBond})
            ).to.be.revertedWith("WrongOperator");
        });
    });

    context("activateRegistration / termination of the service", async function () {
        it("Should fail when activating a non-existent service", async function () {
            const owner = signers[3].address;
            await expect(
                serviceRegistry.activateRegistration(owner, serviceId, {value: regDeposit})
            ).to.be.revertedWith("ServiceNotFound");
        });

        it("Should fail when activating a non-existent service", async function () {
            const serviceManager = signers[3];
            const owner = signers[4].address;
            await serviceRegistry.changeManager(serviceManager.address);
            await expect(
                serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId + 1, {value: regDeposit})
            ).to.be.revertedWith("ServiceNotFound");
        });

        it("Should fail when activating a service that is already active", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await expect(
                serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit})
            ).to.be.revertedWith("ServiceMustBeInactive");
        });

        it("Catching \"ActivateRegistration\" event log after service activation", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;

            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            const activateService = await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId,
                {value: regDeposit});
            const result = await activateService.wait();
            expect(result.events[0].event).to.equal("ActivateRegistration");
        });

        it("Catching \"TerminateService\" event log after service termination", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            const terminateService = await serviceRegistry.connect(serviceManager).terminate(owner, serviceId);
            const result = await terminateService.wait();
            expect(result.events[0].event).to.equal("Refund");
            expect(result.events[1].event).to.equal("TerminateService");
        });

        it("Destroying a service with at least one agent instance", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;

            // Create agents and a service
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);

            // Activate registration and register and agent instance
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});

            // Terminate the service, unbond
            const terminateService = await serviceRegistry.connect(serviceManager).terminate(owner, serviceId);
            let result = await terminateService.wait();
            expect(result.events[0].event).to.equal("Refund");
            expect(result.events[1].event).to.equal("TerminateService");
            await serviceRegistry.connect(serviceManager).unbond(operator, serviceId);

            // The service state must be terminated-unbonded
            const state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(1);
        });
    });

    context("Safe contract from agent instances", async function () {
        it("Should fail when creating a Safe without a full set of registered agent instances", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});
            await expect(
                serviceRegistry.connect(serviceManager).deploy(owner, serviceId, gnosisSafeMultisig.address, payload)
            ).to.be.revertedWith("WrongServiceState");
        });

        it("Catching \"CreateMultisigWithAgents\" event log when calling the Safe contract creation", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstances = [signers[7].address, signers[8].address, signers[9].address];
            const regAgentIds = [agentId, agentId, agentId + 1];
            const maxThreshold = 3;

            // Create components
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(owner, description, componentHash, []);
            await componentRegistry.connect(mechManager).create(owner, description, componentHash1, [1]);

            // Create agents
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1, 2]);

            // Whitelist gnosis multisig implementation
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

            // Create a service and activate the agent instance registration
            let state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(0);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1, 2],
                [[2, regBond], [1, regBond]], maxThreshold);
            state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(1);

            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(2);

            /// Register agent instances
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, agentInstances,
                regAgentIds, {value: 3*regBond});
            state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(3);

            // Create safe passing a specific salt / nonce and payload (won't be used)
            const payload = ethers.utils.solidityPack(["address", "address", "address", "address", "uint256", "uint256", "bytes"],
                [AddressZero, AddressZero, AddressZero, AddressZero, 0, serviceId, "0xabcd"]);
            const safe = await serviceRegistry.connect(serviceManager).deploy(owner, serviceId,
                gnosisSafeMultisig.address, payload);
            const result = await safe.wait();
            expect(result.events[2].event).to.equal("CreateMultisigWithAgents");
            state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(4);

            // Check the service info
            const componentIdsFromServiceId = await serviceRegistry.getComponentIdsOfServiceId(serviceId);
            expect(componentIdsFromServiceId.numComponentIds).to.equal(2);
            for (let i = 0; i < componentIdsFromServiceId.numComponentIds; i++) {
                expect(componentIdsFromServiceId.componentIds[i]).to.equal(i + 1);
            }

            const agentIdsFromServiceId = await serviceRegistry.getAgentIdsOfServiceId(serviceId);
            expect(agentIdsFromServiceId.numAgentIds).to.equal(2);
            for (let i = 0; i < agentIdsFromServiceId.numAgentIds; i++) {
                expect(agentIdsFromServiceId.agentIds[i]).to.equal(i + 1);
            }
        });

        it("Making sure we get correct mapping of _mapComponentIdSetServices formed", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstances = [signers[7].address, signers[8].address, signers[9].address, signers[10].address];
            const maxThreshold = 2;

            // Create components
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(owner, description, componentHash, []);
            await componentRegistry.connect(mechManager).create(owner, description, componentHash1, [1]);

            // Create agents
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1, 2]);

            // Whitelist gnosis multisig implementation
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

            // Create services and activate the agent instance registration
            let state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(0);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1],
                [[2, regBond]], maxThreshold);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash1, [2],
                [[2, regBond]], maxThreshold);

            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId + 1, {value: regDeposit});

            /// Register agent instances
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstances[0], agentInstances[1]],
                [agentId, agentId], {value: 2*regBond});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId + 1, [agentInstances[2], agentInstances[3]],
                [agentId + 1, agentId + 1], {value: 2*regBond});

            await serviceRegistry.connect(serviceManager).deploy(owner, serviceId, gnosisSafeMultisig.address, payload);
            await serviceRegistry.connect(serviceManager).deploy(owner, serviceId + 1, gnosisSafeMultisig.address, payload);
        });
    });

    context("High-level read-only service info requests", async function () {
        it("Should fail when requesting info about a non-existent service", async function () {
            const owner = signers[3].address;
            expect(await serviceRegistry.balanceOf(owner)).to.equal(0);

            await expect(
                serviceRegistry.ownerOf(serviceId)
            ).to.be.revertedWith("NOT_MINTED");

            await expect(
                serviceRegistry.getServiceInfo(serviceId)
            ).to.be.revertedWith("ServiceNotFound");
        });

        it("Obtaining information about service existence, balance, owner, service info", async function () {
            const mechManager = signers[1];
            const serviceManager = signers[2];
            const owner = signers[3].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);

            // Initially owner does not have any services
            expect(await serviceRegistry.exists(serviceId)).to.equal(false);
            expect(await serviceRegistry.balanceOf(owner)).to.equal(0);

            // Creating a service
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);

            // Initial checks
            expect(await serviceRegistry.exists(serviceId)).to.equal(true);
            expect(await serviceRegistry.balanceOf(owner)).to.equal(1);
            expect(await serviceRegistry.ownerOf(serviceId)).to.equal(owner);

            // Check for the service info components
            const serviceInfo = await serviceRegistry.getServiceInfo(serviceId);
            expect(serviceInfo.description).to.equal(description);
            expect(serviceInfo.numAgentIds).to.equal(agentIds.length);
            expect(serviceInfo.configHash.hash).to.equal(configHash.hash);
            for (let i = 0; i < agentIds.length; i++) {
                expect(serviceInfo.agentIds[i]).to.equal(agentIds[i]);
            }
            for (let i = 0; i < agentParams.length; i++) {
                expect(serviceInfo.agentParams[i].slots).to.equal(agentParams[i][0]);
                expect(serviceInfo.agentParams[i].bond).to.equal(agentParams[i][1]);
            }
        });

        it("Obtaining service information after update and creating one more service", async function () {
            const mechManager = signers[1];
            const serviceManager = signers[2];
            const owner = signers[3].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash2, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);

            // Updating a service
            const newAgentIds = [1, 2, 3];
            const newAgentParams = [[2, regBond], [0, regBond], [1, regBond]];
            const newMaxThreshold = newAgentParams[0][0] + newAgentParams[2][0];
            await serviceRegistry.connect(serviceManager).update(owner, description, configHash, newAgentIds,
                newAgentParams, newMaxThreshold, serviceId);

            // Initial checks
            expect(await serviceRegistry.exists(serviceId)).to.equal(true);
            expect(await serviceRegistry.balanceOf(owner)).to.equal(1);
            expect(await serviceRegistry.ownerOf(serviceId)).to.equal(owner);
            let totalSupply = await serviceRegistry.totalSupply();
            expect(totalSupply).to.equal(1);

            // Check for the service info components
            const serviceInfo = await serviceRegistry.getServiceInfo(serviceId);
            expect(serviceInfo.description).to.equal(description);
            expect(serviceInfo.numAgentIds).to.equal(agentIds.length);
            const agentIdsCheck = [newAgentIds[0], newAgentIds[2]];
            for (let i = 0; i < agentIds.length; i++) {
                expect(serviceInfo.agentIds[i]).to.equal(agentIdsCheck[i]);
            }
            const agentNumSlotsCheck = [newAgentParams[0], newAgentParams[2]];
            for (let i = 0; i < agentNumSlotsCheck.length; i++) {
                expect(serviceInfo.agentParams[i].slots).to.equal(agentNumSlotsCheck[i][0]);
                expect(serviceInfo.agentParams[i].bond).to.equal(agentNumSlotsCheck[i][1]);
            }
            const agentInstancesInfo = await serviceRegistry.getInstancesForAgentId(serviceId, agentId);
            expect(agentInstancesInfo.numAgentInstances).to.equal(0);

            // Creating a second service and do basic checks
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIdsCheck,
                agentNumSlotsCheck, newMaxThreshold);
            expect(await serviceRegistry.exists(serviceId + 1)).to.equal(true);
            expect(await serviceRegistry.balanceOf(owner)).to.equal(2);
            expect(await serviceRegistry.ownerOf(serviceId + 1)).to.equal(owner);
            const serviceIds = await serviceRegistry.balanceOf(owner);
            for (let i = 0; i < serviceIds; i++) {
                const serviceIdCheck = await serviceRegistry.tokenByIndex(i);
                expect(serviceIdCheck).to.be.equal(i + 1);
            }
            totalSupply = await serviceRegistry.totalSupply();
            expect(totalSupply).to.equal(2);
        });

        it("Check for returned set of registered agent instances", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstances = [signers[7].address, signers[8].address];
            const regAgentIds = [agentId, agentId];
            const maxThreshold = 2;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1],
                [[2, regBond]], maxThreshold);
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, agentInstances,
                regAgentIds, {value: 2*regBond});

            /// Get the service info
            const serviceInfo = await serviceRegistry.getServiceInfo(serviceId);
            expect(serviceInfo.numAagentInstances == agentInstances.length);
            for (let i = 0; i < agentInstances.length; i++) {
                expect(serviceInfo.agentInstances[i]).to.equal(agentInstances[i]);
            }
            const agentInstancesInfo = await serviceRegistry.getInstancesForAgentId(serviceId, agentId);
            expect(agentInstancesInfo.agentInstances == 2);
            for (let i = 0; i < agentInstances.length; i++) {
                expect(agentInstancesInfo.agentInstances[i]).to.equal(agentInstances[i]);
            }
        });

        it("Should fail when getting hashes of non-existent services", async function () {
            await expect(
                serviceRegistry.getPreviousHashes(1)
            ).to.be.revertedWith("ServiceNotFound");
        });
    });

    context("Termination and unbonding", async function () {
        it("Should fail when trying to terminate service right after creation", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = 2;

            // Create an agent
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);

            // Create a service and activate the agent instance registration
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1],
                [[2, regBond]], maxThreshold);

            // Terminating service without registered agent instances will give it a terminated-unbonded state
            await expect(
                serviceRegistry.connect(serviceManager).terminate(owner, serviceId)
            ).to.be.revertedWith("WrongServiceState");
        });

        it("Terminate service right after creation and registering a single agent instance", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const agentInstance = signers[6].address;
            const operator = signers[7].address;
            const maxThreshold = 2;

            // Create an agent
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);

            // Create a service and activate the agent instance registration
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1],
                [[2, regBond]], maxThreshold);

            // Activate registration and register one agent instance
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});

            // Terminating service with a registered agent instance will give it a terminated-bonded state
            await serviceRegistry.connect(serviceManager).terminate(owner, serviceId);
            const state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(5);

            // Trying to terminate it again will revert
            await expect(
                serviceRegistry.connect(serviceManager).terminate(owner, serviceId)
            ).to.be.revertedWith("WrongServiceState");
        });

        it("Calling terminate from active-registration state", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);

            // Creating the service
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);

            // Activate registration and terminate right after
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).terminate(owner, serviceId);
            // The service state must be terminated-unbonded
            const state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(1);
        });

        it("Unbond when the service registration is terminated", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = 2;

            // Create an agent
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);

            // Create a service and activate the agent instance registration
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1],
                [[2, regBond]], maxThreshold);

            // Revert when insufficient amount is passed
            await expect(
                serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: 0})
            ).to.be.revertedWith("IncorrectRegistrationDepositValue");

            // Activate registration and register one agent instance
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});
            // Balance of the operator must be regBond
            const balanceOperator = Number(await serviceRegistry.getOperatorBalance(operator, serviceId));
            expect(balanceOperator).to.equal(regBond);
            // Contract balance must be the sum of regBond and the regDeposit
            const contractBalance = Number(await ethers.provider.getBalance(serviceRegistry.address));
            expect(contractBalance).to.equal(regBond + regDeposit);

            // Trying to unbond before the service is terminated
            await expect(
                serviceRegistry.connect(serviceManager).unbond(operator, serviceId)
            ).to.be.revertedWith("WrongServiceState");

            // Terminate the service
            await serviceRegistry.connect(serviceManager).terminate(owner, serviceId);

            // Try to unbond by an operator that has not registered a single agent instance
            await expect(
                serviceRegistry.connect(serviceManager).unbond(owner, serviceId)
            ).to.be.revertedWith("OperatorHasNoInstances");

            // Unbonding
            const unbondTx = await serviceRegistry.connect(serviceManager).unbond(operator, serviceId);
            const result = await unbondTx.wait();
            expect(result.events[0].event).to.equal("Refund");
            expect(result.events[1].event).to.equal("OperatorUnbond");
            const state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(1);

            // Operator's balance after unbonding must be zero
            const newBalanceOperator = Number(await serviceRegistry.getOperatorBalance(operator, serviceId));
            expect(newBalanceOperator).to.equal(0);
        });

        it("Should fail when unbond in the incorrect service state", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const maxThreshold = 2;

            // Create an agent
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);

            // Create a service and activate the agent instance registration
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1],
                [[2, regBond]], maxThreshold);

            // Activate registration and try to unbond
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await expect(
                serviceRegistry.connect(serviceManager).unbond(operator, serviceId)
            ).to.be.revertedWith("WrongServiceState");
        });
    });

    context("Manipulations with payable set of functions or balance-related", async function () {
        it("Should revert when calling fallback and receive", async function () {
            const owner = signers[1];
            await expect(
                owner.sendTransaction({to: serviceRegistry.address, value: regBond})
            ).to.be.revertedWith("WrongFunction");

            await expect(
                owner.sendTransaction({to: serviceRegistry.address, value: regBond, data: "0x12"})
            ).to.be.revertedWith("WrongFunction");
        });

        it("Should revert when trying to register an agent instance with a smaller amount", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const maxThreshold = 2;

            // Create an agent
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);

            // Create a service and activate the agent instance registration
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1],
                [[2, regBond]], maxThreshold);

            // Activate registration and register one agent instance
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regBond});
            await expect(
                serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance],
                    [agentId], {value: 0})
            ).to.be.revertedWith("IncorrectAgentBondingValue");
        });

        it("Should fail when trying to activate registration with a smaller amount", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const maxThreshold = 2;

            // Create an agent
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);

            // Create a service and activate the agent instance registration
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1],
                [[2, regBond]], maxThreshold);

            // Activate registration and register one agent instance
            await expect(
                serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit - 1})
            ).to.be.revertedWith("IncorrectRegistrationDepositValue");
        });

        it("Should fail when slashing the agent not in a service", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7].address;
            const wrongAgentInstance = signers[8].address;

            // Create agents
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash1, [1]);

            // Create a service and activate the agent instance registration
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, agentIds,
                agentParams, maxThreshold);

            // Activate registration and register an agent instance
            serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});

            // Should fail when dimentions of arrays don't match
            await expect(
                serviceRegistry.slash([wrongAgentInstance, AddressZero], [regFine], serviceId)
            ).to.be.revertedWith("WrongArrayLength");

            // Simulate slashing with the agent instance that is not in the service
            await expect(
                serviceRegistry.slash([wrongAgentInstance], [regFine], serviceId)
            ).to.be.revertedWith("OnlyOwnServiceMultisig");
        });

        it("Slashing the operator of agent instance", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstance = signers[7];
            const wrongMultisig = signers[9];
            const maxThreshold = 1;

            // Create agents
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);

            // Whitelist gnosis multisig implementation
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

            // Create services and activate the agent instance registration
            let state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(0);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1],
                [[1, regBond]], maxThreshold);

            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});

            /// Register agent instance
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance.address], [agentId], {value: regBond});

            // Create multisig
            const safe = await serviceRegistry.connect(serviceManager).deploy(owner, serviceId,
                gnosisSafeMultisig.address, payload);
            const result = await safe.wait();
            const proxyAddress = result.events[0].address;

            // Try slashing from a different simulated multisig address
            await expect(
                serviceRegistry.connect(wrongMultisig).slash([agentInstance.address], [regFine], serviceId)
            ).to.be.revertedWith("OnlyOwnServiceMultisig");

            // Getting a real multisig address and calling slashing method with it
            const multisig = await ethers.getContractAt("GnosisSafeL2", proxyAddress);
            const safeContracts = require("@gnosis.pm/safe-contracts");
            const nonce = await multisig.nonce();
            const txHashData = await safeContracts.buildContractCall(serviceRegistry, "slash",
                [[agentInstance.address], [regFine], serviceId], nonce, 0, 0);
            const signMessageData = await safeContracts.safeSignMessage(agentInstance, multisig, txHashData, 0);

            // Slash the agent instance operator with the correct multisig
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // After slashing the operator balance must be the difference between the regBond and regFine
            const balanceOperator = Number(await serviceRegistry.getOperatorBalance(operator, serviceId));
            expect(balanceOperator).to.equal(regBond - regFine);

            // The overall slashing balance must be equal to regFine
            const slashedFunds = Number(await serviceRegistry.slashedFunds());
            expect(slashedFunds).to.equal(regFine);
        });

        it("Slashing the operator of agent instances twice and getting the slashed deposit", async function () {
            const mechManager = signers[3];
            const serviceManager = signers[4];
            const owner = signers[5].address;
            const operator = signers[6].address;
            const agentInstances = [signers[7], signers[8]];
            const maxThreshold = 2;

            // Create an agents
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(owner, description, agentHash, [1]);

            // Create services and activate the agent instance registration
            let state = await serviceRegistry.getServiceState(serviceId);
            expect(state).to.equal(0);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, description, configHash, [1],
                [[2, regBond]], maxThreshold);

            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});

            /// Register agent instance
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId,
                [agentInstances[0].address, agentInstances[1].address], [agentId, agentId], {value: 2*regBond});

            // Should fail without whitelisted multisig implementation
            await expect(
                serviceRegistry.connect(serviceManager).deploy(owner, serviceId, gnosisSafeMultisig.address, payload)
            ).to.be.revertedWith("UnauthorizedMultisig");

            // Whitelist gnosis multisig implementation
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

            // Create multisig
            const safe = await serviceRegistry.connect(serviceManager).deploy(owner, serviceId,
                gnosisSafeMultisig.address, payload);
            const result = await safe.wait();
            const proxyAddress = result.events[0].address;

            // Getting a real multisig address and calling slashing method with it
            const multisig = await ethers.getContractAt("GnosisSafeL2", proxyAddress);
            const safeContracts = require("@gnosis.pm/safe-contracts");
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(serviceRegistry, "slash",
                [[agentInstances[0].address], [regFine], serviceId], nonce, 0, 0);
            let signMessageData = [await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0),
                await safeContracts.safeSignMessage(agentInstances[1], multisig, txHashData, 0)];

            // Slash the agent instance operator with the correct multisig
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            // After slashing the operator balance must be the difference between the regBond and regFine
            let balanceOperator = Number(await serviceRegistry.getOperatorBalance(operator, serviceId));
            expect(balanceOperator).to.equal(2 * regBond - regFine);

            // The overall slashing balance must be equal to regFine
            let slashedFunds = Number(await serviceRegistry.slashedFunds());
            expect(slashedFunds).to.equal(regFine);

            // Now slash the operator for the amount bigger than the remaining balance
            // At that time the operator balance is 2 * regBond - regFine
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(serviceRegistry, "slash",
                [[agentInstances[0].address], [2 * regBond], serviceId], nonce, 0, 0);
            signMessageData = [await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0),
                await safeContracts.safeSignMessage(agentInstances[1], multisig, txHashData, 0)];
            await safeContracts.executeTx(multisig, txHashData, signMessageData, 0);

            // Now the operator balance must be zero
            balanceOperator = Number(await serviceRegistry.getOperatorBalance(operator, serviceId));
            expect(balanceOperator).to.equal(0);

            // And the slashed balance must be all the initial operator balance: 2 * regBond
            slashedFunds = Number(await serviceRegistry.slashedFunds());
            expect(slashedFunds).to.equal(2 * regBond);

            // Terminate service and unbond. The operator won't get any refund
            await serviceRegistry.connect(serviceManager).terminate(owner, serviceId);
            const unbond = await serviceRegistry.connect(serviceManager).callStatic.unbond(operator, serviceId);
            expect(Number(unbond.refund)).to.equal(0);
        });
    });

    context("Whitelisting multisig implementations", async function () {
        it("Should fail when passing a zero address multisig", async function () {
            await expect(
                serviceRegistry.changeMultisigPermission(AddressZero, true)
            ).to.be.revertedWith("ZeroAddress");

            await expect(
                serviceRegistry.changeMultisigPermission(AddressZero, false)
            ).to.be.revertedWith("ZeroAddress");
        });

        it("Adding and removing multisig implementation addresses", async function () {
            // Initially should be false
            expect(await serviceRegistry.mapMultisigs(signers[1].address)).to.equal(false);
            // Authorizing and must be true
            await serviceRegistry.changeMultisigPermission(signers[1].address, true);
            expect(await serviceRegistry.mapMultisigs(signers[1].address)).to.equal(true);
            // Deleting and must be false
            await serviceRegistry.changeMultisigPermission(signers[1].address, false);
            expect(await serviceRegistry.mapMultisigs(signers[1].address)).to.equal(false);
            expect(await serviceRegistry.mapMultisigs(signers[2].address)).to.equal(false);
        });
    });
});
