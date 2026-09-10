# Autonolas registries ABIs
These ABIs were obtained with 750 optimization passes.

`abis/0.8.30-no-optimizer/` holds artifacts for deployments made before `foundry.toml` carried
`optimizer`/`optimizer_runs`. The gnosis and base `ComplementaryServiceMetadata` contracts were
deployed on 2025-06-18, and the very commit that recorded that deployment is the one that added the
optimizer settings — so both are unoptimized builds at 3937 B against the 2517 B optimized artifact.
Same source, same solc, same `evm_version`; only the optimizer differs. If either is redeployed,
delete the artifact and repoint the entry back at `abis/0.8.30/`.

## `deployed/`

The per-solc directories are a convention, not an output of any deployment: `deploy_*.sh` run
`forge create --broadcast`, which compiles from source and broadcasts without writing anything back
here. So an entry in `docs/configuration.json` matches only if someone committed an artifact built
the same way the contract was deployed, and that is easy to get wrong in two independent ways.

Chain 4663 got both wrong at once. `abis/0.8.28/` holds **hardhat** artifacts from 2024, while these
contracts were deployed with **solc 0.8.30** through forge — a different compiler and a different
metadata document, since the metadata records source paths and remappings. Lengths happened to
coincide, so the audit's length check passed and only the trailer check caught it.

`deployed/Robinhood*.json` are the forge builds that reproduce chain 4663's deployed bytecode: same
solc, same `optimizer_runs = 750`, same `evm_version`, trailer included. They are stored per
deployment rather than per solc because that is what they are — the build that produced those
particular contracts. Four 4663 entries are not here and still point at `abis/0.8.30/`, because
those files are current forge builds of the same source and already match.

`StakingToken` is the one 4663 contract with no matching artifact anywhere, and it stays that way on
purpose. It was deployed deliberately from the older mode-parity source rather than from `main`, which
is why it is solc 0.8.28 and 13898 B while a `forge create` off current `main` would produce the 0.8.30
build at 17057 B. That is a fleet-parity choice, not drift: the same source compiled at 0.8.25 gives the
13868 B build the other six chains run.

It was compiled fresh at deploy time, not replayed from a committed artifact — its creation transaction
is the same length as `abis/0.8.28/StakingToken.json` and differs from it only in the metadata hash. So
no artifact in this repo matches its trailer, and the trailer check warns by construction.

The body is reproducible exactly: solc 0.8.28, optimizer on at 750 runs, `evm_version = cancun`, and the
source anywhere in the `a0ba899..067990b` window — the closure is only four files (`StakingToken.sol`,
`StakingBase.sol`, `SafeTransferLib.sol`, solmate's `ERC721.sol`) and nothing touched it between
2024-07-12 and 2025-08-13.

The metadata hash was not reproduced, and the search for it was exhaustive rather than abandoned:

- every one of the 43 commits that has ever touched that four-file closure was built and compared.
  Two give a byte-identical body; none gives the trailer;
- the build was repeated inside a copy of the tree that actually performed the deployment, with its
  own `foundry.toml`, `node_modules` and `lib`, so the full remapping set including
  `@gnosis.pm/=node_modules/@gnosis.pm/` was present. Still only the body matched;
- `evm_version` (cancun/shanghai/paris/london — only cancun gives the right length) and an explicit
  `bytecode_hash = "ipfs"` were varied too.

The deployment was a fresh compile, not a replay: its creation transaction is the same length as
`abis/0.8.28/StakingToken.json` and differs only in the metadata hash. So the remaining difference is
in the metadata document rather than the code, and it is not recoverable from this repository's
history — the original document is not pinned on IPFS either.

Do not add a `deployed/RobinhoodStakingToken.json`. Any build we can make is not the build that produced
these bytes, which is the one thing an entry in this directory asserts, and it would swap a warn that is
explained for a warn that looks like an oversight. Sourcify records the contract as `match` rather than
`exact_match` for exactly the same reason, and that is the honest state: the executable bytes are proven,
the metadata document is not.
