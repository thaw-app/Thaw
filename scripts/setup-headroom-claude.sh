#!/usr/bin/env bash
#
# setup-headroom-claude.sh — Headroom + Claude Code CLI setup
#
# Configures token compression for the terminal Claude Code CLI (not Claude Desktop;
# Desktop ignores ANTHROPIC_BASE_URL and cannot use the proxy in subscription mode).
#
# Installers supported:
#   - micromamba  — isolated env (default when micromamba is available)
#   - pip         — python3 -m pip install --user
#   - pipx        — pipx install (isolated app, good when micromamba is absent)
#   - auto        — micromamba, else pipx, else pip
#
# What this script does:
#   1. Installs headroom-ai[proxy,mcp] via the chosen installer
#   2. Runs `headroom init claude -g` (settings.json env + session hooks)
#   3. Registers the Headroom MCP server with the absolute headroom binary path
#   4. Installs ~/.local/bin/claude-headroom (wrap launcher)
#   5. Starts the proxy if nothing is listening on the chosen port
#   6. Runs `headroom doctor`
#
# Usage:
#   ./scripts/setup-headroom-claude.sh
#   ./scripts/setup-headroom-claude.sh --installer pip
#   ./scripts/setup-headroom-claude.sh --installer micromamba --env base
#   ./scripts/setup-headroom-claude.sh --installer pipx --python python3.12
#   ./scripts/setup-headroom-claude.sh --check
#   ./scripts/setup-headroom-claude.sh --skip-install
#
set -euo pipefail

HEADROOM_ENV="${HEADROOM_ENV:-headroom}"
HEADROOM_PORT="${HEADROOM_PORT:-8787}"
INSTALLER="${INSTALLER:-auto}"
PIP_PYTHON="${PIP_PYTHON:-}"
SKIP_INSTALL=false
CHECK_ONLY=false
INSTALL_LAUNCHER=true

MAMBA_CMD=()
HEADROOM_BIN=""
INSTALLER_RESOLVED=""

usage() {
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
    printf '\nOptions:\n'
    printf '  --installer MODE   auto | micromamba | pip | pipx (default: auto)\n'
    printf '  --env NAME         Micromamba environment name (default: headroom)\n'
    printf '  --python BIN       Python for pip/pipx (default: newest 3.10–3.13)\n'
    printf '  --port PORT        Headroom proxy port (default: 8787)\n'
    printf '  --skip-install     Skip package install; configure only\n'
    printf '  --no-launcher      Do not install ~/.local/bin/claude-headroom\n'
    printf '  --check            Verify setup; do not change anything\n'
    printf '  -h, --help         Show this help\n'
    printf '\nEnvironment variables (mirror the flags above; flags take precedence):\n'
    printf '  HEADROOM_ENV       Micromamba environment name (default: headroom)\n'
    printf '  HEADROOM_PORT      Headroom proxy port (default: 8787)\n'
    printf '  INSTALLER          auto | micromamba | pip | pipx (default: auto)\n'
    printf '  PIP_PYTHON         Python binary for pip/pipx installs (default: newest 3.10-3.13)\n'
}

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --installer)    INSTALLER="$2"; shift 2 ;;
        --env)          HEADROOM_ENV="$2"; shift 2 ;;
        --python)       PIP_PYTHON="$2"; shift 2 ;;
        --port)         HEADROOM_PORT="$2"; shift 2 ;;
        --skip-install) SKIP_INSTALL=true; shift ;;
        --no-launcher)  INSTALL_LAUNCHER=false; shift ;;
        --check)        CHECK_ONLY=true; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              die "unknown option: $1 (try --help)" ;;
    esac
done

case "$INSTALLER" in
    auto|micromamba|pip|pipx) ;;
    *) die "invalid --installer '${INSTALLER}' (use auto, micromamba, pip, or pipx)" ;;
esac

if ! [[ "$HEADROOM_PORT" =~ ^[0-9]+$ ]] || (( HEADROOM_PORT < 1024 || HEADROOM_PORT > 65535 )); then
    die "invalid port: $HEADROOM_PORT"
fi

