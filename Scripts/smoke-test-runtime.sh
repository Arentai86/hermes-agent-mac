#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT_DIR/HermesAgent/Resources/runtime/bin/run-hermes-dashboard.sh"
PORT="${PORT:-$(ruby -rsocket -e 's = TCPServer.new("127.0.0.1", 0); puts s.addr[1]; s.close')}"
DATA_DIR="$(mktemp -d /tmp/hermes-agent-smoke.XXXXXX)"
LOG_FILE="$(mktemp /tmp/hermes-agent-smoke-log.XXXXXX)"

cleanup() {
  if [ -n "${PID:-}" ]; then
    kill "$PID" >/dev/null 2>&1 || true
    wait "$PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$DATA_DIR" "$LOG_FILE"
}
trap cleanup EXIT

"$RUNNER" --port "$PORT" --data-dir "$DATA_DIR" >"$LOG_FILE" 2>&1 &
PID=$!

for _ in {1..2400}; do
  if curl -fsS "http://127.0.0.1:$PORT/api/status" >/dev/null 2>&1; then
    echo "Hermes Agent runtime smoke test passed on 127.0.0.1:$PORT"
    exit 0
  fi
  if ! kill -0 "$PID" >/dev/null 2>&1; then
    echo "Hermes Agent runtime exited early" >&2
    cat "$LOG_FILE" >&2 || true
    exit 1
  fi
  sleep 0.25
done

echo "Hermes Agent runtime did not become healthy" >&2
cat "$LOG_FILE" >&2 || true
exit 1
