/*global describe, context, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");

describe("Deployment", function () {
    context("Deployment", async function () {
        it("Deployment steps", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            const signers = await ethers.getSigners();
            // EOA
            const EOA = signers[0];
            // Timelock (already deployed in the mainnet)
            const timelock = signers[1];

            // Deployment of Gnosis Safe contracts (already deployed on various networks)
            const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
            const gnosisSafe = await GnosisSafe.deploy();
            await gnosisSafe.deployed();

            const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
            const gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
            await gnosisSafeProxyFactory.deployed();

            // 1. EOA to deploy ComponentRegistry;
            const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
            const componentRegistry = await ComponentRegistry.connect(EOA).deploy("Component registry", "COMPONENT",
                "https://localhost/component/");
            await componentRegistry.deployed();

            // 2. EOA to deploy AgentRegistry pointed to ComponentRegistry;
            const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
            const agentRegistry = await AgentRegistry.connect(EOA).deploy("Agent registry", "AGENT", "https://localhost/agent/",
                componentRegistry.address);
            await agentRegistry.deployed();

            // 3. EOA to deploy RegistriesManager pointed to ComponentRegistry and AgentRegistry;
            const RegistriesManager = await ethers.getContractFactory("RegistriesManager");
            const registriesManager = await RegistriesManager.connect(EOA).deploy(componentRegistry.address, agentRegistry.address);
            await registriesManager.deployed();

            // 4. EOA to deploy ServiceRegistry;
            const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
            const serviceRegistry = await ServiceRegistry.connect(EOA).deploy("Service registry", "SERVICE", "https://localhost/agent/",
                agentRegistry.address);
            await serviceRegistry.deployed();

            // 5. EOA to deploy ServiceManager pointed to ServiceRegistry;
            const ServiceManager = await ethers.getContractFactory("ServiceManager");
            const serviceManager = await ServiceManager.connect(EOA).deploy(serviceRegistry.address);
            await serviceManager.deployed();

            // 6. EOA to deploy GnosisSafeMultisig;
            const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
            const gnosisSafeMultisig = await GnosisSafeMultisig.connect(EOA).deploy(gnosisSafe.address,
                gnosisSafeProxyFactory.address);
            await gnosisSafeMultisig.deployed();

            // 7. EOA to change the manager of ComponentRegistry and AgentRegistry to RegistriesManager via `changeManager(RegistriesManager)`;
            await componentRegistry.connect(EOA).changeManager(registriesManager.address);
            await agentRegistry.connect(EOA).changeManager(registriesManager.address);
            // 8. EOA to change the manager of ServiceRegistry to ServiceManager calling `changeManager(ServiceManager)`;
            await serviceRegistry.connect(EOA).changeManager(serviceManager.address);
            // 9. EOA to whitelist GnosisSafeMultisig in ServiceRegistry via `changeMultisigPermission(GnosisSafeMultisig)`;
            await serviceRegistry.connect(EOA).changeMultisigPermission(gnosisSafeMultisig.address, true);
            // 10. EOA to transfer ownership rights of ComponentRegistry to Timelock calling `changeOwner(Timelock)`;
            await componentRegistry.connect(EOA).changeOwner(timelock.address);
            // 11. EOA to transfer ownership rights of AgentRegistry to Timelock calling `changeOwner(Timelock)`;
            await agentRegistry.connect(EOA).changeOwner(timelock.address);
            // 12. EOA to transfer ownership rights of ServiceRegistry to Timelock calling `changeOwner(Timelock)`;
            await serviceRegistry.connect(EOA).changeOwner(timelock.address);
            // 13. EOA to transfer ownership rights of RegistriesManager to Timelock calling `changeOwner(Timelock)`;
            await registriesManager.connect(EOA).changeOwner(timelock.address);
            // 14. EOA to transfer ownership rights of ServiceManager to Timelock calling `changeOwner(Timelock)`.
            await serviceManager.connect(EOA).changeOwner(timelock.address);

            // Verify final permissions
            expect(await serviceRegistry.mapMultisigs(gnosisSafeMultisig.address)).to.equal(true);
            expect(await componentRegistry.owner()).to.equal(timelock.address);
            expect(await agentRegistry.owner()).to.equal(timelock.address);
            expect(await serviceRegistry.owner()).to.equal(timelock.address);
            expect(await registriesManager.owner()).to.equal(timelock.address);
            expect(await serviceManager.owner()).to.equal(timelock.address);

            // Restore a previous state of blockchain
            snapshot.restore();
        });
    });
});

