# Teleport Centralized Access & Dynamic Sudo Management

The suite includes complete **[Teleport](https://goteleport.com/)** integration to eliminate credential desynchronization, static SSH keys, and static `/etc/sudoers` files across your cluster.

> [!NOTE]
> For enterprise environments requiring Kerberos KDC, LDAP 389 Directory Server, and native Linux SSSD integration instead of Teleport, see [freeipa-identity.md](freeipa-identity.md).

---

## 1. Architecture Overview

### Teleport Auth & Proxy Server (`roles/teleport_server`)
- Acts as the cluster Certificate Authority and identity gateway.
- Hosts the Web UI / API on port `3080` (or 443), SSH proxy on port `3023`, and reverse tunnel on port `3024`.
- Manages centralized RBAC roles and user accounts.

### Teleport SSH Node Service (`roles/teleport_node`)
- Runs on all cluster nodes (`proxies`, `webservers`, `monitoring`).
- Establishes an outbound reverse tunnel back to the Teleport Proxy—nodes require **zero inbound open SSH ports** to the public internet.
- **Automatic Host User Provisioning (`create_host_user_mode: keep`)**: Target OS user accounts (such as `junior` or `admin`) are automatically created on the fly when the user connects.

```
                   Junior / Admin Workstation
                               │
                               ▼
                 Teleport Proxy & Auth Server
                 (Web/API: 3080 | SSH: 3023)
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
        │ Reverse Tunnel       │ Reverse Tunnel       │ Reverse Tunnel
        │ (Port 3024)          │ (Port 3024)          │ (Port 3024)
        ▼                      ▼                      ▼
  ┌────────────┐         ┌────────────┐         ┌────────────┐
  │  proxy-01  │         │   web-01   │         │ monitor-01 │
  │ (SSH Node) │         │ (SSH Node) │         │ (SSH Node) │
  └────────────┘         └────────────┘         └────────────┘
```

---

## 2. Sudo Management with Just-In-Time (JIT) Access Requests

Permissions are managed centrally through declarative Teleport roles without editing `/etc/sudoers` on individual hosts:

| Role | Default Sudo | Escalation Capability | Description |
| :--- | :--- | :--- | :--- |
| **`lead-admin`** (`admin`) | `ALL = (ALL) NOPASSWD: ALL` | Approver | Persistent sudo across all nodes. Can review and approve access requests. |
| **`junior`** (`junior`) | **None** (unprivileged) | Can request `elevated-sudo` | Zero sudo capability on initial login. Standard commands only. |
| **`elevated-sudo`** | `ALL = (ALL) NOPASSWD: ALL` | 1-hour expiration | Temporary escalation target granted only upon approval. |

---

## 3. Junior Sudo Workflow & Helper Scripts

Pre-configured shell helpers and aliases are deployed to `/usr/local/bin` and `/etc/profile.d/teleport_helpers.sh` across all nodes so junior admins never need to memorize complex CLI flags:

| Helper Command | Short Alias | Purpose |
| :--- | :--- | :--- |
| `teleport-login [user]` | `tlogin` | Connects and authenticates to the Teleport cluster with pre-configured proxy address. |
| `teleport-request-sudo [reason]` | `tsudo` | Prompts for a justification reason, requests `elevated-sudo`, and waits for approval. |
| `teleport-status` | `tstatus` | Checks active session, remaining certificate TTL, and access request status. |
| `teleport-drop-sudo` | `tdrop` | Drops elevated role immediately and reverts to unprivileged status. |
| `teleport-ssh [user@]node` | `tssh` | Connects to a cluster node via Teleport SSH proxy (runs `tsh ls` if no node specified). |
| `teleport-approve-sudo [id]` | `tapprove` | *(Lead Admin)* Interactively reviews and approves pending access requests. |

---

## 4. Complete Junior Admin Workflow Example

### Step 1: Login
```bash
tlogin junior
# Authenticates via SSO/credentials to the Teleport cluster
```

### Step 2: Connect (Unprivileged)
```bash
tssh web-01
# Normal user permissions only. Running `sudo` is rejected.
```

### Step 3: Request Sudo Access
```bash
tsudo "Need to restart HAProxy and verify SSL logs"
# Submits request and waits for lead admin approval:
# [*] Waiting for lead administrator approval (Press Ctrl+C to cancel wait)...
```

### Step 4: Lead Admin Approves (from another terminal or Web UI)
```bash
tapprove
# Lists pending requests and approves the junior's ticket
```

### Step 5: Junior Receives Immediate Sudo Access
Upon approval, `tsudo` automatically activates the elevated certificate:
```bash
# [✓] Access request APPROVED! You now have temporary sudo privileges (1 hour expiration).
sudo systemctl restart haproxy    # Sudo works!
```

### Step 6: Drop Sudo When Done
```bash
tdrop
# [✓] Elevated sudo privileges successfully dropped. Reverted to standard unprivileged role.
```

---

## 5. GitHub Single Sign-On (SSO) Integration (Community Edition)

Teleport Community Edition provides native Single Sign-On via **GitHub OAuth 2.0**. This eliminates local password and TOTP management in favor of your existing GitHub identity.

### Prerequisites & GitHub Setup

Teleport's GitHub connector maps **GitHub Organization Teams** to Teleport RBAC roles.

#### Step 1: Create a GitHub Organization & Team
If you do not already have an organization on GitHub:
1. In GitHub, click your profile icon -> **Your organizations** -> **New organization**.
2. Choose the **Free** plan and select a name (e.g. `my-infra-org`).
3. Inside the organization, navigate to **Teams** -> **New team**, name it `admins`, and add your GitHub user account to this team.

#### Step 2: Register a GitHub OAuth App
1. Inside your GitHub Organization, go to **Settings** -> **Developer settings** (bottom left) -> **OAuth Apps** -> **New OAuth App** (or `https://github.com/organizations/<org>/settings/applications/new`).
2. Complete the form:
   - **Application name**: `Teleport Access`
   - **Homepage URL**: `https://teleport.example.com` (or your Teleport domain)
   - **Authorization callback URL** / **Redirect URIs**:
     ```text
     https://teleport.example.com/v1/webapi/github/callback
     ```
     > [!IMPORTANT]
     > Ensure there is **no trailing slash** after `callback`. Do **not** enable "Device Flow" (Teleport uses the standard Web Authorization Code flow).
3. Click **Register application**, then click **Generate a new client secret**.

#### Step 3: Configure Ansible Variables

In your deployment variables (e.g., `vars/gcp_config.yml` or group vars):

```yaml
# Teleport GitHub SSO Authentication
enable_teleport_github_sso: true
teleport_github_client_id: "Ov23liG45uNc7a01XvdZ"
teleport_github_client_secret: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
teleport_github_organization: "my-infra-org"   # Exact GitHub organization slug
teleport_github_team: "admins"                 # GitHub team slug mapping to lead-admin
```

*(Tip: In production, store `teleport_github_client_secret` in an Ansible Vault).*

### Automated Deployment & Role Mapping

When `enable_teleport_github_sso: true` is set, Ansible automates:
1. Configuring `/etc/teleport/teleport.yaml` with `authentication.type: github`.
2. Deploying `/etc/teleport/resources/github.yaml` (`kind: github`, version `v3`) with `teams_to_roles` mapping your GitHub organization team directly to the `lead-admin` role.
3. Enabling `{{external.username}}` and `{{external.logins}}` in the `lead-admin` role so GitHub users inherit full cluster administrative rights and passwordless sudo.
4. Applying the connector to the cluster via `tctl create -f /etc/teleport/resources/github.yaml`.

### Logging In with GitHub

#### 1. Interactive Web UI
Visit `https://teleport.example.com` in your web browser. Click the **Login with GitHub** button to authorize via GitHub and enter the web terminal.

#### 2. Terminal CLI (`tsh`)
Authenticate directly from your workstation terminal:
```bash
tsh login --proxy=teleport.example.com:443 --auth=github
```
This automatically launches your local browser to complete GitHub authentication, issues short-lived SSH certificates, and saves your session:

```bash
tsh ls
tsh ssh root@web-01
```

### Local Fallback & Emergency Access

If GitHub is unreachable or you need emergency administrative access:
1. Local access via the auth server CLI is always available to root:
   ```bash
   ssh -J admin@proxy-01 admin@<teleport-internal-ip>
   sudo tctl status
   ```
2. You can generate a temporary local admin user at any time:
   ```bash
   sudo tctl users add emergency-admin --roles=lead-admin --logins=root,ubuntu
   ```
