# Proposed Split Operating Model For Olas Polymarket Agents

Date: 2026-05-05

## Executive Summary

Polymarket's deposit wallet migration introduces a new wallet path for new API users. The documented path does not simply replace the existing Olas PolySafe with another Safe-like contract. It introduces a Polymarket deposit wallet, deployed through Polymarket's deposit wallet factory/relayer flow, as the wallet that holds trading funds and validates CLOB orders through `signatureType = 3` / `POLY_1271`.

The recommended operating model is therefore a split-wallet model:

- The Olas PolySafe remains the service treasury, control, and recovery-oriented wallet.
- The Polymarket deposit wallet becomes the Polymarket execution wallet for CLOB orders.
- The agent moves only limited pUSD from the PolySafe to the deposit wallet as needed for trading.
- CLOB API credentials, balance sync, approvals, and orders for deposit-wallet trading must be executed with the deposit-wallet owner or approved session signer and the deposit wallet as the CLOB funder/maker/signer.

This model preserves the existing Olas Safe-based operational assumptions where possible while satisfying Polymarket's new deposit wallet requirements for new API users.

## Scope And Evidence Base

This report is based on:

- Polymarket public documentation reviewed on 2026-05-05.
- `valory-xyz/trader` `origin/main` at commit `07b998da270a79671a16df54e06719c9b751c9e4`.
- Read-only inspection of `autonolas-subgraph-studio` `main` at commit `6de17638a44d9dd9fff8f90e6ea1b782d264595d`, specifically `subgraphs/predict/predict-polymarket`.

Primary sources:

- Polymarket deposit wallet migration: https://docs.polymarket.com/trading/deposit-wallet-migration
- Polymarket CLOB authentication: https://docs.polymarket.com/api-reference/authentication
- Trader CLOB initialization: https://github.com/valory-xyz/trader/blob/07b998da270a79671a16df54e06719c9b751c9e4/packages/valory/connections/polymarket_client/connection.py#L248-L256
- Trader CLOB order placement: https://github.com/valory-xyz/trader/blob/07b998da270a79671a16df54e06719c9b751c9e4/packages/valory/connections/polymarket_client/connection.py#L497-L508
- Polymarket CLOB V2 `POLY_1271` signature implementation: https://raw.githubusercontent.com/Polymarket/clob-client-v2/main/src/order-utils/exchangeOrderBuilderV2.ts
- Polymarket CLOB V2 signature type enum: https://raw.githubusercontent.com/Polymarket/clob-client-v2/main/src/order-utils/model/signatureTypeV2.ts

## Important Scope Qualification

Polymarket's public migration guide states that deposit wallets are the new path for new API users. It also states that existing proxy/Safe users are unaffected in this phase and should continue using their current proxy or Safe setup.

Therefore:

- For new API users, deposit wallet support should be treated as required.
- For existing Safe/proxy users, the documented position is to continue with the existing signature type, provided the agent is already CLOB V2-compatible.
- The public documents reviewed do not expose Polymarket's private backend rule for classifying an account as "new" or "existing".

## Proposed Split Operating Model

The proposed model separates service custody/control from Polymarket trading execution.

### 1. PolySafe As Treasury And Control Wallet

The Olas PolySafe remains the primary service wallet.

Responsibilities:

- Hold the majority of service funds.
- Submit or fund Mech-related requests where the existing Olas flow expects the service Safe.
- Execute treasury movements and recovery-oriented operations.
- Top up the Polymarket deposit wallet when trading liquidity is needed.

Rationale:

- The PolySafe is already integrated into the Olas service model.
- It provides the recovery/security assumptions currently relied on by the service.
- Keeping most funds in the PolySafe reduces exposure if the deposit-wallet owner key or session signer is compromised or lost.

### 2. Deposit Wallet As Polymarket Execution Wallet

The Polymarket deposit wallet becomes the wallet used for Polymarket CLOB trading.

Responsibilities:

- Hold the pUSD and conditional tokens used for Polymarket trading.
- Approve CLOB trading contracts from the deposit wallet address.
- Act as the CLOB order `funder`.
- Act as the CLOB order `maker`.
- Act as the CLOB order `signer`.
- Validate CLOB order signatures through ERC-1271 when `signatureType = 3` / `POLY_1271` is used.

The deposit wallet is not simply a new Olas multisig. Polymarket describes it as a per-user ERC-1967 proxy deployed by a deposit wallet factory. The documented creation path is Polymarket's relayer `WALLET-CREATE` flow.

