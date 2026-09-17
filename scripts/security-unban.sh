#!/usr/bin/env bash
# TASK-0035E10 — safe Fail2ban unban helper for `make security-unban`.
#
# The address MUST arrive via the Make command-line variable `IP`, which
# GNU Make exports into the recipe environment without shell-parsing its
# value into the recipe text. This script therefore reads os.environ["IP"]
# (via the shell's inherited environment) and NEVER interpolates an
# untrusted Make $(IP) into an unquoted shell word.
#
# Rejects anything that is not a literal IPv4/IPv6 address (blocks
# `1.2.3.4;id`, `$(id)`, backticks, pipes, etc.).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

COMPOSE="${COMPOSE:-docker compose}"
COMPOSE_FILES="${COMPOSE_FILES:--f compose.yaml}"
FIXTURE_PROFILE="${FIXTURE_PROFILE:-${COMPOSE_PROFILES:-}}"

# Inherited from `make security-unban IP=...` (Make exports cmdline vars).
CANDIDATE="${IP:-}"
if [ -z "$CANDIDATE" ]; then
  echo "Usage: make security-unban IP=x.x.x.x" >&2
  exit 1
fi

if ! python3 -c 'import ipaddress,sys; ipaddress.ip_address(sys.argv[1])' "$CANDIDATE" 2>/dev/null; then
  echo "ERROR: IP must be a valid literal IPv4 or IPv6 address" >&2
  exit 1
fi

cid="$(COMPOSE_PROFILES="$FIXTURE_PROFILE" $COMPOSE $COMPOSE_FILES ps -q senma-security 2>/dev/null || true)"
if [ -z "$cid" ]; then
  echo "ERROR: senma-security is not running" >&2
  exit 1
fi

# Quoted "$CANDIDATE" is a single argv after validation — no eval.
docker exec "$cid" fail2ban-client set senma-sip-auth unbanip "$CANDIDATE" || true
docker exec "$cid" fail2ban-client set senma-sip-scanner unbanip "$CANDIDATE" || true
echo "unban requested for $CANDIDATE on senma-sip-auth and senma-sip-scanner"
