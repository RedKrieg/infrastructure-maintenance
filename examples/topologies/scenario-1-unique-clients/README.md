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