### 3. Owner Or Session Signer As CLOB Auth And Signing Key

For deposit-wallet trading, the relevant private key is the deposit wallet owner key or approved session signer key.

Responsibilities:

- Create or derive CLOB API credentials using CLOB L1 authentication.
- Sign deposit wallet `WALLET` batches for approvals or wallet calls.
- Sign CLOB order payloads in the `POLY_1271` flow.

Important distinction:

- The API key is not created by the deposit wallet contract itself.
- The API key is created or derived by the owner/session signer through L1 auth.
- The deposit wallet address is then used as the trading wallet/funder/maker/signer in the CLOB order flow.

## Fund Management Policy

The proposed treasury policy is:

- Keep the majority of funds in the PolySafe.
- Maintain only limited pUSD in the deposit wallet.
- On agent startup or at the start of a trading day, check the deposit wallet pUSD balance.
- If the deposit wallet balance is below a configured threshold, for example `< 2.5 pUSD`, top it up from the PolySafe with a small amount, for example `5` or `10 pUSD`.
- If a later trade requires more funds than are available in the deposit wallet, top up again before placing the order.

This policy is not mandated by Polymarket. It is a risk and operations policy.

Tradeoffs:

- Lower deposit-wallet balance reduces custody exposure.
- Frequent top-ups increase gas usage and latency.
- Too-low thresholds increase the risk that a trade cannot be placed immediately.
- Balance changes must be followed by CLOB balance/allowance sync using `signature_type = 3`.

## Required Deposit Wallet Trading Flow

For a new API user using the deposit wallet path, deposit wallet deployment is
an onboarding/provisioning step that happens before normal agent runtime. At
agent startup, the wallet should already exist. The runtime flow should derive
or discover the expected wallet and verify it before trading.

The agent flow should be:

1. Identify the deposit wallet owner or approved session signer.
2. Derive or discover the expected deposit wallet address and verify it exists.
3. Store both identities:
   - `agent_safe_address`
   - `deposit_wallet_address`
4. Fund the deposit wallet with pUSD from the PolySafe.
5. Submit approvals from the deposit wallet through a Polymarket relayer `WALLET` batch.
6. Sync CLOB balance and allowance with `signature_type = 3`.
7. Initialize the CLOB client for deposit wallet mode:
   - `signature_type = SignatureTypeV2.POLY_1271`
   - `funder = deposit_wallet_address`
   - `key = deposit_wallet_owner_or_session_signer_key`
8. Create or derive CLOB API credentials using that owner/session signer key.
9. Place CLOB orders with:
   - `signatureType = 3`
   - `funder = deposit_wallet_address`
   - `maker = deposit_wallet_address`
   - `signer = deposit_wallet_address`
   - `signature = ERC-7739-wrapped POLY_1271 signature`

Polymarket's migration guide states that if the order is signed as a normal EOA order, or if `maker` and `signer` are not both the deposit wallet address, the order will fail ERC-1271 validation.

## Current Trader State

The reviewed Trader `origin/main` code is CLOB V2-compatible for the existing Safe path.

Observed current behavior:

- It uses `py_clob_client_v2`.
- It initializes `ClobClient` with `signature_type=2`.
- It uses `funder=self.safe_address`.
- It creates or derives CLOB API credentials at startup with `create_or_derive_api_key()`.
- It later calls `create_market_order(...)` and `post_order(...)`.

Current Safe-mode initialization:

```python
self.client = ClobClient(
    host,
    chain_id=chain_id,
    key=self.connection_private_key,
    signature_type=2,
    funder=self.safe_address,
    builder_config=self.builder_config,
)
self.client.set_api_creds(self.client.create_or_derive_api_key())
```

Conclusion:

- Existing Safe users can continue only if runtime deployment matches this CLOB V2-compatible path.
- New deposit-wallet users require a separate deposit wallet mode.
- Reusing the existing Safe-mode client setup for deposit-wallet users is insufficient.

## Required Agent Changes

The agent should support at least two explicit wallet modes:

- `safe_mode`
- `deposit_wallet_mode`

Required changes for `deposit_wallet_mode`:

- Add configuration for `deposit_wallet_address`.
- Add configuration or derivation for deposit wallet owner/session signer.
- Add deposit wallet discovery and verification at startup. The actual
  Polymarket relayer deployment remains a pre-runtime onboarding/provisioning
  step.
