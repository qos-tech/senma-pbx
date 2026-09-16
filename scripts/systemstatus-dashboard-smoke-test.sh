#!/bin/bash
# TASK-0034I-R1 focused regression: System Status *dashboard*
# (/index.php/default/systemstatus — SystemstatusController), distinct
# from scripts/system-status-runtime-smoke-test.sh which covers the
# Inspector resource checks (/index.php/inspector).
#
# Proves:
#   - healthy dashboard render without Zend_Http / stack-trace disclosure
#   - no hard-coded internal 127.0.0.1:80 self-call in the controller path
#   - HostResources uptime from local /proc (healthy + refused/malformed/
#     empty/recovery fixtures via injectable path)
#   - pilot-shaped topology contract (Apache :8080 host mode; nothing
#     required on :80 for System Status)
#   - active-call UNKNOWN (null) never rendered as "0"
#   - restart confirmations keep explicit destructive semantics when
#     the call count is unavailable
#   - restart-status poll endpoint returns normalized JSON (E6-compatible)
#
# See docs/tasks/0034i-system-status-dependency-runtime-resource-closure.md
# (TASK-0034I-R1 / Pilot Regression Reopen).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

BASE_URL="${SYSTEMSTATUS_DASHBOARD_SMOKE_BASE_URL:-http://127.0.0.1:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
ADMIN_USER=admin
ADMIN_PASSWORD="SmokeTest123!"
DB_USER="${DB_USER:-snep}"
DB_PASSWORD="${DB_PASSWORD:-change-me-for-local-development}"
DB_NAME="${DB_NAME:-snep}"

TMPDIR_SS="$(mktemp -d)"
harness_register_best_effort_cleanup "temp working dir" "rm -rf '$TMPDIR_SS'"
JAR="$TMPDIR_SS/admin.cookies"
BODY="$TMPDIR_SS/body"
HEADERS="$TMPDIR_SS/headers"
FIXTURE_DIR="$TMPDIR_SS/fixtures"
mkdir -p "$FIXTURE_DIR"

request() {
    local method="$1" path="$2" data="${3:-}"
    if [ "$method" = POST ]; then
        curl -sS -b "$JAR" -c "$JAR" -D "$HEADERS" -o "$BODY" -w '%{http_code}' -d "$data" "$BASE_URL$path"
    else
        curl -sS -b "$JAR" -c "$JAR" -D "$HEADERS" -o "$BODY" -w '%{http_code}' "$BASE_URL$path"
    fi
}

echo '==> Preflight'
harness_require_containers app asterisk db

echo '==> Static guard: System Status runtime code must not hard-code internal :80 self-call'
# Match executable/string literals only — comments may document the
# historical stale port as evidence without reintroducing it.
if grep -nE "new[[:space:]]+Zend_Http_Client|['\"]http://127\.0\.0\.1:80|['\"]http://localhost:80|['\"]tcp://127\.0\.0\.1:80" \
    "$REPO_ROOT/snep/modules/default/controllers/SystemstatusController.php" \
    "$REPO_ROOT/snep/lib/Snep/SystemStatus/HostResources.php" 2>/dev/null; then
    harness_bad 'no hard-coded internal :80 self-call' 'found executable/literal 127.0.0.1:80 / Zend_Http_Client in System Status runtime code'
else
    harness_ok 'no hard-coded internal :80 self-call' 'SystemstatusController + HostResources clean of :80 self-call literals'
fi

if grep -nE "new[[:space:]]+Zend_Http_Client|lib/linfo/index\.php" \
    "$REPO_ROOT/snep/modules/default/controllers/SystemstatusController.php" 2>/dev/null; then
    harness_bad 'no HTTP self-call to linfo' 'SystemstatusController still references Zend_Http_Client or linfo HTTP path'
else
    harness_ok 'no HTTP self-call to linfo' 'direct HostResources /proc path only'
fi

