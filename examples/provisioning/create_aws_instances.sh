#!/usr/bin/env bash
# ==============================================================================
# Script: create_aws_instances.sh
# Purpose: Provision AWS VPC, subnets, security groups, and EC2 instances
#          using direct AWS CLI commands.
# ==============================================================================
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
VPC_CIDR="172.31.0.0/16"
KEY_NAME="cluster-key"
INSTANCE_TYPE="t3.medium"

echo "[*] Provisioning AWS EC2 infrastructure in region: ${AWS_REGION}"

# 1. Ensure Key Pair
if ! aws ec2 describe-key-pairs --key-names "${KEY_NAME}" --region "${AWS_REGION}" &>/dev/null; then
  echo "[+] Importing SSH key pair: ${KEY_NAME}..."
  aws ec2 import-key-pair \
    --key-name "${KEY_NAME}" \
    --public-key-material "fileb://${HOME}/.ssh/id_ed25519.pub" \
    --region "${AWS_REGION}"
fi

# 2. Get Ubuntu 22.04 LTS AMI ID
echo "[+] Looking up latest Canonical Ubuntu 22.04 LTS AMI..."
AMI_ID=$(aws ec2 describe-images \
  --region "${AWS_REGION}" \
  --owners "099720109477" \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" "Name=state,Values=available" \
  --query "reverse(sort_by(Images, &CreationDate))[0].ImageId" \
  --output text)
echo "  [✓] Found AMI: ${AMI_ID}"

# 3. Create VPC
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=cidr-block,Values=${VPC_CIDR}" "Name=tag:Name,Values=cluster-vpc" --region "${AWS_REGION}" --query "Vpcs[0].VpcId" --output text)
if [[ "${VPC_ID}" == "None" || -z "${VPC_ID}" ]]; then
  echo "[+] Creating VPC ${VPC_CIDR}..."
  VPC_ID=$(aws ec2 create-vpc --cidr-block "${VPC_CIDR}" --region "${AWS_REGION}" --query "Vpc.VpcId" --output text)
  aws ec2 create-tags --resources "${VPC_ID}" --tags "Key=Name,Value=cluster-vpc" --region "${AWS_REGION}"
  aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-hostnames "{\"Value\":true}" --region "${AWS_REGION}"
fi
echo "  [✓] VPC ID: ${VPC_ID}"

# 4. Create Internet Gateway
IGW_ID=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPC_ID}" --region "${AWS_REGION}" --query "InternetGateways[0].InternetGatewayId" --output text)
if [[ "${IGW_ID}" == "None" || -z "${IGW_ID}" ]]; then
  echo "[+] Creating and attaching Internet Gateway..."
  IGW_ID=$(aws ec2 create-internet-gateway --region "${AWS_REGION}" --query "InternetGateway.InternetGatewayId" --output text)
  aws ec2 attach-internet-gateway --vpc-id "${VPC_ID}" --internet-gateway-id "${IGW_ID}" --region "${AWS_REGION}"
fi

# 5. Create Subnets across AZs
declare -A SUBNETS=(
  ["cluster-subnet-1a"]="172.31.10.0/24 us-east-1a"
  ["cluster-subnet-1b"]="172.31.20.0/24 us-east-1b"
  ["cluster-subnet-1c"]="172.31.30.0/24 us-east-1c"
)
declare -A SUBNET_IDS

for SNAME in "${!SUBNETS[@]}"; do
  read -r SCIDR SAZ <<< "${SUBNETS[$SNAME]}"
  SID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=cidr-block,Values=${SCIDR}" --region "${AWS_REGION}" --query "Subnets[0].SubnetId" --output text)
  if [[ "${SID}" == "None" || -z "${SID}" ]]; then
    echo "[+] Creating subnet ${SNAME} (${SCIDR}) in ${SAZ}..."
    SID=$(aws ec2 create-subnet --vpc-id "${VPC_ID}" --cidr-block "${SCIDR}" --availability-zone "${SAZ}" --region "${AWS_REGION}" --query "Subnet.SubnetId" --output text)
    aws ec2 create-tags --resources "${SID}" --tags "Key=Name,Value=${SNAME}" --region "${AWS_REGION}"
    aws ec2 modify-subnet-attribute --subnet-id "${SID}" --map-public-ip-on-launch --region "${AWS_REGION}"
  fi
  SUBNET_IDS["$SNAME"]="${SID}"
