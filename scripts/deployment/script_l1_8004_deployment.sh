#!/bin/bash

set -euo pipefail

# Deploy ServiceManager
./scripts/deployment/deploy_07_service_manager.sh $1

# Deploy ServiceManagerProxy
./scripts/deployment/deploy_08_service_manager_proxy.sh $1

# !!!! TEST ONLY, DAO VOTE IN PRODUCTION
# Change managers
./scripts/deployment/script_l1_02_change_managers_registries.sh $1

# Deploy IdentityRegistryBridger
./scripts/deployment/deploy_25_identity_registry_bridger.sh $1

# Deploy IdentityRegistryBridgerProxy
./scripts/deployment/deploy_26_identity_registry_bridger_proxy.sh $1

# Change ServiceManagerProxy in IdentityRegistryBridgerProxy and vice versa
./scripts/deployment/script_l1_03_change_service_manager_identity_registry_bridger.sh $1