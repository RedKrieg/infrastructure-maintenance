# Ansible Vault Secrets Management Guide

This project integrates **Ansible Vault** to secure sensitive credentials—such as HAProxy statistics passwords, database and cache credentials, internal CA tokens, Teleport join tokens, and Prometheus/Grafana authentication—preventing sensitive data from being committed to source control in plain text.

---

## 1. Vault Directory Structure

Global defaults and encrypted vault variables are centralized in `group_vars/all/`, which Ansible automatically loads for all hosts and roles:

```
group_vars/
├── all/
│   ├── common.yml           # Non-secret cluster SSOT defaults (domain, FQDNs, TLS toggle)
│   ├── vault.yml            # Active secrets (encrypt with ansible-vault)
│   └── vault.example.yml    # Unencrypted reference template
├── proxies.yml              # Cluster-level proxy overrides
└── webservers.yml           # Backend webserver overrides
```

### Managed Vault Secrets:
* **Edge & HA**:
  * `vault_haproxy_stats_password`: Password protecting HAProxy `/stats` and `/metrics`.
  * `vault_keepalived_auth_pass`: VRRP authentication passphrase for Keepalived (8 chars max).
  * `vault_internal_ca_token`: Authorization token authenticating node CSR signing requests to `internal-ca-signer`.
* **Identity & Access**:
  * `vault_admin_default_password`: Initial administrative account password fallback.
  * `vault_teleport_auth_token`: Static node join token shared between `teleport_server` and `teleport_node`.
  * `vault_teleport_github_client_id`: GitHub OAuth application Client ID for Teleport SSO.
  * `vault_teleport_github_client_secret`: GitHub OAuth application Client Secret for Teleport SSO.
  * `vault_freeipa_admin_password`: FreeIPA `admin` Kerberos principal password.
  * `vault_freeipa_ds_password`: FreeIPA 389 Directory Server Directory Manager password.
  * `vault_freeipa_client_otp`: FreeIPA One-Time Password (OTP) for automated host enrollment.
* **Observability & Alerting**:
  * `vault_prometheus_password`: Basic auth password used by Prometheus when scraping protected endpoints.
  * `vault_grafana_admin_password`: Grafana UI administrator login password.
  * `vault_alertmanager_smtp_password`: SMTP relay password for Alertmanager email dispatch (when configured).
* **Data, Cache & Broker Tiers**:
  * `vault_db_password`: Application user password for PostgreSQL or MySQL databases.
  * `vault_db_replication_password`: PostgreSQL streaming replication role passphrase.
  * `vault_redis_password`: Redis `requirepass` authentication secret.
  * `vault_rabbitmq_password`: RabbitMQ application vhost user password.
  * `vault_rabbitmq_admin_password`: RabbitMQ Management Web UI & API administrator password.
  * `vault_rabbitmq_erlang_cookie`: Shared secret cookie for RabbitMQ Erlang cluster nodes.

---

## 2. Setting Up Ansible Vault

### Step 2.1: Create a Vault Password File
To avoid typing the vault password on every playbook execution, create a `.vault_pass` file on your local workstation:

```bash
# Generate a random 32-character passphrase:
openssl rand -base64 24 > ~/.vault_pass
chmod 600 ~/.vault_pass

# Or write your existing vault password directly:
echo "YOUR_VAULT_PASSWORD" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

> [!NOTE]
> `.vault_pass`, `.vault_pass.*`, and `*.vault_pass` are already included in `.gitignore` across the project to prevent accidental credential commits.

### Step 2.2: Configure `ansible.cfg` for Automatic Decryption
Add the password file path to your `ansible.cfg`:
```ini
[defaults]
vault_password_file = ~/.vault_pass
```
With this configured, Ansible commands (`ansible-playbook`, `ansible-vault view`) automatically decrypt vault variables in the background without requiring manual CLI flags.

### Step 2.3: Encrypting the Vault File
```bash
# Encrypt the vault file:
ansible-vault encrypt group_vars/all/vault.yml --vault-password-file ~/.vault_pass
```

### Step 2.4: Viewing or Editing While Encrypted
```bash
# View without decrypting:
ansible-vault view group_vars/all/vault.yml --vault-password-file ~/.vault_pass

# Edit in-place with your editor:
ansible-vault edit group_vars/all/vault.yml --vault-password-file ~/.vault_pass
```

---

## 3. Running Playbooks with Vault

When running Ansible playbooks against any inventory, pass the vault password file or `--ask-vault-pass`:

```bash
# Using vault password file:
ansible-playbook -i inventory.ini playbook.yml --vault-password-file ~/.vault_pass

# Or prompt for vault passphrase interactively:
ansible-playbook -i inventory.ini playbook.yml --ask-vault-pass
```

---

## 4. Key Lifecycle & Credential Rotation

For detailed operational procedures on rekeying Ansible Vault (`ansible-vault rekey`), rotating live database and Redis passwords with zero downtime, and cycling Internal CA root keys, see the comprehensive [Secret Rotation & Key Management Guide](secret-rotation-and-key-management.md).
