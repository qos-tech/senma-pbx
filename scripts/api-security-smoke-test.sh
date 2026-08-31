#!/bin/bash
#
# TASK-0026F standalone API authentication/service-resolution focused
# security smoke test.
#
# Exercises the confirmed F17 findings from
# docs/tasks/0026-pre-pilot-security-release-audit.md (re-traced and
# remediated in docs/tasks/0026f-standalone-api-hardening.md) against
# snep/modules/default/api/index.php -- a standalone, unauthenticated-
# bootstrap API entry point that is entirely separate from the main
# Zend MVC front controller / Snep_AuthPlugin / Snep_PermissionPlugin
# stack (deliberately not routed through them -- see the doc above).
#
#   F17-A (pass-the-hash): two Basic-auth parsing branches used to
#   normalize the password inconsistently (one applied md5(), one did
#   not), so a stored MD5 hash itself was accepted as a valid password
#   via the unhashed branch. Fixed by unifying both branches into one
#   (username, plaintext-password) extraction with a single, shared
#   md5() normalization step applied exactly once afterward.
#
#   F17-B (path traversal / arbitrary file inclusion): $_GET['service']
#   was concatenated directly into a PHP filename and require_once'd
#   with only a file_exists() check. Fixed by an explicit, finite
#   service registry -- request data only ever selects a key into a
#   hardcoded array, never a filename.
#
# Every payload below is harmless and non-destructive: SQL/shell-shaped
# credential and service values, a real disposable fixture user (never
# a real admin account), and a proof that traversal-shaped service
# values fail closed -- no secret/file extraction, no destructive
# payloads, matching this task's own explicit constraints.
#
# Deliberately separate from `make smoke` -- never run implicitly by it.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
API_URL="${BASE_URL}/modules/default/api/index.php"
FIXTURE_USER="task0026f-restricted"
FIXTURE_PASSWORD="Task0026fApi123!"

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

fatal_count() {
    local n
    n="$($COMPOSE exec -T app sh -c 'grep -c "Fatal error" /var/log/apache2/mag-error.log 2>/dev/null' 2>/dev/null | tr -d '\r\n ')"
    echo "${n:-0}"
}

md5_of() {
    $COMPOSE exec -T app php -r "echo md5(\$argv[1]);" -- "$1" 2>/dev/null | tr -d '\r'
}

# api_request <user-or-empty> <password-or-empty> <service-or-empty> [extra curl args...]
# Returns HTTP code, leaves the response body in $BODY.
BODY=""
api_request() {
    local user="$1" pass="$2" service="$3"
    shift 3
    local -a curlargs=(-sS -o "$BODY" -w '%{http_code}')
    if [ -n "$user" ] || [ -n "$pass" ]; then
        curlargs+=(-u "${user}:${pass}")
    fi
    curlargs+=(-G "$API_URL")
    if [ -n "$service" ]; then
        curlargs+=(--data-urlencode "service=${service}")
    fi
    curlargs+=("$@")
    curl "${curlargs[@]}"
}

# api_request_raw_header <base64-credentials> <service-or-empty> -- exercises
# the HTTP_AUTHORIZATION server-variable branch explicitly (the branch F17-A
# lived in), independent of curl's own -u handling of PHP_AUTH_USER/PW.
api_request_raw_header() {
    local b64="$1" service="$2"
    local -a curlargs=(-sS -o "$BODY" -w '%{http_code}' -H "Authorization: Basic ${b64}")
    curlargs+=(-G "$API_URL")
    if [ -n "$service" ]; then
        curlargs+=(--data-urlencode "service=${service}")
    fi
    curl "${curlargs[@]}"
}

body_status() {
    grep -o '"status":"[a-z]*"' "$BODY" | head -1
}

# --- 0. Preflight ------------------------------------------------------

harness_require_containers app db
harness_require_env DB_USER DB_PASSWORD DB_NAME

BODY="$(mktemp)"
harness_register_best_effort_cleanup "response temp file" "rm -f '$BODY'"

FATALS_BEFORE="$(fatal_count)"
log "==> baseline PHP Fatal Error count: ${FATALS_BEFORE}"

# A dedicated, persistent, reusable fixture account with a known password,
# reset to that password every run (TASK-0026C/D/E's own established
# convention) -- never a real admin credential.
FIXTURE_HASH="$(md5_of "$FIXTURE_PASSWORD")"
if [ -z "$FIXTURE_HASH" ]; then
    harness_blocked "could not compute the fixture user's password hash via the app container"
