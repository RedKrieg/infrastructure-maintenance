# Operational Runbook: Alert Response, Memory Pressure & Disk Exhaustion

## Overview

When Prometheus and Alertmanager fire telemetry warnings or critical pages, operational staff require structured, systematic procedures to diagnose root causes, relieve immediate pressure, and scale resources without causing cascading outages.

This runbook covers two of the most critical incident types:
1. **Low Memory Conditions & Memory Alarms** (`HostMemoryAvailableLow`, `RabbitMQMemoryAlarmActive`, `RedisMemoryApproachingLimit`).
2. **Low Disk Space & Storage Exhaustion** (`HostDiskSpaceLow`, `HostDiskSpaceCritical`, `RabbitMQDiskFreeAlarmActive`).

---

## 1. Low Memory Conditions & Memory Alarms

### A. Alert Reference

| Alert Name | Severity | Condition | Meaning & Immediate Risk |
| :--- | :--- | :--- | :--- |
| `HostMemoryAvailableLow` | Warning | Available RAM < 10% for 3m | Physical host is close to exhausting RAM; risk of OOM-killer terminating services. |
| `RabbitMQMemoryAlarmActive` | Critical | Watermark alarm == 1 for 1m | RabbitMQ has exceeded memory limit; **all incoming publishers are blocked**. |
| `RedisMemoryApproachingLimit`| Warning | Used memory > 85% of max | Redis cache is near configured limit; keys will be aggressively evicted. |

---

### B. Immediate Diagnostic Triage

Log in to the affected target node (via Teleport `tsh ssh <host>` or direct SSH) and execute:

```bash
# 1. Check total memory, available RAM, and swap usage:
free -h

# 2. Identify the top 15 memory-consuming processes:
ps aux --sort=-%mem | head -15

# 3. Launch interactive process monitor:
btop # or htop

# 4. Check whether the Linux kernel Out-Of-Memory (OOM) killer has terminated any processes:
sudo dmesg -T | grep -i -E "oom|out of memory|killed process"
sudo journalctl -k -S "1 hour ago" | grep -i -E "oom|killed"
```

---

### C. Service-Specific Investigation & Remediation

#### 1. In-Memory Cache (Redis)
* **Inspect Current Memory Usage**:
  ```bash
  redis-cli -a '<vault_redis_password>' info memory
  ```
  Look for:
  - `used_memory_human`: Total memory currently allocated.
  - `maxmemory_human`: Configured ceiling.
  - `mem_fragmentation_ratio`: If > 1.5, memory fragmentation is high.
* **Inspect Connected Clients**:
  ```bash
  redis-cli -a '<vault_redis_password>' info clients
  redis-cli -a '<vault_redis_password>' client list
  ```
* **Remediation**:
  - **Increase Memory Limit Live (No Restart Required)**:
    ```bash
    redis-cli -a '<vault_redis_password>' config set maxmemory 2gb
    ```
    Persist this change in your inventory or `roles/redis/defaults/main.yml` under `redis_maxmemory: "2gb"`.
  - **Verify Eviction Policy**: Ensure `maxmemory-policy` is set to `allkeys-lru` or `volatile-lru` so Redis automatically purges cold keys rather than failing writes.

---

#### 2. Message Broker (RabbitMQ)
When `RabbitMQMemoryAlarmActive` trips, RabbitMQ intentionally stops reading from client TCP sockets to prevent Erlang VM crashes.
* **Diagnose Alarms**:
  ```bash
  sudo rabbitmq-diagnostics alarms
  sudo rabbitmq-diagnostics memory_breakdown
  ```
* **Check Queue Depths & Missing Consumers**:
  ```bash
  sudo rabbitmqctl list_queues name messages messages_ready messages_unacknowledged consumers
  ```
* **Remediation**:
  - If a queue has thousands of messages and **0 consumers**, background worker services (e.g. Celery, Sidekiq, consumer daemons) are dead or stalled. Restart the worker processes on your application servers.
  - If messages are piling up faster than workers can process, temporarily scale out consumer concurrency.
  - If the host legitimately has surplus memory and the alarm was premature, dynamically raise the watermark:
    ```bash
    sudo rabbitmqctl set_vm_memory_high_watermark 0.7
    ```
    Persist permanently in `roles/rabbitmq/defaults/main.yml` under `rabbitmq_vm_memory_high_watermark`.

