/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ComplementaryServiceMetadata", function () {
    let complementaryServiceMetadata;
    let serviceRegistry;
    let signers;
    const AddressZero = ethers.constants.AddressZero;
    const serviceId = 1;
    let deployer;

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];
        
        const ServiceRegistry = await ethers.getContractFactory("MockServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy();
        await serviceRegistry.deployed();
        
        const ComplementaryServiceMetadata = await ethers.getContractFactory("ComplementaryServiceMetadata");
        complementaryServiceMetadata = await ComplementaryServiceMetadata.deploy(serviceRegistry.address);
        await complementaryServiceMetadata.deployed();

        // Set the deployer to the service owner by default
        await serviceRegistry.setServiceOwner(serviceId, deployer.address);
    });

    context("Constructor", function () {
        it("Should set the serviceRegistry address", async function () {
            expect(await complementaryServiceMetadata.serviceRegistry()).to.equal(serviceRegistry.address);
        });
    
        it("Should not allow the zero address as serviceRegistry address", async function () {
            const ComplementaryServiceMetadata = await ethers.getContractFactory("ComplementaryServiceMetadata");
            await expect(ComplementaryServiceMetadata.deploy(AddressZero)).to.be.revertedWithCustomError(complementaryServiceMetadata, "ZeroAddress");
        });
    });

    context("Change hash", function () {

    });

});
