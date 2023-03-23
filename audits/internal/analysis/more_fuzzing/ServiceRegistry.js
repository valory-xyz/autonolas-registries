/*global describe, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe.only("ServiceRegistry", function () {
    let componentRegistry;
    let agentRegistry;
    let serviceRegistry;
    let serviceRegistryProxy;
    let gnosisSafe;
    let gnosisSafeMultisig;
    let gnosisSafeProxyFactory;
    let defaultCallbackHandler;
    let multiSend;
    let gnosisSafeSameAddressMultisig;
    let signers;
    const configHash = "0x" + "5".repeat(64);
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

    beforeEach(async function () {
        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("agent components", "MECHCOMP",
            "https://localhost/component/");
        await componentRegistry.deployed();
        console.log("componentRegistry", componentRegistry.address);

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "MECH", "https://localhost/agent/",
            componentRegistry.address);
        await agentRegistry.deployed();
        console.log("agentRegistry", agentRegistry.address);

        const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
        gnosisSafe = await GnosisSafe.deploy();
        await gnosisSafe.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
        gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafe.address, gnosisSafeProxyFactory.address);
        await gnosisSafeMultisig.deployed();
        console.log("gnosisSafeMultisig", gnosisSafeMultisig.address);

        const DefaultCallbackHandler = await ethers.getContractFactory("DefaultCallbackHandler");
        defaultCallbackHandler = await DefaultCallbackHandler.deploy();
        await defaultCallbackHandler.deployed();

        const MultiSend = await ethers.getContractFactory("MultiSendCallOnly");
        multiSend = await MultiSend.deploy();
        await multiSend.deployed();

        const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
        gnosisSafeSameAddressMultisig = await GnosisSafeSameAddressMultisig.deploy();
        await gnosisSafeSameAddressMultisig.deployed();

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistryAnnotated");
        serviceRegistry = await ServiceRegistry.deploy("service registry", "SERVICE", "https://localhost/service/",
            agentRegistry.address);
        await serviceRegistry.deployed();
        console.log("serviceRegistry", serviceRegistry.address);

        const ServiceRegistryProxy = await ethers.getContractFactory("ServiceRegistryProxy");
        serviceRegistryProxy = await ServiceRegistryProxy.deploy();
        await serviceRegistryProxy.deployed();

        signers = await ethers.getSigners();

        await componentRegistry.changeManager(signers[0].address);
        await componentRegistry.create(signers[0].address, componentHash3, []);
    });

    it("Deploy the service", async function () {
        const mechManager = signers[3];
        const serviceManager = signers[4];
        const owner = signers[5].address;
        const operator = signers[6].address;
        const agentInstances = [signers[7].address, signers[8].address, signers[9].address];
        const regAgentIds = [agentId, agentId, agentId + 1];
        const maxThreshold = 3;

        // Create components
        await componentRegistry.changeManager(mechManager.address);
        await componentRegistry.connect(mechManager).create(owner, componentHash, []);
        await componentRegistry.connect(mechManager).create(owner, componentHash1, [1]);

        // Create agents
        await agentRegistry.changeManager(mechManager.address);
        await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
        await agentRegistry.connect(mechManager).create(owner, agentHash1, [1, 2]);

        // Change owner for proxy
        await serviceRegistry.changeOwner(serviceRegistryProxy.address);
        // Whitelist gnosis multisig implementation
        await serviceRegistryProxy.changeMultisigPermission(gnosisSafeMultisig.address, true);

        // Create a service and activate the agent instance registration
        let serviceInstance = await serviceRegistryProxy.getService(serviceId);
        expect(serviceInstance.state).to.equal(0);
        await serviceRegistryProxy.changeManager(serviceRegistryProxy.address);
        await serviceRegistryProxy.create(owner, configHash, [1, 2],
            [[2, regBond], [1, regBond]], maxThreshold);
        serviceInstance = await serviceRegistryProxy.getService(serviceId);
        expect(serviceInstance.state).to.equal(1);

        await serviceRegistryProxy.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
        serviceInstance = await serviceRegistryProxy.getService(serviceId);
        expect(serviceInstance.state).to.equal(2);

        /// Register agent instances
        await serviceRegistryProxy.connect(serviceManager).registerAgents(operator, serviceId, agentInstances,
            regAgentIds, {value: 3*regBond});
        serviceInstance = await serviceRegistryProxy.getService(serviceId);
        expect(serviceInstance.state).to.equal(3);

        // Create safe passing a specific salt / nonce as a current date and a payload (won't be used)
        const nonce = parseInt(Date.now() / 1000, 10);
        const payload = "0xabcd";
        // Pack the data for gnosis safe
        const data = ethers.utils.solidityPack(["address", "address", "address", "address", "uint256", "uint256", "bytes"],
            [AddressZero, AddressZero, AddressZero, AddressZero, 0, nonce, payload]);
        const safe = await serviceRegistryProxy.connect(serviceManager).deploy(owner, serviceId,
            gnosisSafeMultisig.address, data);
        const result = await safe.wait();
        serviceInstance = await serviceRegistryProxy.getService(serviceId);
        expect(serviceInstance.state).to.equal(4);

        // Terminate service
        await serviceRegistryProxy.connect(serviceManager).terminate(owner, serviceId);

        // Unbond
        await serviceRegistryProxy.connect(serviceManager).unbond(operator, serviceId);
    });

    it("Deploy the service, terminate and unbond)", async function () {
        const mechManager = signers[3];
        const serviceManager = signers[4];
        const owner = signers[5].address;
        const operator = signers[6].address;
        const agentInstances = [signers[7].address, signers[8].address, signers[9].address];
        const regAgentIds = [agentId, agentId, agentId + 1];
        const maxThreshold = 3;

        // Create components
        await componentRegistry.changeManager(mechManager.address);
        await componentRegistry.connect(mechManager).create(owner, componentHash, []);
        await componentRegistry.connect(mechManager).create(owner, componentHash1, [1]);

        // Create agents
        await agentRegistry.changeManager(mechManager.address);
        await agentRegistry.connect(mechManager).create(owner, agentHash, [1]);
        await agentRegistry.connect(mechManager).create(owner, agentHash1, [1, 2]);

        // Change owner for proxy
        await serviceRegistry.changeOwner(serviceRegistryProxy.address);
        // Whitelist gnosis multisig implementation
        await serviceRegistryProxy.changeMultisigPermission(gnosisSafeMultisig.address, true);

        // Create a service and activate the agent instance registration
        let serviceInstance = await serviceRegistryProxy.getService(serviceId);
        expect(serviceInstance.state).to.equal(0);
        await serviceRegistryProxy.changeManager(serviceRegistryProxy.address);
        await serviceRegistryProxy.create(owner, configHash, [1, 2],
            [[2, regBond], [1, regBond]], maxThreshold);
        serviceInstance = await serviceRegistryProxy.getService(serviceId);
        expect(serviceInstance.state).to.equal(1);

        await serviceRegistryProxy.connect(serviceManager).activateRegistration(owner, serviceId, {value: regDeposit});
        serviceInstance = await serviceRegistryProxy.getService(serviceId);
        expect(serviceInstance.state).to.equal(2);

        /// Register agent instances
        await serviceRegistryProxy.connect(serviceManager).registerAgents(operator, serviceId, agentInstances,
            regAgentIds, {value: 3*regBond});
        serviceInstance = await serviceRegistryProxy.getService(serviceId);
        expect(serviceInstance.state).to.equal(3);

        // Create safe passing a specific salt / nonce as a current date and a payload (won't be used)
        const nonce = parseInt(Date.now() / 1000, 10);
        const payload = "0xabcd";
        // Pack the data for gnosis safe
        const data = ethers.utils.solidityPack(["address", "address", "address", "address", "uint256", "uint256", "bytes"],
            [AddressZero, AddressZero, AddressZero, AddressZero, 0, nonce, payload]);
        const safe = await serviceRegistryProxy.connect(serviceManager).deploy(owner, serviceId,
            gnosisSafeMultisig.address, data);
        const result = await safe.wait();
        serviceInstance = await serviceRegistryProxy.getService(serviceId);
        expect(serviceInstance.state).to.equal(4);

        // Terminate service
        await serviceRegistryProxy.connect(serviceManager).terminate(owner, serviceId);

        // Unbond
        await serviceRegistryProxy.connect(serviceManager).unbond(operator, serviceId);
    });
});
