# Database Tier Architecture: PostgreSQL, MySQL & Cloud-Native Services

## Overview

The cluster automation framework provides a fully modular, optional **Database Layer** supporting both self-hosted and cloud-native managed architectures:

- **Supported Engines**: **PostgreSQL** (default & preferred) and **MySQL**.
- **Deployment Models**:
  - **Self-Hosted Automated Provisioning**: Automated deployment of hardened PostgreSQL or MySQL instances on dedicated cluster virtual machines via the `database` role (`roles/database`).
  - **Cloud-Native Managed Services**: Drop-in integration with cloud-native managed database services (AWS RDS, Google Cloud SQL, Azure Database for PostgreSQL Flexible Server, and OCI Database with PostgreSQL).
- **Topology Alignment**: Tailored for **Scenario 1** (dedicated multi-tenant databases), **Scenario 2** (stateless pooled web cluster connecting to central HA database), and **Scenario 3** (hybrid mixed workloads).

---

## Architecture Matrix by Topology

| Dimension | Scenario 1: Dedicated 1:1 Tenants | Scenario 2: Pooled N:1 Clustered Site | Scenario 3: Hybrid Architecture |
| :--- | :--- | :--- | :--- |
| **Database Structure** | Isolated databases & users per tenant (`alpha_db`, `beta_db`, `gamma_db`) | Centralized shared application database (`app_db`) | Mixed: Central `app_db` for core pool + isolated tenant databases |
| **Self-Hosted Pattern** | Shared database node hosting partitioned tenant databases & credentials | Centralized database node (PostgreSQL preferred) | Centralized database node hosting core + tenant databases |
| **Cloud-Native Recommendation** | Single managed PostgreSQL instance with multiple databases/schemas | **Multi-AZ Managed PostgreSQL** (AWS RDS, GCP Cloud SQL, Azure Flexible Server) | Managed PostgreSQL instance with multi-database partitioning |
| **Application State** | Stateful or stateless; tenant data strictly isolated | **Strictly Stateless**: All web nodes share centralized DB & Redis sessions | Core app is stateless; tenant apps may be stateful or stateless |
| **Backup Strategy** | `pg_dumpall` or per-database dumps archived to S3/SSH | Live multi-tier logical dumps + cloud-native automated snapshots | Unified logical dumps capturing core + all tenant databases |

---

## Database Engine Comparison

### 1. PostgreSQL (Recommended & Preferred Default)

PostgreSQL is the default engine for all cluster operations due to its enterprise durability, advanced features, and security model:

- **Authentication**: Native **SCRAM-SHA-256** password encryption in `pg_hba.conf`.
- **Advanced Types**: Native JSONB support for document/relational hybrid data models.
- **Concurrency**: Multi-Version Concurrency Control (MVCC) providing high-throughput concurrent read/write transactions for clustered webservers.
- **Zero-Trust Network Isolation**: Access is restricted strictly to cluster private subnets (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) via both UFW firewall rules and `pg_hba.conf` host entries.

### 2. MySQL

For teams standardized on MySQL:

- **Authentication**: `caching_sha2_password` authentication plugin.
- **Configuration**: Drop-in server configuration at `/etc/mysql/conf.d/cluster-db.cnf` binding to internal cluster interfaces (`bind-address = 0.0.0.0`).
- **Access Control**: Users scoped strictly to trusted private network CIDRs (`user@'%'` protected by UFW).

---

## Self-Hosted Database Provisioning (`roles/database`)

### Inventory Configuration

To enable self-hosted database provisioning, define the `[databases]` group in your inventory file:

#### Scenario 1: Multi-Tenant Per-Client Databases
```ini
[databases]
db-01 ansible_host=192.168.10.51 internal_ip=192.168.10.51 db_engine=postgresql

[databases:vars]
# Isolated database and service user per client tenant
db_databases=[{"name":"alpha_db","user":"alpha_user","password":"AlphaSecret2026!"},{"name":"beta_db","user":"beta_user","password":"BetaSecret2026!"},{"name":"gamma_db","user":"gamma_user","password":"GammaSecret2026!"}]
```

#### Scenario 2: Centralized Clustered Database
```ini
[databases]
db-01 ansible_host=192.168.10.51 internal_ip=192.168.10.51 db_engine=postgresql

[databases:vars]
db_name=app_db
db_user=app_user
db_password=AppSecret2026!
```

#### Scenario 3: Hybrid Database Workload
```ini
[databases]
db-01 ansible_host=192.168.10.51 internal_ip=192.168.10.51 db_engine=postgresql

[databases:vars]
db_databases=[{"name":"app_db","user":"app_user","password":"CoreAppSecret2026!"},{"name":"tenant_a_db","user":"tenant_a_user","password":"TenantASecret2026!"},{"name":"tenant_b_db","user":"tenant_b_user","password":"TenantBSecret2026!"}]
```

### Switching to MySQL

To use MySQL instead of PostgreSQL, set `db_engine=mysql` on the database node or in group variables:

```ini
[databases]
db-01 ansible_host=192.168.10.51 internal_ip=192.168.10.51 db_engine=mysql
```

---

## Cloud-Native Managed Database Architectures

For production deployments in public clouds, cloud-native managed database services are strongly recommended over self-hosted database virtual machines. Managed services deliver:
- **Multi-AZ Automated Failover**: Zero-touch database failover during zone disruptions.
- **Continuous Automated Backups**: Point-in-time recovery (PITR) with zero maintenance playbooks.
- **Managed OS & Engine Patching**: Routine security patches applied without manual apt upgrades.

### 1. Amazon Web Services (AWS) - AWS RDS for PostgreSQL