- Add PolySafe-to-deposit-wallet pUSD top-up logic.
- Add deposit-wallet balance checks and configurable top-up thresholds.
- Add deposit-wallet approval execution through relayer `WALLET` batches.
- Add CLOB balance/allowance sync with `signature_type = 3`.
- Initialize CLOB client with `POLY_1271` and deposit wallet funder.
- Ensure `create_or_derive_api_key()` is called with the deposit-wallet owner/session signer key.
- Prevent reuse of cached Safe-mode signed orders in deposit-wallet mode.
- Separate cache keys by wallet mode, funder, signature type, exchange address, and token/order parameters.

## API Key Handling

Polymarket CLOB authentication uses two levels:

- L1 auth: wallet private key signs an EIP-712 auth message.
- L2 auth: API key, secret, and passphrase are used for authenticated CLOB REST requests.

For deposit-wallet trading:

- The API key creation/derivation should use the deposit wallet owner or approved session signer key.
- The resulting API credentials are used for CLOB requests such as order posting, cancellations, and balance allowance updates.
- The CLOB order still uses deposit-wallet order semantics: `signatureType = 3`, `funder = deposit_wallet`, `maker = deposit_wallet`, and `signer = deposit_wallet`.

This means the execution identity is split:

- PolySafe: treasury, Mech requests, top-ups.
- Owner/session signer: CLOB L1 auth, API key creation/derivation, order signing.
- Deposit wallet: CLOB funder/maker/signer and holder of trading funds.

## CLOB Order Signature Handling

For deposit-wallet mode, the agent should implement the same signing algorithm
used by Polymarket's CLOB V2 SDK for `POLY_1271`. This can be done by using the
SDK directly, by porting the SDK logic into the agent codebase, or by wrapping
the relevant SDK utilities behind the existing Polymarket client connection.
The important requirement is behavioral equivalence with Polymarket's
`POLY_1271` implementation.

The practical code path should be:

1. Select the correct V2 exchange verifying contract for the market:
   - standard market: CTF Exchange V2;
   - negative-risk market: Neg Risk CTF Exchange V2.
2. Build the CLOB V2 order with the deposit wallet as the wallet identity:

   ```text
   maker         = deposit_wallet_address
   signer        = deposit_wallet_address
   signatureType = 3
   ```

3. Keep the actual signing key separate from the order `signer` field:

   ```text
   signing key = deposit wallet owner EOA
              or approved session signer EOA
   ```

4. Build the CTF Exchange V2 EIP-712 order typed data:

   ```text
   domain.name              = "Polymarket CTF Exchange"
   domain.version           = "2"
   domain.chainId           = current chain id
   domain.verifyingContract = selected CTF Exchange V2 address

   primaryType = "Order"
   ```

5. Build the ERC-7739 nested `TypedDataSign` payload. The nested wallet fields
   are:

   ```text
   name              = "DepositWallet"
   version           = "1"
   chainId           = current chain id
   verifyingContract = deposit_wallet_address
   salt              = bytes32(0)
   contents          = CLOB V2 order message
   ```

6. Sign that nested `TypedDataSign` payload with the deposit wallet owner or
   approved session signer key.
7. Assemble the final `POLY_1271` signature in the same shape as the
   Polymarket SDK:

   ```text
   final_signature =
       inner_signature
       || app_domain_separator
       || contents_hash
       || order_type_string
       || uint16_big_endian(order_type_string_length)
   ```

8. Submit the CLOB order with:

   ```text
   signatureType = 3
   maker         = deposit_wallet_address
   signer        = deposit_wallet_address
   signature     = final_signature
   ```

The agent should treat these fields as invariants before posting the order. A
pre-post validation should reject the signed order if:

- `signatureType != 3`;
- `maker != deposit_wallet_address`;
- `signer != deposit_wallet_address`;
- the selected verifying contract does not match the market type;
- the signature looks like a legacy 65-byte-only signature rather than the
  longer ERC-7739/POLY_1271 wrapper.

### Difference From Normal EOA Signing

Normal EOA CLOB signing uses `signatureType = 0`.

Shape:

```text
maker     = EOA address
signer    = EOA address
funder    = EOA address
signature = normal EIP-712 order signature from the EOA
```

Validation model:

- The order signature is a direct ECDSA signature over the CLOB order typed
  data.
