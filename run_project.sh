#!/usr/bin/env bash
set -euo pipefail

MIN_PYTHON_MAJOR=3
MIN_PYTHON_MINOR=10
DEFAULT_UV_PYTHON=3.12

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
VENV_DIR="${VENV_DIR:-.venv}"
INSTALL_PYTHON="${INSTALL_PYTHON:-1}"
UV_CACHE_DIR="${UV_CACHE_DIR:-/tmp/repo-summarizer-uv-cache}"
export UV_CACHE_DIR

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

log() {
    printf '[run_project] %s\n' "$*" >&2
}

warn() {
    printf '[run_project] WARNING: %s\n' "$*" >&2
}

die() {
    printf '[run_project] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage: ./run_project.sh [options]

Creates a Python 3.10+ virtual environment, installs dependencies, prepares .env,
and starts the FastAPI server.

Options:
  --host HOST       Bind host. Default: 0.0.0.0
  --port PORT       Bind port. Default: 8000
  --no-install      Do not attempt to install Python if Python 3.10+ is missing
  -h, --help        Show this help

Environment variables:
  HOST              Same as --host
  PORT              Same as --port
  VENV_DIR          Virtual environment directory. Default: .venv
  INSTALL_PYTHON    Set to 0 to disable automatic Python installation
  RELOAD            Set to 1 to start uvicorn with --reload
  PYTHON            Preferred Python executable or absolute path
USAGE
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --host)
            [ "$#" -ge 2 ] || die "--host requires a value"
            HOST="$2"
            shift 2
            ;;
        --port)
            [ "$#" -ge 2 ] || die "--port requires a value"
            PORT="$2"
            shift 2
            ;;
        --no-install)
            INSTALL_PYTHON=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

python_is_compatible() {
    "$1" - <<PYTHON_CHECK
import sys
raise SystemExit(
    0
    if sys.version_info >= ($MIN_PYTHON_MAJOR, $MIN_PYTHON_MINOR)
    else 1
)
PYTHON_CHECK
}

python_version() {
    "$1" - <<'PYTHON_VERSION'
import sys
print(".".join(map(str, sys.version_info[:3])))
PYTHON_VERSION
}

find_compatible_python() {
    local candidate resolved version_path
    local candidates=()

    if [ -n "${PYTHON:-}" ]; then
        candidates+=("$PYTHON")
    fi

    candidates+=(python3.13 python3.12 python3.11 python3.10 python3 python)

    for candidate in "${candidates[@]}"; do
        if ! resolved="$(command -v "$candidate" 2>/dev/null)"; then
            continue
        fi
        if python_is_compatible "$resolved"; then
            printf '%s\n' "$resolved"
            return 0
        fi
    done

    if command -v uv >/dev/null 2>&1; then
        for candidate in 3.13 3.12 3.11 3.10; do
            version_path="$(uv python find "$candidate" 2>/dev/null || true)"
            if [ -n "$version_path" ] && python_is_compatible "$version_path"; then
                printf '%s\n' "$version_path"
                return 0
            fi
        done
    fi

    return 1
}

run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        die "This installer needs root privileges, but sudo is not available."
    fi
}

install_python() {
    if [ "$INSTALL_PYTHON" = "0" ]; then
        die "Python 3.10+ was not found and automatic installation is disabled."
    fi

    log "Python 3.10+ was not found. Attempting to install it."

    if command -v uv >/dev/null 2>&1; then
        log "Installing Python $DEFAULT_UV_PYTHON with uv."
        if uv python install "$DEFAULT_UV_PYTHON"; then
            return 0
        fi
        warn "uv could not install Python. Trying system package managers."
    fi

    case "$(uname -s)" in
        Darwin)
            if command -v brew >/dev/null 2>&1; then
                log "Installing Python with Homebrew."
                brew install python
                return 0
            fi
            die "Homebrew is not installed. Install Python 3.10+ or Homebrew, then rerun this script."
            ;;
        Linux)
            if command -v apt-get >/dev/null 2>&1; then
                log "Installing Python with apt-get."
                run_as_root apt-get update
                run_as_root apt-get install -y python3 python3-venv python3-pip
                return 0
            fi
            if command -v dnf >/dev/null 2>&1; then
                log "Installing Python with dnf."
                run_as_root dnf install -y python3 python3-pip
                return 0
            fi
            if command -v yum >/dev/null 2>&1; then
                log "Installing Python with yum."
                run_as_root yum install -y python3 python3-pip
                return 0
            fi
            if command -v pacman >/dev/null 2>&1; then
                log "Installing Python with pacman."
                run_as_root pacman -Sy --noconfirm python python-pip
                return 0
            fi
            die "No supported Python installer found. Install Python 3.10+ manually, then rerun this script."
            ;;
        *)
            die "Unsupported OS. Install Python 3.10+ manually, then rerun this script."
            ;;
    esac
}

ensure_python() {
    local python_bin

    if python_bin="$(find_compatible_python)"; then
        printf '%s\n' "$python_bin"
        return 0
    fi

    install_python

    if python_bin="$(find_compatible_python)"; then
        printf '%s\n' "$python_bin"
        return 0
    fi

    die "Python installation finished, but Python 3.10+ is still not available on PATH."
}

ensure_venv() {
    local python_bin="$1"

    if [ -x "$VENV_DIR/bin/python" ]; then
        if python_is_compatible "$VENV_DIR/bin/python"; then
            log "Using existing virtual environment at $VENV_DIR with Python $(python_version "$VENV_DIR/bin/python")."
            return 0
        fi

        warn "Existing $VENV_DIR uses Python $(python_version "$VENV_DIR/bin/python"); recreating it with Python 3.10+."
        rm -rf "$VENV_DIR"
    fi

    log "Creating virtual environment at $VENV_DIR with Python $(python_version "$python_bin")."
    "$python_bin" -m venv "$VENV_DIR"
}

prepare_env_file() {
    if [ -f ".env" ]; then
        return 0
    fi

    if [ -f "env.template" ]; then
        cp env.template .env
        warn "Created .env from env.template. Add OPENAI_API_KEY or NEBIUS_API_KEY before calling /summarize."
        return 0
    fi

    warn "env.template is missing, so .env was not created."
}

install_dependencies() {
    log "Installing Python dependencies from requirements.txt."
    "$VENV_DIR/bin/python" -m pip install -r requirements.txt
}

start_server() {
    local uvicorn_args=(app.main:app --host "$HOST" --port "$PORT")

    if [ "${RELOAD:-0}" = "1" ]; then
        uvicorn_args+=(--reload)
    fi

    log "Starting API server at http://$HOST:$PORT"
    log "Local health check URL: http://127.0.0.1:$PORT/health"
    exec "$VENV_DIR/bin/python" -m uvicorn "${uvicorn_args[@]}"
}

[ -f "requirements.txt" ] || die "requirements.txt was not found in $PROJECT_ROOT."

PYTHON_BIN="$(ensure_python)"
log "Using Python $(python_version "$PYTHON_BIN") at $PYTHON_BIN."
ensure_venv "$PYTHON_BIN"
install_dependencies
prepare_env_file
start_server
