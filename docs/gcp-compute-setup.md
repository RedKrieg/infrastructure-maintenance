# Google Cloud Platform (GCP) Compute Engine Quickstart & Provisioning Guide

This step-by-step guide is designed for new users deploying this high-availability suite onto **Google Cloud Platform (GCP) Compute Engine**. It covers installing and authenticating the `gcloud` CLI, provisioning the custom VPC network, firewalls, and Compute Engine virtual machines via Ansible playbooks, and running the primary cluster configuration.

---

## 1. High-Level GCP Topology

On GCP, the architecture spans multiple Compute Engine zones within a single region (e.g., `us-central1-a`, `us-central1-b`, `us-central1-c`) to ensure cross-zone fault tolerance:

```
                          Internet / Visitors
                                   │
                                   ▼
             ┌───────────────────────────────────────────┐
             │   Regional External TCP Passthrough NLB   │
             │         (Ports 80 and 443 Forwarding)     │
             └─────────────────────┬─────────────────────┘
                                   │
                  ┌────────────────┼────────────────┐
                  ▼                ▼                ▼
         ┌────────────────┐┌────────────────┐┌────────────────┐
         │    proxy-01    ││    proxy-02    ││    proxy-03    │
         │ (us-central1-a)││ (us-central1-b)││ (us-central1-c)│
         │  10.128.0.10   ││  10.128.0.20   ││  10.128.0.30   │
         └────────┬───────┘└────────┬───────┘└────────┬───────┘
                  │                 │                 │
                  └─────────────────┼─────────────────┘
                                    │ (Internal Subnet 10.128.0.0/20)
                  ┌─────────────────┼─────────────────┐
                  ▼                 ▼                 ▼
         ┌────────────────┐┌────────────────┐┌────────────────┐
         │     web-01     ││     web-02     ││     web-03     │
         │ (us-central1-a)││ (us-central1-b)││ (us-central1-c)│
         │  10.128.0.11   ││  10.128.0.21   ││  10.128.0.31   │
         │web1.example.com││web2.example.com││web3.example.com│
         └────────────────┘└────────────────┘└────────────────┘
                  │
         ┌────────┴────────┐
         ▼                 ▼
  ┌──────────────┐  ┌──────────────┐
  │monitoring-01 │  │ teleport-01  │
  │ 10.128.0.50  │  │ 10.128.0.60  │
  │(Prometheus)  │  │(Auth & Proxy)│
  └──────────────┘  └──────────────┘
```

---

## 2. Installing the Google Cloud SDK (`gcloud` CLI)

If you do not yet have the `gcloud` CLI installed on your local control workstation, follow the instructions for your operating system:

### Linux (Ubuntu / Debian)
```bash
# Update package list and install transport prerequisites
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates gnupg curl

# Import the Google Cloud public key
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

# Add the gcloud APT repository
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list

# Install the Google Cloud SDK
sudo apt-get update && sudo apt-get install -y google-cloud-cli
```

