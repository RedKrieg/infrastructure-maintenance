# Headless Ubuntu Initial Setup, HAProxy & Webserver Suite

An enterprise-grade, role-based Ansible solution to provision, harden, and orchestrate high-availability web architectures on headless Ubuntu systems. Modularized into isolated roles with automated kernel & storage tuning, UFW connection rate limiting, SSH daemon hardening, Vim/Tmux/Screen/Git defaults, multi-frontend HAProxy routing, and multi-backend Nginx webservers using `acme.sh` Let's Encrypt SSL certificates with a strict generic 404 fallback.

---

## Workspace Structure

```
.
├── ansible.cfg                      # Ansible defaults (pipelining, roles_path, YAML output)
├── inventory.ini                    # Inventory defining proxies and webservers on 10/8 subnet
├── playbook.yml                     # Main playbook orchestrating all plays and roles
├── vars/
│   └── admin_users.yml              # Central users configuration file (add new admins here)
├── group_vars/
│   ├── proxies.yml                  # HAProxy endpoint mappings (ports, paths, targets)
│   └── webservers.yml               # Nginx enabled sites, real_ip proxies, acme.sh config
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
│   ├── proxy/                       # HAProxy load balancer role
│   │   ├── defaults/main.yml
│   │   ├── handlers/main.yml
│   │   ├── tasks/
│   │   │   ├── main.yml             # Task dispatcher
│   │   │   ├── packages.yml         # Installs haproxy
│   │   │   ├── firewall.yml         # Opens 80, 443, and 8404 in UFW
│   │   │   └── config.yml           # Deploys haproxy.cfg and 404.http fallback
│   │   └── templates/
│   │       └── haproxy.cfg.j2       # Dynamic frontend ports/paths to targets template
│   └── webserver/                   # Nginx, 404 catch-all, and acme.sh SSL role
│       ├── defaults/main.yml
│       ├── handlers/main.yml
│       ├── tasks/
│       │   ├── main.yml             # Task dispatcher
│       │   ├── packages.yml         # Installs nginx, ssl-cert, curl, socat
│       │   ├── firewall.yml         # Opens 80 and 443 in UFW
│       │   ├── default_404.yml      # Removes default site, sets generic 404 and real_ip
│       │   ├── acme.yml             # Installs acme.sh and sets default CA to Let's Encrypt
│       │   └── sites.yml            # Creates docroots, bootstrap/real certs, vhosts
│       └── templates/
│           ├── default_404.conf.j2  # Generic 404 catch-all default_server block
│           ├── real_ip.conf.j2      # set_real_ip_from trusting HAProxy proxies
│           └── site.conf.j2         # Virtual host with HTTP-01 challenge & SSL
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

## Example Architecture: 2 Proxies & 3 Webservers (10.0.0.0/8 Subnet)

The included configuration illustrates an active-active frontend proxy architecture forwarding traffic to a pool of three backend webservers:

```
                          Internet / Clients
                                  │
                  ┌───────────────┴───────────────┐
                  ▼                               ▼
       ┌────────────────────┐           ┌────────────────────┐
       │      proxy-01      │           │      proxy-02      │
       │    (10.0.1.10)     │           │    (10.0.1.20)     │
       │      HAProxy       │           │      HAProxy       │
       └──────────┬─────────┘           └──────────┬─────────┘
                  │                                │
                  └───────────────┬────────────────┘
                                  ▼
         ┌────────────────────────┼────────────────────────┐
         ▼                        ▼                        ▼
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│      web-01      │    │      web-02      │    │      web-03      │
│   (10.0.1.11)    │    │   (10.0.1.12)    │    │   (10.0.1.13)    │
│ Nginx + acme.sh  │    │ Nginx + acme.sh  │    │ Nginx + acme.sh  │
└──────────────────┘    └──────────────────┘    └──────────────────┘
```

### IP Allocations:
- **Frontend Proxies**:
  - `proxy-01`: `10.0.1.10`
  - `proxy-02`: `10.0.1.20`
- **Backend Webservers**:
  - `web-01`: `10.0.1.11`
  - `web-02`: `10.0.1.12`
  - `web-03`: `10.0.1.13`

---

## Role 1: `proxy` (HAProxy Load Balancer)

Configured via **`group_vars/proxies.yml`** (or `roles/proxy/defaults/main.yml`).

### Features:
1. **Frontend Port and Path Mapping**:
   Maps incoming requests by domain name, URL path, and port to backend target pools.
2. **TLS Routing**:
   - On Port 80 (`mode http`): Forwards HTTP requests to webservers, injects `X-Forwarded-For` and `X-Forwarded-Proto`, and routes `/.well-known/acme-challenge/` directly to backend webroots for Let's Encrypt validation.
   - On Port 443 (`mode tcp`): Inspects the TLS Client Hello SNI (`req_ssl_sni`) and routes the encrypted stream directly to the target webserver pool. The backend webservers terminate TLS using their own `acme.sh` certificates.
3. **Built-in HAProxy Stats Dashboard**:
   Accessible on port `8404` at `/stats` with authentication.
4. **Fallback 404**:
   Unmapped requests hitting the proxy receive a clean HTTP 404.

### Example Endpoint Mapping (`group_vars/proxies.yml`):
```yaml
proxy_endpoints:
  - name: "app1_endpoint"
    frontend_port: 80
    ssl: true
    hosts:
      - "app1.example.com"
      - "www.app1.example.com"
    paths:
      - "/app1"
      - "/api"
    balance: "roundrobin"
    targets:
      - { name: "web-01", ip: "10.0.1.11", port: 80, ssl_port: 443, check: true }
      - { name: "web-02", ip: "10.0.1.12", port: 80, ssl_port: 443, check: true }
      - { name: "web-03", ip: "10.0.1.13", port: 80, ssl_port: 443, check: true }

  - name: "app2_endpoint"
    frontend_port: 80
    ssl: true
    hosts:
      - "app2.example.com"
    paths:
      - "/"
    balance: "roundrobin"
    targets:
      - { name: "web-02", ip: "10.0.1.12", port: 80, ssl_port: 443, check: true }
      - { name: "web-03", ip: "10.0.1.13", port: 80, ssl_port: 443, check: true }