fi
FID="$(db_query "SELECT id FROM users WHERE name='${FIXTURE_USER}';")"
if [ -z "$FID" ]; then
    db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${FIXTURE_USER}','${FIXTURE_HASH}','${FIXTURE_USER}@example.test','',1,NOW(),NOW());"
    FID="$(db_query "SELECT id FROM users WHERE name='${FIXTURE_USER}';")"
fi
if [ -z "$FID" ]; then
    harness_blocked "could not provision the API fixture user"
fi
db_query "UPDATE users SET password='${FIXTURE_HASH}' WHERE id=${FID};" >/dev/null
harness_register_best_effort_cleanup "fixture user ${FIXTURE_USER} (id=${FID}) password reset to baseline" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"UPDATE users SET password='${FIXTURE_HASH}' WHERE id=${FID};\" >/dev/null"

# =============================================================================
# Authentication -- F17-A (pass-the-hash unification)
# =============================================================================

log "==> Authentication: PHP_AUTH_USER/PW branch (existing real callers)"

# 1. Valid plaintext credentials via the PHP_AUTH_USER/PW branch (the
# branch call-smoke-test.sh/trunk-smoke-test.sh's own real callers use)
# must still authenticate successfully.
before_fatals="$(fatal_count)"
code="$(api_request "$FIXTURE_USER" "$FIXTURE_PASSWORD" "CallsReport")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"ok"' ] && [ "$before_fatals" = "$after_fatals" ]; then
    harness_ok "auth: valid plaintext via PHP_AUTH_USER/PW succeeds" "HTTP 200, status=ok, no new fatals (existing caller path preserved)"
else
    harness_bad "auth: valid plaintext via PHP_AUTH_USER/PW succeeds" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# 2. F17-A regression guard: the stored MD5 hash used AS the password via
# PHP_AUTH_USER/PW must be rejected (this branch already double-hashed
# before this task; must remain rejected after).
code="$(api_request "$FIXTURE_USER" "$FIXTURE_HASH" "CallsReport")"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"error"' ] && ! grep -q "$FIXTURE_HASH" "$BODY" && ! grep -qi "$FIXTURE_PASSWORD" "$BODY"; then
    harness_ok "F17-A: stored hash as password (PHP_AUTH_USER/PW) is rejected" "HTTP ${code}, status=error, no credential echoed back"
else
    harness_bad "F17-A: stored hash as password (PHP_AUTH_USER/PW) is rejected" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

log "==> Authentication: HTTP_AUTHORIZATION branch (the branch F17-A lived in)"

# 3. Valid plaintext credentials via a raw Authorization header must now
# authenticate successfully -- before this fix, this branch never
# hashed, so it could not authenticate a real plaintext credential at
# all (it compared plaintext directly to the stored MD5 hash).
B64_PLAIN="$(printf '%s' "${FIXTURE_USER}:${FIXTURE_PASSWORD}" | base64)"
before_fatals="$(fatal_count)"
code="$(api_request_raw_header "$B64_PLAIN" "CallsReport")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"ok"' ] && [ "$before_fatals" = "$after_fatals" ]; then
    harness_ok "auth: valid plaintext via HTTP_AUTHORIZATION succeeds" "HTTP 200, status=ok, no new fatals"
else
    harness_bad "auth: valid plaintext via HTTP_AUTHORIZATION succeeds" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# 4. F17-A core proof: the stored MD5 hash used AS the password via a raw
# Authorization header must now be REJECTED (this is the exact
# pass-the-hash vulnerability -- before the fix, this branch skipped
# md5() entirely and this same request authenticated successfully).
code="$(api_request_raw_header "$(printf '%s' "${FIXTURE_USER}:${FIXTURE_HASH}" | base64)" "CallsReport")"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"error"' ] && ! grep -q "$FIXTURE_HASH" "$BODY" && ! grep -qi "$FIXTURE_PASSWORD" "$BODY"; then
    harness_ok "F17-A: pass-the-hash via HTTP_AUTHORIZATION is rejected" "HTTP ${code}, status=error, stored hash no longer authenticates, no credential echoed back"
else
    harness_bad "F17-A: pass-the-hash via HTTP_AUTHORIZATION is rejected" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# 5. A password containing ':' must survive base64 Basic-auth decoding
