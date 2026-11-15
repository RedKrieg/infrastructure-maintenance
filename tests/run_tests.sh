#!/usr/bin/env bash
# ==============================================================================
# Script: run_tests.sh
# Purpose: Execute local verification, syntax validation, and linting
# ==============================================================================
set -euo pipefail

echo "================================================================="
echo " 1. Shell Script Syntax Validation (bash -n)"
echo "================================================================="
find . -name "*.sh" -not -path "*/.git/*" -print0 | while IFS= read -r -d '' file; do
  bash -n "$file"
  echo "  [✓] $file"
done

echo ""
echo "================================================================="
echo " 2. Main Playbook Syntax Checks Across All Inventories"
echo "================================================================="
INVENTORIES=(
  "inventory.ini"
  "examples/inventories/inventory.aws.ini"
  "examples/inventories/inventory.gcp.ini"
  "examples/inventories/inventory.azure.ini"
  "examples/inventories/inventory.oci.ini"
  "examples/inventories/inventory.openstack.ini"
)

for inv in "${INVENTORIES[@]}"; do
  echo "  -> Checking playbook.yml with $inv..."
  ansible-playbook -i "$inv" playbook.yml --syntax-check > /dev/null
  echo "     [✓] PASS"
done

echo ""
echo "================================================================="
echo " 3. Cloud Provisioning Playbook Syntax Checks"
echo "================================================================="
PROV_PLAYBOOKS=(
  "examples/provisioning/provision_aws.yml"
  "examples/provisioning/deprovision_aws.yml"
  "examples/provisioning/provision_gcp.yml"
  "examples/provisioning/deprovision_gcp.yml"
  "examples/provisioning/provision_azure.yml"
  "examples/provisioning/deprovision_azure.yml"
  "examples/provisioning/provision_oci.yml"
  "examples/provisioning/deprovision_oci.yml"
  "examples/provisioning/provision_openstack.yml"
  "examples/provisioning/deprovision_openstack.yml"
)

for pb in "${PROV_PLAYBOOKS[@]}"; do
  echo "  -> Checking $pb..."
  ansible-playbook "$pb" --syntax-check > /dev/null
  echo "     [✓] PASS"
done

echo ""
echo "================================================================="
echo " All syntax and script validation checks PASSED successfully!"
echo "================================================================="
