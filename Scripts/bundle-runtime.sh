#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/HermesAgent/Resources/runtime"
SERVER_DIR="$RUNTIME_DIR/server"
SOURCE_DIR="${HERMES_SOURCE_DIR:-/Users/artem/.hermes/hermes-agent}"
HERMES_VERSION="${HERMES_VERSION:-main}"

if [ ! -d "$SOURCE_DIR" ]; then
  echo "Hermes source directory not found: $SOURCE_DIR" >&2
  echo "Set HERMES_SOURCE_DIR to an extracted hermes-agent checkout." >&2
  exit 1
fi

mkdir -p "$RUNTIME_DIR/bin"
rm -rf "$SERVER_DIR"

rsync -a \
  --exclude '.git' \
  --exclude '.github' \
  --exclude '__pycache__' \
  --exclude '.pytest_cache' \
  --exclude 'venv' \
  --exclude '.venv' \
  --exclude 'node_modules' \
  --exclude 'web/node_modules' \
  --exclude 'website/node_modules' \
  "$SOURCE_DIR/" "$SERVER_DIR/"

if [ ! -x "$RUNTIME_DIR/bin/run-hermes-dashboard.sh" ]; then
  echo "Missing runtime runner: $RUNTIME_DIR/bin/run-hermes-dashboard.sh" >&2
  exit 1
fi

if [ ! -f "$SERVER_DIR/hermes_cli/web_dist/index.html" ]; then
  echo "Hermes web dashboard is missing: $SERVER_DIR/hermes_cli/web_dist/index.html" >&2
  exit 1
fi

cat > "$RUNTIME_DIR/version.json" <<JSON
{
  "version": "$HERMES_VERSION",
  "source": "$SOURCE_DIR",
  "runtime": "hermes-dashboard",
  "kind": "python"
}
JSON

echo "Hermes Agent runtime bundled in $RUNTIME_DIR"
