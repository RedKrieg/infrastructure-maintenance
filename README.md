# Headless Ubuntu Initial Setup, Dynamic HAProxy & Webserver Suite

An enterprise-grade, role-based Ansible suite to provision, harden, and orchestrate high-availability web architectures on headless Ubuntu systems. Designed with dynamic 1:1 host-to-FQDN mapping, Oracle Cloud Infrastructure (OCI) multi-fault-domain redundancy, centralized SSL certificate issuance with cluster-wide deduplication via `acme.sh`, and backend Nginx webservers with strict generic 404 fallbacks.

---

## Workspace Structure

```
.
├── ansible.cfg                      # Ansible defaults (pipelining, roles_path, YAML output)
├── inventory.ini                    # Inventory defining proxies & webservers with external_fqdn
├── playbook.yml                     # Main playbook orchestrating all plays and roles
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
│   │       └── sync-haproxy-certs.sh.j2 # Automated cron renewal rsync hook
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

## High-Redundancy Oracle Cloud Infrastructure (OCI) Architecture

To achieve the **highest level of redundancy** on Oracle Cloud Infrastructure, the two HAProxy frontend nodes are deployed across distinct **Fault Domains** (or separate Availability Domains) behind an **OCI Network Load Balancer (NLB)**:

```
                            Public Internet / Visitors
                                        │
                                        ▼
                  ┌───────────────────────────────────────────┐
                  │       OCI Network Load Balancer (NLB)     │
                  │        (Static Anycast Public IP)         │
                  │   Multi-Fault-Domain High Availability    │
                  └─────────────────────┬─────────────────────┘
                                        │ (Port 80 / 443)
                        ┌───────────────┴───────────────┐
                        ▼                               ▼
             ┌────────────────────┐           ┌────────────────────┐
             │      proxy-01      │           │      proxy-02      │
             │   (Fault Domain 1) │           │   (Fault Domain 2) │
             │    (10.0.1.10)     │           │    (10.0.1.20)     │
             │  Primary Cert Node │           │   Replica Proxy    │
             │ HAProxy + acme.sh  │           │      HAProxy       │
             └──────────┬─────────┘           └──────────┬─────────┘
                        │                                │
                        └───────────────┬────────────────┘
                                        │ (Plain HTTP / Port 80)
               ┌────────────────────────┼────────────────────────┐
               ▼                        ▼                        ▼
      ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
      │      web-01      │    │      web-02      │    │      web-03      │
      │   (10.0.1.11)    │    │   (10.0.1.12)    │    │   (10.0.1.13)    │
      │ web1.example.com │    │ web2.example.com │    │ web3.example.com │
      │ (Generic 404)    │    │ (Generic 404)    │    │ (Generic 404)    │
      └──────────────────┘    └──────────────────┘    └──────────────────┘
```

### Why OCI Network Load Balancer (NLB)?
1. **Zero Downtime Failover**: Operates at Layer 4 with sub-second health checks. If `proxy-01` undergoes kernel updates or hardware maintenance, OCI NLB instantly directs 100% of traffic to `proxy-02`.
2. **Transparent Client IP Preservation**: Preserves the original visitor's source IP address without needing complex headers.
3. **Multi-Fault Domain (FD) Resilience**: `proxy-01` in FD-1 and `proxy-02` in FD-2 ensures that a rack-level, power-unit, or hardware failure within an Oracle data center never brings down your frontends.

---

## Shared SSL Certificates & Deduplication

Requesting SSL certificates independently from multiple frontends causes **Let's Encrypt rate-limit bans** (5 duplicate certs/week) and causes **50% of HTTP-01 challenges to fail** when the challenge request hits `proxy-02` while `proxy-01` is verifying.

This suite solves this using a **Primary Issuer + Cluster Sharing** pattern:

### 1. Unified Challenge Forwarding
- `proxy-01` (`groups['proxies'][0]`) is the designated **Primary Certificate Node**.
- On **all** proxies (`proxy-01`, `proxy-02`), HAProxy routes `path_beg /.well-known/acme-challenge/` to `be_acme`.
- `be_acme` on `proxy-02` forwards the challenge over the internal `10.0.0.0/8` subnet directly to `proxy-01:8888`.
- **Result**: Whether Let's Encrypt hits `proxy-01` or `proxy-02`, the challenge is answered by `proxy-01:8888`. Challenges succeed 100% of the time with zero rate-limit waste.

### 2. Cluster Certificate Synchronization
- **During Provisioning**: The primary proxy generates/issues the certificates, and Ansible distributes the exact `.pem` bundles to all replica proxies in `/etc/haproxy/certs/`.
- **During Automatic Cron Renewals**:
  - `acme.sh` automatically renews certificates on `proxy-01` twice daily.
  - The renewal hook executes `/usr/local/bin/sync-haproxy-certs.sh`.
  - The script uses `rsync` over dedicated internal SSH keys to mirror `/etc/haproxy/certs/` to `proxy-02` and reloads HAProxy on both nodes.

### 3. Automated Zero-Touch Failover (If Primary Proxy Dies)
What happens if `proxy-01` is permanently offline or dead during a renewal cycle?
- **HAProxy Standby ACME Routing**:
  In `haproxy.cfg`, replica proxies configure `backend be_acme` with a health-checked primary server and a local backup:
  ```haproxy
  server acme_primary 10.0.1.10:8888 check fall 2 rise 2
  server acme_local 127.0.0.1:8888 check backup
  ```
  If `proxy-01` is down, HAProxy on replica proxies automatically routes incoming `/.well-known/acme-challenge/` requests to its own local port `8888`.
- **Standby Watchdog Cron (`acme-fallback-watchdog.sh`)**:
  - `acme.sh` is pre-installed on all replica proxies.
  - A daily watchdog runs on replicas at 03:25 AM. It checks certificate expiration via `openssl x509 -checkend`.
  - Under normal conditions (> 15 days remaining or Primary reachable), it takes no action.
  - If `proxy-01` is unreachable **and** certificates are within 15 days of expiration (`acme_fallback_renewal_days: 15`), the replica proxy automatically takes over, requests renewals from Let's Encrypt via local port 8888, bundles the certificates, and reloads HAProxy. Certificates never expire even if the primary host is dead for months.

---

## Inventory & Dynamic 1:1 Mapping

The only setting required per webserver is **`external_fqdn`** in **`inventory.ini`**:

```ini
[proxies]
proxy-01 ansible_host=10.0.1.10
proxy-02 ansible_host=10.0.1.20

[webservers]
web-01 ansible_host=10.0.1.11 external_fqdn=web1.example.com
web-02 ansible_host=10.0.1.12 external_fqdn=web2.example.com
web-03 ansible_host=10.0.1.13 external_fqdn=web3.example.com

[headless_nodes:children]
proxies
webservers
```

HAProxy on both proxies dynamically generates:
- `web1.example.com` ➔ routes to `10.0.1.11:80`
- `web2.example.com` ➔ routes to `10.0.1.12:80`
- `web3.example.com` ➔ routes to `10.0.1.13:80`
- Unmapped hostnames / IPs ➔ **404 Not Found**

---

## How to Run

### Full Fleet Provisioning
```bash
ansible-playbook -i inventory.ini playbook.yml
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
