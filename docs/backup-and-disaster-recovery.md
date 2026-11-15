# Cluster Backup & Disaster Recovery Automation

## Overview

The cluster includes automated, multi-tier disaster recovery playbooks designed to snapshot, export, and restore mission-critical state across all cluster roles:
- **`backup_cluster.yml`**: Scans target cluster hosts, creates compressed archives of TLS certificates, configs, and cryptographic state, and transfers them to configurable targets.
- **`restore_cluster.yml`**: Restores archived state to freshly provisioned or existing target nodes and cleanly restarts related systemd services.
- **`vars/backup_config.yml`**: Declarative configuration specifying backup destinations, compression formats, and remote synchronization parameters.

---

## Supported Backup Destinations

The backup automation natively supports three primary storage backends via `backup_destination_type`:

```
                      Ansible Controller (Orchestrator)
                                      │
               ┌──────────────────────┼──────────────────────┐
               │                      │                      │
               ▼                      ▼                      ▼
        [1. Local Disk]        [2. Remote SSH/SFTP]    [3. Cloud S3 / MinIO]
       /var/backups/cluster    backup.internal.lan     s3://prod-backups/
```

1. **`local`**: Archives are pulled back to the Ansible controller at `backup_local_dir/<timestamp>/`.
2. **`remote_ssh`**: Archives are pushed to an offsite SFTP / SSH storage server using `scp` / `rsync`.
3. **`s3`**: Archives are synchronized to an Amazon S3, MinIO, or S3-compatible object storage bucket.

---

## Configuration (`vars/backup_config.yml`)

Configure backup behavior by referencing `vars/backup_config.example.yml`:

```yaml
# Destination selection: "local", "remote_ssh", or "s3"
backup_destination_type: "local"

# Local storage path on controller
backup_local_dir: "/var/backups/ansible-cluster/archives"
backup_compression: "gz"  # gz, bz2, xz

# Remote SSH settings (for backup_destination_type: remote_ssh)
backup_remote_ssh_host: "backup.internal.company.com"
backup_remote_ssh_port: 22
backup_remote_ssh_user: "backup-operator"
backup_remote_ssh_key: "~/.ssh/id_ed25519"
backup_remote_ssh_dir: "/storage/backups/ansible-cluster"

# S3 Object Storage settings (for backup_destination_type: s3)
backup_s3_bucket: "prod-cluster-backups"
backup_s3_prefix: "cluster-backups"
backup_s3_region: "us-east-1"
backup_s3_endpoint_url: ""  # Leave empty for AWS S3, or set to "https://minio.internal:9000"
backup_s3_access_key: "{{ vault_backup_s3_access_key }}"
backup_s3_secret_key: "{{ vault_backup_s3_secret_key }}"
```

---

## What Gets Backed Up?

| Cluster Component | Host Group | Paths Preserved |
| :--- | :--- | :--- |
| **Edge Proxies & VIP** | `proxies` | `/etc/haproxy/`, `/etc/keepalived/`, `/root/.acme.sh/` (TLS certs) |
| **Webservers** | `webservers` | `/etc/nginx/`, `/etc/ssl/internal/`, `/var/www/` |
| **Teleport Gateway** | `teleport_servers` | `/etc/teleport.yaml`, `/var/lib/teleport/` (CA keys, state) |
| **Monitoring Stack** | `monitoring` | `/etc/prometheus/`, `/etc/grafana/`, `/var/lib/grafana/grafana.db` |

---

## Running a Backup

Execute the backup playbook:

```bash
# Standard backup to the configured destination
ansible-playbook -i inventory.ini backup_cluster.yml

# Override destination on the command line
ansible-playbook -i inventory.ini backup_cluster.yml -e "backup_destination_type=remote_ssh"
```

The resulting archives will be structured as:
```
/var/backups/ansible-cluster/archives/20261115_120000/
├── proxy_proxy-01.tar.gz
├── proxy_proxy-02.tar.gz
├── webserver_web-01.tar.gz
├── webserver_web-02.tar.gz
├── teleport_teleport-01.tar.gz
└── monitoring_monitoring-01.tar.gz
```

---

## Running a Disaster Recovery Restore

To restore the cluster from a backup snapshot:

```bash
# Automatically restore the latest snapshot found in backup_local_dir
ansible-playbook -i inventory.ini restore_cluster.yml

# Restore a specific timestamp snapshot
ansible-playbook -i inventory.ini restore_cluster.yml \
  -e "backup_source_dir=/var/backups/ansible-cluster/archives/20261115_120000"
```

The restore playbook performs safety checks before unarchiving, extracts files to target root paths, and triggers automatic systemd service restarts.
