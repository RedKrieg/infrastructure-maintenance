#!/usr/bin/env bash
# ==============================================================================
# Python Virtual Environment Tooling Helpers
# ==============================================================================
# Base projects directory (defaults to ~/Projects)
export PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Projects}"

# List all existing virtual environments in ~/Projects
function lsvenv() {
    local count=0
    local search_dirs=()
    [ -d "$PROJECTS_DIR" ] && search_dirs+=("$PROJECTS_DIR")
    [ -d "$HOME/projects" ] && [ "$HOME/projects" != "$PROJECTS_DIR" ] && search_dirs+=("$HOME/projects")

    echo "Configured Virtual Environments:"
    for base in "${search_dirs[@]}"; do
        if [ -d "$base" ]; then
            for d in "$base"/*; do
                if [ -d "$d/.venv" ]; then
                    local name
                    name="$(basename "$d")"
                    if [ -n "$VIRTUAL_ENV" ] && [ "$VIRTUAL_ENV" = "$d/.venv" ]; then
                        echo "  * ${name} (active)"
                    else
                        echo "    ${name}"
                    fi
                    count=$((count + 1))
                fi
            done
        fi
    done
    if [ "$count" -eq 0 ]; then
        echo "  (No virtual environments found in ${PROJECTS_DIR})"
    fi
}

# Create a new project directory and python virtual environment
function mkvenv() {
    local venv_name="$1"
    local py_bin="${2:-python3}"

    if [ -z "${venv_name}" ]; then
        echo "Usage: mkvenv <project_name> [python_binary]"
        return 1
    fi

    if ! command -v "${py_bin}" >/dev/null 2>&1; then
        echo "Error: Python interpreter '${py_bin}' not found."
        return 1
    fi

    local project_dir="${PROJECTS_DIR}/${venv_name}"
    mkdir -p "${project_dir}" || return 1
    cd "${project_dir}" || return 1

    echo "Creating virtual environment in ${project_dir}/.venv using ${py_bin}..."
    "${py_bin}" -m venv --upgrade-deps --prompt "${venv_name}" .venv || {
        echo "Failed to create virtual environment. Ensure python3-venv is installed."
        return 1
    }

    # Generate a sensible .gitignore if one does not exist
    if [ ! -f .gitignore ]; then
        cat <<'EOF' > .gitignore
.venv/
__pycache__/
*.py[cod]
*$py.class
*.so
.env
.pytest_cache/
.coverage
htmlcov/
dist/
build/
*.egg-info/
EOF
    elif ! grep -q "^\.venv" .gitignore 2>/dev/null; then
        echo ".venv/" >> .gitignore
    fi

    # Deactivate current venv if active before activating the new one
    if type deactivate >/dev/null 2>&1; then
        deactivate
    fi

    source .venv/bin/activate
    echo "Virtual environment '${venv_name}' activated."
}

# Switch to a project and activate its virtual environment
function workon() {
    local venv_name="$1"
    if [ -z "${venv_name}" ]; then
        echo "Usage: workon <project_name>"
        lsvenv
        return 1
    fi

    local project_dir=""
    if [ -d "${PROJECTS_DIR}/${venv_name}/.venv" ]; then
        project_dir="${PROJECTS_DIR}/${venv_name}"
    elif [ -d "${HOME}/projects/${venv_name}/.venv" ]; then
        project_dir="${HOME}/projects/${venv_name}"
    elif [ -d "${PROJECTS_DIR}/${venv_name}" ]; then
        project_dir="${PROJECTS_DIR}/${venv_name}"
    else
        echo "Error: Project '${venv_name}' not found."
        lsvenv
        return 1
    fi

    if [ ! -f "${project_dir}/.venv/bin/activate" ]; then
        echo "Error: No virtual environment (.venv) found in ${project_dir}"
        return 1
    fi

    # Deactivate existing active venv
    if type deactivate >/dev/null 2>&1; then
        deactivate
    fi

    cd "${project_dir}" || return 1
    source .venv/bin/activate
}

# Safely remove a project's virtual environment
function rmvenv() {
    local venv_name="$1"
    local force="$2"

    if [ -z "${venv_name}" ]; then
        echo "Usage: rmvenv <project_name> [-f|--force]"
        return 1
    fi

    local project_dir=""
    if [ -d "${PROJECTS_DIR}/${venv_name}" ]; then
        project_dir="${PROJECTS_DIR}/${venv_name}"
    elif [ -d "${HOME}/projects/${venv_name}" ]; then
        project_dir="${HOME}/projects/${venv_name}"
    else
        echo "Error: Project directory for '${venv_name}' not found."
        return 1
    fi

    if [ ! -d "${project_dir}/.venv" ]; then
        echo "Error: No .venv found in ${project_dir}"
        return 1
    fi

    if [ "$force" != "-f" ] && [ "$force" != "--force" ]; then
        read -r -p "Are you sure you want to remove .venv in ${project_dir}? [y/N] " confirm
        case "$confirm" in
            [yY][eE][sS]|[yY]) ;;
            *) echo "Aborted."; return 0 ;;
        esac
    fi

    # Deactivate if the environment being deleted is currently active
    if [ -n "$VIRTUAL_ENV" ] && [ "$VIRTUAL_ENV" = "${project_dir}/.venv" ]; then
        deactivate
    fi

    rm -rf "${project_dir}/.venv"
    echo "Removed .venv from ${project_dir}"
}

# Navigate quickly to a project directory
function cdp() {
    local venv_name="$1"
    if [ -z "${venv_name}" ]; then
        cd "${PROJECTS_DIR}" || return
    elif [ -d "${PROJECTS_DIR}/${venv_name}" ]; then
        cd "${PROJECTS_DIR}/${venv_name}" || return
    elif [ -d "${HOME}/projects/${venv_name}" ]; then
        cd "${HOME}/projects/${venv_name}" || return
    else
        echo "Directory not found: ${PROJECTS_DIR}/${venv_name}"
        return 1
    fi
}
