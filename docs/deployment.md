# Deployment & Inventory Configuration Guide

This guide details inventory design, dynamic host-to-FQDN mapping, cloud-specific setups, and Ansible execution commands.

---

## 1. Inventory & Dynamic 1:1 Mapping

The only setting required per webserver is **`external_fqdn`** in your inventory file:

```ini
[proxies]
proxy-01 ansible_host=10.0.1.10
proxy-02 ansible_host=10.0.1.20
proxy-03 ansible_host=10.0.1.30

[webservers]
web-01 ansible_host=10.0.1.11 external_fqdn=web1.example.com
web-02 ansible_host=10.0.1.12 external_fqdn=web2.example.com
web-03 ansible_host=10.0.1.13 external_fqdn=web3.example.com

[monitoring]
monitoring-01 ansible_host=10.0.1.50

[teleport_servers]
teleport-01 ansible_host=10.0.1.60

[headless_nodes:children]
proxies
webservers
monitoring
teleport_servers
```

### Dynamic Routing Behavior
HAProxy on all proxies dynamically generates:
- `web1.example.com` ➔ routes to `10.0.1.11:80`
- `web2.example.com` ➔ routes to `10.0.1.12:80`
- `web3.example.com` ➔ routes to `10.0.1.13:80`
- Unmapped hostnames / IPs ➔ **404 Not Found** (via Nginx default generic 404 server)

---

## 2. Cloud Inventory Templates

Ready-to-use cloud-specific inventory templates are available in the `examples/inventories/` directory:

| Environment | Inventory Path | Architecture Highlights | Setup Guide |
| :--- | :--- | :--- | :--- |
| **AWS EC2** | [examples/inventories/inventory.aws.ini](../examples/inventories/inventory.aws.ini) | Multi-AZ placement (`us-east-1a`, `1b`, `1c`), AWS Network Load Balancer (NLB) fronting proxies. | [AWS EC2 Setup Guide](aws-ec2-setup.md) |
| **Google Cloud (GCP)** | [examples/inventories/inventory.gcp.ini](../examples/inventories/inventory.gcp.ini) | Multi-zone Compute Engine (`us-central1-a`, `1-b`, `1-c`), Regional Passthrough Network Load Balancer. | [GCP Compute Setup Guide](gcp-compute-setup.md) |
| **Microsoft Azure** | [examples/inventories/inventory.azure.ini](../examples/inventories/inventory.azure.ini) | Multi-zone Azure VMs (`1`, `2`, `3`), Azure Standard Load Balancer (TCP 80/443). | [Azure Setup Guide](azure-setup.md) |
| **Oracle Cloud (OCI)** | [examples/inventories/inventory.oci.ini](../examples/inventories/inventory.oci.ini) | Multi-fault-domain Compute (`FD-1`, `FD-2`, `FD-3`), OCI Network Load Balancer. | [OCI Compute Setup Guide](oci-compute-setup.md) |
| **OpenStack** | [examples/inventories/inventory.openstack.ini](../examples/inventories/inventory.openstack.ini) | Nova anti-affinity server groups across physical hypervisors, Octavia TCP listener. | [OpenStack Setup Guide](openstack-setup.md) |
| **OCI / Bare Metal** | [inventory.ini](../inventory.ini) | Standard RFC 1918 multi-rack or fault-domain deployment. | — |

> [!TIP]
> Comprehensive quickstart and automated VM provisioning guides are available for each platform:
> - **[AWS EC2 Setup Guide](aws-ec2-setup.md)** (`examples/provisioning/provision_aws.yml`)
> - **[GCP Compute Setup Guide](gcp-compute-setup.md)** (`examples/provisioning/provision_gcp.yml`)
> - **[Azure Setup Guide](azure-setup.md)** (`examples/provisioning/provision_azure.yml`)
> - **[OCI Compute Setup Guide](oci-compute-setup.md)** (`examples/provisioning/provision_oci.yml`)
> - **[OpenStack Setup Guide](openstack-setup.md)** (`examples/provisioning/provision_openstack.yml`)

---

## 3. How to Run

### Pre-Flight Syntax Check
Before running across your fleet, validate your playbooks and inventory:
```bash
ansible-playbook -i inventory.ini playbook.yml --syntax-check
```

