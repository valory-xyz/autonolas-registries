/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("StakingFactory", function () {
    let staking;
    let stakingFactory;
    let stakingVerifier;
    let token;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const minStakingDepositLimit = ethers.utils.parseEther("10");
    const timeForEmissionsLimit = 100;
    const numServicesLimit = 100;
    const apyLimit = ethers.utils.parseEther("200");

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];

        const Staking = await ethers.getContractFactory("MockStaking");
        staking = await Staking.deploy();
        await staking.deployed();

        const Token = await ethers.getContractFactory("ERC20Token");
        token = await Token.deploy();
        await token.deployed();

        const StakingVerifier = await ethers.getContractFactory("StakingVerifier");
        stakingVerifier = await StakingVerifier.deploy(token.address, signers[1].address, signers[2].address,
            minStakingDepositLimit, timeForEmissionsLimit, numServicesLimit, apyLimit);
        await stakingVerifier.deployed();

        const StakingFactory = await ethers.getContractFactory("StakingFactory");
        stakingFactory = await StakingFactory.deploy(AddressZero);
        await stakingFactory.deployed();
    });

    context("Initialization", function () {
        it("Should not allow the zero values and addresses when deploying contracts", async function () {
            await expect(
                stakingFactory.createStakingInstance(AddressZero, "0x")
            ).to.be.revertedWithCustomError(stakingFactory, "ZeroAddress");

            await expect(
                stakingFactory.createStakingInstance(signers[1].address, "0x")
            ).to.be.revertedWithCustomError(stakingFactory, "ContractOnly");

            await expect(
                stakingFactory.createStakingInstance(staking.address, "0x")
            ).to.be.revertedWithCustomError(stakingFactory, "IncorrectDataLength");
        });

        it("Should fail when initialization parameters are not correctly specified", async function () {
            await expect(
                stakingFactory.createStakingInstance(staking.address, "0x1234567890")
            ).to.be.revertedWithCustomError(stakingFactory, "InitializationFailed");
        });

        it("Should fail when deploying verifier with incorrect parameters", async function () {
            const StakingVerifier = await ethers.getContractFactory("StakingVerifier");

            await expect(
                StakingVerifier.deploy(AddressZero, AddressZero, AddressZero, 0, 0, 0, 0)
            ).to.be.revertedWithCustomError(StakingVerifier, "ZeroAddress");

            await expect(
                StakingVerifier.deploy(token.address, AddressZero, AddressZero, 0, 0, 0, 0)
            ).to.be.revertedWithCustomError(StakingVerifier, "ZeroAddress");

            await expect(
                StakingVerifier.deploy(token.address, signers[1].address, AddressZero, 0, 0, 0, 0)
            ).to.be.revertedWithCustomError(StakingVerifier, "ZeroValue");

            await expect(
                StakingVerifier.deploy(token.address, signers[1].address, AddressZero, minStakingDepositLimit, 0, 0, 0)
            ).to.be.revertedWithCustomError(StakingVerifier, "ZeroValue");

            await expect(
                StakingVerifier.deploy(token.address, signers[1].address, AddressZero, minStakingDepositLimit,
                    timeForEmissionsLimit, 0, 0)
            ).to.be.revertedWithCustomError(StakingVerifier, "ZeroValue");

            await expect(
                StakingVerifier.deploy(token.address, signers[1].address, AddressZero, minStakingDepositLimit,
                    timeForEmissionsLimit, numServicesLimit, 0)
            ).to.be.revertedWithCustomError(StakingVerifier, "ZeroValue");
        });
        
        it("Changing owner in staking factory", async function () {
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                stakingFactory.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(stakingFactory, "OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                stakingFactory.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(stakingFactory, "ZeroAddress");

            // Changing the owner
            await stakingFactory.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                stakingFactory.connect(deployer).changeOwner(deployer.address)
            ).to.be.revertedWithCustomError(stakingFactory, "OwnerOnly");
        });

        it("Changing owner in verifier", async function () {
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                stakingVerifier.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(stakingFactory, "OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                stakingVerifier.connect(deployer).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(stakingFactory, "ZeroAddress");

            // Changing the owner
            await stakingVerifier.connect(deployer).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                stakingVerifier.connect(deployer).changeOwner(deployer.address)
            ).to.be.revertedWithCustomError(stakingFactory, "OwnerOnly");
        });
    });

    context("Deployment", function () {
        it("Try to deploy with the same implementation", async function () {
            const initPayload = staking.interface.encodeFunctionData("initialize", [token.address, signers[1].address,
                signers[2].address]);
            const instances = new Array(2);

            // Create a first instance
            let tx = await stakingFactory.createStakingInstance(staking.address, initPayload);
            let res = await tx.wait();
            // Get staking contract instance address from the event
            instances[0] = "0x" + res.logs[0].topics[2].slice(26);

            // Create a second instance
            tx = await stakingFactory.createStakingInstance(staking.address, initPayload);
            res = await tx.wait();
            // Get staking contract instance address from the event
            instances[1] = "0x" + res.logs[0].topics[2].slice(26);

            // Make sure instances have different addresses
            expect(instances[0]).to.not.equal(instances[1]);

            // Check the service staking proxy implementation
            const proxy = await ethers.getContractAt("StakingProxy", instances[0]);
            const implementation = await proxy.getImplementation();
            expect(implementation).to.equal(staking.address);

            // Verify instance by just comparing the implementation
            await stakingFactory.verifyInstance(instances[0]);

            // Try the implementation that does not exist
            res = await stakingFactory.verifyInstance(deployer.address);
            expect(res).to.be.false;
        });
    });

    context("Verifier", function () {
        it("Implementation with the verifier set", async function () {
            // Set the verifier
            await stakingFactory.changeVerifier(stakingVerifier.address);

            // Create the service staking contract instance
            const initPayload = staking.interface.encodeFunctionData("initialize", [token.address, signers[1].address,
                signers[2].address]);
            let tx = await stakingFactory.createStakingInstance(staking.address, initPayload);
            let res = await tx.wait();
            // Get staking contract instance address from the event
            const instance = "0x" + res.logs[0].topics[2].slice(26);
            const instanceAddress = await stakingFactory.getProxyAddress(staking.address);
            // Check that different blocks give different instance addresses
            expect(instanceAddress).to.not.equal(instance);

            // Check the parameter by the verifier
            const proxy = await ethers.getContractAt("MockStaking", instance);
            let success = await stakingFactory.verifyInstance(instance);
            expect(success).to.be.true;

            // Try to check the instance without implementation
            success = await stakingFactory.callStatic.verifyInstance(AddressZero);
            expect(success).to.be.false;

            // Check the instance when the parameter is changed
            await proxy.changeRewardsPerSecond();
            success = await stakingFactory.verifyInstance(instance);
            expect(success).to.be.false;

            // Verify with an instance being a non contract
            success = await stakingVerifier.verifyInstance(AddressZero, AddressZero);
            expect(success).to.be.false;

            // Set the implementations check
            await stakingVerifier.setImplementationsCheck(true);

            // Verify with a non whitelisted instance by the verifier contract itself
            success = await stakingVerifier.verifyInstance(instance, AddressZero);
            expect(success).to.be.false;

            // Set verifier back to the zero address (no verification by the verifier)
            await stakingFactory.changeVerifier(AddressZero);

            // Verify again without a verifier and it must pass
            success = await stakingFactory.verifyInstance(instance);
            expect(success).to.be.true;

            // Set the instance inactive
            await stakingFactory.setInstanceStatus(instance, false);
            // The verification is going to fail
            success = await stakingFactory.verifyInstance(instance);
            expect(success).to.be.false;
        });

        it("Should fail when setting verification implementations with incorrect parameters", async function () {
            // Try to set verifier not by the owner
            await expect(
                stakingFactory.connect(signers[1]).changeVerifier(stakingVerifier.address)
            ).to.be.revertedWithCustomError(stakingFactory, "OwnerOnly");

            // Try to set implementations check not by the owner
            await expect(
                stakingVerifier.connect(signers[1]).setImplementationsCheck(true)
            ).to.be.revertedWithCustomError(stakingFactory, "OwnerOnly");

            // Try to set implementation statuses not by the owner
            await expect(
                stakingVerifier.connect(signers[1]).setImplementationsStatuses([], [], true)
            ).to.be.revertedWithCustomError(stakingFactory, "OwnerOnly");

            // Try to set implementation statuses with the wrong number of parameters
            await expect(
                stakingVerifier.setImplementationsStatuses([], [], true)
            ).to.be.revertedWithCustomError(stakingVerifier, "WrongArrayLength");

            await expect(
                stakingVerifier.setImplementationsStatuses([AddressZero], [], true)
            ).to.be.revertedWithCustomError(stakingVerifier, "WrongArrayLength");

            await expect(
                stakingVerifier.setImplementationsStatuses([], [true], true)
            ).to.be.revertedWithCustomError(stakingVerifier, "WrongArrayLength");

            await expect(
                stakingVerifier.setImplementationsStatuses([AddressZero], [true], true)
            ).to.be.revertedWithCustomError(stakingVerifier, "ZeroAddress");

            // Try to change the staking param limits not by the owner
            await expect(
                stakingVerifier.connect(signers[1]).changeStakingLimits(0, 0, 0, 0)
            ).to.be.revertedWithCustomError(stakingVerifier, "OwnerOnly");

            // Try to change the staking param limits with the zero value
            await expect(
                stakingVerifier.changeStakingLimits(0, 0, 0, 0)
            ).to.be.revertedWithCustomError(stakingVerifier, "ZeroValue");
            await expect(
                stakingVerifier.changeStakingLimits(minStakingDepositLimit, 0, 0, 0)
            ).to.be.revertedWithCustomError(stakingVerifier, "ZeroValue");
            await expect(
                stakingVerifier.changeStakingLimits(minStakingDepositLimit, timeForEmissionsLimit, 0, 0)
            ).to.be.revertedWithCustomError(stakingVerifier, "ZeroValue");
            await expect(
                stakingVerifier.changeStakingLimits(minStakingDepositLimit, timeForEmissionsLimit, numServicesLimit, 0)
            ).to.be.revertedWithCustomError(stakingVerifier, "ZeroValue");

            // Try to set instance activity not by instance deployer
            await expect(
                stakingFactory.setInstanceStatus(AddressZero, true)
            ).to.be.revertedWithCustomError(stakingFactory, "OwnerOnly");
        });

        it("Setting verification implementations", async function () {
            // Set the verifier
            await stakingFactory.changeVerifier(stakingVerifier.address);

            // Set the implementations check
            await stakingVerifier.setImplementationsCheck(true);

            // Try to create the service staking contract instance with the non-whitelisted implementation
            let initPayload = staking.interface.encodeFunctionData("initialize", [token.address, signers[1].address,
                signers[2].address]);
            await expect(
                stakingFactory.createStakingInstance(staking.address, initPayload)
            ).to.be.revertedWithCustomError(stakingFactory, "UnverifiedImplementation");

            // Whitelist implementation
            await stakingVerifier.setImplementationsStatuses([staking.address], [true], true);

            // Try to create the service staking contract instance with the wrong service parameter (token)
            const Token = await ethers.getContractFactory("ERC20Token");
            const badToken = await Token.deploy();
            await badToken.deployed();
            initPayload = staking.interface.encodeFunctionData("initialize", [badToken.address, signers[1].address,
                signers[2].address]);
            await expect(
                stakingFactory.createStakingInstance(staking.address, initPayload)
            ).to.be.revertedWithCustomError(stakingFactory, "UnverifiedProxy");

            initPayload = staking.interface.encodeFunctionData("initialize", [token.address, signers[1].address,
                signers[2].address]);
            await stakingFactory.createStakingInstance(staking.address, initPayload);

            // Change rewards per second limit parameter
            await stakingVerifier.changeStakingLimits(1, timeForEmissionsLimit, numServicesLimit, apyLimit);

            // Now the initialization will fail since the rewards per second limit is too low
            await expect(
                stakingFactory.createStakingInstance(staking.address, initPayload)
            ).to.be.revertedWithCustomError(stakingFactory, "UnverifiedProxy");

            // Change emissions time limit
            await stakingVerifier.changeStakingLimits(minStakingDepositLimit, 1, numServicesLimit, apyLimit);

            // Now the initialization will fail since the emissions time limit is too low
            await expect(
                stakingFactory.createStakingInstance(staking.address, initPayload)
            ).to.be.revertedWithCustomError(stakingFactory, "UnverifiedProxy");

            // Change number of services limit
            await stakingVerifier.changeStakingLimits(minStakingDepositLimit, timeForEmissionsLimit, 1, apyLimit);

            // Now the initialization will fail since the services number limit is too low
            await expect(
                stakingFactory.createStakingInstance(staking.address, initPayload)
            ).to.be.revertedWithCustomError(stakingFactory, "UnverifiedProxy");

            // Change APY limit
            await stakingVerifier.changeStakingLimits(minStakingDepositLimit, timeForEmissionsLimit, numServicesLimit, 1);

            // Now the initialization will fail since the staking contract APY is too high
            await expect(
                stakingFactory.createStakingInstance(staking.address, initPayload)
            ).to.be.revertedWithCustomError(stakingFactory, "UnverifiedProxy");

            // Change verifier staking limits to defaults
            await stakingVerifier.changeStakingLimits(minStakingDepositLimit, timeForEmissionsLimit, numServicesLimit,
                apyLimit);

            // Calculate proxy address
            let tx = await stakingFactory.createStakingInstance(staking.address, initPayload);
            let res = await tx.wait();
            // Get staking contract instance address from the event
            const proxyAddress = "0x" + res.logs[0].topics[2].slice(26);

            const proxyInstance = await ethers.getContractAt("MockStaking", proxyAddress);

            // Get the emissions amount
            let amount = await stakingFactory.verifyInstanceAndGetEmissionsAmount(proxyAddress);
            expect(amount).to.equal(await proxyInstance.emissionsAmount());

            // Remove the verifier
            await stakingFactory.changeVerifier(AddressZero);

            // Emissions amount is now set without limits check
            amount = await stakingFactory.verifyInstanceAndGetEmissionsAmount(proxyAddress);
            expect(amount).to.gt(0);

            // Try to remove instance not by the DAO
            await expect(
                stakingFactory.connect(signers[1]).removeInstance(proxyAddress)
            ).to.be.revertedWithCustomError(stakingFactory, "OwnerOnly");

            // Remove the instance from the factory
            await stakingFactory.removeInstance(proxyAddress);

            // The verification now fails
            const success = await stakingFactory.verifyInstance(proxyAddress);
            expect(success).to.be.false;
        });

        it("Verify registries", async function () {
            const StakingVerifier = await ethers.getContractFactory("StakingVerifier");

            // Deploy a verifier with the different service registry address
            let wrongVerifier = await StakingVerifier.deploy(token.address, signers[2].address, signers[3].address,
                minStakingDepositLimit, timeForEmissionsLimit, numServicesLimit, apyLimit);
            await wrongVerifier.deployed();

            // Set the new verifier
            await stakingFactory.changeVerifier(wrongVerifier.address);

            // Get the initialization payload
            let initPayload = staking.interface.encodeFunctionData("initialize", [token.address, signers[1].address,
                signers[2].address]);

            // Try to create service staking contract instance with an incorrect service registry
            await expect (
                stakingFactory.createStakingInstance(staking.address, initPayload)
            ).to.be.revertedWithCustomError(stakingFactory, "UnverifiedProxy");

            // Deploy a new verifier with a wrong service registry token utility
            wrongVerifier = await StakingVerifier.deploy(token.address, signers[1].address, signers[3].address,
                minStakingDepositLimit, timeForEmissionsLimit, numServicesLimit, apyLimit);
            await wrongVerifier.deployed();

            // Set the new verifier
            await stakingFactory.changeVerifier(wrongVerifier.address);

            // Try to create service staking contract instance with an incorrect service registry token utility
            await expect (
                stakingFactory.createStakingInstance(staking.address, initPayload)
            ).to.be.revertedWithCustomError(stakingFactory, "UnverifiedProxy");

            // However, staking native token must pass because it does not depend on service registry token utility
            initPayload = staking.interface.encodeFunctionData("initialize", [token.address, signers[1].address,
                AddressZero]);

            await stakingFactory.createStakingInstance(staking.address, initPayload);
        });
    });
});
