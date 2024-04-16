/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ServiceStaking", function () {
    let serviceStaking;
    let serviceStakingFactory;
    let serviceStakingVerifier;
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

        const ServiceStakingFactory = await ethers.getContractFactory("ServiceStakingFactory");
        serviceStakingFactory = await ServiceStakingFactory.deploy();
        await serviceStakingFactory.deployed();

        const ServiceStakingVerifier = await ethers.getContractFactory("ServiceStakingVerifier");
        serviceStakingVerifier = await ServiceStakingVerifier.deploy(rewardsPerSecondLimit);
        await serviceStakingVerifier.deployed();
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
        
        it("Changing owner", async function () {
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
    });


    context("Deployment", function () {
        it("Try to deploy with the same implementation", async function () {
            const initPayload = serviceStaking.interface.encodeFunctionData("initialize", []);
            const instances = new Array(2);

            // Create a first instance
            instances[0] = await serviceStakingFactory.callStatic.createServiceStakingInstance(serviceStaking.address, initPayload);
            await serviceStakingFactory.createServiceStakingInstance(serviceStaking.address, initPayload);

            // Create a second instance
            instances[1] = await serviceStakingFactory.callStatic.createServiceStakingInstance(serviceStaking.address, initPayload);
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
            await expect(
                serviceStakingFactory.verifyInstance(deployer.address)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "InstanceHasNoImplementation");
        });
    });

    context("Verifier", function () {
        it("Implementation with the verifier set", async function () {
            // Set the verifier
            await serviceStakingFactory.changeVerifier(serviceStakingVerifier.address);

            // Create the service staking contract instance
            const initPayload = serviceStaking.interface.encodeFunctionData("initialize", []);
            const instance = await serviceStakingFactory.callStatic.createServiceStakingInstance(
                serviceStaking.address, initPayload);
            await serviceStakingFactory.createServiceStakingInstance(serviceStaking.address, initPayload);

            // Check the parameter by the verifier
            const proxy = await ethers.getContractAt("MockServiceStaking", instance);
            let success = await serviceStakingFactory.verifyInstance(instance);
            expect(success).to.be.true;

            // Try to check the instance without implementation
            await expect(
                serviceStakingFactory.verifyInstance(AddressZero)
            ).to.be.revertedWithCustomError(serviceStakingFactory, "InstanceHasNoImplementation");

            // Check the instance when the parameter is changed
            await proxy.changeRewardsPerSecond();
            success = await serviceStakingFactory.verifyInstance(instance);
            expect(success).to.be.false;

            // Set verifier back to the zero address
            await serviceStakingFactory.changeVerifier(AddressZero);

            // Verify again without a verifier and it must pass
            success = await serviceStakingFactory.verifyInstance(instance);
            expect(success).to.be.true;
        });
    });
});