On AWS, deploy a Multi-AZ **AWS RDS for PostgreSQL** instance inside the cluster VPC's private subnets:

```
                            AWS VPC (172.31.0.0/16)
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │  ┌───────────────────────┐  ┌───────────────────────┐                       │
 │  │      web-01 (AZ-1a)   │  │      web-02 (AZ-1b)   │                       │
 │  │       172.31.10.11    │  │       172.31.20.11    │                       │
 │  └───────────┬───────────┘  └───────────┬───────────┘                       │
 │              │                          │                                   │
 │              └────────────┬─────────────┘                                   │
 │                           │ TCP Port 5432 (Private RDS Endpoint)            │
 │                           ▼                                                 │
 │      ┌──────────────────────────────────────────────┐                       │
 │      │       AWS RDS PostgreSQL (Multi-AZ)          │                       │
 │      │  cluster-postgres-db.xxxxxx.us-east-1.rds... │                       │
 │      │       ┌──────────────┐  ┌──────────────┐     │                       │
 │      │       │Primary(AZ-1a)│──│Standby(AZ-1b)│     │                       │
 │      │       └──────────────┘  └──────────────┘     │                       │
 │      └──────────────────────────────────────────────┘                       │
 └─────────────────────────────────────────────────────────────────────────────┘
```

#### Automated Provisioning Playbook
Run the dedicated RDS provisioning automation:
```bash
ansible-playbook examples/provisioning/provision_aws_rds_postgresql.yml
```

#### Connecting Webservers
Update `group_vars/webservers.yml` or `examples/inventories/inventory.aws.ini`:
```ini
[webservers:vars]
db_host=cluster-postgres-db.c12345678901.us-east-1.rds.amazonaws.com
db_port=5432
db_name=app_db
db_user=dbadmin
db_engine=postgresql
```

---

### 2. Google Cloud Platform (GCP) - Cloud SQL for PostgreSQL

On GCP, deploy a Regional **Cloud SQL for PostgreSQL** instance connected via **Private Services Access** (Private IP):

#### Automated Provisioning Playbook
```bash
ansible-playbook examples/provisioning/provision_gcp_cloudsql_postgresql.yml
```

#### Key Architecture Highlights:
- **Private IP Only**: Public IP is disabled; access is strictly internal over Google's private VPC backbone.
- **Regional High Availability**: Synchronous replication between primary and standby zones (`us-central1-a` and `us-central1-b`) with automatic failover.

#### Connecting Webservers
Update `examples/inventories/inventory.gcp.ini`:
```ini
[webservers:vars]
db_host=10.128.0.50
db_port=5432
db_name=app_db
db_user=app_user
db_engine=postgresql
```

---

### 3. Microsoft Azure - Azure Database for PostgreSQL Flexible Server

On Azure, deploy a **Flexible Server** with **Zone-Redundant High Availability** integrated into a delegated VNet subnet:

#### Automated Provisioning Playbook
```bash
ansible-playbook examples/provisioning/provision_azure_postgresql.yml
```

#### Key Architecture Highlights:
- **VNet Integration**: Injected directly into `subnet-postgres` (`10.240.2.0/24`) without internet exposure.
- **Zone-Redundant Failover**: Warm standby server maintained in a separate availability zone.

#### Connecting Webservers
Update `examples/inventories/inventory.azure.ini`:
```ini
[webservers:vars]
db_host=cluster-postgres-flex.postgres.database.azure.com
db_port=5432
db_name=app_db
db_user=dbadmin
db_engine=postgresql
```

---

### 4. Oracle Cloud (OCI) & OpenStack

- **Oracle Cloud (OCI)**: Use **OCI Database with PostgreSQL** within a private regional subnet across Fault Domains.
- **OpenStack**: Use **OpenStack Trove** database-as-a-service or self-hosted PostgreSQL deployed on a Nova instance within an anti-affinity server group.

---

## Automated Backup & Disaster Recovery

For self-hosted database nodes, the disaster recovery playbooks integrate automated logical dumps:

### Automated Backup (`backup_cluster.yml`)
When `backup_cluster.yml` executes:
1. Detects active database services on `[databases]` hosts.
2. For PostgreSQL: Executes `su - postgres -c 'pg_dumpall' | gzip` to capture all databases, roles, and schema definitions.
3. For MySQL: Executes `mysqldump --all-databases --single-transaction | gzip`.
4. Transports the compressed SQL dumps to the Ansible controller.
5. Synchronizes archives offsite to remote SSH/SFTP or S3/MinIO storage.

```bash
ansible-playbook -i inventory.ini backup_cluster.yml
```

### Automated Restoration (`restore_cluster.yml`)
When `restore_cluster.yml` runs:
1. Discovers the target archive snapshot.
2. Ingests PostgreSQL dumps directly via `psql` under the postgres user.
3. Ingests MySQL dumps via `mysql`.

```bash
ansible-playbook -i inventory.ini restore_cluster.yml
```

---

## Security Best Practices

1. **Strict Private Subnet Binding**: Never bind database listeners to public internet IPs. Use `internal_ip` or private VPC subnets only.
2. **Firewall Enforcement**: UFW automatically restricts ports `5432` and `3306` to `db_trusted_subnets`.
3. **Password Management**: Always encrypt sensitive database passwords with Ansible Vault:
   ```bash
   ansible-vault encrypt_string 'StrongPassword2026!' --name 'vault_db_password'
   ```
4. **Zero-Trust Teleport SSH**: Database nodes are included in `[headless_nodes:children]`, automatically benefiting from JIT Teleport SSH access, central logging (rsyslog), and Prometheus Node Exporter monitoring.
