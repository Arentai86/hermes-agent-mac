#!/bin/bash
set -euo pipefail

PORT="9119"
DATA_DIR="${HOME}/Library/Application Support/Hermes Agent"
TOKEN_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --port)
      PORT="${2:?missing --port value}"
      shift 2
      ;;
    --data-dir)
      DATA_DIR="${2:?missing --data-dir value}"
      shift 2
      ;;
    --token-file)
      TOKEN_FILE="${2:?missing --token-file value}"
      shift 2
      ;;
    --token)
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVER_DIR="$RUNTIME_DIR/server"
USER_RUNTIME_DIR="$DATA_DIR/runtime"
TOOLS_DIR="$USER_RUNTIME_DIR/tools"
USER_VENV="$USER_RUNTIME_DIR/venv"
BOOTSTRAP_SERVER_DIR="$USER_RUNTIME_DIR/server-source"
ARCH="$(uname -m)"

mkdir -p "$DATA_DIR" "$USER_RUNTIME_DIR" "$TOOLS_DIR"
chmod 700 "$DATA_DIR" "$USER_RUNTIME_DIR" "$TOOLS_DIR" 2>/dev/null || true

export HERMES_HOME="$DATA_DIR"
export HERMES_WEB_DIST="${HERMES_WEB_DIST:-$SERVER_DIR/hermes_cli/web_dist}"
export PYTHONPATH="$SERVER_DIR${PYTHONPATH:+:$PYTHONPATH}"
export PATH="$TOOLS_DIR:$PATH"

if [ -n "$TOKEN_FILE" ] && [ ! -f "$TOKEN_FILE" ]; then
  umask 077
  printf '%s\n' "${HERMES_LAUNCHER_TOKEN:-}" > "$TOKEN_FILE"
fi

python_ok() {
  local python="$1"
  [ -x "$python" ] || return 1
  "$python" - <<'PY' >/dev/null 2>&1
import importlib.util
import platform
import sys
if sys.version_info < (3, 11):
    raise SystemExit(1)
if platform.machine() not in ("arm64", "x86_64"):
    raise SystemExit(1)
for name in ("fastapi", "uvicorn", "pydantic"):
    if importlib.util.find_spec(name) is None:
        raise SystemExit(1)
PY
}

python_version_ok() {
  local python="$1"
  [ -x "$python" ] || return 1
  "$python" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 11) else 1)
PY
}

writable_server_source() {
  if [ -f "$BOOTSTRAP_SERVER_DIR/pyproject.toml" ] && [ -f "$BOOTSTRAP_SERVER_DIR/hermes_cli/web_dist/index.html" ]; then
    printf '%s\n' "$BOOTSTRAP_SERVER_DIR"
    return 0
  fi
  rm -rf "$BOOTSTRAP_SERVER_DIR"
  mkdir -p "$BOOTSTRAP_SERVER_DIR"
  /usr/bin/ditto "$SERVER_DIR" "$BOOTSTRAP_SERVER_DIR"
  printf '%s\n' "$BOOTSTRAP_SERVER_DIR"
}

find_python() {
  local candidates=(
    "$SERVER_DIR/venv/bin/python"
    "$USER_VENV/bin/python"
    "/opt/homebrew/bin/python3"
    "/usr/local/bin/python3"
    "/Library/Frameworks/Python.framework/Versions/Current/bin/python3"
    "$(command -v python3 2>/dev/null || true)"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if python_ok "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

bootstrap_with_pip() {
  local seed_python="$1"
  local source_dir
  python_version_ok "$seed_python" || return 1
  rm -rf "$USER_VENV"
  source_dir="$(writable_server_source)"
  "$seed_python" -m venv "$USER_VENV"
  "$USER_VENV/bin/python" -m pip install --upgrade pip wheel setuptools
  "$USER_VENV/bin/python" -m pip install -e "$source_dir[web,pty]"
  python_ok "$USER_VENV/bin/python"
}

bootstrap_uv() {
  local uv_bin="$TOOLS_DIR/uv"
  if [ ! -x "$uv_bin" ]; then
    if command -v uv >/dev/null 2>&1; then
      uv_bin="$(command -v uv)"
    else
      UV_INSTALL_DIR="$TOOLS_DIR" INSTALLER_NO_MODIFY_PATH=1 sh -c "$(curl -LsSf https://astral.sh/uv/install.sh)"
      uv_bin="$TOOLS_DIR/uv"
    fi
  fi
  [ -x "$uv_bin" ] || return 1
  rm -rf "$USER_VENV"
  local source_dir
  source_dir="$(writable_server_source)"
  cd "$source_dir"
  "$uv_bin" venv --python 3.12 "$USER_VENV"
  "$uv_bin" pip install --python "$USER_VENV/bin/python" -e "$source_dir[web,pty]"
  python_ok "$USER_VENV/bin/python"
}

PYTHON="$(find_python || true)"

if [ -z "$PYTHON" ]; then
  for seed in "/opt/homebrew/bin/python3" "/usr/local/bin/python3" "/Library/Frameworks/Python.framework/Versions/Current/bin/python3" "$(command -v python3 2>/dev/null || true)"; do
    if bootstrap_with_pip "$seed"; then
      PYTHON="$USER_VENV/bin/python"
      break
    fi
  done
fi

if [ -z "${PYTHON:-}" ]; then
  if bootstrap_uv; then
    PYTHON="$USER_VENV/bin/python"
  fi
fi

if [ -z "${PYTHON:-}" ]; then
  echo "Hermes Agent requires Python 3.11+ or network access to bootstrap a managed runtime." >&2
  echo "Install Python from python.org, Homebrew, or allow the launcher to download uv/Python on first run." >&2
  exit 127
fi

exec "$PYTHON" "$SERVER_DIR/hermes" dashboard \
  --host 127.0.0.1 \
  --port "$PORT" \
  --no-open \
  --skip-build \
  --tui
