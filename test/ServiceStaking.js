/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ServiceStaking", function () {
    let componentRegistry;
    let agentRegistry;
    let serviceRegistry;
    let serviceRegistryTokenUtility;
    let token;
    let gnosisSafe;
    let gnosisSafeProxyFactory;
    let gnosisSafeMultisig;
    let serviceStaking;
    let serviceStakingToken;
    let reentrancyAttacker;
    let signers;
    let deployer;
    let operator;
    const maxNumServices = 10;
    const rewardsPerSecond = 10;
    const minStakingDeposit = 10;
    const livenessRatio = "1" + "0".repeat(18);
    const AddressZero = ethers.constants.AddressZero;
    const uint256MaxValue = ethers.constants.MaxUint256;
    const defaultHash = "0x" + "5".repeat(64);
    const regDeposit = 1000;
    const regBond = 1000;
    const serviceId = 1;
    const agentIds = [1];
    const bonds = [regBond];
    const agentParams = [[1, regBond]];
    const threshold = 1;
    const initSupply = "5" + "0".repeat(26);
    const payload = "0x";

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

        const ServiceStaking = await ethers.getContractFactory("ServiceStaking");
        serviceStaking = await ServiceStaking.deploy(maxNumServices, rewardsPerSecond, minStakingDeposit,
            livenessRatio, serviceRegistry.address);
        await serviceStaking.deployed();

        const ServiceStakingToken = await ethers.getContractFactory("ServiceStakingToken");
        serviceStakingToken = await ServiceStakingToken.deploy(maxNumServices, rewardsPerSecond, minStakingDeposit,
            livenessRatio, serviceRegistry.address, serviceRegistryTokenUtility.address, token.address);
        await serviceStaking.deployed();

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

        // Create two services
        await componentRegistry.create(deployer.address, defaultHash, []);
        await agentRegistry.create(deployer.address, defaultHash, [1]);
        await serviceRegistry.create(deployer.address, defaultHash, agentIds, agentParams, threshold);
        await serviceRegistry.create(deployer.address, defaultHash, agentIds, agentParams, threshold);

        // Activate registration
        await serviceRegistry.activateRegistration(deployer.address, serviceId, {value: regDeposit});
        await serviceRegistry.activateRegistration(deployer.address, serviceId + 1, {value: regDeposit});

        // Register agent instances
        await serviceRegistry.registerAgents(operator.address, serviceId, [signers[2].address], agentIds, {value: regBond});
        await serviceRegistry.registerAgents(operator.address, serviceId + 1, [signers[3].address], agentIds, {value: regBond});

        // Whitelist gnosis multisig implementation
        await serviceRegistry.changeMultisigPermission(gnosisSafeMultisig.address, true);

        // Deploy services
        await serviceRegistry.deploy(deployer.address, serviceId, gnosisSafeMultisig.address, payload);
        await serviceRegistry.deploy(deployer.address, serviceId + 1, gnosisSafeMultisig.address, payload);
    });

    context("Initialization", function () {
        it("Should not allow the zero values and addresses when deploying contracts", async function () {
            const ServiceStaking = await ethers.getContractFactory("ServiceStaking");
            const ServiceStakingToken = await ethers.getContractFactory("ServiceStakingToken");

            await expect(ServiceStaking.deploy(0, 0, 0, 0, AddressZero)).to.be.revertedWithCustomError(ServiceStaking, "ZeroValue");
            await expect(ServiceStaking.deploy(maxNumServices, 0, 0, 0, AddressZero)).to.be.revertedWithCustomError(ServiceStaking, "ZeroValue");
            await expect(ServiceStaking.deploy(maxNumServices, rewardsPerSecond, 0, 0, AddressZero)).to.be.revertedWithCustomError(ServiceStaking, "ZeroValue");
            await expect(ServiceStaking.deploy(maxNumServices, rewardsPerSecond, minStakingDeposit, 0, AddressZero)).to.be.revertedWithCustomError(ServiceStaking, "ZeroValue");
            await expect(ServiceStaking.deploy(maxNumServices, rewardsPerSecond, minStakingDeposit, livenessRatio, AddressZero)).to.be.revertedWithCustomError(ServiceStaking, "ZeroAddress");

            await expect(ServiceStakingToken.deploy(0, 0, 0, 0, AddressZero, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");
            await expect(ServiceStakingToken.deploy(maxNumServices, 0, 0, 0, AddressZero, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");
            await expect(ServiceStakingToken.deploy(maxNumServices, rewardsPerSecond, 0, 0, AddressZero, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");
            await expect(ServiceStakingToken.deploy(maxNumServices, rewardsPerSecond, minStakingDeposit, 0, AddressZero, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroValue");
            await expect(ServiceStakingToken.deploy(maxNumServices, rewardsPerSecond, minStakingDeposit, livenessRatio, AddressZero, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroAddress");
            await expect(ServiceStakingToken.deploy(maxNumServices, rewardsPerSecond, minStakingDeposit, livenessRatio, serviceRegistry.address, AddressZero, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroAddress");
            await expect(ServiceStakingToken.deploy(maxNumServices, rewardsPerSecond, minStakingDeposit, livenessRatio, serviceRegistry.address, serviceRegistryTokenUtility.address, AddressZero)).to.be.revertedWithCustomError(ServiceStakingToken, "ZeroAddress");
        });
    });

    context("Staking to ServiceStaking and ServiceStakingToken", function () {
        it("Should fail if there are no available rewards", async function () {
            await expect(
                serviceStaking.stake(serviceId)
            ).to.be.revertedWithCustomError(serviceStaking, "NoRewardsAvailable");
        });

        it("Should fail if the maximum number of staking services is reached", async function () {
            // Deploy a contract with max number of services equal to one
            const ServiceStaking = await ethers.getContractFactory("ServiceStaking");
            const sStaking = await ServiceStaking.deploy(1, rewardsPerSecond, minStakingDeposit, livenessRatio,
                serviceRegistry.address);
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

        it("Should fail when the service has insufficient security deposit", async function () {
            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            const securityDeposit = 1;

            // Create a new service (serviceId == 3), activate, register agents and deploy
            await serviceRegistry.create(deployer.address, defaultHash, agentIds, [[1, securityDeposit]], threshold);
            await serviceRegistry.activateRegistration(deployer.address, serviceId + 2, {value: securityDeposit});
            await serviceRegistry.registerAgents(operator.address, serviceId + 2, [signers[4].address], agentIds, {value: securityDeposit});
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
            await serviceRegistry.registerAgents(operator.address, sId, [signers[4].address], agentIds, {value: 1});
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
            await serviceRegistry.registerAgents(operator.address, sId, [signers[4].address], agentIds, {value: 1});
            await serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, sId, agentIds);
            // Deploy the service
            await serviceRegistry.deploy(deployer.address, sId, gnosisSafeMultisig.address, payload);

            // Approve services
            await serviceRegistry.approve(serviceStakingToken.address, sId);

            await expect(
                serviceStakingToken.stake(sId)
            ).to.be.revertedWithCustomError(serviceStakingToken, "LowerThan");
        });

        it("Stake a service at ServiceStaking", async function () {
            // Deposit to the contract
            await deployer.sendTransaction({to: serviceStaking.address, value: ethers.utils.parseEther("1")});

            // Approve services
            await serviceRegistry.approve(serviceStaking.address, serviceId);

            // Stake the first service
            await serviceStaking.stake(serviceId);
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
            await serviceRegistry.registerAgents(operator.address, sId, [signers[4].address], agentIds, {value: 1});
            await serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, sId, agentIds);
            // Deploy the service
            await serviceRegistry.deploy(deployer.address, sId, gnosisSafeMultisig.address, payload);

            // Approve services
            await serviceRegistry.approve(serviceStakingToken.address, sId);

            await serviceStakingToken.stake(sId);
        });
    });

    context("Staking and unstaking", function () {
        it("", async function () {
        });
    });
});
