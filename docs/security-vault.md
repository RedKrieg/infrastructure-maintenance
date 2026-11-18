# Ansible Vault Secrets Management Guide

This project integrates **Ansible Vault** to secure sensitive credentials—such as HAProxy statistics passwords, database and cache credentials, internal CA tokens, Teleport join tokens, and Prometheus/Grafana authentication—preventing sensitive data from being committed to source control in plain text.

---

## 1. Vault Directory Structure

Global secrets are centralized in `group_vars/all/vault.yml` (copied from `group_vars/all/vault.example.yml` and encrypted with Ansible Vault), which Ansible automatically loads for all hosts and roles:

```
group_vars/
└── all/
    ├── admin_users.yml      # Local break-glass admin accounts & SSH keys
    ├── backup_config.yml    # Disaster recovery destination settings
    ├── vault.example.yml    # Reference secrets template
    └── vault.yml            # Active encrypted secrets (git-ignored; copy & encrypt before running)
```

> [!IMPORTANT]
> There are **no default passwords** built into roles or playbooks. Copy `group_vars/all/vault.example.yml` to `group_vars/all/vault.yml`, set strong credentials, and encrypt it before deploying; otherwise Ansible fails fast on undefined secrets.

### Credential Matrix (Single Source of Truth)

All 20 `vault_*` secrets below are declared in [`group_vars/all/vault.example.yml`](../group_vars/all/vault.example.yml) and validated bidirectionally against the codebase by [`tests/run_tests.sh`](../tests/run_tests.sh).

#### Required Credentials (Fail-Fast When Role/Playbook Is Active)

| Vault Variable | Populates | Consumer Roles / Playbooks | Requirement & Format Constraints |
| :--- | :--- | :--- | :--- |
| `vault_haproxy_stats_password` | `haproxy_stats_password` | `roles/proxy`, `verify_cluster.yml` (fallback for `prometheus_haproxy_password`) | **Required**; HTTP Basic Auth for `/stats` & `/metrics`. |
| `vault_internal_ca_token` | `internal_ca_token` | `roles/proxy`, `roles/internal_ca_client` | **Required**; shared bearer token for `internal-ca-signer`. |
| `vault_keepalived_auth_pass` | `keepalived_auth_pass` | `roles/keepalived` | **Required** when Keepalived runs; **max 8 characters** (`PASS` auth). |
| `vault_grafana_admin_password` | `grafana_admin_password` | `roles/grafana` | **Required**; Grafana UI administrator login password. |
| `vault_teleport_auth_token` | `teleport_auth_token` | `roles/teleport_server`, `roles/teleport_node` | **Required**; static join token shared between Auth server and nodes. |
| `vault_freeipa_admin_password` | `freeipa_admin_password` | `roles/freeipa_server`, `roles/freeipa_client` (when OTP is empty) | **Required** for FreeIPA server and non-OTP enrollment; **min 8 characters**. |
| `vault_freeipa_ds_password` | `freeipa_ds_password` | `roles/freeipa_server` | **Required** for FreeIPA Directory Manager; **min 8 characters**. |
| `vault_db_password` | `db_password` | `roles/database`, AWS RDS / GCP Cloud SQL / Azure PostgreSQL provisioning | **Required**; application database user password (`db_user`). |
| `vault_db_replication_password` | `db_replication_password` | `roles/database` | **Required**; PostgreSQL streaming replication role password. |
| `vault_redis_password` | `redis_password` | `roles/redis` | **Required**; Redis `requirepass` authentication secret. |
| `vault_rabbitmq_password` | `rabbitmq_password` | `roles/rabbitmq`, `provision_aws_amazon_mq.yml` | **Required**; RabbitMQ application vhost user password. |
| `vault_rabbitmq_admin_password` | `rabbitmq_admin_password` | `roles/rabbitmq`, `verify_cluster.yml` | **Required**; RabbitMQ Management UI & API admin password. |
| `vault_rabbitmq_erlang_cookie` | `rabbitmq_erlang_cookie` | `roles/rabbitmq` | **Required**; alphanumeric cluster cookie in `/var/lib/rabbitmq/.erlang.cookie`. |

#### Optional / Conditional Credentials

| Vault Variable | Populates | Consumer Roles / Playbooks | Default & Activation Condition |
| :--- | :--- | :--- | :--- |
| `vault_prometheus_password` | `prometheus_haproxy_password` | `roles/prometheus_server` | Optional; falls back to `vault_haproxy_stats_password` if unset. |
| `vault_alertmanager_smtp_password` | `alertmanager_smtp_auth_password` | `roles/prometheus_server` | Defaults to `""`; required only when authenticated SMTP relay is configured. |
| `vault_teleport_github_client_id` | `teleport_github_client_id` | `roles/teleport_server` | Defaults to `""`; required only when `enable_teleport_github_sso: true`. |
| `vault_teleport_github_client_secret` | `teleport_github_client_secret` | `roles/teleport_server` | Defaults to `""`; required only when `enable_teleport_github_sso: true`. |
| `vault_freeipa_client_otp` | `freeipa_client_otp` | `roles/freeipa_client` | Defaults to `""`; optional one-time password instead of `vault_freeipa_admin_password`. |
| `vault_backup_s3_access_key` | `backup_s3_access_key` | `backup_cluster.yml` | Defaults to `""`; required only when `backup_destination_type: "s3"`. |
| `vault_backup_s3_secret_key` | `backup_s3_secret_key` | `backup_cluster.yml` | Defaults to `""`; required only when `backup_destination_type: "s3"`. |

#### Local Break-Glass OS Accounts (`group_vars/all/admin_users.yml`)
- Local UNIX accounts defined in `admin_users` authenticate via **Ed25519/RSA SSH public keys** (`authorized_keys`), with `PasswordAuthentication no` enforced on `sshd`.
- When `password` is omitted from an `admin_users` entry, `roles/admin_users` generates a unique random 32-character SHA-512 OS password per host on initial user creation (`update_password: on_create`), so no shared default UNIX password exists.

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