PROXY_URL="http://127.0.0.1:${HEADROOM_PORT}"
HEADROOM_PACKAGE='headroom-ai[proxy,mcp]'

find_micromamba() {
    if command -v micromamba >/dev/null 2>&1; then
        MAMBA_CMD=(micromamba)
        return 0
    fi
    if [[ -n "${MAMBA_EXE:-}" && -x "$MAMBA_EXE" ]]; then
        MAMBA_CMD=("$MAMBA_EXE")
        return 0
    fi
    if [[ -x /opt/homebrew/opt/micromamba/bin/micromamba ]]; then
        MAMBA_CMD=(/opt/homebrew/opt/micromamba/bin/micromamba)
        return 0
    fi
    return 1
}

mamba_env_exists() {
    "${MAMBA_CMD[@]}" env list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$HEADROOM_ENV"
}

mamba_run() {
    "${MAMBA_CMD[@]}" run -n "$HEADROOM_ENV" --no-capture-output "$@"
}

python_is_compatible() {
    local py="$1"
    command -v "$py" >/dev/null 2>&1 || return 1
    "$py" -c 'import sys; raise SystemExit(0 if (3, 10) <= sys.version_info[:2] <= (3, 13) else 1)' 2>/dev/null
}

find_compatible_python() {
    local py
    if [[ -n "$PIP_PYTHON" ]]; then
        python_is_compatible "$PIP_PYTHON" || die "Python '${PIP_PYTHON}' is missing or unsupported (need 3.10–3.13)"
        echo "$PIP_PYTHON"
        return 0
    fi
    for py in python3.13 python3.12 python3.11 python3.10 python3; do
        if python_is_compatible "$py"; then
            echo "$py"
            return 0
        fi
    done
    return 1
}

ensure_user_local_bin() {
    local user_base
    user_base="$("$1" -m site --user-base 2>/dev/null || true)"
    if [[ -n "$user_base" && -d "${user_base}/bin" ]]; then
        case ":${PATH}:" in
            *":${user_base}/bin:"*) ;;
            *) export PATH="${user_base}/bin:${PATH}" ;;
        esac
    fi
    if [[ -d "$HOME/.local/bin" ]]; then
        case ":${PATH}:" in
            *":${HOME}/.local/bin:"*) ;;
            *) export PATH="${HOME}/.local/bin:${PATH}" ;;
        esac
    fi
}

resolve_installer_auto() {
    if find_micromamba; then
        echo micromamba
        return 0
    fi
    if command -v pipx >/dev/null 2>&1 && find_compatible_python >/dev/null; then
        echo pipx
        return 0
    fi
    if find_compatible_python >/dev/null; then
        echo pip
        return 0
    fi
    return 1
}

install_with_micromamba() {
    find_micromamba || die "micromamba not found (install: brew install micromamba, or use --installer pip)"

    if ! $SKIP_INSTALL; then
        if ! mamba_env_exists; then
            say "Creating micromamba env '${HEADROOM_ENV}' (python 3.12)…"
            "${MAMBA_CMD[@]}" create -n "$HEADROOM_ENV" python=3.12 -y -c conda-forge
        fi

        local py_version
        py_version="$(mamba_run python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
        case "$py_version" in
            3.10|3.11|3.12|3.13) ;;
            *) die "env '${HEADROOM_ENV}' has Python ${py_version}; Headroom needs 3.10–3.13 (not 3.14+)" ;;
        esac

        say "Installing ${HEADROOM_PACKAGE} in micromamba env '${HEADROOM_ENV}'…"
        mamba_run python -m pip install -U "$HEADROOM_PACKAGE"
    elif ! mamba_env_exists; then
        die "micromamba env '${HEADROOM_ENV}' not found (run without --skip-install)"
    fi

    HEADROOM_BIN="$("${MAMBA_CMD[@]}" run -n "$HEADROOM_ENV" which headroom)"
}

