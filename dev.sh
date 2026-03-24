#!/usr/bin/env bash
# dev.sh — start/stop/restart/status CoPaw from source
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SCRIPT_DIR/.venv"
PID_FILE="$SCRIPT_DIR/.copaw.pid"
LOG_FILE="$SCRIPT_DIR/.copaw.log"

_activate() {
  if [[ ! -f "$VENV/bin/activate" ]]; then
    echo "ERROR: virtualenv not found at $VENV" >&2
    echo "       Run: python -m venv .venv && source .venv/bin/activate && pip install -e ." >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  source "$VENV/bin/activate"
}

_build_console() {
  echo ">>> Building frontend console..."
  npm ci --prefix "$SCRIPT_DIR/console" --silent
  npm run build --prefix "$SCRIPT_DIR/console"
  mkdir -p "$SCRIPT_DIR/src/copaw/console"
  cp -R "$SCRIPT_DIR/console/dist/." "$SCRIPT_DIR/src/copaw/console/"
  echo ">>> Frontend built."
}

cmd_start() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "CoPaw is already running (PID $(cat "$PID_FILE"))."
    exit 0
  fi

  _activate

  if [[ "${1:-}" == "--build" ]]; then
    _build_console
  fi

  echo ">>> Starting CoPaw..."
  export ENABLE_TRUNCATE_TOOL_RESULT_TEXTS=true
  export COPAW_MEMORY_COMPACT_RATIO=0.5
  nohup env ENABLE_TRUNCATE_TOOL_RESULT_TEXTS=true COPAW_MEMORY_COMPACT_RATIO=0.5 copaw app > "$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  sleep 2

  if kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "CoPaw started (PID $(cat "$PID_FILE"))."
    echo "Console: http://127.0.0.1:8088"
    echo "Log:     $LOG_FILE"
  else
    echo "ERROR: CoPaw failed to start. Check $LOG_FILE" >&2
    rm -f "$PID_FILE"
    exit 1
  fi
}

cmd_stop() {
  if [[ ! -f "$PID_FILE" ]]; then
    echo "CoPaw is not running (no PID file)."
    return
  fi

  PID="$(cat "$PID_FILE")"
  if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    rm -f "$PID_FILE"
    echo "CoPaw stopped (PID $PID)."
  else
    echo "CoPaw was not running (stale PID $PID)."
    rm -f "$PID_FILE"
  fi
}

cmd_restart() {
  cmd_stop
  sleep 1
  cmd_start "${@:-}"
}

cmd_status() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "CoPaw is running (PID $(cat "$PID_FILE"))."
    echo "Console: http://127.0.0.1:8088"
  else
    echo "CoPaw is not running."
  fi
}

cmd_logs() {
  if [[ -f "$LOG_FILE" ]]; then
    tail -f "$LOG_FILE"
  else
    echo "No log file found at $LOG_FILE"
  fi
}

usage() {
  echo "Usage: $0 {start|stop|restart|status|logs} [--build]"
  echo ""
  echo "  start [--build]   Start CoPaw (--build rebuilds the frontend first)"
  echo "  stop              Stop CoPaw"
  echo "  restart [--build] Restart CoPaw"
  echo "  status            Show running status"
  echo "  logs              Tail the log file"
}

case "${1:-}" in
  start)   shift; cmd_start "$@" ;;
  stop)    cmd_stop ;;
  restart) shift; cmd_restart "$@" ;;
  status)  cmd_status ;;
  logs)    cmd_logs ;;
  *)       usage; exit 1 ;;
esac
