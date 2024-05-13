/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Staking", function () {
    let staking;
    let stakingFactory;
    let stakingVerifier;
    let token;
    let signers;
    let deployer;
    const AddressZero = ethers.constants.AddressZero;
    const rewardsPerSecondLimit = "1" + "0".repeat(15);

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
        stakingVerifier = await StakingVerifier.deploy(token.address, rewardsPerSecondLimit);
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
                StakingVerifier.deploy(AddressZero, 0)
            ).to.be.revertedWithCustomError(StakingVerifier, "ZeroAddress");

            await expect(
                StakingVerifier.deploy(token.address, 0)
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
            const initPayload = staking.interface.encodeFunctionData("initialize", [token.address]);
            const instances = new Array(2);

            // Create a first instance
            instances[0] = await stakingFactory.callStatic.createStakingInstance(staking.address,
                initPayload);
            await stakingFactory.createStakingInstance(staking.address, initPayload);

            // Create a second instance
            instances[1] = await stakingFactory.callStatic.createStakingInstance(staking.address,
                initPayload);
            await stakingFactory.createStakingInstance(staking.address, initPayload);

            // Make sure instances have different addresses
            expect(instances[0]).to.not.equal(instances[1]);

            // Check the service staking proxy implementation
            const proxy = await ethers.getContractAt("StakingProxy", instances[0]);
            const implementation = await proxy.getImplementation();
            expect(implementation).to.equal(staking.address);

            // Verify instance by just comparing the implementation
            await stakingFactory.verifyInstance(instances[0]);

            // Try the implementation that does not exist
            const res = await stakingFactory.verifyInstance(deployer.address);
            expect(res).to.be.false;
        });
    });

    context("Verifier", function () {
        it("Implementation with the verifier set", async function () {
            // Set the verifier
            await stakingFactory.changeVerifier(stakingVerifier.address);

            // Create the service staking contract instance
            const initPayload = staking.interface.encodeFunctionData("initialize", [token.address]);
            const instance = await stakingFactory.callStatic.createStakingInstance(
                staking.address, initPayload);
            const instanceAddress = await stakingFactory.getProxyAddress(staking.address);
            expect(instanceAddress).to.equal(instance);
            await stakingFactory.createStakingInstance(staking.address, initPayload);

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
                stakingVerifier.connect(signers[1]).changeStakingLimits(0)
            ).to.be.revertedWithCustomError(stakingVerifier, "OwnerOnly");

            // Try to change the staking param limits with the zero value
            await expect(
                stakingVerifier.changeStakingLimits(0)
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
            let initPayload = staking.interface.encodeFunctionData("initialize", [token.address]);
            await expect(
                stakingFactory.createStakingInstance(staking.address, initPayload)
            ).to.be.revertedWithCustomError(stakingFactory, "UnverifiedImplementation");

            // Whitelist implementation
            await stakingVerifier.setImplementationsStatuses([staking.address], [true], true);

            // Try to create the service staking contract instance with the wrong service parameter (token)
            const Token = await ethers.getContractFactory("ERC20Token");
            const badToken = await Token.deploy();
            await badToken.deployed();
            initPayload = staking.interface.encodeFunctionData("initialize", [badToken.address]);
            await expect(
                stakingFactory.createStakingInstance(staking.address, initPayload)
            ).to.be.revertedWithCustomError(stakingFactory, "UnverifiedProxy");

            initPayload = staking.interface.encodeFunctionData("initialize", [token.address]);
            await stakingFactory.createStakingInstance(staking.address, initPayload);

            // Change rewards per second limit parameter
            await stakingVerifier.changeStakingLimits(1);

            // Now the initialization will fail since the limit is too low
            await expect(
                stakingFactory.createStakingInstance(staking.address, initPayload)
            ).to.be.revertedWithCustomError(stakingFactory, "UnverifiedProxy");
        });
    });
});