install_with_pip() {
    local py
    py="$(find_compatible_python)" || die "no compatible Python found (need 3.10–3.13; set --python explicitly)"

    if ! $SKIP_INSTALL; then
        say "Installing ${HEADROOM_PACKAGE} with ${py} -m pip install --user…"
        "$py" -m pip install --user -U "$HEADROOM_PACKAGE"
    fi

    ensure_user_local_bin "$py"
    HEADROOM_BIN="$(command -v headroom || true)"
    if [[ -z "$HEADROOM_BIN" && -x "$HOME/.local/bin/headroom" ]]; then
        HEADROOM_BIN="$HOME/.local/bin/headroom"
    fi
}

install_with_pipx() {
    local py
    command -v pipx >/dev/null 2>&1 || die "pipx not found (install: brew install pipx, or use --installer pip)"
    py="$(find_compatible_python)" || die "no compatible Python found for pipx (need 3.10–3.13)"

    if ! $SKIP_INSTALL; then
        say "Installing ${HEADROOM_PACKAGE} with pipx (python: ${py})…"
        if pipx list 2>/dev/null | grep -q 'package headroom-ai'; then
            pipx upgrade --python "$py" headroom-ai || pipx install --python "$py" --force "$HEADROOM_PACKAGE"
        else
            pipx install --python "$py" "$HEADROOM_PACKAGE"
        fi
    fi

    ensure_user_local_bin "$py"
    HEADROOM_BIN="$(pipx environment --executable headroom 2>/dev/null || true)"
    if [[ -z "$HEADROOM_BIN" || ! -x "$HEADROOM_BIN" ]]; then
        HEADROOM_BIN="$(command -v headroom || true)"
    fi
    if [[ -z "$HEADROOM_BIN" && -x "$HOME/.local/bin/headroom" ]]; then
        HEADROOM_BIN="$HOME/.local/bin/headroom"
    fi
}

resolve_headroom_bin_from_config() {
    local config="$HOME/.config/headroom/setup.env"
    [[ -f "$config" ]] || return 1
    # shellcheck disable=SC1090
    source "$config"
    if [[ -n "${HEADROOM_BIN:-}" && -x "$HEADROOM_BIN" ]]; then
        INSTALLER_RESOLVED="${INSTALLER:-}"
        return 0
    fi
    return 1
}

locate_headroom_bin() {
    if resolve_headroom_bin_from_config; then
        return 0
    fi

    if find_micromamba && mamba_env_exists; then
        INSTALLER_RESOLVED=micromamba
        HEADROOM_BIN="$("${MAMBA_CMD[@]}" run -n "$HEADROOM_ENV" which headroom 2>/dev/null || true)"
        [[ -n "$HEADROOM_BIN" && -x "$HEADROOM_BIN" ]] && return 0
    fi

    if command -v pipx >/dev/null 2>&1; then
        HEADROOM_BIN="$(pipx environment --executable headroom 2>/dev/null || true)"
        if [[ -n "$HEADROOM_BIN" && -x "$HEADROOM_BIN" ]]; then
            INSTALLER_RESOLVED=pipx
            return 0
        fi
    fi

    local py
    if py="$(find_compatible_python 2>/dev/null)"; then
        ensure_user_local_bin "$py"
    else
        ensure_user_local_bin python3
    fi

    HEADROOM_BIN="$(command -v headroom || true)"
    if [[ -z "$HEADROOM_BIN" && -x "$HOME/.local/bin/headroom" ]]; then
        HEADROOM_BIN="$HOME/.local/bin/headroom"
    fi
    if [[ -n "$HEADROOM_BIN" && -x "$HEADROOM_BIN" ]]; then
        INSTALLER_RESOLVED=pip
        return 0
    fi

    return 1
}

resolve_headroom_bin() {
    if $CHECK_ONLY; then
        locate_headroom_bin || die "could not locate headroom (run setup without --check)"
        return 0
    fi

    if resolve_headroom_bin_from_config && $SKIP_INSTALL; then
        return 0
    fi

    if [[ "$INSTALLER" == auto ]]; then
        INSTALLER_RESOLVED="$(resolve_installer_auto)" || die "no installer available (need micromamba, pipx, or Python 3.10–3.13 + pip)"
        say "Auto-selected installer: ${INSTALLER_RESOLVED}"
    else
        INSTALLER_RESOLVED="$INSTALLER"
    fi

    case "$INSTALLER_RESOLVED" in
        micromamba) install_with_micromamba ;;
        pip)        install_with_pip ;;
        pipx)       install_with_pipx ;;
        *)          die "internal error: unknown installer '${INSTALLER_RESOLVED}'" ;;
    esac

    [[ -n "$HEADROOM_BIN" && -x "$HEADROOM_BIN" ]] || die "headroom binary not found after ${INSTALLER_RESOLVED} install"
}