---

#### 3. Database Tier (PostgreSQL / MySQL)
* **Check Active Connections & Runaway Queries**:
  ```sql
  -- On PostgreSQL (run as postgres user):
  SELECT pid, client_addr, now() - query_start AS duration, state, query
  FROM pg_stat_activity
  WHERE state != 'idle'
  ORDER BY duration DESC;
  ```
* **Remediation**:
  - **Cancel a Long-Running / Hung Query**:
    ```sql
    SELECT pg_cancel_backend(<pid>);
    ```
  - **Forcefully Terminate a Stuck Connection**:
    ```sql
    SELECT pg_terminate_backend(<pid>);
    ```
  - **Check Per-Query Memory Allocation (`work_mem`)**: If `work_mem` is set too high (e.g. 64MB) and 100 concurrent queries run complex sorts/joins, memory will rapidly deplete. Reduce `work_mem` to `8MB` or `16MB`.

---

#### 4. Backend Webservers (Nginx / PHP-FPM / Python / Node)
* **Check Worker Counts**:
  ```bash
  ps aux | grep -E "php-fpm|gunicorn|node|nginx" | wc -l
  ```
* **Remediation**:
  - If PHP-FPM processes are consuming excessive memory, reduce `pm.max_children` in your pool configuration to match physical RAM:
    $$\text{pm.max\_children} \approx \frac{\text{Total Available RAM}}{\text{Average Memory per Process (typically 60-80MB)}}$$

---

### D. Increasing Physical RAM (Vertical Scaling)

