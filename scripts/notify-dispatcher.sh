#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
event="${1:-${RALPH_EVENT:-unknown}}"
message="${2:-${RALPH_MESSAGE:-Evento do Ralph}}"
provider="${RALPH_NOTIFY_PROVIDER:-n8n}"
fallback="${RALPH_NOTIFY_FALLBACK_PROVIDER:-}"

run_provider() {
  case "$1" in
    n8n) "$SCRIPT_DIR/notify-n8n.sh" "$event" "$message" ;;
    evolution) "$SCRIPT_DIR/notify-evolution.sh" "$event" "$message" ;;
    none|"") return 0 ;;
    *) return 2 ;;
  esac
}

if run_provider "$provider"; then
  exit 0
fi

if [ -n "$fallback" ] && [ "$fallback" != "$provider" ]; then
  run_provider "$fallback" && exit 0
fi

# Notifications are best-effort during Ralph runs, strict in explicit tests.
[ "${QOS_NOTIFY_STRICT:-false}" = "true" ] && exit 1
exit 0
