#!/usr/bin/env bash
# ==============================================================================
# Script: delete_openstack_instances.sh
# Purpose: Delete OpenStack servers, security groups, routers, and networks.
# ==============================================================================
set -euo pipefail

OS_CLOUD="${OS_CLOUD:-openstack}"
NETWORK_NAME="cluster-net"
SUBNET_NAME="cluster-subnet"
ROUTER_NAME="cluster-router"
KEY_NAME="cluster-key"

echo "[*] Tearing down OpenStack cluster using cloud: ${OS_CLOUD}"

# 1. Delete servers
SERVERS=(
  "proxy-01" "proxy-02" "proxy-03"
  "web-01" "web-02" "web-03"
  "monitoring-01" "teleport-01"
)

for NAME in "${SERVERS[@]}"; do
  if openstack --os-cloud "${OS_CLOUD}" server show "${NAME}" &>/dev/null; then
    echo "  -> Deleting server ${NAME}..."
    openstack --os-cloud "${OS_CLOUD}" server delete "${NAME}" --wait
  fi
done

# 2. Delete security group
if openstack --os-cloud "${OS_CLOUD}" security group show cluster-secgroup &>/dev/null; then
  echo "[+] Deleting security group cluster-secgroup..."
  openstack --os-cloud "${OS_CLOUD}" security group delete cluster-secgroup || true
fi

# 3. Delete router
if openstack --os-cloud "${OS_CLOUD}" router show "${ROUTER_NAME}" &>/dev/null; then
  echo "[+] Removing subnet and clearing gateway from router ${ROUTER_NAME}..."
  openstack --os-cloud "${OS_CLOUD}" router remove subnet "${ROUTER_NAME}" "${SUBNET_NAME}" || true
  openstack --os-cloud "${OS_CLOUD}" router unset --external-gateway "${ROUTER_NAME}" || true
  openstack --os-cloud "${OS_CLOUD}" router delete "${ROUTER_NAME}" || true
fi

# 4. Delete subnet & network
if openstack --os-cloud "${OS_CLOUD}" subnet show "${SUBNET_NAME}" &>/dev/null; then
  echo "[+] Deleting subnet ${SUBNET_NAME}..."
  openstack --os-cloud "${OS_CLOUD}" subnet delete "${SUBNET_NAME}" || true
fi

if openstack --os-cloud "${OS_CLOUD}" network show "${NETWORK_NAME}" &>/dev/null; then
  echo "[+] Deleting network ${NETWORK_NAME}..."
  openstack --os-cloud "${OS_CLOUD}" network delete "${NETWORK_NAME}" || true
fi

# 5. Delete Server Group & Keypair
openstack --os-cloud "${OS_CLOUD}" server group delete proxy-anti-affinity || true
openstack --os-cloud "${OS_CLOUD}" keypair delete "${KEY_NAME}" || true

echo "[✓] OpenStack cluster cleanup complete!"
