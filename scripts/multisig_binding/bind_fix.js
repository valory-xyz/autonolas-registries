#!/usr/bin/env node
/*global process*/
/*
 81064 remediation — ServiceManagerProxy.bindMultisig(serviceIds[]) backfill.

 Self-contained: run AFTER the DAO vote points each ServiceManagerProxy at the fixed ServiceManager
 implementation. bindMultisig records mapMultisigServiceIds[multisig]=serviceId (permissionless + idempotent),
 so a later attacker deploy() that tries to bind one of these Safes reverts MultisigAlreadyBound.

 Per chain it:
   1. Confirms the proxy is on the FIXED impl (compares the PROXY_SERVICE_MANAGER impl slot to the expected
      impl). Skips the chain with a warning only if the upgrade hasn't propagated yet (Mode was upgraded by a
      separate manual script rather than the DAO vote, but it's already on the fixed impl, so it's included).
   2. Gnosis only: binds the 205 immediately-drainable serviceIds FIRST (one tx) — the highest $ exposure.
   3. Binds the FULL range serviceId 1..totalSupply() (read LIVE) as backfill. bindMultisig skips
      multisig==0 (undeployed) and already-bound, so reactivated / zero-balance / new services are all covered
      and re-running is safe. Auto-split into the minimum batches under ~90% of the block gas limit.

 The fixed impl exposes serviceRegistry() (an immutable), so the registry is read from the proxy — nothing to
 hardcode but the proxy + expected impl per chain.

 Usage:
   node bind_fix.js <plan|fork|execute> <chain|all> [--chainId N]
     plan     — connect (live, or FORK_URL/RPC_URL), print the batch plan. No send.
     fork     — FORK test: needs anvil at FORK_URL; upgrades the impl via anvil_setStorageAt, binds, verifies, reports gas.
     execute  — REAL send. Signs with PRIVATE_KEY env if set, otherwise a Ledger (one confirmation per batch).
                Batched, idempotent, verified.
   <chain>: ethereum|gnosis|polygon|arbitrum|optimism|base|celo|mode | all | a numeric chainId.
   Each chain has fallback RPCs (first responsive is used); override with RPC_URL=...
   Signer: PRIVATE_KEY=0x... (env) takes precedence; else Ledger at m/44'/60'/2'/0/0 (override DERIVATION_PATH=...).
*/
const { ethers } = require("ethers");
// @anders-t/ethers-ledger is require()d lazily inside execute (so plan/fork don't need the Ledger lib installed).

// execute signs on a Ledger (no PRIVATE_KEY). Default path matches deployment globals_*.json; override with DERIVATION_PATH.
const DERIVATION_PATH = process.env.DERIVATION_PATH || "m/44'/60'/2'/0/0";
const IMPL_SLOT = "0xe39e69948a448ce9239ad71b908b6c5b46225f86ffa735b25a8cd64080315855"; // keccak256("PROXY_SERVICE_MANAGER")
const SM_ABI  = ["function bindMultisig(uint256[] serviceIds) external",
    "function mapMultisigServiceIds(address) view returns (uint256)",
    "function serviceRegistry() view returns (address)"];
const REG_ABI = ["function mapServices(uint256) view returns (uint96,address,bytes32,uint32,uint32,uint32,uint8)",
    "function totalSupply() view returns (uint256)"];
const ANVIL_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"; // gitleaks:allow - well-known public anvil/hardhat account[0] test key; fork mode only, never a real secret

