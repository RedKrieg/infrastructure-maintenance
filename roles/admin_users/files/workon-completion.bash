#!/usr/bin/env bash
_workon_completions()
{
    if [ "${#COMP_WORDS[@]}" -gt 2 ]; then
        return
    fi

    # Support ~/Projects (standard) as well as lowercase ~/projects if present
    local search_dirs=()
    [ -d "$HOME/Projects" ] && search_dirs+=("$HOME/Projects")
    [ -d "$HOME/projects" ] && search_dirs+=("$HOME/projects")

    if [ ${#search_dirs[@]} -eq 0 ]; then
        return
    fi

    local _project_list
    _project_list=$(find "${search_dirs[@]}" -mindepth 2 -maxdepth 2 -type d -name .venv -print0 2>/dev/null | xargs -0 -r -n1 dirname 2>/dev/null | xargs -r -n1 basename 2>/dev/null)
    COMPREPLY=($(compgen -W "${_project_list}" -- "${COMP_WORDS[COMP_CWORD]}"))
}

complete -F _workon_completions workon
complete -F _workon_completions rmvenv
complete -F _workon_completions cdp


