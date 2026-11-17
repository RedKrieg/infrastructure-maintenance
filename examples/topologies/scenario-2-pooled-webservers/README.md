# Scenario 2: Pooled N:1 Load-Balanced Webservers (Single Site / Clustered)

## Overview

In this topology, multiple webservers in the `[webservers]` inventory group share the same `external_fqdn` (e.g., `app.example.com`).

```
                    Internet
                       │
             ┌─────────▼─────────┐
             │ Floating VIP      │ (Keepalived VRRP)
             │ 192.168.10.100    │
             └─────────┬─────────┘
                       │
       ┌───────────────┴───────────────┐
       ▼                               ▼
┌──────────────┐                ┌──────────────┐
│   proxy-01   │                │   proxy-02   │
│   (Master)   │                │   (Backup)   │
└──────┬───────┘                └──────┬───────┘
       │                               │
       ├───────────────────────────────┤
       │ Host Header Routing (N:1 Pool)│
       │ Host: app.example.com         │
       ▼                               ▼
┌────────────────────────────────────────────────────────┐
│             HAProxy Backend Pool: be_app_example_com   │
│             Algorithm: Round-Robin                     │
│                                                        │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│   │    web-01    │  │    web-02    │  │    web-03    │ │
│   │ 192.168.10.21│  │ 192.168.10.22│  │ 192.168.10.23│ │
│   └──────────────┘  └──────────────┘  └──────────────┘ │
└────────────────────────────────────────────────────────┘
```

## How It Works in HAProxy

HAProxy evaluates the incoming `Host` HTTP header for `app.example.com` and directs traffic into a single pooled backend:

```haproxy
frontend fe_https
    # Route for backend pool: app.example.com
    acl is_app_example_com hdr(host) -i app.example.com
    use_backend be_app_example_com if is_app_example_com

backend be_app_example_com
    mode http
    balance roundrobin
    option forwardfor
    http-request set-header Host app.example.com
    option httpchk GET / HTTP/1.1\r\nHost:\ app.example.com
    http-check expect rstatus (2..|3..)
    server web-01 192.168.10.21:443 ssl verify required ca-file /etc/haproxy/certs/internal-ca.crt check inter 3s fall 3 rise 2
    server web-02 192.168.10.22:443 ssl verify required ca-file /etc/haproxy/certs/internal-ca.crt check inter 3s fall 3 rise 2
    server web-03 192.168.10.23:443 ssl verify required ca-file /etc/haproxy/certs/internal-ca.crt check inter 3s fall 3 rise 2
```

## Database Layer (PostgreSQL or MySQL)

In Scenario 2, all pooled webservers (`web-01`, `web-02`, `web-03`) connect to a **centralized database tier** to share state:

1. **Self-Hosted Centralized Database (`db-01`)**:
   - Deploys PostgreSQL (preferred) or MySQL with access restricted strictly to private subnets via UFW and `pg_hba.conf` SCRAM-SHA-256.
   - Database `app_db` and user `app_user` are provisioned automatically.
   ```ini
   [databases]
   db-01 ansible_host=192.168.10.51 internal_ip=192.168.10.51 db_engine=postgresql

   [databases:vars]
   db_name=app_db
   db_user=app_user
   db_password=AppDBSecret2026!
   ```
2. **Cloud-Native Managed Database (AWS RDS / GCP Cloud SQL / Azure Flexible Server)**:
   - For mission-critical pooled clusters, cloud-native managed PostgreSQL is strongly recommended.
   - Webservers connect directly to the managed private DNS endpoint (e.g. `cluster-postgres.c12345678901.us-east-1.rds.amazonaws.com`), providing multi-AZ automated failover and automated snapshots without running database daemons on VMs.

## User Experience & Operational Trade-offs

| Dimension | Behavior in Scenario 2 |
| :--- | :--- |
| **High Availability & Redundancy** | **True Active-Active Clustering**. If any webserver experiences an ungraceful hardware fault or process crash, HAProxy health checks immediately drop that server from the pool. End users experience uninterrupted service via surviving nodes. |
| **State Management** | **Requires Stateless Application Architecture**. Because consecutive requests from the same user may hit different backend nodes, the application must offload state:<br>• **Sessions**: Centralized Redis or Memcached store.<br>• **File Uploads**: Shared S3 object storage or NFS/Ceph mount.<br>• **Database**: Centralized PostgreSQL/MySQL/MariaDB cluster. |
| **Session Stickiness (Optional)** | If state cannot be immediately offloaded, set `haproxy_enable_cookie_persistence: true` in your group variables. HAProxy inserts a `SERVERID` cookie to pin users to the same backend until it goes offline. |
| **Zero-Downtime Rolling Maintenance** | `rolling_maintenance.yml` operates with `serial: 1`. It connects to HAProxy's admin socket to set `web-01` to `state drain`, waits for active requests to finish, performs OS/kernel upgrades, reboots `web-01`, checks its health, and restores it to `state ready`. It then proceeds to `web-02` and `web-03`. The cluster maintains 100% uptime throughout the entire maintenance process! |
| **SSL / TLS Lifecycle** | Let's Encrypt obtains a single certificate for `app.example.com`. The Internal CA signs leaf certificates for each node with SANs containing `app.example.com`, node hostname, and node IP. |

## Quick Start

1. Deploy the pooled cluster:
   ```bash
   ansible-playbook -i examples/topologies/scenario-2-pooled-webservers/inventory.ini playbook.yml
   ```
2. Validate cluster health:
   ```bash
   ansible-playbook -i examples/topologies/scenario-2-pooled-webservers/inventory.ini verify_cluster.yml
   ```
3. Execute zero-downtime rolling maintenance:
   ```bash
   ansible-playbook -i examples/topologies/scenario-2-pooled-webservers/inventory.ini rolling_maintenance.yml
   ```
4. Run chaos drill to confirm seamless failover:
   ```bash
   ansible-playbook -i examples/topologies/scenario-2-pooled-webservers/inventory.ini chaos_drill.yml
   ```
