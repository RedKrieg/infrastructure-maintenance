# Cloud & Backend Agnostic High-Availability Architecture

This architecture relies on a **generic Layer 4 (TCP passthrough) Ingress Load Balancer** distributing inbound HTTP/HTTPS traffic to a tier of headless Ubuntu HAProxy frontends.

Because Layer 4 operates at the transport layer without terminating TLS or altering HTTP headers:
- **Client Source IP addresses are preserved transparently** without proprietary headers or proxy protocols.
- **SSL termination, certificates, and virtual routing stay 100% inside your control** within the HAProxy cluster.
- **Zero Cloud Vendor Lock-In**: The same code runs on AWS, GCP, OpenStack, Azure, OCI, or bare metal with zero proprietary agent or cloud CLI dependencies.

```
                            Public Internet / Visitors
                                        │
                                        ▼
                   ┌───────────────────────────────────────────┐
                   │    Layer 4 Ingress Load Balancer (TCP)    │
                   │  (AWS NLB / GCP Passthrough / Octavia /   │
                   │      Keepalived VRRP / BGP Anycast)       │
                   └─────────────────────┬─────────────────────┘
                                         │ (Port 80 / 443)
                         ┌────────────────┼────────────────┐
                         ▼                ▼                ▼
              ┌────────────────────┐ ┌────────────────────┐ ┌────────────────────┐
              │      proxy-01      │ │      proxy-02      │ │      proxy-03      │
              │   Zone A / Host 1  │ │   Zone B / Host 2  │ │   Zone C / Host 3  │
              │ Primary Cert Node  │ │  Standby Rank 1    │ │  Standby Rank 2    │
              │ HAProxy + acme.sh  │ │ HAProxy + Watchdog │ │ HAProxy + Watchdog │
              └──────────┬─────────┘ └──────────┬─────────┘ └──────────┬─────────┘
                         │                      │                      │
                         └──────────────────────┼──────────────────────┘
                                                │ (Plain HTTP / Port 80)
                 ┌──────────────────────────────┼──────────────────────────────┐
                 ▼                              ▼                              ▼
        ┌──────────────────┐          ┌──────────────────┐          ┌──────────────────┐
        │      web-01      │          │      web-02      │          │      web-03      │
        │ web1.example.com │          │ web2.example.com │          │ web3.example.com │
        │ (Generic 404)    │          │ (Generic 404)    │          │ (Generic 404)    │
        └──────────────────┘          └──────────────────┘          └──────────────────┘
```

---

## Provider Drop-in Mapping

| Provider | Layer 4 Ingress Load Balancer | Fault Domain / Distribution | Private Subnet Example | Inventory Template |
| :--- | :--- | :--- | :--- | :--- |
| **AWS EC2** | **AWS Network Load Balancer (NLB)** (TCP 80/443 with cross-zone load balancing) | Multiple Availability Zones (`us-east-1a`, `1b`, `1c`) | `172.31.0.0/16` | [inventory.aws.ini](../examples/inventories/inventory.aws.ini) |
| **Google Cloud (GCP)** | **Regional External TCP/UDP Passthrough Network Load Balancer** | Multiple Compute Engine Zones (`us-central1-a`, `1-b`, `1-c`) | `10.128.0.0/20` | [inventory.gcp.ini](../examples/inventories/inventory.gcp.ini) |
| **OpenStack** | **Octavia Load Balancer** (TCP Amphora listener) or **Keepalived VIP** | Nova Server Group (`anti-affinity`) across hypervisors | `192.168.100.0/24` | [inventory.openstack.ini](../examples/inventories/inventory.openstack.ini) |
| **Oracle Cloud (OCI)** | **OCI Network Load Balancer (NLB)** (TCP listener) | Multiple Fault Domains (FD-1, FD-2, FD-3) | `10.0.0.0/16` | [inventory.ini](../inventory.ini) |
| **Bare Metal / On-Prem** | **Keepalived VRRP Floating IP** or **BGP Anycast (ECMP)** | Separate physical racks / PDUs | `10.x`, `172.16.x`, `192.168.x` | [inventory.ini](../inventory.ini) |

---

## Universal Network & Firewall Compatibility

- **RFC 1918 Private Subnets**: Out of the box, UFW and Nginx `real_ip` trust all standard private subnets (`10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`), allowing seamless operation regardless of private VPC CIDR blocks.
- **Zero Cloud Agent Dependencies**: The fleet provisions standard headless Ubuntu (20.04, 22.04, 24.04 LTS) images using standard SSH and sudo. No proprietary CLI tools, cloud agents, or IAM roles are required.

---

## Dynamic 1:1 Host-to-FQDN Routing Concept

In this architecture, HAProxy serves as an intelligent reverse proxy that routes traffic based on incoming HTTP `Host` headers directly to designated backend webservers.

- Each backend node specifies an `external_fqdn` in the inventory.
- HAProxy dynamically compiles ACL rules matching each `Host` header to its exact backend server.
- Non-matching or unmapped hostnames/IPs are caught by a strict generic 404 fallback on the backend, preventing information disclosure or unintended virtual host leakage.