# intact (explode(...,2) limit) rather than being truncated at the
# first colon.
COLON_PASSWORD="Task:0026f:Colon!"
COLON_HASH="$(md5_of "$COLON_PASSWORD")"
db_query "UPDATE users SET password='${COLON_HASH}' WHERE id=${FID};" >/dev/null
code="$(api_request_raw_header "$(printf '%s' "${FIXTURE_USER}:${COLON_PASSWORD}" | base64)" "CallsReport")"
db_query "UPDATE users SET password='${FIXTURE_HASH}' WHERE id=${FID};" >/dev/null
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"ok"' ]; then
    harness_ok "auth: password containing ':' is parsed intact" "HTTP ${code}, status=ok -- explode(...,2) preserves the full password"
else
    harness_bad "auth: password containing ':' is parsed intact" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# 6. Wrong password (ordinary case) is still rejected, and the error
# response never echoes the submitted credential back (Phase 7).
code="$(api_request "$FIXTURE_USER" "wrong-password-entirely" "CallsReport")"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"error"' ] && ! grep -qi "wrong-password-entirely" "$BODY"; then
    harness_ok "auth: wrong password rejected, not echoed" "HTTP ${code}, status=error, credential not present in response body"
else
    harness_bad "auth: wrong password rejected, not echoed" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# 7. No credentials at all -> 401 with WWW-Authenticate (preserved).
HEADERFILE="$(mktemp)"
harness_register_best_effort_cleanup "header temp file" "rm -f '$HEADERFILE'"
code="$(curl -sS -D "$HEADERFILE" -o "$BODY" -w '%{http_code}' -G "$API_URL" --data-urlencode "service=CallsReport")"
if [ "$code" = "401" ] && grep -qi '^WWW-Authenticate: Basic' "$HEADERFILE"; then
    harness_ok "auth: no credentials -> 401 Unauthorized" "HTTP 401, WWW-Authenticate: Basic present"
else
    harness_bad "auth: no credentials -> 401 Unauthorized" "HTTP ${code}, headers: $(cat "$HEADERFILE")"
fi

# 8. The historical Signup auth-bypass structure is gone: an
# unauthenticated request for service=Signup must not bypass
# authentication (it now behaves exactly like any other unauthenticated
# request -- 401, not a dispatch attempt).
code="$(api_request "" "" "Signup")"
if [ "$code" = "401" ] && [ "$(body_status)" = '"status":"error"' ]; then
    harness_ok "auth: service=Signup no longer bypasses authentication" "HTTP 401, unauthenticated Signup request is rejected like any other"
else
    harness_bad "auth: service=Signup no longer bypasses authentication" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# =============================================================================
# Service resolution -- F17-B (finite registry, no path from request data)
# =============================================================================

log "==> Service resolution boundary"

# 9. Every real, registered service is still reachable and returns a
# well-formed JSON response with an authenticated request. Contacts and
# CSV_ExportData require their own minimal, legitimate GET parameters to
# execute at all (pre-existing, unrelated to F17 -- see
# docs/tasks/0026f-standalone-api-hardening.md's technical-debt section:
# both crash with a PHP Fatal Error on PHP 8.4 when called with no
# parameters at all, a latent bug in the service files themselves, not
# in the dispatch/auth boundary this task fixes). The values below are
# harmless, non-matching/non-sensitive literals -- not an injection
# attempt, matching this suite's own "no secret extraction" constraint.
for svc in CallsReport Contacts CSV_ExportData CSV_GetParams RankingReport ServicesReport; do
    before_fatals="$(fatal_count)"
    case "$svc" in
        Contacts)
            code="$(api_request "$FIXTURE_USER" "$FIXTURE_PASSWORD" "$svc" --data-urlencode "phone=0000000000")"
            ;;
        CSV_ExportData)
            code="$(api_request "$FIXTURE_USER" "$FIXTURE_PASSWORD" "$svc" --data-urlencode "table=users" --data-urlencode "fields=id" --data-urlencode "order=id")"
            ;;
        *)
            code="$(api_request "$FIXTURE_USER" "$FIXTURE_PASSWORD" "$svc")"
            ;;
    esac
    after_fatals="$(fatal_count)"
    if [ "$code" = "200" ] && [ "$before_fatals" = "$after_fatals" ] && [ -s "$BODY" ]; then
        harness_ok "service resolution: ${svc} still reachable" "HTTP 200, no new fatals, non-empty JSON body"
    else
        harness_bad "service resolution: ${svc} still reachable" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}, body=$(head -c 200 "$BODY")"
    fi