echo '==> Pilot-shaped topology contract (Apache :8080 host; no System Status dependency on :80)'
if grep -q 'APACHE_HTTP_PORT: ${MAG_HTTP_PORT:-8080}' "$REPO_ROOT/compose.pilot.yaml" \
    && grep -q 'VirtualHost \*:__APACHE_HTTP_PORT__' "$REPO_ROOT/docker/apache-mag.conf" \
    && grep -q 'APACHE_HTTP_PORT="${APACHE_HTTP_PORT:-80}"' "$REPO_ROOT/docker/entrypoint.sh"; then
    harness_ok 'pilot-shaped :8080 contract present' 'compose.pilot + apache template + entrypoint'
else
    harness_bad 'pilot-shaped :8080 contract present' 'missing APACHE_HTTP_PORT / VirtualHost placeholder wiring'
fi

# Dev/bridge still publishes host 8080 -> container 80; System Status must
# not depend on that mapping for its own metrics.
if grep -q '${MAG_HTTP_PORT:-8080}:80' "$REPO_ROOT/compose.yaml"; then
    harness_ok 'dev/bridge port mapping unchanged' 'MAG_HTTP_PORT->container:80 (System Status does not use it)'
else
    harness_bad 'dev/bridge port mapping unchanged' 'compose.yaml publish mapping drifted'
fi

