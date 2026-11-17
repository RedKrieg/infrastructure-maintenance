#!/usr/bin/env bash
# ==============================================================================
# Portable Teleport Workstation Helper & Alias Bundle Installer
# Installs tlogin, tsudo, tstatus, tdrop, tssh, tapprove, tnodes, and tapps
# onto an administrator or junior operator workstation.
#
# Usage:
#   ./examples/teleport/install_workstation_helpers.sh --proxy teleport.example.com:443
#   ./examples/teleport/install_workstation_helpers.sh --proxy teleport.example.com:443 --bin-dir ~/.local/bin
# ==============================================================================
set -euo pipefail

PROXY_ADDR="${TELEPORT_PROXY:-teleport.example.com:443}"
if [ "$(id -u)" -eq 0 ]; then
    BIN_DIR="/usr/local/bin"
    ALIAS_FILE="/etc/profile.d/teleport_helpers.sh"
else
    BIN_DIR="${HOME}/.local/bin"
    ALIAS_FILE="${HOME}/.config/teleport-helpers/teleport_helpers.sh"
fi

usage() {
    cat <<EOF
Usage: $(basename "$0") [--proxy <host:port>] [--bin-dir <dir>]

Options:
  --proxy <host:port>   Teleport proxy address (default: ${PROXY_ADDR})
  --bin-dir <dir>       Target directory for CLI wrappers (default: ${BIN_DIR})
  -h, --help            Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --proxy)
            PROXY_ADDR="${2:?--proxy requires an argument}"
            shift 2
            ;;
        --bin-dir)
            BIN_DIR="${2:?--bin-dir requires an argument}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

mkdir -p "${BIN_DIR}" "$(dirname "${ALIAS_FILE}")"

cat > "${BIN_DIR}/teleport-login" <<EOF
#!/usr/bin/env bash
set -e
DEFAULT_PROXY="${PROXY_ADDR}"
PROXY="\${TELEPORT_PROXY:-\$DEFAULT_PROXY}"
USER_ARG="\${1:-\${TELEPORT_USER:-\$USER}}"

echo "===================================================================="
echo " Teleport Cluster Login"
echo "===================================================================="
echo " Proxy Address : \${PROXY}"
echo " User Account  : \${USER_ARG}"
echo "===================================================================="

tsh login --proxy="\${PROXY}" --user="\${USER_ARG}"

echo ""
echo "[✓] Successfully logged into Teleport!"
tsh status
EOF

cat > "${BIN_DIR}/teleport-request-sudo" <<'EOF'
#!/usr/bin/env bash
set -e

ELEVATED_ROLE="elevated-sudo"
NOWAIT=0
REASON=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --nowait|-n)
            NOWAIT=1
            shift
            ;;
        -h|--help)
            echo "Usage: teleport-request-sudo [--nowait] [reason...]"
            echo "Requests temporary 'elevated-sudo' access in the Teleport cluster."
            exit 0
            ;;
        *)
            REASON="${REASON:+${REASON} }$1"
            shift
            ;;
    esac
done

if [ -z "$REASON" ]; then
    echo "===================================================================="
    echo " Teleport Just-In-Time Sudo Elevation Request"
    echo "===================================================================="
    read -r -p "Enter justification reason for sudo access: " REASON
fi

if [ -z "$REASON" ]; then
    echo "[!] Error: A justification reason is required." >&2
    exit 1
fi

echo "===================================================================="
echo " Submitting Sudo Elevation Request"
echo " Role          : ${ELEVATED_ROLE}"
echo " Justification : ${REASON}"
echo "===================================================================="

if [ "$NOWAIT" -eq 1 ]; then
    tsh request create --roles="${ELEVATED_ROLE}" --reason="${REASON}" --nowait
    echo ""
    echo "[✓] Sudo request submitted in background."
    echo "Check status with: teleport-status"
    echo "Once approved, activate role: tsh login --request-id=<ID>"
    echo "Then open a NEW SSH session (e.g. tssh web-01) for host sudoers to apply."
else
    echo "[*] Waiting for lead administrator approval (Press Ctrl+C to cancel wait)..."
    tsh request create --roles="${ELEVATED_ROLE}" --reason="${REASON}"
    echo ""
    echo "===================================================================="
    echo "[✓] Access request APPROVED!"
    echo "Your elevated certificate is now active (1 hour expiration)."
    echo "Open a NEW SSH session (e.g. 'tssh <nodename>') so the target host"
    echo "provisions your temporary sudoers entry for this session."
    echo "NOTE: Previously open unprivileged SSH shells are NOT retroactively elevated."
    echo "When finished, drop elevated privileges with: teleport-drop-sudo"
    echo "===================================================================="