```

---

## Role 2: `webserver` (Nginx, 404 Catch-All & acme.sh SSL)

Configured via **`group_vars/webservers.yml`** (or `roles/webserver/defaults/main.yml`).

### Features:
1. **Generic 404 Catch-All**:
   Removes the default Nginx welcome site and installs `/etc/nginx/conf.d/00-default-404.conf`. Any visitor accessing via direct IP address, unknown hostname, or a disabled site receives an instant `404 Not Found\n`.
2. **HAProxy Real IP Integration**:
   Installs `/etc/nginx/conf.d/real_ip.conf` configuring `set_real_ip_from` for each proxy (`10.0.1.10`, `10.0.1.20`, `10.0.0.0/8`). Nginx access logs and application headers reflect the visitor's genuine remote IP.
3. **acme.sh & Let's Encrypt**:
   - Installs `acme.sh` in `/root/.acme.sh` with Let's Encrypt as the default CA.
   - Configures `/var/www/letsencrypt` as the HTTP-01 challenge webroot.
   - Generates initial self-signed bootstrap certificates so Nginx starts immediately on fresh servers without certificate errors.
   - When `acme_issue_certs: true`, requests valid certificates from Let's Encrypt and sets up daily automatic renewal hooks.
4. **Virtual Hosts**:
   Generates Nginx virtual hosts in `/etc/nginx/sites-available/` with HTTP-to-HTTPS redirection and document roots in `/var/www/<sitename>`.

### Example Sites Configuration (`group_vars/webservers.yml`):
```yaml
haproxy_frontend_ips:
  - "10.0.1.10"
  - "10.0.1.20"
  - "10.0.0.0/8"

webserver_sites:
  - name: "app1"
    domain: "app1.example.com"
    aliases:
      - "www.app1.example.com"
    root: "/var/www/app1"
    index: "index.html index.htm"
    enabled: true
    ssl_enabled: true

  - name: "app2"
    domain: "app2.example.com"
    root: "/var/www/app2"
    index: "index.html index.htm"
    enabled: true
    ssl_enabled: true
```

---

## How to Run

### 1. Run the Entire Suite (Base, Security, Users, Proxies, Webservers)
```bash
ansible-playbook -i inventory.ini playbook.yml
```

### 2. Run Only Proxies or Only Webservers
```bash
# Provision HAProxy load balancers only:
ansible-playbook -i inventory.ini playbook.yml --tags proxy

# Provision Webservers & SSL only:
ansible-playbook -i inventory.ini playbook.yml --tags webserver
```

### 3. Run Targeted Sub-Tasks
```bash
# Update HAProxy routing endpoints:
ansible-playbook -i inventory.ini playbook.yml --tags haproxy

# Update Nginx virtual hosts and sites:
ansible-playbook -i inventory.ini playbook.yml --tags sites

# Update Admin Users only:
ansible-playbook -i inventory.ini playbook.yml --tags users
```
