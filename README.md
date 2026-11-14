# Headless Ubuntu Initial Setup Ansible Playbook

An automated, role-based Ansible suite to provision, harden, and bootstrap fresh headless Ubuntu systems. Modularized into isolated roles with fine-grained task tagging, automated kernel & storage tuning, UFW connection throttling, SSH daemon hardening with keepalives, Vim/Tmux/Screen/Git defaults, and dedicated Python virtual environment tooling.

---

## Workspace Structure

```
.
├── ansible.cfg                      # Ansible defaults (pipelining, roles_path, YAML output)
├── inventory.ini                    # Inventory defining remote headless nodes
├── playbook.yml                     # Main entry-point playbook orchestrating roles
├── vars/
│   └── admin_users.yml              # Central users configuration file (add new admins here)
├── roles/
│   ├── system_base/                 # Core packages, maintenance, kernel & hardware tuning
│   │   ├── defaults/main.yml
│   │   ├── handlers/main.yml
│   │   └── tasks/
│   │       ├── assert.yml           # OS pre-flight validation
│   │       ├── editor.yml           # Vim system alternative & /etc/environment
│   │       ├── journald.yml         # 500M systemd journal disk cap
│   │       ├── kernel_tuning.yml    # BBR, inotify, conditional swap (<4GB), SSD TRIM
│   │       ├── maintenance.yml      # needrestart auto-restarts & 4:00 AM reboot schedule
│   │       ├── main.yml             # Task dispatcher
│   │       ├── packages.yml         # Package suite installation
│   │       └── sysstat.yml          # sar historical accounting
│   ├── security/                    # Host security & firewall isolation
│   │   ├── defaults/main.yml
│   │   ├── handlers/main.yml
│   │   └── tasks/
│   │       ├── main.yml
│   │       ├── sshd.yml             # SSH daemon hardening & server keepalives
│   │       └── ufw.yml              # UFW firewall & connection rate limiting
│   └── admin_users/                 # Per-user provisioning & dotfiles
│       ├── defaults/main.yml
│       ├── files/                   # User dotfiles & scripts
│       │   ├── bashrc_addons
│       │   ├── gitconfig            # push.autoSetupRemote, defaultBranch main
│       │   ├── screenrc             # 10k scrollback, visual bell off, status bar
│       │   ├── tmux.conf            # Mouse mode, 256 colors, 10k scrollback, vi mode
│       │   ├── venv_helpers.bash    # Python venv tooling (mkvenv, workon, etc.)
│       │   ├── vimrc                # Preferred Vim config with Pathogen
│       │   └── workon-completion.bash
│       └── tasks/
│           ├── main.yml             # Iterates through admin_users
│           └── user_setup.yml       # Provisions user, keys, sudo, dotfiles, ssh config
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

## The Three Isolated Roles

### 1. `system_base`
- **Package Suite**: Installs essential sysadmin diagnostics (`iotop`, `lm-sensors`, `iftop`, `iptraf-ng`, `htop`, `btop`, `sysstat`, `strace`, `lsof`, `ncdu`, `tcpdump`, `mtr-tiny`, `iperf3`, `nmap`, `socat`, `smartmontools`, `nvme-cli`, `pciutils`, `usbutils`, `hdparm`, `tmux`, `screen`, `tree`, `jq`, `ripgrep`, `fd-find`, `rsync`, `unzip`, `build-essential`, `python3-venv`, `pipx`).
- **Default Editor**: Configures Vim as the system-wide alternative and exports `EDITOR=vim` and `VISUAL=vim`.
- **Maintenance & Automatic Daemon Restarts**:
  - Configures `needrestart` (`/etc/needrestart/conf.d/auto-restart.conf`) for non-interactive automatic daemon restarts after library updates, preventing interactive curses prompts from hanging automation.
  - Configures `unattended-upgrades` to perform scheduled reboots for security updates at **`04:00 AM` local time** (`/etc/apt/apt.conf.d/52unattended-upgrades-reboot`).
- **Kernel, Memory & Storage Tuning**:
  - **BBR Congestion Control**: Loads `tcp_bbr` and configures `net.core.default_qdisc = fq` and `net.ipv4.tcp_congestion_control = bbr` for lower latency and improved throughput.
  - **Inotify Limits**: Increases `fs.inotify.max_user_watches = 524288` and `fs.inotify.max_user_instances = 512` for development tools and file watchers.
  - **Conditional Swap**: Inspects system memory; if total RAM is **under 4GB**, automatically creates, formats, mounts, and activates a **2GB swapfile** (`/swapfile`) with `vm.swappiness = 10` and `vm.vfs_cache_pressure = 50`. If the system has 4GB or more RAM, swap creation is skipped.
  - **Physical Hardware SSD TRIM**: Checks virtualization facts; if the host is running on **bare-metal hardware** (`ansible_virtualization_role == 'host'`), enables `fstrim.timer` to automatically reclaim SSD blocks.
  - **`fd` Symlink**: Symlinks `/usr/local/bin/fd -> /usr/bin/fdfind`.

### 2. `security`
- **UFW Firewall with Rate Limiting**:
  - Sets default inbound policy to `deny` and outbound to `allow`.
  - Configures `ufw limit 22/tcp` and allows OpenSSH profile.
- **SSH Daemon Hardening & Server Keepalives**:
  - Deploys `/etc/ssh/sshd_config.d/01-hardening.conf`.
  - Enforces `PasswordAuthentication no`, `PermitRootLogin prohibit-password`, `PubkeyAuthentication yes`, `KbdInteractiveAuthentication no`, `X11Forwarding no`, and `MaxAuthTries 4`.
  - Configures server-side keepalives: `ClientAliveInterval 120` and `ClientAliveCountMax 3` (drops unresponsive connections after 6 minutes of silence).
  - *Note: `fail2ban` and `/etc/pam.d/su` are not used.*

### 3. `admin_users`
- Provisions all users listed in `vars/admin_users.yml`.
- For each user:
  - Account and primary group creation with `sudo` group membership.
  - Passwordless sudo configuration in `/etc/sudoers.d/<username>`.
  - Authorized SSH public keys injection.
  - SSH client multiplexing: `~/.ssh/config` with `ControlMaster auto`, `ControlPath ~/.ssh/control/%C`, and `ControlPersist 300`.
  - Preferred Vim configuration with `pathogen.vim` setup.
  - Python virtual environment tooling (`~/.venv_helpers.bash` with `mkvenv`, `workon`, `lsvenv`, `rmvenv`, `cdp`) and `~/Projects/`.
  - Bash completion for `workon`, `rmvenv`, and `cdp`.
  - **`~/.tmux.conf`**: Mouse mode enabled, 256 colors, 10,000-line scrollback buffer, base-index 1, and Vi keybindings.
  - **`~/.screenrc`**: 10,000-line scrollback buffer, visual bell disabled, altscreen enabled, and clean status line.
  - **`~/.gitconfig`**: Includes `push.autoSetupRemote = true` (automatic upstream branch creation on push), `init.defaultBranch = main`, `pull.rebase = false`, and `core.editor = vim`.

---

## UFW Connection Rate Limiting Explained

### How it Works
When UFW applies `ufw limit 22/tcp`, it programs the Linux kernel netfilter/iptables subsystem using the `recent` module:
- It tracks incoming connection attempts (`SYN` packets) per source IP address.
- It calculates connections over a **sliding window of 30 seconds**.
- If an IP address initiates **6 or more connections within 30 seconds**, the kernel immediately begins dropping all new connection attempts from that IP.

### How Long is the Block?
- **Duration**: The block lasts for **30 seconds from the last rejected connection attempt**.
- Because the kernel uses a sliding window, if an automated brute-force bot continuously sends connection attempts, each attempt resets the 30-second timer, keeping the attacker blocked indefinitely.
- Once the IP stops connecting for **30 seconds**, the counter drops below 6 and normal access is instantly restored. Legitimate administrators are never permanently locked out by a typo or connection glitch.

---

## Managing Administrative Users

All administrative accounts and SSH public keys are managed in **`vars/admin_users.yml`**:

```yaml
admin_users:
  - name: redkrieg
    shell: /bin/bash
    sudo_nopasswd: true
    authorized_keys:
      - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID9pb/LNL4+4KU8xPbibpuTkZb/0RIz/98clnXrtxcHG redkrieg@cortex-1"

  # To add another administrator:
  # - name: alex
  #   shell: /bin/bash
  #   sudo_nopasswd: true
  #   authorized_keys:
  #     - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... alex@workstation"
