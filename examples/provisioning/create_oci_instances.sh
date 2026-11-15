#!/usr/bin/env bash
# ==============================================================================
# Script: create_oci_instances.sh
# Purpose: Provision OCI VCN, subnet, security lists, and Compute instances
#          using direct OCI CLI commands.
# ==============================================================================
set -euo pipefail

COMPARTMENT_ID="${OCI_COMPARTMENT_ID:-}"
REGION="${OCI_REGION:-us-ashburn-1}"
VCN_NAME="cluster-vcn"
VCN_CIDR="10.0.0.0/16"
SUBNET_NAME="cluster-subnet"
SUBNET_CIDR="10.0.1.0/24"
SHAPE="VM.Standard.E4.Flex"
OCPUS=1
MEMORY_GBS=4
SSH_KEY_FILE="${HOME}/.ssh/id_ed25519.pub"

if [[ -z "${COMPARTMENT_ID}" ]]; then
  echo "[-] ERROR: OCI_COMPARTMENT_ID is required. Export it or set in script."
  exit 1
fi

echo "[*] Provisioning OCI infrastructure in Compartment: ${COMPARTMENT_ID}"

# 1. Create VCN
VCN_ID=$(oci network vcn list --compartment-id "${COMPARTMENT_ID}" --display-name "${VCN_NAME}" --query "data[0].id" --raw-output 2>/dev/null || true)
if [[ -z "${VCN_ID}" || "${VCN_ID}" == "None" ]]; then
  echo "[+] Creating VCN ${VCN_NAME} (${VCN_CIDR})..."
  VCN_ID=$(oci network vcn create \
    --compartment-id "${COMPARTMENT_ID}" \
    --display-name "${VCN_NAME}" \
    --cidr-block "${VCN_CIDR}" \
    --dns-label clustervcn \
    --query "data.id" --raw-output)
fi
echo "  [✓] VCN ID: ${VCN_ID}"

# 2. Create Internet Gateway
IGW_ID=$(oci network internet-gateway list --compartment-id "${COMPARTMENT_ID}" --vcn-id "${VCN_ID}" --query "data[0].id" --raw-output 2>/dev/null || true)
if [[ -z "${IGW_ID}" || "${IGW_ID}" == "None" ]]; then
  echo "[+] Creating Internet Gateway..."
  IGW_ID=$(oci network internet-gateway create \
    --compartment-id "${COMPARTMENT_ID}" \
    --vcn-id "${VCN_ID}" \
    --display-name "${VCN_NAME}-igw" \
    --is-enabled true \
    --query "data.id" --raw-output)
fi

# 3. Create Subnet
SUBNET_ID=$(oci network subnet list --compartment-id "${COMPARTMENT_ID}" --vcn-id "${VCN_ID}" --display-name "${SUBNET_NAME}" --query "data[0].id" --raw-output 2>/dev/null || true)
if [[ -z "${SUBNET_ID}" || "${SUBNET_ID}" == "None" ]]; then
  echo "[+] Creating Regional Subnet ${SUBNET_NAME} (${SUBNET_CIDR})..."
  SUBNET_ID=$(oci network subnet create \
    --compartment-id "${COMPARTMENT_ID}" \
    --vcn-id "${VCN_ID}" \
    --display-name "${SUBNET_NAME}" \
    --cidr-block "${SUBNET_CIDR}" \
    --dns-label clustersubnet \
    --query "data.id" --raw-output)
fi
echo "  [✓] Subnet ID: ${SUBNET_ID}"

# 4. Lookup Image OCID
IMAGE_ID=$(oci compute image list \
  --compartment-id "${COMPARTMENT_ID}" \
  --operating-system "Canonical Ubuntu" \
  --operating-system-version "22.04" \
  --shape "${SHAPE}" \
  --sort-by TIMECREATED \
  --sort-order DESC \
  --query "data[0].id" --raw-output)

# 5. Launch Instances across Fault Domains
declare -A INSTANCES=(
  ["proxy-01"]="FAULT-DOMAIN-1 10.0.1.10"
  ["proxy-02"]="FAULT-DOMAIN-2 10.0.1.20"
  ["proxy-03"]="FAULT-DOMAIN-3 10.0.1.30"
  ["web-01"]="FAULT-DOMAIN-1 10.0.1.11"
  ["web-02"]="FAULT-DOMAIN-2 10.0.1.21"
  ["web-03"]="FAULT-DOMAIN-3 10.0.1.31"
  ["monitoring-01"]="FAULT-DOMAIN-1 10.0.1.50"
  ["teleport-01"]="FAULT-DOMAIN-1 10.0.1.60"
)

for NAME in "${!INSTANCES[@]}"; do
  read -r FD PRIV_IP <<< "${INSTANCES[$NAME]}"
  EXISTING=$(oci compute instance list --compartment-id "${COMPARTMENT_ID}" --display-name "${NAME}" --lifecycle-state RUNNING --query "data[0].id" --raw-output 2>/dev/null || true)
  if [[ -z "${EXISTING}" || "${EXISTING}" == "None" ]]; then
    echo "  -> Launching ${NAME} in ${FD} (${PRIV_IP})..."
    oci compute instance launch \
      --compartment-id "${COMPARTMENT_ID}" \
      --display-name "${NAME}" \
      --fault-domain "${FD}" \
      --shape "${SHAPE}" \
      --shape-config "{\"ocpus\": ${OCPUS}, \"memoryInGBs\": ${MEMORY_GBS}}" \
      --image-id "${IMAGE_ID}" \
      --subnet-id "${SUBNET_ID}" \
      --private-ip "${PRIV_IP}" \
      --assign-public-ip true \
      --ssh-authorized-keys-file "${SSH_KEY_FILE}" > /dev/null
  else
    echo "  [✓] Instance ${NAME} already exists."
  fi
done

echo "[✓] OCI cluster provisioned successfully!"
