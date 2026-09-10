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

The body is reproducible exactly: solc 0.8.28, optimizer on at 750 runs, `evm_version = cancun`, source
at `5efeb59`. The metadata hash is not, because it covers the whole source set, and a comment anywhere
in `StakingBase.sol` or its imports moves it without changing a byte of code. Three foundry
configurations were tried against it — with and without the `@gnosis.pm` remapping, and with
`bytecode_hash` set explicitly — and none reproduced it; identifying the exact tree would mean
bisecting for a hash. Do not add a `deployed/RobinhoodStakingToken.json`: any build we can make is not
the build that produced these bytes, which is the one thing an entry in this directory asserts.
Sourcify records the contract as `match` rather than `exact_match` for exactly the same reason.
