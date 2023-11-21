/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const safeContracts = require("@gnosis.pm/safe-contracts");

describe.only("ServiceStaking", function () {
    let componentRegistry;
    let agentRegistry;
    let serviceRegistry;
    let serviceRegistryTokenUtility;
    let token;
    let gnosisSafe;
    let gnosisSafeProxyFactory;
    let gnosisSafeMultisig;
    let gnosisSafeSameAddressMultisig;
    let multiSend;
    let safeNonceLib;
    let serviceStaking;
    let serviceStakingToken;
    let attacker;
    let signers;
    let deployer;
    let operator;
    let agentInstances;
    let bytecodeHash;
    const AddressZero = ethers.constants.AddressZero;
    const defaultHash = "0x" + "5".repeat(64);
    const bytes32Zero = "0x" + "0".repeat(64);
    const regDeposit = 1000;
    const regBond = 1000;
    const serviceId = 1;
    const agentIds = [1];
    const agentParams = [[1, regBond]];
    const threshold = 1;
    const livenessPeriod = 10; // Ten seconds
    let maxInactivity;
    const initSupply = "5" + "0".repeat(26);
    const payload = "0x";
    const serviceParams = {
        maxNumServices: 10,
        rewardsPerSecond: "1" + "0".repeat(15),
        minStakingDeposit: 10,
        livenessPeriod: livenessPeriod, // Ten seconds
        livenessRatio: "1" + "0".repeat(16), // 0.01 transaction per second (TPS)
        numAgentInstances: 1,
        agentIds: [],
        threshold: 0,
        configHash: bytes32Zero
    };

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];
        operator = signers[1];

        const ComponentRegistry = await ethers.getContractFactory("ComponentRegistry");
        componentRegistry = await ComponentRegistry.deploy("component", "COMPONENT", "https://localhost/component/");
        await componentRegistry.deployed();

        const AgentRegistry = await ethers.getContractFactory("AgentRegistry");
        agentRegistry = await AgentRegistry.deploy("agent", "AGENT", "https://localhost/agent/", componentRegistry.address);
        await agentRegistry.deployed();

        const ServiceRegistry = await ethers.getContractFactory("ServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy("service registry", "SERVICE", "https://localhost/service/",
            agentRegistry.address);
        await serviceRegistry.deployed();

        const ServiceRegistryTokenUtility = await ethers.getContractFactory("ServiceRegistryTokenUtility");
        serviceRegistryTokenUtility = await ServiceRegistryTokenUtility.deploy(serviceRegistry.address);
        await serviceRegistry.deployed();

        const Token = await ethers.getContractFactory("ERC20Token");
        token = await Token.deploy();
        await token.deployed();

        const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
        gnosisSafe = await GnosisSafe.deploy();
        await gnosisSafe.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
        gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafe.address, gnosisSafeProxyFactory.address);
        await gnosisSafeMultisig.deployed();

        const GnosisSafeProxy = await ethers.getContractFactory("GnosisSafeProxy");
        const gnosisSafeProxy = await GnosisSafeProxy.deploy(gnosisSafe.address);
        await gnosisSafeProxy.deployed();
        const bytecode = await ethers.provider.getCode(gnosisSafeProxy.address);
        bytecodeHash = ethers.utils.keccak256(bytecode);

        const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
        gnosisSafeSameAddressMultisig = await GnosisSafeSameAddressMultisig.deploy(bytecodeHash);
        await gnosisSafeSameAddressMultisig.deployed();

        const MultiSend = await ethers.getContractFactory("MultiSendCallOnly");
        multiSend = await MultiSend.deploy();
        await multiSend.deployed();

        const ServiceStakingNativeToken = await ethers.getContractFactory("ServiceStakingNativeToken");
        serviceStaking = await ServiceStakingNativeToken.deploy(serviceParams, serviceRegistry.address, bytecodeHash);
        await serviceStaking.deployed();

        maxInactivity = Number(await serviceStaking.MAX_INACTIVITY_PERIODS()) * livenessPeriod + 1;

        const ServiceStakingToken = await ethers.getContractFactory("ServiceStakingToken");
        serviceStakingToken = await ServiceStakingToken.deploy(serviceParams, serviceRegistry.address,
            serviceRegistryTokenUtility.address, token.address, bytecodeHash);
        await serviceStakingToken.deployed();

        const SafeNonceLib = await ethers.getContractFactory("SafeNonceLib");
        safeNonceLib = await SafeNonceLib.deploy();
        await safeNonceLib.deployed();

        const Attacker = await ethers.getContractFactory("ReentrancyStakingAttacker");
        attacker = await Attacker.deploy(serviceStaking.address, serviceRegistry.address);
        await attacker.deployed();

        // Set the deployer to be the unit manager by default
        await componentRegistry.changeManager(deployer.address);
        await agentRegistry.changeManager(deployer.address);
        // Set the deployer to be the service manager by default
        await serviceRegistry.changeManager(deployer.address);
        await serviceRegistryTokenUtility.changeManager(deployer.address);

        // Mint tokens to the service owner and the operator
        await token.mint(deployer.address, initSupply);
        await token.mint(operator.address, initSupply);

        // Create component, two agents and two services
        await componentRegistry.create(deployer.address, defaultHash, []);
        await agentRegistry.create(deployer.address, defaultHash, [1]);
        await agentRegistry.create(deployer.address, defaultHash, [1]);
        await serviceRegistry.create(deployer.address, defaultHash, agentIds, agentParams, threshold);
        await serviceRegistry.create(deployer.address, defaultHash, agentIds, agentParams, threshold);

        // Activate registration
        await serviceRegistry.activateRegistration(deployer.address, serviceId, {value: regDeposit});
        await serviceRegistry.activateRegistration(deployer.address, serviceId + 1, {value: regDeposit});

        // Register agent instances
        agentInstances = [signers[2], signers[3], signers[4], signers[5], signers[6], signers[7]];
        await serviceRegistry.registerAgents(operator.address, serviceId, [agentInstances[0].address], agentIds, {value: regBond});
        await serviceRegistry.registerAgents(operator.address, serviceId + 1, [agentInstances[1].address], agentIds, {value: regBond});

        // Whitelist gnosis multisig implementations
        await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);
        await serviceRegistry.changeMultisigPermission(gnosisSafeSameAddressMultisig.address, true);

        // Deploy services
        await serviceRegistry.deploy(deployer.address, serviceId, gnosisSafeMultisig.address, payload);
        await serviceRegistry.deploy(deployer.address, serviceId + 1, gnosisSafeMultisig.address, payload);
    });

    context("Initialization", function () {
        it("Should not allow the zero values and addresses when deploying contracts", async function () {
            const ServiceStakingNativeToken = await ethers.getContractFactory("ServiceStakingNativeToken");
            const ServiceStakingToken = await ethers.getContractFactory("ServiceStakingToken");

            const defaultTestServiceParams = {
                maxNumServices: 0,
                rewardsPerSecond: 0,
                minStakingDeposit: 0,
                livenessPeriod: 0,
                livenessRatio: 0,
                numAgentInstances: 0,
                agentIds: [],
                threshold: 0,
                configHash: bytes32Zero
            };

            // Service Staking Native Token
            let testServiceParams = JSON.parse(JSON.stringify(defaultTestServiceParams));
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");

            testServiceParams.maxNumServices = 1;
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");

            testServiceParams.rewardsPerSecond = 1;
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");

            testServiceParams.livenessPeriod = 1;
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");

            testServiceParams.livenessRatio = 1;
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");

            testServiceParams.numAgentInstances = 1;
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "LowerThan");

            testServiceParams.minStakingDeposit = 2;
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroAddress");

            testServiceParams.agentIds = [0];
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "WrongAgentId");

            testServiceParams.agentIds = [1, 1];
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "WrongAgentId");

            testServiceParams.agentIds = [2, 1];
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "WrongAgentId");

            testServiceParams.agentIds = [];
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");

            await expect(ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");


            // Service Staking Token
            testServiceParams = JSON.parse(JSON.stringify(defaultTestServiceParams));
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");

            testServiceParams.maxNumServices = 1;
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");

            testServiceParams.rewardsPerSecond = 1;
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");

            testServiceParams.livenessPeriod = 1;
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");

            testServiceParams.livenessRatio = 1;
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");

            testServiceParams.numAgentInstances = 1;
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingToken, "LowerThan");

            testServiceParams.minStakingDeposit = 2;
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroAddress");

            await expect(ServiceStakingToken.deploy(testServiceParams, serviceRegistry.address, AddressZero, AddressZero, bytes32Zero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");
            await expect(ServiceStakingToken.deploy(testServiceParams, serviceRegistry.address, serviceRegistryTokenUtility.address, AddressZero, bytecodeHash)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroAddress");
        });
    });

    context("Staking to ServiceStakingNativeToken and ServiceStakingToken", function () {
        it("Should fail if there are no available rewards", async function () {
            await expect(
                serviceStaking.stake(serviceId)
            ).to.be.revertedWithCustomError(serviceStaking, "NoRewardsAvailable");
        });

        it("Should fail if the maximum number of staking services is reached", async function () {
            // Deploy a contract with max number of services equal to one
            const ServiceStakingNativeToken = await ethers.getContractFactory("ServiceStakingNativeToken");
            const testServiceParams = JSON.parse(JSON.stringify(serviceParams));
            testServiceParams.maxNumServices = 1;
            const sStaking = await ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address, bytecodeHash);
            await sStaking.deployed();

            // Deposit to the contract
            await deployer.sendTransaction({to: sStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(sStaking.address, serviceId);
            await serviceRegistry.approve(sStaking.address, serviceId + 1);

            // Stake the first service
            await sStaking.stake(serviceId);

            // Staking next service is going to fail
            await expect(
                sStaking.stake(serviceId + 1)
            ).to.be.revertedWithCustomError(sStaking, "MaxNumServicesReached");
        });

        it("Should fail when the service is not deployed", async function () {
            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            // Create a new service (serviceId == 3)
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, agentParams, threshold);

            // Approve services
            await serviceRegistry.approve(serviceStaking.address, serviceId + 2);

            await expect(
                serviceStaking.stake(serviceId + 2)
            ).to.be.revertedWithCustomError(serviceStaking, "WrongServiceState");
        });

        it("Should fail when the maximum number of instances is incorrect", async function () {
            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            // Create a new service (serviceId == 3)
            await serviceRegistry.create(deployer.address, defaultHash, [1, 2], [agentParams[0], agentParams[0]], 2);

            // Approve services
            await serviceRegistry.approve(serviceStaking.address, serviceId + 2);

            await expect(
                serviceStaking.stake(serviceId + 2)
            ).to.be.revertedWithCustomError(serviceStaking, "WrongServiceConfiguration");
        });

        it("Should fail when the specified config of the service does not match", async function () {
            // Deploy a contract with a different service config specification
            const ServiceStakingNativeToken = await ethers.getContractFactory("ServiceStakingNativeToken");
            const testServiceParams = JSON.parse(JSON.stringify(serviceParams));
            testServiceParams.configHash = "0x" + "1".repeat(64);
            const sStaking = await ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address, bytecodeHash);
            await sStaking.deployed();

            // Deposit to the contract
            await deployer.sendTransaction({to: sStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(sStaking.address, serviceId);

            await expect(
                sStaking.stake(serviceId)
            ).to.be.revertedWithCustomError(sStaking, "WrongServiceConfiguration");
        });

        it("Should fail when the specified threshold of the service does not match", async function () {
            // Deploy a contract with a different service config specification
            const ServiceStakingNativeToken = await ethers.getContractFactory("ServiceStakingNativeToken");
            const testServiceParams = JSON.parse(JSON.stringify(serviceParams));
            testServiceParams.threshold = 2;
            const sStaking = await ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address, bytecodeHash);
            await sStaking.deployed();

            // Deposit to the contract
            await deployer.sendTransaction({to: sStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(sStaking.address, serviceId);

            await expect(
                sStaking.stake(serviceId)
            ).to.be.revertedWithCustomError(serviceStaking, "WrongServiceConfiguration");
        });

        it("Should fail when the optional agent Ids do not match in the service", async function () {
            // Deploy a service staking contract with specific agent Ids
            const ServiceStakingNativeToken = await ethers.getContractFactory("ServiceStakingNativeToken");
            let testServiceParams = JSON.parse(JSON.stringify(serviceParams));
            testServiceParams.agentIds = [1];
            const sStaking = await ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address, bytecodeHash);
            await sStaking.deployed();

            // Check agent Ids
            const agentIds = await sStaking.getAgentIds();
            expect(agentIds.length).to.equal(testServiceParams.agentIds.length);
            for (let i = 0; i < agentIds.length; i++) {
                expect(agentIds[i]).to.equal(testServiceParams.agentIds[i]);
            }

            // Deposit to the contract
            await deployer.sendTransaction({to: sStaking.address, value: ethers.utils.parseEther("1")});

            // Create a new service (serviceId == 3)
            await serviceRegistry.create(deployer.address, defaultHash, [2], agentParams, threshold);
            await serviceRegistry.activateRegistration(deployer.address, serviceId + 2, {value: regDeposit});
            await serviceRegistry.registerAgents(operator.address, serviceId + 2, [agentInstances[2].address], [2], {value: regBond});
            await serviceRegistry.deploy(deployer.address, serviceId + 2, gnosisSafeMultisig.address, payload);

            // Approve services
            await serviceRegistry.approve(sStaking.address, serviceId + 2);

            await expect(
                sStaking.stake(serviceId + 2)
            ).to.be.revertedWithCustomError(sStaking, "WrongAgentId");

            // Create a new service (serviceId == 4)
            await serviceRegistry.create(deployer.address, defaultHash, [1], agentParams, threshold);
            await serviceRegistry.activateRegistration(deployer.address, serviceId + 3, {value: regDeposit});
            await serviceRegistry.registerAgents(operator.address, serviceId + 3, [agentInstances[3].address], agentIds, {value: regBond});
            await serviceRegistry.deploy(deployer.address, serviceId + 3, gnosisSafeMultisig.address, payload);

            // Approve services
            await serviceRegistry.approve(sStaking.address, serviceId + 3);

            // Stake the service
            await sStaking.stake(serviceId + 3);
        });

        it("Should fail when the numer of agent instances matching the wrong agent Ids size", async function () {
            // Deploy a service staking contract with a numer of agent instances matching the wrong agent Ids size
            const ServiceStakingNativeToken = await ethers.getContractFactory("ServiceStakingNativeToken");
            let testServiceParams = JSON.parse(JSON.stringify(serviceParams));
            testServiceParams.agentIds = [1];
            testServiceParams.numAgentInstances = 2;
            const sStaking = await ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address, bytecodeHash);
            await sStaking.deployed();

            // Deposit to the contract
            await deployer.sendTransaction({to: sStaking.address, value: ethers.utils.parseEther("1")});

            // Create a new service (serviceId == 3)
            await serviceRegistry.create(deployer.address, defaultHash, [1, 2], [agentParams[0], agentParams[0]], 2);
            await serviceRegistry.activateRegistration(deployer.address, serviceId + 2, {value: regDeposit});
            await serviceRegistry.registerAgents(operator.address, serviceId + 2, [agentInstances[4].address, agentInstances[5].address], [1, 2], {value: 2 * regBond});
            await serviceRegistry.deploy(deployer.address, serviceId + 2, gnosisSafeMultisig.address, payload);

            // Approve services
            await serviceRegistry.approve(sStaking.address, serviceId + 2);

            await expect(
                sStaking.stake(serviceId + 2)
            ).to.be.revertedWithCustomError(sStaking, "WrongServiceConfiguration");
        });

        it("Should fail when the service has insufficient security deposit", async function () {
            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            const securityDeposit = 1;

            // Create a new service (serviceId == 3), activate, register agents and deploy
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, [[1, securityDeposit]], threshold);
            await serviceRegistry.activateRegistration(deployer.address, serviceId + 2, {value: securityDeposit});
            await serviceRegistry.registerAgents(operator.address, serviceId + 2, [agentInstances[2].address], agentIds, {value: securityDeposit});
            await serviceRegistry.deploy(deployer.address, serviceId + 2, gnosisSafeMultisig.address, payload);

            // Approve services
            await serviceRegistry.approve(serviceStaking.address, serviceId + 2);

            await expect(
                serviceStaking.stake(serviceId + 2)
            ).to.be.revertedWithCustomError(serviceStaking, "LowerThan");
        });

        it("Should fail when the service has insufficient security / staking token", async function () {
            // Deploy another token contract
            const Token = await ethers.getContractFactory("ERC20Token");
            const token2 = await Token.deploy();

            // Mint tokens to deployer, operator and a staking contract
            await token2.mint(deployer.address, initSupply);
            await token2.mint(operator.address, initSupply);
            // Approve token2 for the ServiceRegistryTokenUtility
            await token2.approve(serviceRegistryTokenUtility.address, initSupply);
            await token2.connect(operator).approve(serviceRegistryTokenUtility.address, initSupply);
            // Approve and deposit token to the staking contract
            await token.approve(serviceStakingToken.address, initSupply);
            await serviceStakingToken.deposit(regBond);

            // Create a service with the token2 (service Id == 3)
            const sId = 3;
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, [[1, 1]], threshold);
            await serviceRegistryTokenUtility.createWithToken(sId, token2.address, agentIds, [regBond]);
            // Activate registration
            await serviceRegistry.activateRegistration(deployer.address, sId, {value: 1});
            await serviceRegistryTokenUtility.activateRegistrationTokenDeposit(sId);
            // Register agents
            await serviceRegistry.registerAgents(operator.address, sId, [agentInstances[2].address], agentIds, {value: 1});
            await serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, sId, agentIds);
            // Deploy the service
            await serviceRegistry.deploy(deployer.address, sId, gnosisSafeMultisig.address, payload);

            // Approve services
            await serviceRegistry.approve(serviceStakingToken.address, sId);

            await expect(
                serviceStakingToken.stake(sId)
            ).to.be.revertedWithCustomError(serviceStakingToken, "WrongStakingToken");
        });

        it("Should fail when the service has insufficient security / staking deposit", async function () {
            // Approve token2 for the ServiceRegistryTokenUtility
            await token.approve(serviceRegistryTokenUtility.address, initSupply);
            await token.connect(operator).approve(serviceRegistryTokenUtility.address, initSupply);
            // Approve and deposit token to the staking contract
            await token.approve(serviceStakingToken.address, initSupply);
            await serviceStakingToken.deposit(regBond);

            const securityDeposit = 1;

            // Create a service with the token2 (service Id == 3)
            const sId = 3;
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, [[1, 1]], threshold);
            await serviceRegistryTokenUtility.createWithToken(sId, token.address, agentIds, [securityDeposit]);
            // Activate registration
            await serviceRegistry.activateRegistration(deployer.address, sId, {value: 1});
            await serviceRegistryTokenUtility.activateRegistrationTokenDeposit(sId);
            // Register agents
            await serviceRegistry.registerAgents(operator.address, sId, [agentInstances[2].address], agentIds, {value: 1});
            await serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, sId, agentIds);
            // Deploy the service
            await serviceRegistry.deploy(deployer.address, sId, gnosisSafeMultisig.address, payload);

            // Approve services
            await serviceRegistry.approve(serviceStakingToken.address, sId);

            await expect(
                serviceStakingToken.stake(sId)
            ).to.be.revertedWithCustomError(serviceStakingToken, "ValueLowerThan");
        });

        it("Stake a service at ServiceStakingNativeToken and try to unstake not by the service owner", async function () {
            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(serviceStaking.address, serviceId);

            // Stake the first service
            await serviceStaking.stake(serviceId);

            // Try to unstake not by the owner
            await expect(
                serviceStaking.connect(operator).unstake(serviceId)
            ).to.be.revertedWithCustomError(serviceStaking, "OwnerOnly");
        });

        it("Stake a service at ServiceStakingToken", async function () {
            // Approve ServiceRegistryTokenUtility
            await token.approve(serviceRegistryTokenUtility.address, initSupply);
            await token.connect(operator).approve(serviceRegistryTokenUtility.address, initSupply);
            // Approve and deposit token to the staking contract
            await token.approve(serviceStakingToken.address, initSupply);
            await serviceStakingToken.deposit(regBond);

            // Create a service with the token2 (service Id == 3)
            const sId = 3;
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, [[1, 1]], threshold);
            await serviceRegistryTokenUtility.createWithToken(sId, token.address, agentIds, [regBond]);
            // Activate registration
            await serviceRegistry.activateRegistration(deployer.address, sId, {value: 1});
            await serviceRegistryTokenUtility.activateRegistrationTokenDeposit(sId);
            // Register agents
            await serviceRegistry.registerAgents(operator.address, sId, [agentInstances[2].address], agentIds, {value: 1});
            await serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, sId, agentIds);
            // Deploy the service
            await serviceRegistry.deploy(deployer.address, sId, gnosisSafeMultisig.address, payload);

            // Approve services
            await serviceRegistry.approve(serviceStakingToken.address, sId);

            await serviceStakingToken.stake(sId);
        });

        it("Returns zero rewards for the not staked service", async function () {
            const reward = await serviceStaking.calculateServiceStakingReward(serviceId);
            expect(reward).to.equal(0);
        });
    });

    context("Staking and unstaking", function () {
        it("Stake and unstake without any service activity", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(serviceStaking.address, serviceId);

            // Stake the first service
            await serviceStaking.stake(serviceId);

            // Check that the service is staked
            const isStaked = await serviceStaking.isServiceStaked(serviceId);
            expect(isStaked).to.equal(true);

            // Get the service multisig contract
            const service = await serviceRegistry.getService(serviceId);
            const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Increase the time while the service does not reach the required amount of transactions per second (TPS)
            await helpers.time.increase(maxInactivity);

            // Calculate service staking reward that must be zero
            const reward = await serviceStaking.calculateServiceStakingReward(serviceId);
            expect(reward).to.equal(0);

            // Unstake the service
            const balanceBefore = await ethers.provider.getBalance(multisig.address);
            await serviceStaking.unstake(serviceId);
            const balanceAfter = await ethers.provider.getBalance(multisig.address);

            // The multisig balance before and after unstake must be the same (zero reward)
            expect(balanceBefore).to.equal(balanceAfter);

            // Check the final serviceIds set to be empty
            const serviceIds = await serviceStaking.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake right away without any service activity for two services", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(serviceStaking.address, serviceId);
            await serviceRegistry.approve(serviceStaking.address, serviceId + 1);

            // Stake services
            await serviceStaking.stake(serviceId);
            await serviceStaking.stake(serviceId + 1);

            // Call the checkpoint to make sure the rewards logic is not hit
            await serviceStaking.checkpoint();

            // Get the next checkpoint timestamp and compare with the next reward timestamp
            const tsNext = Number(await serviceStaking.getNextRewardCheckpointTimestamp());
            const tsLast = Number(await serviceStaking.tsCheckpoint());
            const livenessPeriod = Number(await serviceStaking.livenessPeriod());
            expect(tsNext - tsLast).to.equal(livenessPeriod);

            // Calculate service staking reward that must be zero
            let reward = await serviceStaking.calculateServiceStakingReward(serviceId);
            expect(reward).to.equal(0);
            reward = await serviceStaking.calculateServiceStakingReward(serviceId + 1);
            expect(reward).to.equal(0);

            // Get the service multisig contract
            let service = await serviceRegistry.getService(serviceId);
            let multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Increase the time before unstake
            await helpers.time.increase(maxInactivity);

            // Unstake services
            let balanceBefore = await ethers.provider.getBalance(multisig.address);
            await serviceStaking.unstake(serviceId);
            let balanceAfter = await ethers.provider.getBalance(multisig.address);

            // The multisig balance before and after unstake must be the same (zero reward)
            expect(balanceBefore).to.equal(balanceAfter);

            // Get the service multisig contract
            service = await serviceRegistry.getService(serviceId + 1);
            multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            balanceBefore = await ethers.provider.getBalance(multisig.address);
            await serviceStaking.unstake(serviceId + 1);
            balanceAfter = await ethers.provider.getBalance(multisig.address);

            // The multisig balance before and after unstake must be the same (zero reward)
            expect(balanceBefore).to.equal(balanceAfter);

            // Check the final serviceIds set to be empty
            const serviceIds = await serviceStaking.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake with the service activity", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(serviceStaking.address, serviceId);

            // Stake the first service
            await serviceStaking.stake(serviceId);

            // Get the service multisig contract
            const service = await serviceRegistry.getService(serviceId);
            const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Make transactions by the service multisig
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            let signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(maxInactivity);

            // Call the checkpoint at this time
            await serviceStaking.checkpoint();

            // Checking the nonce info
            let serviceInfo = await serviceStaking.getServiceInfo(serviceId);
            const lastNonce = serviceInfo.nonces[0];
            expect(lastNonce).to.greaterThan(0);

            // Execute one more multisig tx
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(maxInactivity);

            // Checking the nonce info (it is not updated as none of checkpoint or unstake were not called)
            serviceInfo = await serviceStaking.getServiceInfo(serviceId);
            const lastLastNonce = serviceInfo.nonces[0];
            expect(lastLastNonce).to.equal(lastNonce);

            // Calculate service staking reward that must be greater than zero
            const reward = await serviceStaking.calculateServiceStakingReward(serviceId);
            expect(reward).to.greaterThan(0);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
            await serviceStaking.unstake(serviceId);
            const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter).to.gt(balanceBefore);

            // Check the final serviceIds set to be empty
            const serviceIds = await serviceStaking.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake with the service activity with a custom ERC20 token", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Approve ServiceRegistryTokenUtility
            await token.approve(serviceRegistryTokenUtility.address, initSupply);
            await token.connect(operator).approve(serviceRegistryTokenUtility.address, initSupply);
            // Approve and deposit token to the staking contract
            await token.approve(serviceStakingToken.address, initSupply);
            await serviceStakingToken.deposit(ethers.utils.parseEther("1"));

            // Create a service with the token2 (service Id == 3)
            const sId = 3;
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, [[1, 1]], threshold);
            await serviceRegistryTokenUtility.createWithToken(sId, token.address, agentIds, [regBond]);
            // Activate registration
            await serviceRegistry.activateRegistration(deployer.address, sId, {value: 1});
            await serviceRegistryTokenUtility.activateRegistrationTokenDeposit(sId);
            // Register agents
            await serviceRegistry.registerAgents(operator.address, sId, [agentInstances[2].address], agentIds, {value: 1});
            await serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, sId, agentIds);
            // Deploy the service
            await serviceRegistry.deploy(deployer.address, sId, gnosisSafeMultisig.address, payload);

            // Approve services
            await serviceRegistry.approve(serviceStakingToken.address, sId);

            // Stake the first service
            await serviceStakingToken.stake(sId);

            // Get the service multisig contract
            const service = await serviceRegistry.getService(sId);
            const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Make transactions by the service multisig
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            let signMessageData = await safeContracts.safeSignMessage(agentInstances[2], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(livenessPeriod);

            // Call the checkpoint at this time
            await serviceStakingToken.checkpoint();

            // Execute one more multisig tx
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            signMessageData = await safeContracts.safeSignMessage(agentInstances[2], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(maxInactivity);

            // Calculate service staking reward that must be greater than zero
            const reward = await serviceStakingToken.calculateServiceStakingReward(sId);
            expect(reward).to.greaterThan(0);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await token.balanceOf(multisig.address));
            await serviceStakingToken.unstake(sId);
            const balanceAfter = ethers.BigNumber.from(await token.balanceOf(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter.gt(balanceBefore));

            // Check the final serviceIds set to be empty
            const serviceIds = await serviceStaking.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and checkpoint in the same timestamp twice", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(serviceStaking.address, serviceId);

            // Stake the first service
            await serviceStaking.stake(serviceId);

            // Get the service multisig contract
            const service = await serviceRegistry.getService(serviceId);
            const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Increase the time for the liveness period
            await helpers.time.increase(maxInactivity);

            // Construct the payload for the multisig
            let callData = [];
            let txs = [];
            const nonce = await multisig.nonce();
            // Add two addresses, and bump the threshold
            for (let i = 0; i < 2; i++) {
                callData[i] = serviceStaking.interface.encodeFunctionData("checkpoint", []);
                txs[i] = safeContracts.buildSafeTransaction({to: serviceStaking.address, data: callData[i], nonce: 0});
            }

            // Build and execute a multisend transaction to be executed by the service multisig (via its agent isntance)
            const safeTx = safeContracts.buildMultiSendSafeTx(multiSend, txs, nonce);
            await safeContracts.executeTxWithSigners(multisig, safeTx, [agentInstances[0]]);

            // Calculate service staking reward that must be greater than zero (calculated only in the first checkpoint)
            const reward = await serviceStaking.calculateServiceStakingReward(serviceId);
            expect(reward).to.greaterThan(0);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
            await serviceStaking.unstake(serviceId);
            const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter).to.gt(balanceBefore);

            // Check the final serviceIds set to be empty
            const serviceIds = await serviceStaking.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake to drain the full balance", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: serviceParams.rewardsPerSecond});

            // Approve services
            await serviceRegistry.approve(serviceStaking.address, serviceId);

            // Stake the first service
            await serviceStaking.stake(serviceId);

            // Get the service multisig contract
            const service = await serviceRegistry.getService(serviceId);
            const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Make transactions by the service multisig
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            let signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(livenessPeriod);

            // Call the checkpoint at this time
            await serviceStaking.checkpoint();

            // Execute one more multisig tx
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(maxInactivity);

            // Calculate service staking reward that must be greater than zero
            const reward = await serviceStaking.calculateServiceStakingReward(serviceId);
            expect(reward).to.greaterThan(0);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
            await serviceStaking.unstake(serviceId);
            const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter).to.gt(balanceBefore);

            // Check the final serviceIds set to be empty
            const serviceIds = await serviceStaking.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake to drain the full balance by several services", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: serviceParams.rewardsPerSecond});

            // Create and deploy one more service (serviceId == 3)
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, agentParams, threshold);
            await serviceRegistry.activateRegistration(deployer.address, serviceId + 2, {value: regDeposit});
            await serviceRegistry.registerAgents(operator.address, serviceId + 2, [agentInstances[2].address], agentIds, {value: regBond});
            await serviceRegistry.deploy(deployer.address, serviceId + 2, gnosisSafeMultisig.address, payload);

            for (let i = 0; i < 3; i++) {
                // Approve services
                await serviceRegistry.approve(serviceStaking.address, serviceId + i);

                // Stake the first service
                await serviceStaking.stake(serviceId + i);

                // Get the service multisig contract
                const service = await serviceRegistry.getService(serviceId + i);
                const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

                // Make transactions by the service multisig, except for the service Id == 3
                if (i < 2) {
                    const nonce = await multisig.nonce();
                    const txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
                    const signMessageData = await safeContracts.safeSignMessage(agentInstances[i], multisig, txHashData, 0);
                    await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);
                }
            }

            // Increase the time for the liveness period
            await helpers.time.increase(livenessPeriod);

            // Calculate service staking reward that must be greater than zero except for the serviceId == 3
            for (let i = 0; i < 2; i++) {
                const reward = await serviceStaking.calculateServiceStakingReward(serviceId + i);
                expect(reward).to.greaterThan(0);
            }

            // Call the checkpoint at this time
            await serviceStaking.checkpoint();

            // Execute one more multisig tx for services except for the service Id == 3
            for (let i = 0; i < 2; i++) {
                // Get the service multisig contract
                const service = await serviceRegistry.getService(serviceId + i);
                const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

                const nonce = await multisig.nonce();
                const txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
                const signMessageData = await safeContracts.safeSignMessage(agentInstances[i], multisig, txHashData, 0);
                await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);
            }


            // Increase the time for the liveness period
            await helpers.time.increase(maxInactivity);

            for (let i = 0; i < 3; i++) {
                // Calculate service staking reward that must be greater than zero except for the serviceId == 3
                const reward = await serviceStaking.calculateServiceStakingReward(serviceId + i);
                if (i < 2) {
                    expect(reward).to.greaterThan(0);
                } else {
                    expect(reward).to.equal(0);
                }

                // Get the service multisig contract
                const service = await serviceRegistry.getService(serviceId + i);
                const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

                // Unstake services
                const balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
                await serviceStaking.unstake(serviceId + i);
                const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

                // The balance before and after the unstake call must be different except for the serviceId == 3
                if (i < 2) {
                    expect(balanceAfter).to.gt(balanceBefore);
                } else {
                    expect(reward).to.equal(0);
                }
            }

            // Check the final serviceIds set to be empty
            const serviceIds = await serviceStaking.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake with the service activity", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(serviceStaking.address, serviceId);

            // Stake the first service
            await serviceStaking.stake(serviceId);

            // Take the staking timestamp
            let block = await ethers.provider.getBlock("latest");
            const tsStart = block.timestamp;

            // Get the service multisig contract
            const service = await serviceRegistry.getService(serviceId);
            const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Make transactions by the service multisig
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            let signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(livenessPeriod);

            // Call the checkpoint at this time
            await serviceStaking.checkpoint();

            // Execute one more multisig tx
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(livenessPeriod);

            block = await ethers.provider.getBlock("latest");
            const tsEnd = block.timestamp;

            // Get the expected reward
            const tsDiff = tsEnd - tsStart;
            const expectedReward = serviceParams.rewardsPerSecond * tsDiff;

            // Nonce is just 1 as there was 1 transaction
            const ratio = (10**18 * 1.0) / tsDiff;
            expect(ratio).to.greaterThan(Number(serviceParams.livenessRatio));

            // Calculate service staking reward that must match the calculated reward
            const reward = await serviceStaking.calculateServiceStakingReward(serviceId);
            expect(Number(reward)).to.equal(expectedReward);

            // Increase the time to be bigger than inactivity to unstake
            await helpers.time.increase(maxInactivity);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
            await serviceStaking.unstake(serviceId);
            const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter).to.gt(balanceBefore);

            // Check the final serviceIds set to be empty
            const serviceIds = await serviceStaking.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });
    });

    context("Reentrancy and failures", function () {
        it("Stake and checkpoint in the same tx", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            // Get the service multisig contract
            const service = await serviceRegistry.getService(serviceId);
            const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Transfer the service to the attacker (note we need to use the transfer not to get another reentrancy call)
            await serviceRegistry.transferFrom(deployer.address, attacker.address, serviceId);

            // Stake and checkpoint
            await attacker.stakeAndCheckpoint(serviceId);

            // Increase the time for the liveness period
            await helpers.time.increase(maxInactivity);

            // Make sure the service have not earned any rewards
            const reward = await serviceStaking.calculateServiceStakingReward(serviceId);
            expect(reward).to.equal(0);

            // Try to unstake the service with the re-entrancy will fail
            await expect(
                attacker.unstake(serviceId)
            ).to.be.reverted;

            // Unsetting the attack will allow to unstake the service
            await attacker.setAttack(false);
            const balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
            await attacker.unstake(serviceId);
            const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

            // Check that the service got no reward
            expect(balanceAfter).to.equal(balanceBefore);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Failure to stake a service with an unauthorized multisig proxy", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            // Redeploy the service with the attacker being the multisig
            await serviceRegistry.terminate(deployer.address, serviceId);
            await serviceRegistry.unbond(operator.address, serviceId);

            await attacker.setOwner(agentInstances[0].address);
            await serviceRegistry.activateRegistration(deployer.address, serviceId, {value: regDeposit});
            await serviceRegistry.registerAgents(operator.address, serviceId, [agentInstances[0].address], agentIds, {value: regBond});

            // Prepare the payload to redeploy with the attacker address
            const data = ethers.utils.solidityPack(["address"], [attacker.address]);
            await expect(
                serviceRegistry.deploy(deployer.address, serviceId, gnosisSafeSameAddressMultisig.address, data)
            ).to.be.revertedWithCustomError(gnosisSafeSameAddressMultisig, "UnauthorizedMultisig");

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Decrease nonce in the multisig and try to fail the checkpoint", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            // Get the service multisig contract
            const service = await serviceRegistry.getService(serviceId);
            const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Approve service for staking
            await serviceRegistry.approve(serviceStaking.address, serviceId);

            // Stake the service
            await serviceStaking.stake(serviceId);

            // Make a transaction by the service multisig
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            let signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(livenessPeriod);

            // Call the checkpoint at this time
            await serviceStaking.checkpoint();

            // Decrease the nonce
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(safeNonceLib, "decreaseNonce", [1000], nonce, 0, 0);
            // This must be a delegatecall
            txHashData.operation = 1;
            signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(livenessPeriod);

            // Call the checkpoint after the nonce has decreased
            await serviceStaking.checkpoint();

            // Restore a previous state of blockchain
            snapshot.restore();
        });
    });
});
