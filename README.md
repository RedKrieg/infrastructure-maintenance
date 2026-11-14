# Headless Ubuntu Initial Setup Ansible Playbook

An automated, role-based Ansible solution to provision, configure, and bootstrap new headless Ubuntu systems. Designed with modular administrative user management, UFW firewall security, SSH daemon hardening, SSH client multiplexing, Vim editor defaults, shell quality-of-life enhancements, Python virtual environment tooling, sysadmin troubleshooting suites, and headless performance tuning.

---

## Workspace Structure

```
.
├── ansible.cfg                      # Ansible defaults (pipelining, roles_path, YAML output)
├── inventory.ini                    # Inventory defining remote headless nodes
├── playbook.yml                     # Main entry-point playbook (invokes setup_base role)
├── vars/
│   └── admin_users.yml              # Central users configuration file (add new admins here)
├── roles/
│   └── setup_base/                  # Core provisioning role
│       ├── defaults/
│       │   └── main.yml             # Default variables and package lists
│       ├── files/                   # Static files deployed to targets
│       │   ├── bashrc_addons        # Shell environment, aliases, and loaders
│       │   ├── venv_helpers.bash    # Python virtual environment tooling helpers
│       │   ├── vimrc                # Preferred Vim configuration
│       │   └── workon-completion.bash # Tab completion for workon, rmvenv, and cdp
│       ├── handlers/
│       │   └── main.yml             # Handlers (sshd, sysstat, journald)
│       └── tasks/                   # Modular sub-tasks
│           ├── assert.yml           # OS family pre-flight validation
│           ├── editor.yml           # System-wide Vim alternatives & environment
│           ├── main.yml             # Task dispatcher
│           ├── packages.yml         # Apt cache updates & package installation
│           ├── security.yml         # UFW firewall & SSH daemon hardening
│           ├── system.yml           # Headless tuning & system optimizations
│           ├── user_setup.yml       # Per-user provisioning tasks
│           └── users.yml            # Iterates over admin_users list
├── authorized_keys                  # Default public key for redkrieg
├── bashrc_addons                    # Root copy of shell addons
├── venv_helpers.bash                # Root copy of venv tooling helpers
├── vimrc                            # Root copy of Vim configuration
├── workon-completion.bash           # Root copy of tab completion script
└── README.md                        # Documentation and usage guide
```

---

## Managing Administrative Users

All administrative users and their SSH public keys are managed centrally in **`vars/admin_users.yml`**.

### How Users Are Configured
The file defines an `admin_users` list of user dictionaries. Each entry supports the following keys:
- `name` *(required)*: The system username (e.g., `redkrieg`).
- `shell` *(optional, defaults to `/bin/bash`)*: User's login shell.
- `sudo_nopasswd` *(optional, defaults to `true`)*: Grants passwordless sudo via `/etc/sudoers.d/<username>`.
- `authorized_keys` *(optional)*: List of public SSH key strings to inject into `~/.ssh/authorized_keys`.
- `key` *(optional)*: Single public SSH key string.
- `key_file` *(optional)*: Relative path to a local key file (e.g. `authorized_keys`).

### Example: Adding a New Admin User
To provision an additional administrator, open `vars/admin_users.yml` and append their definition to the `admin_users` list:

```yaml
admin_users:
  # Existing admin user
  - name: redkrieg
    shell: /bin/bash
    sudo_nopasswd: true
    authorized_keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID9pb/LNL4+4KU8xPbibpuTkZb/0RIz/98clnXrtxcHG redkrieg@cortex-1"

  # New admin user
  - name: alex
    shell: /bin/bash
    sudo_nopasswd: true
    authorized_keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC59zK... alex@workstation"
```

### What Each Admin User Automatically Receives
Every user listed in `vars/admin_users.yml` is provisioned identically:
1. **System Account & Group**: Dedicated primary group and user created with supplementary `sudo` group membership.
2. **Passwordless Sudo**: Drop-in sudoers file at `/etc/sudoers.d/<username>` (validated via `visudo -cf`).
3. **SSH Authorized Keys**: Injected into `/home/<username>/.ssh/authorized_keys` (mode `0600`).
4. **SSH Client Multiplexing**: Configures `/home/<username>/.ssh/config` and `/home/<username>/.ssh/control/` with `ControlMaster auto`, `ControlPath ~/.ssh/control/%C`, and `ControlPersist 300`.
5. **Vim Defaults & Pathogen**: Deploys `~/.vimrc`, sets up `~/.vim/autoload/pathogen.vim`, and sets `~/.selected_editor`.
6. **Shell Addons & Environment**: Deploys `~/.bashrc_addons` and sources it from `~/.bashrc`.
7. **Python Virtual Environment Tooling**: Deploys `~/.venv_helpers.bash` and `~/Projects/`.
8. **Tab Completion**: Deploys `workon-completion.bash` into `~/.bash_completion.d/`.

---

