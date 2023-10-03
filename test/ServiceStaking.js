/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const safeContracts = require("@gnosis.pm/safe-contracts");

describe("ServiceStakingNativeToken", function () {
    let componentRegistry;
    let agentRegistry;
    let serviceRegistry;
    let serviceRegistryTokenUtility;
    let token;
    let gnosisSafe;
    let gnosisSafeProxyFactory;
    let gnosisSafeMultisig;
    let multiSend;
    let serviceStaking;
    let serviceStakingToken;
    let reentrancyAttacker;
    let signers;
    let deployer;
    let operator;
    let agentInstances;
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

        const MultiSend = await ethers.getContractFactory("MultiSendCallOnly");
        multiSend = await MultiSend.deploy();
        await multiSend.deployed();

        const ServiceStakingNativeToken = await ethers.getContractFactory("ServiceStakingNativeToken");
        serviceStaking = await ServiceStakingNativeToken.deploy(serviceParams, serviceRegistry.address);
        await serviceStaking.deployed();

        const ServiceStakingToken = await ethers.getContractFactory("ServiceStakingToken");
        serviceStakingToken = await ServiceStakingToken.deploy(serviceParams, serviceRegistry.address,
            serviceRegistryTokenUtility.address, token.address);
        await serviceStakingToken.deployed();

        const ReentrancyAttacker = await ethers.getContractFactory("ReentrancyTokenAttacker");
        reentrancyAttacker = await ReentrancyAttacker.deploy(serviceRegistryTokenUtility.address);
        await reentrancyAttacker.deployed();

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

        // Whitelist gnosis multisig implementation
        await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

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
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");

            testServiceParams.maxNumServices = 1;
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");

            testServiceParams.rewardsPerSecond = 1;
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");

            testServiceParams.minStakingDeposit = 1;
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");

            testServiceParams.livenessPeriod = 1;
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");

            testServiceParams.livenessRatio = 1;
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroValue");

            testServiceParams.numAgentInstances = 1;
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, AddressZero)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "ZeroAddress");

            testServiceParams.agentIds = [0];
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "WrongAgentId");

            testServiceParams.agentIds = [1, 1];
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "WrongAgentId");

            testServiceParams.agentIds = [2, 1];
            await expect(ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address)).to.be.revertedWithCustomError(ServiceStakingNativeToken, "WrongAgentId");


            // Service Staking Token
            testServiceParams = JSON.parse(JSON.stringify(defaultTestServiceParams));
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");

            testServiceParams.maxNumServices = 1;
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");

            testServiceParams.rewardsPerSecond = 1;
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");

            testServiceParams.minStakingDeposit = 1;
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");

            testServiceParams.livenessPeriod = 1;
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");

            testServiceParams.livenessRatio = 1;
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");

            testServiceParams.numAgentInstances = 1;
            await expect(ServiceStakingToken.deploy(testServiceParams, AddressZero, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroAddress");

            await expect(ServiceStakingToken.deploy(testServiceParams, serviceRegistry.address, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroAddress");
            await expect(ServiceStakingToken.deploy(testServiceParams, serviceRegistry.address, serviceRegistryTokenUtility.address, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroAddress");
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
            const testServiceParams = serviceParams;
            testServiceParams.maxNumServices = 1;
            const sStaking = await ServiceStakingNativeToken.deploy(serviceParams, serviceRegistry.address);
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
            const sStaking = await ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address);
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
            const sStaking = await ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address);
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
            const sStaking = await ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address);
            await sStaking.deployed();

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
            const sStaking = await ServiceStakingNativeToken.deploy(testServiceParams, serviceRegistry.address);
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
            ).to.be.revertedWithCustomError(serviceStakingToken, "LowerThan");
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

        it("Should fail when calculating staking rewards for the not staked service", async function () {
            await expect(
                serviceStaking.calculateServiceStakingReward(serviceId)
            ).to.be.revertedWithCustomError(serviceStaking, "ServiceNotStaked");
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

            // Get the service multisig contract
            const service = await serviceRegistry.getService(serviceId);
            const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Increase the time while the service does not reach the required amount of transactions per second (TPS)
            await helpers.time.increase(livenessPeriod);

            // Calculate service staking reward that must be zero
            const reward = await serviceStaking.calculateServiceStakingReward(serviceId);
            expect(reward).to.equal(0);

            // Unstake the service
            const balanceBefore = await ethers.provider.getBalance(multisig.address);
            await serviceStaking.unstake(serviceId);
            const balanceAfter = await ethers.provider.getBalance(multisig.address);

            // The multisig balance before and after unstake must be the same (zero reward)
            expect(balanceBefore).to.equal(balanceAfter);

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

            // Calculate service staking reward that must be greater than zero
            const reward = await serviceStaking.calculateServiceStakingReward(serviceId);
            expect(reward).to.greaterThan(0);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
            await serviceStaking.unstake(serviceId);
            const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter).to.gt(balanceBefore);

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
            await helpers.time.increase(livenessPeriod);

            // Calculate service staking reward that must be greater than zero
            const reward = await serviceStakingToken.calculateServiceStakingReward(sId);
            expect(reward).to.greaterThan(0);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await token.balanceOf(multisig.address));
            await serviceStakingToken.unstake(sId);
            const balanceAfter = ethers.BigNumber.from(await token.balanceOf(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter.gt(balanceBefore));

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
            await helpers.time.increase(livenessPeriod);

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
            await helpers.time.increase(livenessPeriod);

            // Calculate service staking reward that must be greater than zero
            const reward = await serviceStaking.calculateServiceStakingReward(serviceId);
            expect(reward).to.greaterThan(0);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
            await serviceStaking.unstake(serviceId);
            const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter).to.gt(balanceBefore);

            // Restore a previous state of blockchain
            snapshot.restore();
        });
    });
});
