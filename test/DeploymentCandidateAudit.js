/* eslint-env mocha, node */
const { expect } = require("chai");
const { ethers, artifacts, network } = require("hardhat");
const { checkDeploymentCandidate } = require("../scripts/audit_chains/audit_contracts_setup");

describe("Deployment candidate audit", function () {
    let globals, manager, proxy, wrapper, managerArtifact, wrapperArtifact, snapshot;

    before(async function () {
        const [owner, utility, safe, safeFactory] = await ethers.getSigners();
        const Registry = await ethers.getContractFactory("ServiceRegistryL2");
        const registry = await Registry.deploy("Services", "SVC", "https://example.invalid/");
        const Manager = await ethers.getContractFactory("ServiceManager");
        manager = await Manager.deploy(registry.address, utility.address);
        const oldManager = await Manager.deploy(registry.address, utility.address);
        const Proxy = await ethers.getContractFactory("ServiceManagerProxy");
        proxy = await Proxy.deploy(oldManager.address, Manager.interface.encodeFunctionData("initialize"));
        const Wrapper = await ethers.getContractFactory("GnosisSafeMultisig");
        wrapper = await Wrapper.deploy(safe.address, safeFactory.address);
        globals = {
            chainId: (await ethers.provider.getNetwork()).chainId,
            serviceManagerAddress: manager.address,
            serviceManagerProxyAddress: proxy.address,
            serviceRegistryAddress: registry.address,
            serviceRegistryTokenUtilityAddress: utility.address,
            gnosisSafeMultisigImplementationAddress: wrapper.address,
            gnosisSafeAddress: safe.address,
            gnosisSafeProxyFactoryAddress: safeFactory.address,
            previousWrapper: owner.address
        };
        managerArtifact = await artifacts.readArtifact("ServiceManager");
        wrapperArtifact = await artifacts.readArtifact("GnosisSafeMultisig");
    });

    beforeEach(async function () {
        snapshot = await network.provider.send("evm_snapshot");
    });
    afterEach(async function () {
        await network.provider.send("evm_revert", [snapshot]);
    });

    const audit = (globals, name, artifact, activated = false, old) =>
        checkDeploymentCandidate(ethers.provider, globals, name, artifact, activated, old);

    it("rejects missing, malformed or zero proxy addresses before any RPC reads", async function () {
        const noReads = { getNetwork: async () => { throw new Error("Unexpected RPC read"); } };
        for (const address of [undefined, "not-an-address", ethers.constants.AddressZero]) {
            await expect(checkDeploymentCandidate(noReads, { ...globals, serviceManagerProxyAddress: address },
                "ServiceManager", managerArtifact)).to.be.rejectedWith("serviceManagerProxyAddress must be a nonzero address");
        }
    });

    it("reports expected and actual implementation without an activation flag", async function () {
        const actual = await proxy.getImplementation();
        expect(actual).not.to.equal(manager.address);
        const messages = [];
        const originalLog = console.log;
        console.log = message => messages.push(message);
        try {
            // Candidate build/bindings pass; only the unchanged proxy implementation mismatches.
            await expect(audit(globals, "ServiceManager", managerArtifact))
                .to.be.rejectedWith("AUDIT FAILED: 1 checks: proxy implementation");
        } finally {
            console.log = originalLog;
        }
        expect(messages).to.include("Expected implementation: " + manager.address);
        expect(messages).to.include("Actual implementation: " + actual);
    });

    it("passes the same manager audit after the proxy switches", async function () {
        await manager.attach(proxy.address).changeImplementation(manager.address);
        await audit(globals, "ServiceManager", managerArtifact);
    });

    it("accepts correct wrapper code and constructor bindings without whitelisting it", async function () {
        await audit(globals, "GnosisSafeMultisig", wrapperArtifact);
    });

    it("rejects wrong constructor bindings on either candidate", async function () {
        await expect(audit({ ...globals, serviceRegistryAddress: globals.gnosisSafeAddress },
            "ServiceManager", managerArtifact)).to.be.rejectedWith("runtime hash");
        await expect(audit({ ...globals, gnosisSafeProxyFactoryAddress: globals.gnosisSafeAddress },
            "GnosisSafeMultisig", wrapperArtifact)).to.be.rejectedWith("runtime hash");
    });

    it("rejects a same-length executable-byte change with unchanged metadata", async function () {
        const code = await ethers.provider.getCode(wrapper.address);
        const changed = (code.slice(2, 4) === "00" ? "01" : "00");
        await network.provider.send("hardhat_setCode", [wrapper.address, "0x" + changed + code.slice(4)]);
        await expect(audit(globals, "GnosisSafeMultisig", wrapperArtifact)).to.be.rejectedWith("runtime hash");
    });

    it("rejects an address with no code and a mismatching chain", async function () {
        await expect(audit({ ...globals, gnosisSafeMultisigImplementationAddress: globals.gnosisSafeAddress },
            "GnosisSafeMultisig", wrapperArtifact)).to.be.rejectedWith("runtime hash");
        await expect(audit({ ...globals, chainId: 1 }, "ServiceManager", managerArtifact)).to.be.rejectedWith("chainId");
    });

    it("requires the wrapper grant and previous-wrapper revoke after activation", async function () {
        const registry = await ethers.getContractAt("ServiceRegistryL2", globals.serviceRegistryAddress);
        await expect(audit(globals, "GnosisSafeMultisig", wrapperArtifact, true))
            .to.be.rejectedWith("--previous-wrapper");
        await expect(audit(globals, "GnosisSafeMultisig", wrapperArtifact, true, globals.previousWrapper))
            .to.be.rejectedWith("new wrapper permission");
        await registry.changeMultisigPermission(wrapper.address, true);
        await registry.changeMultisigPermission(globals.previousWrapper, true);
        await expect(audit(globals, "GnosisSafeMultisig", wrapperArtifact, true, globals.previousWrapper))
            .to.be.rejectedWith("previous wrapper permission");
        await registry.changeMultisigPermission(globals.previousWrapper, false);
        await audit(globals, "GnosisSafeMultisig", wrapperArtifact, true, globals.previousWrapper);
    });

    it("reports all mismatches with expected/observed values before rejecting", async function () {
        const registry = await ethers.getContractAt("ServiceRegistryL2", globals.serviceRegistryAddress);
        await registry.changeMultisigPermission(globals.previousWrapper, true);
        const messages = [];
        const originalError = console.error;
        console.error = message => messages.push(message);
        try {
            await expect(audit({ ...globals, gnosisSafeAddress: globals.serviceRegistryTokenUtilityAddress,
                gnosisSafeProxyFactoryAddress: globals.serviceRegistryTokenUtilityAddress },
            "GnosisSafeMultisig", wrapperArtifact, true, globals.previousWrapper))
                .to.be.rejectedWith("AUDIT FAILED: 5 checks");
        } finally {
            console.error = originalError;
        }
        expect(messages).to.have.length(5);
        for (const label of ["runtime hash", "gnosisSafe()", "gnosisSafeProxyFactory()",
            "new wrapper permission", "previous wrapper permission"]) {
            expect(messages.some(message => message.includes(label) && message.includes("expected=")
                && message.includes("observed="))).to.equal(true);
        }
    });

    it("continues to permission checks when candidate getters cannot be read", async function () {
        await network.provider.send("hardhat_setCode", [wrapper.address, "0x"]);
        const registry = await ethers.getContractAt("ServiceRegistryL2", globals.serviceRegistryAddress);
        await registry.changeMultisigPermission(globals.previousWrapper, true);
        await expect(audit(globals, "GnosisSafeMultisig", wrapperArtifact, true, globals.previousWrapper))
            .to.be.rejectedWith("AUDIT FAILED: 5 checks: runtime hash, gnosisSafe(), gnosisSafeProxyFactory(), new wrapper permission, previous wrapper permission");
    });

    it("audits an uninitialized StakingToken implementation without programme bindings", async function () {
        const staking = await (await ethers.getContractFactory("StakingToken")).deploy();
        const artifact = await artifacts.readArtifact("StakingToken");
        await audit({ chainId: globals.chainId, stakingTokenAddress: staking.address }, "StakingToken", artifact);
    });

    it("rejects StakingNativeToken even though it reports the same version", async function () {
        const staking = await (await ethers.getContractFactory("StakingNativeToken")).deploy();
        expect(await staking.VERSION()).to.equal("0.4.0");
        await expect(audit({ chainId: globals.chainId, stakingTokenAddress: staking.address }, "StakingToken",
            await artifacts.readArtifact("StakingToken"))).to.be.rejectedWith("runtime hash");
    });

    it("reports both code and VERSION mismatches for StakingToken", async function () {
        await expect(audit({ chainId: globals.chainId, stakingTokenAddress: manager.address }, "StakingToken",
            await artifacts.readArtifact("StakingToken"))).to.be.rejectedWith("AUDIT FAILED: 2 checks: runtime hash, VERSION()");
    });

    it("accepts the Forge artifact bytecode shape", async function () {
        await audit(globals, "GnosisSafeMultisig", { ...wrapperArtifact, bytecode: { object: wrapperArtifact.bytecode } });
    });
});