done

# 10. No service param defaults to CallsReport (preserved).
code="$(api_request "$FIXTURE_USER" "$FIXTURE_PASSWORD" "")"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"ok"' ]; then
    harness_ok "service resolution: no service param defaults to CallsReport" "HTTP 200, status=ok"
else
    harness_bad "service resolution: no service param defaults to CallsReport" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# 11. F17-B core proof: a traversal-shaped service value must fail closed
# with the generic "not found" response -- no filesystem path, no stack
# trace, no PHP warning in the response body -- and must not produce a
# new PHP Fatal Error (the registry rejects it before require_once is
# ever reached, unlike the pre-fix behavior this task's own reproduction
# confirmed).
before_fatals="$(fatal_count)"
code="$(api_request "$FIXTURE_USER" "$FIXTURE_PASSWORD" "../../../../../../../../etc/passwd")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"error"' ] && [ "$before_fatals" = "$after_fatals" ] \
    && ! grep -qi "fatal\|stack trace\|/var/www\|warning" "$BODY"; then
    harness_ok "F17-B: traversal-shaped service fails closed" "HTTP ${code}, status=error, no new fatals, no path/stack-trace disclosure"
else
    harness_bad "F17-B: traversal-shaped service fails closed" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}, body=$(head -c 300 "$BODY")"
fi

# 12. A second traversal shape (absolute path with no leading dots) is
# also rejected -- proves the registry allowlist, not a naive "reject
# dots" filter, is what's actually doing the work.
before_fatals="$(fatal_count)"
code="$(api_request "$FIXTURE_USER" "$FIXTURE_PASSWORD" "/etc/passwd%00")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"error"' ] && [ "$before_fatals" = "$after_fatals" ]; then
    harness_ok "F17-B: absolute-path-shaped service fails closed" "HTTP ${code}, status=error, no new fatals"
else
    harness_bad "F17-B: absolute-path-shaped service fails closed" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}, body=$(head -c 300 "$BODY")"
fi

# 13. A plausible-but-unregistered service name fails closed the same way.
code="$(api_request "$FIXTURE_USER" "$FIXTURE_PASSWORD" "NoSuchThing")"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"error"' ]; then
    harness_ok "service resolution: unregistered service name fails closed" "HTTP ${code}, status=error"
else
    harness_bad "service resolution: unregistered service name fails closed" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

# 14. An array-shaped service parameter (service[]=x) must not reach
# array_key_exists()/require_once() and crash -- must fail closed like
# any other unregistered value.
before_fatals="$(fatal_count)"
code="$(curl -sS -o "$BODY" -w '%{http_code}' -u "${FIXTURE_USER}:${FIXTURE_PASSWORD}" -G "$API_URL" --data-urlencode "service[]=CallsReport")"
after_fatals="$(fatal_count)"
if [ "$code" = "200" ] && [ "$(body_status)" = '"status":"error"' ] && [ "$before_fatals" = "$after_fatals" ]; then
    harness_ok "service resolution: array-shaped service param fails closed" "HTTP ${code}, status=error, no new fatals"
else
    harness_bad "service resolution: array-shaped service param fails closed" "HTTP ${code}, fatals ${before_fatals}->${after_fatals}, body=$(head -c 300 "$BODY")"
fi

# 15. CallsReport-specific JSON slash-unescaping is preserved for the
# named service (behavior predating this task, must not regress).
code="$(api_request "$FIXTURE_USER" "$FIXTURE_PASSWORD" "CallsReport")"
if [ "$code" = "200" ] && ! grep -q '\\/' "$BODY"; then
    harness_ok "service resolution: CallsReport slash-unescaping preserved" "HTTP ${code}, no escaped '\\/' sequences in the response body"
else
    harness_bad "service resolution: CallsReport slash-unescaping preserved" "HTTP ${code}, body contains escaped slashes: $(head -c 200 "$BODY")"
fi

# 16. Unauthenticated dispatch attempt with a valid registered service
# name must still be denied (authentication is unconditional now --
# there is no longer any service name that skips it).
code="$(api_request "" "" "CallsReport")"
if [ "$code" = "401" ]; then
    harness_ok "auth: unauthenticated dispatch is always denied" "HTTP 401 even for a real, registered service name"
else
    harness_bad "auth: unauthenticated dispatch is always denied" "HTTP ${code}, body=$(head -c 200 "$BODY")"
fi

harness_complete
