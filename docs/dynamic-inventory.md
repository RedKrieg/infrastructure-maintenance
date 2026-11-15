# Dynamic Inventory Plugins Guide

In addition to static INI inventories, this suite provides native **Ansible Dynamic Inventory** plugin configurations for **AWS EC2**, **Google Cloud Platform (GCP)**, and **Microsoft Azure**. Dynamic inventory automatically queries the cloud provider's API to discover running virtual machines, map their private IPs, and classify them into role groups using tags.

---

## 1. AWS EC2 Dynamic Inventory

### File: `examples/inventories/aws_ec2.yml`
* **Plugin**: `amazon.aws.aws_ec2`
* **Filter**: Discovers instances with tag `Cluster: headless-ubuntu` in state `running`.
* **Group Mapping**: Maps hosts into `proxies`, `webservers`, `monitoring`, and `teleport_servers` based on the `Role` tag.

### Execution:
```bash
# Verify discovered hosts:
ansible-inventory -i examples/inventories/aws_ec2.yml --graph

# Run playbook:
ansible-playbook -i examples/inventories/aws_ec2.yml playbook.yml
```

---

## 2. Google Cloud Platform (GCP) Dynamic Inventory

### File: `examples/inventories/gcp_compute.yml`
* **Plugin**: `google.cloud.gcp_compute`
* **Filter**: Discovers Compute Engine instances with status `RUNNING`.
* **Group Mapping**: Automatically groups nodes into inventory groups based on network tags (`proxy`, `webserver`, `monitoring`, `teleport`).

### Execution:
```bash
# Verify discovered hosts:
ansible-inventory -i examples/inventories/gcp_compute.yml --graph

# Run playbook:
ansible-playbook -i examples/inventories/gcp_compute.yml playbook.yml
```

---

## 3. Microsoft Azure Dynamic Inventory

### File: `examples/inventories/azure_rm.yml`
* **Plugin**: `azure.azcollection.azure_rm`
* **Filter**: Queries Virtual Machines within the `cluster-rg` Resource Group.
* **Group Mapping**: Groups VMs into inventory roles using the `Role` tag.

### Execution:
```bash
# Verify discovered hosts:
ansible-inventory -i examples/inventories/azure_rm.yml --graph

# Run playbook:
ansible-playbook -i examples/inventories/azure_rm.yml playbook.yml
```

---

## 4. Tagging Standards for Dynamic Discovery

When provisioning instances manually or with external automation, apply these tags for dynamic discovery:

| Tag Key | Value Example | Used By |
| :--- | :--- | :--- |
| `Cluster` | `headless-ubuntu` | All providers to identify cluster members |
| `Role` | `proxy` / `webserver` / `monitoring` / `teleport_servers` | Keyed group categorization |
| `external_fqdn` | `web1.example.com` | Composed into hostvars for Nginx & HAProxy routing |