// Gnosis immediately-drainable serviceIds (PreReg/ActiveReg + RecoveryModule + funded; live snapshot 2026-06-15,
// ~$11.1k). Bound FIRST in one tx so the highest-$ exposure is protected before the full-range backfill.
const GNOSIS_DRAINABLE = [
    614, 704, 995, 996, 997, 998, 999, 1000, 1001, 1002, 1003, 1004, 1005, 1006, 1012,
    1013, 1027, 1028, 1029, 1031, 1032, 1033, 1034, 1035, 1036, 1037, 1038, 1039, 1040, 1041,
    1042, 1043, 1044, 1046, 1081, 1082, 1083, 1098, 1099, 1100, 1101, 1102, 1103, 1104, 1109,
    1110, 1117, 1146, 1147, 1148, 1189, 1190, 1191, 1192, 1193, 1194, 1195, 1196, 1197, 1198,
    1199, 1200, 1201, 1202, 1220, 1235, 1236, 1251, 1253, 1254, 1255, 1259, 1263, 1264, 1265,
    1266, 1267, 1268, 1269, 1285, 1286, 1293, 1295, 1308, 1323, 1351, 1434, 1437, 1438, 1440,
    1441, 1442, 1445, 1448, 1449, 1452, 1453, 1454, 1455, 1456, 1461, 1466, 1467, 1471, 1472,
    1473, 1475, 1477, 1479, 1480, 1481, 1482, 1483, 1484, 1486, 1487, 1490, 1492, 1494, 1495,
    1496, 1498, 1500, 1501, 1502, 1503, 1504, 1505, 1506, 1508, 1509, 1510, 1511, 1513, 1514,
    1515, 1516, 1517, 1518, 1519, 1520, 1521, 1522, 1523, 1524, 1527, 1528, 1529, 1531, 1532,
    1533, 1534, 1535, 1551, 1552, 1567, 1592, 1593, 1679, 1699, 1840, 1858, 1859, 1860, 1866,
    1879, 1882, 1883, 1884, 1889, 1890, 1892, 1895, 1898, 1912, 1926, 1951, 2038, 2040, 2043,
    2045, 2048, 2051, 2052, 2053, 2056, 2059, 2060, 2070, 2075, 2077, 2080, 2081, 2118, 2127,
    2219, 2269, 2436, 2602, 2686, 2914, 2916, 2925, 3093, 3170,
];

// proxy + expected fixed impl per chain (proposal_11_sm_update §G; Mode via the separate manual script).
// inProposal is informational only — a chain is processed iff its proxy is already on the fixed impl.
const CHAINS = {
    gnosis:   { chainId: 100,   inProposal: true,  proxy: "0x068a4f0946cF8c7f9C1B58a3b5243Ac8843bf473", impl: "0x2D2754EAc33C4B456e96C7438C3141735C3b60B8", priority: GNOSIS_DRAINABLE,
        rpcs: ["https://rpc.gnosischain.com", "https://gnosis-rpc.publicnode.com", "https://gnosis.drpc.org", "https://1rpc.io/gnosis"] },
    optimism: { chainId: 10,    inProposal: true,  proxy: "0xA5C7FbCCFf28441b7d250412b0Fb87AA1c8b14AD", impl: "0x43fB32f25dce34EB76c78C7A42C8F40F84BCD237",
        rpcs: ["https://optimism.drpc.org", "https://mainnet.optimism.io", "https://optimism-rpc.publicnode.com", "https://1rpc.io/op"] },
    mode:     { chainId: 34443, inProposal: true,  proxy: "0xcDdD9D9ABaB36fFa882530D69c73FeE5D4001C2d", impl: "0xaea9ef993d8a1A164397642648DF43F053d43D85",
        rpcs: ["https://mainnet.mode.network", "https://mode.drpc.org", "https://mode.gateway.tenderly.co"] },
    polygon:  { chainId: 137,   inProposal: true,  proxy: "0xE3e5Df46060370af5Fd37B2aA11e7dac3cCB4bd0", impl: "0x69E679AF02D7F18157A8730189f9aFa8cf9c9a2a",
        rpcs: ["https://polygon.drpc.org", "https://polygon-bor-rpc.publicnode.com", "https://polygon.gateway.tenderly.co", "https://1rpc.io/matic"] },
    base:     { chainId: 8453,  inProposal: true,  proxy: "0x1262136cac6a06A782DC94eb3a3dF0b4d09FF6A6", impl: "0x32B5A40B43C4eDb123c9cFa6ea97432380a38dDF",
        rpcs: ["https://mainnet.base.org", "https://base.drpc.org", "https://base-rpc.publicnode.com", "https://1rpc.io/base"] },
    arbitrum: { chainId: 42161, inProposal: true,  proxy: "0xD421f433e36465B3e558B1121F584ac09Fc33DF8", impl: "0x7fc0ddf4DFB61CfA5519db2A5eE7B2Eb02De0140",
        rpcs: ["https://arb1.arbitrum.io/rpc", "https://arbitrum-one-rpc.publicnode.com", "https://arbitrum.drpc.org", "https://1rpc.io/arb"] },
    celo:     { chainId: 42220, inProposal: true,  proxy: "0x84B4DA67B37B1EA1dea9c7044042C1d2297b80a0", impl: "0xd00Cb760Bf30183EAFE67f0E590BEeE190F35Cf3",
        rpcs: ["https://forno.celo.org", "https://celo.drpc.org", "https://1rpc.io/celo", "https://rpc.ankr.com/celo"] },
    ethereum: { chainId: 1,     inProposal: true,  proxy: "0x94a1892D91c05D0C61c3f49F42205D2285b914c9", impl: "0xA8C52f0bB977F423E31400d151F1b98181511f2e",
        rpcs: ["https://eth.llamarpc.com", "https://ethereum-rpc.publicnode.com", "https://eth.drpc.org", "https://rpc.ankr.com/eth", "https://1rpc.io/eth"] },
};
const PRIORITY = ["gnosis", "optimism", "mode", "polygon", "base", "arbitrum", "celo", "ethereum"]; // by $ at risk