- There is no deposit wallet.
- There is no ERC-1271 wallet validation.
- There is no ERC-7739 wrapper.

Deposit-wallet mode differs because the EOA key signs as the wallet owner or
session signer, but the CLOB order identity is the deposit wallet.

### Difference From Existing PolySafe Signing

Current Trader Safe mode initializes the CLOB client with `signature_type = 2`
and `funder = self.safe_address`.

Shape:

```text
maker         = PolySafe / Safe address
funder        = PolySafe / Safe address
signer        = agent instance EOA
signatureType = 2
signature     = EIP-712 order signature from the agent instance EOA
```

Validation model:

- The Safe is the funded account.
- The agent instance EOA is the order signer.
- The CLOB order is not validated through the deposit wallet's ERC-1271 path.
- The order does not use the ERC-7739/POLY_1271 wrapper.

Deposit-wallet mode changes the meaning of the order signer:

```text
PolySafe mode:
    order.maker  = Safe
    order.signer = agent instance EOA

Deposit-wallet mode:
    order.maker  = deposit wallet
    order.signer = deposit wallet
    actual key   = deposit wallet owner or approved session signer
```

This is why signed order caching must be separated by wallet mode. A cached
Safe-mode order with `signatureType = 2` is structurally invalid for
deposit-wallet mode, even if the same agent instance key produced it.

## Existing Versus New User Classification

The public evidence supports only the following:

- Polymarket distinguishes existing proxy/Safe users from new API users.
- Existing users should continue using their current signature type in this phase.
- New API users should use deposit wallets.

The public evidence does not show:

- An on-chain Safe deployment-date check.
- A public automatic ban list for new Safes.
- A Trader code path that checks whether a Safe is old or new.
- The exact Polymarket backend predicate for classifying a user as existing or new.

Risk:

- A newly created PolySafe may not be accepted as an "existing Safe user" by Polymarket's backend, even if there is no public on-chain evidence of such a rule.
- Off-chain classification cannot be excluded based on the reviewed public material.

Operational conclusion:

- For new users, relying on newly created PolySafes as if they were existing Safe users is not a robust plan.
- Implementing deposit-wallet mode is the safer compatibility path for new onboarding.

## Predict Polymarket Subgraph Impact

The current local `predict-polymarket` subgraph appears to attribute trading activity to the service multisig/Safe address.

Observed model:

- `TraderAgent` is keyed by an address-like `id: Bytes`.
- `handleCreateMultisigWithAgents(...)` creates `TraderAgent(event.params.multisig)`.
- `handleOrderFilled(...)` identifies the trader from `event.params.maker`.
- `processRedemption(...)` identifies the trader from `redeemer`.

Deposit-wallet impact:

- In deposit-wallet orders, Polymarket requires `maker = deposit_wallet`.
- Therefore, `OrderFilled.maker` will be the deposit wallet, not the PolySafe.
- The current subgraph will try to load `TraderAgent(deposit_wallet)`.
- If only the PolySafe was registered as `TraderAgent`, the trade will not be attributed to the agent/service.
- Redemptions can have the same issue if the redeemer is the deposit wallet.

Required subgraph model change:

- Introduce an association between the deposit wallet and the Olas service identity.
- Resolve `maker` and `redeemer` through that association before updating trader statistics.
- Decide the canonical analytics identity:
  - service ID,
  - PolySafe address,
  - deposit wallet address,
  - or a separate canonical `TraderAccount` entity that can contain multiple wallet addresses.

Recommended direction:

- Keep analytics keyed by the Olas service or PolySafe identity.
- Add deposit wallets as execution wallets linked to that identity.
- This avoids splitting one agent's trading history across multiple wallet addresses.

## Conclusion

The proposed split operating model is the most coherent path based on the reviewed evidence.

It keeps the PolySafe as the Olas service treasury and recovery-oriented control wallet, while using the Polymarket deposit wallet as the required execution wallet for new API-user CLOB trading. This avoids assuming that newly created PolySafes will be treated as existing Safe users by Polymarket, while preserving the existing Safe-based custody model for most funds.

The model requires changes in both the agent and the analytics/indexing layer. The agent must support deposit-wallet discovery/verification, top-ups, approvals, CLOB balance sync, API key creation/derivation with the deposit-wallet owner/session signer, and `POLY_1271` order placement. The `predict-polymarket` subgraph must link deposit wallets back to the Olas service/Safe identity to avoid losing trade attribution.
