# Autonolas registries ABIs
These ABIs were obtained with 750 optimization passes.

`abis/0.8.30-no-optimizer/` holds artifacts for deployments made before `foundry.toml` carried
`optimizer`/`optimizer_runs`. The gnosis and base `ComplementaryServiceMetadata` contracts were
deployed on 2025-06-18, and the very commit that recorded that deployment is the one that added the
optimizer settings — so both are unoptimized builds at 3937 B against the 2517 B optimized artifact.
Same source, same solc, same `evm_version`; only the optimizer differs. If either is redeployed,
delete the artifact and repoint the entry back at `abis/0.8.30/`.
