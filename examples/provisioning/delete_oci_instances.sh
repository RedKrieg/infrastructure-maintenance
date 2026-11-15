#!/usr/bin/env bash
# ==============================================================================
# Script: delete_oci_instances.sh
# Purpose: Terminate OCI Compute instances and delete networking resources.
# ==============================================================================
set -euo pipefail

COMPARTMENT_ID="${OCI_COMPARTMENT_ID:-}"
VCN_NAME="cluster-vcn"
SUBNET_NAME="cluster-subnet"

if [[ -z "${COMPARTMENT_ID}" ]]; then
  echo "[-] ERROR: OCI_COMPARTMENT_ID is required."
  exit 1
fi

echo "[*] Tearing down OCI cluster resources in Compartment: ${COMPARTMENT_ID}"

# 1. Terminate instances
INSTANCES=(
  "proxy-01" "proxy-02" "proxy-03"
  "web-01" "web-02" "web-03"
  "monitoring-01" "teleport-01"
)

for NAME in "${INSTANCES[@]}"; do
  INST_ID=$(oci compute instance list --compartment-id "${COMPARTMENT_ID}" --display-name "${NAME}" --lifecycle-state RUNNING --query "data[0].id" --raw-output 2>/dev/null || true)
  if [[ -n "${INST_ID}" && "${INST_ID}" != "None" ]]; then
    echo "  -> Terminating ${NAME}..."
    oci compute instance terminate --instance-id "${INST_ID}" --preserve-boot-volume false --force
  fi
done

# 2. Delete Subnet
SUBNET_ID=$(oci network subnet list --compartment-id "${COMPARTMENT_ID}" --display-name "${SUBNET_NAME}" --query "data[0].id" --raw-output 2>/dev/null || true)
if [[ -n "${SUBNET_ID}" && "${SUBNET_ID}" != "None" ]]; then
  echo "[+] Deleting Subnet ${SUBNET_NAME}..."
  oci network subnet delete --subnet-id "${SUBNET_ID}" --force || true
fi

# 3. Delete VCN
VCN_ID=$(oci network vcn list --compartment-id "${COMPARTMENT_ID}" --display-name "${VCN_NAME}" --query "data[0].id" --raw-output 2>/dev/null || true)
if [[ -n "${VCN_ID}" && "${VCN_ID}" != "None" ]]; then
  echo "[+] Deleting VCN ${VCN_NAME}..."
  oci network vcn delete --vcn-id "${VCN_ID}" --force || true
fi

echo "[✓] OCI cleanup complete!"