## How to Run the Playbook

### 1. Define Target Nodes in `inventory.ini`
Open `inventory.ini` and specify your remote server IP or hostname and the connection user. The connecting user must have passwordless sudo on the remote system:

```ini
[headless_nodes]
192.168.1.100 ansible_user=ubuntu
192.168.1.101 ansible_user=ubuntu
```

### 2. Execute the Playbook

Run against the entire inventory:
```bash
ansible-playbook -i inventory.ini playbook.yml
```

Run against a specific host in the inventory:
```bash
ansible-playbook -i inventory.ini playbook.yml --limit 192.168.1.100
```

Run ad-hoc against a single IP without modifying `inventory.ini`:
```bash
ansible-playbook -i '192.168.1.100,' -u ubuntu playbook.yml
```

Perform a dry run (check mode) without making changes:
```bash
ansible-playbook -i inventory.ini playbook.yml --check --diff
```

### 3. Connect as the Provisioned Admin User
Once the playbook completes, log in using any configured admin account:

```bash
ssh redkrieg@192.168.1.100
```

---

## Role Features & Defaults

### Security Hardening (Enabled by Default)
- **UFW Firewall**:
  - Automatically permits OpenSSH and port `22/tcp` before activating.
  - Sets default inbound policy to `deny` and outbound to `allow`.
  - Enables the firewall service without risking SSH lockout.
- **SSH Daemon Hardening**:
  - Drops `/etc/ssh/sshd_config.d/01-hardening.conf` enforcing `PasswordAuthentication no`, `PermitRootLogin prohibit-password`, `PubkeyAuthentication yes`, `KbdInteractiveAuthentication no`, `X11Forwarding no`, and `MaxAuthTries 4`.
  - *Note: `fail2ban` is not used.*

### SSH Client Multiplexing
- Creates `/home/<user>/.ssh/control/` with permissions `0700`.
- Sets `ControlPath ~/.ssh/control/%C` to avoid UNIX domain socket path length limits (108 characters on Linux).
- Sets `ControlPersist 300` (5 minutes) and client keep-alives (`ServerAliveInterval 60`).

### Default Editor (Vim)
- Installs full `vim` package.
- Sets `/usr/bin/vim.basic` as system default alternative via `update-alternatives`.
- Exports `EDITOR=vim` and `VISUAL=vim` in `/etc/environment`.
- Installs `pathogen.vim` in `~/.vim/autoload/` so `execute pathogen#infect()` runs without warning.

### Python Virtual Environment Helpers (`venv_helpers.bash`)
- `mkvenv <name> [python_bin]`: Creates `~/Projects/<name>`, generates virtual environment with `--upgrade-deps` and `--prompt <name>`, automatically creates a `.gitignore` if missing, and activates it.
- `workon <name>`: Checks `~/Projects/<name>/.venv`, cleanly deactivates any running venv, switches directory, and activates the new environment. If run with no arguments, lists available environments.
- `lsvenv`: Scans `~/Projects` and lists all configured environments, indicating which one is currently active.
- `rmvenv <name> [-f|--force]`: Confirms before deleting `.venv`, and automatically deactivates if active.
- `cdp <name>`: Fast directory change directly into `~/Projects/<name>`.
- Tab completion (`workon-completion.bash`) matches both `~/Projects` and `~/projects` for `workon`, `rmvenv`, and `cdp`.

### Sysadmin Diagnostics Suite
- **Requested Diagnostics**: `iotop`, `lm-sensors`, `iftop`, `iptraf-ng`.
- **Process & Performance**: `htop`, `btop`, `sysstat` (sar/iostat), `strace`, `lsof`, `ncdu`.
- **Network Analysis**: `tcpdump`, `mtr-tiny`, `iperf3`, `nmap`, `socat`, `net-tools`, `iputils-ping`, `dnsutils`, `ethtool`, `curl`, `wget`.
- **Storage & Hardware**: `smartmontools`, `nvme-cli`, `pciutils`, `usbutils`, `hdparm`.
- **Python & Build Tools**: `python3`, `python3-venv`, `python3-pip`, `python3-dev`, `pipx`, `build-essential`, `git`.
- **Productivity**: `tmux`, `tree`, `jq`, `ripgrep`, `fd-find`, `rsync`, `unzip`, `bash-completion`.

### Headless Optimizations
- **Sysstat (sar)**: Enables `ENABLED="true"` in `/etc/default/sysstat` and starts the `sysstat` service for continuous 10-minute historical performance logging.
- **Journald Storage Limit**: Caps `systemd-journald` disk usage at `500M` (`/etc/systemd/journald.conf.d/maxuse.conf`) to avoid root disk saturation.
- **`fd` Symlink**: Symlinks `/usr/bin/fdfind` to `/usr/local/bin/fd`.
- **NTP Synchronization**: Enables `systemd-timesyncd`.
- **Automatic Security Patches**: Enables `unattended-upgrades`.
