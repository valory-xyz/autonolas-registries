/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

// ServiceManager.update removes the service agent Ids omitted from the new set, so no parameters of an omitted
// agent Id remain to be registered against. Run against both ServiceRegistry and ServiceRegistryL2.
for (const registryKind of ["ServiceRegistry", "ServiceRegistryL2"]) {
    describe(`ServiceManager update with omitted agent Ids (${registryKind})`, function () {
        const defaultHash = "0x" + "5".repeat(64);
        const regBond = 1000;
        const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
        const payload = "0x";
        const maxDeadline = ethers.constants.MaxUint256;
        const EIP712_REGISTER_AGENTS_TX_TYPE = {
            RegisterAgents: [
                { type: "address", name: "operator" },
                { type: "address", name: "serviceOwner" },
                { type: "uint256", name: "serviceId" },
                { type: "address[]", name: "agentInstances" },
                { type: "uint32[]", name: "agentIds" },
                { type: "address", name: "bondToken" },
                { type: "uint256", name: "maxBond" },
                { type: "uint256", name: "deadline" },
                { type: "uint256", name: "nonce" },
            ]
        };
        const ServiceState = { PreRegistration: 1, ActiveRegistration: 2, FinishedRegistration: 3, Deployed: 4 };

        let signers;
        let deployer;
        let operator;
        let serviceOwner;
        let serviceRegistry;
        let serviceRegistryTokenUtility;
        let serviceManager;
        let gnosisSafeMultisig;
        let token;
        let nextInstance;

        beforeEach(async function () {
            signers = await ethers.getSigners();
            deployer = signers[0];
            operator = signers[1];
            serviceOwner = signers[2];
            nextInstance = 3;

            if (registryKind == "ServiceRegistry") {
                const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
                const componentRegistry = await ComponentRegistry.deploy("components", "COMP", "https://localhost/c/");
                const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
                const agentRegistry = await AgentRegistry.deploy("agents", "AGENT", "https://localhost/a/",
                    componentRegistry.address);
                await componentRegistry.changeManager(deployer.address);
                await agentRegistry.changeManager(deployer.address);
                await componentRegistry.create(deployer.address, defaultHash, []);
                // Agent Ids 1..6
                for (let i = 0; i < 6; i++) {
                    await agentRegistry.create(deployer.address, defaultHash, [1]);
                }
                const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
                serviceRegistry = await ServiceRegistry.deploy("services", "SERVICE", "https://localhost/s/",
                    agentRegistry.address);
            } else {
                const ServiceRegistryL2 = await ethers.getContractFactory("ServiceRegistryL2");
                serviceRegistry = await ServiceRegistryL2.deploy("services", "SERVICE", "https://localhost/s/");
            }
            await serviceRegistry.deployed();

            const ServiceRegistryTokenUtility = await ethers.getContractFactory("ServiceRegistryTokenUtility");
            serviceRegistryTokenUtility = await ServiceRegistryTokenUtility.deploy(serviceRegistry.address);
            await serviceRegistryTokenUtility.deployed();

            const ServiceManager = await ethers.getContractFactory("ServiceManager");
            const implementation = await ServiceManager.deploy(serviceRegistry.address,
                serviceRegistryTokenUtility.address);
            const ServiceManagerProxy = await ethers.getContractFactory("ServiceManagerProxy");
            const proxy = await ServiceManagerProxy.deploy(implementation.address,
                implementation.interface.encodeFunctionData("initialize", []));
            serviceManager = await ethers.getContractAt("ServiceManager", proxy.address);

            await serviceRegistry.changeManager(serviceManager.address);
            await serviceRegistryTokenUtility.changeManager(serviceManager.address);

            const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
            const gnosisSafe = await GnosisSafe.deploy();
            const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
            const gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
            const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
            gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafe.address, gnosisSafeProxyFactory.address);
            await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

            const Token = await ethers.getContractFactory("ERC20Token");
            token = await Token.deploy();
            await token.deployed();
            const initSupply = "1" + "0".repeat(20);
            for (const account of [operator, serviceOwner]) {
                await token.mint(account.address, initSupply);
                await token.connect(account).approve(serviceRegistryTokenUtility.address, initSupply);
            }
        });

        function agentParams(slotsList, bond = regBond) {
            return slotsList.map((slots) => [slots, bond]);
        }

        function instances(n) {
            const out = signers.slice(nextInstance, nextInstance + n).map((signer) => signer.address);
            nextInstance += n;
            return out;
        }

        function serviceAgentKey(serviceId, agentId) {
            return ethers.BigNumber.from(serviceId).or(ethers.BigNumber.from(agentId).shl(32));
        }

        async function registryParams(serviceId, agentId) {
            return serviceRegistry.mapServiceAndAgentIdAgentParams(serviceAgentKey(serviceId, agentId));
        }

        async function create(bondToken, agentIds, slotsList) {
            const threshold = slotsList.reduce((sum, slots) => sum + slots, 0);
            await serviceManager.create(serviceOwner.address, bondToken, defaultHash, agentIds, agentParams(slotsList),
                threshold);
            return serviceRegistry.totalSupply();
        }

        function update(bondToken, agentIds, slotsList, serviceId) {
            const threshold = slotsList.reduce((sum, slots) => sum + slots, 0);
            return serviceManager.connect(serviceOwner).update(bondToken, defaultHash, agentIds,
                agentParams(slotsList), threshold, serviceId);
        }

        async function activate(serviceId, bondToken) {
            await serviceManager.connect(serviceOwner).activateRegistration(serviceId,
                {value: bondToken == ETHAddress ? regBond : 1});
        }

        function registerValue(bondToken, n) {
            return bondToken == ETHAddress ? regBond * n : n;
        }

        async function signedRegistration(serviceId, agentInstances, agentIds, bondToken, maxBond) {
            const message = { operator: operator.address, serviceOwner: serviceOwner.address, serviceId: serviceId,
                agentInstances: agentInstances, agentIds: agentIds, bondToken: bondToken, maxBond: maxBond,
                deadline: maxDeadline,
                nonce: await serviceManager.getOperatorRegisterAgentsNonce(operator.address, serviceId) };
            const domain = { name: await serviceManager.NAME(), version: await serviceManager.VERSION(),
                chainId: (await ethers.provider.getNetwork()).chainId, verifyingContract: serviceManager.address };
            return operator._signTypedData(domain, EIP712_REGISTER_AGENTS_TX_TYPE, message);
        }

        // Token balance, token-utility allowance and ETH balance of the operator
        async function operatorFunds() {
            return [await token.balanceOf(operator.address),
                await token.allowance(operator.address, serviceRegistryTokenUtility.address),
                await ethers.provider.getBalance(operator.address)];
        }

        // Registration under an omitted agent Id is rejected by the registry on both paths. Allowance and signed cap
        // are sufficient, so the registry check is the one reached; any token transfer is rolled back.
        async function expectOmittedRejected(serviceId, omittedId, bondToken) {
            const agentInstances = instances(1);
            const value = registerValue(bondToken, 1);
            const before = await operatorFunds();
            await expect(serviceManager.connect(operator).registerAgents(serviceId, agentInstances, [omittedId],
                {value: value})).to.be.revertedWithCustomError(serviceRegistry, "AgentNotInService")
                .withArgs(omittedId, serviceId);

            const maxBond = ethers.constants.MaxUint256;
            const signature = await signedRegistration(serviceId, agentInstances, [omittedId], bondToken, maxBond);
            await expect(serviceManager.connect(serviceOwner).registerAgentsWithSignature(operator.address, serviceId,
                agentInstances, [omittedId], bondToken, maxBond, maxDeadline, signature, {value: value}))
                .to.be.revertedWithCustomError(serviceRegistry, "AgentNotInService").withArgs(omittedId, serviceId);

            const after = await operatorFunds();
            expect(after[0]).to.equal(before[0], "no net token debit");
            expect(after[1]).to.equal(before[1], "no allowance consumed");
            // ETH: only the gas of the direct attempt, which the operator sent
            expect(before[2].sub(after[2])).to.be.lt(ethers.utils.parseEther("0.01"));
        }

        // Retained agents register at the expected bond, and the service deploys
        async function registerRetainedAndDeploy(serviceId, retainedIds, slotsList, bondToken) {
            const agentIds = [];
            retainedIds.forEach((id, i) => agentIds.push(...new Array(slotsList[i]).fill(id)));
            const agentInstances = instances(agentIds.length);
            const tokenBefore = await token.balanceOf(operator.address);
            await serviceManager.connect(operator).registerAgents(serviceId, agentInstances, agentIds,
                {value: registerValue(bondToken, agentIds.length)});
            if (bondToken != ETHAddress) {
                expect(tokenBefore.sub(await token.balanceOf(operator.address))).to.equal(regBond * agentIds.length,
                    "token bond of the retained agents");
            }
            expect((await serviceRegistry.getService(serviceId)).state).to.equal(ServiceState.FinishedRegistration);
            await serviceManager.connect(serviceOwner).deploy(serviceId, gnosisSafeMultisig.address, payload);
            expect((await serviceRegistry.getService(serviceId)).state).to.equal(ServiceState.Deployed);
        }

        context("Omitted agent Ids are removed", async function () {
            for (const bondToken of [ETHAddress, "token"]) {
                const label = bondToken == ETHAddress ? "native" : "ERC20";

                it(`${label}: an omitted agent Id is cleared and cannot be registered; retained agents deploy`,
                    async function () {
                        const tokenAddress = bondToken == ETHAddress ? ETHAddress : token.address;
                        const serviceId = await create(tokenAddress, [1, 2], [1, 1]);
                        await update(tokenAddress, [2], [2], serviceId);

                        const params = await registryParams(serviceId, 1);
                        expect(params.slots).to.equal(0);
                        expect(params.bond).to.equal(0);
                        const service = await serviceRegistry.getService(serviceId);
                        expect(service.agentIds).to.deep.equal([2]);
                        expect(service.maxNumAgentInstances).to.equal(2);

                        await activate(serviceId, tokenAddress);
                        await expectOmittedRejected(serviceId, 1, tokenAddress);
                        await registerRetainedAndDeploy(serviceId, [2], [2], tokenAddress);
                    });
            }

            it("Interleaved sets merge in ascending order", async function () {
                const serviceId = await create(ETHAddress, [1, 3, 5], [1, 1, 1]);
                await update(ETHAddress, [2, 4], [1, 2], serviceId);

                const service = await serviceRegistry.getService(serviceId);
                expect(service.agentIds).to.deep.equal([2, 4]);
                expect(service.maxNumAgentInstances).to.equal(3);
                for (const omitted of [1, 3, 5]) {
                    expect((await registryParams(serviceId, omitted)).slots).to.equal(0);
                }
                expect((await registryParams(serviceId, 2)).slots).to.equal(1);
                expect((await registryParams(serviceId, 4)).slots).to.equal(2);
            });

            it("An explicit zero-slot removal is kept and not inserted twice", async function () {
                const serviceId = await create(ETHAddress, [1, 2, 3], [1, 1, 1]);
                // 1 removed explicitly, 3 omitted
                await update(ETHAddress, [1, 2], [0, 1], serviceId);

                const service = await serviceRegistry.getService(serviceId);
                expect(service.agentIds).to.deep.equal([2]);
                expect((await registryParams(serviceId, 1)).slots).to.equal(0);
                expect((await registryParams(serviceId, 3)).slots).to.equal(0);
            });

            it("Invalid sets are rejected before the omitted agent Ids are added", async function () {
                const serviceId = await create(ETHAddress, [1, 2, 3], [1, 1, 1]);

                await expect(serviceManager.connect(serviceOwner).update(ETHAddress, defaultHash, [], [], 1, serviceId))
                    .to.be.revertedWithCustomError(serviceManager, "WrongArrayLength").withArgs(0, 0);
                await expect(serviceManager.connect(serviceOwner).update(ETHAddress, defaultHash, [2],
                    agentParams([1, 1]), 1, serviceId))
                    .to.be.revertedWithCustomError(serviceManager, "WrongArrayLength").withArgs(1, 2);
                await expect(update(ETHAddress, [3, 2], [1, 1], serviceId))
                    .to.be.revertedWithCustomError(serviceManager, "WrongAgentId").withArgs(2);
                await expect(update(ETHAddress, [2, 2], [1, 1], serviceId))
                    .to.be.revertedWithCustomError(serviceManager, "WrongAgentId").withArgs(2);
                await expect(update(ETHAddress, [0, 2], [1, 1], serviceId))
                    .to.be.revertedWithCustomError(serviceManager, "WrongAgentId").withArgs(0);
            });
        });

        context("Bond currency changes with an omitted agent Id", async function () {
            it("Native to ERC20: the omitted agent Id is cleared, retained agents register at the token bond",
                async function () {
                    const serviceId = await create(ETHAddress, [1, 2], [1, 1]);
                    await update(token.address, [2], [2], serviceId);

                    expect((await registryParams(serviceId, 1)).slots).to.equal(0);
                    expect((await serviceRegistry.getService(serviceId)).agentIds).to.deep.equal([2]);

                    await activate(serviceId, token.address);
                    await expectOmittedRejected(serviceId, 1, token.address);
                    await registerRetainedAndDeploy(serviceId, [2], [2], token.address);
                });

            it("ERC20 to native: the omitted agent Id is cleared, retained agents register at the native bond",
                async function () {
                    const serviceId = await create(token.address, [1, 2], [1, 1]);
                    await update(ETHAddress, [2], [2], serviceId);

                    expect((await registryParams(serviceId, 1)).slots).to.equal(0);
                    expect((await serviceRegistry.getService(serviceId)).agentIds).to.deep.equal([2]);

                    await activate(serviceId, ETHAddress);
                    await expectOmittedRejected(serviceId, 1, ETHAddress);
                    await registerRetainedAndDeploy(serviceId, [2], [2], ETHAddress);
                });

            it("ERC20 to ERC20: the stale token bond of the omitted agent Id is never netted from the operator",
                async function () {
                    const serviceId = await create(token.address, [1, 2], [1, 1]);
                    await update(token.address, [2], [2], serviceId);

                    // The token utility keeps the old bond record of agent 1; the registry no longer has its params
                    expect(await serviceRegistryTokenUtility.mapServiceAndAgentIdAgentBond(serviceAgentKey(serviceId, 1)))
                        .to.equal(regBond);
                    expect((await registryParams(serviceId, 1)).slots).to.equal(0);

                    await activate(serviceId, token.address);
                    await expectOmittedRejected(serviceId, 1, token.address);
                    await registerRetainedAndDeploy(serviceId, [2], [2], token.address);
                });
        });

        context("Both stuck-service mechanisms of an omitted agent Id are prevented", async function () {
            // Without the fix, registrations under the omitted agent 1 overshoot maxNumAgentInstances, and the strict
            // equality to reach FinishedRegistration never holds again.
            it("Instance count cannot overshoot the maximum", async function () {
                const serviceId = await create(ETHAddress, [1, 2], [2, 1]);
                await update(ETHAddress, [2], [1], serviceId);
                await activate(serviceId, ETHAddress);

                await expect(serviceManager.connect(operator).registerAgents(serviceId, instances(2), [1, 1],
                    {value: regBond * 2})).to.be.revertedWithCustomError(serviceRegistry, "AgentNotInService");
                await registerRetainedAndDeploy(serviceId, [2], [1], ETHAddress);
            });

            // Without the fix, an instance registered under the omitted agent 1 fills the slot capacity, deploy
            // enumerates only the current agent Ids and builds an owner set with a zero address.
            it("Deployment owner set cannot miss an instance", async function () {
                const serviceId = await create(ETHAddress, [1, 2], [1, 2]);
                await update(ETHAddress, [2], [2], serviceId);
                await activate(serviceId, ETHAddress);

                await expect(serviceManager.connect(operator).registerAgents(serviceId, instances(1), [1],
                    {value: regBond})).to.be.revertedWithCustomError(serviceRegistry, "AgentNotInService");
                await registerRetainedAndDeploy(serviceId, [2], [2], ETHAddress);
            });
        });
    });
}
