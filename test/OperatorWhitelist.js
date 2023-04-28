/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("OperatorWhitelist", function () {
    let operatorWhitelist;
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
        
        const OperatorWhitelist = await ethers.getContractFactory("OperatorWhitelist");
        operatorWhitelist = await OperatorWhitelist.deploy(serviceRegistry.address);
        await operatorWhitelist.deployed();

        // Set the deployer to the service owner by default
        await serviceRegistry.setServiceOwner(serviceId, deployer.address);
    });

    context("Constructor", function () {
        it("Should set the serviceRegistry address", async function () {
            expect(await operatorWhitelist.serviceRegistry()).to.equal(serviceRegistry.address);
        });
    
        it("Should not allow the zero address as serviceRegistry address", async function () {
            const OperatorWhitelist = await ethers.getContractFactory("OperatorWhitelist");
            await expect(OperatorWhitelist.deploy(AddressZero)).to.be.revertedWithCustomError(operatorWhitelist, "ZeroAddress");
        });
    });

    context("setOperatorsCheck", function () {
        it("Should set the operator check status", async function () {
            await operatorWhitelist.setOperatorsCheck(serviceId, true);
            expect(await operatorWhitelist.mapServiceIdOperatorsCheck(serviceId)).to.be.true;
            await operatorWhitelist.setOperatorsCheck(serviceId, false);
            expect(await operatorWhitelist.mapServiceIdOperatorsCheck(serviceId)).to.be.false;
        });
    
        it("Should revert if the service owner is not the message sender", async function () {
            await expect(
                operatorWhitelist.connect(signers[1]).setOperatorsCheck(serviceId, true)
            ).to.be.revertedWithCustomError(operatorWhitelist, "OwnerOnly");
        });
    });

    context("setOperatorsStatuses", function () {
        it("Should set the operators whitelisting status", async function () {
            await operatorWhitelist.setOperatorsStatuses(serviceId, [signers[1].address, signers[2].address], [true, false], true);
            expect(await operatorWhitelist.mapServiceIdOperators(serviceId, signers[1].address)).to.be.true;
            expect(await operatorWhitelist.mapServiceIdOperators(serviceId, signers[2].address)).to.be.false;

            // Check for the service owner itself to be whitelisted
            expect(await operatorWhitelist.isOperatorWhitelisted(serviceId, deployer.address)).to.be.true;
            // Check for whitelisted operators
            expect(await operatorWhitelist.isOperatorWhitelisted(serviceId, signers[1].address)).to.be.true;
            expect(await operatorWhitelist.isOperatorWhitelisted(serviceId, signers[2].address)).to.be.false;

            // Unset the operator whitelist verification
            await operatorWhitelist.setOperatorsCheck(serviceId, false);
            // No all of the addresses are considered whitelisted
            expect(await operatorWhitelist.isOperatorWhitelisted(serviceId, signers[1].address)).to.be.true;
            expect(await operatorWhitelist.isOperatorWhitelisted(serviceId, signers[2].address)).to.be.true;
        });
        
        it("Should revert if the arrays have different lengths", async function () {
            await expect(
                operatorWhitelist.setOperatorsStatuses(serviceId, [signers[1].address, signers[2].address], [true], true)
            ).to.be.revertedWithCustomError(operatorWhitelist, "WrongArrayLength");
        });
        
        it("Should revert if the arrays are empty", async function () {
            await expect(
                operatorWhitelist.setOperatorsStatuses(serviceId, [], [], false)
            ).to.be.revertedWithCustomError(operatorWhitelist, "WrongArrayLength");
        });
        
        it("Should revert if the service owner is not the message sender", async function () {
            await expect(
                operatorWhitelist.connect(signers[1]).setOperatorsStatuses(serviceId, [signers[2].address], [true], false)
            ).to.be.revertedWithCustomError(operatorWhitelist, "OwnerOnly");
        });
        
        it("Should revert if an operator address is the zero address", async function () {
            await expect(
                operatorWhitelist.setOperatorsStatuses(serviceId, [AddressZero], [true], false)
            ).to.be.revertedWithCustomError(operatorWhitelist, "ZeroAddress");
        });
    });
});
