#!/usr/bin/env bash
# ==============================================================================
# Script: create_gcp_instances.sh
# Purpose: Provision GCP VPC, firewall rules, and Compute Engine instances
#          using direct gcloud CLI commands.
# ==============================================================================
set -euo pipefail

# Configuration Defaults (override via environment variables)
PROJECT_ID="${GCP_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${GCP_REGION:-us-central1}"
NETWORK_NAME="cluster-vpc"
SUBNET_NAME="cluster-subnet"
SUBNET_RANGE="10.128.0.0/20"
MACHINE_TYPE="e2-medium"
IMAGE_FAMILY="ubuntu-2204-lts"
IMAGE_PROJECT="ubuntu-os-cloud"
BOOT_DISK_SIZE="30GB"

if [[ -z "${PROJECT_ID}" || "${PROJECT_ID}" == "(unset)" ]]; then
  echo "[-] ERROR: GCP Project ID is unset. Run: gcloud config set project YOUR_PROJECT_ID"
  exit 1
fi

echo "[*] Using GCP Project: ${PROJECT_ID} in Region: ${REGION}"

# 1. Enable required APIs
echo "[+] Enabling compute.googleapis.com..."
gcloud services enable compute.googleapis.com --project="${PROJECT_ID}"

# 2. Create custom VPC network
if ! gcloud compute networks describe "${NETWORK_NAME}" --project="${PROJECT_ID}" &>/dev/null; then
  echo "[+] Creating custom VPC network: ${NETWORK_NAME}..."
  gcloud compute networks create "${NETWORK_NAME}" \
    --project="${PROJECT_ID}" \
    --subnet-mode=custom
else
  echo "[✓] VPC network ${NETWORK_NAME} already exists."
fi

# 3. Create regional subnetwork
if ! gcloud compute networks subnets describe "${SUBNET_NAME}" --region="${REGION}" --project="${PROJECT_ID}" &>/dev/null; then
  echo "[+] Creating subnet ${SUBNET_NAME} (${SUBNET_RANGE})..."
  gcloud compute networks subnets create "${SUBNET_NAME}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --network="${NETWORK_NAME}" \
    --range="${SUBNET_RANGE}"
else
  echo "[✓] Subnet ${SUBNET_NAME} already exists."
fi

# 4. Create firewall rules
echo "[+] Configuring firewall rules..."

# Allow SSH
if ! gcloud compute firewall-rules describe "${NETWORK_NAME}-allow-ssh" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud compute firewall-rules create "${NETWORK_NAME}-allow-ssh" \
    --project="${PROJECT_ID}" \
    --network="${NETWORK_NAME}" \
    --allow=tcp:22 \
    --source-ranges=0.0.0.0/0 \
    --description="Allow SSH ingress"
fi

# Allow HTTP/HTTPS to Proxies
if ! gcloud compute firewall-rules describe "${NETWORK_NAME}-allow-http-https" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud compute firewall-rules create "${NETWORK_NAME}-allow-http-https" \
    --project="${PROJECT_ID}" \
    --network="${NETWORK_NAME}" \
    --allow=tcp:80,tcp:443 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=proxy \
    --description="Allow public HTTP/HTTPS to HAProxy load balancers"
fi

# Allow internal subnet traffic
if ! gcloud compute firewall-rules describe "${NETWORK_NAME}-allow-internal" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud compute firewall-rules create "${NETWORK_NAME}-allow-internal" \
    --project="${PROJECT_ID}" \
    --network="${NETWORK_NAME}" \
    --allow=tcp,udp,icmp \
    --source-ranges="${SUBNET_RANGE}" \
    --description="Allow internal subnet mesh communication"
fi

# Allow Teleport Web, SSH proxy and reverse tunnels
if ! gcloud compute firewall-rules describe "${NETWORK_NAME}-allow-teleport" --project="${PROJECT_ID}" &>/dev/null; then
  gcloud compute firewall-rules create "${NETWORK_NAME}-allow-teleport" \
    --project="${PROJECT_ID}" \
    --network="${NETWORK_NAME}" \
    --allow=tcp:3080,tcp:3023,tcp:3024 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=teleport \
    --description="Allow Teleport Web and Proxy access"
fi

# 5. Create Compute Instances
echo "[+] Provisioning Compute Engine instances across availability zones..."

declare -A INSTANCES=(
  ["proxy-01"]="us-central1-a 10.128.0.10 proxy,http-server,https-server"
  ["proxy-02"]="us-central1-b 10.128.0.20 proxy,http-server,https-server"
  ["proxy-03"]="us-central1-c 10.128.0.30 proxy,http-server,https-server"
  ["web-01"]="us-central1-a 10.128.0.11 webserver"
  ["web-02"]="us-central1-b 10.128.0.21 webserver"
  ["web-03"]="us-central1-c 10.128.0.31 webserver"
  ["monitoring-01"]="us-central1-a 10.128.0.50 monitoring"
  ["teleport-01"]="us-central1-a 10.128.0.60 teleport"
)

for NAME in "${!INSTANCES[@]}"; do
  read -r ZONE PRIVATE_IP TAGS <<< "${INSTANCES[$NAME]}"
  if ! gcloud compute instances describe "${NAME}" --zone="${ZONE}" --project="${PROJECT_ID}" &>/dev/null; then
    echo "  -> Creating ${NAME} in ${ZONE} (IP: ${PRIVATE_IP})..."
    gcloud compute instances create "${NAME}" \
      --project="${PROJECT_ID}" \
      --zone="${ZONE}" \
      --machine-type="${MACHINE_TYPE}" \
      --network="${NETWORK_NAME}" \
      --subnet="${SUBNET_NAME}" \
      --private-network-ip="${PRIVATE_IP}" \
      --image-family="${IMAGE_FAMILY}" \
      --image-project="${IMAGE_PROJECT}" \
      --boot-disk-size="${BOOT_DISK_SIZE}" \
      --tags="${TAGS}"
  else
    echo "  [✓] Instance ${NAME} already exists in ${ZONE}."
  fi
done

echo ""
echo "[✓] All Compute Engine instances provisioned successfully!"
echo "    Verify instances with: gcloud compute instances list --project=${PROJECT_ID}"