done

# Route Table
RT_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=cluster-public-rt" --region "${AWS_REGION}" --query "RouteTables[0].RouteTableId" --output text)
if [[ "${RT_ID}" == "None" || -z "${RT_ID}" ]]; then
  RT_ID=$(aws ec2 create-route-table --vpc-id "${VPC_ID}" --region "${AWS_REGION}" --query "RouteTable.RouteTableId" --output text)
  aws ec2 create-tags --resources "${RT_ID}" --tags "Key=Name,Value=cluster-public-rt" --region "${AWS_REGION}"
  aws ec2 create-route --route-table-id "${RT_ID}" --destination-cidr-block "0.0.0.0/0" --gateway-id "${IGW_ID}" --region "${AWS_REGION}"
  for SID in "${SUBNET_IDS[@]}"; do
    aws ec2 associate-route-table --subnet-id "${SID}" --route-table-id "${RT_ID}" --region "${AWS_REGION}" || true
  done
fi

# 6. Security Group
SG_ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=cluster-sg" --region "${AWS_REGION}" --query "SecurityGroups[0].GroupId" --output text)
if [[ "${SG_ID}" == "None" || -z "${SG_ID}" ]]; then
  echo "[+] Creating Security Group cluster-sg..."
  SG_ID=$(aws ec2 create-security-group --group-name "cluster-sg" --description "Cluster Security Group" --vpc-id "${VPC_ID}" --region "${AWS_REGION}" --query "GroupId" --output text)
  aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" --protocol tcp --port 22 --cidr "0.0.0.0/0" --region "${AWS_REGION}"
  aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" --protocol tcp --port 80 --cidr "0.0.0.0/0" --region "${AWS_REGION}"
  aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" --protocol tcp --port 443 --cidr "0.0.0.0/0" --region "${AWS_REGION}"
  aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" --protocol tcp --port 3080 --cidr "0.0.0.0/0" --region "${AWS_REGION}"
  aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" --protocol tcp --port 3023 --cidr "0.0.0.0/0" --region "${AWS_REGION}"
  aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" --protocol tcp --port 3024 --cidr "0.0.0.0/0" --region "${AWS_REGION}"
  aws ec2 authorize-security-group-ingress --group-id "${SG_ID}" --protocol -1 --cidr "${VPC_CIDR}" --region "${AWS_REGION}"
fi

# 7. Launch Instances
declare -A INSTANCES=(
  ["proxy-01"]="cluster-subnet-1a 172.31.10.10 proxy"
  ["proxy-02"]="cluster-subnet-1b 172.31.20.10 proxy"
  ["proxy-03"]="cluster-subnet-1c 172.31.30.10 proxy"
  ["web-01"]="cluster-subnet-1a 172.31.10.11 webserver"
  ["web-02"]="cluster-subnet-1b 172.31.20.11 webserver"
  ["web-03"]="cluster-subnet-1c 172.31.30.11 webserver"
  ["monitoring-01"]="cluster-subnet-1a 172.31.10.50 monitoring"
  ["teleport-01"]="cluster-subnet-1a 172.31.10.60 teleport"
)

for NAME in "${!INSTANCES[@]}"; do
  read -r SUBNET_KEY PRIV_IP ROLE <<< "${INSTANCES[$NAME]}"
  SID="${SUBNET_IDS[$SUBNET_KEY]}"
  EXISTING=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${NAME}" "Name=instance-state-name,Values=running,pending" --region "${AWS_REGION}" --query "Reservations[0].Instances[0].InstanceId" --output text)
  if [[ "${EXISTING}" == "None" || -z "${EXISTING}" ]]; then
    echo "  -> Launching ${NAME} (${PRIV_IP})..."
    aws ec2 run-instances \
      --image-id "${AMI_ID}" \
      --instance-type "${INSTANCE_TYPE}" \
      --key-name "${KEY_NAME}" \
      --subnet-id "${SID}" \
      --private-ip-address "${PRIV_IP}" \
      --security-group-ids "${SG_ID}" \
      --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":30,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME}},{Key=Cluster,Value=headless-ubuntu},{Key=Role,Value=${ROLE}}]" \
      --region "${AWS_REGION}" > /dev/null
  else
    echo "  [✓] Instance ${NAME} already running (${EXISTING})."
  fi
done

echo "[✓] AWS EC2 cluster provisioned successfully!"