function resolveChain(arg) {
    if (arg === "all") return PRIORITY;
    if (CHAINS[arg]) return [arg];
    if (/^\d+$/.test(arg || "")) {
        const k = Object.keys(CHAINS).find((c) => CHAINS[c].chainId === Number(arg));
        if (k) return [k];
    }
    throw new Error("unknown chain '" + arg + "' (use a name, a chainId, or 'all')");
}

async function connect(chain) {
    const forced = process.env.FORK_URL || process.env.RPC_URL;
    const list = forced ? [forced] : CHAINS[chain].rpcs;
    for (const url of list) {
        try { const p = new ethers.providers.JsonRpcProvider(url); await p.getBlockNumber(); console.log("  RPC:", url); return p; }
        catch (e) { console.log("  RPC down, trying next:", url); }
    }
    throw new Error("no responsive RPC for " + chain);
}

async function implInPlace(provider, C) {
    const cur = "0x" + (await provider.getStorageAt(C.proxy, IMPL_SLOT)).slice(26);
    return cur.toLowerCase() === C.impl.toLowerCase();
}

async function blockGasLimit(provider) {
    const blk = await provider.getBlock("latest");
    return blk.gasLimit.toNumber();
}

// Gas-sizing constants. SAFE_FRAC caps each batch's REAL estimated gas; the gasLimit is set above that and the
// per-batch limit must clear the EIP-150 1/64 rule: a call through the proxy only forwards 63/64 of the gas to
// the impl, so we need gasLimit*63/64 >= actual. gasLimit = est*LIMIT_MULT gives ~23% headroom over that.
const SAFE_FRAC = 0.6;     // target real batch gas <= 60% of the block limit
const LIMIT_MULT = 1.25;   // gasLimit = estimate * 1.25
const CAP_FRAC = 0.95;     // never set gasLimit above 95% of the block limit
const limitFor = (est, blk) => Math.min(Math.floor(blk * CAP_FRAC), Math.ceil(est * LIMIT_MULT));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Build { priority, rest, ts } for a chain. priority = the embedded drainable set (Gnosis only); rest =
// every other serviceId 1..totalSupply() read LIVE now (catches services minted since this list was made).
async function buildIds(chain, sm, provider) {
    const reg = new ethers.Contract(await sm.serviceRegistry(), REG_ABI, provider);
    const ts = (await reg.totalSupply()).toNumber();
    const priority = (CHAINS[chain].priority || []).filter((id) => id <= ts);
    const seen = new Set(priority); const rest = [];
    for (let i = 1; i <= ts; i++) if (!seen.has(i)) rest.push(i);
    return { priority, rest, ts };
}

// Size batches from a REAL estimateGas of the actual slice (accurate for any mix of bound/unbound — so it is
// correct on a fresh run AND on an idempotent re-run, unlike a fixed per-service sample). Shrink the slice
// until its real gas is <= SAFE_FRAC of the block limit. gas[b] is the per-batch gasLimit (1/64-aware).
const FALLBACK_N = 150; // batch size when estimateGas can't be obtained (keeps batches sane on a flaky RPC)
async function planChunk(sm, ids, blk) {
    const SAFE = Math.floor(blk * SAFE_FRAC);
    const batches = [], gas = []; let i = 0, guess = 400;
    while (i < ids.length) {
        let n = Math.min(guess, ids.length - i), est = null, rpcFails = 0;
        for (let tries = 0; tries < 12; tries++) {
            try { est = (await sm.estimateGas.bindMultisig(ids.slice(i, i + n))).toNumber(); }
            catch (e) { est = null; }
            if (est === null) {                                    // RPC hiccup (NOT a contract revert — bindMultisig can't revert)
                if (++rpcFails <= 3) { await sleep(700); continue; }            // retry same size a few times
                n = Math.min(n, FALLBACK_N); est = Math.floor(SAFE * 0.8);      // give up estimating -> safe fixed size
                break;
            }
            if (est > SAFE && n > 1) { n = Math.max(1, Math.floor(n * SAFE / est * 0.85)); continue; } // too big -> shrink proportionally
            break;
        }
        batches.push(ids.slice(i, i + n)); gas.push(limitFor(est || SAFE, blk)); i += n; guess = Math.max(FALLBACK_N, n);
    }
    return { batches, gas };
}