run_headroom() {
    case "${INSTALLER_RESOLVED:-}" in
        micromamba) mamba_run "$HEADROOM_BIN" "$@" ;;
        *)          "$HEADROOM_BIN" "$@" ;;
    esac
}

proxy_healthy() {
    curl -sf "${PROXY_URL}/health" >/dev/null 2>&1
}

read_settings_base_url() {
    local settings="$HOME/.claude/settings.json"
    [[ -f "$settings" ]] || return 1
    python3 - "$settings" <<'PY' 2>/dev/null || return 1
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
env = data.get("env") or {}
print(env.get("ANTHROPIC_BASE_URL", ""))
PY
}

mcp_uses_absolute_headroom() {
    command -v claude >/dev/null 2>&1 || return 1
    claude mcp get headroom 2>/dev/null | grep -q "Command: /"
}

run_doctor() {
    if [[ -n "${HEADROOM_BIN:-}" ]]; then
        "$HEADROOM_BIN" doctor --port "$HEADROOM_PORT" || true
    fi
}

installer_summary() {
    case "${INSTALLER_RESOLVED:-unknown}" in
        micromamba) printf 'micromamba env %s\n  %s run -n %s headroom --version' "$HEADROOM_ENV" "${MAMBA_CMD[*]}" "$HEADROOM_ENV" ;;
        pip)        printf 'pip (--user)\n  %s' "$HEADROOM_BIN" ;;
        pipx)       printf 'pipx\n  %s' "$HEADROOM_BIN" ;;
        *)          printf '%s\n  %s' "${INSTALLER_RESOLVED:-unknown}" "$HEADROOM_BIN" ;;
    esac
}

