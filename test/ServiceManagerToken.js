/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ServiceManagerToken", function () {
    let componentRegistry;
    let agentRegistry;
    let gnosisSafe;
    let gnosisSafeProxyFactory;
    let serviceRegistry;
    let serviceRegistryL2;
    let serviceRegistryTokenUtility;
    let serviceRegistryTokenUtilityL2;
    let serviceManager;
    let serviceManagerL2;
    let gnosisSafeMultisig;
    let token;
    let operatorWhitelist;
    let operatorWhitelistL2;
    let reentrancyAttacker;
    let signers;
    let deployer;
    const configHash = "0x" + "5".repeat(64);
    const regBond = 1000;
    const regDeposit = 1000;
    const regFine = 500;
    const agentIds = [1, 2];
    const agentParams = [[3, regBond], [4, regBond]];
    const serviceIds = [1, 2];
    const threshold = 1;
    const maxThreshold = agentParams[0][0] + agentParams[1][0];
    const unitHash = "0x" + "9".repeat(64);
    const unitHash1 = "0x" + "1".repeat(64);
    const unitHash2 = "0x" + "2".repeat(64);
    const unitHash3 = "0x" + "3".repeat(64);
    const payload = "0x";
    const AddressZero = "0x" + "0".repeat(40);
    const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    const initSupply = "5" + "0".repeat(26);
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
        gnosisSafe = await GnosisSafe.deploy();
        await gnosisSafe.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy("service registry", "SERVICE", "https://localhost/agent/",
            agentRegistry.address);
        await serviceRegistry.deployed();

        const ServiceRegistryL2 = await ethers.getContractFactory("ServiceRegistryL2");
        serviceRegistryL2 = await ServiceRegistryL2.deploy("Service Registry L2", "SERVICE", "https://localhost/service/");
        await serviceRegistryL2.deployed();

        const ServiceRegistryTokenUtility = await ethers.getContractFactory("ServiceRegistryTokenUtility");
        serviceRegistryTokenUtility = await ServiceRegistryTokenUtility.deploy(serviceRegistry.address);
        await serviceRegistryTokenUtility.deployed();

        serviceRegistryTokenUtilityL2 = await ServiceRegistryTokenUtility.deploy(serviceRegistryL2.address);
        await serviceRegistryTokenUtilityL2.deployed();

        const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
        gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafe.address, gnosisSafeProxyFactory.address);
        await gnosisSafeMultisig.deployed();

        const OperatorWhitelist = await ethers.getContractFactory("OperatorWhitelist");
        operatorWhitelist = await OperatorWhitelist.deploy(serviceRegistry.address);
        await operatorWhitelist.deployed();

        operatorWhitelistL2 = await OperatorWhitelist.deploy(serviceRegistryL2.address);
        await operatorWhitelistL2.deployed();

        const ServiceManager = await ethers.getContractFactory("ServiceManagerToken");
        serviceManager = await ServiceManager.deploy(serviceRegistry.address, serviceRegistryTokenUtility.address,
            operatorWhitelist.address);
        await serviceManager.deployed();

        serviceManagerL2 = await ServiceManager.deploy(serviceRegistryL2.address, serviceRegistryTokenUtilityL2.address,
            operatorWhitelistL2.address);
        await serviceManagerL2.deployed();

        const Token = await ethers.getContractFactory("ERC20Token");
        token = await Token.deploy();
        await token.deployed();

        const ReentrancyAttacker = await ethers.getContractFactory("ReentrancyTokenAttacker");
        reentrancyAttacker = await ReentrancyAttacker.deploy(serviceRegistryTokenUtility.address);
        await reentrancyAttacker.deployed();

        signers = await ethers.getSigners();
        deployer = signers[0];
        await token.mint(deployer.address, initSupply);
        await componentRegistry.changeManager(signers[0].address);
        await componentRegistry.create(signers[0].address, unitHash3, []);
    });

    context("Initialization", async function () {
        it("Constructor must fail with zero provided addresses", async function () {
            const ServiceManager = await ethers.getContractFactory("ServiceManagerToken");

            await expect(
                ServiceManager.deploy(AddressZero, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(serviceManager, "ZeroAddress");

            await expect(
                ServiceManager.deploy(serviceRegistry.address, AddressZero, AddressZero)
            ).to.be.revertedWithCustomError(serviceManager, "ZeroAddress");
        });

        it("Changing owner", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                serviceManager.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(serviceManager, "OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                serviceManager.connect(owner).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(serviceManager, "ZeroAddress");

            // Changing the owner
            await serviceManager.connect(owner).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                serviceManager.connect(owner).changeOwner(owner.address)
            ).to.be.revertedWithCustomError(serviceManager, "OwnerOnly");
        });

        it("Pausing and unpausing", async function () {
            const owner = signers[1].address;
            const manager = signers[2];

            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner, unitHash, [1]);
            await agentRegistry.connect(manager).create(owner, unitHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);

            // Try to pause not from the owner of the service manager
            await expect(
                serviceManager.connect(manager).pause()
            ).to.be.revertedWithCustomError(serviceManager, "OwnerOnly");

            // Pause the contract
            await serviceManager.pause();

            // Try minting when paused
            // 0 is component, 1 is agent
            await expect(
                serviceManager.create(owner, ETHAddress, configHash, agentIds, agentParams, maxThreshold)
            ).to.be.revertedWithCustomError(serviceManager, "Paused");

            // Try to unpause not from the owner of the service manager
            await expect(
                serviceManager.connect(manager).unpause()
            ).to.be.revertedWithCustomError(serviceManager, "OwnerOnly");

            // Unpause the contract
            await serviceManager.unpause();

            // Mint component and agent
            await serviceManager.create(owner, ETHAddress, configHash, agentIds, agentParams, maxThreshold);
        });

        it("Should fail when creating a service without a manager being white listed", async function () {
            const owner = signers[4].address;
            await expect(
                serviceManager.create(owner, ETHAddress, configHash, agentIds, agentParams, threshold)
            ).to.be.revertedWithCustomError(serviceManager, "ManagerOnly");
        });

        it("Service Id=1 after first successful service creation must exist", async function () {
            const manager = signers[4];
            const owner = signers[5].address;
            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner, unitHash, [1]);
            await agentRegistry.connect(manager).create(owner, unitHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceManager.create(owner, ETHAddress, configHash, agentIds, agentParams,
                maxThreshold);
            expect(await serviceRegistry.exists(serviceIds[0])).to.equal(true);
        });

        it("Registering several services and agent instances", async function () {
            const manager = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstances = [signers[7].address, signers[8].address, signers[9].address];
            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner.address, unitHash, [1]);
            await agentRegistry.connect(manager).create(owner.address, unitHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistryTokenUtility.changeManager(serviceManager.address);
            await serviceManager.create(owner.address, ETHAddress, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.create(owner.address, ETHAddress, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.connect(owner).activateRegistration(serviceIds[0], {value: regDeposit});
            await serviceManager.connect(owner).activateRegistration(serviceIds[1], {value: regDeposit});
            await serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstances[0], agentInstances[2]],
                [agentIds[0], agentIds[0]], {value: 2*regBond});
            await serviceManager.connect(operator).registerAgents(serviceIds[1], [agentInstances[1]], [agentIds[1]], {value: regBond});

            expect(await serviceRegistry.exists(2)).to.equal(true);
            expect(await serviceRegistry.exists(3)).to.equal(false);
        });

        it("Pausing and unpausing", async function () {
            const manager = signers[2];
            const owner = signers[3];

            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner.address, unitHash, [1]);
            await serviceRegistry.changeManager(serviceManager.address);

            // Pause the contract
            await serviceManager.pause();

            // Try creating a contract when paused
            await expect(
                serviceManager.create(owner.address, ETHAddress, configHash, [1], [[1, regBond]], 1)
            ).to.be.revertedWithCustomError(serviceManager, "Paused");

            // Unpause the contract
            await serviceManager.unpause();

            // Create a service
            await serviceManager.create(owner.address, ETHAddress, configHash, [1], [[1, regBond]], 1);
        });

        it("Should fail when setting the operator whitelist incorrectly", async function () {
            // Try to set the address not by the owner
            await expect(
                serviceManager.connect(signers[1]).setOperatorWhitelist(deployer.address)
            ).to.be.revertedWithCustomError(serviceManager, "OwnerOnly");
        });

        it("Should fail when calling functions with a zero token", async function () {
            // Create a service
            await expect(
                serviceManager.create(deployer.address, AddressZero, configHash, agentIds, agentParams, threshold)
            ).to.be.revertedWithCustomError(serviceManager, "ZeroAddress");
            // Update a service
            await expect(
                serviceManager.update(AddressZero, configHash, agentIds, agentParams, threshold, serviceIds[0])
            ).to.be.revertedWithCustomError(serviceManager, "ZeroAddress");
        });
    });
    
    context("Service creation and update via manager", async function () {
        it("Creating services, updating one of them", async function () {
            const manager = signers[4];
            const owner = signers[5];
            await agentRegistry.changeManager(manager.address);
            await agentRegistry.connect(manager).create(owner.address, unitHash, [1]);
            await agentRegistry.connect(manager).create(owner.address, unitHash1, [1]);
            await agentRegistry.connect(manager).create(owner.address, unitHash2, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistryTokenUtility.changeManager(serviceManager.address);
            await serviceManager.create(owner.address, ETHAddress, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.create(owner.address, ETHAddress, configHash, agentIds, agentParams,
                maxThreshold);
            await serviceManager.connect(owner).update(ETHAddress, configHash, [1, 2, 3],
                [[3, regBond], [0, regBond], [4, regBond]], maxThreshold, serviceIds[0]);
            expect(await serviceRegistry.exists(2)).to.equal(true);
            expect(await serviceRegistry.exists(3)).to.equal(false);
        });
    });

    context("Service manipulations via manager", async function () {
        serviceRegistryImplementations.forEach(async function (serviceRegistryImplementation) {
            it("Creating a service with a custom token, update, register, deploy, terminate, unbond", async function () {
                // Choose the service registry implementation: L1 or L2
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    serviceManager = serviceManagerL2;
                    serviceRegistryTokenUtility = serviceRegistryTokenUtilityL2;
                    operatorWhitelist = operatorWhitelistL2;
                }

                const manager = signers[4];
                const owner = signers[5];
                const operator = signers[6];
                const agentInstances = [signers[7].address, signers[8].address];

                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(manager.address);
                    // Creating 3 canonical agents
                    await agentRegistry.connect(manager).create(owner.address, unitHash, [1]);
                    await agentRegistry.connect(manager).create(owner.address, unitHash1, [1]);
                    await agentRegistry.connect(manager).create(owner.address, unitHash2, [1]);
                }
                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistryTokenUtility.changeManager(serviceManager.address);

                // Try to create a service with a token having specified at least one zero bond
                let errAgentIds = [1, 4];
                let errAgentParams = [[1, 0], [1, regBond]];
                await expect(
                    serviceManager.create(deployer.address, token.address, configHash, errAgentIds, errAgentParams, maxThreshold)
                ).to.be.revertedWithCustomError(serviceManager, "ZeroValue");

                // Create one service with the ERC20 token bond
                const initAgentIds = [1, 3];
                await serviceManager.create(deployer.address, token.address, configHash, initAgentIds, agentParams, maxThreshold);

                // Try to update a service with at least one slot being non zero and its corresponding bond being a zero
                errAgentIds = [1, 2, 3];
                errAgentParams = [[1, regBond], [1, 0], [1, regBond]];
                const errThreshold = errAgentParams[0][0] + errAgentParams[1][0] + errAgentParams[2][0];
                await expect(
                    serviceManager.update(token.address, configHash, errAgentIds, errAgentParams, errThreshold, serviceIds[0])
                ).to.be.revertedWithCustomError(serviceManager, "ZeroValue");

                // Construct correct values for the service update
                const newAgentIds = [1, 2, 3];
                const newAgentParams = [[1, regBond], [1, regBond],  [0, 0]];
                const newMaxThreshold = newAgentParams[0][0] + newAgentParams[1][0];

                // Update a service with the ERC20 token bond
                await serviceManager.update(token.address, configHash, newAgentIds, newAgentParams, newMaxThreshold, serviceIds[0]);
                // Approve token for the serviceRegistryTokenUtility contract
                await token.connect(deployer).approve(serviceRegistryTokenUtility.address, regBond);

                // Activate the registration
                await serviceManager.connect(deployer).activateRegistration(serviceIds[0], {value: 1});
                let service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(2);

                // Set the operator whitelist checker contract
                // Whitelist a random operator address for the service
                await operatorWhitelist.setOperatorsStatuses(serviceIds[0], [signers[15].address], [true], true);
                // Try to register agents with the non-whitelited operator address
                await expect(
                    serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstances[0], agentInstances[1]],
                        agentIds, {value: 2})
                ).to.be.revertedWithCustomError(serviceManager, "WrongOperator");

                // Whitelist a correct operator address
                await operatorWhitelist.setOperatorsStatuses(serviceIds[0], [operator.address], [true], true);
                // Try to register agents without the approve from the operator
                await expect(
                    serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstances[0], agentInstances[1]],
                        agentIds, {value: 2})
                ).to.be.revertedWithCustomError(serviceManager, "IncorrectAgentBondingValue");

                // Approve token for the serviceRegistryTokenUtility contract by the operator
                await token.mint(operator.address, 2 * regBond);
                await token.connect(operator).approve(serviceRegistryTokenUtility.address, 2 * regBond);
                // Registering agents for the service Id
                await serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstances[0], agentInstances[1]],
                    agentIds, {value: 2*regBond});
                service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(3);

                // Whitelist gnosis multisig implementation
                await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
                // Deploying the service
                await serviceManager.connect(deployer).deploy(serviceIds[0], gnosisSafeMultisig.address, payload);
                service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(4);

                // Terminate the service
                await serviceManager.connect(deployer).terminate(serviceIds[0]);
                service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(5);

                // Unbond agent instances
                await serviceManager.connect(operator).unbond(serviceIds[0]);
                service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(1);
            });

            it("Creating a service with a custom token, register agent instances and slash", async function () {
                // Choose the service registry implementation: L1 or L2
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    serviceManager = serviceManagerL2;
                    serviceRegistryTokenUtility = serviceRegistryTokenUtilityL2;
                }

                const manager = signers[4];
                const owner = signers[5];
                const operator = signers[6];
                const agentInstance = signers[7];

                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(manager.address);
                    // Creating 3 canonical agents
                    await agentRegistry.connect(manager).create(owner.address, unitHash, [1]);
                    await agentRegistry.connect(manager).create(owner.address, unitHash1, [1]);
                    await agentRegistry.connect(manager).create(owner.address, unitHash2, [1]);
                }

                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistryTokenUtility.changeManager(serviceManager.address);

                const newAgentIds = [1];
                const newAgentParams = [[1, regBond]];

                // Remove the operator whitelist check completely
                serviceManager.connect(deployer).setOperatorWhitelist(AddressZero);

                // Creating one service with the ERC20 token bond
                await serviceManager.create(deployer.address, token.address, configHash, newAgentIds, newAgentParams, threshold);
                // Approve token for the serviceRegistryTokenUtility contract
                await token.connect(deployer).approve(serviceRegistryTokenUtility.address, regBond);

                // Activate the registration
                await serviceManager.connect(deployer).activateRegistration(serviceIds[0], {value: 1});
                let service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(2);

                // Approve token for the serviceRegistryTokenUtility contract by the operator
                await token.mint(operator.address, regBond);
                await token.connect(operator).approve(serviceRegistryTokenUtility.address, regBond);
                // Registering agents for the service Id
                await serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstance.address],
                    newAgentIds, {value: regBond});
                service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(3);

                // Whitelist gnosis multisig implementation
                await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
                // Deploying the service
                const safe = await serviceManager.connect(deployer).deploy(serviceIds[0], gnosisSafeMultisig.address, payload);
                const result = await safe.wait();
                const proxyAddress = result.events[0].address;
                service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(4);

                // Check initial operator's balance
                const balanceOperator = Number(await serviceRegistryTokenUtility.getOperatorBalance(operator.address, serviceIds[0]));
                expect(balanceOperator).to.equal(regBond);

                // Get all the necessary info about multisig and slash the operator
                const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);
                const safeContracts = require("@gnosis.pm/safe-contracts");
                const nonce = await multisig.nonce();
                const txHashData = await safeContracts.buildContractCall(serviceRegistryTokenUtility, "slash",
                    [[agentInstance.address], [regFine], serviceIds[0]], nonce, 0, 0);
                const signMessageData = await safeContracts.safeSignMessage(agentInstance, multisig, txHashData, 0);

                // Slash the agent instance operator with the correct multisig
                await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

                // Check the new operator's balance, it must be the original balance minus the fine
                const newBalanceOperator = Number(await serviceRegistryTokenUtility.getOperatorBalance(operator.address, serviceIds[0]));
                expect(newBalanceOperator).to.equal(balanceOperator - regFine);

                // Terminate the service
                await serviceManager.connect(deployer).terminate(serviceIds[0]);
                service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(5);

                // Unbond agent instances
                await serviceManager.connect(operator).unbond(serviceIds[0]);
                service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(1);

                // Check the balance of the operator that has to correspond the balance after slashing
                const balance = Number(await token.balanceOf(operator.address));
                expect(newBalanceOperator).to.equal(balance);

                // Set drainer and drain funds
                const balanceBefore = Number(await token.balanceOf(deployer.address));
                await serviceRegistryTokenUtility.changeDrainer(deployer.address);
                await serviceRegistryTokenUtility.connect(deployer).drain(token.address);
                const balanceAfter = Number(await token.balanceOf(deployer.address));
                expect(balanceAfter).to.equal(balanceBefore + regFine);
            });

            it("Creating services, updating one of them, activating, registering agent instances", async function () {
                // Choose the service registry implementation: L1 or L2
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    serviceManager = serviceManagerL2;
                    serviceRegistryTokenUtility = serviceRegistryTokenUtilityL2;
                }

                const manager = signers[4];
                const owner = signers[5];
                const operator = signers[6];
                const agentInstances = [signers[7].address, signers[8].address, signers[9].address, signers[10].address];

                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(manager.address);
                    // Creating 3 canonical agents
                    await agentRegistry.connect(manager).create(owner.address, unitHash, [1]);
                    await agentRegistry.connect(manager).create(owner.address, unitHash1, [1]);
                    await agentRegistry.connect(manager).create(owner.address, unitHash2, [1]);
                }

                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistryTokenUtility.changeManager(serviceManager.address);

                // Creating two services
                await serviceManager.create(owner.address, ETHAddress, configHash, agentIds, agentParams,
                    maxThreshold);
                await serviceManager.create(owner.address, ETHAddress, configHash, agentIds, agentParams,
                    maxThreshold);

                // Updating service Id == 1
                const newAgentIds = [1, 2, 3];
                const newAgentParams = [[2, regBond], [0, regBond], [1, regBond]];
                const newMaxThreshold = newAgentParams[0][0] + newAgentParams[2][0];
                await serviceManager.connect(owner).update(ETHAddress, configHash, newAgentIds,
                    newAgentParams, newMaxThreshold, serviceIds[0]);
                let service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(1);

                // Activate the registration
                await serviceManager.connect(owner).activateRegistration(serviceIds[0], {value: regDeposit});
                await serviceManager.connect(owner).activateRegistration(serviceIds[1], {value: regDeposit});
                service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(2);

                // Fail when trying to update the service again, even though no agent instances are registered yet
                await expect(
                    serviceManager.connect(owner).update(ETHAddress, configHash, newAgentIds,
                        newAgentParams, newMaxThreshold, serviceIds[0])
                ).to.be.revertedWithCustomError(serviceManager, "WrongServiceState");

                // Registering agents for service Id == 1
                await serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstances[0], agentInstances[2]],
                    [newAgentIds[0], newAgentIds[0]], {value: 2*regBond});
                // After the update, service has only 2 slots for canonical agent 1 and 1 slot for canonical agent 3
                await expect(
                    serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstances[3]], [newAgentIds[0]], {value: regBond})
                ).to.be.revertedWithCustomError(serviceManager, "AgentInstancesSlotsFilled");
                // Registering agent instance for the last possible slot
                await serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstances[1]],
                    [newAgentIds[2]], {value: regBond});
                // Now all slots are filled and the service cannot register more agent instances
                await expect(
                    serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstances[3]], [newAgentIds[2]], {value: regBond})
                ).to.be.revertedWithCustomError(serviceManager, "WrongServiceState");

                // When terminated, no agent instance registration is possible
                await serviceManager.connect(owner).terminate(serviceIds[1]);
                const newAgentInstance = signers[11].address;
                await expect(
                    serviceManager.connect(operator).registerAgents(serviceIds[1], [newAgentInstance], [agentIds[0]], {value: regBond})
                ).to.be.revertedWithCustomError(serviceManager, "WrongServiceState");

                expect(await serviceRegistry.exists(2)).to.equal(true);
                expect(await serviceRegistry.exists(3)).to.equal(false);
            });

            it("Should fail when updating a service with zero bonds and non-zero slots", async function () {
                // Choose the service registry implementation: L1 or L2
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    serviceManager = serviceManagerL2;
                    serviceRegistryTokenUtility = serviceRegistryTokenUtilityL2;
                }

                const manager = signers[4];
                const owner = signers[5];

                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(manager.address);
                    // Creating 3 canonical agents
                    await agentRegistry.connect(manager).create(owner.address, unitHash, [1]);
                    await agentRegistry.connect(manager).create(owner.address, unitHash1, [1]);
                    await agentRegistry.connect(manager).create(owner.address, unitHash2, [1]);
                }

                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistryTokenUtility.changeManager(serviceManager.address);

                // Creating a service
                await serviceManager.create(owner.address, ETHAddress, configHash, agentIds, agentParams, maxThreshold);

                // Updating service Id == 1
                const newAgentIds = [1, 2, 3];
                const newAgentParams = [[2, regBond], [0, regBond], [1, 0]];
                const newMaxThreshold = newAgentParams[0][0] + newAgentParams[2][0];
                // Try to update a service with the non-zero slot and a zero bond
                await expect(
                    serviceManager.connect(owner).update(ETHAddress, configHash, newAgentIds, newAgentParams,
                        newMaxThreshold, serviceIds[0])
                ).to.be.revertedWithCustomError(serviceManager, "ZeroValue");
            });

            it("Creating a service, registering agent instances from different operators, calling Safe", async function () {
                // Choose the service registry implementation: L1 or L2
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    serviceManager = serviceManagerL2;
                    serviceRegistryTokenUtility = serviceRegistryTokenUtilityL2;
                }

                const manager = signers[4];
                const owner = signers[5];
                const operators = [signers[6], signers[7]];
                const agentInstances = [signers[8].address, signers[9].address, signers[10].address, signers[11].address];

                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(manager.address);
                    // Creating 2 canonical agents
                    await agentRegistry.connect(manager).create(owner.address, unitHash, [1]);
                    await agentRegistry.connect(manager).create(owner.address, unitHash1, [1]);
                }

                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistryTokenUtility.changeManager(serviceManager.address);

                // Creating a service
                const newAgentIds = [1, 2];
                const newAgentParams = [[2, regBond], [1, regBond]];
                const newMaxThreshold = newAgentParams[0][0] + newAgentParams[1][0];
                await serviceManager.create(owner.address, ETHAddress, configHash, newAgentIds,
                    newAgentParams, newMaxThreshold);
                await serviceManager.connect(owner).activateRegistration(serviceIds[0], {value: regDeposit});

                // Registering agents for service Id == 1
                await serviceManager.connect(operators[0]).registerAgents(serviceIds[0], [agentInstances[0], agentInstances[1]],
                    [newAgentIds[0], newAgentIds[1]], {value: 2*regBond});

                // Whitelist gnosis multisig implementation
                await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

                // Safe is not possible without all the registered agent instances
                await expect(
                    serviceManager.connect(owner).deploy(serviceIds[0], gnosisSafeMultisig.address, payload)
                ).to.be.revertedWithCustomError(serviceManager, "WrongServiceState");
                // Registering the final agent instance
                await serviceManager.connect(operators[0]).registerAgents(serviceIds[0], [agentInstances[2]],
                    [newAgentIds[0]], {value: regBond});

                // Check that neither of operators can register the agent after all slots have been filled
                await expect(
                    serviceManager.connect(operators[0]).registerAgents(serviceIds[0], [agentInstances[3]],
                        [newAgentIds[0]], {value: regBond})
                ).to.be.revertedWithCustomError(serviceManager, "WrongServiceState");
                await expect(
                    serviceManager.connect(operators[1]).registerAgents(serviceIds[0], [agentInstances[3]],
                        [newAgentIds[1]], {value: regBond})
                ).to.be.revertedWithCustomError(serviceManager, "WrongServiceState");

                // Creating Safe with blanc safe parameters for the test
                const safe = await serviceManager.connect(owner).deploy(serviceIds[0], gnosisSafeMultisig.address, payload);
                const result = await safe.wait();
                const proxyAddress = result.events[0].address;

                // Verify the deployment of the created Safe: checking threshold and owners
                const proxyContract = await ethers.getContractAt("GnosisSafe", proxyAddress);
                if (await proxyContract.getThreshold() != newMaxThreshold) {
                    throw new Error("incorrect threshold");
                }
                const actualAgentInstances = [agentInstances[0], agentInstances[1], agentInstances[2]];
                for (const aInstance of actualAgentInstances) {
                    const isOwner = await proxyContract.isOwner(aInstance);
                    if (!isOwner) {
                        throw new Error("incorrect agent instance");
                    }
                }
            });

            it("Creating services, getting resulting information", async function () {
                // Choose the service registry implementation: L1 or L2
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    serviceManager = serviceManagerL2;
                    serviceRegistryTokenUtility = serviceRegistryTokenUtilityL2;
                }

                const manager = signers[4];
                const sigOwner = signers[5];
                const owner = signers[5].address;

                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(manager.address);
                    // Creating 2 canonical agents
                    await agentRegistry.connect(manager).create(owner, unitHash, [1]);
                    await agentRegistry.connect(manager).create(owner, unitHash1, [1]);
                }

                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistryTokenUtility.changeManager(serviceManager.address);

                // Creating two services
                await serviceManager.create(owner, ETHAddress, configHash, agentIds, agentParams,
                    maxThreshold);
                await serviceManager.create(owner, ETHAddress, configHash, agentIds, agentParams,
                    maxThreshold);

                // Initial checks
                // Total supply must be 2
                let totalSupply = await serviceRegistry.totalSupply();
                expect(totalSupply).to.equal(2);
                // Balance of owner is 2, each service id belongs to the owner
                expect(await serviceRegistry.balanceOf(owner)).to.equal(2);
                expect(await serviceRegistry.ownerOf(serviceIds[0])).to.equal(owner);
                expect(await serviceRegistry.ownerOf(serviceIds[1])).to.equal(owner);
                // Getting the set of service Ids of the owner
                let serviceIdsRet = await serviceRegistry.balanceOf(owner);
                for (let i = 0; i < serviceIdsRet; i++) {
                    const serviceIdCheck = await serviceRegistry.tokenByIndex(i);
                    expect(serviceIdCheck).to.be.equal(i + 1);
                }

                // Activate registration and terminate the very first service and destroy it
                await serviceManager.connect(sigOwner).activateRegistration(serviceIds[0], {value: regDeposit});
                await serviceManager.connect(sigOwner).terminate(serviceIds[0]);

                // Check for the information consistency
                totalSupply = await serviceRegistry.totalSupply();
                expect(totalSupply).to.equal(2);
                // Balance of owner is 1, only service Id 2 belongs to the owner
                expect(await serviceRegistry.balanceOf(owner)).to.equal(2);
                expect(await serviceRegistry.exists(serviceIds[0])).to.equal(true);
                expect(await serviceRegistry.exists(serviceIds[1])).to.equal(true);
                expect(await serviceRegistry.ownerOf(serviceIds[0])).to.equal(owner);
                expect(await serviceRegistry.ownerOf(serviceIds[1])).to.equal(owner);
                // Getting the set of service Ids of the owner, must be service Id 2 only
                serviceIdsRet = await serviceRegistry.balanceOf(owner);
                expect(serviceIdsRet).to.equal(2);
                expect(await serviceRegistry.tokenByIndex(0)).to.equal(1);
                expect(await serviceRegistry.tokenByIndex(1)).to.equal(2);
            });

            it("Terminated service is unbonded", async function () {
                // Choose the service registry implementation: L1 or L2
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    serviceManager = serviceManagerL2;
                    serviceRegistryTokenUtility = serviceRegistryTokenUtilityL2;
                }

                const mechManager = signers[3];
                const owner = signers[4];
                const operator = signers[5];
                const agentInstances = [signers[6].address, signers[7].address];
                const maxThreshold = 2;

                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(mechManager.address);
                    await agentRegistry.connect(mechManager).create(owner.address, unitHash, [1]);
                    await agentRegistry.connect(mechManager).create(owner.address, unitHash1, [1]);
                }

                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistryTokenUtility.changeManager(serviceManager.address);
                await serviceManager.connect(owner).create(owner.address, ETHAddress, configHash, [agentIds[0]],
                    [[maxThreshold, regBond]], maxThreshold);

                // Activate agent instance registration and register an agent instance
                await serviceManager.connect(owner).activateRegistration(serviceIds[0], {value: regDeposit});
                await serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstances[0]],
                    [agentIds[0]], {value: regBond});

                // Try to unbond when service is still in active registration
                await expect(
                    serviceManager.connect(operator).unbond(serviceIds[0])
                ).to.be.revertedWithCustomError(serviceManager, "WrongServiceState");

                // Registering the remaining agent instance
                await serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstances[1]],
                    [agentIds[0]], {value: regBond});

                // Terminate the service before it's deployed
                await serviceManager.connect(owner).terminate(serviceIds[0]);
                let service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(5);

                // Unbond agent instances. Since all the agents will eb unbonded, the service state is terminated-unbonded
                await serviceManager.connect(operator).unbond(serviceIds[0]);
                service = await serviceRegistry.getService(serviceIds[0]);
                expect(service.state).to.equal(1);
            });

            it("Update the terminated service without registered agent instances", async function () {
                // Choose the service registry implementation: L1 or L2
                if (serviceRegistryImplementation == "l2") {
                    serviceRegistry = serviceRegistryL2;
                    serviceManager = serviceManagerL2;
                    serviceRegistryTokenUtility = serviceRegistryTokenUtilityL2;
                }

                const manager = signers[4];
                const owner = signers[5];

                if (serviceRegistryImplementation == "l1") {
                    await agentRegistry.changeManager(manager.address);
                    await agentRegistry.connect(manager).create(owner.address, unitHash, [1]);
                    await agentRegistry.connect(manager).create(owner.address, unitHash1, [1]);
                    await agentRegistry.connect(manager).create(owner.address, unitHash2, [1]);
                }

                await serviceRegistry.changeManager(serviceManager.address);
                await serviceRegistryTokenUtility.changeManager(serviceManager.address);
                await serviceManager.create(owner.address, ETHAddress, configHash, agentIds, agentParams,
                    maxThreshold);
                await serviceManager.create(owner.address, ETHAddress, configHash, agentIds, agentParams,
                    maxThreshold);
                await serviceManager.connect(owner).activateRegistration(serviceIds[0], {value: regDeposit});
                await serviceManager.connect(owner).terminate(serviceIds[0]);
                await serviceManager.connect(owner).update(ETHAddress, configHash, [1, 2, 3],
                    [[3, regBond], [0, regBond], [4, regBond]], maxThreshold, serviceIds[0]);
            });
        });
    });

    context("Manipulations with payable set of functions or balance-related", async function () {
        it("Create a service, then deploy, slash, unbond", async function () {
            const manager = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstance = signers[7];
            await agentRegistry.changeManager(manager.address);

            // Creating 2 canonical agents
            await agentRegistry.connect(manager).create(owner.address, unitHash, [1]);
            await agentRegistry.connect(manager).create(owner.address, unitHash1, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistryTokenUtility.changeManager(serviceManager.address);

            // Creating a service and activating registration
            await serviceManager.create(owner.address, ETHAddress, configHash, [1], [[1, regBond]], 1);
            await serviceManager.connect(owner).activateRegistration(serviceIds[0], {value: regDeposit});

            // Registering agent instance
            await serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstance.address],
                [agentIds[0]], {value: regBond});

            // Check the contract's initial balance
            const expectedContractBalance = regBond + regDeposit;
            const contractBalance = Number(await ethers.provider.getBalance(serviceRegistry.address));
            expect(contractBalance).to.equal(expectedContractBalance);

            // Whitelist gnosis multisig implementation
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

            // Create multisig
            const safe = await serviceManager.connect(owner).deploy(serviceIds[0], gnosisSafeMultisig.address, payload);
            const result = await safe.wait();
            const proxyAddress = result.events[0].address;

            // Check initial operator's balance
            const balanceOperator = Number(await serviceRegistry.getOperatorBalance(operator.address, serviceIds[0]));
            expect(balanceOperator).to.equal(regBond);

            // Get all the necessary info about multisig and slash the operator
            const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);
            const safeContracts = require("@gnosis.pm/safe-contracts");
            const nonce = await multisig.nonce();
            const txHashData = await safeContracts.buildContractCall(serviceRegistry, "slash",
                [[agentInstance.address], [regFine], serviceIds[0]], nonce, 0, 0);
            const signMessageData = await safeContracts.safeSignMessage(agentInstance, multisig, txHashData, 0);

            // Slash the agent instance operator with the correct multisig
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Check the new operator's balance, it must be the original balance minus the fine
            const newBalanceOperator = Number(await serviceRegistry.getOperatorBalance(operator.address, serviceIds[0]));
            expect(newBalanceOperator).to.equal(balanceOperator - regFine);

            // Terminate service and unbond the operator
            await serviceManager.connect(owner).terminate(serviceIds[0]);
            // Use the static call first that emulates the call, to get the return value of a refund
            const unbond = await serviceManager.connect(operator).callStatic.unbond(serviceIds[0]);
            // The refund for unbonding is the bond minus the fine
            expect(Number(unbond.refund)).to.equal(balanceOperator - regFine);

            // Do the real unbond call
            await serviceManager.connect(operator).unbond(serviceIds[0]);

            // Check the balance of the contract - it must be the total minus the slashed fine minus the deposit
            const newContractBalance = Number(await ethers.provider.getBalance(serviceRegistry.address));
            expect(newContractBalance).to.equal(contractBalance - regFine - regDeposit);
        });
    });

    context("Contract transfers", async function () {
        it("Should fail when sending funds directly to the contract", async function () {
            await expect(
                signers[0].sendTransaction({to: serviceManager.address, value: ethers.utils.parseEther("1000"), data: "0x12"})
            ).to.be.reverted;
        });
    });

    context("Attacks", async function () {
        it("Reentrancy during a drain function", async function () {
            const manager = signers[4];
            const owner = signers[5];
            const operator = signers[6];
            const agentInstance = signers[7];
            await agentRegistry.changeManager(manager.address);

            // Creating 3 canonical agents
            await agentRegistry.connect(manager).create(owner.address, unitHash, [1]);
            await agentRegistry.connect(manager).create(owner.address, unitHash1, [1]);
            await agentRegistry.connect(manager).create(owner.address, unitHash2, [1]);
            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistryTokenUtility.changeManager(serviceManager.address);

            const newAgentIds = [1];
            const newAgentParams = [[1, regBond]];

            // Remove the operator whitelist check completely
            serviceManager.connect(deployer).setOperatorWhitelist(AddressZero);

            // Creating one service with the ERC20 token bond
            await serviceManager.create(deployer.address, reentrancyAttacker.address, configHash, newAgentIds, newAgentParams, threshold);

            // Activate the registration
            await serviceManager.connect(deployer).activateRegistration(serviceIds[0], {value: 1});
            let service = await serviceRegistry.getService(serviceIds[0]);
            expect(service.state).to.equal(2);

            // Registering agents for the service Id
            await serviceManager.connect(operator).registerAgents(serviceIds[0], [agentInstance.address],
                newAgentIds, {value: regBond});
            service = await serviceRegistry.getService(serviceIds[0]);
            expect(service.state).to.equal(3);

            // Whitelist gnosis multisig implementation
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
            // Deploying the service
            const safe = await serviceManager.connect(deployer).deploy(serviceIds[0], gnosisSafeMultisig.address, payload);
            const result = await safe.wait();
            const proxyAddress = result.events[0].address;
            service = await serviceRegistry.getService(serviceIds[0]);
            expect(service.state).to.equal(4);

            // Check initial operator's balance
            const balanceOperator = Number(await serviceRegistryTokenUtility.getOperatorBalance(operator.address, serviceIds[0]));
            expect(balanceOperator).to.equal(regBond);

            // Get all the necessary info about multisig and slash the operator
            const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);
            const safeContracts = require("@gnosis.pm/safe-contracts");
            const nonce = await multisig.nonce();
            const txHashData = await safeContracts.buildContractCall(serviceRegistryTokenUtility, "slash",
                [[agentInstance.address], [regFine], serviceIds[0]], nonce, 0, 0);
            const signMessageData = await safeContracts.safeSignMessage(agentInstance, multisig, txHashData, 0);

            // Slash the agent instance operator with the correct multisig
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Check the new operator's balance, it must be the original balance minus the fine
            const newBalanceOperator = Number(await serviceRegistryTokenUtility.getOperatorBalance(operator.address, serviceIds[0]));
            expect(newBalanceOperator).to.equal(balanceOperator - regFine);

            // Terminate the service
            await serviceManager.connect(deployer).terminate(serviceIds[0]);
            service = await serviceRegistry.getService(serviceIds[0]);
            expect(service.state).to.equal(5);

            // Unbond agent instances
            await serviceManager.connect(operator).unbond(serviceIds[0]);
            service = await serviceRegistry.getService(serviceIds[0]);
            expect(service.state).to.equal(1);

            // Set the reentrancy attack on agent instances unbond
            await reentrancyAttacker.setAttackState(9);
            await serviceRegistryTokenUtility.changeDrainer(deployer.address);
            // Try to terminate the service
            await expect(
                serviceRegistryTokenUtility.drain(reentrancyAttacker.address)
            ).to.be.reverted;
        });
    });
});