### Full Fleet Provisioning
```bash
# Using the default bare-metal / RFC 1918 inventory:
ansible-playbook -i inventory.ini playbook.yml

# Or deploying to AWS EC2:
ansible-playbook -i examples/inventories/inventory.aws.ini playbook.yml

# Or deploying to GCP Compute Engine:
ansible-playbook -i examples/inventories/inventory.gcp.ini playbook.yml

# Or deploying to Microsoft Azure:
ansible-playbook -i examples/inventories/inventory.azure.ini playbook.yml

# Or deploying to Oracle Cloud Infrastructure (OCI):
ansible-playbook -i examples/inventories/inventory.oci.ini playbook.yml

# Or deploying to OpenStack:
ansible-playbook -i examples/inventories/inventory.openstack.ini playbook.yml
```

---

## 4. Targeted Execution Using Tags

Use Ansible tags to target specific layers or roles without running the entire playbook:

| Tag | Purpose | Description |
| :--- | :--- | :--- |
| `proxy` | HAProxy Ingress | Deploys HAProxy packages, firewall rules, stats whitelists, HTTP/2 & rate limit configs. |
| `certs` | SSL Synchronization | Triggers primary issuance, cert distribution, standby watchdogs, and reconciliation. |
| `webserver` | Backend Webservers | Installs Nginx, generic 404 handler, and virtual host blocks for assigned FQDNs. |
| `monitoring` | Prometheus | Provisions the Prometheus monitoring server and scrapes proxies. |
| `teleport_server` | Teleport Auth & Proxy | Sets up Teleport Auth/Proxy service, joins tokens, RBAC roles, and users. |
| `teleport_node` | Teleport SSH Nodes | Installs Teleport Node service and connects reverse tunnels on cluster hosts. |
| `logging` | Centralized Logging | Deploys central rsyslog ingestion server on monitoring host and shippers on nodes. |
| `users` | User Accounts | Manages user creation, dotfiles, shell helpers, and Python venv tools. |

### Tagged Command Examples
```bash
# Provision or update HAProxy load balancers only:
ansible-playbook -i inventory.ini playbook.yml --tags proxy

# Synchronize certificates only:
ansible-playbook -i inventory.ini playbook.yml --tags certs

# Provision or update backend webservers only:
ansible-playbook -i inventory.ini playbook.yml --tags webserver

# Provision or update Prometheus monitoring server only:
ansible-playbook -i inventory.ini playbook.yml --tags monitoring

# Provision or update Centralized Logging only:
ansible-playbook -i inventory.ini playbook.yml --tags logging

# Provision or update Teleport Auth/Proxy server only:
ansible-playbook -i inventory.ini playbook.yml --tags teleport_server

# Provision or update Teleport SSH node services only:
ansible-playbook -i inventory.ini playbook.yml --tags teleport_node

# Update user accounts, helper scripts, and dotfiles only:
ansible-playbook -i inventory.ini playbook.yml --tags users
```

---

## 5. Dynamic Cloud Inventory Plugins

Instead of static INI inventories, auto-discover cloud instances using tags:

```bash
# AWS EC2 Dynamic Discovery:
ansible-playbook -i examples/inventories/aws_ec2.yml playbook.yml

# Google Cloud (GCP) Dynamic Discovery:
ansible-playbook -i examples/inventories/gcp_compute.yml playbook.yml

# Microsoft Azure Dynamic Discovery:
ansible-playbook -i examples/inventories/azure_rm.yml playbook.yml
```

For full setup instructions, see the [Dynamic Inventory Plugins Guide](dynamic-inventory.md).

---

## 6. Running with Ansible Vault

When `group_vars/all/vault.yml` is encrypted, pass your vault passphrase or password file:

```bash
# Using a local password file:
ansible-playbook -i inventory.ini playbook.yml --vault-password-file ~/.vault_pass

# Or prompt interactively:
ansible-playbook -i inventory.ini playbook.yml --ask-vault-pass
```

For full details, see the [Ansible Vault Secrets Management Guide](security-vault.md).

---

## 7. Local Test Suite & Linting

Run automated syntax validation across all inventories, provisioning playbooks, and shell scripts:

```bash
./tests/run_tests.sh
```
