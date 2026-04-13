/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ApplicationClassifier", function () {
    let applicationClassifier;
    let applicationClassifierProxy;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        // Deploy implementation
        const ApplicationClassifier = await ethers.getContractFactory("ApplicationClassifier");
        applicationClassifier = await ApplicationClassifier.deploy();
        await applicationClassifier.deployed();

        // Prepare initialization data
        const iface = new ethers.utils.Interface(["function initialize()"]);
        const initData = iface.encodeFunctionData("initialize");

        // Deploy proxy
        const AgentClassificationProxy = await ethers.getContractFactory("AgentClassificationProxy");
        applicationClassifierProxy = await AgentClassificationProxy.deploy(applicationClassifier.address, initData);
        await applicationClassifierProxy.deployed();

        // Attach implementation ABI to proxy address
        applicationClassifier = ApplicationClassifier.attach(applicationClassifierProxy.address);
    });

    context("Proxy deployment", function () {
        it("Should not allow zero implementation address", async function () {
            const iface = new ethers.utils.Interface(["function initialize()"]);
            const initData = iface.encodeFunctionData("initialize");
            const AgentClassificationProxy = await ethers.getContractFactory("AgentClassificationProxy");
            await expect(
                AgentClassificationProxy.deploy(AddressZero, initData)
            ).to.be.revertedWithCustomError(applicationClassifierProxy, "ZeroAddress");
        });

        it("Should not allow zero initialization data", async function () {
            const ApplicationClassifier = await ethers.getContractFactory("ApplicationClassifier");
            const impl = await ApplicationClassifier.deploy();
            await impl.deployed();
            const AgentClassificationProxy = await ethers.getContractFactory("AgentClassificationProxy");
            await expect(
                AgentClassificationProxy.deploy(impl.address, "0x")
            ).to.be.revertedWithCustomError(applicationClassifierProxy, "ZeroValue");
        });

        it("Should return the correct implementation address", async function () {
            const ApplicationClassifier = await ethers.getContractFactory("ApplicationClassifier");
            const impl = await ApplicationClassifier.deploy();
            await impl.deployed();

            const iface = new ethers.utils.Interface(["function initialize()"]);
            const initData = iface.encodeFunctionData("initialize");
            const AgentClassificationProxy = await ethers.getContractFactory("AgentClassificationProxy");
            const proxy = await AgentClassificationProxy.deploy(impl.address, initData);
            await proxy.deployed();

            expect(await proxy.getImplementation()).to.equal(impl.address);
        });
    });

    context("Initialization", function () {
        it("Should set deployer as owner after initialization", async function () {
            expect(await applicationClassifier.owner()).to.equal(deployer.address);
        });

        it("Should return correct version", async function () {
            expect(await applicationClassifier.VERSION()).to.equal("0.1.0");
        });

        it("Should revert on double initialization", async function () {
            await expect(
                applicationClassifier.initialize()
            ).to.be.revertedWithCustomError(applicationClassifier, "AlreadyInitialized");
        });
    });

    context("Change owner", function () {
        it("Should change owner and emit event", async function () {
            const tx = await applicationClassifier.changeOwner(signers[1].address);
            const result = await tx.wait();
            expect(result.events[0].args.owner).to.equal(signers[1].address);
            expect(await applicationClassifier.owner()).to.equal(signers[1].address);
        });

        it("Should revert if non-owner calls changeOwner", async function () {
            await expect(
                applicationClassifier.connect(signers[1]).changeOwner(signers[2].address)
            ).to.be.revertedWithCustomError(applicationClassifier, "OwnerOnly");
        });

        it("Should revert on zero address", async function () {
            await expect(
                applicationClassifier.changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(applicationClassifier, "ZeroAddress");
        });
    });

    context("Change maintainer", function () {
        it("Should change maintainer and emit event", async function () {
            const tx = await applicationClassifier.changeMaintainer(signers[1].address);
            const result = await tx.wait();
            expect(result.events[0].args.maintainer).to.equal(signers[1].address);
            expect(await applicationClassifier.maintainer()).to.equal(signers[1].address);
        });

        it("Should revert if non-owner calls changeMaintainer", async function () {
            await expect(
                applicationClassifier.connect(signers[1]).changeMaintainer(signers[2].address)
            ).to.be.revertedWithCustomError(applicationClassifier, "OwnerOnly");
        });

        it("Should revert on zero address", async function () {
            await expect(
                applicationClassifier.changeMaintainer(AddressZero)
            ).to.be.revertedWithCustomError(applicationClassifier, "ZeroAddress");
        });
    });

    context("Change implementation", function () {
        it("Should change implementation and emit event", async function () {
            const ApplicationClassifier = await ethers.getContractFactory("ApplicationClassifier");
            const newImpl = await ApplicationClassifier.deploy();
            await newImpl.deployed();

            const tx = await applicationClassifier.changeImplementation(newImpl.address);
            const result = await tx.wait();
            expect(result.events[0].args.implementation).to.equal(newImpl.address);

            // Verify the proxy now points to new implementation
            expect(await applicationClassifierProxy.getImplementation()).to.equal(newImpl.address);
        });

        it("Should revert if non-owner calls changeImplementation", async function () {
            await expect(
                applicationClassifier.connect(signers[1]).changeImplementation(signers[2].address)
            ).to.be.revertedWithCustomError(applicationClassifier, "OwnerOnly");
        });

        it("Should revert on zero address", async function () {
            await expect(
                applicationClassifier.changeImplementation(AddressZero)
            ).to.be.revertedWithCustomError(applicationClassifier, "ZeroAddress");
        });

        it("Storage slot constant should match between proxy and implementation", async function () {
            const implSlot = await applicationClassifier.PROXY_AGENT_CLASSIFICATION();
            const proxySlot = await applicationClassifierProxy.PROXY_AGENT_CLASSIFICATION();
            expect(implSlot).to.equal(proxySlot);
        });
    });

    context("Record application type", function () {
        beforeEach(async function () {
            // Set maintainer
            await applicationClassifier.changeMaintainer(signers[1].address);
        });

        it("Should record application type and emit event", async function () {
            const serviceId = 1;
            // ApplicationType.PEARL = 1
            const tx = await applicationClassifier.connect(signers[1]).recordApplicationType(serviceId, 1);
            const result = await tx.wait();
            expect(result.events[0].args.serviceId).to.equal(serviceId);
            expect(result.events[0].args.appType).to.equal(1);
            expect(await applicationClassifier.mapServiceIdStatuses(serviceId)).to.equal(1);
        });

        it("Should record all application types", async function () {
            const maintainer = signers[1];
            // NON_EXISTENT = 0
            await applicationClassifier.connect(maintainer).recordApplicationType(1, 0);
            expect(await applicationClassifier.mapServiceIdStatuses(1)).to.equal(0);
            // PEARL = 1
            await applicationClassifier.connect(maintainer).recordApplicationType(2, 1);
            expect(await applicationClassifier.mapServiceIdStatuses(2)).to.equal(1);
            // OTHER = 2
            await applicationClassifier.connect(maintainer).recordApplicationType(3, 2);
            expect(await applicationClassifier.mapServiceIdStatuses(3)).to.equal(2);
        });

        it("Should update application type for the same service", async function () {
            const serviceId = 1;
            await applicationClassifier.connect(signers[1]).recordApplicationType(serviceId, 1);
            expect(await applicationClassifier.mapServiceIdStatuses(serviceId)).to.equal(1);

            await applicationClassifier.connect(signers[1]).recordApplicationType(serviceId, 2);
            expect(await applicationClassifier.mapServiceIdStatuses(serviceId)).to.equal(2);
        });

        it("Should revert if non-maintainer calls recordApplicationType", async function () {
            await expect(
                applicationClassifier.connect(signers[2]).recordApplicationType(1, 1)
            ).to.be.revertedWithCustomError(applicationClassifier, "MaintainerOnly");
        });

        it("Should revert if owner (non-maintainer) calls recordApplicationType", async function () {
            await expect(
                applicationClassifier.recordApplicationType(1, 1)
            ).to.be.revertedWithCustomError(applicationClassifier, "MaintainerOnly");
        });
    });
});
