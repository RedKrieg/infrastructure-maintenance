#!/usr/bin/env bash
# ==============================================================================
# Script: delete_gcp_instances.sh
# Purpose: Cleanly teardown GCP Compute Engine instances, firewalls, and VPC.
# ==============================================================================
set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${GCP_REGION:-us-central1}"
NETWORK_NAME="cluster-vpc"
SUBNET_NAME="cluster-subnet"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "[-] ERROR: GCP Project ID is unset. Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

echo "[*] Tearing down GCP cluster resources in project: ${PROJECT_ID}"

# 1. Delete instances
INSTANCES=(
  "proxy-01:us-central1-a"
  "proxy-02:us-central1-b"
  "proxy-03:us-central1-c"
  "web-01:us-central1-a"
  "web-02:us-central1-b"
  "web-03:us-central1-c"
  "monitoring-01:us-central1-a"
  "teleport-01:us-central1-a"
)

for ENTRY in "${INSTANCES[@]}"; do
  NAME="${ENTRY%%:*}"
  ZONE="${ENTRY##*:}"
  if gcloud compute instances describe "${NAME}" --zone="${ZONE}" --project="${PROJECT_ID}" &>/dev/null; then
    echo "  -> Deleting instance ${NAME} in ${ZONE}..."
    gcloud compute instances delete "${NAME}" --zone="${ZONE}" --project="${PROJECT_ID}" --quiet
  fi
done

# 2. Delete firewalls
FIREWALLS=(
  "${NETWORK_NAME}-allow-ssh"
  "${NETWORK_NAME}-allow-http-https"
  "${NETWORK_NAME}-allow-internal"
  "${NETWORK_NAME}-allow-teleport"
)

for FW in "${FIREWALLS[@]}"; do
  if gcloud compute firewall-rules describe "${FW}" --project="${PROJECT_ID}" &>/dev/null; then
    echo "  -> Deleting firewall rule ${FW}..."
    gcloud compute firewall-rules delete "${FW}" --project="${PROJECT_ID}" --quiet
  fi
done

# 3. Delete subnet
if gcloud compute networks subnets describe "${SUBNET_NAME}" --region="${REGION}" --project="${PROJECT_ID}" &>/dev/null; then
  echo "  -> Deleting subnet ${SUBNET_NAME}..."
  gcloud compute networks subnets delete "${SUBNET_NAME}" --region="${REGION}" --project="${PROJECT_ID}" --quiet
fi

# 4. Delete network
if gcloud compute networks describe "${NETWORK_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
  echo "  -> Deleting VPC network ${NETWORK_NAME}..."
  gcloud compute networks delete "${NETWORK_NAME}" --project="${PROJECT_ID}" --quiet
fi

echo "[✓] Cleanup complete!"
