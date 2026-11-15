# Headless Ubuntu Initial Setup, Dynamic HAProxy & Webserver Suite

An enterprise-grade, role-based Ansible suite to provision, harden, and orchestrate high-availability web architectures on headless Ubuntu systems (20.04, 22.04, 24.04 LTS). Designed to be **100% backend and cloud agnostic**—running identically across **AWS EC2**, **Google Cloud Platform (GCP)**, **OpenStack**, **Oracle Cloud (OCI)**, and **bare-metal/on-premises** infrastructure.

Features dynamic 1:1 host-to-FQDN mapping, cross-zone/multi-fault-domain Layer 4 redundancy, centralized SSL certificate issuance with cluster-wide deduplication via `acme.sh`, rank-based fallback line of succession with 1-day staggered renewal windows, self-healing boot-time certificate adoption, and backend Nginx webservers with strict generic 404 fallbacks.

---

## Workspace Structure

```
.
├── ansible.cfg                      # Ansible defaults (pipelining, roles_path, YAML output)
├── inventory.ini                    # Active cluster inventory (proxies & webservers with external_fqdn)
├── playbook.yml                     # Main playbook orchestrating all plays and roles
├── backup_cluster.yml               # Multi-tier cluster backup & disaster recovery export playbook
├── restore_cluster.yml              # Cluster disaster recovery restore & reconciliation playbook
├── verify_cluster.yml               # Automated post-deployment smoke test & compliance verification
├── docs/                            # Modular architecture and operational documentation
│   ├── architecture.md              # Cloud-agnostic Layer 4 ingress architecture and provider mapping
│   ├── keepalived-baremetal.md      # Bare Metal HA with Keepalived VRRP floating IP & health tracking
│   ├── ssl-certificates.md          # Multi-node ACME line of succession, sync scripts & recovery
│   ├── internal-tls.md              # Zero-Trust internal TLS encryption between HAProxy and Nginx
│   ├── proxy-security.md            # HTTP/2, HSTS, rate limiting (300/10s), health checks & stats ACL
│   ├── waf-coraza.md                # Coraza WAF via HAProxy SPOE & OWASP Core Rule Set (default on)
│   ├── security-vault.md            # Ansible Vault secrets management & credential encryption
│   ├── centralized-logging.md       # Cluster log shipping via rsyslog with 60-day retention
│   ├── teleport-access.md           # Teleport JIT sudo access, RBAC roles & CLI helper scripts
│   ├── monitoring.md                # Native HAProxy Prometheus metrics, alert rules & retention
│   ├── grafana-dashboards.md        # Grafana & Node Exporter telemetry, dashboards & PromQL alerts
│   ├── backup-and-disaster-recovery.md # Multi-tier disaster recovery, remote targets & restore steps
│   ├── verification.md              # Automated smoke testing, security assertions & compliance checks
│   ├── deployment.md                # Inventory setup, cloud templates, and targeted Ansible tags
│   ├── dynamic-inventory.md         # AWS, GCP, and Azure tag-based dynamic discovery plugins
│   ├── aws-ec2-setup.md             # AWS EC2 quickstart: AWS CLI, VPC, subnets across AZs & EC2 automation
│   ├── gcp-compute-setup.md         # GCP quickstart: gcloud CLI, auth & automated VM provisioning
│   ├── azure-setup.md               # Azure quickstart: az CLI, VNet, NSG & automated VM provisioning
│   ├── oci-compute-setup.md         # OCI quickstart: oci CLI, VCN, Fault Domains & VM provisioning
│   └── openstack-setup.md           # OpenStack quickstart: clouds.yaml, anti-affinity & Nova provisioning
├── examples/
│   ├── inventories/                 # Cloud-specific example inventory templates & dynamic plugins
│   │   ├── inventory.aws.ini        # AWS EC2 multi-AZ example (VPC 172.31.0.0/16)
│   │   ├── inventory.gcp.ini        # GCP Compute Engine multi-zone example (VPC 10.128.0.0/20)
│   │   ├── inventory.azure.ini      # Microsoft Azure multi-zone example (VNet 10.240.0.0/16)
│   │   ├── inventory.oci.ini        # Oracle Cloud Infrastructure multi-FD example (VCN 10.0.0.0/16)
│   │   ├── inventory.openstack.ini  # OpenStack anti-affinity example (192.168.100.0/24)
│   │   ├── aws_ec2.yml              # AWS EC2 dynamic inventory plugin configuration
│   │   ├── gcp_compute.yml          # GCP dynamic inventory plugin configuration
│   │   └── azure_rm.yml             # Microsoft Azure dynamic inventory plugin configuration
│   └── provisioning/                # Cloud VM and network provisioning automation
│       ├── provision_aws.yml        # Ansible playbook provisioning AWS VPC, subnets & EC2 instances
│       ├── provision_gcp.yml        # Ansible playbook provisioning GCP VPC, firewalls & VMs
│       ├── provision_azure.yml      # Ansible playbook provisioning Azure VNet, NSG & VMs
│       ├── provision_oci.yml        # Ansible playbook provisioning OCI VCN, subnets & VMs
│       ├── provision_openstack.yml  # Ansible playbook provisioning OpenStack networks & Nova VMs
│       ├── deprovision_*.yml        # Teardown playbooks for clean resource removal
│       └── create_*_instances.sh    # Direct CLI shell scripts for zero-dependency provisioning
├── vars/
│   └── admin_users.yml              # Central users configuration file (admins, credentials, public keys)
├── group_vars/
│   ├── all/                         # Global variables across all hosts
│   │   ├── vault.yml                # Ansible Vault encrypted secrets (stats, tokens, passwords)
│   │   └── vault.example.yml        # Unencrypted template reference
│   ├── proxies.yml                  # Global proxy & acme.sh settings
│   └── webservers.yml               # Webserver trusted proxy subnets
├── roles/
│   ├── system_base/                 # Core packages, maintenance, kernel & hardware tuning
│   ├── security/                    # Host security, UFW rate limiting & SSH hardening (MaxAuthTries 10)
│   ├── admin_users/                 # Per-user provisioning, dotfiles & venv tooling
│   ├── keepalived/                  # Bare metal HA with VRRP floating IP & health check scripts
│   ├── node_exporter/               # Host metrics telemetry agent (port 9100) across all nodes
│   ├── proxy/                       # HAProxy role (terminates SSL, Coraza WAF, routes 1:1 to backends)
│   ├── webserver/                   # Backend Nginx role (generic 404 & internal TLS encryption)
│   ├── central_logging/             # Centralized log collection (server & shipper) with 60-day retention
│   ├── prometheus_server/           # Standalone Prometheus server role (port 9090, 60d retention, alert rules)
│   ├── grafana/                     # Grafana visualization server (port 3000, pre-built dashboards)
│   ├── teleport_server/             # Teleport Auth & Proxy Service role (ports 3080/3023/3024)
│   └── teleport_node/               # Teleport SSH Node Service role (reverse tunnels, JIT host users)
├── tests/
│   └── run_tests.sh                 # Local test runner for syntax checks & shell script validation
└── .github/
    └── workflows/ci.yml             # Automated CI pipeline for linting and syntax checks
```

