/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("GnosisSafeMultisig", function () {
    let gnosisSafe;
    let gnosisSafeProxyFactory;
    let gnosisSafeMultisig;
    let signers;
    let defaultOwnerAddresses;
    const threshold = 2;
    const AddressZero = "0x" + "0".repeat(40);
    const maxUint256 = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

    beforeEach(async function () {
        const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
        gnosisSafe = await GnosisSafe.deploy();
        await gnosisSafe.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const GnosisSafeMultisig = await ethers.getContractFactory("GnosisSafeMultisig");
        gnosisSafeMultisig = await GnosisSafeMultisig.deploy(gnosisSafe.address, gnosisSafeProxyFactory.address);
        await gnosisSafeMultisig.deployed();

        signers = await ethers.getSigners();
        defaultOwnerAddresses = [signers[1].address, signers[2].address, signers[3].address];
    });

    context("Creating multisigs", async function () {
        it("Passing the zero data value", async function () {
            // Pass the default multisig owner addresses, threshold and a zero input
            const tx = await gnosisSafeMultisig.create(defaultOwnerAddresses, threshold, "0x");
            const result = await tx.wait();

            // Check that the obtained address is not zero
            expect(result.events[0].address).to.not.equal(AddressZero);
        });

        it("Should fail when passing the non-zero multisig data with the incorrect number of bytes", async function () {
            await expect(
                gnosisSafeMultisig.create(defaultOwnerAddresses, threshold, "0x55")
            ).to.be.revertedWith("IncorrectDataLength");
        });

        it("Passing static fields to meet the minimum bytes length requirement with a zero payload", async function () {
            const to = signers[4].address;
            const fallbackHandler = signers[5].address;
            const paymentToken = signers[6].address;
            const paymentReceiver = signers[7].address;
            const payment = 0;
            const nonce = parseInt(Date.now() / 1000, 10);
            const payload = "0x";
            // Pack the data
            const data = ethers.utils.solidityPack(["address", "address", "address", "address", "uint256", "uint256", "bytes"],
                [to, fallbackHandler, paymentToken, paymentReceiver, payment, nonce, payload]);

            // Create a multisig with the packed data
            const tx = await gnosisSafeMultisig.create(defaultOwnerAddresses, threshold, data);
            const result = await tx.wait();

            // Check that the obtained address is not zero
            expect(result.events[0].address).to.not.equal(AddressZero);
            const proxyAddress = result.events[0].address;

            // Get the safe multisig instance
            const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);

            // Check the multisig owners and threshold
            const owners = await multisig.getOwners();
            for (let i = 0; i < defaultOwnerAddresses.length; i++) {
                expect(owners[i]).to.equal(defaultOwnerAddresses[i]);
            }
            expect(await multisig.getThreshold()).to.equal(threshold);
        });

        it("Passing static fields together with the non-zero payload data", async function () {
            const to = signers[4].address;
            const fallbackHandler = signers[5].address;
            const paymentToken = signers[6].address;
            const paymentReceiver = signers[7].address;
            const payment = 0;
            const nonce = parseInt(Date.now() / 1000, 10);
            const payload = "0xabcd";
            // Pack the data
            const data = ethers.utils.solidityPack(["address", "address", "address", "address", "uint256", "uint256", "bytes"],
                [to, fallbackHandler, paymentToken, paymentReceiver, payment, nonce, payload]);

            // Create a multisig with the packed data
            const tx = await gnosisSafeMultisig.create(defaultOwnerAddresses, threshold, data);
            const result = await tx.wait();

            // Check that the obtained address is not zero
            expect(result.events[0].address).to.not.equal(AddressZero);
            const proxyAddress = result.events[0].address;

            // Get the safe multisig instance
            const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);

            // Check the multisig owners and threshold
            const owners = await multisig.getOwners();
            for (let i = 0; i < defaultOwnerAddresses.length; i++) {
                expect(owners[i]).to.equal(defaultOwnerAddresses[i]);
            }
            expect(await multisig.getThreshold()).to.equal(threshold);
        });

        it("Passing static fields together with a max possible nonce and a bigger payload data", async function () {
            const payload = "0x" + "1".repeat(100) + "2".repeat(200) + "3".repeat(300);
            // Pack the data
            const data = ethers.utils.solidityPack(["address", "address", "address", "address", "uint256", "uint256", "bytes"],
                [AddressZero, AddressZero, AddressZero, AddressZero, 0, maxUint256, payload]);

            // Create a multisig with the packed data
            const tx = await gnosisSafeMultisig.create(defaultOwnerAddresses, threshold, data);
            const result = await tx.wait();

            // Check that the obtained address is not zero
            expect(result.events[0].address).to.not.equal(AddressZero);
            const proxyAddress = result.events[0].address;

            // Get the safe multisig instance
            const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);

            // Check the multisig owners and threshold
            const owners = await multisig.getOwners();
            for (let i = 0; i < defaultOwnerAddresses.length; i++) {
                expect(owners[i]).to.equal(defaultOwnerAddresses[i]);
            }
            expect(await multisig.getThreshold()).to.equal(threshold);
        });

        it("Setting a guard contract address that guards transactions for not being able to transfer ETH funds", async function () {
            // Set up a guard contract with the last Safe owner being the guard owner
            const SafeGuard = await ethers.getContractFactory("SafeGuard");
            const safeGuard = await SafeGuard.deploy(signers[2].address);
            await safeGuard.deployed();

            const to = safeGuard.address;
            const fallbackHandler = AddressZero;
            const paymentToken = AddressZero;
            const paymentReceiver = AddressZero;
            const payment = 0;
            let nonce = 0;
            const payload = safeGuard.interface.encodeFunctionData("setGuardForSafe", [safeGuard.address]);
            // Pack the data
            const data = ethers.utils.solidityPack(["address", "address", "address", "address", "uint256", "uint256", "bytes"],
                [to, fallbackHandler, paymentToken, paymentReceiver, payment, nonce, payload]);

            // Create a multisig with the packed data
            const tx = await gnosisSafeMultisig.create(defaultOwnerAddresses, threshold, data);
            const result = await tx.wait();

            // Check that the obtained address is not zero
            expect(result.events[0].address).to.not.equal(AddressZero);
            const proxyAddress = result.events[0].address;

            // Get the safe multisig instance
            const multisig = await ethers.getContractAt("GnosisSafe", proxyAddress);

            // Check the multisig owners and threshold
            const owners = await multisig.getOwners();
            for (let i = 0; i < defaultOwnerAddresses.length; i++) {
                expect(owners[i]).to.equal(defaultOwnerAddresses[i]);
            }
            expect(await multisig.getThreshold()).to.equal(threshold);

            // Check the guard slot
            const guardSlot = "0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8";
            let slotValue = await ethers.provider.getStorageAt(multisig.address, guardSlot);
            slotValue = ethers.utils.hexlify(ethers.utils.stripZeros(slotValue));
            const safeGuardAddress = safeGuard.address.toLowerCase();
            expect(slotValue).to.equal(safeGuardAddress);

            // Send funds to the multisig address
            await signers[0].sendTransaction({to: multisig.address, value: ethers.utils.parseEther("1000")});

            // Try to send ETH funds from the multisig using first two Safe owners while facing the guard check
            const safeContracts = require("@gnosis.pm/safe-contracts");
            nonce = await multisig.nonce();
            // The function call is irrelevant, we just need to pass the value
            let txHashData = await safeContracts.buildContractCall(multisig, "nonce", [], nonce, 0, 0);
            txHashData.value = ethers.utils.parseEther("10");
            const signMessageData = [await safeContracts.safeSignMessage(signers[1], multisig, txHashData, 0),
                await safeContracts.safeSignMessage(signers[2], multisig, txHashData, 0)];
            await expect(
                safeContracts.executeTx(multisig, txHashData, signMessageData, 0)
            ).to.be.revertedWith("Guarded");
        });
    });
});
