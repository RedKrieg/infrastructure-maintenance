# Headless Ubuntu Initial Setup, Dynamic HAProxy & Webserver Suite

An enterprise-grade, role-based Ansible suite to provision, harden, and orchestrate high-availability web architectures on headless Ubuntu systems. Designed to be **100% backend and cloud agnostic**—running identically across **AWS EC2**, **Google Cloud Platform (GCP)**, **OpenStack**, **Oracle Cloud (OCI)**, and **bare-metal/on-premises** infrastructure.

Features dynamic 1:1 host-to-FQDN mapping, cross-zone/multi-fault-domain Layer 4 redundancy, centralized SSL certificate issuance with cluster-wide deduplication via `acme.sh`, rank-based fallback line of succession with 1-day staggered renewal windows, self-healing boot-time certificate adoption, and backend Nginx webservers with strict generic 404 fallbacks.

---

## Workspace Structure

```
.
├── ansible.cfg                      # Ansible defaults (pipelining, roles_path, YAML output)
├── inventory.ini                    # Active cluster inventory (proxies & webservers with external_fqdn)
├── playbook.yml                     # Main playbook orchestrating all plays and roles
├── examples/
│   └── inventories/                 # Cloud-specific example inventory templates
│       ├── inventory.aws.ini        # AWS EC2 multi-AZ example (VPC 172.31.0.0/16)
│       ├── inventory.gcp.ini        # GCP Compute Engine multi-zone example (VPC 10.128.0.0/20)
│       └── inventory.openstack.ini  # OpenStack anti-affinity example (192.168.100.0/24)
├── vars/
│   └── admin_users.yml              # Central users configuration file (add new admins here)
├── group_vars/
│   ├── proxies.yml                  # Global proxy & acme.sh settings
│   └── webservers.yml               # Webserver trusted proxy subnets
├── roles/
│   ├── system_base/                 # Core packages, maintenance, kernel & hardware tuning
│   │   ├── defaults/main.yml
│   │   ├── handlers/main.yml
│   │   └── tasks/
│   ├── security/                    # Host security, UFW rate limiting & SSH hardening
│   │   ├── defaults/main.yml
│   │   ├── handlers/main.yml
│   │   └── tasks/
│   ├── admin_users/                 # Per-user provisioning, dotfiles & venv tooling
│   │   ├── defaults/main.yml
│   │   ├── files/
│   │   └── tasks/
│   ├── proxy/                       # HAProxy role (terminates SSL & routes 1:1 to backends)
│   │   ├── defaults/main.yml
│   │   ├── handlers/main.yml
│   │   ├── tasks/
│   │   │   ├── main.yml             # Task dispatcher
│   │   │   ├── packages.yml         # Installs haproxy, openssl, curl, socat, cron
│   │   │   ├── firewall.yml         # Opens 80, 443, 8404, and internal 8888 in UFW
│   │   │   ├── certs.yml            # Primary issuance & cluster-wide certificate distribution
│   │   │   └── config.yml           # Deploys dynamic haproxy.cfg
│   │   └── templates/
│   │       ├── haproxy.cfg.j2       # Dynamic Jinja2 template iterating over webservers
│   │       ├── check-and-adopt-cluster-certs.sh.j2 # Boot-time reconciliation & adoption
│   │       ├── sync-haproxy-certs.sh.j2            # Cluster-wide certificate push script
│   │       └── acme-fallback-watchdog.sh.j2        # 1-day staggered standby renewal watchdog
│   └── webserver/                   # Backend Nginx role (generic 404 & enabled FQDN site)
│       ├── defaults/main.yml
│       ├── handlers/main.yml
│       ├── tasks/
│       │   ├── main.yml             # Task dispatcher
│       │   ├── packages.yml         # Installs nginx
│       │   ├── firewall.yml         # Opens 80 in UFW
│       │   └── config.yml           # Deploys generic 404, real_ip, and FQDN virtual host
│       └── templates/
│           ├── default_404.conf.j2  # Generic 404 catch-all default_server block
│           ├── real_ip.conf.j2      # set_real_ip_from trusting HAProxy proxies
│           └── site.conf.j2         # Virtual host for assigned external_fqdn
├── authorized_keys                  # Default public key for redkrieg
├── bashrc_addons                    # Root copy of shell addons
├── gitconfig                        # Root copy of global git defaults
├── screenrc                         # Root copy of screen config
├── tmux.conf                        # Root copy of tmux config
├── venv_helpers.bash                # Root copy of venv tooling helpers
├── vimrc                            # Root copy of Vim configuration
├── workon-completion.bash           # Root copy of tab completion script
└── README.md                        # Documentation and usage guide
```