// Exercise verification completion/failure without sending deployment or explorer requests.
describe("Deployment explorer verification", function () {
    const fs = require("fs");
    const os = require("os");
    const path = require("path");
    const { spawnSync } = require("child_process");
    for (const script of ["scripts/deployment/deploy_07_service_manager.sh",
        "scripts/deployment/l2/deploy_04_service_manager.sh", "scripts/deployment/l2/deploy_06a_gnosis_safe_multisig.sh",
        "scripts/deployment/l2/deploy_16_service_staking_token.sh"]) {
        it(script + " waits for verification and propagates either explorer failure", function () {
            const dir = fs.mkdtempSync(path.join(os.tmpdir(), "registry-verification-"));
            try {
                const address = "0x0000000000000000000000000000000000000001";
                fs.copyFileSync(path.join(__dirname, "..", script), path.join(dir, "deploy.sh"));
                fs.writeFileSync(path.join(dir, "cast"), "#!/bin/bash\necho " + address + "\n", { mode: 0o755 });
                fs.writeFileSync(path.join(dir, "forge"), `#!/bin/bash
if [ "$1" = "create" ]; then
  echo "Deployed to: ${address}"
  exit 0
fi
case " $* " in *" --watch "*) ;; *) exit 9 ;; esac
if [[ "$*" == *"--verifier blockscout"* ]]; then
  exit "\${BLOCKSCOUT_STATUS:-0}"
fi
exit "\${ETHERSCAN_STATUS:-0}"
`, { mode: 0o755 });
                for (const [etherscanStatus, blockscoutStatus] of [[0, 0], [1, 0], [0, 1]]) {
                    fs.writeFileSync(path.join(dir, "globals_test.json"), JSON.stringify({
                        contractVerification: true, useLedger: true, chainId: 31337,
                        derivationPath: "test", networkURL: "http://localhost:8545",
                        blockscoutURL: "https://example.invalid", serviceRegistryAddress: address,
                        serviceRegistryTokenUtilityAddress: address, gnosisSafeAddress: address,
                        gnosisSafeProxyFactoryAddress: address
                    }));
                    const result = spawnSync("bash", [path.join(dir, "deploy.sh"), "test"], {
                        encoding: "utf8", env: { ...process.env, PATH: dir + path.delimiter + process.env.PATH,
                            ETHERSCAN_STATUS: String(etherscanStatus), BLOCKSCOUT_STATUS: String(blockscoutStatus) }
                    });
                    expect(result.status, result.stdout + result.stderr).to.equal(etherscanStatus || blockscoutStatus);
                }
            } finally {
                fs.rmSync(dir, { recursive: true, force: true });
            }
        });
    }
});