If service tuning has been exhausted and workloads legitimately require more physical hardware, execute a **Zero-Downtime Rolling Vertical Migration**:
* Follow the step-by-step procedure in [Resource Sizing & Scaling Guide](resource-sizing-and-scaling.md#4-zero-downtime-vertical-scaling-migrating-to-higher-tiers).
* Webservers are drained via HAProxy admin socket (`set server ... state drain`), resized via cloud CLI, validated, and returned to service with zero dropped packets.

---

## 2. Low Disk Space & Storage Exhaustion

### A. Alert Reference

| Alert Name | Severity | Condition | Meaning & Immediate Risk |
| :--- | :--- | :--- | :--- |
| `HostDiskSpaceLow` | Warning | Free disk space < 15% for 5m | Filesystem is filling up; needs routine maintenance or expansion. |
| `HostDiskSpaceCritical` | Critical | Free disk space < 5% for 2m | **Imminent risk of service crash**, database read-only lockdown, or corrupt writes. |
| `RabbitMQDiskFreeAlarmActive`| Critical | Free space < `disk_free_limit` | RabbitMQ has halted publishers due to low disk space on `/var/lib/rabbitmq`. |

---

### B. Immediate Diagnostic Triage

Log in to the affected target node and inspect the storage state:

```bash
# 1. Check disk utilization across all mounted filesystems:
df -h -x tmpfs -x devtmpfs

# 2. Check inode exhaustion (disks can be 'full' if inodes run out, even with free GBs!):
df -i -x tmpfs -x devtmpfs

# 3. Find the top 20 largest directories starting from root:
sudo du -ahx / 2>/dev/null | sort -rh | head -20

# 4. Alternatively, use ncdu for interactive visual navigation:
sudo ncdu -x /
```

---

### C. What Specific Disk Users to Check For (The "Dirty Dozen")

Examine the following 11 common culprits in order of frequency:

```
┌────────────────────────────────────────────────────────────────────────┐
│                   COMMON DISK SPACE CONSUMERS & LOCATIONS              │
│                                                                        │
│ 1. Journald Logs     (/var/log/journal/)       -> vacuum logs          │
│ 2. Web Access Logs   (/var/log/nginx/, /haproxy) -> force logrotate    │
│ 3. Remote Syslog     (/var/log/remote/<host>/) -> prune retention      │
│ 4. Database WAL      (/var/lib/postgresql/pg_wal/) -> drop dead slots │
│ 5. RabbitMQ Mnesia   (/var/lib/rabbitmq/mnesia/) -> purge dead queues  │
│ 6. Redis AOF         (/var/lib/redis/appendonly) -> bgrewriteaof       │
│ 7. Package Cache     (/var/cache/apt/archives/) -> apt-get clean       │
│ 8. Core Dumps        (/var/crash/)             -> remove crash dumps   │
│ 9. Prometheus TSDB   (/var/lib/prometheus/)    -> adjust retention     │
│ 10. Backup Staging   (/var/backups/, /tmp/)    -> clear stale tarballs │
│ 11. Ghost Files      (Deleted but held open)   -> lsof +L1 & restart   │
└────────────────────────────────────────────────────────────────────────┘
```

#### 1. Systemd Journal Logs (`/var/log/journal/`)
* **Check Usage**:
  ```bash
  journalctl --disk-usage
  ```
* **Cleanup Command**:
  ```bash
  # Vacuum journal logs to maximum 500 MB:
  sudo journalctl --vacuum-size=500M
  # Or vacuum logs older than 7 days:
  sudo journalctl --vacuum-time=7d
  ```

#### 2. Nginx & HAProxy Access Logs (`/var/log/nginx/`, `/var/log/haproxy.log`)
* **Check Usage**:
  ```bash
  ls -lh /var/log/nginx/ /var/log/haproxy*
  ```
* **Cleanup Command**:
  ```bash
  # Force immediate logrotate execution and compression:
  sudo logrotate -f /etc/logrotate.d/nginx
  sudo logrotate -f /etc/logrotate.d/haproxy
  # Remove uncompressed old log archives if any exist:
  sudo rm -f /var/log/nginx/*.1 /var/log/nginx/*.log.1
  ```

#### 3. Remote Syslog Storage on Monitoring Host (`/var/log/remote/`)
On the centralized logging server, log files are categorized per host:
* **Check Usage**:
  ```bash
  du -sh /var/log/remote/*
  ```
* **Cleanup Command**:
  ```bash
  # Prune archived logs older than 30 days:
  sudo find /var/log/remote -type f -name "*.gz" -mtime +30 -delete
  ```

#### 4. Database WAL (Write-Ahead Logs) & Binary Logs
* **PostgreSQL (`/var/lib/postgresql/<version>/main/pg_wal/`)**:
  - *Cause*: A disconnected streaming read replica or inactive replication slot causes PostgreSQL to retain every WAL file indefinitely on disk.
  - *Check*:
    ```bash
    sudo -u postgres psql -c "SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS lag FROM pg_replication_slots;"
    ```
  - *Cleanup*: If an inactive slot is holding gigabytes of WAL:
    ```sql
    SELECT pg_drop_replication_slot('inactive_slot_name');
    ```
    PostgreSQL will immediately recycle and remove unneeded WAL segments.
* **MySQL (`/var/lib/mysql/binlog.*`)**:
  - *Cleanup*:
    ```sql
    PURGE BINARY LOGS BEFORE NOW() - INTERVAL 3 DAY;
    ```

#### 5. RabbitMQ Message Store & Mnesia Data (`/var/lib/rabbitmq/mnesia/`)
* **Check Usage**:
  ```bash
  du -sh /var/lib/rabbitmq/mnesia/*
  ```
* **Cause**: Persistent queues accumulating unconsumed messages.
* **Cleanup Command**:
  ```bash
  # List queues with large backlogs:
  sudo rabbitmqctl list_queues name messages messages_ready
  # Purge an abandoned test or dead-letter queue:
  sudo rabbitmqctl purge_queue <stale_queue_name>
  ```

#### 6. Redis AOF (Append-Only File) (`/var/lib/redis/appendonly.aof`)
* **Check Usage**:
  ```bash
  ls -lh /var/lib/redis/
  ```
* **Cleanup Command**:
  Trigger a background AOF compaction rewrite:
  ```bash
  redis-cli -a '<vault_redis_password>' bgrewriteaof
  ```

#### 7. APT Package Cache (`/var/cache/apt/archives/`)
* **Check Usage**:
  ```bash
  du -sh /var/cache/apt/archives
  ```
* **Cleanup Command**:
  ```bash
  sudo apt-get clean && sudo apt-get autoremove -y
  ```

#### 8. System Core Dumps & Crash Reports (`/var/crash/`, `/var/lib/systemd/coredump/`)
* **Check & Cleanup**:
  ```bash
  sudo rm -f /var/crash/*
  sudo rm -rf /var/lib/systemd/coredump/*
  ```

#### 9. Prometheus TSDB Storage on Monitoring Node (`/var/lib/prometheus/`)
* **Check Usage**:
  ```bash
  du -sh /var/lib/prometheus/
  ```
* **Remediation**:
  If retention is set too long, reduce retention time in `/etc/default/prometheus`:
  `--storage.tsdb.retention.time=15d` (instead of 60d), then reload Prometheus (`sudo systemctl reload prometheus`).

#### 10. Backup Staging Archives (`/tmp/`, `/var/backups/`)
* **Check & Cleanup**:
  ```bash
  # Remove orphaned SQL dumps or tarballs in /tmp:
  sudo rm -f /tmp/*.sql.gz /tmp/*.tar.*
  # Prune local backup snapshots older than 14 days:
  sudo find /var/backups/ansible-cluster/archives -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +
  ```

#### 11. Ghost Space (Deleted Files Still Held Open by Processes)
* **Symptom**: `df -h` reports 99% full, but `du -sh /` reports only 20GB used.
* **Cause**: A log file was deleted with `rm`, but a running daemon (like Nginx, HAProxy, or Java) still holds the file descriptor open. Linux cannot free the disk blocks until the process closes the file.
* **Diagnostic**:
  ```bash
  sudo lsof +L1
  ```
* **Cleanup Command**:
  Restart the specific daemon holding the deleted file descriptor:
  ```bash
  # Example: if Nginx is holding a deleted access.log:
  sudo systemctl restart nginx
  ```

---

### D. Legitimate Need for More Storage: Online Cloud Volume Expansion

If all unneeded files have been cleaned and the workload legitimately requires a larger disk, modern cloud platforms allow you to expand block storage **online without rebooting or unmounting filesystems**.

#### 1. Expand the Cloud Volume via Cloud CLI

* **Amazon Web Services (AWS EBS)**:
  ```bash
  # 1. Expand EBS volume to 60 GB:
  aws ec2 modify-volume --volume-id vol-0123456789abcdef0 --size 60
  # 2. Wait until status is in-use / optimizing:
  aws ec2 describe-volumes-modifications --volume-id vol-0123456789abcdef0
  ```
* **Google Cloud Platform (GCP Persistent Disk)**:
  ```bash
  gcloud compute disks resize web-01 --size=60GB --zone=us-central1-a
  ```
* **Microsoft Azure (Managed OS / Data Disk)**:
  ```bash
  az disk update --resource-group cluster-rg --name web-01_OsDisk --size-gb 64
  ```
* **OpenStack (Cinder Volume)**:
  ```bash
  openstack volume set --size 60 <volume_id>
  ```

#### 2. Expand Partition & Filesystem on the Target Node (Online)

Once the cloud volume has been expanded in the cloud control plane, log in to the machine and apply the new capacity to the Linux partition and filesystem:

```bash
# 1. Verify the kernel sees the new raw block device size (e.g. nvme0n1 or sda):
lsblk

# 2. Expand partition 1 to consume all newly added space:
# If device is NVMe:
sudo growpart /dev/nvme0n1 1
# If device is SCSI (SDA):
sudo growpart /dev/sda 1

# 3. Resize the filesystem to fill the partition:
# For ext4 filesystems (Ubuntu default):
sudo resize2fs /dev/nvme0n1p1  # or /dev/sda1

# For XFS filesystems:
sudo xfs_growfs /

# 4. Confirm new capacity is immediately available:
df -h /
```

The filesystem expands dynamically within seconds with **zero downtime, zero unmounting, and zero process restarts**.
