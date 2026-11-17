#!/usr/bin/env bash
# ==============================================================================
# Script: create_openstack_instances.sh
# Purpose: Provision OpenStack networks, security groups, server groups,
#          and Nova instances using direct OpenStack CLI commands.
# ==============================================================================
set -euo pipefail

OS_CLOUD="${OS_CLOUD:-openstack}"
NETWORK_NAME="cluster-net"
SUBNET_NAME="cluster-subnet"
SUBNET_CIDR="192.168.100.0/24"
ROUTER_NAME="cluster-router"
EXT_NET="${OS_EXTERNAL_NETWORK:-public}"
FLAVOR="${OS_FLAVOR:-m1.medium}"
IMAGE="${OS_IMAGE:-Ubuntu 22.04 LTS}"
KEY_NAME="cluster-key"

echo "[*] Provisioning OpenStack cluster using cloud: ${OS_CLOUD}"

# 1. Keypair
if ! openstack --os-cloud "${OS_CLOUD}" keypair show "${KEY_NAME}" &>/dev/null; then
  echo "[+] Creating keypair ${KEY_NAME}..."
  openstack --os-cloud "${OS_CLOUD}" keypair create --public-key "${HOME}/.ssh/id_ed25519.pub" "${KEY_NAME}"
fi

# 2. Server Groups (Anti-Affinity)
SG_GRP_ID=$(openstack --os-cloud "${OS_CLOUD}" server group show proxy-anti-affinity -c id -f value 2>/dev/null || true)
if [[ -z "${SG_GRP_ID}" ]]; then
  echo "[+] Creating Nova anti-affinity server group for proxies..."
  SG_GRP_ID=$(openstack --os-cloud "${OS_CLOUD}" server group create --policy anti-affinity proxy-anti-affinity -c id -f value)
fi

WEB_SG_GRP_ID=$(openstack --os-cloud "${OS_CLOUD}" server group show web-anti-affinity -c id -f value 2>/dev/null || true)
if [[ -z "${WEB_SG_GRP_ID}" ]]; then
  echo "[+] Creating Nova anti-affinity server group for webservers..."
  WEB_SG_GRP_ID=$(openstack --os-cloud "${OS_CLOUD}" server group create --policy anti-affinity web-anti-affinity -c id -f value)
fi

# 3. Network & Subnet
if ! openstack --os-cloud "${OS_CLOUD}" network show "${NETWORK_NAME}" &>/dev/null; then
  echo "[+] Creating network ${NETWORK_NAME}..."
  openstack --os-cloud "${OS_CLOUD}" network create "${NETWORK_NAME}"
fi

if ! openstack --os-cloud "${OS_CLOUD}" subnet show "${SUBNET_NAME}" &>/dev/null; then
  echo "[+] Creating subnet ${SUBNET_NAME} (${SUBNET_CIDR})..."
  openstack --os-cloud "${OS_CLOUD}" subnet create "${SUBNET_NAME}" \
    --network "${NETWORK_NAME}" \
    --subnet-range "${SUBNET_CIDR}" \
    --dns-nameserver 1.1.1.1 --dns-nameserver 8.8.8.8
fi

# 4. Router
if ! openstack --os-cloud "${OS_CLOUD}" router show "${ROUTER_NAME}" &>/dev/null; then
  echo "[+] Creating router ${ROUTER_NAME} and attaching to ${EXT_NET}..."
  openstack --os-cloud "${OS_CLOUD}" router create "${ROUTER_NAME}"
  openstack --os-cloud "${OS_CLOUD}" router set --external-gateway "${EXT_NET}" "${ROUTER_NAME}"
  openstack --os-cloud "${OS_CLOUD}" router add subnet "${ROUTER_NAME}" "${SUBNET_NAME}" || true
fi

# 5. Security Group
if ! openstack --os-cloud "${OS_CLOUD}" security group show cluster-secgroup &>/dev/null; then
  echo "[+] Creating security group cluster-secgroup..."
  openstack --os-cloud "${OS_CLOUD}" security group create cluster-secgroup --description "Cluster Security Group"
  openstack --os-cloud "${OS_CLOUD}" security group rule create --protocol tcp --dst-port 22:22 --remote-ip 0.0.0.0/0 cluster-secgroup
  openstack --os-cloud "${OS_CLOUD}" security group rule create --protocol tcp --dst-port 80:80 --remote-ip 0.0.0.0/0 cluster-secgroup
  openstack --os-cloud "${OS_CLOUD}" security group rule create --protocol tcp --dst-port 443:443 --remote-ip 0.0.0.0/0 cluster-secgroup
  openstack --os-cloud "${OS_CLOUD}" security group rule create --protocol tcp --dst-port 3080:3080 --remote-ip 0.0.0.0/0 cluster-secgroup
  openstack --os-cloud "${OS_CLOUD}" security group rule create --protocol tcp --dst-port 3023:3023 --remote-ip 0.0.0.0/0 cluster-secgroup
  openstack --os-cloud "${OS_CLOUD}" security group rule create --protocol tcp --dst-port 3024:3024 --remote-ip 0.0.0.0/0 cluster-secgroup
  openstack --os-cloud "${OS_CLOUD}" security group rule create --remote-ip "${SUBNET_CIDR}" cluster-secgroup
fi

# 6. Create Servers
declare -A SERVERS=(
  ["proxy-01"]="192.168.100.10 proxy"
  ["proxy-02"]="192.168.100.20 proxy"
  ["proxy-03"]="192.168.100.30 proxy"
  ["web-01"]="192.168.100.11 webserver"
  ["web-02"]="192.168.100.12 webserver"
  ["web-03"]="192.168.100.13 webserver"
  ["monitoring-01"]="192.168.100.50 monitoring"
  ["teleport-01"]="192.168.100.60 teleport"
)

for NAME in "${!SERVERS[@]}"; do
  read -r PRIV_IP ROLE <<< "${SERVERS[$NAME]}"
  if ! openstack --os-cloud "${OS_CLOUD}" server show "${NAME}" &>/dev/null; then
    echo "  -> Launching ${NAME} (${PRIV_IP})..."
    HINT_OPT=""
    if [[ "${ROLE}" == "proxy" ]]; then
      HINT_OPT="--hint group=${SG_GRP_ID}"
    elif [[ "${ROLE}" == "webserver" ]]; then
      HINT_OPT="--hint group=${WEB_SG_GRP_ID}"
    fi
    openstack --os-cloud "${OS_CLOUD}" server create "${NAME}" \
      --flavor "${FLAVOR}" \
      --image "${IMAGE}" \
      --key-name "${KEY_NAME}" \
      --network "${NETWORK_NAME}" \
      --nic "net-id=${NETWORK_NAME},v4-fixed-ip=${PRIV_IP}" \
      --security-group "cluster-secgroup" \
      ${HINT_OPT} \
      --wait
  else
    echo "  [✓] Server ${NAME} already exists."
  fi
done

echo "[✓] OpenStack cluster provisioned successfully!"
