# Enterprise Zero-Trust High-Availability Infrastructure & Operations Suite

A comprehensive, cloud-agnostic, and zero-trust infrastructure orchestration and Day-2 operations suite for headless Ubuntu systems (20.04, 22.04, 24.04 LTS). Built with Ansible to run identically across **AWS EC2**, **Google Cloud Platform (GCP)**, **Microsoft Azure**, **Oracle Cloud (OCI)**, **OpenStack**, and **bare-metal/on-premises** data centers with zero vendor lock-in.

### What This Platform Delivers:
* **Edge Ingress & Threat Mitigation**: Multi-node HAProxy edge fleet with Keepalived VRRP floating IP, Coraza WAF (OWASP Core Rule Set), in-memory rate limiting (300 req/10s), automated ACME public SSL line of succession with 1-day staggered renewal windows, and strict generic 404 catch-alls.
* **Flexible Backend Topologies**: Dedicated 1:1 multi-tenant webservers, high-availability pooled N:1 round-robin webservers with session affinity, or hybrid coexisting architectures.
* **Stateful Data & Broker Tiers**: Production-ready PostgreSQL (Single-Primary write master + streaming read replica + PgBouncer connection pooling) or MySQL 8.0, Redis in-memory caching and session clustering, and RabbitMQ AMQP message broker with management UI.
* **End-to-End Fleet Zero-Trust Encryption**: Automated Cluster Internal CA authority (ECDSA P-384) with rank-based succession failover, issuing 90-day leaf certificates with automated renewal to backends, Rsyslog TLS logging (Port 6514), Node Exporter HTTPS telemetry (Port 9100), and database transit.
* **Dual Enterprise Identity & Access Governance**: Teleport Zero-Trust Gateway (short-lived SSH/HTTPS certs, browser consoles, and JIT elevation) alongside FreeIPA (Kerberos KDC, LDAP 389, and SSSD integration), backed by out-of-band Ed25519 break-glass admin accounts.
* **Complete Observability & Telemetry**: Standalone Prometheus server, pre-configured Grafana dashboards, centralized Rsyslog aggregation with 60-day compressed retention, multi-tier Alertmanager routing (Slack, PagerDuty, Teams, Discord), and Google Chat Cards v2 webhook relays.
* **Automated Day-2 Operations & Resilience**: Zero-downtime rolling maintenance with HAProxy runtime socket connection draining, multi-cloud disaster recovery backup & restoration via `rclone` (70+ cloud backends), non-destructive chaos engineering drills, and operational emergency runbooks.

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
├── rolling_maintenance.yml          # Zero-downtime rolling OS & kernel upgrades with HAProxy socket draining
├── chaos_drill.yml                  # Automated chaos resilience drills (VRRP failover, backend outage)
├── inventories/                     # Multi-environment inventory topologies
│   ├── staging/                     # Staging tier (Let's Encrypt Staging CA, isolated subnets)
│   └── production/                  # Production tier (Production Let's Encrypt CA, 60d retention)
├── docs/                            # Modular architecture and operational documentation
│   ├── administrator-and-troubleshooting-guide.md # Plain-English operational guide, cheatsheet & junior triage
│   ├── architecture.md              # Cloud-agnostic Layer 4 ingress architecture and provider mapping
│   ├── backend-topologies.md        # Dedicated 1:1 vs. Pooled N:1 load-balanced webserver clusters
│   ├── database-architecture.md     # Optional database tier: PostgreSQL, MySQL & Cloud-Native services
│   ├── cache-and-queue-architecture.md # Optional Redis cache/sessions & RabbitMQ message broker
│   ├── staging-production.md        # Staging vs. production environment strategy & ACME rate limit defense
│   ├── keepalived-baremetal.md      # Bare Metal HA with Keepalived VRRP floating IP & health tracking
│   ├── ssl-certificates.md          # Multi-node ACME line of succession, sync scripts & recovery
│   ├── internal-tls.md              # Zero-Trust internal TLS encryption between HAProxy and Nginx
│   ├── proxy-security.md            # HTTP/2, HSTS, rate limiting (300/10s), health checks & stats ACL
│   ├── waf-coraza.md                # Coraza WAF via HAProxy SPOE & OWASP Core Rule Set (default on)
│   ├── security-vault.md            # Ansible Vault secrets management & credential encryption
│   ├── centralized-logging.md       # Cluster log shipping via rsyslog with 60-day retention
│   ├── teleport-access.md           # Teleport JIT sudo access, RBAC roles & CLI helper scripts
│   ├── freeipa-identity.md          # FreeIPA identity server, client enrollment, SSSD & Kerberos
│   ├── monitoring.md                # Native HAProxy Prometheus metrics, alert rules & retention
│   ├── alertmanager.md              # Alertmanager admin email alerts, Slack, PagerDuty, Discord & Teams
│   ├── alert-response-and-runbooks.md # Incident triage, memory limit tuning, disk vacuuming & online expansion
│   ├── secret-rotation-and-key-management.md # Zero-downtime secret rotation, vault rekey, DB & CA lifecycle
│   ├── google-chat-alerts.md        # Google Chat Cards v2 webhook alerts & Python relay daemon
│   ├── grafana-dashboards.md        # Grafana & Node Exporter telemetry, dashboards & PromQL alerts
│   ├── rolling-maintenance.md       # Zero-downtime rolling maintenance, socket draining & kernel reboots
│   ├── chaos-engineering.md         # Automated chaos resilience drills & failover validation
│   ├── backup-and-disaster-recovery.md # Multi-tier disaster recovery, remote targets & restore steps
│   ├── verification.md              # Automated smoke testing, security assertions & compliance checks
│   ├── deployment.md                # Inventory setup, cloud templates, and targeted Ansible tags
│   ├── dynamic-inventory.md         # AWS, GCP, and Azure tag-based dynamic discovery plugins
│   ├── aws-ec2-setup.md             # AWS EC2 quickstart: AWS CLI, VPC, subnets across AZs & EC2 automation
│   ├── gcp-compute-setup.md         # GCP quickstart: gcloud CLI, auth & automated VM provisioning
│   ├── azure-setup.md               # Azure quickstart: az CLI, VNet, NSG & automated VM provisioning
│   ├── oci-compute-setup.md         # OCI quickstart: oci CLI, VCN, Fault Domains & VM provisioning
│   ├── openstack-setup.md           # OpenStack quickstart: clouds.yaml, anti-affinity & Nova provisioning
│   ├── resource-sizing-and-scaling.md # Minimum memory matrix, assertions & rolling vertical scaling
│   └── anti-affinity-and-resilience.md # Failure domains, Nova server groups & multi-AZ distribution
├── examples/
│   ├── topologies/                  # Pre-configured cluster backend topology scenarios
│   │   ├── scenario-1-unique-clients/ # Dedicated 1:1 webservers for isolated client tenants
│   │   ├── scenario-2-pooled-webservers/ # High-availability N:1 pooled webservers with round-robin
│   │   └── scenario-3-hybrid/       # Clustered HA core site coexisting with dedicated tenant backends
│   ├── freeipa/                     # FreeIPA standup & existing enterprise domain enrollment examples
│   │   ├── standup_freeipa_cluster.yml # Standalone cluster with dedicated FreeIPA server
│   │   └── enroll_existing_freeipa.yml # Enrolling nodes into an existing FreeIPA / Red Hat IdM domain
│   ├── internal-tls/                # Zero-Trust Internal CA & mTLS reference configuration examples
│   │   ├── enable_internal_tls_vars.yml # Complete proxy & backend internal TLS variable reference
│   │   └── README.md                # Setup, succession failover & verification guide
│   ├── teleport/                    # Teleport Workstation Helper Bundle & Bastion guide
│   │   ├── install_workstation_helpers.sh # Portable workstation CLI wrapper & alias installer
│   │   └── README.md                # Workstation install, bastion jump-host & JIT sudo guide
│   ├── alertmanager/                # Drop-in Alertmanager configuration templates
│   │   ├── alertmanager-slack.yml   # Slack webhook notifications with channel routing
│   │   ├── alertmanager-pagerduty.yml # PagerDuty Events API v2 on-call escalation
│   │   ├── alertmanager-discord.yml # Discord webhook integration (Slack-compatible)
│   │   ├── alertmanager-teams.yml   # Microsoft Teams webhook connector
│   │   ├── alertmanager-google-chat.yml # Google Chat webhook routing template
│   │   ├── google_chat_relay.py     # Zero-dependency Python 3 relay daemon for Google Chat Cards v2
│   │   └── alertmanager-multi-channel.yml # Unified multi-tier routing tree
│   ├── inventories/                 # Cloud-specific example inventory templates & dynamic plugins
│   │   ├── inventory.aws.ini        # AWS EC2 multi-AZ example (VPC 172.31.0.0/16)
│   │   ├── inventory.gcp.ini        # GCP Compute Engine multi-zone example (VPC 10.128.0.0/20)
│   │   ├── inventory.azure.ini      # Microsoft Azure multi-zone example (VNet 10.240.0.0/16)
│   │   ├── inventory.oci.ini        # Oracle Cloud Infrastructure multi-FD example (VCN 10.0.0.0/16)
│   │   ├── inventory.openstack.ini  # OpenStack anti-affinity example (192.168.100.0/24)
│   │   ├── aws_ec2.yml              # AWS EC2 dynamic inventory plugin configuration
│   │   ├── gcp_compute.yml          # GCP dynamic inventory plugin configuration
│   │   └── azure_rm.yml             # Microsoft Azure dynamic inventory plugin configuration
│   └── provisioning/                # Cloud VM, managed service & network provisioning automation
│       ├── provision_aws.yml        # Ansible playbook provisioning AWS VPC, subnets & EC2 instances
│       ├── provision_aws_rds_postgresql.yml # Managed AWS RDS PostgreSQL provisioning
│       ├── provision_aws_elasticache_redis.yml # Managed AWS ElastiCache Redis provisioning
│       ├── provision_aws_amazon_mq.yml # Managed AWS Amazon MQ RabbitMQ provisioning
│       ├── provision_gcp.yml        # Ansible playbook provisioning GCP VPC, firewalls & VMs
│       ├── provision_gcp_cloudsql_postgresql.yml # Managed GCP Cloud SQL PostgreSQL provisioning
│       ├── provision_gcp_memorystore_redis.yml # Managed GCP Memorystore Redis provisioning
│       ├── provision_azure.yml      # Ansible playbook provisioning Azure VNet, NSG & VMs
│       ├── provision_azure_postgresql.yml # Managed Azure Database for PostgreSQL provisioning
│       ├── provision_azure_cache_redis.yml # Managed Azure Cache for Redis provisioning
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
│   ├── internal_ca_client/          # Fleet-wide Internal CA trust store & 90-day leaf cert enrollment
│   ├── node_exporter/               # Host metrics telemetry agent (port 9100, optional HTTPS) across all nodes
│   ├── proxy/                       # HAProxy role (terminates SSL, Coraza WAF, routes 1:1 to backends)
│   ├── webserver/                   # Backend Nginx role (generic 404 & internal TLS encryption)
│   ├── database/                    # Optional Database role (PostgreSQL preferred & MySQL engines)
│   ├── redis/                       # Optional Redis role (in-memory caching & centralized session store)
│   ├── rabbitmq/                    # Optional RabbitMQ role (AMQP message broker & task queue)
│   ├── central_logging/             # Centralized log collection (server & shipper) with 60-day retention
│   ├── prometheus_server/           # Standalone Prometheus server role (port 9090, 60d retention, alert rules)
│   ├── grafana/                     # Grafana visualization server (port 3000, pre-built dashboards)
│   ├── teleport_server/             # Teleport Auth, Proxy & Bastion role (ports 3080/3023/3024, bundle builder, tsudo watcher)
│   ├── teleport_node/               # Teleport SSH Node reverse-tunnel daemon on target hosts (no client helpers)
│   ├── freeipa_server/              # FreeIPA Centralized Identity Server role (Kerberos, LDAP 389/636, Web UI)
│   └── freeipa_client/              # FreeIPA Client Enrollment & SSSD Centralized Authentication role
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
| **[Admin & Junior Runbook](docs/administrator-and-troubleshooting-guide.md)** | Daily Operations, Junior On-Call & Incident Runbooks | • Plain-English end-to-end request lifecycle and service overview<br>• Access matrix (Teleport, FreeIPA, Break-Glass SSH)<br>• "Dirty Dozen" service matrix (units, configs, logs, sockets)<br>• Step-by-step triage runbooks for 502/503, VIP drop, SSL expiry, memory/disk alarms, DB lag<br>• Draining, rolling upgrades, backups, and operator golden rules |
| **[Architecture](docs/architecture.md)** | Cloud-Agnostic High-Availability Architecture | • Generic Layer 4 Ingress Load Balancer (TCP Passthrough)<br>• Transparent client IP preservation with zero cloud lock-in<br>• Provider drop-in mapping table (AWS NLB, GCP Passthrough, Azure LB, OCI NLB, Octavia, Bare Metal)<br>• RFC 1918 universal subnet compatibility & zero-cloud-agent model<br>• Dynamic 1:1 host-to-FQDN reverse proxy routing concept |
| **[Backend Topologies](docs/backend-topologies.md)** | Dedicated 1:1 vs Pooled N:1 vs Hybrid Clusters | • Scenario 1: Dedicated 1:1 webservers for isolated client tenants<br>• Scenario 2: High-availability N:1 pooled webservers with round-robin<br>• Scenario 3: Clustered HA core site coexisting with dedicated tenant backends<br>• State management, session stickiness, and failure domain trade-offs |
| **[Resource Sizing & Scaling](docs/resource-sizing-and-scaling.md)** | Memory Bounds, Pre-flight Checks & Scaling | • Minimum RAM sizing matrix across all cluster roles<br>• Automated pre-flight memory validation (`enforce_min_memory_check: true`)<br>• Service memory limiters (Redis LRU, RabbitMQ watermark, Postgres buffers)<br>• Zero-downtime rolling vertical migration procedure via HAProxy socket draining |
| **[Anti-Affinity & Resilience](docs/anti-affinity-and-resilience.md)** | Failure Domain Isolation & Redundancy | • Multi-AZ distribution across AWS, GCP, Azure, and OCI Fault Domains<br>• OpenStack Nova anti-affinity server groups (`proxy-anti-affinity`, `web-anti-affinity`)<br>• Decoupled hypervisor placement preventing correlated failure<br>• Physical rack and PDU isolation on bare metal |
| **[Database Architecture](docs/database-architecture.md)** | PostgreSQL, MySQL & Cloud-Native Services | • PostgreSQL preferred default with SCRAM-SHA-256 and JSONB<br>• MySQL 8.0 support<br>• Scenario 1 multi-tenant partitioned databases<br>• Scenario 2 Single-Primary write master + streaming read replica + PgBouncer pooling (port 6432)<br>• Cloud-native managed database provisioning (AWS RDS, GCP Cloud SQL, Azure Flexible Server, OCI) |
| **[Cache & Queue Architecture](docs/cache-and-queue-architecture.md)** | Redis Sessions/Cache & RabbitMQ Message Broker | • Redis in-memory cache and centralized session store for stateless pooled webservers<br>• LRU memory eviction and dual RDB/AOF persistence<br>• RabbitMQ AMQP 0-9-1 task queue and worker decoupling<br>• RabbitMQ Management Web UI routed through HAProxy with TLS (`mq.<domain>`) and Prometheus metrics (port 15692)<br>• Cloud-native provisioning (AWS ElastiCache, Amazon MQ, GCP Memorystore, Azure Cache) |
| **[Staging vs. Production](docs/staging-production.md)** | Multi-Environment Decoupling & Strategy | • Decoupled environment structures under `inventories/staging/` and `inventories/production/`<br>• Let's Encrypt Staging CA (`acme_use_staging: true`) to prevent API rate limiting<br>• Environment-specific TSDB metrics retention (7d staging vs 60d production)<br>• Staging vs production domain segregation and notification routing |
| **[Bare Metal HA (Keepalived)](docs/keepalived-baremetal.md)** | Layer 4 VRRP Ingress Redundancy | • High availability on bare metal / private clouds without managed cloud load balancers<br>• Automated health-checking tracking script (`check_haproxy.sh`) with dynamic priority reduction<br>• Kernel sysctl tuning (`net.ipv4.ip_nonlocal_bind = 1`) & UFW protocol 112 rules<br>• Unicast peer discovery and non-preemptive failback protection |
| **[SSL Certificates & Failover](docs/ssl-certificates.md)** | Shared SSL Certificates, Succession & Recovery | • Cluster-wide HTTP-01 challenge routing via `backend be_acme`<br>• Automated `sync-haproxy-certs.sh` push over dedicated cluster SSH keys<br>• Rank-based fallback line of succession with 1-day staggered renewal windows<br>• Active SSH protocol negotiation checks (`ssh-keyscan` key exchange & RFC 4253 banner check)<br>• Boot-time reconciliation service (`haproxy-cert-reconcile.service`) & seamless rank resumption |
| **[Zero-Trust Internal TLS](docs/internal-tls.md)** | Backend Encryption & Certificate Authority | • Zero-trust end-to-end encryption between HAProxy edge load balancers and backend webservers<br>• Replicated lightweight Internal Root CA with automated out-of-band renewal and peer reconciliation<br>• HAProxy backend SSL re-encryption with strict cryptographic verification (`ssl verify required`)<br>• Standby watchdog failover, 14-day client auto-renewals, non-destructive Ansible runs, and Prometheus alerting |
| **[Proxy Security & Hardening](docs/proxy-security.md)** | Edge Hardening, Performance & Access Control | • HTTP/2 ALPN negotiation (`h2,http/1.1`) with HTTP/1.1 fallback<br>• Security response headers (`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`) & HSTS (1 year preload)<br>• In-memory stick-table volumetric rate limiting (300 req/10s $\rightarrow$ HTTP 429)<br>• Active HTTP backend health checks (`option httpchk` with Host header & regex rstatus)<br>• Dynamic stats & Prometheus ACL whitelist (IPs, CIDRs, dynamic FQDN resolution script & systemd timer)<br>• 60-day log retention via logrotate (`copytruncate`) and journald `MaxRetentionSec=60day` |
| **[Teleport Access & Sudo Management](docs/teleport-access.md)** | Centralized Access & Dynamic Elevation | • Zero-trust access architecture: Auth/Proxy/Bastion service (`bastion=true`) and outbound reverse tunnels<br>• Automatic host user provisioning (`create_host_user_mode: keep`)<br>• RBAC role hierarchy: `lead-admin`, unprivileged `junior`, and temporary `elevated-sudo`<br>• Just-In-Time (JIT) access request watcher (`teleport-access-watcher`) routing `tsudo` alerts to Alertmanager/Slack/Google Chat/Teams with one-click Web UI approval links<br>• Workstation bundle installer and Bastion CLI aliases (`tlogin`, `tsudo`, `tstatus`, `tdrop`, `tssh`, `tapprove`)<br>• End-to-end junior administrator workflow walkthrough |
| **[FreeIPA Identity & Access Management](docs/freeipa-identity.md)** | Centralized Linux Identity & Kerberos/SSSD | • Standalone FreeIPA server deployment (`freeipa_server` role) with Kerberos KDC, LDAP 389/636, Web UI<br>• Client enrollment (`freeipa_client` role) into local or existing enterprise FreeIPA / Red Hat IdM domains<br>• Authentication via One-Time Password (OTP) or administrator credentials<br>• SSSD integration for centralized SSH public key lookup (`sss_ssh_authorizedkeys`)<br>• Centralized sudo rules (`sudoers: files sss`) and PAM automatic home directory creation (`mkhomedir`)<br>• HAProxy reverse proxy integration with Admin ACL protection for Web UI |
| **[Prometheus Monitoring](docs/monitoring.md)** | Metrics Scraping & Centralized Monitoring | • Native HAProxy Prometheus exporter (`/metrics` on port 8404)<br>• Unified ACL whitelist and HTTP basic authentication matching stats UI<br>• Automatic whitelisting of inventory `[monitoring]` group hosts<br>• Standalone Prometheus server role (`roles/prometheus_server` on port 9090)<br>• Dynamic proxy scrape target discovery and configuration<br>• Automated `promtool check config` validation, 60-day TSDB retention, and UFW isolation |
| **[Alertmanager Notifications](docs/alertmanager.md)** | Alert Routing, Email & Chat Integrations | • Native Prometheus Alertmanager deployment (port 9093) with admin email notifications<br>• Dynamic admin recipient discovery from `vars/admin_users.yml`<br>• Ready-to-use configurations for Slack, PagerDuty, Discord, and Microsoft Teams<br>• Multi-tier severity routing with alert inhibition rules to prevent alarm floods |
| **[Alert Response & Runbooks](docs/alert-response-and-runbooks.md)** | Incident Triage & Emergency Runbooks | • Low memory triage (`free -h`, `ps`, OOM inspection), Redis/RabbitMQ/PostgreSQL memory limit adjustments<br>• Low disk triage, directory breakdown (journald, WAL, mnesia, ghost files via `lsof +L1`)<br>• Online cloud block volume expansion (AWS EBS, GCP PD, Azure Disk, Cinder, LVM) with zero downtime |
| **[Secret Rotation & Key Management](docs/secret-rotation-and-key-management.md)** | Credential Lifecycles & Zero-Downtime Rotation | • Master Ansible Vault rekeying (`ansible-vault rekey`)<br>• Zero-downtime PostgreSQL & MySQL application password rotation<br>• Live Redis `requirepass` update via `CONFIG SET`<br>• RabbitMQ credentials & Erlang cluster cookie rotation<br>• Internal Root CA & Leaf X.509 certificate lifecycle & emergency revocation<br>• Teleport token rotation, FreeIPA admin credentials & break-glass admin SSH keys |
| **[Google Chat Alert Webhooks](docs/google-chat-alerts.md)** | Cards v2 Translation & Delivery | • Incoming webhook integration for Google Workspace Spaces<br>• Zero-dependency Python 3 relay daemon ([google_chat_relay.py](examples/alertmanager/google_chat_relay.py))<br>• Translates Alertmanager schema to rich Google Chat Cards v2 with status badges |
| **[Grafana & Hardware Telemetry](docs/grafana-dashboards.md)** | Visual Dashboards & Fleet Observability | • Grafana server deployment on port 3000 with auto-provisioned Prometheus datasource<br>• Universal Node Exporter deployment (port 9100) across all cluster hosts<br>• Pre-configured `HAProxy & Coraza WAF Overview` dashboard (traffic, errors, WAF blocks)<br>• Pre-configured `Fleet Hardware Health` dashboard (CPU, memory, disk, network throughput) |
| **[Zero-Downtime Rolling Maintenance](docs/rolling-maintenance.md)** | Kernel Upgrades & Socket Connection Draining | • Automated `rolling_maintenance.yml` playbook executing across nodes with `serial: 1`<br>• HAProxy runtime administrative socket draining (`set server state drain` / `maint`)<br>• Configuration preservation (`force-confold`) during unattended package upgrades<br>• Automated kernel reboot detection (`/var/run/reboot-required`) & health check recovery |
| **[Chaos & Resilience Drills](docs/chaos-engineering.md)** | Failure Injection & Failover Validation | • Automated `chaos_drill.yml` non-destructive resilience testing<br>• Backend server crash simulation and dynamic HAProxy health check rerouting<br>• Bare metal Keepalived VRRP Virtual IP migration verification<br>• Guaranteed 100% self-healing with automatic service state restoration |
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
