#!/usr/bin/env bash
#
# apmenv - Environment manager for APM (Agent Package Manager)
# Manages named profiles of agent/skill configurations and deploys them via apm.
#

set -euo pipefail

ENVS_ROOT="${HOME}/.apm-envs"
CONFIG_FILE="${ENVS_ROOT}/config.json"
ACTIVE_OUTPUT="${ENVS_ROOT}/_active"

ensure_envs_root() {
    mkdir -p "$ENVS_ROOT"
}

read_config_field() {
    local field="$1" default="${2:-}"
    if [ -f "$CONFIG_FILE" ]; then
        python3 -c "import json; d=json.load(open('$CONFIG_FILE')); v=d.get('$field'); print(','.join(v) if isinstance(v,list) else (v or ''))" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

write_config() {
    local active="$1" output_dir="$2" targets="$3"
    ensure_envs_root
    python3 -c "
import json, sys
try:
    d = json.load(open('$CONFIG_FILE'))
except Exception:
    d = {}
d['active'] = '$active'
d['outputDir'] = '$output_dir'
d['targets'] = [t for t in '$targets'.split(',') if t]
print(json.dumps(d))
" > "$CONFIG_FILE"
}

read_active() {
    read_config_field active
}

read_targets() {
    read_config_field targets
}

read_output_dir() {
    local val
    val=$(read_config_field outputDir)
    echo "${val:-$ACTIVE_OUTPUT}"
}

write_active() {
    local name="$1"
    local output_dir targets
    output_dir=$(read_output_dir)
    targets=$(read_targets)
    write_config "$name" "$output_dir" "$targets"
}

get_env_path() {
    echo "${ENVS_ROOT}/$1"
}

assert_env_exists() {
    local path
    path=$(get_env_path "$1")
    if [ ! -d "$path" ]; then
        echo "Error: Environment '$1' does not exist. Run: apmenv create $1" >&2
        exit 1
    fi
    echo "$path"
}

assert_active() {
    local active
    active=$(read_active)
    if [ -z "$active" ]; then
        echo "Error: No active environment. Run: apmenv activate <name>" >&2
        exit 1
    fi
    echo "$active"
}

cmd_create() {
    local name="" from=""
    name="${1:-}"
    shift || true

    if [ -z "$name" ]; then
        echo "Usage: apmenv create <name> [--from <existing-env>]" >&2
        exit 1
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --from) from="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done

    ensure_envs_root
    local env_path
    env_path=$(get_env_path "$name")

    if [ -d "$env_path" ]; then
        echo "Error: Environment '$name' already exists." >&2
        exit 1
    fi

    if [ -n "$from" ]; then
        local src_path
        src_path=$(assert_env_exists "$from")
        cp -r "$src_path" "$env_path"
        echo "Created environment '$name' (cloned from '$from')"
    else
        mkdir -p "$env_path"
        cat > "${env_path}/apm.yml" <<EOF
name: ${name}
version: 1.0.0
dependencies:
  apm: []
  mcp: []
EOF
        echo "Created environment '$name' at ${env_path}"
    fi
}

