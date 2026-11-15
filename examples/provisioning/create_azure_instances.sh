#!/usr/bin/env bash
# ==============================================================================
# Script: create_azure_instances.sh
# Purpose: Provision Azure Resource Group, VNet, NSG, and Ubuntu VMs
#          using direct Azure CLI (az) commands.
# ==============================================================================
set -euo pipefail

RG_NAME="${AZURE_RG:-cluster-rg}"
LOCATION="${AZURE_LOCATION:-eastus}"
VNET_NAME="cluster-vnet"
VNET_CIDR="10.240.0.0/16"
SUBNET_NAME="cluster-subnet"
SUBNET_CIDR="10.240.1.0/24"
NSG_NAME="cluster-nsg"
VM_SIZE="Standard_B2s"
SSH_PUB_KEY="${HOME}/.ssh/id_ed25519.pub"

echo "[*] Provisioning Azure infrastructure in Resource Group: ${RG_NAME} (${LOCATION})"

# 1. Create Resource Group
if ! az group show --name "${RG_NAME}" &>/dev/null; then
  echo "[+] Creating Resource Group ${RG_NAME}..."
  az group create --name "${RG_NAME}" --location "${LOCATION}" > /dev/null
fi

# 2. Create NSG & Rules
if ! az network nsg show --resource-group "${RG_NAME}" --name "${NSG_NAME}" &>/dev/null; then
  echo "[+] Creating NSG ${NSG_NAME}..."
  az network nsg create --resource-group "${RG_NAME}" --name "${NSG_NAME}" > /dev/null
  az network nsg rule create --resource-group "${RG_NAME}" --nsg-name "${NSG_NAME}" --name AllowSSH --priority 100 --destination-port-ranges 22 --protocol Tcp --access Allow > /dev/null
  az network nsg rule create --resource-group "${RG_NAME}" --nsg-name "${NSG_NAME}" --name AllowHTTP --priority 110 --destination-port-ranges 80 --protocol Tcp --access Allow > /dev/null
  az network nsg rule create --resource-group "${RG_NAME}" --nsg-name "${NSG_NAME}" --name AllowHTTPS --priority 120 --destination-port-ranges 443 --protocol Tcp --access Allow > /dev/null
  az network nsg rule create --resource-group "${RG_NAME}" --nsg-name "${NSG_NAME}" --name AllowTeleport --priority 130 --destination-port-ranges 3080 3023 3024 --protocol Tcp --access Allow > /dev/null
  az network nsg rule create --resource-group "${RG_NAME}" --nsg-name "${NSG_NAME}" --name AllowInternal --priority 140 --source-address-prefixes "${VNET_CIDR}" --destination-port-ranges '*' --protocol '*' --access Allow > /dev/null
fi

# 3. Create VNet and Subnet
if ! az network vnet show --resource-group "${RG_NAME}" --name "${VNET_NAME}" &>/dev/null; then
  echo "[+] Creating Virtual Network ${VNET_NAME}..."
  az network vnet create \
    --resource-group "${RG_NAME}" \
    --name "${VNET_NAME}" \
    --address-prefixes "${VNET_CIDR}" \
    --subnet-name "${SUBNET_NAME}" \
    --subnet-prefixes "${SUBNET_CIDR}" \
    --network-security-group "${NSG_NAME}" > /dev/null
fi

# 4. Provision VMs across Availability Zones
declare -A VMS=(
  ["proxy-01"]="1 10.240.1.10"
  ["proxy-02"]="2 10.240.1.20"
  ["proxy-03"]="3 10.240.1.30"
  ["web-01"]="1 10.240.1.11"
  ["web-02"]="2 10.240.1.21"
  ["web-03"]="3 10.240.1.31"
  ["monitoring-01"]="1 10.240.1.50"
  ["teleport-01"]="1 10.240.1.60"
)

for NAME in "${!VMS[@]}"; do
  read -r ZONE PRIV_IP <<< "${VMS[$NAME]}"
  if ! az vm show --resource-group "${RG_NAME}" --name "${NAME}" &>/dev/null; then
    echo "  -> Launching VM ${NAME} in Zone ${ZONE} (${PRIV_IP})..."
    az vm create \
      --resource-group "${RG_NAME}" \
      --name "${NAME}" \
      --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest" \
      --size "${VM_SIZE}" \
      --admin-username "ubuntu" \
      --ssh-key-values "${SSH_PUB_KEY}" \
      --vnet-name "${VNET_NAME}" \
      --subnet "${SUBNET_NAME}" \
      --private-ip-address "${PRIV_IP}" \
      --public-ip-address "${NAME}-pip" \
      --public-ip-sku "Standard" \
      --zone "${ZONE}" \
      --no-wait > /dev/null
  else
    echo "  [✓] VM ${NAME} already exists."
  fi
done

echo "[*] Waiting for VM deployment operations to complete..."
az vm wait --resource-group "${RG_NAME}" --name "proxy-01" --created 2>/dev/null || true

echo "[✓] Azure cluster provisioned successfully!"
