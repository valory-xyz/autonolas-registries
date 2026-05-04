# CLOB v2 Migration — Impact on Olas Subgraphs

**Date:** 2026-05-04
**Companion to:**
- [`clob_v2_impact_polySafeCreator.md`](./clob_v2_impact_polySafeCreator.md) — impact on the existing PolySafe creator (Safe-creation layer is unaffected by CLOB v2 itself).
- [`clob_v2_deposit_wallet_creator_plan.md`](./clob_v2_deposit_wallet_creator_plan.md) — the new deposit-wallet creator plan whose Reading-B path is the source of the subgraph breakage analysed here.

**Scope:** Two consumer subgraphs of the OLAS service-registry chain state.
- [`predict-polymarket`](https://github.com/valory-xyz/autonolas-subgraph/tree/main/subgraphs/predict-polymarket) (per-agent CLOB activity, profit, payouts).
- [`service-registry`](https://github.com/valory-xyz/autonolas-subgraph-studio/tree/main/subgraphs/service-registry) DAA dashboard (cross-chain Daily Active Agent metrics).

## TL;DR

- Under CLOB v1 / today's PolySafe model the OLAS service multisig is also the CLOB trading wallet **and** the on-chain redeemer **and** the Safe that emits `ExecutionSuccess` per trade. Both subgraphs key everything off that single address.
- Under the CLOB v2 deposit-wallet model (Reading B in `CLOB_V2_FOLLOWUPS.md`, design corrected on 2026-05-04 in [`clob_v2_deposit_wallet_creator_plan.md` §"Probe results — 2026-05-04 — major design correction"](./clob_v2_deposit_wallet_creator_plan.md)), the trading wallet is a **separate per-service `DepositWallet`** owned by the agent-instance EOA. The Safe and the DepositWallet are independent peers; trades flow relayer → `DepositWallet.execute`, never through the Safe.
- **Predict-polymarket silently drops every new-model trade and redemption** because `OrderFilled.maker` and `PositionsRedeemed.initiator` become the DepositWallet, which is not registered as a `TraderAgent`.
- **DAA `txCount` for predict services collapses** because the Safe no longer emits `ExecutionSuccess` per trade.
- Both subgraphs need migration. The cleanest fix depends on the new creator landing the on-chain Safe↔DepositWallet link (Design C / `DepositWalletLinked` event) sketched in the deposit-wallet plan; without it, there is no on-chain join key.
- The PolySafe creator itself is **not** part of the breakage path — see [`clob_v2_impact_polySafeCreator.md`](./clob_v2_impact_polySafeCreator.md) for why the Safe layer is untouched.

## Today's tracking model — single anchor address

Both subgraphs are anchored on one load-bearing assumption: **the OLAS service multisig (PolySafe today) is the same address that signs CLOB orders, that redeems CTF payouts, and that emits Safe `ExecutionSuccess`.**

The PolySafe creator preserves this anchor across the v1 → v2 cutover (the Safe substrate is identical, see [`clob_v2_impact_polySafeCreator.md`](./clob_v2_impact_polySafeCreator.md)). The breakage analysed here only kicks in on services deployed via the **new** deposit-wallet creator under Reading B, not on existing PolySafe services.

### `predict-polymarket` — anchor is `service.multisig`

Anchor lifecycle (file:line):

- [`src/service-registry-l-2.ts:33`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/src/service-registry-l-2.ts#L33) creates the `TraderAgent` entity with `id = event.params.multisig` from `ServiceRegistryL2.CreateMultisigWithAgents`.
- [`src/ctf-exchange-v2.ts:8`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/src/ctf-exchange-v2.ts#L8) resolves CLOB v2 trades via `TraderAgent.load(event.params.maker)` — relies on `OrderFilled.maker == multisig`.
- [`src/ctf-exchange.ts`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/src/ctf-exchange.ts) does the same on CLOB v1 `OrderFilled.maker` (data source capped at block 86750000 in [`subgraph.yaml:184`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/subgraph.yaml#L184)).
- [`src/collateral-adapter.ts:14`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/src/collateral-adapter.ts#L14) + [`processRedemption`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/src/utils.ts) in `src/utils.ts` resolves redemptions via `TraderAgent.load(event.params.initiator)` — relies on `PositionsRedeemed.initiator == multisig`.
- All downstream entities — `Bet`, `MarketParticipant.outcomeShares0/1`, `DailyProfitStatistic.totalTraded/totalPayout/dailyProfit`, `Global.totalBets/totalTraded/totalPayout` — derive from those two anchor lookups (`maker` for trades, `initiator` for redemptions).

This works today because PolySafe-signed CLOB orders use `sigType=2` (`POLY_GNOSIS_SAFE`) where `order.maker == Safe`, and the Pearl trader redemption path lands the `PositionsRedeemed.initiator` on the Safe ([`subgraph.yaml:291-303`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/subgraph.yaml#L291-L303) notes this explicitly).

### `service-registry` (DAA) — anchor is the Safe emitting `ExecutionSuccess`

Anchor lifecycle (file:line):

- [`src/mapping.ts:163`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/src/mapping.ts#L163) `GnosisSafeTemplate.create(event.params.multisig)` instantiates a per-Safe template at `CreateMultisigWithAgents` time.
- [`subgraph.matic.yaml:68-97`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/subgraph.matic.yaml#L68-L97) declares the `GnosisSafe` template with `ExecutionSuccess` and `ExecutionFromModuleSuccess` event handlers.
- [`src/mapping.ts:200`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/src/mapping.ts#L200) and [`src/mapping.ts:219`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/src/mapping.ts#L219) listen for those events on every Safe and call `updateDailyAgentPerformance`, which increments `DailyAgentPerformance.txCount` and links a `DailyAgentMultisig` row.
- [`schema.graphql:68-81`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/schema.graphql#L68-L81) defines `DailyAgentPerformance` (`txCount`, `activeMultisigCount`) and `DailyAgentMultisig` (per-day Safe membership for an agent).

For predict services this means: every CLOB order today ⇒ one `Safe.execTransaction` ⇒ one `ExecutionSuccess` ⇒ one DAA tx tick. That linkage is the entire DAA signal for predict.

## What the deposit-wallet model changes

Per the corrected design in [`clob_v2_deposit_wallet_creator_plan.md` §"Corrected design — Safe + DepositWallet as independent peers"](./clob_v2_deposit_wallet_creator_plan.md) the topology becomes:

```
                ServiceSafe                        DepositWallet
       (OLAS service multisig)                  (Polymarket trading)
                    │                                  ▲
                    │ owners[] include                 │ owner field =
                    │ agentInstance                    │ agentInstance
                    └──────────────┬───────────────────┘
                                   ▼
                       agent-instance EOA
                          (sole bridge)
```

Three load-bearing facts surfaced by the 2026-05-04 source probe:

1. `DepositWalletFactory.deploy()` is `onlyOperator`-gated. Polymarket's hosted relayer is the only deployer.
2. The DepositWallet's `_erc1271IsValidSignatureNowCalldata` is hard-coded ECDSA against its `owner` slot — the owner **must** be an EOA (the agent instance), not the Safe.
3. `DepositWallet.execute()` is `onlyFactory`-gated. All batch ops (session-signer authorization, approvals, withdrawals) flow relayer → `factory.proxy()` → `wallet.execute()`. The Safe is never on the call path for trades.

Per plan §"deposit wallet stack" item 3: **CLOB v2 orders carry `maker == signer == DepositWallet`.** This is the key behavioural change that breaks both subgraphs.

What gets recorded where:
- `service.multisig` = the Safe (unchanged from existing flow). `ServiceRegistryL2.CreateMultisigWithAgents.multisig` still points at the Safe.
- `IdentityRegistryBridger.setAgentWallet(agentId, multisig)` = the Safe.
- `DepositWallet` = a separate address. Discoverable on-chain only if the new creator lands the `DepositWalletLinked(safe, depositWallet)` event + `mapMultisigDepositWallets[safe] = depositWallet` mapping (Design C in the plan §"Recommended design").

## Impact on `predict-polymarket`

| Anchor | Today | Under deposit-wallet model | Effect |
|---|---|---|---|
| `OrderFilled.maker` ([`src/ctf-exchange-v2.ts:8`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/src/ctf-exchange-v2.ts#L8)) | `= Safe` (= `TraderAgent.id`) | `= DepositWallet`, never registered as a `TraderAgent` | `TraderAgent.load(maker)` returns null → handler early-returns at line 9 → **every new-model trade silently dropped**. `Bet`, `DailyProfitStatistic.totalBets/totalTraded`, `MarketParticipant`, `Global.totalBets/totalTraded` all stop incrementing for migrated services. |
| `PositionsRedeemed.initiator` ([`src/collateral-adapter.ts:14`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/src/collateral-adapter.ts#L14)) | `= Safe` | `= DepositWallet` if the trader migrates the redemption path; possibly `= Safe` if it stays | If DW: `TraderAgent.load(initiator)` null → `totalPayout`, `DailyProfitStatistic.totalPayout`, `Global.totalPayout` stop incrementing. |
| `MarketParticipant.outcomeShares0/1` (populated in [`processTradeActivity`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/src/utils.ts)) | accumulated per fill | not accumulated (fills dropped above) | At resolution, `processMarketResolution` reads zero balances → `expectedPayout = 0` → `dailyProfit = 0 − 0 = 0`. Profit dashboards flatline for migrated services. |
| `TraderAgent` row creation ([`src/service-registry-l-2.ts:31`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/src/service-registry-l-2.ts#L31)) | unchanged — Safe is still the registered multisig | unchanged | Entity exists but accumulates nothing — looks like a dead service. |

**Net:** post-migration predict services produce empty `TraderAgent` rows. The on-chain Safe↔DW link recommended in the deposit-wallet plan §"Design C" is exactly the bridge the subgraph needs; without it there's no on-chain way to join `OrderFilled.maker` (DepositWallet) back to the `TraderAgent` (keyed on Safe).

### Migration sketch

Assumes the new creator ships the Design-C link event (treat as a hard prerequisite — without it, the subgraph cannot bridge the two addresses without trusting off-chain config):

1. Add a dataSource for the new creator contract, listening for `DepositWalletLinked(multisig, depositWallet)` (the exact name/sig will come from the creator implementation — see plan §"Contract surface").
2. Add a reverse-lookup entity, e.g.
   ```graphql
   type DepositWalletLink @entity(immutable: true) {
     id: Bytes!            # depositWallet address
     traderAgent: TraderAgent!  # keyed by the Safe
   }
   ```
3. In `handleOrderFilledV2` ([`src/ctf-exchange-v2.ts:8`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/src/ctf-exchange-v2.ts#L8)) replace
   ```ts
   let agent = TraderAgent.load(event.params.maker);
   ```
   with a two-step lookup: first try the link entity; fall back to direct load for legacy PolySafe services that pre-date migration.
4. Same fallback in v1 `handleOrderFilled` ([`src/ctf-exchange.ts`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/src/ctf-exchange.ts)) if v1 markets persist past cutover (currently bounded by [`subgraph.yaml:184`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/subgraph.yaml#L184) `endBlock: 86750000`).
5. Same fallback in `handlePositionsRedeemed` ([`src/collateral-adapter.ts:14`](https://github.com/valory-xyz/autonolas-subgraph/blob/main/subgraphs/predict-polymarket/src/collateral-adapter.ts#L14)) — applies only if the Pearl trader moves redemption to the DepositWallet.
6. Decide between two keying strategies for `TraderAgent.id`:
   - **Keep Safe-keyed (recommended).** Preserves continuity with existing rows and the join key shared with the `service-registry` DAA subgraph. Add the link entity for resolution.
   - **Re-key on DepositWallet.** Cleaner for v2-only consumers but breaks back-compat and breaks the cross-subgraph join with the service-registry DAA dataset.

## Impact on `service-registry` DAAs

| Anchor | Today | Under deposit-wallet model | Effect |
|---|---|---|---|
| `Safe.ExecutionSuccess` per CLOB order ([`src/mapping.ts:200`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/src/mapping.ts#L200)) | one per trade (sigType=2 Safe-signed order ⇒ one `execTransaction`) | **zero** — orders go relayer → `DepositWallet.execute` (`onlyFactory`-gated, Safe never called) | `DailyAgentPerformance.txCount` for predict services drops to ~0 from its current trade-driven cadence. |
| `Safe.ExecutionSuccess` for Safe maintenance | rare today (occasional approvals, recovery) | rare (deploy bootstrap, periodic session-signer rotation, withdrawals, recovery — see plan §"Session-signer escape hatch") | Some residual ticks but orders of magnitude lower than today. |
| `DailyAgentMultisig` linkage ([`src/mapping.ts:65`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/src/mapping.ts#L65) / [`src/utils.ts:200`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/src/utils.ts#L200)) | populated each tx day | populated only on the rare days the Safe actually executes | `activeMultisigCount` undercounts predict agents post-migration. |
| `DailyActiveMultisigs.count` ([`src/mapping.ts:96`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/src/mapping.ts#L96)) | counts Safes with any `ExecutionSuccess` that day | drops similarly | System-wide "active multisigs today" view loses predict services almost entirely. |
| `Global.txCount` ([`src/mapping.ts:104`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/src/mapping.ts#L104)) | incremented per `ExecutionSuccess` | drops | Top-line activity counter understates real agent activity. |

This is a structural regression in the cross-chain DAA dashboard — predict agents will look idle even when actively trading. **`DailyAgentPerformance` becomes structurally undercounted for any predict service that migrates to the deposit-wallet creator.**

### Migration sketch

The DAA subgraph is generic across all services (not predict-specific), so the fix needs to be expressed in those terms:

1. Add a `DepositWallet` template in [`subgraph.matic.yaml`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/subgraph.matic.yaml) (alongside the existing `GnosisSafe` template at [`subgraph.matic.yaml:68-97`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/subgraph.matic.yaml#L68-L97)), with a handler for the DepositWallet's batch-execution event. The exact event signature needs a probe of the DW source at `0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB` — the plan flags this as one of the load-bearing unknowns (plan §"What's assumed vs confirmed at each step").
2. Instantiate the template when the new creator emits `DepositWalletLinked(multisig, depositWallet)` (same event the predict subgraph consumes).
3. In the new handler, resolve the bound `Multisig` via the link entity, then call the existing `updateDailyAgentPerformance` / `updateDailyActiveMultisigs` / `updateGlobalMetrics` paths ([`src/mapping.ts:41`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/src/mapping.ts#L41), [`:96`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/src/mapping.ts#L96), [`:104`](https://github.com/valory-xyz/autonolas-subgraph-studio/blob/main/subgraphs/service-registry/src/mapping.ts#L104)) so a DepositWallet execution counts as a tx for the bound Safe's agents. This preserves the existing `DailyAgentPerformance` semantics — one execution = one tick — without forking the schema.
4. Decide whether session-signer-signed CLOB orders (the ergonomics path described in plan §"Session-signer escape hatch") should count as DAA ticks. Those orders never touch on-chain via Safe or DW `execute` — they're signed off-chain and matched on `CTFExchangeV2`. The only on-chain signal is `OrderFilled` on the exchange itself. To capture them, the DAA subgraph would need to index `CTFExchangeV2.OrderFilled` directly (overlapping the predict-polymarket subgraph but the only way to recover trade-as-activity under sigType=3). **Recommendation:** treat this as a separate decision; ship steps 1-3 first, since they fix the relayer-batch path (deploy bootstrap, session-signer rotation, withdrawals) which is structurally similar to today's on-chain ticks.

## Open questions for both subgraphs

1. **Will the new creator land Design C** (`DepositWalletLinked` event + `mapMultisigDepositWallets` mapping)? If not, both subgraphs lose their on-chain join key and have to fall back to off-chain config — operationally fragile for indexers. Plan §"Recommended design" recommends Design C precisely because of this; flagged as a hard prerequisite for clean indexing.
2. **What does the DepositWallet's batch-execution event look like?** Needed to instantiate the DW template in the DAA subgraph. Probe target: `0x58CA52ebe0DadfdF531Cde7062e76746de4Db1eB` on Polygon.
3. **Will the Pearl trader migrate the redemption path to the DepositWallet?** Determines whether `predict-polymarket` needs the redemption-handler change (step 5 above) or only the trade-handler change.
4. **Reading A vs Reading B settlement.** If Reading A wins (existing PolySafe path keeps working for new accounts), no subgraph changes needed at all. The migration here is conditional on the same Reading-B trigger that gates the new creator itself — see plan §"Trigger".
