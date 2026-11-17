# Cluster Backup & Disaster Recovery Automation

## Overview

The cluster includes automated, multi-tier disaster recovery playbooks designed to snapshot, export, and restore mission-critical state across all cluster roles:
- **`backup_cluster.yml`**: Scans target cluster hosts, creates compressed archives of TLS certificates, configs, and cryptographic state, and transfers them to configurable targets.
- **`restore_cluster.yml`**: Restores archived state to freshly provisioned or existing target nodes and cleanly restarts related systemd services.
- **`vars/backup_config.yml`**: Declarative configuration specifying backup destinations, compression formats, and remote synchronization parameters.

---

## Supported Backup Destinations

The backup automation natively supports four primary storage backends via `backup_destination_type`:

```
                                  Ansible Controller (Orchestrator)
                                                  │
                 ┌───────────────────┬────────────┴───────┬───────────────────┐
                 │                   │                    │                   │
                 ▼                   ▼                    ▼                   ▼
          [1. Local Disk]     [2. Remote SSH]      [3. Cloud S3]       [4. Rclone Multi-Cloud]
         /var/backups/...    backup.internal.lan   s3://cluster-...    70+ Cloud Backends
                                                                       (R2, B2, GCS, Azure, Crypt)
```

1. **`local`**: Archives are pulled back to the Ansible controller at `backup_local_dir/<timestamp>/`.
2. **`remote_ssh`**: Archives are pushed to an offsite SFTP / SSH storage server using `scp` / `rsync`.
3. **`s3`**: Archives are synchronized to an Amazon S3, MinIO, or S3-compatible object storage bucket via AWS CLI.
4. **`rclone`**: Synchronizes archives across **70+ cloud providers** using `rclone` (Cloudflare R2, Backblaze B2, Google Cloud Storage, Azure Blob Storage, WebDAV, Proton Drive, or client-side transparent encryption via `crypt`).

---

## Configuration (`vars/backup_config.yml`)

Configure backup behavior by referencing `vars/backup_config.example.yml`:

```yaml
# Destination selection: "local", "remote_ssh", "s3", or "rclone"
backup_destination_type: "rclone"

# Local storage path on controller
backup_local_dir: "/var/backups/ansible-cluster/archives"
backup_compression: "gz"  # gz, bz2, xz
backup_retention_days: 30

# ------------------------------------------------------------------------------
# Rclone Multi-Cloud Configuration (for backup_destination_type: rclone)
# ------------------------------------------------------------------------------
backup_rclone_remote: "r2-backup"            # Name of remote configured in rclone.conf
backup_rclone_path: "cluster-backups"        # Destination subpath / bucket prefix
backup_rclone_config: ""                     # Path to rclone.conf (defaults to ~/.config/rclone/rclone.conf)
backup_rclone_flags: "--fast-list --transfers 4 --checkers 8"
backup_rclone_bandwidth_limit: "50M"         # Optional throttling
backup_rclone_auto_install: true             # Automatically install rclone on controller if missing
backup_rclone_enable_retention_cleanup: true # Automatically prune snapshots older than backup_retention_days
```

For sample `rclone.conf` configurations across Cloudflare R2, Backblaze B2, AWS S3, Google Cloud Storage, Azure Blob, SFTP, Nextcloud WebDAV, and transparent Crypt encryption, see [vars/rclone.conf.example](../vars/rclone.conf.example).

---

## What Gets Backed Up?

| Cluster Component | Host Group | Paths & State Preserved |
| :--- | :--- | :--- |
| **Edge Proxies & VIP** | `proxies` | `/etc/haproxy/`, `/etc/keepalived/`, `/etc/ssl/internal/` (Internal Root CA), `/root/.acme.sh/` (ACME certs) |
| **Webservers** | `webservers` | `/etc/nginx/`, `/etc/ssl/internal/`, `/var/www/` |
| **Database Tier** | `databases` | Live compressed SQL dumps (`pg_dumpall`, `mysqldump`), `/etc/postgresql/`, `/etc/mysql/` |
| **Redis Cache Tier** | `redis_servers` | Point-in-time snapshot (`dump.rdb`, `appendonly.aof`), `/etc/redis/redis.conf` |
| **RabbitMQ Message Broker**| `rabbitmq_servers` | Schema & broker definitions export (JSON), `/etc/rabbitmq/`, `.erlang.cookie` |
| **Teleport Gateway** | `teleport_servers` | `/etc/teleport.yaml`, `/var/lib/teleport/` (CA keys, state) |
| **FreeIPA Identity Server** | `freeipa_servers` | Native backup (`ipa-backup --data`), `/var/lib/ipa/backup/`, `/etc/ipa/`, `/etc/dirsrv/`, `/etc/krb5.conf` |
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

# Fetch a snapshot directly from an Rclone remote before restoring
ansible-playbook -i inventory.ini restore_cluster.yml \
  -e "backup_restore_from_rclone=true" \
  -e "rclone_snapshot_name=20261115_120000"
```

The restore playbook performs safety checks before unarchiving, extracts files to target root paths, and triggers automatic systemd service restarts.
