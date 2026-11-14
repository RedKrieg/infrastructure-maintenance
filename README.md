# Headless Ubuntu Initial Setup, Dynamic HAProxy & Webserver Suite

An automated, role-based Ansible suite to provision, harden, and orchestrate high-availability web architectures on headless Ubuntu systems. Designed with dynamic 1:1 host-to-FQDN mapping, edge SSL termination and certificate management on HAProxy frontends via `acme.sh` Let's Encrypt, and backend Nginx webservers with strict generic 404 fallbacks.

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
│   │   │   ├── firewall.yml         # Opens 80, 443, and 8404 in UFW
│   │   │   ├── certs.yml            # Manages SSL certs on proxy (bootstrap & acme.sh)
│   │   │   └── config.yml           # Deploys dynamic haproxy.cfg
│   │   └── templates/
│   │       └── haproxy.cfg.j2       # Dynamic Jinja2 template iterating over webservers
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

## Dynamic Architecture (10.0.0.0/8 Subnet Example)

```
                            Internet / Visitors
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
         ┌────────────────────┐           ┌────────────────────┐
         │      proxy-01      │           │      proxy-02      │
         │    (10.0.1.10)     │           │    (10.0.1.20)     │
         │ HAProxy + acme.sh  │           │ HAProxy + acme.sh  │
         │ (Decodes TLS 443)  │           │ (Decodes TLS 443)  │
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

### The Only Configurable: `external_fqdn`
In `inventory.ini`, assign the desired `external_fqdn` directly to each webserver host. The proxy role dynamically discovers these hosts from the inventory:

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

---

## How It Works

### 1. SSL Decoding & Certificates on the Proxies (`roles/proxy`)
- **SSL Termination**: All SSL/TLS is terminated at the proxy edge on port 443 (`bind *:443 ssl crt /etc/haproxy/certs/`).
- **Certificate Handling**:
  - `acme.sh` runs on the proxies.
  - Automatically provisions a bootstrap self-signed combined `.pem` for each discovered FQDN so HAProxy starts up cleanly on first run.
  - For HTTP-01 Let's Encrypt challenges, HAProxy routes `/.well-known/acme-challenge/` to a local `acme.sh` standalone listener on port `8888`.
  - All regular HTTP traffic on port 80 is automatically redirected to HTTPS (`http-request redirect scheme https unless is_acme_challenge`).
  - When `acme_issue_certs: true` is set, `acme.sh` issues genuine Let's Encrypt certificates and auto-renews them via cron.
- **Dynamic 1:1 Mapping**:
  HAProxy loops over `groups['webservers']` and automatically generates ACLs and backends:
  - `web1.example.com` ➔ routes to `10.0.1.11:80`
  - `web2.example.com` ➔ routes to `10.0.1.12:80`
  - `web3.example.com` ➔ routes to `10.0.1.13:80`
  - Any request not matching an enabled FQDN receives an immediate **404 Not Found**.

### 2. Backend Webservers with Generic 404 Fallback (`roles/webserver`)
- **Strict Generic 404**:
  The default catch-all server block (`/etc/nginx/conf.d/00-default-404.conf`) returns `404 Not Found\n` for any direct IP access, unrecognized Host header, or unconfigured domain.
- **Only the Assigned FQDN is Enabled**:
  Each webserver only enables a single virtual host matching its `external_fqdn` (`/var/www/{{ external_fqdn }}`).
- **HAProxy Real IP Integration**:
  Installs `/etc/nginx/conf.d/real_ip.conf` trusting the HAProxy proxy IPs (`groups['proxies']` and `10.0.0.0/8`). Nginx access logs and application headers record the visitor's genuine remote IP from `X-Forwarded-For`.

---

## How to Run

### Run the Entire Cluster Deployment
```bash
ansible-playbook -i inventory.ini playbook.yml
```

### Targeted Execution Using Tags
```bash
# Provision or update HAProxy load balancers only:
ansible-playbook -i inventory.ini playbook.yml --tags proxy

# Provision or update backend webservers only:
ansible-playbook -i inventory.ini playbook.yml --tags webserver

# Update user accounts and dotfiles only:
ansible-playbook -i inventory.ini playbook.yml --tags users

# Apply kernel and hardware tuning only:
ansible-playbook -i inventory.ini playbook.yml --tags tuning
```
