# Microsoft Azure Quickstart & Provisioning Guide

This step-by-step guide is designed for new users deploying this high-availability suite onto **Microsoft Azure**. It covers installing and authenticating the Azure CLI (`az`), provisioning Resource Groups, VNets, Subnets across Availability Zones, Network Security Groups, and Ubuntu virtual machines via Ansible playbooks, and running the primary cluster configuration.

---

## 1. High-Level Azure Architecture

On Microsoft Azure, the architecture distributes frontend HAProxy nodes across distinct **Availability Zones** (`1`, `2`, `3`) behind an Azure Standard Load Balancer with Layer 4 TCP load balancing rules:

```
                          Internet / Visitors
                                   │
                                   ▼
             ┌───────────────────────────────────────────┐
             │       Azure Standard Load Balancer        │
             │       (TCP Ports 80 and 443 Rules)        │
             └─────────────────────┬─────────────────────┘
                                   │
                  ┌────────────────┼────────────────┐
                  ▼                ▼                ▼
         ┌────────────────┐┌────────────────┐┌────────────────┐
         │    proxy-01    ││    proxy-02    ││    proxy-03    │
         │ Availability 1 ││ Availability 2 ││ Availability 3 │
         │  10.240.1.10   ││  10.240.1.20   ││  10.240.1.30   │
         └────────┬───────┘└────────┬───────┘└────────┬───────┘
                  │                 │                 │
                  └─────────────────┼─────────────────┘
                                    │ (VNet Subnet 10.240.1.0/24)
                  ┌─────────────────┼─────────────────┐
                  ▼                 ▼                 ▼
         ┌────────────────┐┌────────────────┐┌────────────────┐
         │     web-01     ││     web-02     ││     web-03     │
         │ Availability 1 ││ Availability 2 ││ Availability 3 │
         │  10.240.1.11   ││  10.240.1.21   ││  10.240.1.31   │
         │web1.example.com││web2.example.com││web3.example.com│
         └────────────────┘└────────────────┘└────────────────┘
                  │
         ┌────────┴────────┐
         ▼                 ▼
  ┌──────────────┐  ┌──────────────┐
  │monitoring-01 │  │ teleport-01  │
  │ 10.240.1.50  │  │ 10.240.1.60  │
  │(Prometheus)  │  │(Auth & Proxy)│
  └──────────────┘  └──────────────┘
```

---

## 2. Installing the Azure CLI (`az`)

Install the official Azure CLI on your local workstation:

### Linux (Ubuntu / Debian)
```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

### macOS
```bash
brew install azure-cli
```

### Windows
Run in PowerShell:
```powershell
winget install Microsoft.AzureCLI
```

### Verify Installation
```bash
az --version
```

---

## 3. Authenticating with Microsoft Azure

### Step 3.1: Interactive Browser Login
Authenticate with your Azure account:
```bash
az login
```

### Step 3.2: Select Subscription
If you have multiple Azure subscriptions, set your active subscription:
```bash
# List subscriptions:
az account list --output table

