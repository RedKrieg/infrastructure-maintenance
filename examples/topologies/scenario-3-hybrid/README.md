# Scenario 3: Hybrid Topology (Pooled Clustered Site + Dedicated Tenants)

## Overview

In enterprise environments, organizations frequently require both architectures simultaneously:
1. **A mission-critical clustered application** requiring high availability, horizontal scaling, and zero-downtime rolling updates (`app.example.com`).
2. **Dedicated, isolated virtual hosts** for specific customers, internal portals, or legacy stateful applications (`tenant-a.example.com`, `tenant-b.example.com`).

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
                 │ L7 Host Routing               │
                 ▼                               ▼
       ┌──────────────────┐            ┌──────────────────┐
       │ Host: app.*      │            │ Host: tenant-*   │
       ▼                  ▼            ▼                  ▼
┌──────────────────────────────┐ ┌──────────────┐ ┌──────────────┐
│  HA Pool: be_app_example_com │ │  web-tenant-a│ │  web-tenant-b│
│  (Round-Robin Load Balanced) │ │  (1:1 Tenant)│ │  (1:1 Tenant)│
│  ┌────────────┐ ┌──────────┐ │ │  tenant-a.   │ │  tenant-b.   │
│  │web-pool-01 │ │web-pool-02││ │  example.com │ │  example.com │
│  └────────────┘ └──────────┘ │ └──────────────┘ └──────────────┘
└──────────────────────────────┘
```

## How It Works in HAProxy

HAProxy inspects the `external_fqdn` of each host in `groups['webservers']`. Webservers with matching FQDNs are grouped into load-balanced pools, while webservers with unique FQDNs are assigned dedicated 1:1 backends:

```haproxy
frontend fe_https
    # Clustered HA Pool
    acl is_app_example_com hdr(host) -i app.example.com
    use_backend be_app_example_com if is_app_example_com

    # Dedicated Tenants
    acl is_tenant_a_example_com hdr(host) -i tenant-a.example.com
    use_backend be_tenant_a_example_com if is_tenant_a_example_com

    acl is_tenant_b_example_com hdr(host) -i tenant-b.example.com
    use_backend be_tenant_b_example_com if is_tenant_b_example_com
```

## Database Layer (PostgreSQL or MySQL)

In Scenario 3, the database layer accommodates both the clustered application and the isolated tenant sites:
- **Central Core App DB (`app_db`)**: Dedicated to `web-pool-01` and `web-pool-02`.
- **Tenant Databases (`tenant_a_db`, `tenant_b_db`)**: Dedicated to `web-tenant-a` and `web-tenant-b` respectively.

This can be deployed on a shared database node (`db-01`) or partitioned across cloud-native managed databases:
```ini
[databases]
db-01 ansible_host=192.168.10.51 internal_ip=192.168.10.51 db_engine=postgresql

[databases:vars]
db_databases=[{"name":"app_db","user":"app_user","password":"CoreAppSecret2026!"},{"name":"tenant_a_db","user":"tenant_a_user","password":"TenantASecret2026!"},{"name":"tenant_b_db","user":"tenant_b_user","password":"TenantBSecret2026!"}]
```

## Cache & Message Broker Layer (Redis & RabbitMQ)

In Scenario 3, Redis and RabbitMQ support both the core pooled application and dedicated client tenants:
- **Redis (`redis-01`)**: Core webservers (`web-pool-01`, `web-pool-02`) share sessions in `db 0`, while isolated tenant apps use separate Redis logical databases (`db 1`, `db 2`).
- **RabbitMQ (`mq-01`)**: Hosts the primary `/app` vhost for pooled asynchronous processing, alongside isolated vhosts (`/tenant-a`, `/tenant-b`) for tenant workers. Management UI is accessible at `mq.example.com` via HAProxy.

```ini
[redis_servers]
redis-01 ansible_host=192.168.10.61 internal_ip=192.168.10.61

[rabbitmq_servers]
mq-01 ansible_host=192.168.10.71 internal_ip=192.168.10.71 rabbitmq_mgmt_fqdn=mq.example.com
```

## Quick Start

1. Deploy the hybrid cluster:
   ```bash
   ansible-playbook -i examples/topologies/scenario-3-hybrid/inventory.ini playbook.yml
   ```
2. Validate cluster health:
   ```bash
   ansible-playbook -i examples/topologies/scenario-3-hybrid/inventory.ini verify_cluster.yml
   ```
3. Run zero-downtime rolling maintenance:
   ```bash
   ansible-playbook -i examples/topologies/scenario-3-hybrid/inventory.ini rolling_maintenance.yml
   ```