print_next_steps() {
    cat <<EOF

Headroom CLI setup complete.

Daily use (recommended):
  claude-headroom                 # starts proxy + claude with compression
  claude-headroom -- --resume ID  # pass flags after --

Or, if the proxy is already running:
  claude                          # uses ~/.claude/settings.json routing

Verify:
  headroom doctor
  claude mcp list                 # headroom should be Connected
  open ${PROXY_URL}/dashboard     # token savings (after real API traffic)

Installer: $(installer_summary)

Note: Claude Desktop (the GUI app) does not route through Headroom in normal
subscription mode. Use this CLI setup for compressed coding sessions.

Stop / undo:
  pkill -f 'headroom proxy'       # stop the running proxy

  'headroom init claude -g' rewrote ~/.claude/settings.json to add
  ANTHROPIC_BASE_URL=${PROXY_URL}. This reroutes ALL \`claude\` CLI usage
  through the proxy (not just \`claude-headroom\`). If the proxy is down
  (or the machine rebooted) and settings.json still points at it, plain
  \`claude\` will fail with a connection-refused error until the setting
  is restored.

  headroom does not currently ship a documented 'init claude --undo' (or
  '--uninstall') flag — verified via 'headroom init claude --help' — so
  restore manually:
    1. Open ~/.claude/settings.json
    2. Remove the "ANTHROPIC_BASE_URL" entry under "env" (and any other
       headroom-added keys there)
    3. Optionally drop the MCP registration:
         claude mcp remove headroom -s user

  Check headroom's own docs/release notes for a future '--undo' flag
  before relying on the manual steps above.

EOF
}

# --- check-only mode ----------------------------------------------------------

if $CHECK_ONLY; then
    say "Checking Headroom + Claude CLI setup…"
    locate_headroom_bin || die "could not locate headroom (run setup without --check)"
    say "Using headroom at ${HEADROOM_BIN} (${INSTALLER_RESOLVED:-unknown})"
    command -v claude >/dev/null 2>&1 || warn "claude CLI not on PATH"

    settings_url="$(read_settings_base_url || true)"
    if [[ "$settings_url" == "$PROXY_URL" ]]; then
        say "settings.json routes to ${PROXY_URL}"
    else
        warn "settings.json ANTHROPIC_BASE_URL is '${settings_url:-<unset>}' (expected ${PROXY_URL})"
    fi

    if mcp_uses_absolute_headroom; then
        say "MCP headroom uses an absolute binary path"
    else
        warn "MCP headroom is missing or still uses bare 'headroom' on PATH"
    fi

    if proxy_healthy; then
        say "proxy is healthy at ${PROXY_URL}"
    else
        warn "proxy is not reachable at ${PROXY_URL}"
    fi

    launcher="$HOME/.local/bin/claude-headroom"
    if [[ -x "$launcher" ]]; then
        if grep -qF "$HEADROOM_BIN" "$launcher" 2>/dev/null; then
            say "launcher ${launcher} matches recorded HEADROOM_BIN"
        else
            warn "launcher ${launcher} does not reference ${HEADROOM_BIN} (stale? re-run setup)"
        fi
    else
        warn "launcher ${launcher} not found (run without --no-launcher to install it)"
    fi

    run_doctor
    exit 0
fi

# --- install / configure ------------------------------------------------------

resolve_headroom_bin

headroom_version="$("$HEADROOM_BIN" --version 2>/dev/null | awk '{print $NF}')"
say "Using headroom ${headroom_version} at ${HEADROOM_BIN} (${INSTALLER_RESOLVED})"

if ! command -v claude >/dev/null 2>&1; then
    die "claude CLI not found. Install Claude Code: https://code.claude.com"
fi

claude_version="$(claude --version 2>/dev/null | head -1 || true)"
say "Found ${claude_version:-claude CLI}"

say "Configuring Claude Code (headroom init claude -g)…"
run_headroom init claude -g --port "$HEADROOM_PORT"

say "Registering Headroom MCP with absolute binary path…"
if claude mcp get headroom >/dev/null 2>&1; then
    if mcp_uses_absolute_headroom; then
        say "MCP already uses an absolute path; refreshing registration…"
    else
        warn "Replacing MCP entry that used bare 'headroom' on PATH"
    fi
    claude mcp remove headroom -s user >/dev/null 2>&1 || true
fi
claude mcp add headroom -s user -- "$HEADROOM_BIN" mcp serve

mkdir -p "$HOME/.headroom/logs"

if ! proxy_healthy; then
    say "Starting Headroom proxy on port ${HEADROOM_PORT}…"
    nohup "$HEADROOM_BIN" proxy --port "$HEADROOM_PORT" --no-telemetry \
        >>"$HOME/.headroom/logs/proxy.log" 2>&1 &
    for _ in {1..15}; do
        proxy_healthy && break
        sleep 1
    done
    proxy_healthy || die "proxy failed to start; see ~/.headroom/logs/proxy.log"
else
    say "Proxy already healthy at ${PROXY_URL}"
fi

if $INSTALL_LAUNCHER; then
    launcher="$HOME/.local/bin/claude-headroom"
    mkdir -p "$(dirname "$launcher")"
    cat >"$launcher" <<EOF
#!/usr/bin/env bash
# Generated by Thaw scripts/setup-headroom-claude.sh — do not edit by hand.
set -euo pipefail
exec "$HEADROOM_BIN" wrap claude --port "$HEADROOM_PORT" --no-telemetry -- "\$@"
EOF
    chmod +x "$launcher"
    say "Installed launcher: ${launcher}"
fi

config_dir="$HOME/.config/headroom"
mkdir -p "$config_dir"
cat >"$config_dir/setup.env" <<EOF
# Generated by Thaw scripts/setup-headroom-claude.sh
INSTALLER=${INSTALLER_RESOLVED}
HEADROOM_ENV=${HEADROOM_ENV}
HEADROOM_BIN=${HEADROOM_BIN}
HEADROOM_PORT=${HEADROOM_PORT}
HEADROOM_PROXY_URL=${PROXY_URL}
EOF

say "Running headroom doctor…"
run_doctor

print_next_steps
