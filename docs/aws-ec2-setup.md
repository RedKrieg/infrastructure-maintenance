# Amazon Web Services (AWS) EC2 Quickstart & Provisioning Guide

This step-by-step guide is designed for new users deploying this high-availability suite onto **Amazon Web Services (AWS) EC2**. It covers installing and configuring the AWS CLI, provisioning the custom VPC, subnets across Availability Zones, security groups, and EC2 virtual machines via Ansible playbooks, and running the primary cluster configuration.

---

## 1. High-Level AWS Architecture

On AWS, the architecture distributes frontend HAProxy nodes across distinct Availability Zones (`us-east-1a`, `us-east-1b`, `us-east-1c`) behind an AWS Network Load Balancer (NLB) with cross-zone load balancing enabled:

```
                          Internet / Visitors
                                   │
                                   ▼
             ┌───────────────────────────────────────────┐
             │         AWS Network Load Balancer         │
             │     (TCP 80 and 443 Cross-Zone NLB)       │
             └─────────────────────┬─────────────────────┘
                                   │
                  ┌────────────────┼────────────────┐
                  ▼                ▼                ▼
         ┌────────────────┐┌────────────────┐┌────────────────┐
         │    proxy-01    ││    proxy-02    ││    proxy-03    │
         │  (us-east-1a)  ││  (us-east-1b)  ││  (us-east-1c)  │
         │  172.31.10.10  ││  172.31.20.10  ││  172.31.30.10  │
         └────────┬───────┘└────────┬───────┘└────────┬───────┘
                  │                 │                 │
                  └─────────────────┼─────────────────┘
                                    │ (VPC Subnets 172.31.0.0/16)
                  ┌─────────────────┼─────────────────┐
                  ▼                 ▼                 ▼
         ┌────────────────┐┌────────────────┐┌────────────────┐
         │     web-01     ││     web-02     ││     web-03     │
         │  (us-east-1a)  ││  (us-east-1b)  ││  (us-east-1c)  │
         │  172.31.10.11  ││  172.31.20.11  ││  172.31.30.11  │
         │web1.example.com││web2.example.com││web3.example.com│
         └────────────────┘└────────────────┘└────────────────┘
                  │
         ┌────────┴────────┐
         ▼                 ▼
  ┌──────────────┐  ┌──────────────┐
  │monitoring-01 │  │ teleport-01  │
  │ 172.31.10.50 │  │ 172.31.10.60 │
  │(Prometheus)  │  │(Auth & Proxy)│
  └──────────────┘  └──────────────┘
```

---

## 2. Installing the AWS CLI

Install the official AWS CLI v2 on your control workstation:

### Linux (Ubuntu / Debian / RHEL)
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt-get install -y unzip
unzip -q awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip
```

### macOS
```bash
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /
rm AWSCLIV2.pkg
```
Or via Homebrew:
```bash
brew install awscli
```

### Windows
Download and execute the official [AWS CLI MSI Installer](https://awscli.amazonaws.com/AWSCLIV2.msi) or via winget:
```powershell
winget install Amazon.AWSCLI
```

### Verify Installation
```bash
aws --version
```

---

## 3. Authenticating with AWS

### Step 3.1: Configure Credentials
Run `aws configure` to set your credentials and preferred region:
```bash
aws configure
```
Prompt responses:
- **AWS Access Key ID**: `YOUR_ACCESS_KEY_ID`
- **AWS Secret Access Key**: `YOUR_SECRET_ACCESS_KEY`
- **Default region name**: `us-east-1`
- **Default output format**: `json`

*(Alternatively, if your organization uses AWS IAM Identity Center / SSO, run `aws configure sso`.)*

### Step 3.2: Verify Caller Identity
```bash
aws sts get-caller-identity
```

---

## 4. SSH Key Setup for EC2 Instances

```bash
# Generate a modern ED25519 key pair if you do not already have one:
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "ubuntu"

# Import public key to AWS EC2:
aws ec2 import-key-pair \
  --key-name "cluster-key" \
  --public-key-material "fileb://${HOME}/.ssh/id_ed25519.pub" \
  --region us-east-1