// priority first (its own batch(es)), then the full-range backfill.
async function planAll(sm, priority, rest, blk) {
    const pr = priority.length ? await planChunk(sm, priority, blk) : { batches: [], gas: [] };
    const re = rest.length ? await planChunk(sm, rest, blk) : { batches: [], gas: [] };
    return { batches: pr.batches.concat(re.batches), gas: pr.gas.concat(re.gas), pCount: pr.batches.length };
}

async function verify(sm, reg, ids) {
    let ok = 0; const miss = [];
    for (const id of ids) {
        const ms = (await reg.mapServices(id))[1];
        if (ms === ethers.constants.AddressZero) { ok++; continue; } // undeployed: nothing to bind
        const bound = await sm.mapMultisigServiceIds(ms);
        if (bound.toNumber() === id) ok++; else miss.push(id);
    }
    return { ok, miss };
}

// EIP-1559 fees from the NODE's suggested tip (×1.25 margin), NOT ethers v5 getFeeData which hardcodes a
// 1.5 gwei tip — far below Polygon's ~25 gwei floor, which is why sends there were rejected as SERVER_ERROR.
async function feeOverrides(provider) {
    const blk = await provider.getBlock("latest");
    let tip;
    try { tip = ethers.BigNumber.from(await provider.send("eth_maxPriorityFeePerGas", [])); }
    catch (e) { const fd = await provider.getFeeData(); tip = fd.maxPriorityFeePerGas || ethers.utils.parseUnits("2", "gwei"); }
    tip = tip.mul(125).div(100);
    if (blk.baseFeePerGas) return { maxFeePerGas: blk.baseFeePerGas.mul(2).add(tip), maxPriorityFeePerGas: tip };
    const gp = await provider.getGasPrice();
    return { gasPrice: gp.mul(125).div(100) }; // legacy (non-1559) chains
}

// Submit a batch. Distinguish two failure kinds:
//  - submission/transport error (RPC rejected, underpriced, network): retry the SAME batch a few times, then
//    abort — splitting cannot fix a transport/fee problem (this is what caused the earlier retry storm).
//  - mined-but-reverted (out-of-gas via the 1/64 rule): split in half, re-estimate, retry — recoverable.
async function sendOne(sm, ids, blk, gl, fees, label) {
    let tx;
    for (let attempt = 1; ; attempt++) {
        try { tx = await sm.bindMultisig(ids, { gasLimit: gl, ...fees }); break; }
        catch (e) {
            const msg = ((e.error && e.error.message) || e.reason || e.code || e.message || "").toString();
            if (attempt < 3) { console.log(`    ${label}: submit failed (${msg.slice(0, 80)}) — retry ${attempt}/2`); await sleep(2500); continue; }
            throw new Error(`submit failed for ${ids.length} ids after 3 tries: ${msg.slice(0, 160)}`);
        }
    }
    try {
        const rc = await tx.wait();
        if (rc.status !== 1) throw new Error("mined but reverted");
        console.log(`    ${label}: ${ids.length} ids -> OK gasUsed ${rc.gasUsed.toNumber().toLocaleString()}  ${tx.hash}`);
        return rc.gasUsed.toNumber();
    } catch (e) {
        if (ids.length <= 1) { console.log(`    ${label}: 1 id (${ids[0]}) reverted (${tx.hash}) — skipping`); return 0; }
        console.log(`    ${label}: ${ids.length} ids reverted/out-of-gas (${tx.hash}) -> splitting in half`);
        const mid = ids.length >> 1; let g = 0;
        for (const [j, half] of [ids.slice(0, mid), ids.slice(mid)].entries()) {
            let est; try { est = (await sm.estimateGas.bindMultisig(half)).toNumber(); } catch (_) { est = Math.floor(blk * SAFE_FRAC); }
            g += await sendOne(sm, half, blk, limitFor(est, blk), fees, `${label}.${j + 1}`);
        }
        return g;
    }
}

async function send(sm, batches, gas, pCount, blk, fees) {
    let totalGas = 0;
    for (let b = 0; b < batches.length; b++) {
        const tag = pCount && b < pCount ? "drainable" : "backfill";
        totalGas += await sendOne(sm, batches[b], blk, gas[b], fees, `batch ${b + 1}/${batches.length} [${tag}]`);
    }
    return totalGas;
}

