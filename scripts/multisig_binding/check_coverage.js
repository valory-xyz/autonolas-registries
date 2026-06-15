#!/usr/bin/env node
/*global process*/
/*
 Read-only bindMultisig coverage check for proposal 11. For each chain: read every service's multisig
 (mapServices 1..totalSupply via Multicall3) and confirm it's claimed in mapMultisigServiceIds. A service is
 "covered" if its multisig == 0 (nothing to bind) OR mapMultisigServiceIds[multisig] != 0 (claimed). Reports
 any still-unbound serviceIds per chain. No sends. Run: NODE_PATH=.../node_modules node check_coverage.js [chain]
*/
const { ethers } = require("ethers");
const MULTICALL3 = "0xcA11bde05977b3631167028862bE2a173976CA11";

const CHAINS = {
    ethereum: { proxy: "0x94a1892D91c05D0C61c3f49F42205D2285b914c9", rpcs: ["https://eth.llamarpc.com", "https://ethereum-rpc.publicnode.com", "https://eth.drpc.org", "https://1rpc.io/eth"] },
    gnosis:   { proxy: "0x068a4f0946cF8c7f9C1B58a3b5243Ac8843bf473", rpcs: ["https://rpc.gnosischain.com", "https://gnosis-rpc.publicnode.com", "https://gnosis.drpc.org"] },
    optimism: { proxy: "0xA5C7FbCCFf28441b7d250412b0Fb87AA1c8b14AD", rpcs: ["https://optimism.drpc.org", "https://optimism-rpc.publicnode.com", "https://mainnet.optimism.io"] },
    polygon:  { proxy: "0xE3e5Df46060370af5Fd37B2aA11e7dac3cCB4bd0", rpcs: ["https://polygon.drpc.org", "https://polygon-bor-rpc.publicnode.com", "https://1rpc.io/matic"] },
    base:     { proxy: "0x1262136cac6a06A782DC94eb3a3dF0b4d09FF6A6", rpcs: ["https://mainnet.base.org", "https://base.drpc.org", "https://base-rpc.publicnode.com"] },
    arbitrum: { proxy: "0xD421f433e36465B3e558B1121F584ac09Fc33DF8", rpcs: ["https://arb1.arbitrum.io/rpc", "https://arbitrum-one-rpc.publicnode.com", "https://arbitrum.drpc.org"] },
    celo:     { proxy: "0x84B4DA67B37B1EA1dea9c7044042C1d2297b80a0", rpcs: ["https://forno.celo.org", "https://celo.drpc.org", "https://1rpc.io/celo"] },
    mode:     { proxy: "0xcDdD9D9ABaB36fFa882530D69c73FeE5D4001C2d", rpcs: ["https://mainnet.mode.network", "https://mode.drpc.org"] },
};
const ORDER = ["ethereum", "gnosis", "optimism", "polygon", "base", "arbitrum", "celo", "mode"];

const SM = new ethers.utils.Interface(["function mapMultisigServiceIds(address) view returns (uint256)", "function serviceRegistry() view returns (address)"]);
const REG = new ethers.utils.Interface(["function mapServices(uint256) view returns (uint96,address,bytes32,uint32,uint32,uint32,uint8)", "function totalSupply() view returns (uint256)"]);
const MC = new ethers.utils.Interface(["function aggregate3((address target,bool allowFailure,bytes callData)[]) view returns ((bool success,bytes returnData)[])"]);

async function connect(chain) {
    for (const url of CHAINS[chain].rpcs) {
        try { const p = new ethers.providers.JsonRpcProvider(url); await p.getBlockNumber(); return p; }
        catch (e) { /* next */ }
    }
    throw new Error("no RPC for " + chain);
}

// Multicall3 aggregate3 in chunks; returns array of returnData (or null on per-call failure).
async function multicall(provider, calls, chunk = 600) {
    const out = [];
    for (let i = 0; i < calls.length; i += chunk) {
        const slice = calls.slice(i, i + chunk);
        const data = MC.encodeFunctionData("aggregate3", [slice.map((c) => [c.target, true, c.data])]);
        const ret = await provider.call({ to: MULTICALL3, data });
        const [res] = MC.decodeFunctionResult("aggregate3", ret);
        for (const r of res) out.push(r.success ? r.returnData : null);
    }
    return out;
}

async function checkChain(chain) {
    const provider = await connect(chain);
    const proxy = CHAINS[chain].proxy;
    const registry = SM.decodeFunctionResult("serviceRegistry", await provider.call({ to: proxy, data: SM.encodeFunctionData("serviceRegistry", []) }))[0];
    const ts = REG.decodeFunctionResult("totalSupply", await provider.call({ to: registry, data: REG.encodeFunctionData("totalSupply", []) }))[0].toNumber();

    // 1) every service's multisig
    const idCalls = []; for (let i = 1; i <= ts; i++) idCalls.push({ target: registry, data: REG.encodeFunctionData("mapServices", [i]) });
    const svc = await multicall(provider, idCalls);
    const ids = [], multisigs = [];
    for (let k = 0; k < svc.length; k++) {
        const id = k + 1;
        let ms = ethers.constants.AddressZero;
        if (svc[k]) { try { ms = REG.decodeFunctionResult("mapServices", svc[k])[1]; } catch (e) { ms = null; } }
        ids.push(id); multisigs.push(ms);
    }
    // 2) for non-zero multisigs, is it claimed?
    const withMs = ids.filter((id, k) => multisigs[k] && multisigs[k] !== ethers.constants.AddressZero);
    const claimCalls = withMs.map((id) => ({ target: proxy, data: SM.encodeFunctionData("mapMultisigServiceIds", [multisigs[ids.indexOf(id)]]) }));
    const claims = await multicall(provider, claimCalls);
    const unbound = [];
    for (let k = 0; k < withMs.length; k++) {
        let bound = false;
        if (claims[k]) { try { bound = !SM.decodeFunctionResult("mapMultisigServiceIds", claims[k])[0].isZero(); } catch (e) { bound = false; } }
        if (!bound) unbound.push(withMs[k]);
    }
    const rpcFail = svc.filter((s) => s === null).length + claims.filter((c) => c === null).length;
    return { ts, withMs: withMs.length, noMs: ts - withMs.length, unbound, rpcFail };
}

async function run() {
    const only = process.argv[2];
    const chains = only ? [only] : ORDER;
    const summary = [];
    for (const chain of chains) {
        process.stdout.write(`${chain}: `);
        try {
            const r = await checkChain(chain);
            const status = r.unbound.length === 0 ? "✅ fully bound" : `❌ ${r.unbound.length} UNBOUND`;
            console.log(`totalSupply ${r.ts} | with multisig ${r.withMs} | no multisig ${r.noMs} | ${status}${r.rpcFail ? `  (rpcFail ${r.rpcFail})` : ""}`);
            if (r.unbound.length) console.log(`    unbound serviceIds: ${r.unbound.slice(0, 60).join(", ")}${r.unbound.length > 60 ? " …" : ""}`);
            summary.push(`${chain}=${r.unbound.length === 0 ? "OK" : r.unbound.length + " unbound"}`);
        } catch (e) { console.log("ERROR", e.message); summary.push(`${chain}=ERR`); }
    }
    console.log("\nSUMMARY: " + summary.join("  "));
}

run().catch((e) => { console.error(e.message || e); process.exit(1); });
