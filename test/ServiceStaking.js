/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-network-helpers");
const safeContracts = require("@gnosis.pm/safe-contracts");

describe("Staking", function () {
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
    let stakingFactory;
    let stakingImplementation;
    let stakingNativeToken;
    let stakingTokenImplementation;
    let stakingToken;
    let stakingActivityChecker;
    let attacker;
    let signers;
    let deployer;
    let operator;
    let agentInstances;
    let bytecodeHash;
    const AddressZero = ethers.constants.AddressZero;
    const HashZero = ethers.constants.HashZero;
    const defaultHash = "0x" + "5".repeat(64);
    const regDeposit = 1000;
    const regBond = 1000;
    const serviceId = 1;
    const agentIds = [1];
    const agentParams = [[1, regBond]];
    const threshold = 1;
    const livenessPeriod = 10; // Ten seconds
    const initSupply = "5" + "0".repeat(26);
    const payload = "0x";
    const livenessRatio = "1" + "0".repeat(16); // 0.01 transaction per second (TPS)
    let serviceParams = {
        metadataHash: defaultHash,
        maxNumServices: 3,
        rewardsPerSecond: "1" + "0".repeat(15),
        minStakingDeposit: 10,
        minNumStakingPeriods: 3,
        maxNumInactivityPeriods: 3,
        livenessPeriod: livenessPeriod, // Ten seconds
        timeForEmissions: 100,
        numAgentInstances: 1,
        agentIds: [],
        threshold: 0,
        configHash: HashZero,
        proxyHash: HashZero,
        serviceRegistry: AddressZero,
        activityChecker: AddressZero
    };
    const maxInactivity = serviceParams.maxNumInactivityPeriods * livenessPeriod + 1;

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
        serviceParams.serviceRegistry = serviceRegistry.address;

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
        serviceParams.proxyHash = bytecodeHash;

        const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
        gnosisSafeSameAddressMultisig = await GnosisSafeSameAddressMultisig.deploy(bytecodeHash);
        await gnosisSafeSameAddressMultisig.deployed();

        const MultiSend = await ethers.getContractFactory("MultiSendCallOnly");
        multiSend = await MultiSend.deploy();
        await multiSend.deployed();

        const StakingFactory = await ethers.getContractFactory("StakingFactory");
        stakingFactory = await StakingFactory.deploy(AddressZero);
        await stakingFactory.deployed();

        const StakingActivityChecker = await ethers.getContractFactory("StakingActivityChecker");
        stakingActivityChecker = await StakingActivityChecker.deploy(livenessRatio);
        await stakingActivityChecker.deployed();
        serviceParams.activityChecker = stakingActivityChecker.address;

        const StakingNativeToken = await ethers.getContractFactory("StakingNativeToken");
        stakingImplementation = await StakingNativeToken.deploy();
        let initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
            [serviceParams]);
        const stakingAddress = await stakingFactory.callStatic.createStakingInstance(
            stakingImplementation.address, initPayload);
        await stakingFactory.createStakingInstance(stakingImplementation.address, initPayload);
        stakingNativeToken = await ethers.getContractAt("StakingNativeToken", stakingAddress);

        const StakingToken = await ethers.getContractFactory("StakingToken");
        stakingTokenImplementation = await StakingToken.deploy();
        initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
            [serviceParams, serviceRegistryTokenUtility.address, token.address]);
        const stakingTokenAddress = await stakingFactory.callStatic.createStakingInstance(
            stakingTokenImplementation.address, initPayload);
        await stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload);
        stakingToken = await ethers.getContractAt("StakingToken", stakingTokenAddress);

        const SafeNonceLib = await ethers.getContractFactory("SafeNonceLib");
        safeNonceLib = await SafeNonceLib.deploy();
        await safeNonceLib.deployed();

        const Attacker = await ethers.getContractFactory("ReentrancyStakingAttacker");
        attacker = await Attacker.deploy(stakingNativeToken.address, serviceRegistry.address);
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
            // Activity checker
            const StakingActivityChecker = await ethers.getContractFactory("StakingActivityChecker");
            await expect(
                StakingActivityChecker.deploy(0)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");

            const defaultTestServiceParams = {
                metadataHash: HashZero,
                maxNumServices: 0,
                rewardsPerSecond: 0,
                minStakingDeposit: 0,
                minNumStakingPeriods: 0,
                maxNumInactivityPeriods: 0,
                livenessPeriod: 0,
                timeForEmissions: 0,
                numAgentInstances: 0,
                agentIds: [],
                threshold: 0,
                configHash: HashZero,
                proxyHash: HashZero,
                serviceRegistry: AddressZero,
                activityChecker: AddressZero
            };

            // Service Staking Native Token
            let testServiceParams = JSON.parse(JSON.stringify(defaultTestServiceParams));
            let initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");

            testServiceParams.metadataHash = defaultHash;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");

            testServiceParams.maxNumServices = 1;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");

            testServiceParams.rewardsPerSecond = 1;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");

            testServiceParams.livenessPeriod = 1;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");

            testServiceParams.livenessRatio = 1;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");

            testServiceParams.numAgentInstances = 1;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");

            testServiceParams.timeForEmissions = 1;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");

            testServiceParams.minNumStakingPeriods = 1;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");

            testServiceParams.maxNumInactivityPeriods = 2;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "LowerThan");

            testServiceParams.maxNumInactivityPeriods = 1;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "LowerThan");

            testServiceParams.minStakingDeposit = 2;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroAddress");

            testServiceParams.serviceRegistry = serviceRegistry.address;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroAddress");

            testServiceParams.activityChecker = deployer.address;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ContractOnly");

            testServiceParams.activityChecker = stakingActivityChecker.address;
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");

            testServiceParams.agentIds = [0];
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "WrongAgentId");

            testServiceParams.agentIds = [1, 1];
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "WrongAgentId");

            testServiceParams.agentIds = [2, 1];
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "WrongAgentId");

            testServiceParams.agentIds = [];
            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");

            initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            await expect(
                stakingFactory.createStakingInstance(stakingImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingImplementation, "ZeroValue");


            // Service Staking Token
            testServiceParams = JSON.parse(JSON.stringify(defaultTestServiceParams));
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroValue");

            testServiceParams.metadataHash = defaultHash;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroValue");

            testServiceParams.maxNumServices = 1;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroValue");

            testServiceParams.rewardsPerSecond = 1;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroValue");

            testServiceParams.livenessPeriod = 1;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroValue");

            testServiceParams.livenessRatio = 1;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroValue");

            testServiceParams.numAgentInstances = 1;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroValue");

            testServiceParams.timeForEmissions = 1;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroValue");

            testServiceParams.minNumStakingPeriods = 1;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroValue");

            testServiceParams.maxNumInactivityPeriods = 2;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "LowerThan");

            testServiceParams.maxNumInactivityPeriods = 1;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "LowerThan");

            testServiceParams.minStakingDeposit = 2;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroAddress");

            testServiceParams.serviceRegistry = serviceRegistry.address;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroAddress");

            testServiceParams.activityChecker = stakingActivityChecker.address;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, AddressZero, token.address]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroValue");

            testServiceParams.proxyHash = bytecodeHash;
            initPayload = stakingTokenImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams, serviceRegistryTokenUtility.address, AddressZero]);
            await expect(
                stakingFactory.createStakingInstance(stakingTokenImplementation.address, initPayload)
            ).to.be.revertedWithCustomError(stakingTokenImplementation, "ZeroTokenAddress");
        });
    });

    context("Staking to StakingNativeToken and StakingToken", function () {
        it("Should fail if there are no available rewards", async function () {
            await expect(
                stakingNativeToken.stake(serviceId)
            ).to.be.revertedWithCustomError(stakingNativeToken, "NoRewardsAvailable");
        });

        it("Should fail if the maximum number of staking services is reached", async function () {
            // Deploy a contract with max number of services equal to one
            const testServiceParams = JSON.parse(JSON.stringify(serviceParams));
            testServiceParams.maxNumServices = 1;
            let initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            const sStakingAddress = await stakingFactory.callStatic.createStakingInstance(
                stakingImplementation.address, initPayload);
            await stakingFactory.createStakingInstance(stakingImplementation.address, initPayload);
            const sStaking = await ethers.getContractAt("StakingNativeToken", sStakingAddress);

            // Try to initialize once again
            await expect(
                sStaking.initialize(testServiceParams)
            ).to.be.revertedWithCustomError(sStaking, "AlreadyInitialized");

            // Deposit to the contract
            await deployer.sendTransaction({to: sStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(sStaking.address, serviceId);
            await serviceRegistry.approve(sStaking.address, serviceId + 1);

            // Stake the service
            await sStaking.stake(serviceId);

            // Staking next service is going to fail
            await expect(
                sStaking.stake(serviceId + 1)
            ).to.be.revertedWithCustomError(sStaking, "MaxNumServicesReached");
        });

        it("Should fail when the service is not deployed", async function () {
            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Create a new service (serviceId == 3)
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, agentParams, threshold);

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId + 2);

            await expect(
                stakingNativeToken.stake(serviceId + 2)
            ).to.be.revertedWithCustomError(stakingNativeToken, "WrongServiceState");
        });

        it("Should fail when the maximum number of instances is incorrect", async function () {
            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Create a new service (serviceId == 3)
            await serviceRegistry.create(deployer.address, defaultHash, [1, 2], [agentParams[0], agentParams[0]], 2);

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId + 2);

            await expect(
                stakingNativeToken.stake(serviceId + 2)
            ).to.be.revertedWithCustomError(stakingNativeToken, "WrongServiceConfiguration");
        });

        it("Should fail when the specified config of the service does not match", async function () {
            // Deploy a contract with a different service config specification
            const testServiceParams = JSON.parse(JSON.stringify(serviceParams));
            testServiceParams.configHash = "0x" + "1".repeat(64);
            let initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            const sStakingAddress = await stakingFactory.callStatic.createStakingInstance(
                stakingImplementation.address, initPayload);
            await stakingFactory.createStakingInstance(stakingImplementation.address, initPayload);
            const sStaking = await ethers.getContractAt("StakingNativeToken", sStakingAddress);

            // Deposit to the contract
            await deployer.sendTransaction({to: sStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(sStaking.address, serviceId);

            await expect(
                sStaking.stake(serviceId)
            ).to.be.revertedWithCustomError(sStaking, "WrongServiceConfiguration");
        });

        it("Should fail when the multisig hash is incorrect", async function () {
            // Deploy a contract with a different service config specification
            const testBytecodeHash = "0x" + "0".repeat(63) + "1";
            serviceParams.proxyHash = testBytecodeHash;
            let initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [serviceParams]);
            const sStakingAddress = await stakingFactory.callStatic.createStakingInstance(
                stakingImplementation.address, initPayload);
            await stakingFactory.createStakingInstance(stakingImplementation.address, initPayload);
            const sStaking = await ethers.getContractAt("StakingNativeToken", sStakingAddress);

            // Deposit to the contract
            await deployer.sendTransaction({to: sStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(sStaking.address, serviceId);

            await expect(
                sStaking.stake(serviceId)
            ).to.be.revertedWithCustomError(sStaking, "UnauthorizedMultisig");
        });

        it("Should fail when the specified threshold of the service does not match", async function () {
            // Deploy a contract with a different service config specification
            const testServiceParams = JSON.parse(JSON.stringify(serviceParams));
            testServiceParams.threshold = 2;
            let initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            const sStakingAddress = await stakingFactory.callStatic.createStakingInstance(
                stakingImplementation.address, initPayload);
            await stakingFactory.createStakingInstance(stakingImplementation.address, initPayload);
            const sStaking = await ethers.getContractAt("StakingNativeToken", sStakingAddress);

            // Deposit to the contract
            await deployer.sendTransaction({to: sStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(sStaking.address, serviceId);

            await expect(
                sStaking.stake(serviceId)
            ).to.be.revertedWithCustomError(sStaking, "WrongServiceConfiguration");
        });

        it("Should fail when the optional agent Ids do not match in the service", async function () {
            // Deploy a service staking contract with specific agent Ids
            let testServiceParams = JSON.parse(JSON.stringify(serviceParams));
            testServiceParams.agentIds = [1];
            let initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            const sStakingAddress = await stakingFactory.callStatic.createStakingInstance(
                stakingImplementation.address, initPayload);
            await stakingFactory.createStakingInstance(stakingImplementation.address, initPayload);
            const sStaking = await ethers.getContractAt("StakingNativeToken", sStakingAddress);

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
            let testServiceParams = JSON.parse(JSON.stringify(serviceParams));
            testServiceParams.agentIds = [1];
            testServiceParams.numAgentInstances = 2;
            let initPayload = stakingImplementation.interface.encodeFunctionData("initialize",
                [testServiceParams]);
            const sStakingAddress = await stakingFactory.callStatic.createStakingInstance(
                stakingImplementation.address, initPayload);
            await stakingFactory.createStakingInstance(stakingImplementation.address, initPayload);
            const sStaking = await ethers.getContractAt("StakingNativeToken", sStakingAddress);

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
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            const securityDeposit = 1;

            // Create a new service (serviceId == 3), activate, register agents and deploy
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, [[1, securityDeposit]], threshold);
            await serviceRegistry.activateRegistration(deployer.address, serviceId + 2, {value: securityDeposit});
            await serviceRegistry.registerAgents(operator.address, serviceId + 2, [agentInstances[2].address], agentIds, {value: securityDeposit});
            await serviceRegistry.deploy(deployer.address, serviceId + 2, gnosisSafeMultisig.address, payload);

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId + 2);

            await expect(
                stakingNativeToken.stake(serviceId + 2)
            ).to.be.revertedWithCustomError(stakingNativeToken, "LowerThan");
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
            await token.approve(stakingToken.address, initSupply);
            await stakingToken.deposit(regBond);

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
            await serviceRegistry.approve(stakingToken.address, sId);

            await expect(
                stakingToken.stake(sId)
            ).to.be.revertedWithCustomError(stakingToken, "WrongStakingToken");
        });

        it("Should fail when the service has insufficient security / staking deposit", async function () {
            // Approve token2 for the ServiceRegistryTokenUtility
            await token.approve(serviceRegistryTokenUtility.address, initSupply);
            await token.connect(operator).approve(serviceRegistryTokenUtility.address, initSupply);
            // Approve and deposit token to the staking contract
            await token.approve(stakingToken.address, initSupply);
            await stakingToken.deposit(regBond);

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
            await serviceRegistry.approve(stakingToken.address, sId);

            await expect(
                stakingToken.stake(sId)
            ).to.be.revertedWithCustomError(stakingToken, "ValueLowerThan");
        });

        it("Stake a service at StakingNativeToken and try to unstake not by the service owner", async function () {
            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId);

            // Stake the service
            await stakingNativeToken.stake(serviceId);

            // Try to unstake not by the owner
            await expect(
                stakingNativeToken.connect(operator).unstake(serviceId)
            ).to.be.revertedWithCustomError(stakingNativeToken, "OwnerOnly");
        });

        it("Stake a service at StakingToken", async function () {
            // Approve ServiceRegistryTokenUtility
            await token.approve(serviceRegistryTokenUtility.address, initSupply);
            await token.connect(operator).approve(serviceRegistryTokenUtility.address, initSupply);
            // Approve and deposit token to the staking contract
            await token.approve(stakingToken.address, initSupply);
            await stakingToken.deposit(regBond);

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
            await serviceRegistry.approve(stakingToken.address, sId);

            await stakingToken.stake(sId);
        });

        it("Returns zero rewards for the not staked service", async function () {
            const reward = await stakingNativeToken.calculateStakingReward(serviceId);
            expect(reward).to.equal(0);
        });
    });

    context("Staking and unstaking", function () {
        it("Should fail when trying to unstake without staking for a minimum required time", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId);

            // Stake the service
            await stakingNativeToken.stake(serviceId);

            // Trying to unstake right away
            await expect(
                stakingNativeToken.unstake(serviceId)
            ).to.be.revertedWithCustomError(stakingNativeToken, "NotEnoughTimeStaked");

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake without any service activity", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId);

            // Stake the service
            await stakingNativeToken.stake(serviceId);

            // Check that the service is staked
            let stakingState = await stakingNativeToken.getStakingState(serviceId);
            expect(stakingState).to.equal(1);

            // Get the service multisig contract
            const service = await serviceRegistry.getService(serviceId);
            const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Increase the time while the service does not reach the required amount of transactions per second (TPS)
            await helpers.time.increase(maxInactivity);

            // Calculate service staking reward that must be zero
            const reward = await stakingNativeToken.calculateStakingReward(serviceId);
            expect(reward).to.equal(0);

            // Call the checkpoint
            await stakingNativeToken.checkpoint();

            // By this time, services are evicted
            // Check that the service is evicted
            stakingState = await stakingNativeToken.getStakingState(serviceId);
            expect(stakingState).to.equal(2);

            // After the eviction, check the final serviceIds set to be empty
            const serviceIds = await stakingNativeToken.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Try to stake evicted service
            await expect(
                stakingNativeToken.stake(serviceId)
            ).to.be.revertedWithCustomError(stakingNativeToken, "ServiceNotUnstaked");

            // Unstake the service
            const balanceBefore = await ethers.provider.getBalance(multisig.address);
            await stakingNativeToken.unstake(serviceId);
            const balanceAfter = await ethers.provider.getBalance(multisig.address);

            // Check that the service is unstaked
            stakingState = await stakingNativeToken.getStakingState(serviceId);
            expect(stakingState).to.equal(0);

            // The multisig balance before and after unstake must be the same (zero reward)
            expect(balanceBefore).to.equal(balanceAfter);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake right away without any service activity for two services", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId);
            await serviceRegistry.approve(stakingNativeToken.address, serviceId + 1);

            // Stake services
            await stakingNativeToken.stake(serviceId);
            await stakingNativeToken.stake(serviceId + 1);

            // Call the checkpoint to make sure the rewards logic is not hit
            await stakingNativeToken.checkpoint();

            // Get the next checkpoint timestamp and compare with the next reward timestamp
            const tsNext = Number(await stakingNativeToken.getNextRewardCheckpointTimestamp());
            const tsLast = Number(await stakingNativeToken.tsCheckpoint());
            const livenessPeriod = Number(await stakingNativeToken.livenessPeriod());
            expect(tsNext - tsLast).to.equal(livenessPeriod);

            // Calculate service staking reward that must be zero
            let reward = await stakingNativeToken.calculateStakingReward(serviceId);
            expect(reward).to.equal(0);
            reward = await stakingNativeToken.calculateStakingReward(serviceId + 1);
            expect(reward).to.equal(0);

            // Get the service multisig contract
            let service = await serviceRegistry.getService(serviceId);
            let multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Increase the time before unstake
            await helpers.time.increase(maxInactivity);

            // Unstake services
            let balanceBefore = await ethers.provider.getBalance(multisig.address);
            await stakingNativeToken.unstake(serviceId);
            let balanceAfter = await ethers.provider.getBalance(multisig.address);

            // The multisig balance before and after unstake must be the same (zero reward)
            expect(balanceBefore).to.equal(balanceAfter);

            // Get the service multisig contract
            service = await serviceRegistry.getService(serviceId + 1);
            multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            balanceBefore = await ethers.provider.getBalance(multisig.address);
            await stakingNativeToken.unstake(serviceId + 1);
            balanceAfter = await ethers.provider.getBalance(multisig.address);

            // The multisig balance before and after unstake must be the same (zero reward)
            expect(balanceBefore).to.equal(balanceAfter);

            // Check the final serviceIds set to be empty
            const serviceIds = await stakingNativeToken.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake with the service activity", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId);

            // Stake the service
            await stakingNativeToken.stake(serviceId);

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
            await stakingNativeToken.checkpoint();

            // Checking the nonce info
            let serviceInfo = await stakingNativeToken.getServiceInfo(serviceId);
            const lastNonce = serviceInfo.nonces[0];
            expect(lastNonce).to.greaterThan(0);

            // Execute one more multisig tx
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(maxInactivity);

            // Checking the nonce info (it is not updated as none of checkpoint or unstake were called)
            serviceInfo = await stakingNativeToken.getServiceInfo(serviceId);
            const lastLastNonce = serviceInfo.nonces[0];
            expect(lastLastNonce).to.equal(lastNonce);

            // Calculate service staking reward that must be greater than zero
            const reward = await stakingNativeToken.calculateStakingReward(serviceId);
            expect(reward).to.greaterThan(0);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
            await stakingNativeToken.unstake(serviceId);
            const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter).to.gt(balanceBefore);

            // Check the final serviceIds set to be empty
            const serviceIds = await stakingNativeToken.getServiceIds();
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
            await token.approve(stakingToken.address, initSupply);
            await stakingToken.deposit(ethers.utils.parseEther("1"));

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
            await serviceRegistry.approve(stakingToken.address, sId);

            // Stake the service
            await stakingToken.stake(sId);

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
            await stakingToken.checkpoint();

            // Execute one more multisig tx
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            signMessageData = await safeContracts.safeSignMessage(agentInstances[2], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(maxInactivity);

            // Calculate service staking reward that must be greater than zero
            const reward = await stakingToken.calculateStakingReward(sId);
            expect(reward).to.greaterThan(0);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await token.balanceOf(multisig.address));
            await stakingToken.unstake(sId);
            const balanceAfter = ethers.BigNumber.from(await token.balanceOf(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter.gt(balanceBefore));

            // Check the final serviceIds set to be empty
            const serviceIds = await stakingNativeToken.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and checkpoint in the same timestamp twice", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId);

            // Stake the service
            await stakingNativeToken.stake(serviceId);

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
                callData[i] = stakingNativeToken.interface.encodeFunctionData("checkpoint", []);
                txs[i] = safeContracts.buildSafeTransaction({to: stakingNativeToken.address, data: callData[i], nonce: 0});
            }

            // Build and execute a multisend transaction to be executed by the service multisig (via its agent isntance)
            const safeTx = safeContracts.buildMultiSendSafeTx(multiSend, txs, nonce);
            await safeContracts.executeTxWithSigners(multisig, safeTx, [agentInstances[0]]);

            // Calculate service staking reward that must be greater than zero (calculated only in the first checkpoint)
            const reward = await stakingNativeToken.calculateStakingReward(serviceId);
            expect(reward).to.greaterThan(0);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
            await stakingNativeToken.unstake(serviceId);
            const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter).to.gt(balanceBefore);

            // Check the final serviceIds set to be empty
            const serviceIds = await stakingNativeToken.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake to drain the full balance", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: serviceParams.rewardsPerSecond});

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId);

            // Stake the service
            await stakingNativeToken.stake(serviceId);

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
            await stakingNativeToken.checkpoint();

            // Execute one more multisig tx
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(maxInactivity);

            // Calculate service staking reward that must be greater than zero
            const reward = await stakingNativeToken.calculateStakingReward(serviceId);
            expect(reward).to.greaterThan(0);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
            await stakingNativeToken.unstake(serviceId);
            const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter).to.gt(balanceBefore);

            // Check the final serviceIds set to be empty
            const serviceIds = await stakingNativeToken.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake to drain the full balance by several services", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: serviceParams.rewardsPerSecond});

            // Create and deploy one more service (serviceId == 3)
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, agentParams, threshold);
            await serviceRegistry.activateRegistration(deployer.address, serviceId + 2, {value: regDeposit});
            await serviceRegistry.registerAgents(operator.address, serviceId + 2, [agentInstances[2].address], agentIds, {value: regBond});
            await serviceRegistry.deploy(deployer.address, serviceId + 2, gnosisSafeMultisig.address, payload);

            for (let i = 0; i < 3; i++) {
                // Approve services
                await serviceRegistry.approve(stakingNativeToken.address, serviceId + i);

                // Stake the service
                await stakingNativeToken.stake(serviceId + i);

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
                const reward = await stakingNativeToken.calculateStakingReward(serviceId + i);
                expect(reward).to.greaterThan(0);
            }

            // Call the checkpoint at this time
            await stakingNativeToken.checkpoint();

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

            // Check staking status to be staked
            for (let i = 0; i < 3; i++) {
                const stakingState = await stakingNativeToken.getStakingState(serviceId + i);
                expect(stakingState).to.equal(1);
            }

            // Increase the time for the liveness period
            await helpers.time.increase(livenessPeriod);

            // Call the checkpoint
            await stakingNativeToken.checkpoint();

            // Check staking status to be staked
            for (let i = 0; i < 3; i++) {
                const stakingState = await stakingNativeToken.getStakingState(serviceId + i);
                expect(stakingState).to.equal(1);
            }

            for (let i = 0; i < 3; i++) {
                // Calculate service staking reward that must be greater than zero except for the serviceId == 3
                const reward = await stakingNativeToken.calculateStakingReward(serviceId + i);
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
                await stakingNativeToken.unstake(serviceId + i);
                const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

                // The balance before and after the unstake call must be different except for the serviceId == 3
                if (i < 2) {
                    expect(balanceAfter).to.gt(balanceBefore);
                } else {
                    expect(reward).to.equal(0);
                }
            }

            // Check the final serviceIds set to be empty
            const serviceIds = await stakingNativeToken.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake with one service being inactive", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Create and deploy one more service (serviceId == 3)
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, agentParams, threshold);
            await serviceRegistry.activateRegistration(deployer.address, serviceId + 2, {value: regDeposit});
            await serviceRegistry.registerAgents(operator.address, serviceId + 2, [agentInstances[2].address], agentIds, {value: regBond});
            await serviceRegistry.deploy(deployer.address, serviceId + 2, gnosisSafeMultisig.address, payload);

            for (let i = 0; i < 3; i++) {
                // Approve services
                await serviceRegistry.approve(stakingNativeToken.address, serviceId + i);

                // Stake the service
                await stakingNativeToken.stake(serviceId + i);

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
                const reward = await stakingNativeToken.calculateStakingReward(serviceId + i);
                expect(reward).to.greaterThan(0);
            }

            // Call the checkpoint at this time
            await stakingNativeToken.checkpoint();

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

            // Check staking status to be staked
            for (let i = 0; i < 3; i++) {
                const stakingState = await stakingNativeToken.getStakingState(serviceId + i);
                expect(stakingState).to.equal(1);
            }

            // Increase the time for the twice the liveness period
            await helpers.time.increase(2 * livenessPeriod);

            // Call the checkpoint
            await stakingNativeToken.checkpoint();

            // Check staking status to be staked for the first two services
            for (let i = 0; i < 2; i++) {
                const stakingState = await stakingNativeToken.getStakingState(serviceId + i);
                expect(stakingState).to.equal(1);
            }
            // The last service must be evicted by that time
            const stakingState = await stakingNativeToken.getStakingState(serviceId + 2);
            expect(stakingState).to.equal(2);

            for (let i = 0; i < 3; i++) {
                // Calculate service staking reward that must be greater than zero except for the serviceId == 3
                const reward = await stakingNativeToken.calculateStakingReward(serviceId + i);
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
                await stakingNativeToken.unstake(serviceId + i);
                const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

                // The balance before and after the unstake call must be different except for the serviceId == 3
                if (i < 2) {
                    expect(balanceAfter).to.gt(balanceBefore);
                } else {
                    expect(reward).to.equal(0);
                }
            }

            // Check the final serviceIds set to be empty
            const serviceIds = await stakingNativeToken.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake the full allowed number of services, evict all of them and stake again", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Create and deploy one more service (serviceId == 3)
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, agentParams, threshold);
            await serviceRegistry.activateRegistration(deployer.address, serviceId + 2, {value: regDeposit});
            await serviceRegistry.registerAgents(operator.address, serviceId + 2, [agentInstances[2].address], agentIds, {value: regBond});
            await serviceRegistry.deploy(deployer.address, serviceId + 2, gnosisSafeMultisig.address, payload);

            // Stake 3 initial services
            for (let i = 0; i < 3; i++) {
                // Approve services
                await serviceRegistry.approve(stakingNativeToken.address, serviceId + i);

                // Stake the service
                await stakingNativeToken.stake(serviceId + i);
            }

            // Increase the time for the liveness period
            await helpers.time.increase(maxInactivity);

            // Call the checkpoint at this time (all services will be evicted)
            await stakingNativeToken.checkpoint();

            // Check the staking state of all the services
            for (let i = 0; i < 3; i++) {
                const stakingState = await stakingNativeToken.getStakingState(serviceId + i);
                expect(stakingState).to.equal(2);
            }

            // Try to stake the same service again
            await expect(
                stakingNativeToken.stake(serviceId)
            ).to.be.revertedWithCustomError(stakingNativeToken, "ServiceNotUnstaked");

            // Create and deploy yet one more service (serviceId == 4)
            await serviceRegistry.create(deployer.address, defaultHash, [1], agentParams, threshold);
            await serviceRegistry.activateRegistration(deployer.address, serviceId + 3, {value: regDeposit});
            await serviceRegistry.registerAgents(operator.address, serviceId + 3, [agentInstances[3].address], agentIds, {value: regBond});
            await serviceRegistry.deploy(deployer.address, serviceId + 3, gnosisSafeMultisig.address, payload);

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId + 3);

            // Stake the service
            await stakingNativeToken.stake(serviceId + 3);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake and unstake with the service activity", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId);

            // Stake the service
            await stakingNativeToken.stake(serviceId);

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
            await stakingNativeToken.checkpoint();

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
            expect(ratio).to.greaterThan(Number(livenessRatio));

            // Calculate service staking reward that must match the calculated reward
            const reward = await stakingNativeToken.calculateStakingReward(serviceId);
            expect(Number(reward)).to.equal(expectedReward);

            // Increase the time to be bigger than inactivity to unstake
            await helpers.time.increase(maxInactivity);

            // Unstake the service
            const balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
            await stakingNativeToken.unstake(serviceId);
            const balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter).to.gt(balanceBefore);

            // Check the final serviceIds set to be empty
            const serviceIds = await stakingNativeToken.getServiceIds();
            expect(serviceIds.length).to.equal(0);

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Stake, claim and unstake with the service activity", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(stakingNativeToken.address, serviceId);

            // Stake the service
            await stakingNativeToken.stake(serviceId);

            // Try to claim not by the service owner
            await expect(
                stakingNativeToken.connect(signers[1]).claim(serviceId)
            ).to.be.revertedWithCustomError(stakingNativeToken, "OwnerOnly");

            // Try to claim right away
            await expect(
                stakingNativeToken.claim(serviceId)
            ).to.be.revertedWithCustomError(stakingNativeToken, "ZeroValue");

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

            // Try to call claim without calling a single checkpoint
            await expect(
                stakingNativeToken.claim(serviceId)
            ).to.be.revertedWithCustomError(stakingNativeToken, "ZeroValue");

            let reward = await stakingNativeToken.calculateStakingReward(serviceId);
            let claimReward = await stakingNativeToken.callStatic.checkpointAndClaim(serviceId);
            expect(reward).to.equal(claimReward);

            // Call claim (calls checkpoint as well)
            await stakingNativeToken.checkpointAndClaim(serviceId);

            // Try to claim again right away
            await expect(
                stakingNativeToken.claim(serviceId)
            ).to.be.revertedWithCustomError(stakingNativeToken, "ZeroValue");

            // Execute one more multisig tx
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(livenessPeriod);

            // Check that the reward during unstake now is the same as the claimed reward
            reward = await stakingNativeToken.calculateStakingReward(serviceId);
            claimReward = await stakingNativeToken.callStatic.checkpointAndClaim(serviceId);
            expect(reward).to.equal(claimReward);

            // Claim the reward
            let balanceBefore = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));
            await stakingNativeToken.checkpointAndClaim(serviceId);
            let balanceAfter = ethers.BigNumber.from(await ethers.provider.getBalance(multisig.address));

            // The balance before and after the unstake call must be different
            expect(balanceAfter).to.gt(balanceBefore);

            // Execute one more multisig tx
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(livenessPeriod);

            // Check that the reward during unstake now is the same as the claimed reward
            reward = await stakingNativeToken.calculateStakingReward(serviceId);
            let unstakedReward = await stakingNativeToken.callStatic.unstake(serviceId);
            expect(reward).to.equal(unstakedReward);
            expect(claimReward).to.gte(unstakedReward);

            // Restore a previous state of blockchain
            snapshot.restore();
        });
    });

    context("Reentrancy and failures", function () {
        it("Stake and checkpoint in the same tx", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

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
            const reward = await stakingNativeToken.calculateStakingReward(serviceId);
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

        it("Trying to reenter the claim function", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Get the service multisig contract
            const service = await serviceRegistry.getService(serviceId);
            const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Transfer the service to the attacker (note we need to use the transfer not to get another reentrancy call)
            await serviceRegistry.transferFrom(deployer.address, attacker.address, serviceId);

            // Stake and checkpoint
            await attacker.stake(serviceId);

            // Make transactions by the service multisig
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            let signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(livenessPeriod);

            let reward = await stakingNativeToken.calculateStakingReward(serviceId);
            expect(reward).to.gt(0);

            // Try to perform a reentrancy attack during claim
            await attacker.checkpointAndClaim(serviceId);
            // Receive funds by attacker and call claim() right away
            nonce = await multisig.nonce();
            txHashData = await safeContracts.buildContractCall(attacker, "getThreshold", [], nonce, 0, 0);
            txHashData.data = "0x";
            txHashData.value = reward;
            signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await expect(
                safeContracts.executeTx(multisig, txHashData, [signMessageData], 0)
            ).to.be.reverted;

            // Restore a previous state of blockchain
            snapshot.restore();
        });

        it("Failure to stake a service with an unauthorized multisig proxy", async function () {
            // Take a snapshot of the current state of the blockchain
            const snapshot = await helpers.takeSnapshot();

            // Deposit to the contract
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

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
            await deployer.sendTransaction({to: stakingNativeToken.address, value: ethers.utils.parseEther("1")});

            // Get the service multisig contract
            const service = await serviceRegistry.getService(serviceId);
            const multisig = await ethers.getContractAt("GnosisSafe", service.multisig);

            // Approve service for staking
            await serviceRegistry.approve(stakingNativeToken.address, serviceId);

            // Stake the service
            await stakingNativeToken.stake(serviceId);

            // Make a transaction by the service multisig
            let nonce = await multisig.nonce();
            let txHashData = await safeContracts.buildContractCall(multisig, "getThreshold", [], nonce, 0, 0);
            let signMessageData = await safeContracts.safeSignMessage(agentInstances[0], multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Increase the time for the liveness period
            await helpers.time.increase(livenessPeriod);

            // Call the checkpoint at this time
            await stakingNativeToken.checkpoint();

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
            await stakingNativeToken.checkpoint();

            // Restore a previous state of blockchain
            snapshot.restore();
        });
    });
});
