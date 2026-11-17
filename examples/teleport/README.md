# Teleport Operator Workstation Bundle & Bastion Guide

The Teleport helper scripts (`teleport-login`, `teleport-request-sudo`, `teleport-status`, `teleport-drop-sudo`, `teleport-ssh`, `teleport-approve-sudo`) and shell aliases (`tlogin`, `tsudo`, `tstatus`, `tdrop`, `tssh`, `tapprove`, `tnodes`, `tapps`) are **intentionally excluded from target workload nodes** (`webservers`, `databases`, `redis_servers`, `rabbitmq_servers`).

Instead, operators choose between two clean models:
1. **Workstation Bundle (Recommended)**: Install the CLI helpers onto your local laptop/workstation where `tsh` lives.
2. **Teleport Bastion (`teleport-01`)**: SSH into the `[teleport_servers]` bastion node (`bastion=true`), where all helpers are pre-installed system-wide in `/usr/local/bin` and `/etc/profile.d/teleport_helpers.sh`.

---

## Option 1: Install Workstation Helpers on Your Laptop

### Method A: Directly from This Repository
Make sure you have the `tsh` CLI installed locally, then run [install_workstation_helpers.sh](install_workstation_helpers.sh):

```bash
./examples/teleport/install_workstation_helpers.sh --proxy teleport.example.com:443
source ~/.config/teleport-helpers/teleport_helpers.sh
```

### Method B: Pull the Pre-Configured Bundle from the Teleport Bastion
`roles/teleport_server` automatically stages a ready-to-install tarball pre-configured for your environment's `teleport_public_addr` on every `[teleport_servers]` host at `/opt/teleport-workstation-bundle/teleport-workstation-helpers.tar.gz`:

```bash
# 1. Authenticate with tsh once:
tsh login --proxy=teleport.example.com:443

# 2. Download and unpack the workstation bundle from teleport-01:
tsh scp ubuntu@teleport-01:/opt/teleport-workstation-bundle/teleport-workstation-helpers.tar.gz /tmp/
mkdir -p /tmp/tp-bundle
tar -xzf /tmp/teleport-workstation-helpers.tar.gz -C /tmp/tp-bundle

# 3. Run the bundled installer:
/tmp/tp-bundle/install.sh
source ~/.config/teleport-helpers/teleport_helpers.sh
```

---

## Option 2: Use `teleport-01` Directly as a Jump Bastion

If you are working from a locked-down machine without local `tsh` helpers installed:

1. Connect to the Teleport Web UI (`https://teleport.example.com`) and open a web shell on `teleport-01` (`bastion=true`), **or** connect via `tsh ssh ubuntu@teleport-01`.
2. All helpers (`tlogin`, `tsudo`, `tapprove`, `tssh`, `tnodes`) are immediately available in your PATH.

---

## Critical Rule for JIT Sudo (`tsudo` -> `tssh`)

Teleport enforces `host_sudoers` rules when an SSH connection opens based on the roles inside your active `tsh` certificate:

1. Authenticate first: `tlogin junior`
2. Connect unprivileged to investigate: `tssh web-01`
3. When elevated privileges are needed, run `tsudo "Restarting Nginx after TLS renewal"` **on your workstation (or Bastion)** — not expecting an already-open unprivileged shell on `web-01` to change mid-session.
4. `teleport-access-watcher` on `teleport-01` automatically pushes the pending request to Alertmanager (Slack, Google Chat, Microsoft Teams, Discord, PagerDuty, Email) with a clickable approval link (`https://teleport.example.com/web/requests/<id>`). Lead Admin clicks that link in chat to approve in the Web UI (or runs `tapprove` via CLI).
5. Open a **new** session (`tssh web-01`) — your shell now receives temporary 1-hour `sudo` rights.
6. Drop elevated privileges when done: `tdrop`.

For complete RBAC, GitHub SSO, and troubleshooting instructions, see [Teleport Access & Sudo Management](../../docs/teleport-access.md).
