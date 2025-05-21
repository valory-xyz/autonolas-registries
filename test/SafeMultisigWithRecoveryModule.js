/*global describe, beforeEach, it*/

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SafeMultisigWithRecoveryModule", function () {
    let gnosisSafe;
    let gnosisSafeProxyFactory;
    let safeMultisigWithRecoveryModule;
    let recoveryModule;
    let owner;
    let other;

    beforeEach(async () => {
        [owner, other] = await ethers.getSigners();

        // Deploy Safe, Factory, and Recovery Module
        const GnosisSafe = await ethers.getContractFactory("GnosisSafe");
        gnosisSafe = await GnosisSafe.deploy();
        await gnosisSafe.deployed();

        const GnosisSafeProxyFactory = await ethers.getContractFactory("GnosisSafeProxyFactory");
        gnosisSafeProxyFactory = await GnosisSafeProxyFactory.deploy();
        await gnosisSafeProxyFactory.deployed();

        const RecoveryModule = await ethers.getContractFactory("RecoveryModule");
        recoveryModule = await RecoveryModule.deploy(owner.address, owner.address);
        await recoveryModule.deployed();

        const SafeMultisigFactory = await ethers.getContractFactory("SafeMultisigWithRecoveryModule");
        safeMultisigWithRecoveryModule = await SafeMultisigFactory.deploy(
            gnosisSafe.address,
            gnosisSafeProxyFactory.address,
            recoveryModule.address
        );
    });

    it("Should revert if any constructor address is zero", async () => {
        const SafeMultisig = await ethers.getContractFactory("SafeMultisigWithRecoveryModule");

        await expect(
            SafeMultisig.deploy(ethers.constants.AddressZero, gnosisSafeProxyFactory.address, recoveryModule.address)
        ).to.be.revertedWithCustomError(safeMultisigWithRecoveryModule, "ZeroAddress");

        await expect(
            SafeMultisig.deploy(gnosisSafe.address, ethers.constants.AddressZero, recoveryModule.address)
        ).to.be.revertedWithCustomError(safeMultisigWithRecoveryModule, "ZeroAddress");

        await expect(
            SafeMultisig.deploy(gnosisSafe.address, gnosisSafeProxyFactory.address, ethers.constants.AddressZero)
        ).to.be.revertedWithCustomError(safeMultisigWithRecoveryModule, "ZeroAddress");
    });

    it("Should revert if data length is invalid", async () => {
        await expect(
            safeMultisigWithRecoveryModule.create([owner.address], 1, ethers.utils.hexlify("0x00"))
        ).to.be.revertedWithCustomError(safeMultisigWithRecoveryModule, "IncorrectDataLength");
    });

    it("Should revert on reentrancy", async () => {
        // manually lock
        await ethers.provider.send("hardhat_setStorageAt", [
            safeMultisigWithRecoveryModule.address,
            ethers.utils.hexZeroPad("0x0", 32),
            ethers.utils.hexZeroPad("0x2", 32),
        ]);

        await expect(
            safeMultisigWithRecoveryModule.create([owner.address], 1, "0x")
        ).to.be.revertedWithCustomError(safeMultisigWithRecoveryModule, "ReentrancyGuard");
    });

    it("Should create multisig with empty data (nonce = 0)", async () => {
        const tx = await safeMultisigWithRecoveryModule.create([owner.address], 1, "0x");
        const receipt = await tx.wait();

        const event = receipt.events.find(
            (e) => e.event === undefined && e.address === gnosisSafeProxyFactory.address
        );
        expect(event).to.exist;
    });

    it("Should create multisig with correct data (fallback + nonce)", async () => {
        const fallbackHandler = other.address;
        const nonce = 42;
        const encoded = ethers.utils.defaultAbiCoder.encode(
            ["address", "uint256"],
            [fallbackHandler, nonce]
        );

        const tx = await safeMultisigWithRecoveryModule.create([owner.address], 1, encoded);
        const receipt = await tx.wait();

        const event = receipt.events.find(
            (e) => e.event === undefined && e.address === gnosisSafeProxyFactory.address
        );
        expect(event).to.exist;
    });
});
