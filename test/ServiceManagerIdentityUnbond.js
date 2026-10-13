/*global describe, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");
const safeContracts = require("@gnosis.pm/safe-contracts");

// The final unbond clears the multisig link to the service 8004 agent Id and unsets the agent wallet; a redeployment
// links the deployed multisig again. Run against both ServiceRegistry and ServiceRegistryL2.
for (const registryKind of ["ServiceRegistry", "ServiceRegistryL2"]) {
    describe(`ServiceManager 8004 identity on unbond (${registryKind})`, function () {
        const defaultHash = "0x" + "5".repeat(64);
        const regBond = 1000;
        const ETHAddress = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
        const AddressZero = ethers.constants.AddressZero;
        const maxDeadline = ethers.constants.MaxUint256;
        const baseURI = "https://localhost/erc8004/service/";
        const ServiceState = { PreRegistration: 1, Deployed: 4, TerminatedBonded: 5 };
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
        // cleanup. It only exercises rollback on a downstream failure; normal operation offers no such transfer.
        async function injectCleanupFailure(agentId) {
            const bridgerSigner = await impersonate(bridger.address);
            await identityRegistry.connect(bridgerSigner).transferFrom(bridger.address, signers[12].address, agentId);
        }

        for (const [path, unbond] of Object.entries(unbondPaths)) {
            describe(`${path} unbond`, function () {
                it("Final unbond clears the multisig link and the agent wallet, keeps the identity and the binding",
                    async function () {
                        const instance = signers[10];
                        const serviceId = await createService(1);
                        const safe = await registerAndDeploy(serviceId, [[operator, instance]]);
                        const agentId = await bridger.mapServiceIdAgentIds(serviceId);
                        expect(agentId).to.be.gt(0);

                        await expectLinked(safe, agentId);
                        await setSafeAsAgentWallet(safe, agentId, instance);

                        await serviceManager.connect(serviceOwner).terminate(serviceId);
                        await expect(unbond(serviceId, operator)).to.emit(bridger, "AgentMultisigUpdated")
                            .withArgs(serviceId, agentId, safe, AddressZero);

                        expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(
                            ServiceState.PreRegistration);
                        await expectUnlinked(safe);
                        expect(await identityRegistry.getMetadata(agentId, "agentWallet")).to.equal("0x");
                        await expectIdentityIntact(serviceId, agentId);
                        // The multisig stays bound to its service
                        expect(await serviceManager.mapMultisigServiceIds(safe)).to.equal(serviceId);
                    });

                it("Partial unbond keeps the link until the last agent instance unbonds", async function () {
                    const serviceId = await createService(2);
                    const safe = await registerAndDeploy(serviceId, [[operator, signers[10]],
                        [operator2, signers[11]]]);
                    const agentId = await bridger.mapServiceIdAgentIds(serviceId);

                    await serviceManager.connect(serviceOwner).terminate(serviceId);
                    await expect(unbond(serviceId, operator)).to.not.emit(bridger, "AgentMultisigUpdated");
                    expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(
                        ServiceState.TerminatedBonded);
                    await expectLinked(safe, agentId);

                    await expect(unbond(serviceId, operator2)).to.emit(bridger, "AgentMultisigUpdated")
                        .withArgs(serviceId, agentId, safe, AddressZero);
                    await expectUnlinked(safe);
                    await expectIdentityIntact(serviceId, agentId);
                });

                it("Redeployment with the same Safe links it again", async function () {
                    const instance = signers[10];
                    const serviceId = await createService(1);
                    const safe = await registerAndDeploy(serviceId, [[operator, instance]]);
                    const agentId = await bridger.mapServiceIdAgentIds(serviceId);
                    await serviceManager.connect(serviceOwner).terminate(serviceId);
                    await unbond(serviceId, operator);
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

                it("Redeployment with a different Safe links only the new one", async function () {
                    const serviceId = await createService(1);
                    const oldSafe = await registerAndDeploy(serviceId, [[operator, signers[10]]]);
                    const agentId = await bridger.mapServiceIdAgentIds(serviceId);
                    await serviceManager.connect(serviceOwner).terminate(serviceId);
                    await unbond(serviceId, operator);

                    const newSafe = await registerAndDeploy(serviceId, [[operator, signers[11]]]);
                    expect(newSafe).to.not.equal(oldSafe);
                    await expectLinked(newSafe, agentId);
                    await expectUnlinked(oldSafe);
                    await expectIdentityIntact(serviceId, agentId);
                    expect(await serviceManager.mapMultisigServiceIds(newSafe)).to.equal(serviceId);
                    expect(await serviceManager.mapMultisigServiceIds(oldSafe)).to.equal(0);
                });

                it("A failing identity cleanup reverts the whole unbond (fault injection)", async function () {
                    const serviceId = await createService(1);
                    const safe = await registerAndDeploy(serviceId, [[operator, signers[10]]]);
                    const agentId = await bridger.mapServiceIdAgentIds(serviceId);
                    await serviceManager.connect(serviceOwner).terminate(serviceId);

                    await injectCleanupFailure(agentId);

                    const registryBalance = await ethers.provider.getBalance(serviceRegistry.address);
                    const unbondNonce = await serviceManager.getOperatorUnbondNonce(operator.address, serviceId);
                    await expect(unbond(serviceId, operator)).to.be.revertedWith("Not authorized");

                    expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(
                        ServiceState.TerminatedBonded);
                    expect(await serviceRegistry.getOperatorBalance(operator.address, serviceId)).to.equal(regBond);
                    expect(await ethers.provider.getBalance(serviceRegistry.address)).to.equal(registryBalance);
                    expect(await serviceManager.getOperatorUnbondNonce(operator.address, serviceId)).to.equal(
                        unbondNonce);
                    expect(await bridger.mapMultisigAgentIds(safe)).to.equal(agentId);
                });
            });
        }

        it("Final unbond of an ERC20-secured service clears the multisig link and refunds the token bond",
            async function () {
                const serviceId = await createService(1, token.address);
                const safe = await registerAndDeploy(serviceId, [[operator, signers[10]]], token.address);
                const agentId = await bridger.mapServiceIdAgentIds(serviceId);
                await expectLinked(safe, agentId);

                await serviceManager.connect(serviceOwner).terminate(serviceId);
                const balanceBefore = await token.balanceOf(operator.address);
                await expect(serviceManager.connect(operator).unbond(serviceId))
                    .to.emit(bridger, "AgentMultisigUpdated").withArgs(serviceId, agentId, safe, AddressZero);
                expect(await token.balanceOf(operator.address)).to.equal(balanceBefore.add(regBond));

                await expectUnlinked(safe);
                await expectIdentityIntact(serviceId, agentId);
            });

        it("A failing identity cleanup reverts the token refund of an ERC20-secured service (fault injection)",
            async function () {
                const serviceId = await createService(1, token.address);
                const safe = await registerAndDeploy(serviceId, [[operator, signers[10]]], token.address);
                const agentId = await bridger.mapServiceIdAgentIds(serviceId);
                await serviceManager.connect(serviceOwner).terminate(serviceId);

                await injectCleanupFailure(agentId);

                const operatorTokens = await token.balanceOf(operator.address);
                const utilityTokens = await token.balanceOf(serviceRegistryTokenUtility.address);
                await expect(serviceManager.connect(operator).unbond(serviceId)).to.be.revertedWith("Not authorized");

                expect(await token.balanceOf(operator.address)).to.equal(operatorTokens);
                expect(await token.balanceOf(serviceRegistryTokenUtility.address)).to.equal(utilityTokens);
                expect(await serviceRegistryTokenUtility.getOperatorBalance(operator.address, serviceId)).to.equal(
                    regBond);
                expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(ServiceState.TerminatedBonded);
                expect(await bridger.mapMultisigAgentIds(safe)).to.equal(agentId);
            });

        it("Final unbond of a never-deployed service skips the identity cleanup", async function () {
            const serviceId = await createService(1);
            const agentId = await bridger.mapServiceIdAgentIds(serviceId);
            expect(agentId).to.be.gt(0);
            await activateAndRegister(serviceId, [[operator, signers[10]]]);

            await serviceManager.connect(serviceOwner).terminate(serviceId);
            await expect(serviceManager.connect(operator).unbond(serviceId)).to.not.emit(bridger,
                "AgentMultisigUpdated");
            const service = await serviceRegistry.mapServices(serviceId);
            expect(service.state).to.equal(ServiceState.PreRegistration);
            expect(service.multisig).to.equal(AddressZero);
            await expectIdentityIntact(serviceId, agentId);
        });

        it("Redeployment with a different Safe unlinks a previous Safe still linked from before this upgrade",
            async function () {
                const instance = signers[10];
                const serviceId = await createService(1);
                const oldSafe = await registerAndDeploy(serviceId, [[operator, instance]]);
                const agentId = await bridger.mapServiceIdAgentIds(serviceId);
                await setSafeAsAgentWallet(oldSafe, agentId, instance);

                // Unbond without the bridger, as before this upgrade: the old link remains
                await serviceManager.setIdentityRegistryBridger(AddressZero);
                await serviceManager.connect(serviceOwner).terminate(serviceId);
                await serviceManager.connect(operator).unbond(serviceId);
                await serviceManager.setIdentityRegistryBridger(bridger.address);
                expect(await bridger.mapMultisigAgentIds(oldSafe)).to.equal(agentId);

                const newSafe = await registerAndDeploy(serviceId, [[operator, signers[11]]]);
                await expectLinked(newSafe, agentId);
                await expectUnlinked(oldSafe);
                expect(await identityRegistry.getMetadata(agentId, "agentWallet")).to.equal("0x");
            });

        it("Final unbond leaves a link to another service's agent Id untouched", async function () {
            const serviceId = await createService(1);
            const safe = await registerAndDeploy(serviceId, [[operator, signers[10]]]);
            const otherServiceId = await createService(1);
            const otherAgentId = await bridger.mapServiceIdAgentIds(otherServiceId);

            // Simulate a legacy shared Safe: the bridger links the Safe to the other service's agent Id
            const manager = await impersonate(serviceManager.address);
            await bridger.connect(manager).updateAgentWallet(otherServiceId, AddressZero, safe);
            expect(await bridger.mapMultisigAgentIds(safe)).to.equal(otherAgentId);

            await serviceManager.connect(serviceOwner).terminate(serviceId);
            await expect(serviceManager.connect(operator).unbond(serviceId)).to.not.emit(bridger,
                "AgentMultisigUpdated");
            expect(await bridger.mapMultisigAgentIds(safe)).to.equal(otherAgentId);
        });

        it("Final unbond without a bridger, or of a service without an agent Id, does not call the bridger",
            async function () {
                // No bridger set
                const serviceId = await createService(1);
                const safe = await registerAndDeploy(serviceId, [[operator, signers[10]]]);
                await serviceManager.setIdentityRegistryBridger(AddressZero);
                await serviceManager.connect(serviceOwner).terminate(serviceId);
                await serviceManager.connect(operator).unbond(serviceId);
                expect((await serviceRegistry.mapServices(serviceId)).state).to.equal(ServiceState.PreRegistration);
                expect(await bridger.mapMultisigAgentIds(safe)).to.be.gt(0);

                // Service created while no bridger was set has no agent Id
                const legacyServiceId = await createService(1);
                await serviceManager.setIdentityRegistryBridger(bridger.address);
                const legacySafe = await registerAndDeploy(legacyServiceId, [[operator, signers[11]]]);
                expect(await bridger.mapServiceIdAgentIds(legacyServiceId)).to.equal(0);
                await serviceManager.connect(serviceOwner).terminate(legacyServiceId);
                await expect(serviceManager.connect(operator).unbond(legacyServiceId)).to.not.emit(bridger,
                    "AgentMultisigUpdated");
                expect(await bridger.mapMultisigAgentIds(legacySafe)).to.equal(0);
            });
    });
}
