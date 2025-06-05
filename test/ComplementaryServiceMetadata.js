/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ComplementaryServiceMetadata", function () {
    let complementaryServiceMetadata;
    let serviceRegistry;
    let signers;
    const AddressZero = ethers.constants.AddressZero;
    const serviceId = 1;
    const serviceHash = "0x" + "5".repeat(64);
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
        const newHash = "0x1234567890123456789012345678901234567890123456789012345678901234";

        it("Should allow service owner to change hash when service is not deployed", async function () {
            const serviceId2 = serviceId + 100;
            // Set the deployer to the service owner by default
            await serviceRegistry.setServiceOwner(serviceId2, deployer.address);

            // service Ids 101+ have mocked state as 0
            await expect(complementaryServiceMetadata.changeHash(serviceId2, newHash))
                .to.emit(complementaryServiceMetadata, "ComplementaryMetadataUpdated")
                .withArgs(serviceId2, newHash);
            
            expect(await complementaryServiceMetadata.mapServiceHashes(serviceId2)).to.equal(newHash);
        });

        it("Should allow multisig to change hash when service is deployed", async function () {
            // deployer is serviceId multisig
            // ServiceId is in the deployed state
            await expect(complementaryServiceMetadata.connect(deployer).changeHash(serviceId, newHash))
                .to.emit(complementaryServiceMetadata, "ComplementaryMetadataUpdated")
                .withArgs(serviceId, newHash);
            
            expect(await complementaryServiceMetadata.mapServiceHashes(serviceId)).to.equal(newHash);
        });

        it("Should not allow non-owner to change hash when service is not deployed", async function () {
            const nonOwner = signers[1];

            const serviceId2 = serviceId + 100;
            // Set the deployer to the service owner by default
            await serviceRegistry.setServiceOwner(serviceId2, deployer.address);

            // service Ids 101+ have mocked state as 0

            await expect(complementaryServiceMetadata.connect(nonOwner).changeHash(serviceId2, newHash))
                .to.be.revertedWithCustomError(complementaryServiceMetadata, "UnauthorizedAccount")
                .withArgs(nonOwner.address);
        });

        it("Should not allow non-multisig to change hash when service is deployed", async function () {
            const nonMultisig = signers[1];
            
            await expect(complementaryServiceMetadata.connect(nonMultisig).changeHash(serviceId, newHash))
                .to.be.revertedWithCustomError(complementaryServiceMetadata, "UnauthorizedAccount")
                .withArgs(nonMultisig.address);
        });

        it("Should emit ComplementaryMetadataUpdated event with correct parameters", async function () {
            await expect(complementaryServiceMetadata.changeHash(serviceId, newHash))
                .to.emit(complementaryServiceMetadata, "ComplementaryMetadataUpdated")
                .withArgs(serviceId, newHash);
        });

        it("Check complementary token URI", async function () {
            await complementaryServiceMetadata.changeHash(serviceId, serviceHash)
            const baseURI = await serviceRegistry.baseURI();
            const cidPrefix = "f01701220";
            expect(await complementaryServiceMetadata.complementaryTokenURI(serviceId))
                .to.equal(baseURI + cidPrefix + serviceHash.slice(2));
        });
    });

});
