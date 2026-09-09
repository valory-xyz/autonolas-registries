# Robinhood Chain (4663) — verification inputs

Standard-JSON compiler inputs and ABI-encoded constructor arguments for every contract
deployed in wave 1, captured at deploy time.

## Why these files exist

Neither automatic verification route works on chain 4663:

- **Etherscan V2** does not list 4663 at all — no API key helps.
- **Robinhood's Blockscout** sits behind a Cloudflare challenge that returns 403 to every
  non-browser client, including `forge`. A key for that instance does not help either; it is an
  edge block, not an auth gate.
- **Sourcify** does support the chain and `forge --verifier sourcify --chain-id 4663` submits
  correctly, but its single 4663 RPC (`lb.drpc.org`) was failing at deploy time with
  `cannot_fetch_bytecode`. Contracts verified there earlier the same day, so this is an outage
  rather than a lack of support.

Rather than leave verification dependent on reconstructing build settings weeks later, the inputs
were captured while the build trees were live.

## Verifying later

When Sourcify's 4663 RPC recovers:

    forge verify-contract --verifier sourcify --chain-id 4663 <address> <path> \
      --constructor-args $(cat <Name>.constructor-args.txt)

Or paste `<Name>.standard-input.json` into Blockscout's browser verification form, which is not
subject to the API-level block.

## Build trees — these differ, and it matters

| contracts | source | solc | optimizer | evmVersion |
|---|---|---|---|---|
| all except StakingToken | `main` @ 52ee868 | 0.8.30 | on, 750 runs | prague |
| **StakingToken** | **commit 5efeb59** | **0.8.28** | on, 750 runs | **cancun** |

StakingToken is pinned to 0.2.0 to match every other chain; `main` now carries 0.3.0. Building it
with the repository's current settings produces the wrong contract. The settings above come from
that commit's `hardhat.config.js`, since the repo had no `foundry.toml` then, and reproduce Mode's
live implementation exactly once metadata is stripped.
