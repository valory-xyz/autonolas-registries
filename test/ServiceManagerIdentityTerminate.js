/*global describe, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const safeContracts = require("@gnosis.pm/safe-contracts");

// Termination clears the multisig link to the service 8004 agent Id and unsets the agent wallet, from any state the
// service can be terminated in; unbonding does not involve the bridger; a redeployment links the deployed multisig
// again. Run against both ServiceRegistry and ServiceRegistryL2.
for (const registryKind of ["ServiceRegistry", "ServiceRegistryL2"]) {
    describe(`ServiceManager 8004 identity on termination (${registryKind})`, function () {
        const defaultHash = "0x" + "5".repeat(64);
        const regBond = 1000;
        const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
        const AddressZero = ethers.constants.AddressZero;
        const maxDeadline = ethers.constants.MaxUint256;
        const baseURI = "https://localhost/erc8004/service/";
        const ServiceState = { PreRegistration: 1, ActiveRegistration: 2, FinishedRegistration: 3, Deployed: 4, TerminatedBonded: 5 };
        const EIP712_UNBOND_TX_TYPE = {
            Unbond: [
                { type: "address", name: "operator" },
                { type: "address", name: "serviceOwner" },
                { type: "uint256", name: "serviceId" },
                { type: "uint256", name: "deadline" },
                { type: "uint256", name: "nonce" },
            ]
        };

        let signers;
        let operator;
        let operator2;
        let serviceOwner;
        let serviceRegistry;
        let serviceRegistryTokenUtility;
        let serviceManager;
        let safeMultisigWithRecoveryModule;
        let gnosisSafeSameAddressMultisig;
        let fallbackHandler;
        let signMessageLib;
        let identityRegistry;
        let bridger;
        let token;
        let safeNonce;

        beforeEach(async function () {
            signers = await ethers.getSigners();
            operator = signers[1];
            operator2 = signers[2];
            serviceOwner = signers[3];
            safeNonce = 0;

            if (registryKind == "ServiceRegistry") {
                const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
                const componentRegistry = await ComponentRegistry.deploy("components", "COMP", "https://localhost/c/");
                const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
                const agentRegistry = await AgentRegistry.deploy("agents", "AGENT", "https://localhost/a/",
                    componentRegistry.address);
                await componentRegistry.changeManager(signers[0].address);
                await agentRegistry.changeManager(signers[0].address);
                await componentRegistry.create(signers[0].address, defaultHash, []);
                await agentRegistry.create(signers[0].address, defaultHash, [1]);
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
            const MultiSend = await ethers.getContractFactory("MultiSend");
            const multiSend = await MultiSend.deploy();
            const SignMessageLib = await ethers.getContractFactory("SignMessageLib");
            signMessageLib = await SignMessageLib.deploy();
            const FallbackHandler = await ethers.getContractFactory("CompatibilityFallbackHandler");
            fallbackHandler = await FallbackHandler.deploy();

            const RecoveryModule = await ethers.getContractFactory("RecoveryModule");
            const recoveryModule = await RecoveryModule.deploy(multiSend.address, serviceRegistry.address);
            const SafeMultisigWithRecoveryModule = await ethers.getContractFactory("SafeMultisigWithRecoveryModule");
            safeMultisigWithRecoveryModule = await SafeMultisigWithRecoveryModule.deploy(gnosisSafe.address,
                gnosisSafeProxyFactory.address, recoveryModule.address);

            // Same-address multisig implementation keyed on the Safe proxy bytecode
            const GnosisSafeProxy = await ethers.getContractFactory("GnosisSafeProxy");
            const gnosisSafeProxy = await GnosisSafeProxy.deploy(gnosisSafe.address);
            const proxyHash = ethers.utils.keccak256(await ethers.provider.getCode(gnosisSafeProxy.address));
            const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
            gnosisSafeSameAddressMultisig = await GnosisSafeSameAddressMultisig.deploy(proxyHash, gnosisSafe.address);

            await serviceRegistry.changeMultisigPermission(safeMultisigWithRecoveryModule.address, true);
            await serviceRegistry.changeMultisigPermission(gnosisSafeSameAddressMultisig.address, true);

            const IdentityRegistry = await ethers.getContractFactory("MockIdentityRegistry");
            identityRegistry = await IdentityRegistry.deploy();
            await identityRegistry.initialize();
            const IdentityRegistryBridger = await ethers.getContractFactory("IdentityRegistryBridger");
            const bridgerImplementation = await IdentityRegistryBridger.deploy(identityRegistry.address,
                serviceRegistry.address);
            const IdentityRegistryBridgerProxy = await ethers.getContractFactory("IdentityRegistryBridgerProxy");
            const bridgerProxy = await IdentityRegistryBridgerProxy.deploy(bridgerImplementation.address,
                bridgerImplementation.interface.encodeFunctionData("initialize", [baseURI]));
            bridger = await ethers.getContractAt("IdentityRegistryBridger", bridgerProxy.address);
            await serviceManager.setIdentityRegistryBridger(bridger.address);

            const Token = await ethers.getContractFactory("ERC20Token");
            token = await Token.deploy();
            await token.deployed();
            const initSupply = "1" + "0".repeat(20);
            for (const account of [operator, operator2, serviceOwner]) {
                await token.mint(account.address, initSupply);
                await token.connect(account).approve(serviceRegistryTokenUtility.address, initSupply);
            }
        });

        // Sends transactions as the given address, e.g. a service Safe calling the bridger directly
        async function impersonate(address) {
            await ethers.provider.send("hardhat_impersonateAccount", [address]);
            await ethers.provider.send("hardhat_setBalance", [address, "0x56BC75E2D63100000"]);
            return ethers.getSigner(address);
        }

        // Value sent with activation or with one agent instance registration: the bond, or the token wrapper
        function bondValue(bondToken) {
            return bondToken == ETHAddress ? regBond : 1;
        }

        // Creates a service with one agent instance slot per instance; a threshold of all instances
        async function createService(numInstances, bondToken = ETHAddress) {
            await serviceManager.create(serviceOwner.address, bondToken, defaultHash, [1], [[numInstances, regBond]],
                numInstances);
            return serviceRegistry.totalSupply();
        }

        // Activates registration, registers each instance by its operator
        async function activateAndRegister(serviceId, registrations, bondToken = ETHAddress) {
            await serviceManager.connect(serviceOwner).activateRegistration(serviceId, {value: bondValue(bondToken)});
            for (const [op, instance] of registrations) {
                await serviceManager.connect(op).registerAgents(serviceId, [instance.address], [1],
                    {value: bondValue(bondToken)});
            }
        }

        // Activates registration, registers each instance by its operator and deploys a new Safe
        async function registerAndDeploy(serviceId, registrations, bondToken = ETHAddress) {
            await activateAndRegister(serviceId, registrations, bondToken);
            const payload = ethers.utils.defaultAbiCoder.encode(["address", "uint256"],
                [fallbackHandler.address, safeNonce++]);
            await serviceManager.connect(serviceOwner).deploy(serviceId, safeMultisigWithRecoveryModule.address,
                payload);
            return (await serviceRegistry.mapServices(serviceId)).multisig;
        }

        // Both unbond paths: the operator directly, or the service owner with the operator's signed message
        const unbondPaths = {
            direct: (serviceId, op) => serviceManager.connect(op).unbond(serviceId),
            signed: async (serviceId, op) => {
                const domain = { name: await serviceManager.NAME(), version: await serviceManager.VERSION(),
                    chainId: (await ethers.provider.getNetwork()).chainId, verifyingContract: serviceManager.address };
                const nonce = await serviceManager.getOperatorUnbondNonce(op.address, serviceId);
                const signature = await op._signTypedData(domain, EIP712_UNBOND_TX_TYPE, { operator: op.address,
                    serviceOwner: serviceOwner.address, serviceId, deadline: maxDeadline, nonce });
                return serviceManager.connect(serviceOwner).unbondWithSignature(op.address, serviceId, maxDeadline,
                    signature);
            }
        };

        // Asserts the Safe can still act on the identity through the bridger
        async function expectLinked(safe, agentId) {
            expect(await bridger.mapMultisigAgentIds(safe)).to.equal(agentId);
            const safeSigner = await impersonate(safe);
            await bridger.connect(safeSigner).setMetadata("endpoint", "0x01");
            expect(await identityRegistry.getMetadata(agentId, "endpoint")).to.equal("0x01");
        }

        // Asserts the Safe can no longer act on the identity through the bridger
        async function expectUnlinked(safe) {
            expect(await bridger.mapMultisigAgentIds(safe)).to.equal(0);
            const safeSigner = await impersonate(safe);
            await expect(
                bridger.connect(safeSigner).setMetadata("endpoint", "0x02")
            ).to.be.revertedWithCustomError(bridger, "ZeroValue");
            await expect(
                bridger.connect(safeSigner).unsetAgentWallet()
            ).to.be.revertedWithCustomError(bridger, "ZeroValue");
        }

        // Asserts the agent Id and its protected metadata are those registered for the service
        async function expectIdentityIntact(serviceId, agentId) {
            expect(await bridger.mapServiceIdAgentIds(serviceId)).to.equal(agentId);
            const coder = ethers.utils.defaultAbiCoder;
            expect(await identityRegistry.getMetadata(agentId, "ecosystem")).to.equal(coder.encode(["string"],
                ["Olas"]));
            expect(await identityRegistry.getMetadata(agentId, "serviceRegistry")).to.equal(coder.encode(["address"],
                [serviceRegistry.address]));
            expect(await identityRegistry.getMetadata(agentId, "serviceId")).to.equal(coder.encode(["uint256"],
                [serviceId]));
        }

        // Sets the Safe as the agent wallet: the Safe signs the wallet digest, then calls the bridger
        async function setSafeAsAgentWallet(safe, agentId, owner) {
            const domain = await identityRegistry.eip712Domain();
            const deadline = (await ethers.provider.getBlock("latest")).timestamp + 100;
            const digest = ethers.utils._TypedDataEncoder.hash(
                { name: domain[1], version: domain[2], chainId: domain[3], verifyingContract: identityRegistry.address },
                { AgentWalletSet: [
                    { type: "uint256", name: "agentId" },
                    { type: "address", name: "newWallet" },
                    { type: "address", name: "owner" },
                    { type: "uint256", name: "deadline" },
                ] },
                { agentId, newWallet: safe, owner: bridger.address, deadline }
            );
            const multisig = await ethers.getContractAt("GnosisSafe", safe);
            const txHashData = await safeContracts.buildContractCall(signMessageLib, "signMessage", [digest],
                await multisig.nonce(), 1, 0);
            const signature = await safeContracts.safeSignMessage(owner, multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signature], 0);
            await bridger.connect(await impersonate(safe)).setAgentWallet(deadline, "0x");
            expect((await identityRegistry.getMetadata(agentId, "agentWallet")).toLowerCase()).to.equal(
                safe.toLowerCase());
        }

        // Fault injection: moves the agent Id away from the bridger, so the bridger's wallet unset reverts during
        // cleanup. It only exercises behaviour on a downstream failure; normal operation offers no such transfer.
        async function injectCleanupFailure(agentId) {
            const bridgerSigner = await impersonate(bridger.address);
            await identityRegistry.connect(bridgerSigner).transferFrom(bridger.address, signers[12].address, agentId);
        }


        // Leaves a service in PreRegistration with its former Safe still linked: the service is deployed, then
        // terminated and unbonded while no bridger is set.
        async function linkKeptFromEarlierDeployment(numInstances = 1) {
            const serviceId = await createService(numInstances);
            const registrations = [];
            for (let i = 0; i < numInstances; i++) {
                registrations.push([i == 0 ? operator : operator2, signers[13 + i]]);
            }
            const safe = await registerAndDeploy(serviceId, registrations);
            const agentId = await bridger.mapServiceIdAgentIds(serviceId);
            // A one-owner Safe also sets itself as agent wallet
            if (numInstances == 1) {
                await setSafeAsAgentWallet(safe, agentId, signers[13]);
            }
            await serviceManager.setIdentityRegistryBridger(AddressZero);
            await serviceManager.connect(serviceOwner).terminate(serviceId);
            for (const [op] of registrations) {
                await serviceManager.connect(op).unbond(serviceId);
            }
            await serviceManager.setIdentityRegistryBridger(bridger.address);
            expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(ServiceState.PreRegistration);
            expect(await bridger.mapMultisigAgentIds(safe)).to.equal(agentId);
            return { serviceId, agentId, safe };
        }

        it("Termination of a deployed service clears the link and the agent wallet while agents stay bonded",
            async function () {
                const instance = signers[10];
                const serviceId = await createService(1);
                const safe = await registerAndDeploy(serviceId, [[operator, instance]]);
                const agentId = await bridger.mapServiceIdAgentIds(serviceId);
                await expectLinked(safe, agentId);
                await setSafeAsAgentWallet(safe, agentId, instance);

                await expect(serviceManager.connect(serviceOwner).terminate(serviceId))
                    .to.emit(bridger, "AgentMultisigUpdated").withArgs(serviceId, agentId, safe, AddressZero);

                expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(ServiceState.TerminatedBonded);
                await expectUnlinked(safe);
                expect(await identityRegistry.getMetadata(agentId, "agentWallet")).to.equal("0x");
                await expectIdentityIntact(serviceId, agentId);
                // The multisig stays bound to its service
                expect(await serviceManager.mapMultisigServiceIds(safe)).to.equal(serviceId);
            });

        // Terminates a deployed service while no bridger is set, so its Safe stays linked through the unbonds that
        // follow; a cleanup still reachable from either unbond path would clear that link or, under fault injection,
        // revert.
        async function terminatedWithLinkInPlace(registrations) {
            const serviceId = await createService(registrations.length);
            const safe = await registerAndDeploy(serviceId, registrations);
            const agentId = await bridger.mapServiceIdAgentIds(serviceId);
            await serviceManager.setIdentityRegistryBridger(AddressZero);
            await serviceManager.connect(serviceOwner).terminate(serviceId);
            await serviceManager.setIdentityRegistryBridger(bridger.address);
            expect(await bridger.mapMultisigAgentIds(safe)).to.equal(agentId);
            return { serviceId, agentId, safe };
        }

        for (const [path, unbond] of Object.entries(unbondPaths)) {
            describe(`${path} unbond`, function () {
                it("Partial and final unbonds leave a link that is still in place untouched", async function () {
                    const { serviceId, agentId, safe } = await terminatedWithLinkInPlace([[operator, signers[10]],
                        [operator2, signers[11]]]);

                    await expect(unbond(serviceId, operator)).to.not.emit(bridger, "AgentMultisigUpdated");
                    expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(
                        ServiceState.TerminatedBonded);
                    expect(await bridger.mapMultisigAgentIds(safe)).to.equal(agentId);

                    await expect(unbond(serviceId, operator2)).to.not.emit(bridger, "AgentMultisigUpdated");
                    expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(
                        ServiceState.PreRegistration);
                    expect(await bridger.mapMultisigAgentIds(safe)).to.equal(agentId);
                });

                it("Final unbond succeeds while the bridger would fail on a link still in place (fault injection)",
                    async function () {
                        const { serviceId, agentId, safe } = await terminatedWithLinkInPlace([[operator,
                            signers[10]]]);
                        await injectCleanupFailure(agentId);

                        await unbond(serviceId, operator);
                        expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(
                            ServiceState.PreRegistration);
                        expect(await serviceRegistry.getOperatorBalance(operator.address, serviceId)).to.equal(0);
                        expect(await bridger.mapMultisigAgentIds(safe)).to.equal(agentId);
                    });
            });
        }

        it("Termination from ActiveRegistration without agents clears a link kept from an earlier deployment",
            async function () {
                const { serviceId, agentId, safe } = await linkKeptFromEarlierDeployment();
                await serviceManager.connect(serviceOwner).activateRegistration(serviceId, {value: regBond});

                await expect(serviceManager.connect(serviceOwner).terminate(serviceId))
                    .to.emit(bridger, "AgentMultisigUpdated").withArgs(serviceId, agentId, safe, AddressZero);

                expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(ServiceState.PreRegistration);
                await expectUnlinked(safe);
                expect(await identityRegistry.getMetadata(agentId, "agentWallet")).to.equal("0x");
                await expectIdentityIntact(serviceId, agentId);
            });

        it("Termination from ActiveRegistration with an agent registered clears a link kept from an earlier deployment",
            async function () {
                const { serviceId, agentId, safe } = await linkKeptFromEarlierDeployment(2);
                await serviceManager.connect(serviceOwner).activateRegistration(serviceId, {value: regBond});
                await serviceManager.connect(operator).registerAgents(serviceId, [signers[15].address], [1],
                    {value: regBond});
                expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(ServiceState.ActiveRegistration);

                await expect(serviceManager.connect(serviceOwner).terminate(serviceId))
                    .to.emit(bridger, "AgentMultisigUpdated").withArgs(serviceId, agentId, safe, AddressZero);

                expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(ServiceState.TerminatedBonded);
                await expectUnlinked(safe);
                expect(await identityRegistry.getMetadata(agentId, "agentWallet")).to.equal("0x");
            });

        it("Termination from FinishedRegistration clears a link kept from an earlier deployment", async function () {
            const { serviceId, agentId, safe } = await linkKeptFromEarlierDeployment();
            await activateAndRegister(serviceId, [[operator, signers[15]]]);
            expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(ServiceState.FinishedRegistration);

            await expect(serviceManager.connect(serviceOwner).terminate(serviceId))
                .to.emit(bridger, "AgentMultisigUpdated").withArgs(serviceId, agentId, safe, AddressZero);

            expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(ServiceState.TerminatedBonded);
            await expectUnlinked(safe);
            expect(await identityRegistry.getMetadata(agentId, "agentWallet")).to.equal("0x");
            await expectIdentityIntact(serviceId, agentId);
        });

        it("Termination of a never-deployed service does not call the bridger", async function () {
            // From ActiveRegistration with no agent, and from FinishedRegistration
            const active = await createService(1);
            await serviceManager.connect(serviceOwner).activateRegistration(active, {value: regBond});
            await expect(serviceManager.connect(serviceOwner).terminate(active)).to.not.emit(bridger,
                "AgentMultisigUpdated");

            const finished = await createService(1);
            await activateAndRegister(finished, [[operator, signers[10]]]);
            await expect(serviceManager.connect(serviceOwner).terminate(finished)).to.not.emit(bridger,
                "AgentMultisigUpdated");
            const service = await serviceRegistry.mapServices(finished);
            expect(service.state).to.equal(ServiceState.TerminatedBonded);
            expect(service.multisig).to.equal(AddressZero);
        });

        it("Termination leaves a link to another service's agent Id untouched", async function () {
            const serviceId = await createService(1);
            const safe = await registerAndDeploy(serviceId, [[operator, signers[10]]]);
            const otherServiceId = await createService(1);
            const otherAgentId = await bridger.mapServiceIdAgentIds(otherServiceId);

            // Simulate a legacy shared Safe: the bridger links the Safe to the other service's agent Id
            const manager = await impersonate(serviceManager.address);
            await bridger.connect(manager).updateAgentWallet(otherServiceId, AddressZero, safe);
            expect(await bridger.mapMultisigAgentIds(safe)).to.equal(otherAgentId);

            await expect(serviceManager.connect(serviceOwner).terminate(serviceId)).to.not.emit(bridger,
                "AgentMultisigUpdated");
            expect(await bridger.mapMultisigAgentIds(safe)).to.equal(otherAgentId);
        });

        it("Termination without a bridger, or of a service without an agent Id, does not call the bridger",
            async function () {
                // No bridger set
                const serviceId = await createService(1);
                const safe = await registerAndDeploy(serviceId, [[operator, signers[10]]]);
                await serviceManager.setIdentityRegistryBridger(AddressZero);
                await serviceManager.connect(serviceOwner).terminate(serviceId);
                expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(ServiceState.TerminatedBonded);
                expect(await bridger.mapMultisigAgentIds(safe)).to.be.gt(0);

                // Service created while no bridger was set has no agent Id
                const legacyServiceId = await createService(1);
                await serviceManager.setIdentityRegistryBridger(bridger.address);
                const legacySafe = await registerAndDeploy(legacyServiceId, [[operator, signers[11]]]);
                expect(await bridger.mapServiceIdAgentIds(legacyServiceId)).to.equal(0);
                await expect(serviceManager.connect(serviceOwner).terminate(legacyServiceId)).to.not.emit(bridger,
                    "AgentMultisigUpdated");
                expect(await bridger.mapMultisigAgentIds(legacySafe)).to.equal(0);
            });

        it("A failing identity cleanup reverts the termination and its refund (fault injection)", async function () {
            const serviceId = await createService(1);
            const safe = await registerAndDeploy(serviceId, [[operator, signers[10]]]);
            const agentId = await bridger.mapServiceIdAgentIds(serviceId);
            await injectCleanupFailure(agentId);

            const registryBalance = await ethers.provider.getBalance(serviceRegistry.address);
            await expect(serviceManager.connect(serviceOwner).terminate(serviceId)).to.be.revertedWith(
                "Not authorized");

            expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(ServiceState.Deployed);
            expect(await ethers.provider.getBalance(serviceRegistry.address)).to.equal(registryBalance);
            expect(await bridger.mapMultisigAgentIds(safe)).to.equal(agentId);
        });

        it("A failing identity cleanup reverts the token refund of an ERC20-secured termination (fault injection)",
            async function () {
                const serviceId = await createService(1, token.address);
                const safe = await registerAndDeploy(serviceId, [[operator, signers[10]]], token.address);
                const agentId = await bridger.mapServiceIdAgentIds(serviceId);
                await injectCleanupFailure(agentId);

                const ownerTokens = await token.balanceOf(serviceOwner.address);
                const utilityTokens = await token.balanceOf(serviceRegistryTokenUtility.address);
                const deposit = await serviceRegistryTokenUtility.mapServiceIdTokenDeposit(serviceId);
                await expect(serviceManager.connect(serviceOwner).terminate(serviceId)).to.be.revertedWith(
                    "Not authorized");

                expect(await token.balanceOf(serviceOwner.address)).to.equal(ownerTokens);
                expect(await token.balanceOf(serviceRegistryTokenUtility.address)).to.equal(utilityTokens);
                const depositAfter = await serviceRegistryTokenUtility.mapServiceIdTokenDeposit(serviceId);
                expect(depositAfter.securityDeposit).to.equal(deposit.securityDeposit);
                expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(ServiceState.Deployed);
                expect(await bridger.mapMultisigAgentIds(safe)).to.equal(agentId);
            });

        it("Termination of an ERC20-secured service clears the link and refunds the token deposit", async function () {
            const serviceId = await createService(1, token.address);
            const safe = await registerAndDeploy(serviceId, [[operator, signers[10]]], token.address);
            const agentId = await bridger.mapServiceIdAgentIds(serviceId);

            const balanceBefore = await token.balanceOf(serviceOwner.address);
            await expect(serviceManager.connect(serviceOwner).terminate(serviceId))
                .to.emit(bridger, "AgentMultisigUpdated").withArgs(serviceId, agentId, safe, AddressZero);
            expect(await token.balanceOf(serviceOwner.address)).to.equal(balanceBefore.add(regBond));

            await expectUnlinked(safe);
            await expectIdentityIntact(serviceId, agentId);
        });

        it("Redeployment with the same Safe after termination links it again", async function () {
            const instance = signers[10];
            const serviceId = await createService(1);
            const safe = await registerAndDeploy(serviceId, [[operator, instance]]);
            const agentId = await bridger.mapServiceIdAgentIds(serviceId);
            await serviceManager.connect(serviceOwner).terminate(serviceId);
            await serviceManager.connect(operator).unbond(serviceId);
            await expectUnlinked(safe);

            // The Safe owners are unchanged, so the same instance redeploys the same Safe
            await activateAndRegister(serviceId, [[operator, instance]]);
            await expect(serviceManager.connect(serviceOwner).deploy(serviceId,
                gnosisSafeSameAddressMultisig.address, ethers.utils.solidityPack(["address"], [safe])))
                .to.emit(bridger, "AgentMultisigUpdated").withArgs(serviceId, agentId, AddressZero, safe);

            expect((await serviceRegistry.mapServices(serviceId)).multisig).to.equal(safe);
            await expectLinked(safe, agentId);
            await expectIdentityIntact(serviceId, agentId);
        });

        it("Redeployment with a different Safe after termination links only the new one", async function () {
            const serviceId = await createService(1);
            const oldSafe = await registerAndDeploy(serviceId, [[operator, signers[10]]]);
            const agentId = await bridger.mapServiceIdAgentIds(serviceId);
            await serviceManager.connect(serviceOwner).terminate(serviceId);
            await serviceManager.connect(operator).unbond(serviceId);

            const newSafe = await registerAndDeploy(serviceId, [[operator, signers[11]]]);
            expect(newSafe).to.not.equal(oldSafe);
            await expectLinked(newSafe, agentId);
            await expectUnlinked(oldSafe);
            await expectIdentityIntact(serviceId, agentId);
            expect(await serviceManager.mapMultisigServiceIds(newSafe)).to.equal(serviceId);
            expect(await serviceManager.mapMultisigServiceIds(oldSafe)).to.equal(0);
        });

        it("Redeployment with a different Safe replaces a link kept from an earlier deployment", async function () {
            const { serviceId, agentId, safe: oldSafe } = await linkKeptFromEarlierDeployment();

            const newSafe = await registerAndDeploy(serviceId, [[operator, signers[16]]]);
            await expectLinked(newSafe, agentId);
            await expectUnlinked(oldSafe);
            expect(await identityRegistry.getMetadata(agentId, "agentWallet")).to.equal("0x");
        });
    });
}