async function run() {
    const argv = process.argv.slice(2);
    const mode = argv[0];
    let chainArg = argv[1];
    const ci = argv.indexOf("--chainId");
    if (ci >= 0) chainArg = String(argv[ci + 1]);
    if (!["plan", "fork", "execute"].includes(mode)) throw new Error("mode must be plan|fork|execute");
    const chains = resolveChain(chainArg);

    for (const chain of chains) {
        const C = CHAINS[chain];
        console.log(`\n===== ${chain.toUpperCase()} (chainId ${C.chainId}, ServiceManagerProxy ${C.proxy})  mode=${mode} =====`);
        const provider = await connect(chain);
        const blk = await blockGasLimit(provider);
        console.log(`  block gasLimit ${blk.toLocaleString()} -> target ~${Math.floor(blk * SAFE_FRAC).toLocaleString()} gas/batch`);

        let signer = provider;
        if (mode === "fork") {
            await provider.send("anvil_setStorageAt", [C.proxy, IMPL_SLOT, ethers.utils.hexZeroPad(C.impl, 32)]);
            if (!(await implInPlace(provider, C))) throw new Error("impl override failed");
            console.log("  proxy impl -> fixed", C.impl, "(fork override)");
            signer = new ethers.Wallet(ANVIL_KEY, provider);
            await provider.send("anvil_setBalance", [signer.address, "0x3635c9adc5dea00000"]);
        } else {
            if (!(await implInPlace(provider, C))) {
                console.log(`  ! SKIP: proxy is NOT on the fixed impl yet${C.inProposal ? " (DAO vote not propagated to this chain)" : " (NOT in the proposal — needs a separate upgrade)"}.`);
                continue;
            }
            console.log("  proxy impl -> fixed", C.impl, "(confirmed)");
            if (mode === "execute") {
                if (process.env.PRIVATE_KEY) {                              // PRIVATE_KEY (env) takes precedence over the Ledger
                    signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
                    console.log(`  PRIVATE_KEY signer -> ${signer.address}, bal ${ethers.utils.formatEther(await provider.getBalance(signer.address))}`);
                } else {
                    const { LedgerSigner } = require("@anders-t/ethers-ledger");
                    signer = new LedgerSigner(provider, DERIVATION_PATH); // confirm each batch on the device
                    console.log(`  connecting to Ledger at ${DERIVATION_PATH} — unlock it, open the Ethereum app, enable Contract data / blind signing (if it hangs here: replug the device and kill any other process using it)...`);
                    const addr = await signer.getAddress();
                    console.log(`  Ledger -> ${addr}, bal ${ethers.utils.formatEther(await provider.getBalance(addr))}`);
                }
            }
        }

        const sm = new ethers.Contract(C.proxy, SM_ABI, signer);
        const reg = new ethers.Contract(await sm.serviceRegistry(), REG_ABI, provider);
        const { priority, rest, ts } = await buildIds(chain, sm, provider);
        console.log(`  ids: ${priority.length} drainable (first) + ${rest.length} backfill = ${priority.length + rest.length} (totalSupply=${ts}, live)`);
        const { batches, gas, pCount } = await planAll(sm, priority, rest, blk);
        console.log(`  PLAN: ${batches.length} batch(es) (${pCount} drainable + ${batches.length - pCount} backfill) -> sizes [${batches.map((b) => b.length)}]`);

        if (mode === "plan") continue;

        const fees = await feeOverrides(provider);
        console.log(`  fees: maxPriorityFee ${ethers.utils.formatUnits(fees.maxPriorityFeePerGas || fees.gasPrice, "gwei")} gwei${fees.maxFeePerGas ? ", maxFee " + ethers.utils.formatUnits(fees.maxFeePerGas, "gwei") + " gwei" : " (legacy)"}`);
        const totalGas = await send(sm, batches, gas, pCount, blk, fees);
        const checkSet = priority.concat(rest.length <= 300 ? rest : []); // verify drainable always; full backfill only when small
        const v = await verify(sm, reg, checkSet);
        console.log(`  VERIFY: ${v.ok}/${checkSet.length} bound${v.miss.length ? "  MISSING " + v.miss.slice(0, 20) : ""}${rest.length > 300 ? " (drainable set; backfill confirmed by tx status)" : ""}`);
        console.log(`  ${mode === "fork" ? "RESULT" : "DONE"}: ${batches.length} batch(es), total gasUsed ${totalGas.toLocaleString()}`);
    }
}

run().catch((e) => { console.error(e.message || e); process.exit(1); });
