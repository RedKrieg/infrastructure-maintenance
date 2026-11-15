# Ansible Vault Secrets Management Guide

This project integrates **Ansible Vault** to secure sensitive credentials—such as HAProxy statistics passwords, Teleport join tokens, and Prometheus scrape authentication—preventing sensitive data from being committed to source control in plain text.

---

## 1. Vault Directory Structure

Vault variables are centralized in `group_vars/all/vault.yml`, which Ansible automatically loads for all hosts and roles:

```
group_vars/
├── all/
│   ├── vault.yml            # Active secrets (encrypt with ansible-vault)
│   └── vault.example.yml    # Unencrypted reference template
├── proxies.yml              # Cluster-level proxy overrides
└── webservers.yml           # Backend webserver overrides
```

### Managed Vault Secrets:
* `vault_haproxy_stats_password`: Password protecting HAProxy `/stats` and `/metrics`.
* `vault_teleport_auth_token`: Static node join token shared between `teleport_server` and `teleport_node`.
* `vault_prometheus_password`: Basic auth password used by Prometheus to scrape proxy metrics.
* `vault_admin_default_password`: Initial administrative account password fallback.

---

## 2. Setting Up Ansible Vault

### Step 2.1: Create a Vault Password File
To avoid typing the vault password on every playbook execution, create a `.vault_pass` file on your local workstation:

```bash
# Generate a random 32-character passphrase:
openssl rand -base64 24 > ~/.vault_pass
chmod 600 ~/.vault_pass
```

> [!NOTE]
> `.vault_pass`, `.vault_pass.*`, and `*.vault_pass` are already included in `.gitignore` to prevent accidental credential commits.

### Step 2.2: Encrypting the Vault File
```bash
# Encrypt the vault file:
ansible-vault encrypt group_vars/all/vault.yml --vault-password-file ~/.vault_pass
```

### Step 2.3: Viewing or Editing While Encrypted
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

### Configuring `ansible.cfg` (Optional)
To make Ansible use your vault password file automatically without passing `--vault-password-file` every time, set in `ansible.cfg`:
```ini
[defaults]
vault_password_file = ~/.vault_pass
```