cmd_list() {
    ensure_envs_root
    local active
    active=$(read_active)

    local found=0
    for dir in "${ENVS_ROOT}"/*/; do
        [ -d "$dir" ] || continue
        found=1
        local env_name
        env_name=$(basename "$dir")
        [ "$env_name" = "*" ] && continue
        [ "$env_name" = "_active" ] && continue

        local marker=""
        [ "$env_name" = "$active" ] && marker=" *"

        local pkg_count=0
        if [ -f "${dir}/apm.yml" ]; then
            pkg_count=$(grep -cE '^\s+-\s' "${dir}/apm.yml" 2>/dev/null || echo 0)
        fi
        echo "${env_name}${marker}  (${pkg_count} packages)"
    done

    if [ "$found" -eq 0 ]; then
        echo "No environments. Run: apmenv create <name>"
    fi
}

cmd_activate() {
    local name="${1:-}"
    shift || true

    if [ -z "$name" ]; then
        echo "Usage: apmenv activate <name> [--target copilot,claude,...] [--root <dir>]" >&2
        exit 1
    fi

    local env_path
    env_path=$(assert_env_exists "$name")

    local targets="" root=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --target) targets="${2:-}"; shift 2 ;;
            --root)   root="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done

    # Fall back to saved default targets if none specified
    if [ -z "$targets" ]; then
        targets=$(read_targets)
    fi

    write_active "$name"

    # Clear and re-populate the _active output folder
    local deploy_root
    deploy_root="${root:-$(read_output_dir)}"
    rm -rf "$deploy_root"
    mkdir -p "$deploy_root"
    cp -r "${env_path}/"* "$deploy_root/" 2>/dev/null || true

    # Deploy
    local apm_args=("install" "--root" "$deploy_root")
    [ -n "$targets" ] && apm_args+=("--target" "$targets")

    echo "Activating environment '$name'..."
    echo "Output folder: $deploy_root"
    [ -n "$targets" ] && echo "Targets: $targets"
    (cd "$env_path" && apm "${apm_args[@]}")
    echo "Environment '$name' is now active."
    echo "Add this folder to VS Code: $deploy_root"
}

cmd_deactivate() {
    local active
    active=$(read_active)
    if [ -z "$active" ]; then
        echo "No environment is active."
        return
    fi
    write_active ""

    # Clear the _active output folder
    rm -rf "$ACTIVE_OUTPUT"

    echo "Deactivated environment '$active'. Output folder cleared."
}

cmd_remove() {
    local name="${1:-}"
    if [ -z "$name" ]; then
        echo "Usage: apmenv remove <name>" >&2
        exit 1
    fi

    local env_path
    env_path=$(assert_env_exists "$name")

    local active
    active=$(read_active)
    [ "$active" = "$name" ] && write_active ""

    rm -rf "$env_path"
    echo "Removed environment '$name'."
}

cmd_install() {
    local active
    active=$(assert_active)
    local env_path
    env_path=$(get_env_path "$active")

    # Inject saved targets when caller didn't pass --target / -t
    local has_target=false final_args=()
    local i=0 args=("$@")
    while [ $i -lt ${#args[@]} ]; do
        if [ "${args[$i]}" = "--target" ] || [ "${args[$i]}" = "-t" ]; then
            has_target=true
            final_args+=("${args[$i]}")
            i=$((i+1))
            # normalise space-joined list back to commas
            final_args+=("$(echo "${args[$i]}" | tr ' ' ',')") 
        else
            # Resolve relative paths to absolute before cd-ing into the env folder.
            # Also convert Linux/WSL paths to Windows paths when apm is a .exe binary.
            arg="${args[$i]}"
            if [[ "$arg" != -* ]] && [ -e "$arg" ]; then
                arg="$(cd "$arg" 2>/dev/null && pwd || realpath "$arg")"
                # Under WSL, apm may be a wrapper around a .exe — convert to Windows path
                if command -v wslpath >/dev/null 2>&1; then
                    # Walk the wrapper script to find the actual binary being exec'd
                    local apm_bin actual_bin
                    apm_bin="$(command -v apm)"
                    actual_bin="$(grep -oE '[^ ]+\.exe' "$apm_bin" 2>/dev/null | head -1 || echo "")"
                    if [ -n "$actual_bin" ]; then
                        arg="$(wslpath -w "$arg" 2>/dev/null || echo "$arg")"
                    fi
                fi
            fi
            final_args+=("$arg")
        fi
        i=$((i+1))
    done

    if [ "$has_target" = false ]; then
        local saved_targets
        saved_targets=$(read_targets)
        if [ -n "$saved_targets" ]; then
            final_args+=("--target" "$saved_targets")
        fi
    fi

    echo "Installing into environment '$active'..."
    if [ "$has_target" = true ] || [ -n "$(read_targets)" ]; then
        local tgt
        for j in "${!final_args[@]}"; do
            [ "${final_args[$j]}" = "--target" ] && tgt="${final_args[$((j+1))]}" && break
        done
        echo "Targets: $tgt"
    fi
    (cd "$env_path" && apm install "${final_args[@]}")

    # Auto-deploy to the output folder so changes are immediately visible
    cmd_deploy
}

cmd_uninstall() {
    local active
    active=$(assert_active)
    local env_path
    env_path=$(get_env_path "$active")

    (cd "$env_path" && apm uninstall "$@")
}

cmd_packages() {
    local active
    active=$(assert_active)
    local env_path
    env_path=$(get_env_path "$active")

    (cd "$env_path" && apm list "$@")
}

cmd_deploy() {
    local active
    active=$(assert_active)
    local env_path
    env_path=$(get_env_path "$active")

    local targets="" root=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --target) targets="${2:-}"; shift 2 ;;
            --root)   root="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done

    local apm_args=("install")
    [ -n "$root" ] && apm_args+=("--root" "$root")
    [ -n "$targets" ] && apm_args+=("--target" "$targets")

    echo "Deploying environment '$active'..."
    (cd "$env_path" && apm "${apm_args[@]}")
}

cmd_current() {
    local active
    active=$(read_active)
    if [ -n "$active" ]; then
        echo "$active"
    else
        echo "(none)"
    fi
}

cmd_setup() {
    local output_dir="" targets=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --output)  output_dir="${2:-}"; shift 2 ;;
            --targets) targets="${2:-}"; shift 2 ;;
            *) shift ;;
        esac
    done

    local cur_active cur_output cur_targets
    cur_active=$(read_active)
    cur_output=$(read_output_dir)
    cur_targets=$(read_targets)

    local new_output="${output_dir:-$cur_output}"
    local new_targets="${targets:-$cur_targets}"

    write_config "$cur_active" "$new_output" "$new_targets"

    echo "Current configuration:"
    echo "  Output directory: $new_output"
    echo "  Default targets:  ${new_targets:-(auto-detect)}"
}

show_help() {
    cat <<'EOF'
apmenv - Environment manager for APM

Usage: apmenv <command> [args]

Environment management:
  create <name> [--from <env>]     Create a new environment (optionally clone)
  list                             List all environments (* = active)
  activate <name> [--target ...]   Set active env and deploy via apm install
  deactivate                       Unset the active environment
  remove <name>                    Delete an environment
  current                          Print the active environment name

Package management (operates on active env):
  install <pkg> [apm flags]        apm install into the active environment
  uninstall <pkg>                  apm uninstall from the active environment
  packages                         apm list for the active environment

Deployment:
  deploy [--target ...] [--root .] Re-deploy active env to a workspace/target

Output folder:
  ~/.apm-envs/_active/           Add this one folder to VS Code

Examples:
  apmenv create web-dev
  apmenv activate web-dev --target copilot,claude
  apmenv install microsoft/apm-sample-package
  apmenv deploy --target codex --root ./my-project
  apmenv create data-eng --from web-dev
EOF
}

# --- Dispatch ---
command="${1:-help}"
shift || true

case "$command" in
    create)     cmd_create "$@" ;;
    list)       cmd_list ;;
    activate)   cmd_activate "$@" ;;
    deactivate) cmd_deactivate ;;
    remove)     cmd_remove "$@" ;;
    install)    cmd_install "$@" ;;
    uninstall)  cmd_uninstall "$@" ;;
    packages)   cmd_packages "$@" ;;
    deploy)     cmd_deploy "$@" ;;
    current)    cmd_current ;;
    setup)      cmd_setup "$@" ;;
    help|--help|-h) show_help ;;
    *)
        echo "Error: Unknown command: $command. Run: apmenv help" >&2
        exit 1
        ;;
esac