fi
EOF

cat > "${BIN_DIR}/teleport-status" <<'EOF'
#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " Teleport Session & Privilege Status"
echo "===================================================================="

if ! tsh status >/dev/null 2>&1; then
    echo "[!] You are not currently logged in to Teleport."
    echo "Run 'teleport-login' to authenticate."
    exit 1
fi

tsh status

echo ""
echo "--- Active / Pending Access Requests ---"
tsh request ls 2>/dev/null || echo "No active access requests."

if tsh status 2>/dev/null | grep -q "elevated-sudo"; then
    echo ""
    echo "[!] NOTICE: Elevated sudo privileges are currently ACTIVE."
    echo "    To revert to standard unprivileged role: teleport-drop-sudo"
else
    echo ""
    echo "[i] Status: Standard unprivileged access (No sudo)."
    echo "    To request sudo escalation: teleport-request-sudo <reason>"
fi
EOF

cat > "${BIN_DIR}/teleport-drop-sudo" <<'EOF'
#!/usr/bin/env bash
set -e

echo "===================================================================="
echo " Dropping Teleport Elevated Privileges"
echo "===================================================================="

if ! tsh status >/dev/null 2>&1; then
    echo "[!] Not logged in to Teleport."
    exit 0
fi

tsh request drop

echo ""
echo "[✓] Elevated sudo privileges successfully dropped."
echo "You have reverted to standard unprivileged role."
EOF

cat > "${BIN_DIR}/teleport-ssh" <<'EOF'
#!/usr/bin/env bash
set -e

if [ $# -eq 0 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "Usage: teleport-ssh [user@]nodename [command...]"
    echo ""
    echo "Available cluster nodes:"
    tsh ls
    exit 0
fi

TARGET="$1"
shift

tsh ssh "$TARGET" "$@"
EOF

cat > "${BIN_DIR}/teleport-approve-sudo" <<'EOF'
#!/usr/bin/env bash
set -e

REQ_ID="${1:-}"

if [ -z "$REQ_ID" ]; then
    echo "===================================================================="
    echo " Pending Access Requests in Cluster"
    echo "===================================================================="
    if command -v tctl >/dev/null 2>&1 && [ -w /var/lib/teleport ]; then
        tctl request ls
    else
        tsh request ls
    fi
    echo ""
    read -r -p "Enter Request ID to approve (or Ctrl+C to cancel): " REQ_ID
fi

if [ -n "$REQ_ID" ]; then
    echo "[*] Approving request ${REQ_ID}..."
    if command -v tctl >/dev/null 2>&1 && [ -w /var/lib/teleport ]; then
        tctl request approve "$REQ_ID"
    else
        tsh request review --approve "$REQ_ID"
    fi
    echo "[✓] Request ${REQ_ID} successfully approved!"
fi
EOF

chmod 0755 \
    "${BIN_DIR}/teleport-login" \
    "${BIN_DIR}/teleport-request-sudo" \
    "${BIN_DIR}/teleport-status" \
    "${BIN_DIR}/teleport-drop-sudo" \
    "${BIN_DIR}/teleport-ssh" \
    "${BIN_DIR}/teleport-approve-sudo"

cat > "${ALIAS_FILE}" <<'EOF'
# Unified Teleport Workstation Aliases

alias tlogin='teleport-login'
alias tsudo='teleport-request-sudo'
alias tstatus='teleport-status'
alias tdrop='teleport-drop-sudo'
alias tssh='teleport-ssh'
alias tapprove='teleport-approve-sudo'
alias tnodes='tsh ls'
alias tapps='tsh app ls'
EOF
chmod 0644 "${ALIAS_FILE}"

if [ "$(id -u)" -ne 0 ]; then
    SOURCE_LINE="[ -f \"${ALIAS_FILE}\" ] && source \"${ALIAS_FILE}\""
    for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
        if [ -f "${rc}" ] && ! grep -Fq "${ALIAS_FILE}" "${rc}"; then
            {
                echo ""
                echo "# Teleport Workstation Helpers"
                echo "${SOURCE_LINE}"
            } >> "${rc}"
            echo "Updated ${rc} with Teleport aliases."
        fi
    done
    case ":${PATH}:" in
        *":${BIN_DIR}:"*) ;;
        *) echo "NOTE: Ensure ${BIN_DIR} is in your PATH (e.g. export PATH=\"${BIN_DIR}:\$PATH\")." ;;
    esac
fi

echo "[✓] Installed Teleport workstation helpers to ${BIN_DIR} (default proxy: ${PROXY_ADDR})"
echo "[✓] Alias file written to ${ALIAS_FILE}"
echo "    Run: source \"${ALIAS_FILE}\""
