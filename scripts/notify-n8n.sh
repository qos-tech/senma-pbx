#!/usr/bin/env bash
#
# Hook de notificacao do ralph.sh para n8n.
#
# Obrigatorio:
#   RALPH_NOTIFY_WEBHOOK=https://n8n.exemplo.com/webhook/ralph-whatsapp
#
# Opcional:
#   RALPH_NOTIFY_TOKEN=segredo-compartilhado
#   RALPH_WHATSAPP_NUMBER=5541999999999
#
# O webhook recebe JSON. No n8n, use {{$json.message}} como texto da mensagem.

set -u

event="${1:-${RALPH_EVENT:-unknown}}"
message="${2:-${RALPH_MESSAGE:-Evento do Ralph}}"
webhook="${RALPH_NOTIFY_WEBHOOK:-}"

[ -n "$webhook" ] || exit 0

payload=$(python3 - "$event" "$message" <<'PY'
import json
import os
import sys


def env(name: str, default: str = "") -> str:
    return os.getenv(name, default)

print(json.dumps({
    "event": sys.argv[1],
    "message": sys.argv[2],
    "run_id": env("RALPH_RUN_ID"),
    "project": env("RALPH_PROJECT_NAME"),
    "engine": env("RALPH_ENGINE"),
    "phase": {
        "number": env("RALPH_PHASE_NUM"),
        "title": env("RALPH_PHASE_TITLE"),
        "total": env("RALPH_PHASE_TOTAL"),
        "attempt": env("RALPH_PHASE_ATTEMPT"),
        "max_attempts": env("RALPH_PHASE_MAX_ATTEMPTS"),
    },
    "whatsapp_number": env("RALPH_WHATSAPP_NUMBER"),
}, ensure_ascii=False))
PY
) || exit 0

curl_args=(
  --silent
  --show-error
  --fail-with-body
  --connect-timeout 5
  --max-time 15
  --retry 2
  --retry-delay 2
  --request POST
  --header "Content-Type: application/json"
  --data "$payload"
)

if [ -n "${RALPH_NOTIFY_TOKEN:-}" ]; then
  curl_args+=(--header "Authorization: Bearer ${RALPH_NOTIFY_TOKEN}")
fi

if curl "${curl_args[@]}" "$webhook" >/dev/null 2>&1; then
  exit 0
fi
[ "${QOS_NOTIFY_STRICT:-false}" = "true" ] && exit 1
exit 0