```

---

## 5. Preparing the Local Ansible Environment

Install `boto3` (AWS Python SDK) and the Ansible collection:

```bash
pip install boto3 botocore
ansible-galaxy collection install amazon.aws
```

---

## 6. Provisioning EC2 Infrastructure with Ansible

The suite provides a complete AWS provisioning playbook in `examples/provisioning/`:

- [examples/provisioning/vars_aws.yml](../examples/provisioning/vars_aws.yml)
- [examples/provisioning/provision_aws.yml](../examples/provisioning/provision_aws.yml)
- [examples/provisioning/deprovision_aws.yml](../examples/provisioning/deprovision_aws.yml)

### Step 6.1: Run the Playbook
```bash
ansible-playbook examples/provisioning/provision_aws.yml
```

### What This Playbook Creates:
1. **Custom VPC (`cluster-vpc`)**: `172.31.0.0/16` with DNS hostnames enabled.
2. **Multi-AZ Subnets**:
   - `cluster-subnet-1a` (`172.31.10.0/24`, `us-east-1a`)
   - `cluster-subnet-1b` (`172.31.20.0/24`, `us-east-1b`)
   - `cluster-subnet-1c` (`172.31.30.0/24`, `us-east-1c`)
3. **Internet Gateway & Route Table**: Configured with default `0.0.0.0/0` route.
4. **Security Group (`cluster-vpc-sg`)**: Ingress for SSH (22), HTTP (80), HTTPS (443), Teleport (3080/3023/3024), and internal VPC mesh.
5. **8 Canonical Ubuntu 22.04 LTS EC2 Instances**:
   - `proxy-01` (`us-east-1a`, `172.31.10.10`)
   - `proxy-02` (`us-east-1b`, `172.31.20.10`)
   - `proxy-03` (`us-east-1c`, `172.31.30.10`)
   - `web-01` (`us-east-1a`, `172.31.10.11`, FQDN: `web1.example.com`)
   - `web-02` (`us-east-1b`, `172.31.20.11`, FQDN: `web2.example.com`)
   - `web-03` (`us-east-1c`, `172.31.30.11`, FQDN: `web3.example.com`)
   - `monitoring-01` (`us-east-1a`, `172.31.10.50`, Prometheus)
   - `teleport-01` (`us-east-1a`, `172.31.10.60`, Teleport Auth/Proxy)
6. **Inventory Generation**: Updates `examples/inventories/inventory.aws.ini`.

---

## 7. Alternative: Provisioning via AWS CLI Shell Script

If you prefer provisioning directly with `aws` shell commands:

```bash
export AWS_REGION="us-east-1"
./examples/provisioning/create_aws_instances.sh
```

---

## 8. Deploying the Cluster Suite

### Step 8.1: Test Node Connectivity
```bash
ansible -i examples/inventories/inventory.aws.ini -m ping all
```

### Step 8.2: Run Syntax Check
```bash
ansible-playbook -i examples/inventories/inventory.aws.ini playbook.yml --syntax-check
```

### Step 8.3: Execute Full Cluster Provisioning
```bash
ansible-playbook -i examples/inventories/inventory.aws.ini playbook.yml
```

---

## 9. Creating the AWS Network Load Balancer (NLB)

To distribute public traffic across the proxies with cross-zone routing:

```bash
# 1. Look up Subnet IDs:
SUBNET_1A=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=cluster-subnet-1a" --query "Subnets[0].SubnetId" --output text)
SUBNET_1B=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=cluster-subnet-1b" --query "Subnets[0].SubnetId" --output text)
SUBNET_1C=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=cluster-subnet-1c" --query "Subnets[0].SubnetId" --output text)
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=cluster-vpc" --query "Vpcs[0].VpcId" --output text)

# 2. Look up Proxy Instance IDs:
P1=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=proxy-01" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)
P2=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=proxy-02" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)
P3=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=proxy-03" "Name=instance-state-name,Values=running" --query "Reservations[0].Instances[0].InstanceId" --output text)

# 3. Create Network Load Balancer:
NLB_ARN=$(aws elbv2 create-load-balancer \
  --name "cluster-nlb" \
  --type network \
  --subnets "${SUBNET_1A}" "${SUBNET_1B}" "${SUBNET_1C}" \
  --query "LoadBalancers[0].LoadBalancerArn" --output text)

# 4. Create Target Groups for TCP 80 & 443:
TG_80=$(aws elbv2 create-target-group --name "tg-proxies-80" --protocol TCP --port 80 --vpc-id "${VPC_ID}" --query "TargetGroups[0].TargetGroupArn" --output text)
TG_443=$(aws elbv2 create-target-group --name "tg-proxies-443" --protocol TCP --port 443 --vpc-id "${VPC_ID}" --query "TargetGroups[0].TargetGroupArn" --output text)

# 5. Register Proxies to Target Groups:
aws elbv2 register-targets --target-group-arn "${TG_80}" --targets Id="${P1}" Id="${P2}" Id="${P3}"
aws elbv2 register-targets --target-group-arn "${TG_443}" --targets Id="${P1}" Id="${P2}" Id="${P3}"

# 6. Create Listeners:
aws elbv2 create-listener --load-balancer-arn "${NLB_ARN}" --protocol TCP --port 80 --default-actions Type=forward,TargetGroupArn="${TG_80}"
aws elbv2 create-listener --load-balancer-arn "${NLB_ARN}" --protocol TCP --port 443 --default-actions Type=forward,TargetGroupArn="${TG_443}"
```

---

## 10. Teardown & Resource Cleanup

```bash
# Using Ansible:
ansible-playbook examples/provisioning/deprovision_aws.yml

# Or using shell script:
./examples/provisioning/delete_aws_instances.sh
```