### macOS
Using [Homebrew](https://brew.sh/):
```bash
brew install --cask google-cloud-sdk
```

### Windows
Download and run the [Google Cloud CLI Installer](https://cloud.google.com/sdk/docs/install#windows) or use PowerShell:
```powershell
(New-Object Net.WebClient).DownloadFile("https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe", "$env:Temp\GoogleCloudSDKInstaller.exe")
& $env:Temp\GoogleCloudSDKInstaller.exe
```

### Verify Installation
```bash
gcloud --version
```

---

## 3. Authenticating with Google Cloud

### Step 3.1: Log in with User Credentials
Authenticate your user account with Google Cloud:
```bash
gcloud auth login
```
This command opens a browser window prompting you to sign in with your Google Cloud account and grant SDK permissions.

### Step 3.2: Configure Application Default Credentials (ADC)
Ansible's `google.cloud` modules authenticate using Google's Application Default Credentials library. Run:
```bash
gcloud auth application-default login
```
This generates credentials in `~/.config/gcloud/application_default_credentials.json`, which Ansible automatically discovers.

### Step 3.3: Set Default Project and Region
Configure your target GCP Project ID and preferred default compute region:
```bash
# List available projects
gcloud projects list

# Set active project
gcloud config set project YOUR_PROJECT_ID

# Set default region and zone
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a
```

### Step 3.4: Enable the Compute Engine API
Ensure the Compute Engine API is enabled in your project:
```bash
gcloud services enable compute.googleapis.com
```

### Optional: Service Account Authentication
For headless automation or CI/CD pipelines where interactive browser login is unavailable:
```bash
# Create service account
gcloud iam service-accounts create ansible-provisioner \
  --description="Ansible GCP Compute Provisioner" \
  --display-name="ansible-provisioner"

# Assign Compute Admin and Service Account User roles
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:ansible-provisioner@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/compute.admin"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:ansible-provisioner@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"

# Generate JSON service account key
gcloud iam service-accounts keys create ~/gcp-key.json \
  --iam-account="ansible-provisioner@YOUR_PROJECT_ID.iam.gserviceaccount.com"
```

---

## 4. SSH Key Setup for Compute Engine Instances

Compute Engine instances require an SSH public key to allow Ansible access as the `ubuntu` user:

```bash
# Generate a modern ED25519 SSH key pair if you do not already have one:
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "ubuntu"

# Register the public key in your GCP project's metadata so all new instances accept it:
gcloud compute project-info add-metadata \
  --metadata="ssh-keys=ubuntu:$(cat ~/.ssh/id_ed25519.pub)"
```

---

## 5. Preparing the Local Ansible Environment

Install the required Python client libraries and the Ansible collection:

```bash
# 1. Install Google Auth and Requests Python libraries
pip install google-auth requests

# 2. Install the google.cloud collection
ansible-galaxy collection install google.cloud
```

---

## 6. Provisioning the Infrastructure with Ansible

This repository includes a dedicated provisioning playbook and variable file located in `examples/provisioning/`:

- [examples/provisioning/vars_gcp.yml](../examples/provisioning/vars_gcp.yml)
- [examples/provisioning/provision_gcp.yml](../examples/provisioning/provision_gcp.yml)
- [examples/provisioning/deprovision_gcp.yml](../examples/provisioning/deprovision_gcp.yml)

### Step 6.1: Configure Variables
Edit `examples/provisioning/vars_gcp.yml` to specify your project ID and SSH key location:

```yaml
# In examples/provisioning/vars_gcp.yml:
gcp_project_id: "YOUR_PROJECT_ID"           # Set your GCP Project ID
gcp_region: "us-central1"
gcp_auth_kind: "application"                 # Uses Application Default Credentials
gcp_ssh_user: "ubuntu"
gcp_ssh_pub_key_file: "~/.ssh/id_ed25519.pub"
```

### Step 6.2: Run the Provisioning Playbook
Execute the playbook from your terminal:

```bash
ansible-playbook examples/provisioning/provision_gcp.yml
```

### What This Playbook Creates:
1. **Custom VPC Network (`cluster-vpc`)**: Configured with custom subnets (non-legacy).
2. **Regional Subnet (`cluster-subnet`)**: CIDR `10.128.0.0/20` in `us-central1`.
3. **Firewall Rules**:
   - `cluster-vpc-allow-ssh`: Port 22 from anywhere.
   - `cluster-vpc-allow-http-https`: Ports 80 and 443 to instances tagged `proxy`.
   - `cluster-vpc-allow-internal`: Full TCP/UDP/ICMP mesh within `10.128.0.0/20`.
   - `cluster-vpc-allow-teleport`: Ports 3080, 3023, and 3024 to instances tagged `teleport`.
4. **8 Compute Engine Instances**:
   - `proxy-01` (`us-central1-a`, IP `10.128.0.10`)
   - `proxy-02` (`us-central1-b`, IP `10.128.0.20`)
   - `proxy-03` (`us-central1-c`, IP `10.128.0.30`)
   - `web-01` (`us-central1-a`, IP `10.128.0.11`, FQDN `web1.example.com`)
   - `web-02` (`us-central1-b`, IP `10.128.0.21`, FQDN `web2.example.com`)
   - `web-03` (`us-central1-c`, IP `10.128.0.31`, FQDN `web3.example.com`)
   - `monitoring-01` (`us-central1-a`, IP `10.128.0.50`, Prometheus)
   - `teleport-01` (`us-central1-a`, IP `10.128.0.60`, Teleport Auth/Proxy)
5. **Inventory Generation**: Automatically generates `examples/inventories/inventory.gcp.ini` ready for immediate cluster deployment.

---

## 7. Alternative: Provisioning via CLI Shell Script

If you prefer provisioning directly with `gcloud` shell commands without installing Python libraries:

```bash
# Set your project ID:
export GCP_PROJECT_ID="YOUR_PROJECT_ID"
export GCP_REGION="us-central1"

# Execute the provisioning script:
./examples/provisioning/create_gcp_instances.sh
```

---

## 8. Verifying & Deploying the Cluster Suite

### Step 8.1: Test Node Connectivity
Verify that Ansible can connect to all instances:
```bash
ansible -i examples/inventories/inventory.gcp.ini -m ping all
```

### Step 8.2: Run Pre-Flight Syntax Check
```bash
ansible-playbook -i examples/inventories/inventory.gcp.ini playbook.yml --syntax-check
```

### Step 8.3: Execute Full Cluster Provisioning
Deploy the complete suite across your new GCP instances:
```bash
ansible-playbook -i examples/inventories/inventory.gcp.ini playbook.yml
```

This single command will:
- Harden all Ubuntu systems (kernel tuning, UFW, SSH `MaxAuthTries 10`).
- Configure HAProxy frontends with HTTP/2, security headers, HSTS, and rate limits.
- Issue and synchronize ACME SSL certificates across the proxies with rank-based succession.
- Deploy backend Nginx webservers with dynamic 1:1 FQDN routing and generic 404 fallbacks.
- Stand up the Prometheus monitoring server and configure scrape targets.
- Initialize Teleport Auth/Proxy and connect all cluster nodes via outbound reverse tunnels.

---

## 9. Creating the GCP Layer 4 Ingress Load Balancer

To distribute public traffic across `proxy-01`, `proxy-02`, and `proxy-03`, create a Regional External TCP Passthrough Network Load Balancer:

```bash
# 1. Create an unmanaged instance group for each zone:
gcloud compute instance-groups unmanaged create ig-proxies-a --zone=us-central1-a
gcloud compute instance-groups unmanaged create ig-proxies-b --zone=us-central1-b
gcloud compute instance-groups unmanaged create ig-proxies-c --zone=us-central1-c

# 2. Add proxies to their respective instance groups:
gcloud compute instance-groups unmanaged add-instances ig-proxies-a --zone=us-central1-a --instances=proxy-01
gcloud compute instance-groups unmanaged add-instances ig-proxies-b --zone=us-central1-b --instances=proxy-02
gcloud compute instance-groups unmanaged add-instances ig-proxies-c --zone=us-central1-c --instances=proxy-03

# 3. Create a health check monitoring port 80:
gcloud compute health-checks create tcp hc-proxy-tcp80 --port=80 --region=us-central1

# 4. Create the backend service with connection tracking:
gcloud compute backend-services create be-proxy-service \
  --protocol=TCP \
  --region=us-central1 \
  --health-checks=hc-proxy-tcp80 \
  --health-checks-region=us-central1

# 5. Attach the instance groups to the backend service:
gcloud compute backend-services add-backend be-proxy-service --region=us-central1 --instance-group=ig-proxies-a --instance-group-zone=us-central1-a
gcloud compute backend-services add-backend be-proxy-service --region=us-central1 --instance-group=ig-proxies-b --instance-group-zone=us-central1-b
gcloud compute backend-services add-backend be-proxy-service --region=us-central1 --instance-group=ig-proxies-c --instance-group-zone=us-central1-c

# 6. Reserve a static external IP address:
gcloud compute addresses create lb-proxy-ip --region=us-central1

# 7. Create forwarding rules for Port 80 and Port 443:
gcloud compute forwarding-rules create fr-proxy-tcp80 \
  --region=us-central1 \
  --ports=80 \
  --address=lb-proxy-ip \
  --backend-service=be-proxy-service

gcloud compute forwarding-rules create fr-proxy-tcp443 \
  --region=us-central1 \
  --ports=443 \
  --address=lb-proxy-ip \
  --backend-service=be-proxy-service
```

---

## 10. Teardown & Resource Cleanup

To delete all provisioned GCP resources when testing is finished:

```bash
# Using Ansible:
ansible-playbook examples/provisioning/deprovision_gcp.yml

# Or using the cleanup shell script:
./examples/provisioning/delete_gcp_instances.sh
```