---

## Cloud & Backend Agnostic High-Availability Architecture

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

### Provider Drop-in Mapping

| Provider | Layer 4 Ingress Load Balancer | Fault Domain / Distribution | Private Subnet Example | Inventory Template |
| :--- | :--- | :--- | :--- | :--- |
| **AWS EC2** | **AWS Network Load Balancer (NLB)** (TCP 80/443 with cross-zone load balancing) | Multiple Availability Zones (`us-east-1a`, `1b`, `1c`) | `172.31.0.0/16` | [inventory.aws.ini](file:///home/redkrieg/Projects/ansible-stuff/examples/inventories/inventory.aws.ini) |
| **Google Cloud (GCP)** | **Regional External TCP/UDP Passthrough Network Load Balancer** | Multiple Compute Engine Zones (`us-central1-a`, `1-b`, `1-c`) | `10.128.0.0/20` | [inventory.gcp.ini](file:///home/redkrieg/Projects/ansible-stuff/examples/inventories/inventory.gcp.ini) |
| **OpenStack** | **Octavia Load Balancer** (TCP Amphora listener) or **Keepalived VIP** | Nova Server Group (`anti-affinity`) across hypervisors | `192.168.100.0/24` | [inventory.openstack.ini](file:///home/redkrieg/Projects/ansible-stuff/examples/inventories/inventory.openstack.ini) |
| **Oracle Cloud (OCI)** | **OCI Network Load Balancer (NLB)** (TCP listener) | Multiple Fault Domains (FD-1, FD-2, FD-3) | `10.0.0.0/16` | [inventory.ini](file:///home/redkrieg/Projects/ansible-stuff/inventory.ini) |
| **Bare Metal / On-Prem** | **Keepalived VRRP Floating IP** or **BGP Anycast (ECMP)** | Separate physical racks / PDUs | `10.x`, `172.16.x`, `192.168.x` | [inventory.ini](file:///home/redkrieg/Projects/ansible-stuff/inventory.ini) |

### Universal Network & Firewall Compatibility
- **RFC 1918 Private Subnets**: Out of the box, UFW and Nginx `real_ip` trust all standard private subnets (`10.0.0.0/8`, `172.16.0.0/12`, and `192.168.0.0/16`), allowing seamless operation regardless of private VPC CIDR blocks.
- **Zero Cloud Agent Dependencies**: The fleet provisions standard headless Ubuntu (20.04, 22.04, 24.04 LTS) images using standard SSH and sudo. No proprietary CLI tools, cloud agents, or IAM roles are required.

---

## Shared SSL Certificates, Succession & Failover

Requesting SSL certificates independently from multiple frontends causes **Let's Encrypt rate-limit bans** (5 duplicate certs/week) and causes **HTTP-01 challenge failures** when validation requests hit a proxy other than the one requesting the cert.

This suite solves this using a **Rank-Based Line of Succession + Self-Healing Cluster Mesh**:

### 1. Unified Challenge Forwarding with Succession
- `proxy-01` (`groups['proxies'][0]`) is the designated **Primary Certificate Node**.
- On **all** proxies, HAProxy routes `path_beg /.well-known/acme-challenge/` to `backend be_acme`.
- `be_acme` lists all cluster proxies in rank order:
  - Primary (`proxy-01`) is active.
  - Replicas (`proxy-02`, `proxy-03`) are configured with `backup`.
- **Result**: Whether Let's Encrypt hits `proxy-01`, `proxy-02`, or `proxy-03`, challenges route directly to the active certificate requester in succession order.

### 2. Multi-Directional Cluster Certificate Synchronization
- **Provisioning**: The primary proxy generates/issues certificates, and Ansible distributes the exact `.pem` bundles to all replica proxies in `/etc/haproxy/certs/`.
- **Automatic Cron Renewals**:
  - `acme.sh` renews certificates on the active node.
  - The renewal hook executes `/usr/local/bin/sync-haproxy-certs.sh`.
  - The script uses `rsync` over dedicated cluster SSH keys (`/root/.ssh/id_ed25519_certsync`) to mirror `/etc/haproxy/certs/` and `/root/.acme.sh/` to all online peer proxies, reloading HAProxy across the cluster.

### 3. Rank-Based Line of Succession & 1-Day Staggered Windows
What keeps `proxy-02` and `proxy-03` from trying to renew simultaneously if `proxy-01` is offline?
- **1-Day Staggered Thresholds**:
  Standby watchdogs calculate their renewal expiration threshold staggered by **1 day per rank**:
  `Threshold = acme_fallback_renewal_days - (rank - 1)`
  - `proxy-02` (Rank 1): triggers at **15 days** remaining.
  - `proxy-03` (Rank 2): triggers at **14 days** remaining.
  - `proxy-04` (Rank 3): triggers at **13 days** remaining.
  `proxy-02` has a full 24-hour window to renew before `proxy-03` even considers checking.
- **Rank Succession Reachability Check**:
  Before attempting renewal, any standby proxy queries all higher-ranking proxies (e.g., `proxy-03` checks `proxy-01` and `proxy-02`). If any higher-ranking node is reachable over SSH or ICMP ping, the standby stands down and yields renewal authority.
- **Pre-Check Cluster Reconciliation**:
  Before testing expiration thresholds, each watchdog runs `/usr/local/bin/check-and-adopt-cluster-certs.sh`. If a peer already renewed, the local node adopts the newer certificate immediately, resetting its local certificate lifetime to 90 days.

### 4. Node Recovery & Automatic Rank Resumption
What happens when a higher-priority proxy (such as `proxy-01`) comes back online **after** a standby proxy renewed the certificate?
1. **Boot-Time Systemd Reconciliation Service (`haproxy-cert-reconcile.service`)**:
   - Runs `check-and-adopt-cluster-certs.sh` **before** `haproxy.service` starts.
   - Compares certificate expiration epochs (`openssl x509 -enddate`) against all peer proxies.
   - Discovers that a standby node has a newer certificate (validity difference > 1 day).
   - Copies the newer `.pem` bundle and `acme.sh` store from the peer via `rsync`.
   - HAProxy starts up with the fresh, renewed certificate.
2. **Seamless Rank Resumption**:
   - Because `proxy-01` is now online and has the renewed cert, standby watchdogs on `proxy-02` and `proxy-03` detect `proxy-01` as reachable and stand down.
   - `proxy-01` automatically resumes its rank as the primary certificate authority for future scheduled renewals.

---

## Inventory & Dynamic 1:1 Mapping

The only setting required per webserver is **`external_fqdn`** in your inventory file:

```ini
[proxies]
proxy-01 ansible_host=10.0.1.10
proxy-02 ansible_host=10.0.1.20
proxy-03 ansible_host=10.0.1.30

[webservers]
web-01 ansible_host=10.0.1.11 external_fqdn=web1.example.com
web-02 ansible_host=10.0.1.12 external_fqdn=web2.example.com
web-03 ansible_host=10.0.1.13 external_fqdn=web3.example.com

[headless_nodes:children]
proxies
webservers
```

HAProxy on all proxies dynamically generates:
- `web1.example.com` ➔ routes to `10.0.1.11:80`
- `web2.example.com` ➔ routes to `10.0.1.12:80`
- `web3.example.com` ➔ routes to `10.0.1.13:80`
- Unmapped hostnames / IPs ➔ **404 Not Found**

---

## How to Run

### Full Fleet Provisioning
```bash
# Using the default inventory:
ansible-playbook -i inventory.ini playbook.yml

# Or deploying to AWS EC2:
ansible-playbook -i examples/inventories/inventory.aws.ini playbook.yml

# Or deploying to GCP Compute Engine:
ansible-playbook -i examples/inventories/inventory.gcp.ini playbook.yml

# Or deploying to OpenStack:
ansible-playbook -i examples/inventories/inventory.openstack.ini playbook.yml
```

### Targeted Execution Using Tags
```bash
# Provision or update HAProxy load balancers only:
ansible-playbook -i inventory.ini playbook.yml --tags proxy

# Synchronize certificates only:
ansible-playbook -i inventory.ini playbook.yml --tags certs

# Provision or update backend webservers only:
ansible-playbook -i inventory.ini playbook.yml --tags webserver

# Update user accounts and dotfiles only:
ansible-playbook -i inventory.ini playbook.yml --tags users
```
