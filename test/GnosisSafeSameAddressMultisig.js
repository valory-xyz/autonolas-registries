/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("GnosisSafeSameAddressMultisig", function () {
    let gnosisSafe;
    let gnosisSafeProxyFactory;
    let gnosisSafeSameAddressMultisig;
    let signers;
    let initialOwner;
    let newOwnerAddresses;
    const initialThreshold = 1;
    const newThreshold = 3;
    const AddressZero = "0x" + "0".repeat(40);
    const maxUint256 = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

    beforeEach(async function () {
        const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
        gnosisSafe = await GnosisSafe.deploy();
        await gnosisSafe.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
        gnosisSafeSameAddressMultisig = await GnosisSafeSameAddressMultisig.deploy(gnosisSafe.address);
        await gnosisSafeSameAddressMultisig.deployed();

        signers = await ethers.getSigners();
        initialOwner = signers[1];
        newOwnerAddresses = [signers[1].address, signers[2].address, signers[3].address, signers[4].address];
    });

    context("Verifying multisigs", async function () {
        it("Should fail when passing the non-zero multisig data with the incorrect number of bytes", async function () {
            await expect(
                gnosisSafeSameAddressMultisig.create(newOwnerAddresses, initialThreshold, "0x55")
            ).to.be.revertedWith("IncorrectDataLength");

            const data = AddressZero + "55";
            await expect(
                gnosisSafeSameAddressMultisig.create(newOwnerAddresses, initialThreshold, data)
            ).to.be.revertedWith("IncorrectDataLength");
        });

        it("Create a multisig and change its owners and threshold", async function () {
            // Create an initial multisig with a salt being the max of uint256
            const safeContracts = require("@gnosis.pm/safe-contracts");
            const setupData = gnosisSafe.interface.encodeFunctionData(
                "setup",
                // signers, threshold, to_address, data, fallback_handler, payment_token, payment, payment_receiver
                [[initialOwner.address], initialThreshold, AddressZero, "0x", AddressZero, AddressZero, 0, AddressZero]
            );
            const proxyAddress = await safeContracts.calculateProxyAddress(gnosisSafeProxyFactory, gnosisSafe.address,
                setupData, maxUint256);
            await gnosisSafeProxyFactory.createProxyWithNonce(gnosisSafe.address, setupData, maxUint256).then((tx) => tx.wait());
            const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);

            // Pack the original multisig address
            const data = ethers.utils.solidityPack(["address"], [multisig.address]);

            // Update multisig with the same owners and threshold
            let updatedMultisigAddress = await gnosisSafeSameAddressMultisig.create([initialOwner.address], initialThreshold, data);
            expect(multisig.address).to.equal(updatedMultisigAddress);

            // Try to verify incorrect multisig data
            // Threshold is incorrect
            await expect(
                gnosisSafeSameAddressMultisig.create([initialOwner.address], newThreshold, data)
            ).to.be.revertedWith("WrongThreshold");

            // Number of owners does not match
            await expect(
                gnosisSafeSameAddressMultisig.create(newOwnerAddresses, initialThreshold, data)
            ).to.be.revertedWith("WrongNumOwners");

            // Number of owners is the same, but the addresses are different
            await expect(
                gnosisSafeSameAddressMultisig.create([signers[2].address], initialThreshold, data)
            ).to.be.revertedWith("WrongOwner");

            // Change the multisig owners and threshold (skipping the first one)
            // Add owners
            for (let i = 1; i < newOwnerAddresses.length; i++) {
                const nonce = await multisig.nonce();
                const txHashData = await safeContracts.buildContractCall(multisig, "addOwnerWithThreshold",
                    [newOwnerAddresses[i], 1], nonce, 0, 0);
                const signMessageData = await safeContracts.safeSignMessage(initialOwner, multisig, txHashData, 0);
                await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);
            }
            // Change threshold
            const nonce = await multisig.nonce();
            const txHashData = await safeContracts.buildContractCall(multisig, "changeThreshold",
                [newThreshold], nonce, 0, 0);
            const signMessageData = await safeContracts.safeSignMessage(initialOwner, multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Verify the new multisig data
            updatedMultisigAddress = await gnosisSafeSameAddressMultisig.create(newOwnerAddresses, newThreshold, data);
            expect(multisig.address).to.equal(updatedMultisigAddress);
        });
    });
});