---

## Quickstart

```bash
# Validate playbook syntax against active inventory:
ansible-playbook -i inventory.ini playbook.yml --syntax-check

# Provision the entire cluster:
ansible-playbook -i inventory.ini playbook.yml
```

For cloud-specific inventories (AWS, GCP, Azure, OCI, OpenStack) or targeted execution by tags (`proxy`, `certs`, `webserver`, `monitoring`, `teleport_server`, `teleport_node`, `users`), see the [Deployment Guide](docs/deployment.md).

---

## Documentation Index

Comprehensive technical documentation is organized into modular guides in the [`docs/`](docs/) directory:

| Document | Description | Key Topics Included |
| :--- | :--- | :--- |
| **[Architecture](docs/architecture.md)** | Cloud-Agnostic High-Availability Architecture | • Generic Layer 4 Ingress Load Balancer (TCP Passthrough)<br>• Transparent client IP preservation with zero cloud lock-in<br>• Provider drop-in mapping table (AWS NLB, GCP Passthrough, Azure LB, OCI NLB, Octavia, Bare Metal)<br>• RFC 1918 universal subnet compatibility & zero-cloud-agent model<br>• Dynamic 1:1 host-to-FQDN reverse proxy routing concept |
| **[Bare Metal HA (Keepalived)](docs/keepalived-baremetal.md)** | Layer 4 VRRP Ingress Redundancy | • High availability on bare metal / private clouds without managed cloud load balancers<br>• Automated health-checking tracking script (`check_haproxy.sh`) with dynamic priority reduction<br>• Kernel sysctl tuning (`net.ipv4.ip_nonlocal_bind = 1`) & UFW protocol 112 rules<br>• Unicast peer discovery and non-preemptive failback protection |
| **[SSL Certificates & Failover](docs/ssl-certificates.md)** | Shared SSL Certificates, Succession & Recovery | • Cluster-wide HTTP-01 challenge routing via `backend be_acme`<br>• Automated `sync-haproxy-certs.sh` push over dedicated cluster SSH keys<br>• Rank-based fallback line of succession with 1-day staggered renewal windows<br>• Active SSH protocol negotiation checks (`ssh-keyscan` key exchange & RFC 4253 banner check)<br>• Boot-time reconciliation service (`haproxy-cert-reconcile.service`) & seamless rank resumption |
| **[Zero-Trust Internal TLS](docs/internal-tls.md)** | Backend Encryption & Certificate Provisioning | • Zero-trust end-to-end encryption between HAProxy edge load balancers and backend webservers<br>• Automated 4096-bit RSA key and internal TLS certificate provisioning for Nginx hosts<br>• HAProxy backend SSL re-encryption (`ssl verify none`) with modern cipher suites and HTTP/2 |
| **[Proxy Security & Hardening](docs/proxy-security.md)** | Edge Hardening, Performance & Access Control | • HTTP/2 ALPN negotiation (`h2,http/1.1`) with HTTP/1.1 fallback<br>• Security response headers (`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`) & HSTS (1 year preload)<br>• In-memory stick-table volumetric rate limiting (300 req/10s $\rightarrow$ HTTP 429)<br>• Active HTTP backend health checks (`option httpchk` with Host header & regex rstatus)<br>• Dynamic stats & Prometheus ACL whitelist (IPs, CIDRs, dynamic FQDN resolution script & systemd timer)<br>• 60-day log retention via logrotate (`copytruncate`) and journald `MaxRetentionSec=60day` |
| **[Teleport Access & Sudo Management](docs/teleport-access.md)** | Centralized Access & Dynamic Elevation | • Zero-trust access architecture: Auth/Proxy service and outbound reverse tunnels<br>• Automatic host user provisioning (`create_host_user_mode: keep`)<br>• RBAC role hierarchy: `lead-admin`, unprivileged `junior`, and temporary `elevated-sudo`<br>• Just-In-Time (JIT) access request and approval workflow<br>• Built-in CLI helper scripts and shell aliases (`tlogin`, `tsudo`, `tstatus`, `tdrop`, `tssh`, `tapprove`)<br>• End-to-end junior administrator workflow walkthrough |
| **[Prometheus Monitoring](docs/monitoring.md)** | Metrics Scraping & Centralized Monitoring | • Native HAProxy Prometheus exporter (`/metrics` on port 8404)<br>• Unified ACL whitelist and HTTP basic authentication matching stats UI<br>• Automatic whitelisting of inventory `[monitoring]` group hosts<br>• Standalone Prometheus server role (`roles/prometheus_server` on port 9090)<br>• Dynamic proxy scrape target discovery and configuration<br>• Automated `promtool check config` validation, 60-day TSDB retention, and UFW isolation |
| **[Grafana & Hardware Telemetry](docs/grafana-dashboards.md)** | Visual Dashboards & Fleet Observability | • Grafana server deployment on port 3000 with auto-provisioned Prometheus datasource<br>• Universal Node Exporter deployment (port 9100) across all cluster hosts<br>• Pre-configured `HAProxy & Coraza WAF Overview` dashboard (traffic, errors, WAF blocks)<br>• Pre-configured `Fleet Hardware Health` dashboard (CPU, memory, disk, network throughput) |
| **[Backup & Disaster Recovery](docs/backup-and-disaster-recovery.md)** | Multi-Tier Backup & Restoration | • Automated `backup_cluster.yml` and `restore_cluster.yml` playbooks<br>• Configurable targets: local controller disk, offsite SSH/SFTP server, or AWS S3 / MinIO<br>• Complete capture of HAProxy configs, ACME certs, Teleport state, Nginx sites, and Prometheus TSDB<br>• Verifiable restore execution with safety checks and automatic service recovery |
| **[Cluster Verification & Smoke Tests](docs/verification.md)** | Post-Deployment Compliance Testing | • Automated non-destructive cluster health validation via `verify_cluster.yml`<br>• HTTP-to-HTTPS redirect validation and default 404 catch-all verification<br>• Coraza WAF synthetic SQLi injection block testing<br>• Prometheus, Grafana, and Node Exporter metrics endpoint assertion |
| **[Deployment & Operations](docs/deployment.md)** | Inventory Setup & Execution Guide | • Inventory layout & dynamic 1:1 mapping syntax (`external_fqdn`)<br>• Cloud-specific inventory templates (AWS, GCP, Azure, OCI, OpenStack, bare-metal)<br>• Full fleet provisioning commands<br>• Granular execution reference with Ansible tags (`proxy`, `certs`, `webserver`, `monitoring`, `teleport_server`, `teleport_node`, `users`)<br>• Pre-flight syntax validation instructions |
| **[AWS EC2 Setup Guide](docs/aws-ec2-setup.md)** | AWS EC2 Quickstart & Instance Provisioning | • Complete beginner guide for AWS EC2<br>• Installing AWS CLI v2 & authentication (`aws configure`, SSO)<br>• Automated instance provisioning with Ansible (`examples/provisioning/provision_aws.yml`)<br>• Custom VPC, multi-AZ subnets (`us-east-1a`, `1b`, `1c`), and security groups<br>• Direct CLI script (`create_aws_instances.sh`) & Network Load Balancer (NLB) setup |
| **[GCP Compute Setup Guide](docs/gcp-compute-setup.md)** | Google Cloud Quickstart & Instance Provisioning | • Complete beginner guide for Google Cloud Platform (GCP)<br>• Installing `gcloud` CLI & authentication (`gcloud auth login`, ADC)<br>• Automated instance provisioning with Ansible (`examples/provisioning/provision_gcp.yml`)<br>• Custom VPC, subnet (`10.128.0.0/20`), firewalls, and multi-zone VM placement<br>• Direct CLI script (`create_gcp_instances.sh`) & Regional Passthrough NLB setup |
| **[Azure Setup Guide](docs/azure-setup.md)** | Microsoft Azure Quickstart & Instance Provisioning | • Complete beginner guide for Microsoft Azure<br>• Installing Azure CLI (`az`) & authentication (`az login`, Service Principal)<br>• Automated instance provisioning with Ansible (`examples/provisioning/provision_azure.yml`)<br>• Resource Groups, VNets, Subnets, NSGs, and multi-zone Ubuntu VMs (`1`, `2`, `3`)<br>• Direct CLI script (`create_azure_instances.sh`) & Azure Standard Load Balancer setup |
| **[OCI Compute Setup Guide](docs/oci-compute-setup.md)** | Oracle Cloud Quickstart & Instance Provisioning | • Complete beginner guide for Oracle Cloud Infrastructure (OCI)<br>• Installing OCI CLI & authentication (`oci setup config`, API signing keys)<br>• Automated instance provisioning with Ansible (`examples/provisioning/provision_oci.yml`)<br>• VCN, regional subnets (`10.0.1.0/24`), and multi-Fault Domain instances (`FD-1`, `FD-2`, `FD-3`)<br>• Direct CLI script (`create_oci_instances.sh`) & OCI Network Load Balancer setup |
| **[OpenStack Setup Guide](docs/openstack-setup.md)** | OpenStack Quickstart & Instance Provisioning | • Complete beginner guide for OpenStack clouds<br>• Installing OpenStack CLI & authentication via `clouds.yaml`<br>• Automated instance provisioning with Ansible (`examples/provisioning/provision_openstack.yml`)<br>• Nova anti-affinity server groups across physical hypervisors, Neutron networks & routers<br>• Direct CLI script (`create_openstack_instances.sh`) & Octavia Load Balancer setup |
| **[Coraza WAF Guide](docs/waf-coraza.md)** | Web Application Firewall Integration | • HAProxy Stream Processing Offload Engine (SPOE) architecture<br>• OWASP Core Rule Set (CRS) inspection for SQLi, XSS, Path Traversal & RCE<br>• Enabled by default with zero-overhead async TCP daemon socket (`coraza-spoa`)<br>• Declarative rules configuration in `/etc/coraza/coraza.conf` |
| **[Ansible Vault Secrets](docs/security-vault.md)** | Credentials Encryption & Security | • Centralized secrets management via `group_vars/all/vault.yml`<br>• Encrypted protection for stats passwords, Teleport join tokens & Prometheus credentials<br>• Step-by-step encryption workflows with `.vault_pass` and `--vault-password-file`<br>• Built-in `.gitignore` guards preventing accidental token leaks |
| **[Centralized Logging](docs/centralized-logging.md)** | Cluster Log Aggregation & 60-Day Storage | • Lightweight TCP log forwarding via `rsyslog` across all cluster nodes<br>• Centralized log collector on monitoring node storing in `/var/log/remote/%HOSTNAME%/`<br>• Automated daily log rotation and strict 60-day compressed retention<br>• UFW network restriction to trusted RFC 1918 internal subnets |
| **[Dynamic Inventory](docs/dynamic-inventory.md)** | Cloud Auto-Discovery Plugins | • Automatic VM discovery for AWS EC2 (`aws_ec2.yml`), GCP (`gcp_compute.yml`), and Azure (`azure_rm.yml`)<br>• Tag-based dynamic grouping into `proxies`, `webservers`, `monitoring`, and `teleport_servers`<br>• Eliminates manual INI updates during cloud auto-scaling operations |