# Set active subscription:
az account set --subscription "YOUR_SUBSCRIPTION_ID_OR_NAME"
```

### Optional: Service Principal Authentication
For automated CI/CD pipelines:
```bash
az ad sp create-for-rbac --name "ansible-cluster-sp" --role Contributor --scopes /subscriptions/YOUR_SUBSCRIPTION_ID
```

---

## 4. SSH Key Setup for Azure VMs

```bash
# Generate a modern ED25519 key pair:
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "ubuntu"
```

---

## 5. Preparing the Local Ansible Environment

Install Azure Python SDK dependencies and the Ansible collection:

```bash
pip install azure-mgmt-compute azure-mgmt-network azure-mgmt-resource azure-identity
ansible-galaxy collection install azure.azcollection
```

---

## 6. Provisioning Azure Infrastructure with Ansible

The suite provides a complete Azure provisioning playbook in `examples/provisioning/`:

- [examples/provisioning/vars_azure.yml](../examples/provisioning/vars_azure.yml)
- [examples/provisioning/provision_azure.yml](../examples/provisioning/provision_azure.yml)
- [examples/provisioning/deprovision_azure.yml](../examples/provisioning/deprovision_azure.yml)

### Step 6.1: Run the Playbook
```bash
ansible-playbook examples/provisioning/provision_azure.yml
```

### What This Playbook Creates:
1. **Resource Group (`cluster-rg`)**: In region `eastus`.
2. **Virtual Network & Subnet**: `cluster-vnet` (`10.240.0.0/16`) and `cluster-subnet` (`10.240.1.0/24`).
3. **Network Security Group (`cluster-nsg`)**: Ingress rules for SSH (22), HTTP (80), HTTPS (443), Teleport (3080/3023/3024), and internal VNet mesh.
4. **8 Ubuntu 22.04 LTS Virtual Machines**:
   - `proxy-01` (Zone `1`, `10.240.1.10`)
   - `proxy-02` (Zone `2`, `10.240.1.20`)
   - `proxy-03` (Zone `3`, `10.240.1.30`)
   - `web-01` (Zone `1`, `10.240.1.11`, FQDN: `web1.example.com`)
   - `web-02` (Zone `2`, `10.240.1.21`, FQDN: `web2.example.com`)
   - `web-03` (Zone `3`, `10.240.1.31`, FQDN: `web3.example.com`)
   - `monitoring-01` (Zone `1`, `10.240.1.50`, Prometheus)
   - `teleport-01` (Zone `1`, `10.240.1.60`, Teleport Auth/Proxy)
5. **Inventory Generation**: Updates `examples/inventories/inventory.azure.ini`.

---

## 7. Alternative: Provisioning via Azure CLI Shell Script

If you prefer provisioning directly with `az` shell commands:

```bash
export AZURE_RG="cluster-rg"
export AZURE_LOCATION="eastus"
./examples/provisioning/create_azure_instances.sh
```

---

## 8. Deploying the Cluster Suite

### Step 8.1: Test Node Connectivity
```bash
ansible -i examples/inventories/inventory.azure.ini -m ping all
```

### Step 8.2: Run Syntax Check
```bash
ansible-playbook -i examples/inventories/inventory.azure.ini playbook.yml --syntax-check
```

### Step 8.3: Execute Full Cluster Provisioning
```bash
ansible-playbook -i examples/inventories/inventory.azure.ini playbook.yml
```

---

## 9. Creating the Azure Standard Load Balancer

```bash
# 1. Create a Standard Public IP for the Load Balancer:
az network public-ip create \
  --resource-group cluster-rg \
  --name cluster-lb-pip \
  --sku Standard

# 2. Create the Load Balancer:
az network lb create \
  --resource-group cluster-rg \
  --name cluster-lb \
  --sku Standard \
  --public-ip-address cluster-lb-pip \
  --frontend-ip-name lb-frontend \
  --backend-pool-name proxy-pool

# 3. Create Health Probe on Port 80:
az network lb probe create \
  --resource-group cluster-rg \
  --lb-name cluster-lb \
  --name tcp80-probe \
  --protocol Tcp \
  --port 80

# 4. Create Load Balancing Rules for TCP 80 & 443:
az network lb rule create \
  --resource-group cluster-rg \
  --lb-name cluster-lb \
  --name lb-rule-http \
  --protocol Tcp \
  --frontend-port 80 \
  --backend-port 80 \
  --frontend-ip-name lb-frontend \
  --backend-pool-name proxy-pool \
  --probe-name tcp80-probe

az network lb rule create \
  --resource-group cluster-rg \
  --lb-name cluster-lb \
  --name lb-rule-https \
  --protocol Tcp \
  --frontend-port 443 \
  --backend-port 443 \
  --frontend-ip-name lb-frontend \
  --backend-pool-name proxy-pool \
  --probe-name tcp80-probe
```

---

## 10. Teardown & Resource Cleanup

```bash
# Using Ansible:
ansible-playbook examples/provisioning/deprovision_azure.yml

# Or using shell script:
./examples/provisioning/delete_azure_instances.sh
```
