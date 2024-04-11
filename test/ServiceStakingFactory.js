/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe.only("ServiceStaking", function () {
    let serviceStaking;
    let serviceStakingFactory;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        const ServiceStaking = await ethers.getContractFactory("MockServiceStaking");
        serviceStaking = await ServiceStaking.deploy();
        await serviceStaking.deployed();

        const ServiceStakingFactory = await ethers.getContractFactory("ServiceStakingFactory");
        serviceStakingFactory = await ServiceStakingFactory.deploy();
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

        it("Try to deploy with the same implementation", async function () {
            const initPayload = serviceStaking.interface.encodeFunctionData("getNextServiceId", []);
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
        });
    });
});
