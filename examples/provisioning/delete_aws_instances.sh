#!/usr/bin/env bash
# ==============================================================================
# Script: delete_aws_instances.sh
# Purpose: Terminate EC2 instances and tear down AWS cluster resources.
# ==============================================================================
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"

echo "[*] Tearing down AWS EC2 cluster in region: ${AWS_REGION}"

# 1. Terminate instances
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Cluster,Values=headless-ubuntu" "Name=instance-state-name,Values=running,pending,stopped" \
  --region "${AWS_REGION}" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)

if [[ -n "${INSTANCE_IDS}" && "${INSTANCE_IDS}" != "None" ]]; then
  echo "[+] Terminating instances: ${INSTANCE_IDS}..."
  aws ec2 terminate-instances --instance-ids ${INSTANCE_IDS} --region "${AWS_REGION}" > /dev/null
  echo "[*] Waiting for instances to terminate..."
  aws ec2 wait instance-terminated --instance-ids ${INSTANCE_IDS} --region "${AWS_REGION}"
fi

# 2. Find and delete VPC
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=cluster-vpc" \
  --region "${AWS_REGION}" \
  --query "Vpcs[0].VpcId" \
  --output text)

if [[ -n "${VPC_ID}" && "${VPC_ID}" != "None" ]]; then
  echo "[+] Cleaning up VPC ${VPC_ID}..."
  
  # Delete Security Group
  SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=cluster-sg" --region "${AWS_REGION}" --query "SecurityGroups[0].GroupId" --output text)
  if [[ -n "${SG_ID}" && "${SG_ID}" != "None" ]]; then
    aws ec2 delete-security-group --group-id "${SG_ID}" --region "${AWS_REGION}" || true
  fi

  # Detach and delete IGW
  IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPC_ID}" --region "${AWS_REGION}" --query "InternetGateways[0].InternetGatewayId" --output text)
  if [[ -n "${IGW_ID}" && "${IGW_ID}" != "None" ]]; then
    aws ec2 detach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}" --region "${AWS_REGION}" || true
    aws ec2 delete-internet-gateway --internet-gateway-id "${IGW_ID}" --region "${AWS_REGION}" || true
  fi

  # Delete subnets
  SUBNET_IDS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" --region "${AWS_REGION}" --query "Subnets[*].SubnetId" --output text)
  for SID in ${SUBNET_IDS}; do
    aws ec2 delete-subnet --subnet-id "${SID}" --region "${AWS_REGION}" || true
  done

  # Delete route tables
  RT_IDS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=cluster-public-rt" --region "${AWS_REGION}" --query "RouteTables[*].RouteTableId" --output text)
  for RT in ${RT_IDS}; do
    aws ec2 delete-route-table --route-table-id "${RT}" --region "${AWS_REGION}" || true
  done

  # Delete VPC
  aws ec2 delete-vpc --vpc-id "${VPC_ID}" --region "${AWS_REGION}"
fi

# 3. Delete Key Pair
aws ec2 delete-key-pair --key-name "cluster-key" --region "${AWS_REGION}" || true

echo "[✓] AWS EC2 cluster cleanup complete!"
