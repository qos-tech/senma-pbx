#!/usr/bin/env bash
set -u

event="${1:-${RALPH_EVENT:-unknown}}"
message="${2:-${RALPH_MESSAGE:-Evento do Ralph}}"
base_url="${RALPH_EVOLUTION_BASE_URL:-}"
instance="${RALPH_EVOLUTION_INSTANCE:-}"
api_key="${RALPH_EVOLUTION_API_KEY:-}"
number="${RALPH_WHATSAPP_NUMBER:-${RALPH_EVOLUTION_NUMBER:-}}"
payload_format="${RALPH_EVOLUTION_PAYLOAD_FORMAT:-text}"

[ -n "$base_url" ] || exit 1
[ -n "$instance" ] || exit 1
[ -n "$api_key" ] || exit 1
[ -n "$number" ] || exit 1

payload=$(python3 - "$event" "$message" "$payload_format" <<'PY'
import json, os, sys
fmt=sys.argv[3]
body={"number": os.getenv("RALPH_WHATSAPP_NUMBER") or os.getenv("RALPH_EVOLUTION_NUMBER", "")}
if fmt == "text_message":
    body["textMessage"]={"text": sys.argv[2]}
else:
    body["text"]=sys.argv[2]
print(json.dumps(body, ensure_ascii=False))
PY
) || exit 1

url="${base_url%/}/message/sendText/${instance}"
curl --silent --show-error --fail-with-body \
  --connect-timeout 5 --max-time 15 --retry 2 --retry-delay 2 \
  --request POST \
  --header "Content-Type: application/json" \
  --header "apikey: ${api_key}" \
  --data "$payload" \
  "$url" >/dev/null 2>&1
