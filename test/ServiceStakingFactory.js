/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ServiceStaking", function () {
    let serviceStaking;
    let serviceStakingFactory;
    let serviceStakingVerifier;
    let token;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const rewardsPerSecondLimit = "1" + "0".repeat(15);

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        const ServiceStaking = await ethers.getContractFactory("MockServiceStaking");
        serviceStaking = await ServiceStaking.deploy();
        await serviceStaking.deployed();

        const Token = await ethers.getContractFactory("ERC20Token");
        token = await Token.deploy();
        await token.deployed();

        const ServiceStakingVerifier = await ethers.getContractFactory("ServiceStakingVerifier");
        serviceStakingVerifier = await ServiceStakingVerifier.deploy(token.address, rewardsPerSecondLimit);
        await serviceStakingVerifier.deployed();

        const ServiceStakingFactory = await ethers.getContractFactory("ServiceStakingFactory");
        serviceStakingFactory = await ServiceStakingFactory.deploy(AddressZero);
        await serviceStakingFactory.deployed();
    });

    context("Initialization", function () {
        it("Should not allow the zero values and addresses when deploying contracts", async function () {
            await expect(
                serviceStakingFactory.createServiceStakingInstance(AddressZero, "0x")
            ).to.be.revertedWithCustomError(serviceStakingFactory, "ZeroAddress");

            await expect(
                serviceStakingFactory.createServiceStakingInstance(signers[1].address, "0x")
            ).to.be.revertedWithCustomError(serviceStakingFactory, "ContractOnly");

            await expect(
                serviceStakingFactory.createServiceStakingInstance(serviceStaking.address, "0x")
            ).to.be.revertedWithCustomError(serviceStakingFactory, "IncorrectDataLength");
        });

        it("Should fail when initialization parameters are not correctly specified", async function () {
            await expect(
                serviceStakingFactory.createServiceStakingInstance(serviceStaking.address, "0x1234567890")
            ).to.be.revertedWithCustomError(serviceStakingFactory, "InitializationFailed");
        });

        it("Should fail when deploying verifier with incorrect parameters", async function () {
            const ServiceStakingVerifier = await ethers.getContractFactory("ServiceStakingVerifier");

            await expect(
                ServiceStakingVerifier.deploy(AddressZero, 0)
            ).to.be.revertedWithCustomError(ServiceStakingVerifier, "ZeroAddress");

            await expect(
                ServiceStakingVerifier.deploy(token.address, 0)
            ).to.be.revertedWithCustomError(ServiceStakingVerifier, "ZeroValue");
        });
        
        it("Changing owner in staking factory", async function () {
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                serviceStakingFactory.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                serviceStakingFactory.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "ZeroAddress");

            // Changing the owner
            await serviceStakingFactory.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                serviceStakingFactory.connect(deployer).changeOwner(deployer.address)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "OwnerOnly");
        });

        it("Changing owner in verifier", async function () {
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                serviceStakingVerifier.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                serviceStakingVerifier.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "ZeroAddress");

            // Changing the owner
            await serviceStakingVerifier.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                serviceStakingVerifier.connect(deployer).changeOwner(deployer.address)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "OwnerOnly");
        });
    });

    context("Deployment", function () {
        it("Try to deploy with the same implementation", async function () {
            const initPayload = serviceStaking.interface.encodeFunctionData("initialize", [token.address]);
            const instances = new Array(2);

            // Create a first instance
            instances[0] = await serviceStakingFactory.callStatic.createServiceStakingInstance(serviceStaking.address,
                initPayload);
            await serviceStakingFactory.createServiceStakingInstance(serviceStaking.address, initPayload);

            // Create a second instance
            instances[1] = await serviceStakingFactory.callStatic.createServiceStakingInstance(serviceStaking.address,
                initPayload);
            await serviceStakingFactory.createServiceStakingInstance(serviceStaking.address, initPayload);

            // Make sure instances have different addresses
            expect(instances[0]).to.not.equal(instances[1]);

            // Check the service staking proxy implementation
            const proxy = await ethers.getContractAt("ServiceStakingProxy", instances[0]);
            const implementation = await proxy.getImplementation();
            expect(implementation).to.equal(serviceStaking.address);

            // Verify instance by just comparing the implementation
            await serviceStakingFactory.verifyInstance(instances[0]);

            // Try the implementation that does not exist
            const res = await serviceStakingFactory.verifyInstance(deployer.address);
            expect(res).to.be.false;
        });
    });

    context("Verifier", function () {
        it("Implementation with the verifier set", async function () {
            // Set the verifier
            await serviceStakingFactory.changeVerifier(serviceStakingVerifier.address);

            // Create the service staking contract instance
            const initPayload = serviceStaking.interface.encodeFunctionData("initialize", [token.address]);
            const instance = await serviceStakingFactory.callStatic.createServiceStakingInstance(
                serviceStaking.address, initPayload);
            const instanceAddress = await serviceStakingFactory.getProxyAddress(serviceStaking.address);
            expect(instanceAddress).to.equal(instance);
            await serviceStakingFactory.createServiceStakingInstance(serviceStaking.address, initPayload);

            // Check the parameter by the verifier
            const proxy = await ethers.getContractAt("MockServiceStaking", instance);
            let success = await serviceStakingFactory.verifyInstance(instance);
            expect(success).to.be.true;

            // Try to check the instance without implementation
            success = await serviceStakingFactory.callStatic.verifyInstance(AddressZero);
            expect(success).to.be.false;

            // Check the instance when the parameter is changed
            await proxy.changeRewardsPerSecond();
            success = await serviceStakingFactory.verifyInstance(instance);
            expect(success).to.be.false;

            // Set the implementations check
            await serviceStakingVerifier.setImplementationsCheck(true);

            // Verify with a non whitelisted instance by the verifier contract itself
            success = await serviceStakingVerifier.verifyInstance(instance, AddressZero);
            expect(success).to.be.false;

            // Set verifier back to the zero address (no verification by the verifier)
            await serviceStakingFactory.changeVerifier(AddressZero);

            // Verify again without a verifier and it must pass
            success = await serviceStakingFactory.verifyInstance(instance);
            expect(success).to.be.true;

            // Set the instance inactive
            await serviceStakingFactory.setInstanceActivity(instance, false);
            // The verification is going to fail
            success = await serviceStakingFactory.verifyInstance(instance);
            expect(success).to.be.false;
        });

        it("Should fail when setting verification implementations with incorrect parameters", async function () {
            // Try to set verifier not by the owner
            await expect(
                serviceStakingFactory.connect(signers[1]).changeVerifier(serviceStakingVerifier.address)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "OwnerOnly");

            // Try to set implementations check not by the owner
            await expect(
                serviceStakingVerifier.connect(signers[1]).setImplementationsCheck(true)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "OwnerOnly");

            // Try to set implementation statuses not by the owner
            await expect(
                serviceStakingVerifier.connect(signers[1]).setImplementationsStatuses([], [], true)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "OwnerOnly");

            // Try to set implementation statuses with the wrong number of parameters
            await expect(
                serviceStakingVerifier.setImplementationsStatuses([], [], true)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "WrongArrayLength");

            await expect(
                serviceStakingVerifier.setImplementationsStatuses([AddressZero], [], true)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "WrongArrayLength");

            await expect(
                serviceStakingVerifier.setImplementationsStatuses([], [true], true)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "WrongArrayLength");

            await expect(
                serviceStakingVerifier.setImplementationsStatuses([AddressZero], [true], true)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "ZeroAddress");

            // Try to change the staking param limits not by the owner
            await expect(
                serviceStakingVerifier.connect(signers[1]).changeStakingLimits(0)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "OwnerOnly");

            // Try to change the staking param limits with the zero value
            await expect(
                serviceStakingVerifier.changeStakingLimits(0)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "ZeroValue");

            // Try to set instance activity not by instance deployer
            await expect(
                serviceStakingFactory.setInstanceActivity(AddressZero, true)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "OwnerOnly");
        });

        it("Setting verification implementations", async function () {
            // Set the verifier
            await serviceStakingFactory.changeVerifier(serviceStakingVerifier.address);

            // Set the implementations check
            await serviceStakingVerifier.setImplementationsCheck(true);

            // Try to create the service staking contract instance with the non-whitelisted implementation
            let initPayload = serviceStaking.interface.encodeFunctionData("initialize", [token.address]);
            await expect(
                serviceStakingFactory.createServiceStakingInstance(serviceStaking.address, initPayload)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "UnverifiedImplementation");

            // Whitelist implementation
            await serviceStakingVerifier.setImplementationsStatuses([serviceStaking.address], [true], true);

            // Try to create the service staking contract instance with the wrong service parameter (token)
            const Token = await ethers.getContractFactory("ERC20Token");
            const badToken = await Token.deploy();
            await badToken.deployed();
            initPayload = serviceStaking.interface.encodeFunctionData("initialize", [badToken.address]);
            await expect(
                serviceStakingFactory.createServiceStakingInstance(serviceStaking.address, initPayload)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "UnverifiedProxy");

            initPayload = serviceStaking.interface.encodeFunctionData("initialize", [token.address]);
            await serviceStakingFactory.createServiceStakingInstance(serviceStaking.address, initPayload);

            // Change rewards per second limit parameter
            await serviceStakingVerifier.changeStakingLimits(1);

            // Now the initialization will fail since the limit is too low
            await expect(
                serviceStakingFactory.createServiceStakingInstance(serviceStaking.address, initPayload)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "UnverifiedProxy");
        });
    });
});
