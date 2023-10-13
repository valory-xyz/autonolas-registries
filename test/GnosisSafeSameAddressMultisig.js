/*global describe, context, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("GnosisSafeSameAddressMultisig", function () {
    let gnosisSafe;
    let gnosisSafeProxyFactory;
    let multiSend;
    let gnosisSafeSameAddressMultisig;
    let signers;
    let initialOwner;
    let newOwnerAddresses;
    const initialThreshold = 1;
    const newThreshold = 3;
    const AddressZero = "0x" + "0".repeat(40);
    const maxUint256 = "115792089237316195423570985008687907853269984665640564039457584007913129639935";
    let bytecodeHash;

    beforeEach(async function () {
        const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
        gnosisSafe = await GnosisSafe.deploy();
        await gnosisSafe.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const MultiSend = await ethers.getContractFactory("MultiSendCallOnly");
        multiSend = await MultiSend.deploy();
        await multiSend.deployed();

        const GnosisSafeProxy = await ethers.getContractFactory("GnosisSafeProxy");
        const gnosisSafeProxy = await GnosisSafeProxy.deploy(gnosisSafe.address);
        await gnosisSafeProxy.deployed();
        const bytecode = await ethers.provider.getCode(gnosisSafeProxy.address);
        bytecodeHash = ethers.utils.keccak256(bytecode);

        const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
        gnosisSafeSameAddressMultisig = await GnosisSafeSameAddressMultisig.deploy(bytecodeHash);
        await gnosisSafeSameAddressMultisig.deployed();

        signers = await ethers.getSigners();
        initialOwner = signers[1];
        newOwnerAddresses = [signers[1].address, signers[2].address, signers[3].address, signers[4].address];
    });

    context("Verifying multisigs", async function () {
        it("Try to deploy a contract without specified proxies or zero hashes", async function () {
            const GnosisSafeSameAddressMultisig = await ethers.getContractFactory("GnosisSafeSameAddressMultisig");
            const bytes32Zero = "0x" + "0".repeat(64);
            await expect(
                GnosisSafeSameAddressMultisig.deploy(bytes32Zero)
            ).to.be.revertedWithCustomError(gnosisSafeSameAddressMultisig, "ZeroValue");
        });

        it("Should fail when passing the non-zero multisig data with the incorrect number of bytes", async function () {
            await expect(
                gnosisSafeSameAddressMultisig.create(newOwnerAddresses, initialThreshold, "0x55")
            ).to.be.revertedWithCustomError(gnosisSafeSameAddressMultisig, "IncorrectDataLength");

            const data = AddressZero + "55";
            await expect(
                gnosisSafeSameAddressMultisig.create(newOwnerAddresses, initialThreshold, data)
            ).to.be.reverted;
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
            // Static call to compare results
            let updatedMultisigAddress = await gnosisSafeSameAddressMultisig.callStatic.create([initialOwner.address],
                initialThreshold, data);
            expect(multisig.address).to.equal(updatedMultisigAddress);
            // Real call
            await gnosisSafeSameAddressMultisig.create([initialOwner.address], initialThreshold, data);

            // Try to verify incorrect multisig data
            // Threshold is incorrect
            await expect(
                gnosisSafeSameAddressMultisig.create([initialOwner.address], newThreshold, data)
            ).to.be.revertedWithCustomError(gnosisSafeSameAddressMultisig, "WrongThreshold");

            // Number of owners does not match
            await expect(
                gnosisSafeSameAddressMultisig.create(newOwnerAddresses, initialThreshold, data)
            ).to.be.revertedWithCustomError(gnosisSafeSameAddressMultisig, "WrongNumOwners");

            // Number of owners is the same, but the addresses are different
            await expect(
                gnosisSafeSameAddressMultisig.create([signers[2].address], initialThreshold, data)
            ).to.be.revertedWithCustomError(gnosisSafeSameAddressMultisig, "WrongOwner");

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
            updatedMultisigAddress = await gnosisSafeSameAddressMultisig.callStatic.create(newOwnerAddresses, newThreshold, data);
            expect(multisig.address).to.equal(updatedMultisigAddress);
        });

        it("Create a multisig and change its owners and threshold via a multisend", async function () {
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

            // Swap the owner of the multisig to the deployer (initial owner to give up rights for the deployer)
            const deployer = signers[0];
            const sentinelOwners = "0x" + "0".repeat(39) + "1";
            let nonce = await multisig.nonce();
            const txHashData = await safeContracts.buildContractCall(multisig, "swapOwner",
                [sentinelOwners, initialOwner.address, deployer.address], nonce, 0, 0);
            const signMessageData = await safeContracts.safeSignMessage(initialOwner, multisig, txHashData, 0);
            await safeContracts.executeTx(multisig, txHashData, [signMessageData], 0);

            // Add all the new multisig owner addresses and remove the deployer
            let callData = [];
            let txs = [];
            nonce = await multisig.nonce();
            // Add the addresses, but keep the threshold the same
            for (let i = 0; i < newOwnerAddresses.length; i++) {
                callData[i] = multisig.interface.encodeFunctionData("addOwnerWithThreshold", [newOwnerAddresses[i], 1]);
                txs[i] = safeContracts.buildSafeTransaction({to: multisig.address, data: callData[i], nonce: 0});
            }
            // Remove the original multisig owner and change the threshold
            // Note that the prevOwner is the very first added address as it corresponds to the reverse order of added addresses
            // The order in the gnosis safe multisig is as follows: sentinelOwners => newOwnerAddresses[last] => ... =>
            // => newOwnerAddresses[0] => deployer
            callData.push(multisig.interface.encodeFunctionData("removeOwner", [newOwnerAddresses[0], deployer.address,
                newThreshold]));
            txs.push(safeContracts.buildSafeTransaction({to: multisig.address, data: callData[callData.length - 1], nonce: 0}));
            let safeTx = safeContracts.buildMultiSendSafeTx(multiSend, txs, nonce);
            await expect(
                safeContracts.executeTxWithSigners(multisig, safeTx, [deployer])
            ).to.emit(multisig, "ExecutionSuccess");

            // Pack the original multisig address
            const data = ethers.utils.solidityPack(["address"], [multisig.address]);

            // Verify the new multisig data
            const updatedMultisigAddress = await gnosisSafeSameAddressMultisig.callStatic.create(newOwnerAddresses, newThreshold, data);
            expect(multisig.address).to.equal(updatedMultisigAddress);
        });
    });
});
