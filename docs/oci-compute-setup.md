# Oracle Cloud Infrastructure (OCI) Quickstart & Provisioning Guide

This step-by-step guide is designed for new users deploying this high-availability suite onto **Oracle Cloud Infrastructure (OCI)**. It covers installing and configuring the OCI CLI, authenticating via API signing keys, provisioning VCN networking, regional subnets, and compute instances across Fault Domains via Ansible playbooks, and running the primary cluster configuration.

---

## 1. High-Level OCI Architecture

On OCI, the architecture distributes frontend HAProxy nodes across distinct **Fault Domains** (`FAULT-DOMAIN-1`, `FAULT-DOMAIN-2`, `FAULT-DOMAIN-3`) within an Availability Domain behind an OCI Network Load Balancer (NLB):

```
                        Internet / Visitors
                                 │
                                 ▼
           ┌───────────────────────────────────────────┐
           │         OCI Network Load Balancer         │
           │       (TCP Ports 80 and 443 NLB)          │
           └─────────────────────┬─────────────────────┘
                                 │
          ┌──────────────────────┼──────────────────────┐
          ▼                      ▼                      ▼
┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
│     proxy-01      │  │     proxy-02      │  │     proxy-03      │
│  FAULT-DOMAIN-1   │  │  FAULT-DOMAIN-2   │  │  FAULT-DOMAIN-3   │
│     10.0.1.10     │  │     10.0.1.20     │  │     10.0.1.30     │
└─────────┬─────────┘  └─────────┬─────────┘  └─────────┬─────────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │ (VCN Subnet 10.0.1.0/24)
          ┌──────────────────────┼──────────────────────┐
          ▼                      ▼                      ▼
┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
│      web-01       │  │      web-02       │  │      web-03       │
│  FAULT-DOMAIN-1   │  │  FAULT-DOMAIN-2   │  │  FAULT-DOMAIN-3   │
│     10.0.1.11     │  │     10.0.1.21     │  │     10.0.1.31     │
│ web1.example.com  │  │ web2.example.com  │  │ web3.example.com  │
└─────────┬─────────┘  └─────────┬─────────┘  └─────────┬─────────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    ▼                         ▼
          ┌───────────────────┐     ┌───────────────────┐
          │   monitoring-01   │     │    teleport-01    │
          │     10.0.1.50     │     │     10.0.1.60     │
          │   (Prometheus)    │     │  (Auth & Proxy)   │
          └───────────────────┘     └───────────────────┘
```

---

## 2. Installing the OCI CLI

Install the official OCI CLI on your local workstation:

### Linux (Ubuntu / Debian)
```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

### macOS
```bash
brew install oci-cli
```

### Windows
Run in PowerShell as Administrator:
```powershell
Set-ExecutionPolicy RemoteSigned
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.ps1'))"
```

### Verify Installation
```bash
oci --version
```

---

## 3. Authenticating with OCI

### Step 3.1: Run Interactive Setup
Execute `oci setup config` to generate your API keys and configuration file (`~/.oci/config`):
```bash
oci setup config
```
Prompts will ask for:
- **User OCID**: Find under *Profile → User Settings* in OCI Console.
- **Tenancy OCID**: Find under *Administration → Tenancy Details*.
- **Region**: e.g., `us-ashburn-1` or `us-phoenix-1`.
- **Generate API Signing Key Pair**: Enter `Y`.

### Step 3.2: Upload Public API Key to OCI Console
1. Print your public key:
   ```bash
   cat ~/.oci/oci_api_key_public.pem
   ```
2. In the OCI Console, navigate to **Identity → Users → User Details → API Keys → Add API Key**.
3. Paste the contents of `oci_api_key_public.pem` and click **Add**.

### Step 3.3: Verify Authentication
```bash
oci os ns get
```

---

## 4. SSH Key Setup for Compute Instances

```bash
# Generate a modern ED25519 key pair:
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "ubuntu"
```

---

## 5. Provisioning OCI Infrastructure with Ansible

The suite provides complete OCI provisioning resources in `examples/provisioning/`:

- [examples/provisioning/vars_oci.yml](../examples/provisioning/vars_oci.yml)
- [examples/provisioning/provision_oci.yml](../examples/provisioning/provision_oci.yml)
- [examples/provisioning/deprovision_oci.yml](../examples/provisioning/deprovision_oci.yml)

### Step 5.1: Configure Variables
Edit `examples/provisioning/vars_oci.yml` with your Compartment OCID:
```yaml
oci_compartment_id: "ocid1.compartment.oc1..your_compartment_ocid"
oci_region: "us-ashburn-1"
```

### Step 5.2: Run the Playbook
```bash
ansible-playbook examples/provisioning/provision_oci.yml
```

### What This Playbook Creates:
1. **Custom VCN (`cluster-vcn`)**: CIDR `10.0.0.0/16`.
2. **Internet Gateway & Default Route**.
3. **Regional Subnet (`cluster-subnet`)**: CIDR `10.0.1.0/24`.
4. **Security List**: Ingress for SSH (22), HTTP (80), HTTPS (443), Teleport (3080/3023/3024), and internal VCN communication.
5. **8 Ubuntu 22.04 LTS Compute Instances**:
   - `proxy-01` (`FAULT-DOMAIN-1`, `10.0.1.10`)
   - `proxy-02` (`FAULT-DOMAIN-2`, `10.0.1.20`)
   - `proxy-03` (`FAULT-DOMAIN-3`, `10.0.1.30`)
   - `web-01` (`FAULT-DOMAIN-1`, `10.0.1.11`, FQDN: `web1.example.com`)
   - `web-02` (`FAULT-DOMAIN-2`, `10.0.1.21`, FQDN: `web2.example.com`)
   - `web-03` (`FAULT-DOMAIN-3`, `10.0.1.31`, FQDN: `web3.example.com`)
   - `monitoring-01` (`FAULT-DOMAIN-1`, `10.0.1.50`, Prometheus)
   - `teleport-01` (`FAULT-DOMAIN-1`, `10.0.1.60`, Teleport Auth/Proxy)
6. **Inventory Generation**: Updates `examples/inventories/inventory.oci.ini`.

---

## 6. Alternative: Provisioning via OCI CLI Shell Script

If you prefer provisioning directly with `oci` shell commands:

```bash
export OCI_COMPARTMENT_ID="ocid1.compartment.oc1..your_ocid"
./examples/provisioning/create_oci_instances.sh
```

---

## 7. Deploying the Cluster Suite

### Step 7.1: Test Node Connectivity
```bash
ansible -i examples/inventories/inventory.oci.ini -m ping all
```

### Step 7.2: Run Syntax Check
```bash
ansible-playbook -i examples/inventories/inventory.oci.ini playbook.yml --syntax-check
```

### Step 7.3: Execute Full Cluster Provisioning
```bash
ansible-playbook -i examples/inventories/inventory.oci.ini playbook.yml
```

---

## 8. Creating the OCI Network Load Balancer (NLB)

```bash
# 1. Create OCI Network Load Balancer:
oci nlb network-load-balancer create \
  --compartment-id "${OCI_COMPARTMENT_ID}" \
  --display-name "cluster-nlb" \
  --subnet-id "${SUBNET_ID}" \
  --is-private false

# 2. Add backend sets and listeners for TCP 80 & 443 with proxy backends.
```

---

## 9. Teardown & Resource Cleanup

```bash
# Using Ansible:
ansible-playbook examples/provisioning/deprovision_oci.yml

# Or using shell script:
./examples/provisioning/delete_oci_instances.sh
```