```

---

## How to Run the Playbook

### Full Deployment
Execute against all hosts in `inventory.ini`:
```bash
ansible-playbook -i inventory.ini playbook.yml
```

Target a single ad-hoc host directly:
```bash
ansible-playbook -i '192.168.1.100,' -u ubuntu playbook.yml
```

### Fast Selective Execution Using Tags

Because tasks are tagged, you can run isolated sections of the playbook:

| Goal | Command |
| :--- | :--- |
| **Add / Update Admin Users Only** (skips package installation and system tuning) | `ansible-playbook -i inventory.ini playbook.yml --tags users` |
| **Update User Dotfiles Only** (`.tmux.conf`, `.screenrc`, `.gitconfig`, `.vimrc`) | `ansible-playbook -i inventory.ini playbook.yml --tags dotfiles` |
| **Update Firewall & SSH Daemon Settings Only** | `ansible-playbook -i inventory.ini playbook.yml --tags security` |
| **Run Kernel & Hardware Tuning Only** (BBR, Swap, TRIM, Inotify) | `ansible-playbook -i inventory.ini playbook.yml --tags tuning` |
| **Install / Update Packages Only** | `ansible-playbook -i inventory.ini playbook.yml --tags packages` |
| **Perform a Dry Run (Check Mode)** | `ansible-playbook -i inventory.ini playbook.yml --check --diff` |

---

## Post-Install Connection
Log in as any provisioned administrator:
```bash
ssh redkrieg@192.168.1.100
```
