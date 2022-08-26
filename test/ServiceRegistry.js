/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ServiceRegistry", function () {
    let componentRegistry;
    let agentRegistry;
    let serviceRegistry;
    let serviceRegistryL2;
    let gnosisSafeMultisig;
    let reentrancyAttacker;
    let reentrancyAttackerL2;
    let signers;
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
    const componentHash = "0x" + "5".repeat(64);
    const componentHash1 = "0x" + "1".repeat(64);
    const componentHash2 = "0x" + "2".repeat(64);
    const componentHash3 = "0x" + "3".repeat(64);
    const agentHash = "0x" + "7".repeat(64);
    const agentHash1 = "0x" + "8".repeat(64);
    const agentHash2 = "0x" + "9".repeat(64);
    const AddressZero = "0x" + "0".repeat(40);
    const payload = "0x";
    const serviceRegistryImplementations = ["l1", "l2"];

    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
            componentRegistry.address);
        await agentRegistry.deployed();

        const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
        const gnosisSafe = await GnosisSafe.deploy();
        await gnosisSafe.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        const gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
        gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafe.address, gnosisSafeProxyFactory.address);
        await gnosisSafeMultisig.deployed();

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy("service registry", "SERVICE", "https://localhost/service/",
            agentRegistry.address);
        await serviceRegistry.deployed();

        const ServiceRegistryL2 = await ethers.getContractFactory("ServiceRegistryL2");
        serviceRegistryL2 = await ServiceRegistryL2.deploy("Service Registry L2", "SERVICE", "https://localhost/service/");
        await serviceRegistryL2.deployed();

        const ReentrancyAttacker = await ethers.getContractFactory("ReentrancyAttacker");
        reentrancyAttacker = await ReentrancyAttacker.deploy(componentRegistry.address, serviceRegistry.address);
        await reentrancyAttacker.deployed();

        const ReentrancyAttackerL2 = await ethers.getContractFactory("ReentrancyAttacker");
        reentrancyAttackerL2 = await ReentrancyAttackerL2.deploy(componentRegistry.address, serviceRegistryL2.address);
        await reentrancyAttackerL2.deployed();

        signers = await ethers.getSigners();

        await componentRegistry.changeManager(signers[0].address);
        await componentRegistry.create(signers[0].address, componentHash3, []);
    });

    context("Initialization", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Changing owner", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }
                const owner = signers[0];
                const account = signers[1];

                // Trying to change owner from a non-owner account address
                await expect(
                    serviceRegistry.connect(account).changeOwner(account.address)
                ).to.be.revertedWith("OwnerOnly");

                // Trying to change owner for the zero address
                await expect(
                    serviceRegistry.connect(owner).changeOwner(AddressZero)
                ).to.be.revertedWith("ZeroAddress");

                // Changing the owner
                await serviceRegistry.connect(owner).changeOwner(account.address);

                // Trying to change owner from the previous owner address
                await expect(
                    serviceRegistry.connect(owner).changeOwner(owner.address)
                ).to.be.revertedWith("OwnerOnly");
            });

            it("Changing drainer", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }
                const owner = signers[0];
                const account = signers[1];

                // Trying to change owner from a non-owner account address
                await expect(
                    serviceRegistry.connect(account).changeDrainer(account.address)
                ).to.be.revertedWith("OwnerOnly");

                // Trying to change owner for the zero address
                await expect(
                    serviceRegistry.connect(owner).changeDrainer(AddressZero)
                ).to.be.revertedWith("ZeroAddress");

                // Changing the owner
                await serviceRegistry.connect(owner).changeDrainer(account.address);

                // Verifying the drainer address
                expect(await serviceRegistry.drainer()).to.equal(account.address);
            });

            it("Should fail when checking for the service id existence", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }
                const tokenId = 0;
                expect(await serviceRegistry.exists(tokenId)).to.equal(false);
            });

            it("Should fail when trying to change the serviceManager from a different address", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }
                await expect(
                    serviceRegistry.connect(signers[3]).changeManager(signers[3].address)
                ).to.be.revertedWith("OwnerOnly");
            });

            it("Setting the base URI", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }
                await expect(
                    serviceRegistry.connect(signers[1]).setBaseURI("https://localhost2/service/")
                ).to.be.revertedWith("OwnerOnly");

                await expect(
                    serviceRegistry.setBaseURI("")
                ).to.be.revertedWith("ZeroValue");

                await serviceRegistry.setBaseURI("https://localhost2/service/");
                expect(await serviceRegistry.baseURI()).to.equal("https://localhost2/service/");
            });
        });
    });

    context("Service creation", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Should fail when creating a service without a serviceManager", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const owner = signers[3].address;
                await expect(
                    serviceRegistry.create(owner, configHash, agentIds, agentParams, threshold)
                ).to.be.revertedWith("ManagerOnly");
            });

            it("Should fail when changing the owner and the manager to a zero address", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                // Try to change the owner to the zero address
                await expect(
                    serviceRegistry.changeOwner(AddressZero)
                ).to.be.revertedWith("ZeroAddress");

                // Try to change the manager to the zero address
                await expect(
                    serviceRegistry.changeManager(AddressZero)
                ).to.be.revertedWith("ZeroAddress");
            });

            it("Should fail when the owner of a service has a zero address", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const serviceManager = signers[3];
                await serviceRegistry.changeManager(serviceManager.address);
                await expect(
                    serviceRegistry.connect(serviceManager).create(AddressZero, configHash, agentIds,
                        agentParams, threshold)
                ).to.be.revertedWith("ZeroAddress");
            });

            it("Should fail when creating a service with a zero value config hash", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const serviceManager = signers[3];
                const owner = signers[4].address;
                await serviceRegistry.changeManager(serviceManager.address);
                await expect(
                    serviceRegistry.connect(serviceManager).create(owner, ZeroBytes32, agentIds, agentParams,
                        threshold)
                ).to.be.revertedWith("ZeroValue");
            });

            it("Should fail when creating a service with incorrect agent slots values", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const serviceManager = signers[3];
                const owner = signers[4].address;
                await serviceRegistry.changeManager(serviceManager.address);
                await expect(
                    serviceRegistry.connect(serviceManager).create(owner, configHash, [], [], threshold)
                ).to.be.revertedWith("WrongArrayLength");
                await expect(
                    serviceRegistry.connect(serviceManager).create(owner, configHash, [1], [], threshold)
                ).to.be.revertedWith("WrongArrayLength");
                await expect(
                    serviceRegistry.connect(serviceManager).create(owner, configHash, [1, 3], [[2, regBond]],
                        threshold)
                ).to.be.revertedWith("WrongArrayLength");
            });

            it("Should fail when creating a service with non existent canonical agent", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const serviceManager = signers[3];
                const owner = signers[4].address;
                await serviceRegistry.changeManager(serviceManager.address);
                if (serviceRegistryImplementation == "l1") {
                    await expect(
                        serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                            agentParams, threshold)
                    ).to.be.revertedWith("WrongAgentId");
                }
            });

            it("Should fail when creating a service with duplicate canonical agents in agent slots", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await expect(
                    serviceRegistry.connect(serviceManager).create(owner, configHash, [1, 1],
                        [[2, regBond], [2, regBond]], threshold)
                ).to.be.revertedWith("WrongAgentId");
            });

            it("Should fail when creating a service with incorrect input parameter", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                if (serviceRegistryImplementation == "l2") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await expect(
                    serviceRegistry.connect(serviceManager).create(owner, configHash, [1, 0],
                        [[2, regBond], [2, regBond]], threshold)
                ).to.be.revertedWith("WrongAgentId");
            });

            it("Should fail when trying to set empty agent slots", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await expect(
                    serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                        [[3, regBond], [0, regBond]], threshold)
                ).to.be.revertedWith("ZeroValue");
            });

            it("Checking for different signers threshold combinations", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const minThreshold = Math.floor(maxThreshold * 2 / 3 + 1);
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await expect(
                    serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                        agentParams, minThreshold - 1)
                ).to.be.revertedWith("WrongThreshold");
                await expect(
                    serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                        agentParams, maxThreshold + 1)
                ).to.be.revertedWith("WrongThreshold");
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, minThreshold);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
            });

            it("Catching \"CreateService\" event log after registration of a service", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                const service = await serviceRegistry.connect(serviceManager).create(owner, configHash,
                    agentIds, agentParams, maxThreshold);
                const result = await service.wait();
                expect(result.events[1].event).to.equal("CreateService");
            });

            it("Service Id=1 after first successful service registration must exist", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                expect(await serviceRegistry.exists(1)).to.equal(true);
            });

            it("Getting the token URI", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash,
                    agentIds, agentParams, maxThreshold);

                const baseURI = "https://localhost/ipfs/";
                const cidPrefix = "f01701220";
                await serviceRegistry.setBaseURI(baseURI);
                expect(await serviceRegistry.tokenURI(1)).to.equal(baseURI + cidPrefix + "5".repeat(64));
            });

            it("Should fail when trying to get a service Id with the wrong token index", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash,
                    agentIds, agentParams, maxThreshold);
                await expect(
                    serviceRegistry.tokenByIndex(1)
                ).to.be.revertedWith("Overflow");
                expect(await serviceRegistry.tokenByIndex(0)).to.equal(serviceId);
            });
        });
    });

    context("Service update", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Should fail when creating a service without a serviceManager", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const owner = signers[3].address;
                await expect(
                    serviceRegistry.create(owner, configHash, agentIds, agentParams, threshold)
                ).to.be.revertedWith("ManagerOnly");
            });

            it("Should fail when the owner of a service has a zero address during the update", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const serviceManager = signers[3];
                await serviceRegistry.changeManager(serviceManager.address);
                await expect(
                    serviceRegistry.connect(serviceManager).update(AddressZero, configHash, agentIds,
                        agentParams, threshold, 0)
                ).to.be.revertedWith("NOT_MINTED");
            });

            it("Should fail when trying to update a non-existent service", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const serviceManager = signers[3];
                const owner = signers[4].address;
                await serviceRegistry.changeManager(serviceManager.address);
                await expect(
                    serviceRegistry.connect(serviceManager).update(owner, configHash, agentIds,
                        agentParams, threshold, 0)
                ).to.be.revertedWith("NOT_MINTED");
            });

            it("Catching \"UpdateService\" event log after update of a service", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                const service = await serviceRegistry.connect(serviceManager).update(owner, configHash,
                    agentIds, agentParams, maxThreshold, 1);
                const result = await service.wait();
                expect(result.events[0].event).to.equal("UpdateService");
                expect(await serviceRegistry.exists(1)).to.equal(true);
                expect(await serviceRegistry.exists(2)).to.equal(false);
            });

            it("Should fail when trying to update the service with already active registration", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});

                // Try to register agents with a conflicting agent information
                await expect(
                    serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [], {value: regBond})
                ).to.be.revertedWith("WrongArrayLength");

                await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});
                await expect(
                    serviceRegistry.connect(serviceManager).update(owner, configHash, agentIds,
                        agentParams, maxThreshold, 1)
                ).to.be.revertedWith("WrongServiceState");
            });

            it("Update specifically for hashes, then get service hashes", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);

                // If we update with the same config hash as previous one, it must not be added
                await serviceRegistry.connect(serviceManager).update(owner, configHash, agentIds,
                    agentParams, maxThreshold, 1);
                let hashes = await serviceRegistry.getPreviousHashes(serviceId);
                expect(hashes.numHashes).to.equal(0);

                // Now we are going to have two config hashes
                await serviceRegistry.connect(serviceManager).update(owner, configHash1, agentIds,
                    agentParams, maxThreshold, 1);
                hashes = await serviceRegistry.getPreviousHashes(serviceId);
                expect(hashes.numHashes).to.equal(1);
                expect(hashes.configHashes[0].hash).to.equal(configHash.hash);
            });
        });
    });

    context("Register agent instance", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Should fail when registering an agent instance without a serviceManager", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const operator = signers[6].address;
                const agentInstance = signers[7].address;
                await expect(
                    serviceRegistry.registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond})
                ).to.be.revertedWith("ManagerOnly");
            });

            it("Should fail when registering an agent instance with a non-existent service", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const serviceManager = signers[4];
                const operator = signers[6].address;
                const agentInstance = signers[7].address;
                await serviceRegistry.changeManager(serviceManager.address);
                await expect(
                    serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond})
                ).to.be.revertedWith("WrongServiceState");
            });

            it("Should fail when registering an agent instance for the inactive service", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7].address;

                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                await expect(
                    serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond})
                ).to.be.revertedWith("WrongServiceState");
            });

            it("Should fail when registering an agent instance that is already registered", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});
                await expect(
                    serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond})
                ).to.be.revertedWith("AgentInstanceRegistered");
            });

            it("Should fail when registering an agent instance for non existent canonical agent Id", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                await expect(
                    serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [0])
                ).to.be.revertedWith("AgentNotInService");
            });

            it("Should fail when registering an agent instance for the service with no available slots", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstances = [signers[7].address, signers[8].address, signers[9].address, signers[10].address];
                const regAgentIds = [agentId, agentId, agentId, agentId];
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                await expect(
                    serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, agentInstances, regAgentIds, {value: 4*regBond})
                ).to.be.revertedWith("AgentInstancesSlotsFilled");
            });

            it("Catching \"RegisterInstance\" event log after agent instance registration", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                const regAgent = await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId,
                    [agentInstance], [agentId], {value: regBond});
                const result = await regAgent.wait();
                expect(result.events[0].event).to.equal("RegisterInstance");
            });

            it("Registering several agent instances in different services by the same operator", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = [signers[7].address, signers[8].address, signers[9].address];
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
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
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstances = [signers[7].address, signers[8].address];
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
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
    });

    context("activateRegistration / termination of the service", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Should fail when activating a non-existent service", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const serviceManager = signers[3];
                const owner = signers[4].address;
                await serviceRegistry.changeManager(serviceManager.address);
                await expect(
                    serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId + 1, {value: regDeposit})
                ).to.be.revertedWith("NOT_MINTED");
            });

            it("Should fail when activating a service that is already active", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                await expect(
                    serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit})
                ).to.be.revertedWith("ServiceMustBeInactive");
            });

            it("Catching \"ActivateRegistration\" event log after service activation", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;

                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                const activateService = await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId,
                    {value: regDeposit});
                const result = await activateService.wait();
                expect(result.events[0].event).to.equal("ActivateRegistration");
            });

            it("Catching \"TerminateService\" event log after service termination", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                const terminateService = await serviceRegistry.connect(serviceManager).terminate(owner, serviceId);
                const result = await terminateService.wait();
                expect(result.events[0].event).to.equal("Refund");
                expect(result.events[1].event).to.equal("TerminateService");
            });

            it("Terminating a service with at least one agent instance", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7].address;

                // Create agents and a service
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);

                // Activate registration and register and agent instance
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});

                // Terminate the service, unbond
                const terminateService = await serviceRegistry.connect(serviceManager).terminate(owner, serviceId);
                let result = await terminateService.wait();
                expect(result.events[0].event).to.equal("Refund");
                expect(result.events[1].event).to.equal("TerminateService");

                // Try to unbond to a zero address
                await expect(
                    serviceRegistry.connect(serviceManager).unbond(AddressZero, serviceId)
                ).to.be.revertedWith("ZeroAddress");

                await serviceRegistry.connect(serviceManager).unbond(operator, serviceId);

                // The service state must be terminated-unbonded
                const serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(1);
            });
        });
    });

    context("Safe contract from agent instances", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Should fail when creating a Safe without a full set of registered agent instances", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});
                await expect(
                    serviceRegistry.connect(serviceManager).deploy(owner, serviceId, gnosisSafeMultisig.address, payload)
                ).to.be.revertedWith("WrongServiceState");
            });

            it("Catching \"CreateMultisigWithAgents\" event log when calling the Safe contract creation", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstances = [signers[7].address, signers[8].address, signers[9].address];
                const regAgentIds = [agentId, agentId, agentId + 1];
                const maxThreshold = 3;

                if (serviceRegistryImplementation == "l1") {
                    // Create components
                    await componentRegistry.changeManager(mechManager.address);
                    await componentRegistry.connect(mechManager).create(owner, componentHash, []);
                    await componentRegistry.connect(mechManager).create(owner, componentHash1, [1]);

                    // Create agents
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1, 2]);
                }

                // Whitelist gnosis multisig implementation
                await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

                // Create a service and activate the agent instance registration
                let serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(0);
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1, 2],
                    [[2, regBond], [1, regBond]], maxThreshold);
                serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(1);

                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(2);

                /// Register agent instances
                await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, agentInstances,
                    regAgentIds, {value: 3*regBond});
                serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(3);

                // Create safe passing a specific salt / nonce as a current date and a payload (won't be used)
                const nonce = parseInt(Date.now() / 1000, 10);
                const payload = "0xabcd";
                // Pach the data for gnosis safe
                const data = ethers.utils.solidityPack(["address", "address", "address", "address", "uint256", "uint256", "bytes"],
                    [AddressZero, AddressZero, AddressZero, AddressZero, 0, nonce, payload]);
                const safe = await serviceRegistry.connect(serviceManager).deploy(owner, serviceId,
                    gnosisSafeMultisig.address, data);
                const result = await safe.wait();
                expect(result.events[2].event).to.equal("CreateMultisigWithAgents");
                serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(4);

                if (serviceRegistryImplementation == "l1") {
                    // Check the service info
                    // 0 is component, 1 is agent
                    const componentIdsFromServiceId = await serviceRegistry.getUnitIdsOfService(0, serviceId);
                    expect(componentIdsFromServiceId.numUnitIds).to.equal(2);
                    for (let i = 0; i < componentIdsFromServiceId.numUnitIds; i++) {
                        expect(componentIdsFromServiceId.unitIds[i]).to.equal(i + 1);
                    }

                    const agentIdsFromServiceId = await serviceRegistry.getUnitIdsOfService(1, serviceId);
                    expect(agentIdsFromServiceId.numUnitIds).to.equal(2);
                    for (let i = 0; i < agentIdsFromServiceId.numUnitIds; i++) {
                        expect(agentIdsFromServiceId.unitIds[i]).to.equal(i + 1);
                    }
                }
            });

            it("Making sure we get correct mapping of _mapComponentIdSetServices formed", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstances = [signers[7].address, signers[8].address, signers[9].address, signers[10].address];
                const maxThreshold = 2;

                if (serviceRegistryImplementation == "l1") {
                    // Create components
                    await componentRegistry.changeManager(mechManager.address);
                    await componentRegistry.connect(mechManager).create(owner, componentHash, []);
                    await componentRegistry.connect(mechManager).create(owner, componentHash1, [1]);

                    // Create agents
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1, 2]);
                }

                // Whitelist gnosis multisig implementation
                await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

                // Create services and activate the agent instance registration
                let serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(0);
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
                    [[2, regBond]], maxThreshold);
                await serviceRegistry.connect(serviceManager).create(owner, configHash1, [2],
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
    });

    context("High-level read-only service info requests", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Should fail when requesting an owner info about a non-existent service", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const owner = signers[3].address;
                expect(await serviceRegistry.balanceOf(owner)).to.equal(0);

                await expect(
                    serviceRegistry.ownerOf(serviceId)
                ).to.be.revertedWith("NOT_MINTED");

                const serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(0);
            });

            it("Obtaining information about service existence, balance, owner, service info", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[1];
                const serviceManager = signers[2];
                const owner = signers[3].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }

                // Initially owner does not have any services
                expect(await serviceRegistry.exists(serviceId)).to.equal(false);
                expect(await serviceRegistry.balanceOf(owner)).to.equal(0);

                // Creating a service
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);

                // Initial checks
                expect(await serviceRegistry.exists(serviceId)).to.equal(true);
                expect(await serviceRegistry.balanceOf(owner)).to.equal(1);
                expect(await serviceRegistry.ownerOf(serviceId)).to.equal(owner);

                // Check for the service info components
                const serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.agentIds.length).to.equal(agentIds.length);
                expect(serviceInstance.configHash.hash).to.equal(configHash.hash);
                for (let i = 0; i < agentIds.length; i++) {
                    expect(serviceInstance.agentIds[i]).to.equal(agentIds[i]);
                }
                const serviceAgentParams = await serviceRegistry.getAgentParams(serviceId);
                expect(serviceAgentParams.numAgentIds).to.equal(agentParams.length);
                for (let i = 0; i < agentParams.length; i++) {
                    expect(serviceAgentParams.agentParams[i].slots).to.equal(agentParams[i][0]);
                    expect(serviceAgentParams.agentParams[i].bond).to.equal(agentParams[i][1]);
                }
            });

            it("Obtaining service information after update and creating one more service", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[1];
                const serviceManager = signers[2];
                const owner = signers[3].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash2, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);

                // Updating a service
                const newAgentIds = [1, 2, 3];
                const newAgentParams = [[2, regBond], [0, regBond], [1, regBond]];
                const newMaxThreshold = newAgentParams[0][0] + newAgentParams[2][0];
                await serviceRegistry.connect(serviceManager).update(owner, configHash, newAgentIds,
                    newAgentParams, newMaxThreshold, serviceId);

                // Initial checks
                expect(await serviceRegistry.exists(serviceId)).to.equal(true);
                expect(await serviceRegistry.balanceOf(owner)).to.equal(1);
                expect(await serviceRegistry.ownerOf(serviceId)).to.equal(owner);
                let totalSupply = await serviceRegistry.totalSupply();
                expect(totalSupply).to.equal(1);

                // Check for the service info components
                const serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.agentIds.length).to.equal(agentIds.length);
                const agentIdsCheck = [newAgentIds[0], newAgentIds[2]];
                for (let i = 0; i < agentIds.length; i++) {
                    expect(serviceInstance.agentIds[i]).to.equal(agentIdsCheck[i]);
                }
                const agentNumSlotsCheck = [newAgentParams[0], newAgentParams[2]];
                const serviceAgentParams = await serviceRegistry.getAgentParams(serviceId);
                expect(serviceAgentParams.numAgentIds).to.equal(agentParams.length);
                for (let i = 0; i < agentNumSlotsCheck.length; i++) {
                    expect(serviceAgentParams.agentParams[i].slots).to.equal(agentNumSlotsCheck[i][0]);
                    expect(serviceAgentParams.agentParams[i].bond).to.equal(agentNumSlotsCheck[i][1]);
                }
                const agentInstancesInfo = await serviceRegistry.getInstancesForAgentId(serviceId, agentId);
                expect(agentInstancesInfo.numAgentInstances).to.equal(0);

                // Creating a second service and do basic checks
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIdsCheck,
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
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstances = [signers[7].address, signers[8].address];
                const regAgentIds = [agentId, agentId];
                const maxThreshold = 2;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
                    [[2, regBond]], maxThreshold);
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, agentInstances,
                    regAgentIds, {value: 2*regBond});

                /// Get the service info
                const serviceInstance = await serviceRegistry.getAgentInstances(serviceId);
                expect(serviceInstance.numAgentInstances == agentInstances.length);
                for (let i = 0; i < agentInstances.length; i++) {
                    expect(serviceInstance.agentInstances[i]).to.equal(agentInstances[i]);
                }
                const agentInstancesInfo = await serviceRegistry.getInstancesForAgentId(serviceId, agentId);
                expect(agentInstancesInfo.agentInstances == 2);
                for (let i = 0; i < agentInstances.length; i++) {
                    expect(agentInstancesInfo.agentInstances[i]).to.equal(agentInstances[i]);
                }
            });

            it("Get zero previous hashes when the service does not exist", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const hashes = await serviceRegistry.getPreviousHashes(1);
                expect(hashes.numHashes).to.equal(0);
            });
        });
    });

    context("Termination and unbonding", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Should fail when trying to terminate service right after creation", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const maxThreshold = 2;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }

                // Create a service and activate the agent instance registration
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
                    [[2, regBond]], maxThreshold);

                // Terminating service without registered agent instances will give it a terminated-unbonded state
                await expect(
                    serviceRegistry.connect(serviceManager).terminate(owner, serviceId)
                ).to.be.revertedWith("WrongServiceState");
            });

            it("Terminate service right after creation and registering a single agent instance", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const agentInstance = signers[6].address;
                const operator = signers[7].address;
                const maxThreshold = 2;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }

                // Create a service and activate the agent instance registration
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
                    [[2, regBond]], maxThreshold);

                // Activate registration and register one agent instance
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});

                // Terminating service with a registered agent instance will give it a terminated-bonded state
                await serviceRegistry.connect(serviceManager).terminate(owner, serviceId);
                const serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(5);

                // Trying to terminate it again will revert
                await expect(
                    serviceRegistry.connect(serviceManager).terminate(owner, serviceId)
                ).to.be.revertedWith("WrongServiceState");
            });

            it("Calling terminate from active-registration state", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);

                // Creating the service
                await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                    agentParams, maxThreshold);

                // Activate registration and terminate right after
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                await serviceRegistry.connect(serviceManager).terminate(owner, serviceId);
                // The service state must be terminated-unbonded
                const serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(1);
            });

            it("Unbond when the service registration is terminated", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7].address;
                const maxThreshold = 2;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }

                // Create a service and activate the agent instance registration
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
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
                const serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(1);

                // Operator's balance after unbonding must be zero
                const newBalanceOperator = Number(await serviceRegistry.getOperatorBalance(operator, serviceId));
                expect(newBalanceOperator).to.equal(0);
            });

            it("Should fail when unbond in the incorrect service state", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const maxThreshold = 2;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }

                // Create a service and activate the agent instance registration
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
                    [[2, regBond]], maxThreshold);

                // Activate registration and try to unbond
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                await expect(
                    serviceRegistry.connect(serviceManager).unbond(operator, serviceId)
                ).to.be.revertedWith("WrongServiceState");
            });
        });
    });

    context("Manipulations with payable set of functions or balance-related", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Should revert when trying to register an agent instance with a smaller amount", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7].address;
                const maxThreshold = 2;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }

                // Create a service and activate the agent instance registration
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
                    [[2, regBond]], maxThreshold);

                // Activate registration and register one agent instance
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regBond});
                await expect(
                    serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance],
                        [agentId], {value: 0})
                ).to.be.revertedWith("IncorrectAgentBondingValue");
            });

            it("Should fail when trying to activate registration with a smaller amount", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const maxThreshold = 2;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }

                // Create a service and activate the agent instance registration
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
                    [[2, regBond]], maxThreshold);

                // Activate registration and register one agent instance
                await expect(
                    serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit - 1})
                ).to.be.revertedWith("IncorrectRegistrationDepositValue");
            });

            it("Should fail when slashing the agent not in a service", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7].address;
                const wrongAgentInstance = signers[8].address;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }

                // Create a service and activate the agent instance registration
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
                    [[1, regBond]], 1);

                // Activate registration and register an agent instance
                serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
                serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance], [agentId], {value: regBond});

                // Try to slash in a non deployed service state
                await expect(
                    serviceRegistry.slash([wrongAgentInstance], [regFine], serviceId)
                ).to.be.revertedWith("WrongServiceState");

                // Whitelist gnosis multisig implementation
                await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

                // Create multisig
                await serviceRegistry.connect(serviceManager).deploy(owner, serviceId, gnosisSafeMultisig.address, payload);

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
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7];
                const wrongMultisig = signers[9];
                const maxThreshold = 1;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }

                // Whitelist gnosis multisig implementation
                await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

                // Create services and activate the agent instance registration
                let serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(0);
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
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
                const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);
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

            it("Drain slashed funds", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const drainer = signers[2];
                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7];
                const maxThreshold = 1;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }

                // Whitelist gnosis multisig implementation
                await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

                // Create services and activate the agent instance registration
                let serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(0);
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
                    [[1, regBond]], maxThreshold);

                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});

                /// Register agent instance
                await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance.address], [agentId], {value: regBond});

                // Create multisig
                const safe = await serviceRegistry.connect(serviceManager).deploy(owner, serviceId,
                    gnosisSafeMultisig.address, payload);
                const result = await safe.wait();
                const proxyAddress = result.events[0].address;

                // Getting a real multisig address and calling slashing method with it
                const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);
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

                // Drain slashed funds by the drainer
                await serviceRegistry.changeDrainer(drainer.address);
                // Trying to drain by the operator
                await expect(
                    serviceRegistry.connect(signers[6]).drain()
                ).to.be.revertedWith("ManagerOnly");

                // Get the slashed funds transferred to the drainer address
                const amount = await serviceRegistry.connect(drainer).callStatic.drain();
                expect(amount).to.equal(regFine);

                // Check that slashed funds are zeroed
                await serviceRegistry.connect(drainer).drain();
                expect(await serviceRegistry.slashedFunds()).to.equal(0);

                // Try to drain again
                // First one to check the drained amount to be zero with a static call
                expect(await serviceRegistry.connect(drainer).callStatic.drain()).to.equal(0);
                // Then do the real drain and make sure nothing has changed or failed
                await serviceRegistry.connect(drainer).drain();
                expect(await serviceRegistry.slashedFunds()).to.equal(0);
            });

            it("Slashing the operator of agent instances twice and getting the slashed deposit", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstances = [signers[7], signers[8]];
                const maxThreshold = 2;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }

                // Create services and activate the agent instance registration
                let serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(0);
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
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
                const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);
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

            it("Should fail when trying to not act through the service manager", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                // Create a service
                await serviceRegistry.connect(serviceManager).create(owner, configHash,
                    agentIds, agentParams, maxThreshold);

                // Trying to update with a wrong manager
                await expect(
                    serviceRegistry.update(owner, configHash, agentIds, agentParams, threshold, serviceId)
                ).to.be.revertedWith("ManagerOnly");

                // Trying to activate the service with a wrong manager
                await expect(
                    serviceRegistry.activateRegistration(owner, serviceId)
                ).to.be.revertedWith("ManagerOnly");

                // Trying to register an agent instance with a wrong manager
                await expect(
                    serviceRegistry.registerAgents(operator, serviceId, [AddressZero], [agentId])
                ).to.be.revertedWith("ManagerOnly");

                // Trying to deploy the service with a wrong manager
                await expect(
                    serviceRegistry.deploy(owner, serviceId, AddressZero, "0x")
                ).to.be.revertedWith("ManagerOnly");

                // Trying to terminate the service with a wrong manager
                await expect(
                    serviceRegistry.terminate(owner, serviceId)
                ).to.be.revertedWith("ManagerOnly");

                // Trying to unbond from the service with a wrong manager
                await expect(
                    serviceRegistry.unbond(operator, serviceId)
                ).to.be.revertedWith("ManagerOnly");
            });

            it("Should fail when trying to act on a service being not its owner", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const nonOwner = signers[6].address;
                const operator = signers[7].address;
                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner, agentHash1, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                // Create a service
                await serviceRegistry.connect(serviceManager).create(owner, configHash,
                    agentIds, agentParams, maxThreshold);

                // Trying to update with a wrong manager
                await expect(
                    serviceRegistry.connect(serviceManager).update(nonOwner, configHash, agentIds, agentParams,
                        threshold, serviceId)
                ).to.be.revertedWith("OwnerOnly");

                // Trying to activate the service with a wrong manager
                await expect(
                    serviceRegistry.connect(serviceManager).activateRegistration(nonOwner, serviceId)
                ).to.be.revertedWith("OwnerOnly");

                // Trying to deploy the service with a wrong manager
                await expect(
                    serviceRegistry.connect(serviceManager).deploy(nonOwner, serviceId, AddressZero, "0x")
                ).to.be.revertedWith("OwnerOnly");

                // Trying to terminate the service with a wrong manager
                await expect(
                    serviceRegistry.connect(serviceManager).terminate(nonOwner, serviceId)
                ).to.be.revertedWith("OwnerOnly");

                // Trying to unbond from the service with a wrong manager
                await expect(
                    serviceRegistry.unbond(operator, serviceId)
                ).to.be.revertedWith("ManagerOnly");
            });
        });
    });

    context("Whitelisting multisig implementations", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Should fail when passing a zero address multisig or trying to change not by the owner", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                await expect(
                    serviceRegistry.connect(signers[1]).changeMultisigPermission(AddressZero, true)
                ).to.be.revertedWith("OwnerOnly");

                await expect(
                    serviceRegistry.changeMultisigPermission(AddressZero, true)
                ).to.be.revertedWith("ZeroAddress");

                await expect(
                    serviceRegistry.changeMultisigPermission(AddressZero, false)
                ).to.be.revertedWith("ZeroAddress");
            });

            it("Adding and removing multisig implementation addresses", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

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

    context("Subcomponents", async function () {
        it("Get the list of service subcomponents for 4 components and 3 agents", async function () {
            const mechManager = signers[1];
            const serviceManager = signers[2];
            const owner = signers[3].address;
            const operator = signers[4].address;
            const agentInstances = [signers[5].address, signers[6].address, signers[7].address, signers[8].address,
                signers[9].address];
            const componentOwners = [signers[11], signers[12], signers[13], signers[14]];
            const agentOwners = [signers[15], signers[16], signers[17]];

            // Create 4 components (one is already created in the beforeEach()) and 3 agents based on them
            await componentRegistry.changeManager(mechManager.address);
            await componentRegistry.connect(mechManager).create(componentOwners[0].address, componentHash, []);
            await componentRegistry.connect(mechManager).create(componentOwners[1].address, componentHash1, []);
            await componentRegistry.connect(mechManager).create(componentOwners[2].address, componentHash2, []);
            await agentRegistry.changeManager(mechManager.address);
            await agentRegistry.connect(mechManager).create(agentOwners[0].address, agentHash, [1, 2]);
            await agentRegistry.connect(mechManager).create(agentOwners[1].address, agentHash1, [2]);
            await agentRegistry.connect(mechManager).create(agentOwners[2].address, agentHash2, [3]);

            // Create 2 services
            const agentIds = [[1, 2], [1, 3]];
            const agentParams = [[1, regBond], [1, regBond]];
            const threshold = 2;
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds[0],
                agentParams, threshold);
            await serviceRegistry.connect(serviceManager).create(owner, configHash1, agentIds[1],
                agentParams, threshold);

            // Register agent instances
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, 2, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId,
                [agentInstances[0], agentInstances[1]], agentIds[0], {value: 2 * regBond});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, 2, [agentInstances[2], agentInstances[3]],
                agentIds[1], {value: 2 * regBond});

            // Deploy services
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
            await serviceRegistry.connect(serviceManager).deploy(owner, serviceId, gnosisSafeMultisig.address, payload);
            await serviceRegistry.connect(serviceManager).deploy(owner, 2, gnosisSafeMultisig.address, payload);

            let subComponents = await serviceRegistry.getUnitIdsOfService(0, 1);
            // subcomponents for service 1: agent1 => [1, 2] and agent2 => [2] |=> [1, 2]
            expect(subComponents.numUnitIds).to.equal(2);
            for (let i = 0; i < subComponents.numUnitIds; i++) {
                expect(subComponents.unitIds[i]).to.equal(i + 1);
            }
            subComponents = await serviceRegistry.getUnitIdsOfService(0, 2);
            // subcomponents for service 2: agent1 => [1, 2] and agent3 => [3] |=> [1, 2, 3]
            expect(subComponents.numUnitIds).to.equal(3);
            for (let i = 0; i < subComponents.numUnitIds; i++) {
                expect(subComponents.unitIds[i]).to.equal(i + 1);
            }
        });

        it("Get the list of service subcomponents for 10 components and 3 agents", async function () {
            const mechManager = signers[0];
            const serviceManager = signers[2];
            const owner = signers[3].address;
            const operator = signers[4].address;
            const agentInstances = [signers[5].address, signers[6].address, signers[7].address];

            let salt = "0x";
            let hash = ethers.utils.keccak256(salt);
            // Create 10 components (one is already created in the beforeEach()) and 3 agents based on them
            await componentRegistry.changeManager(mechManager.address);
            // c2
            await componentRegistry.create(owner, hash, [1]);
            // c3
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [1, 2]);
            // c4
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [1, 3]);
            // c5
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [1, 3, 4]);
            // c6
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [2, 4, 5]);
            // c7
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, []);
            // c8
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [4]);
            // c9
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [3, 4, 6]);
            // c10
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [6, 8, 9]);

            await agentRegistry.changeManager(mechManager.address);
            // a1
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await agentRegistry.create(owner, hash, [5, 6]);
            // a2
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await agentRegistry.create(owner, hash, [5, 9]);
            // a3
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await agentRegistry.create(owner, hash, [6, 9, 10]);

            // Create 1 service consisting of all three agents
            const agentIds = [1, 2, 3];
            const agentParams = [[1, regBond], [1, regBond], [1, regBond]];
            const threshold = 3;
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistry.connect(serviceManager).create(owner, configHash, agentIds,
                agentParams, threshold);

            // Register agent instances
            await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
            await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId,
                [agentInstances[0], agentInstances[1], agentInstances[2]], agentIds, {value: 3 * regBond});

            // Deploy the service
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
            const multisig = await serviceRegistry.connect(serviceManager).deploy(owner, serviceId,
                gnosisSafeMultisig.address, payload);
            // Check that the multisig is created and does not have a zero address
            const result = await multisig.wait();
            const proxyAddress = result.events[0].address;
            expect(proxyAddress).to.not.equal(AddressZero);

            // 0 is component, 1 is agent
            let subComponents = await serviceRegistry.getUnitIdsOfService(0, serviceId);
            // subcomponents for the service 1:
            // agent1 => [5, 6] |=> [1, 3, 4, 5], [2, 4, 5, 6] |=>
            // [1, [1, 2], [1, 2, 3], [1, 3, 4], 5], [[1, 2], [1, 3, 4], [1, 3, 4, 5], 6] |=> ... |=> [1, 2, 3, 4, 5, 6]
            // agent 2 => [5, 9] |=> [1, 3, 4, 5], [3, 4, 6, 9] |=>
            // [1, [1, 2, 3], [1, 3, 4], 5], [[1, 2, 3], [1, 3, 4], [2, 4, 5, 6], 9]] |=> ... |=> [1 - 6, 9]
            // agent 2 => [6, 9, 10] |=> [2, 4, 5, 6], [3, 4, 6, 9], [6, 8, 9, 10] |=>
            // [[1, 2], [1, 3, 4], [1, 3, 4, 5], 6], [[1, 2, 3], [1, 3, 4], [2, 4, 5, 6], 9]],
            // [[2, 4, 5, 6], [4, 8], [3, 4, 6, 9], 10] |=> ... |=> [1 - 6, 8, 9, 10]
            expect(subComponents.numUnitIds).to.equal(9);
            for (let i = 0; i < 6; i++) {
                expect(subComponents.unitIds[i]).to.equal(i + 1);
            }
            for (let i = 6; i < 9; i++) {
                expect(subComponents.unitIds[i]).to.equal(i + 2);
            }
            // Check agent ids
            let subAgents = await serviceRegistry.getUnitIdsOfService(1, serviceId);
            // subagents for the service: agent1, agent2, agent3 => [1, 2, 3]
            expect(subAgents.numUnitIds).to.equal(3);
            for (let i = 0; i < subAgents.numUnitIds; i++) {
                expect(subAgents.unitIds[i]).to.equal(i + 1);
            }
        });

        it("Subcomponents production case simulation", async function () {
            const mechManager = signers[0];
            const serviceManager = signers[2];
            const owner = signers[3].address;
            const operator = signers[4].address;
            const agentInstances = [signers[5].address, signers[6].address, signers[7].address];

            let salt = "0x";
            let hash = ethers.utils.keccak256(salt);
            // Create 11 components (one is already created in the beforeEach()) and 3 agents based on them
            await componentRegistry.changeManager(mechManager.address);
            // c2
            await componentRegistry.create(owner, hash, []);
            // c3
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [1]);
            // c4
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [2, 3]);
            // c5
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [3]);
            // c6
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [3]);
            // c7
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [3]);
            // c8
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [3]);
            // c9
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [3]);
            // c10
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [3]);
            // c11
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await componentRegistry.create(owner, hash, [2, 3, 6, 7, 8, 9, 10]);

            await agentRegistry.changeManager(mechManager.address);
            // a1
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await agentRegistry.create(owner, hash, [4]);
            // a2
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await agentRegistry.create(owner, hash, [5]);
            // a3
            salt += "00";
            hash = ethers.utils.keccak256(salt);
            await agentRegistry.create(owner, hash, [11]);

            // Create 3 services consisting of one agent each
            const agentIds = [1, 2, 3];
            const agentParams = [[1, regBond], [1, regBond], [1, regBond]];
            const threshold = 1;
            await serviceRegistry.changeManager(serviceManager.address);
            for (let i = 0; i < 3; i++) {
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [agentIds[i]],
                    [agentParams[i]], threshold);
            }

            // Register agent instances
            for (let i = 0; i < 3; i++) {
                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId + i, {value: regDeposit});
                await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId + i,
                    [agentInstances[i]], [agentIds[i]], {value: regBond});
            }

            // Deploy services
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
            for (let i = 0; i < 3; i++) {
                const multisig = await serviceRegistry.connect(serviceManager).deploy(owner, serviceId + i,
                    gnosisSafeMultisig.address, payload);
                // Check that the multisig is created and does not have a zero address
                const result = await multisig.wait();
                const proxyAddress = result.events[0].address;
                expect(proxyAddress).to.not.equal(AddressZero);
            }

            // Checking subcomponents of service 1
            // 0 is component, 1 is agent
            let subComponents = await serviceRegistry.getUnitIdsOfService(0, serviceId);
            // subcomponents for the service 1:
            // agent1 => [4] |=> [2, 3, 4] |=> [[2], [1, 3], 4] |=> [[2], [1, [1], 3], 4] |=> [1, 2, 3, 4]
            expect(subComponents.numUnitIds).to.equal(4);
            for (let i = 0; i < subComponents.numUnitIds; i++) {
                expect(subComponents.unitIds[i]).to.equal(i + 1);
            }

            // Checking subcomponents of service 2
            subComponents = await serviceRegistry.getUnitIdsOfService(0, serviceId + 1);
            // subcomponents for the service 2:
            // agent1 => [5] |=> [3, 5] |=> [[1, 3], 5] |=> [[1, [1], 3], 5] |=> [1, 3, 5]
            expect(subComponents.numUnitIds).to.equal(3);
            expect(subComponents.unitIds[0]).to.equal(1);
            expect(subComponents.unitIds[1]).to.equal(3);
            expect(subComponents.unitIds[2]).to.equal(5);

            // Checking subcomponents of service 3
            subComponents = await serviceRegistry.getUnitIdsOfService(0, serviceId + 2);
            // subcomponents for the service 3:
            // agent1 => [11] |=> [[2, 3, 6, 7, 8, 9, 10], 11] |=> ... |=> [1, 2, 3, 6, 7, 8, 9, 10, 11]
            expect(subComponents.numUnitIds).to.equal(9);
            for (let i = 0; i < 3; i++) {
                expect(subComponents.unitIds[i]).to.equal(i + 1);
            }
            for (let i = 3; i < 9; i++) {
                expect(subComponents.unitIds[i]).to.equal(i + 3);
            }
        });
    });

    context("Attacks", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Reentrancy attack by the manager during the service creation", async function () {
                // Adopt the reentrancy attacker to be based on the service registry L2 as well
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    reentrancyAttacker = reentrancyAttackerL2;
                }

                const mechManager = signers[0];
                const owner = signers[1].address;

                if (serviceRegistryImplementation == "l1") {
                    // Create two agents
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.create(owner, agentHash, [1]);
                    await agentRegistry.create(owner, agentHash1, [1]);
                }

                // Change the manager to the attacker contract address
                await serviceRegistry.changeManager(reentrancyAttacker.address);

                // Simulate the reentrancy attack
                await reentrancyAttacker.setAttackOnCreate(true);
                await expect(
                    reentrancyAttacker.createBadService(reentrancyAttacker.address, configHash, agentIds,
                        agentParams, maxThreshold)
                ).to.be.revertedWith("ReentrancyGuard");
            });

            it("Reentrancy attack by the manager during the service deployment", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    reentrancyAttacker = reentrancyAttackerL2;
                }

                const mechManager = signers[0];
                const serviceManager = signers[1];
                const owner = signers[2].address;
                const operator = signers[3].address;
                const agentInstances = [signers[7]];
                const maxThreshold = 1;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.create(owner, agentHash, [1]);
                }

                // Create services and activate the agent instance registration
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(reentrancyAttacker.address, configHash, [1],
                    [[1, regBond]], maxThreshold);

                await serviceRegistry.connect(serviceManager).activateRegistration(reentrancyAttacker.address,
                    serviceId, {value: regDeposit});

                /// Register agent instance
                await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId,
                    [agentInstances[0].address], [agentId], {value: regBond});

                // Whitelist attacker multisig implementation
                await serviceRegistry.changeMultisigPermission(reentrancyAttacker.address, true);

                // Service manager is compromised with a multisig implementation attacker address
                await serviceRegistry.changeManager(reentrancyAttacker.address);

                // Calling deployment by the attacker
                await expect(
                    reentrancyAttacker.deployBadMultisig(reentrancyAttacker.address, serviceId, reentrancyAttacker.address, payload)
                ).to.be.revertedWith("ReentrancyGuard");
            });

            it("Reentrancy attack by the manager during the service termination", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    reentrancyAttacker = reentrancyAttackerL2;
                }

                const mechManager = signers[0];
                const serviceManager = signers[1];
                const owner = signers[2].address;
                const agentInstances = [signers[7]];
                const maxThreshold = 1;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.create(owner, agentHash, [1]);
                }

                // Create services and activate the agent instance registration
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(reentrancyAttacker.address, configHash, [1],
                    [[1, regBond]], maxThreshold);

                await serviceRegistry.connect(serviceManager).activateRegistration(reentrancyAttacker.address,
                    serviceId, {value: regDeposit});

                /// Register agent instance with the malicious operator
                await serviceRegistry.connect(serviceManager).registerAgents(reentrancyAttacker.address, serviceId,
                    [agentInstances[0].address], [agentId], {value: regBond});

                // Deploy the service
                await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
                await serviceRegistry.connect(serviceManager).deploy(reentrancyAttacker.address, serviceId,
                    gnosisSafeMultisig.address, payload);

                // Attacker manages to become the manager tries to call a malicious terminate() function
                await serviceRegistry.changeManager(reentrancyAttacker.address);
                // Reentrancy guard revert failed the attacker receive() function that returned as "TransferFailed"
                await expect(
                    reentrancyAttacker.terminateBadRefund(reentrancyAttacker.address, serviceId)
                ).to.be.revertedWith("TransferFailed");
            });

            it("Reentrancy attack by the manager during the service unbond", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    reentrancyAttacker = reentrancyAttackerL2;
                }

                const mechManager = signers[0];
                const serviceManager = signers[1];
                const owner = signers[2].address;
                const agentInstances = [signers[7]];
                const maxThreshold = 1;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.create(owner, agentHash, [1]);
                }

                // Create services and activate the agent instance registration
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
                    [[1, regBond]], maxThreshold);

                await serviceRegistry.connect(serviceManager).activateRegistration(owner,
                    serviceId, {value: regDeposit});

                /// Register agent instance with the malicious operator
                await serviceRegistry.connect(serviceManager).registerAgents(reentrancyAttacker.address, serviceId,
                    [agentInstances[0].address], [agentId], {value: regBond});

                // Deploy the service
                await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
                await serviceRegistry.connect(serviceManager).deploy(owner, serviceId,
                    gnosisSafeMultisig.address, payload);

                // Terminate service
                await serviceRegistry.connect(serviceManager).terminate(owner, serviceId);

                // Now become a manager and try to call a bad unbond() function
                await serviceRegistry.changeManager(reentrancyAttacker.address);
                // Reentrancy guard revert failed the attacker receive() function that returned as "TransferFailed"
                await expect(
                    reentrancyAttacker.unbondBadOperator(reentrancyAttacker.address, serviceId)
                ).to.be.revertedWith("TransferFailed");
            });

            it("Reentrancy attack by the bad drainer", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    reentrancyAttacker = reentrancyAttackerL2;
                }

                const mechManager = signers[3];
                const serviceManager = signers[4];
                const owner = signers[5].address;
                const operator = signers[6].address;
                const agentInstance = signers[7];
                const maxThreshold = 1;

                if (serviceRegistryImplementation == "l1") {
                    // Create an agent
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
                }

                // Whitelist gnosis multisig implementation
                await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

                // Create services and activate the agent instance registration
                let serviceInstance = await serviceRegistry.getService(serviceId);
                expect(serviceInstance.state).to.equal(0);
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistry.connect(serviceManager).create(owner, configHash, [1],
                    [[1, regBond]], maxThreshold);

                await serviceRegistry.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});

                /// Register agent instance
                await serviceRegistry.connect(serviceManager).registerAgents(operator, serviceId, [agentInstance.address], [agentId], {value: regBond});

                // Create multisig
                const safe = await serviceRegistry.connect(serviceManager).deploy(owner, serviceId,
                    gnosisSafeMultisig.address, payload);
                const result = await safe.wait();
                const proxyAddress = result.events[0].address;

                // Getting a real multisig address and calling slashing method with it
                const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);
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

                // Drain slashed funds by the drainer
                await serviceRegistry.changeDrainer(reentrancyAttacker.address);
                // Trying to drain by the attacker who got the drain access
                await expect(
                    reentrancyAttacker.drainFromBadAddress()
                ).to.be.revertedWith("TransferFailed");
            });
        });
    });

    context("Contract transfers", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Should fail when sending funds directly to the contract", async function () {
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                }

                await expect(
                    signers[0].sendTransaction({to: serviceRegistry.address, value: ethers.utils.parseEther("1000"), data: "0x12"})
                ).to.be.reverted;
            });
        });
    });
});
