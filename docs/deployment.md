# Deployment & Inventory Configuration Guide

This guide details inventory design, dynamic host-to-FQDN mapping, cloud-specific setups, and Ansible execution commands.

---

## 1. Inventory & Backend Topologies

The infrastructure playbooks support both **Dedicated 1:1 Webservers** (multi-tenant isolation) and **Pooled N:1 Webservers** (clustered high availability), as well as a **Hybrid Architecture** combining both.

For an extensive architectural breakdown and operational comparison, see the [Backend Webserver Topologies Guide](backend-topologies.md).

### Scenario 1: Dedicated 1:1 Mapping (Multi-Tenant)
Each webserver specifies a unique **`external_fqdn`**:

```ini
[webservers]
web-alpha ansible_host=10.0.1.11 external_fqdn=alpha.example.com
web-beta  ansible_host=10.0.1.12 external_fqdn=beta.example.com
web-gamma ansible_host=10.0.1.13 external_fqdn=gamma.example.com
```
HAProxy routes `alpha.example.com` ➔ `10.0.1.11`, `beta.example.com` ➔ `10.0.1.12`, etc.

### Scenario 2: Pooled N:1 Clustered Mapping (High Availability)
Multiple webservers share the exact same **`external_fqdn`**:

```ini
[webservers]
web-01 ansible_host=10.0.1.21 external_fqdn=app.example.com
web-02 ansible_host=10.0.1.22 external_fqdn=app.example.com
web-03 ansible_host=10.0.1.23 external_fqdn=app.example.com
```
HAProxy pools all three servers under `be_app_example_com` with round-robin load balancing. When running `rolling_maintenance.yml`, nodes drain serially with zero downtime.

Example inventories are ready to use in `examples/topologies/`:
- [Scenario 1: Dedicated 1:1](../examples/topologies/scenario-1-unique-clients/README.md)
- [Scenario 2: Pooled N:1](../examples/topologies/scenario-2-pooled-webservers/README.md)
- [Scenario 3: Hybrid](../examples/topologies/scenario-3-hybrid/README.md)

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
> - **[AWS EC2 Setup Guide](aws-ec2-setup.md)** (`examples/provisioning/provision_aws.yml` & `provision_aws_rds_postgresql.yml`)
> - **[GCP Compute Setup Guide](gcp-compute-setup.md)** (`examples/provisioning/provision_gcp.yml` & `provision_gcp_cloudsql_postgresql.yml`)
> - **[Azure Setup Guide](azure-setup.md)** (`examples/provisioning/provision_azure.yml` & `provision_azure_postgresql.yml`)
> - **[OCI Compute Setup Guide](oci-compute-setup.md)** (`examples/provisioning/provision_oci.yml`)
> - **[OpenStack Setup Guide](openstack-setup.md)** (`examples/provisioning/provision_openstack.yml`)
> - **[Database Architecture Guide](database-architecture.md)** (Self-hosted & cloud-native PostgreSQL / MySQL)
> - **[Cache & Queue Architecture Guide](cache-and-queue-architecture.md)** (Redis caching/sessions & RabbitMQ message broker)

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
| `keepalived` | Bare Metal HA | Configures VRRP floating IP and HAProxy health checking on proxies. |
| `node_exporter` | Host Telemetry | Installs prometheus-node-exporter across all cluster hosts on port 9100. |
| `grafana` | Visualization | Deploys Grafana server with auto-provisioned dashboards on port 3000. |
| `users` | User Accounts | Manages user creation, dotfiles, shell helpers, and Python venv tools. |

### Tagged Command Examples
```bash
# Provision or update HAProxy load balancers only:
ansible-playbook -i inventory.ini playbook.yml --tags proxy

# Synchronize certificates only:
ansible-playbook -i inventory.ini playbook.yml --tags certs

# Provision or update Database tier only:
ansible-playbook -i inventory.ini playbook.yml --tags database

# Provision or update Redis in-memory cache tier only:
ansible-playbook -i inventory.ini playbook.yml --tags redis

# Provision or update RabbitMQ message broker tier only:
ansible-playbook -i inventory.ini playbook.yml --tags rabbitmq

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

## 7. Operational Playbooks (Backup, Restore, Verification)

| Playbook | Purpose | Documentation |
| :--- | :--- | :--- |
| `backup_cluster.yml` | Snapshots configs, certs, and state; synchronizes to local, SFTP, or S3 targets. | [Backup & Disaster Recovery](backup-and-disaster-recovery.md) |
| `restore_cluster.yml` | Restores cluster snapshots to nodes and restarts affected services. | [Backup & Disaster Recovery](backup-and-disaster-recovery.md) |
| `verify_cluster.yml` | Executes automated post-deployment smoke tests and security compliance checks. | [Verification & Smoke Testing](verification.md) |
| `rolling_maintenance.yml` | Drains backends via HAProxy socket, applies kernel/OS updates, reboots safely. | [Rolling Maintenance](rolling-maintenance.md) |
| `chaos_drill.yml` | Injects non-destructive failures (backend outage, VRRP failover) to test recovery. | [Chaos & Resilience Drills](chaos-engineering.md) |

```bash
# Backup cluster:
ansible-playbook -i inventory.ini backup_cluster.yml

# Restore cluster:
ansible-playbook -i inventory.ini restore_cluster.yml

# Run smoke tests & compliance verification:
ansible-playbook -i inventory.ini verify_cluster.yml

# Run zero-downtime rolling maintenance:
ansible-playbook -i inventory.ini rolling_maintenance.yml

# Run automated chaos resilience drills:
ansible-playbook -i inventory.ini chaos_drill.yml
```

---

## 8. Staging vs Production Environments

The cluster provides decoupled inventories and variable tiers:
- **Staging**: `inventories/staging/hosts.ini` (uses Let's Encrypt Staging CA to prevent rate limits).
- **Production**: `inventories/production/hosts.ini` (uses Let's Encrypt Production CA and 60d retention).

For detailed setup and variables, see the [Staging vs. Production Guide](staging-production.md).

---

## 9. Local Test Suite & Linting

Run automated syntax validation across all inventories, provisioning playbooks, and shell scripts:

```bash
./tests/run_tests.sh
```
