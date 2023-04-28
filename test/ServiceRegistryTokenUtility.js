/*global describe, context, beforeEach, it*/
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("serviceRegistryTokenUtility", function () {
    let serviceRegistry;
    let serviceRegistryTokenUtility;
    let token;
    let reentrancyAttacker;
    let signers;
    let deployer;
    let operator;
    const AddressZero = ethers.constants.AddressZero;
    const uint256MaxValue = ethers.constants.MaxUint256;
    const serviceId = 1;
    const agentIds = [1, 2, 3];
    const bonds = [100, 300, 200];
    const initSupply = "5" + "0".repeat(26);

    beforeEach(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];
        operator = signers[1];
        
        const ServiceRegistry = await ethers.getContractFactory("MockServiceRegistry");
        serviceRegistry = await ServiceRegistry.deploy();
        await serviceRegistry.deployed();

        const ServiceRegistryTokenUtility = await ethers.getContractFactory("ServiceRegistryTokenUtility");
        serviceRegistryTokenUtility = await ServiceRegistryTokenUtility.deploy(serviceRegistry.address);
        await serviceRegistry.deployed();

        const Token = await ethers.getContractFactory("ERC20Token");
        token = await Token.deploy();
        await token.deployed();

        const ReentrancyAttacker = await ethers.getContractFactory("ReentrancyTokenAttacker");
        reentrancyAttacker = await ReentrancyAttacker.deploy(serviceRegistryTokenUtility.address);
        await reentrancyAttacker.deployed();

        // Set the deployer to the service owner by default
        await serviceRegistry.setServiceOwner(serviceId, deployer.address);
        // Set the deployer to be the service manager by default
        await serviceRegistryTokenUtility.changeManager(deployer.address);
        // Mint tokens to the service owner and the operator
        await token.mint(deployer.address, initSupply);
        await token.mint(operator.address, initSupply);
    });

    context("Initialization", function () {
        it("Should not allow the zero address as serviceRegistry address", async function () {
            const ServiceRegistryTokenUtility = await ethers.getContractFactory("ServiceRegistryTokenUtility");
            await expect(ServiceRegistryTokenUtility.deploy(AddressZero)).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "ZeroAddress");
        });

        it("Changing owner", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                serviceRegistryTokenUtility.connect(account).changeOwner(account.address)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                serviceRegistryTokenUtility.connect(owner).changeOwner(AddressZero)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "ZeroAddress");

            // Changing the owner
            await serviceRegistryTokenUtility.connect(owner).changeOwner(account.address);

            // Trying to change owner from the previous owner address
            await expect(
                serviceRegistryTokenUtility.connect(owner).changeOwner(owner.address)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "OwnerOnly");
        });

        it("Changing manager", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Trying to change manager from a non-owner account address
            await expect(
                serviceRegistryTokenUtility.connect(account).changeManager(account.address)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "OwnerOnly");

            // Trying to change manager for the zero address
            await expect(
                serviceRegistryTokenUtility.connect(owner).changeManager(AddressZero)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "ZeroAddress");

            // Changing the manager
            await serviceRegistryTokenUtility.connect(owner).changeManager(account.address);
        });

        it("Changing drainer", async function () {
            const owner = signers[0];
            const account = signers[1];

            // Trying to change owner from a non-owner account address
            await expect(
                serviceRegistryTokenUtility.connect(account).changeDrainer(account.address)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "OwnerOnly");

            // Trying to change owner for the zero address
            await expect(
                serviceRegistryTokenUtility.connect(owner).changeDrainer(AddressZero)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "ZeroAddress");

            // Changing the owner
            await serviceRegistryTokenUtility.connect(owner).changeDrainer(account.address);

            // Verifying the drainer address
            expect(await serviceRegistryTokenUtility.drainer()).to.equal(account.address);
        });
    });

    context("Create", function () {
        it("Should fail if not called by the manager", async function () {
            await expect(
                serviceRegistryTokenUtility.connect(operator).createWithToken(serviceId, token.address, agentIds, bonds)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "ManagerOnly");
        });

        it("Should fail if one of the bonds has an overflow value", async function () {
            await expect(
                serviceRegistryTokenUtility.createWithToken(serviceId, token.address, agentIds, [0, uint256MaxValue])
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "Overflow");
        });

        it("Should fail if the token does not pass the verification", async function () {
            // Try to use a non-contract address
            await expect(
                serviceRegistryTokenUtility.createWithToken(serviceId, deployer.address, agentIds, bonds)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "TokenRejected");
            // Try to use a non ERC20 token
            await expect(
                serviceRegistryTokenUtility.createWithToken(serviceId, serviceRegistry.address, agentIds, bonds)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "TokenRejected");
        });

        it("Create a service record for a specific token", async function () {
            await serviceRegistryTokenUtility.createWithToken(serviceId, token.address, agentIds, bonds);
            // Check for the service token address
            let tokenSecurityDeposit = await serviceRegistryTokenUtility.mapServiceIdTokenDeposit(serviceId);
            expect(tokenSecurityDeposit.token).to.equal(token.address);
            expect(tokenSecurityDeposit.securityDeposit).to.equal(Math.max(...bonds));

            // Overwrite a token with another set of agent Ids and bonds having zero values
            const newAgentIds = [1, 2, 3, 4];
            const newBonds = [100, 0, 300, 200];
            await serviceRegistryTokenUtility.createWithToken(serviceId, token.address, newAgentIds, newBonds);
            // Check for the service token address
            tokenSecurityDeposit = await serviceRegistryTokenUtility.mapServiceIdTokenDeposit(serviceId);
            expect(tokenSecurityDeposit.token).to.equal(token.address);
            expect(tokenSecurityDeposit.securityDeposit).to.equal(Math.max(...bonds));
            // Check the agent Id bonds
            for (let i = 0; i < newAgentIds.length; i++) {
                const agentBond = Number(await serviceRegistryTokenUtility.getAgentBond(serviceId, newAgentIds[i]));
                if (newBonds[i] > 0) {
                    expect(agentBond).to.equal(newBonds[i]);
                }
            }

            // Check if the service is token secured
            expect(await serviceRegistryTokenUtility.isTokenSecuredService(serviceId)).to.be.true;

            // Try to reset the token not by the manager
            await expect(
                serviceRegistryTokenUtility.connect(operator).resetServiceToken(serviceId)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "ManagerOnly");
            // Reset the token and check its record
            await serviceRegistryTokenUtility.connect(deployer).resetServiceToken(serviceId);
            tokenSecurityDeposit = await serviceRegistryTokenUtility.mapServiceIdTokenDeposit(serviceId);
            expect(tokenSecurityDeposit.token).to.equal(AddressZero);
            expect(tokenSecurityDeposit.securityDeposit).to.equal(0);

            // Check if the service is token secured
            expect(await serviceRegistryTokenUtility.isTokenSecuredService(serviceId)).to.be.false;
        });
    });

    context("Activate registration", function () {
        it("Should fail if not called by the manager", async function () {
            await expect(
                serviceRegistryTokenUtility.connect(operator).activateRegistrationTokenDeposit(serviceId)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "ManagerOnly");
        });

        it("Try to activate a service with a zero-address token", async function () {
            const isTokenSecured = await serviceRegistryTokenUtility.callStatic.activateRegistrationTokenDeposit(serviceId + 1);
            expect(isTokenSecured).to.equal(false);
        });

        it("Create a service record for a specific token and activate it", async function () {
            await serviceRegistryTokenUtility.createWithToken(serviceId, token.address, agentIds, bonds);
            const securityDeposit = Math.max(...bonds);
            // Check for the service token address
            let tokenSecurityDeposit = await serviceRegistryTokenUtility.mapServiceIdTokenDeposit(serviceId);
            expect(tokenSecurityDeposit.token).to.equal(token.address);
            expect(tokenSecurityDeposit.securityDeposit).to.equal(securityDeposit);

            // Try to activate a service without approving the ServiceRegistryTokenUtility contract for the security deposit amount
            await expect(
                serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "IncorrectRegistrationDepositValue");

            // Approve token for the ServiceRegistryTokenUtility contract
            await token.connect(deployer).approve(serviceRegistryTokenUtility.address, securityDeposit);

            // Check the activation status
            const isTokenSecured = await serviceRegistryTokenUtility.callStatic.activateRegistrationTokenDeposit(serviceId);
            expect(isTokenSecured).to.equal(true);
            await serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId);
        });
    });

    context("Register agents", function () {
        it("Should fail if not called by the manager", async function () {
            await expect(
                serviceRegistryTokenUtility.connect(operator).registerAgentsTokenDeposit(operator.address, serviceId, agentIds)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "ManagerOnly");
        });

        it("Try to register agent instances with a zero-address token", async function () {
            const isTokenSecured = await serviceRegistryTokenUtility.callStatic.registerAgentsTokenDeposit(operator.address,
                serviceId + 1, agentIds);
            expect(isTokenSecured).to.equal(false);
        });

        it("Create a service record for a specific token, activate it and register agent instances", async function () {
            await serviceRegistryTokenUtility.createWithToken(serviceId, token.address, agentIds, bonds);
            const securityDeposit = Math.max(...bonds);
            // Check for the service token address
            let tokenSecurityDeposit = await serviceRegistryTokenUtility.mapServiceIdTokenDeposit(serviceId);
            expect(tokenSecurityDeposit.token).to.equal(token.address);
            expect(tokenSecurityDeposit.securityDeposit).to.equal(securityDeposit);


            // Approve token for the ServiceRegistryTokenUtility contract and activate registration
            await token.connect(deployer).approve(serviceRegistryTokenUtility.address, securityDeposit);
            await serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId);

            // Try to register agent instances without approving the ServiceRegistryTokenUtility contract for the security deposit amount
            await expect(
                serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, serviceId, agentIds)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "IncorrectAgentBondingValue");

            // Approve token for the ServiceRegistryTokenUtility contract by the operator and register agent instances
            const totalBond = bonds.reduce((a, b) => a + b, 0);
            await token.connect(operator).approve(serviceRegistryTokenUtility.address, totalBond);

            // Check the registration status
            const isTokenSecured = await serviceRegistryTokenUtility.callStatic.registerAgentsTokenDeposit(operator.address,
                serviceId, agentIds);
            expect(isTokenSecured).to.equal(true);
            await serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, serviceId, agentIds);
        });
    });

    context("Full cycle of service routines", function () {
        it("Should fail if not called by the manager", async function () {
            await expect(
                serviceRegistryTokenUtility.connect(operator).terminateTokenRefund(serviceId)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "ManagerOnly");

            await expect(
                serviceRegistryTokenUtility.connect(operator).unbondTokenRefund(operator.address, serviceId)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "ManagerOnly");
        });

        it("Try to register agent instances with a zero-address token", async function () {
            let refund = await serviceRegistryTokenUtility.callStatic.terminateTokenRefund(serviceId + 1);
            expect(refund).to.equal(0);

            refund = await serviceRegistryTokenUtility.callStatic.unbondTokenRefund(operator.address, serviceId + 1);
            expect(refund).to.equal(0);
        });

        it("Create, activate, register agent instances, terminate, unbond", async function () {
            await serviceRegistryTokenUtility.createWithToken(serviceId, token.address, agentIds, bonds);
            const securityDeposit = Math.max(...bonds);
            // Check for the service token address
            let tokenSecurityDeposit = await serviceRegistryTokenUtility.mapServiceIdTokenDeposit(serviceId);
            expect(tokenSecurityDeposit.token).to.equal(token.address);
            expect(tokenSecurityDeposit.securityDeposit).to.equal(securityDeposit);


            // Approve token for the ServiceRegistryTokenUtility contract and activate registration
            await token.connect(deployer).approve(serviceRegistryTokenUtility.address, securityDeposit);
            await serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId);

            // Try to register agent instances without approving the ServiceRegistryTokenUtility contract for the security deposit amount
            await expect(
                serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, serviceId, agentIds)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "IncorrectAgentBondingValue");

            // Approve token for the ServiceRegistryTokenUtility contract by the operator and register agent instances
            const totalBond = bonds.reduce((a, b) => a + b, 0);
            await token.connect(operator).approve(serviceRegistryTokenUtility.address, totalBond);

            // Register agent instances
            await serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, serviceId, agentIds);

            // Check the termination refund
            let refund = await serviceRegistryTokenUtility.callStatic.terminateTokenRefund(serviceId);
            expect(refund).to.equal(securityDeposit);
            await serviceRegistryTokenUtility.terminateTokenRefund(serviceId);

            // Check the unbond refund
            refund = await serviceRegistryTokenUtility.callStatic.unbondTokenRefund(operator.address, serviceId);
            expect(refund).to.equal(totalBond);
            await serviceRegistryTokenUtility.unbondTokenRefund(operator.address, serviceId);
        });

        it("Should fail on slashing with wrong parameters", async function () {
            // Try to slash when the service is not deployed
            await expect(
                serviceRegistryTokenUtility.slash([AddressZero], [0], 0)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "WrongServiceState");

            // Try to slash with empty arrays
            await expect(
                serviceRegistryTokenUtility.slash([], [], serviceId)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "WrongArrayLength");

            // Try to slash with incorrect array lengths
            await expect(
                serviceRegistryTokenUtility.slash([AddressZero], [], serviceId)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "WrongArrayLength");

            // Try to slash with the wrong service multisig
            await expect(
                serviceRegistryTokenUtility.slash([AddressZero], [0], serviceId + 1)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "OnlyOwnServiceMultisig");

            // Try to slash the service that is not token-secured
            await expect(
                serviceRegistryTokenUtility.slash([AddressZero], [0], serviceId)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "ZeroAddress");
        });

        it("Create, activate, register agent instances, slash, terminate, unbond, drain", async function () {
            await serviceRegistryTokenUtility.createWithToken(serviceId, token.address, agentIds, bonds);
            const securityDeposit = Math.max(...bonds);
            // Check for the service token address
            let tokenSecurityDeposit = await serviceRegistryTokenUtility.mapServiceIdTokenDeposit(serviceId);
            expect(tokenSecurityDeposit.token).to.equal(token.address);
            expect(tokenSecurityDeposit.securityDeposit).to.equal(securityDeposit);


            // Approve token for the ServiceRegistryTokenUtility contract and activate registration
            await token.connect(deployer).approve(serviceRegistryTokenUtility.address, securityDeposit);
            await serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId);

            // Approve token for the ServiceRegistryTokenUtility contract by the operator and register agent instances
            const totalBond = bonds.reduce((a, b) => a + b, 0);
            await token.connect(operator).approve(serviceRegistryTokenUtility.address, totalBond);

            // Register agent instances
            await serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, serviceId, agentIds);

            // Slash the operator
            const minBond = Math.min(...bonds);
            await serviceRegistryTokenUtility.slash([operator.address], [minBond], serviceId);
            // Check for the contract slashed balance
            let slashedBalance = Number(await serviceRegistryTokenUtility.mapSlashedFunds(token.address));
            expect(slashedBalance).to.equal(minBond);

            // Slash more
            await serviceRegistryTokenUtility.slash([operator.address], [securityDeposit], serviceId);
            // Slash even more such that there is nothing to slash
            await serviceRegistryTokenUtility.slash([operator.address], [securityDeposit], serviceId);
            await serviceRegistryTokenUtility.slash([operator.address], [securityDeposit], serviceId);
            slashedBalance = Number(await serviceRegistryTokenUtility.mapSlashedFunds(token.address));
            expect(slashedBalance).to.equal(totalBond);

            // Terminate the service
            await serviceRegistryTokenUtility.terminateTokenRefund(serviceId);

            // Check the unbond refund
            const refund = await serviceRegistryTokenUtility.getOperatorBalance(operator.address, serviceId);
            expect(refund).to.equal(0);
            await serviceRegistryTokenUtility.unbondTokenRefund(operator.address, serviceId);

            // Drain slashed funds
            const account = signers[2];
            // Try to drain with a zero drainer address
            await expect(
                serviceRegistryTokenUtility.connect(deployer).drain(token.address)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "ZeroAddress");
            await serviceRegistryTokenUtility.changeDrainer(account.address);
            // Try to drain not by the owner
            await expect(
                serviceRegistryTokenUtility.connect(operator).drain(token.address)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "OwnerOnly");
            // Try to drain non existent token funds
            await serviceRegistryTokenUtility.drain(AddressZero);
            // Drain the token funds
            const balanceBefore = Number(await token.balanceOf(account.address));
            await serviceRegistryTokenUtility.drain(token.address);
            const balanceAfter = Number(await token.balanceOf(account.address));
            expect(balanceAfter).to.equal(balanceBefore + totalBond);

            // Try to drain again when there is nothing left to drain
            await serviceRegistryTokenUtility.drain(token.address);
            const balanceAfterZeroDrain = Number(await token.balanceOf(account.address));
            expect(balanceAfter).to.equal(balanceAfterZeroDrain);
        });
    });

    context("Attacks", async function () {
        it("Failed transferFrom during the service activation", async function () {
            // Record token data when creating a service
            await serviceRegistryTokenUtility.createWithToken(serviceId, reentrancyAttacker.address, agentIds, bonds);

            // Set the transferFrom failure
            await reentrancyAttacker.setAttackState(4);

            // Try to activate registration with the failed transferFrom
            await expect(
                serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "TransferFailed");
        });

        it("Failed transfer during the termination", async function () {
            // Record token data when creating a service
            await serviceRegistryTokenUtility.createWithToken(serviceId, reentrancyAttacker.address, agentIds, bonds);

            // Set the transfer failure
            await reentrancyAttacker.setAttackState(3);

            // Activate registration
            await serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId);

            // Try to terminate a service with the failed transfer function
            await expect(
                serviceRegistryTokenUtility.terminateTokenRefund(serviceId)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "TransferFailed");
        });

        it("Incorrectly received funds during the transferFrom function call in registration activation", async function () {
            // Record token data when creating a service
            await serviceRegistryTokenUtility.createWithToken(serviceId, reentrancyAttacker.address, agentIds, bonds);

            // Set the balance failure where the second balanceOf is lower than the first one
            await reentrancyAttacker.setAttackState(1);

            // Try to activate registration with the incorrect transferFrom function
            await expect(
                serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "IncorrectRegistrationDepositValue");

            // Set the balance failure such that the diff of balanceOf before and after the transferFrom is invalid
            await reentrancyAttacker.setAttackState(2);

            // Try to activate registration with the incorrect transferFrom function
            await expect(
                serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "IncorrectRegistrationDepositValue");
        });

        it("Incorrectly received funds during the transferFrom function call in agent registration", async function () {
            // Record token data when creating a service
            await serviceRegistryTokenUtility.createWithToken(serviceId, reentrancyAttacker.address, agentIds, bonds);
            // Activate service registration
            await serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId);

            // Set the balance failure where the second balanceOf is lower than the first one
            await reentrancyAttacker.setAttackState(1);
            // Try to register agent instances with the incorrect transferFrom function
            await expect(
                serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, serviceId, agentIds)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "IncorrectAgentBondingValue");

            // Set the balance failure such that the diff of balanceOf before and after the transferFrom is invalid
            await reentrancyAttacker.setAttackState(2);
            // Try to register agent instances with the incorrect transferFrom function
            await expect(
                serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, serviceId, agentIds)
            ).to.be.revertedWithCustomError(serviceRegistryTokenUtility, "IncorrectAgentBondingValue");
        });

        it("Reentrancy attack during the service activation", async function () {
            // Record token data when creating a service
            await serviceRegistryTokenUtility.createWithToken(serviceId, reentrancyAttacker.address, agentIds, bonds);

            // Set the reentrancy attack on registration activation
            await reentrancyAttacker.setAttackState(5);

            // Try to activate registration
            await expect(
                serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId)
            ).to.be.reverted;
        });

        it("Reentrancy attack during the agent registration", async function () {
            // Record token data when creating a service
            await serviceRegistryTokenUtility.createWithToken(serviceId, reentrancyAttacker.address, agentIds, bonds);

            // Set the reentrancy attack on agent instance registration
            await reentrancyAttacker.setAttackState(6);

            // Activate service registration
            serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId);
            // Try to register agent instances
            await expect(
                serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, serviceId, agentIds)
            ).to.be.reverted;
        });

        it("Reentrancy attack during the termination", async function () {
            // Record token data when creating a service
            await serviceRegistryTokenUtility.createWithToken(serviceId, reentrancyAttacker.address, agentIds, bonds);
            // Activate service registration
            serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId);
            // Register agent instances
            await serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, serviceId, agentIds);

            // Set the reentrancy attack on service termination
            await reentrancyAttacker.setAttackState(7);
            // Try to terminate the service
            await expect(
                serviceRegistryTokenUtility.terminateTokenRefund(serviceId)
            ).to.be.reverted;
        });

        it("Reentrancy attack during the unbond", async function () {
            // Record token data when creating a service
            await serviceRegistryTokenUtility.createWithToken(serviceId, reentrancyAttacker.address, agentIds, bonds);
            // Activate service registration
            serviceRegistryTokenUtility.activateRegistrationTokenDeposit(serviceId);
            // Register agent instances
            await serviceRegistryTokenUtility.registerAgentsTokenDeposit(operator.address, serviceId, agentIds);
            // Terminate the service
            await serviceRegistryTokenUtility.terminateTokenRefund(serviceId);

            // Set the reentrancy attack on agent instances unbond
            await reentrancyAttacker.setAttackState(8);
            // Try to terminate the service
            await expect(
                serviceRegistryTokenUtility.unbondTokenRefund(operator.address, serviceId)
            ).to.be.reverted;
        });
    });
});
