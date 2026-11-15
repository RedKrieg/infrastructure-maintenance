#!/usr/bin/env bash
# ==============================================================================
# Script: delete_azure_instances.sh
# Purpose: Cleanly delete Azure Resource Group and all associated cluster VMs.
# ==============================================================================
set -euo pipefail

RG_NAME="${AZURE_RG:-cluster-rg}"

echo "[*] Deleting Azure Resource Group: ${RG_NAME} (this removes all associated VMs and network resources)..."
az group delete --name "${RG_NAME}" --yes --no-wait

echo "[✓] Azure deletion initiated!"
