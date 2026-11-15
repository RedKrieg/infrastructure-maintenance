# Teleport Centralized Access & Dynamic Sudo Management

The suite includes complete **[Teleport](https://goteleport.com/)** integration to eliminate credential desynchronization, static SSH keys, and static `/etc/sudoers` files across your cluster.

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