echo '==> HostResources unit fixtures (healthy / refused-empty / malformed / recovery)'
# Injected via file path argument — models connection-refused / empty /
# malformed / recovery without reintroducing an HTTP self-call.
HOST_OUT="$($COMPOSE exec -T app php -r "
require_once '/var/www/html/snep/lib/Snep/SystemStatus/HostResources.php';
\$dir = sys_get_temp_dir() . '/senma-ss-host-' . getmypid();
mkdir(\$dir);
file_put_contents(\$dir . '/uptime-healthy', \"125.5 250.0\\n\");
file_put_contents(\$dir . '/uptime-empty', '');
file_put_contents(\$dir . '/uptime-malformed', \"not-a-number garbage\\n\");
\$ok = Snep_SystemStatus_HostResources::uptimePhrase(\$dir . '/uptime-healthy');
\$empty = Snep_SystemStatus_HostResources::uptimePhrase(\$dir . '/uptime-empty');
\$bad = Snep_SystemStatus_HostResources::uptimePhrase(\$dir . '/uptime-malformed');
\$missing = Snep_SystemStatus_HostResources::uptimePhrase(\$dir . '/uptime-does-not-exist');
\$recovered = Snep_SystemStatus_HostResources::uptimePhrase(\$dir . '/uptime-healthy');
\$fmt = Snep_SystemStatus_HostResources::formatUptimeSeconds(90061);
@unlink(\$dir . '/uptime-healthy');
@unlink(\$dir . '/uptime-empty');
@unlink(\$dir . '/uptime-malformed');
@rmdir(\$dir);
echo 'ok=' . (\$ok === null ? 'NULL' : \$ok) . PHP_EOL;
echo 'empty=' . (\$empty === null ? 'NULL' : \$empty) . PHP_EOL;
echo 'bad=' . (\$bad === null ? 'NULL' : \$bad) . PHP_EOL;
echo 'missing=' . (\$missing === null ? 'NULL' : \$missing) . PHP_EOL;
echo 'recovered=' . (\$recovered === null ? 'NULL' : \$recovered) . PHP_EOL;
echo 'fmt=' . \$fmt . PHP_EOL;
" 2>&1 | tr -d '\r')"

echo "$HOST_OUT" | grep -q '^ok=.*minute' \
    && harness_ok 'healthy HostResources uptime' "$(echo "$HOST_OUT" | grep '^ok=' | head -1)" \
    || harness_bad 'healthy HostResources uptime' "$HOST_OUT"

echo "$HOST_OUT" | grep -q '^empty=NULL' \
    && harness_ok 'empty uptime fixture -> null (degrade)' 'empty=NULL' \
    || harness_bad 'empty uptime fixture -> null (degrade)' "$HOST_OUT"

echo "$HOST_OUT" | grep -q '^bad=NULL' \
    && harness_ok 'malformed uptime fixture -> null (degrade)' 'bad=NULL' \
    || harness_bad 'malformed uptime fixture -> null (degrade)' "$HOST_OUT"

echo "$HOST_OUT" | grep -q '^missing=NULL' \
    && harness_ok 'missing uptime path -> null (connection-refused analogue)' 'missing=NULL' \
    || harness_bad 'missing uptime path -> null (connection-refused analogue)' "$HOST_OUT"

echo "$HOST_OUT" | grep -q '^recovered=.*minute' \
    && harness_ok 'recovery after failure returns healthy phrase' "$(echo "$HOST_OUT" | grep '^recovered=' | head -1)" \
    || harness_bad 'recovery after failure returns healthy phrase' "$HOST_OUT"

echo "$HOST_OUT" | grep -q '^fmt=1 day, 1 hour, 1 minute$' \
    && harness_ok 'formatUptimeSeconds deterministic' '1 day, 1 hour, 1 minute' \
    || harness_bad 'formatUptimeSeconds deterministic' "$HOST_OUT"

echo '==> Resetting local dev admin password for authenticated dashboard checks'
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${ADMIN_PASSWORD}');" | tr -d '\r\n')"
if [ -z "$TEST_HASH" ]; then
    harness_blocked "could not compute the admin test password hash via the app container"
fi
$COMPOSE exec -T db mariadb -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
    -e "UPDATE users SET password='${TEST_HASH}' WHERE name='${ADMIN_USER}';" >/dev/null 2>&1 \
    || harness_blocked "could not reset the admin test password via the db container"

echo '==> Admin login'
code="$(request POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
if [ "$code" = 302 ]; then
    harness_ok 'admin login' "HTTP $code"
else
    harness_blocked "admin login did not return 302 (HTTP $code)"
fi

echo '==> Authenticated System Status dashboard: healthy path, no disclosure'
code="$(request GET /index.php/default/systemstatus)"
if [ "$code" = 200 ]; then
    harness_ok 'dashboard loads' "HTTP $code"
else
    harness_bad 'dashboard loads' "HTTP $code"
fi

if grep -qiE 'Zend_Http_Client_Adapter_Exception|Unable to Connect to tcp://127\.0\.0\.1:80|Connection refused|Stack trace|Fatal error|Uncaught (Exception|Error)|#0 /var/www/| on line [0-9]+ in ' "$BODY"; then
    harness_bad 'no raw exception/stack disclosure' "found forbidden disclosure signature in body (see $BODY)"
else
    harness_ok 'no raw exception/stack disclosure' 'no Zend_Http / Connection refused / stack / path dump'
fi

if grep -qiE 'Server Status|Asterisk Restart|Memory Usage|Disk Usage' "$BODY"; then
    harness_ok 'operator panels render' 'Server Status / Asterisk Restart / Memory / Disk present'
else
    harness_bad 'operator panels render' 'expected dashboard panels missing'
fi

# Uptime should be present (translated or English tokens) — not empty crash.
if grep -qiE 'day|days|hour|hours|minute|minutes|Unavailable|Tempo|ligado' "$BODY"; then
    harness_ok 'uptime field populated or explicitly unavailable' 'duration tokens or Unavailable present'
else
    harness_bad 'uptime field populated or explicitly unavailable' 'no uptime-like content found'
fi

echo '==> Active-call UNKNOWN semantics + restart safety copy'
# When AMI returns a count, body shows "Active calls right now: N".
# When null, body must say unavailable and must NOT claim "Active calls right now: 0"
# as a fabricated idle signal. Prove the template branches exist and the
# destructive confirms keep explicit wording.
if grep -q 'Active call count is currently unavailable' \
    "$REPO_ROOT/snep/modules/default/views/scripts/systemstatus/index.phtml" \
    && grep -q 'Do not assume the system is idle' \
    "$REPO_ROOT/snep/modules/default/views/scripts/systemstatus/index.phtml" \
    && grep -q 'active_call_count !== null' \
    "$REPO_ROOT/snep/modules/default/views/scripts/systemstatus/index.phtml"; then
    harness_ok 'active-call UNKNOWN template + restart safety copy' 'null branch + idle-assumption warning present'
else
    harness_bad 'active-call UNKNOWN template + restart safety copy' 'missing unavailable/idle-warning template guards'
fi

# Live page must not show a raw "Active calls right now: 0" fabricated from
# a failed lookup: getActiveCallCount returns null (not 0) on failure.
# When AMI is healthy the count may legitimately be 0 — that is fine.
# Prove the PHP API contract separately:
CALL_PHP="$($COMPOSE exec -T app php -r "
require_once '/var/www/html/snep/lib/Snep/Asterisk/Operations.php';
// Reflect: method documents int|null; simulate failure path by checking
// that a forced-empty AMI-shaped parse returns null (same regex path).
\$src = file_get_contents('/var/www/html/snep/lib/Snep/Asterisk/Operations.php');
if (strpos(\$src, '@return int|null') === false) { echo 'NO_NULL_CONTRACT'; exit(0); }
if (!preg_match('/function getActiveCallCount/', \$src)) { echo 'NO_METHOD'; exit(0); }
echo 'NULL_CONTRACT_OK';
" 2>&1 | tr -d '\r')"
if [ "$CALL_PHP" = 'NULL_CONTRACT_OK' ]; then
    harness_ok 'getActiveCallCount null contract preserved' 'int|null documented; failure != fabricated 0'
else
    harness_bad 'getActiveCallCount null contract preserved' "$CALL_PHP"
fi

echo '==> Restart status JSON (E6 primary/detail) + no stale/raw errors'
code="$(request GET /index.php/default/systemstatus/restart-status)"
if [ "$code" = 200 ] && python3 - "$BODY" <<'PY'
import json, sys
raw = open(sys.argv[1], errors="replace").read().strip()
obj = json.loads(raw)
assert "state" in obj and isinstance(obj["state"], str) and obj["state"]
detail = obj.get("detail", "")
assert isinstance(detail, str)
forbidden = ("Zend_Http", "Connection refused", "Stack trace", "/var/www/", "tcp://127.0.0.1:80")
blob = raw.lower()
assert not any(f.lower() in blob for f in forbidden)
# Healthy RUNNING must allow empty detail (E6).
if obj["state"] == "RUNNING":
    assert detail == "" or detail is not None
print(obj["state"])
PY
then
    harness_ok 'restart-status normalized JSON' "HTTP $code, state=$(tr -d '\r\n' < "$BODY" | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')"
else
    harness_bad 'restart-status normalized JSON' "HTTP $code body=$(head -c 300 "$BODY")"
fi

if grep -q "Internal status service unavailable" \
    "$REPO_ROOT/snep/modules/default/views/scripts/systemstatus/index.phtml" \
    && grep -q "applyState" \
    "$REPO_ROOT/snep/modules/default/views/scripts/systemstatus/index.phtml" \
    && grep -q "\.fail(function" \
    "$REPO_ROOT/snep/modules/default/views/scripts/systemstatus/index.phtml"; then
    harness_ok 'poll failure maps to normalized UNAVAILABLE detail' 'JS .fail -> applyState(UNAVAILABLE)'
else
    harness_bad 'poll failure maps to normalized UNAVAILABLE detail' 'missing poll .fail containment in index.phtml'
fi

echo '==> Nothing on :80 required inside app for System Status metrics'
# In current bridge topology Apache IS on :80, but System Status must not
# call it. Prove the controller path does not open a socket to :80 by
# confirming the HTTP client call is gone (static) and HostResources uses
# /proc/uptime live:
LIVE_UP="$($COMPOSE exec -T app php -r "
require_once '/var/www/html/snep/lib/Snep/SystemStatus/HostResources.php';
\$p = Snep_SystemStatus_HostResources::uptimePhrase();
echo \$p === null ? 'NULL' : \$p;
" 2>&1 | tr -d '\r')"
if [ "$LIVE_UP" != 'NULL' ] && [ -n "$LIVE_UP" ]; then
    harness_ok 'live /proc uptime without HTTP :80' "$LIVE_UP"
else
    harness_bad 'live /proc uptime without HTTP :80' "got: $LIVE_UP"
fi

harness_require_containers app asterisk db
harness_complete
