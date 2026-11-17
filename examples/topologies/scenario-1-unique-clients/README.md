# Scenario 1: Dedicated 1:1 Webserver Backends (Unique Clients / Multi-Tenant)

## Overview

In this topology, each webserver in the `[webservers]` inventory group is dedicated to a distinct client or application tenant with its own unique `external_fqdn`.

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
       │ Host Header Routing (1:1)     │
       ▼                               ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  web-alpha   │  │   web-beta   │  │  web-gamma   │
│  (Client A)  │  │  (Client B)  │  │  (Client C)  │
│  alpha.      │  │  beta.       │  │  gamma.      │
│  example.com │  │  example.com │  │  example.com │
└──────────────┘  └──────────────┘  └──────────────┘
```

## How It Works in HAProxy

HAProxy evaluates the incoming `Host` HTTP request header and matches it to the individual tenant backend:

- `alpha.example.com` -> routes directly to backend `be_alpha_example_com` (`web-alpha:443`)
- `beta.example.com`  -> routes directly to backend `be_beta_example_com` (`web-beta:443`)
- `gamma.example.com` -> routes directly to backend `be_gamma_example_com` (`web-gamma:443`)

Each backend contains a single server definition:
```haproxy
backend be_alpha_example_com
    mode http
    balance roundrobin
    option forwardfor
    http-request set-header Host alpha.example.com
    server web-alpha 192.168.10.21:443 ssl verify required ca-file /etc/haproxy/certs/internal-ca.crt check
```

## Database Layer (PostgreSQL or MySQL)

In Scenario 1, the optional database tier can be deployed in two configurations:

1. **Shared Multi-Tenant Database Node (`db-01`)**:
   A single database instance (PostgreSQL preferred) hosting isolated databases and separate credentials per client:
   - `alpha_db` (user: `alpha_user`) for `web-alpha`
   - `beta_db` (user: `beta_user`) for `web-beta`
   - `gamma_db` (user: `gamma_user`) for `web-gamma`
   This is configured via `db_databases` in `inventory.ini`:
   ```ini
   [databases]
   db-01 ansible_host=192.168.10.51 internal_ip=192.168.10.51 db_engine=postgresql

   [databases:vars]
   db_databases=[{"name":"alpha_db","user":"alpha_user","password":"AlphaDBSecret2026!"},{"name":"beta_db","user":"beta_user","password":"BetaDBSecret2026!"},{"name":"gamma_db","user":"gamma_user","password":"GammaDBSecret2026!"}]
   ```
2. **Cloud-Native Managed Databases (AWS RDS / GCP Cloud SQL / Azure Flexible Server)**:
   For cloud deployments, each tenant can point to an isolated database on a managed PostgreSQL instance with private VPC peering.

## Cache & Message Broker Layer (Redis & RabbitMQ)

In Scenario 1, caching and queuing can be deployed either per-tenant or as a shared infrastructure layer:
- **Redis (`redis-01`)**: Provides tenant-isolated Redis databases (db 0 for Alpha, db 1 for Beta, db 2 for Gamma) or dedicated Redis keyspaces with password authentication.
- **RabbitMQ (`mq-01`)**: Provides tenant-isolated virtual hosts (`/alpha`, `/beta`, `/gamma`) with dedicated credentials and queues, or shared message passing.

```ini
[redis_servers]
redis-01 ansible_host=192.168.10.61 internal_ip=192.168.10.61

[rabbitmq_servers]
mq-01 ansible_host=192.168.10.71 internal_ip=192.168.10.71 rabbitmq_mgmt_fqdn=mq.example.com
```

## User Experience & Operational Trade-offs

| Dimension | Behavior in Scenario 1 |
| :--- | :--- |
| **Tenant Isolation** | **Complete**. Each client's traffic, filesystem, CPU, memory, and database processes are isolated to their dedicated host. |
| **State Management** | **Simple / Local**. Applications can store session files, sqlite databases, or uploaded media directly on the local disk without distributed file locking or shared caching. |
| **High Availability** | **Active-Passive at Ingress; Single Instance at Web Tier**. While proxies fail over seamlessly via Keepalived VRRP, an outage on `web-alpha` takes down `alpha.example.com` until recovered. |
| **Rolling Maintenance** | `rolling_maintenance.yml` drains connections for each tenant before rebooting. During that specific host's reboot, HAProxy responds with HTTP 503 until the host restarts. Maintenance can be scheduled per tenant. |
| **SSL / TLS Lifecycle** | Let's Encrypt obtains individual SAN or wildcard certificates. The internal CA signs separate ECDSA P-384 certificates for each tenant domain. |

## Quick Start

1. Deploy the cluster:
   ```bash
   ansible-playbook -i examples/topologies/scenario-1-unique-clients/inventory.ini playbook.yml
   ```
2. Validate cluster health:
   ```bash
   ansible-playbook -i examples/topologies/scenario-1-unique-clients/inventory.ini verify_cluster.yml
   ```
3. Run zero-downtime rolling maintenance:
   ```bash
   ansible-playbook -i examples/topologies/scenario-1-unique-clients/inventory.ini rolling_maintenance.yml
   ```
