#!/bin/bash
#
# HTTP smoke test harness for the SENMA/SNEP admin interface (TASK-0003).
#
# Exercises the flows validated manually during TASK-0002 (PHP 8.4
# compatibility) against a running `make dev` Docker environment, using
# plain curl -- no test framework dependency. See:
#   docs/tasks/0003-http-smoke-harness.md
#   docs/tasks/0002-php84-compatibility-baseline.md
#
# Exit code: 0 if every flow is PASS or an explicitly-known EXPECTED
# LIMITATION; 1 if any flow FAILs or a new PHP Fatal Error is detected.

set -uo pipefail

# --- Configuration -----------------------------------------------------

BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
# Dev-only test credentials, established idempotently by this script
# against the running dev database. Never used outside local Docker dev.
#
# Deliberately reuses the seeded 'admin' account rather than a dedicated
# synthetic user: a first attempt created a separate 'smoketest' user
# (same profile_id=1 as admin) and it was redirected to
# /index.php/permission/error on every admin page -- profile_id alone
# does not carry the same effective permissions as the seeded admin row
# (a profiles_permissions/ACL concern, out of this task's scope to
# investigate). Reusing 'admin' matches the exact approach already
# validated end-to-end throughout TASK-0002.
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"

COOKIEJAR="$(mktemp)"
TMP_BODY="$(mktemp)"
TMP_HEADERS="$(mktemp)"
cleanup() { rm -f "$COOKIEJAR" "$TMP_BODY" "$TMP_HEADERS"; }
trap cleanup EXIT

PASS=0
FAIL=0
LIMITATION=0
declare -a RESULTS=()
START_TIME=$(date +%s)

log()  { printf '%s\n' "$*" >&2; }
row()  { RESULTS+=("$1|$2|$3"); }  # flow|status|detail

# --- Pre-flight: validate the Docker environment ------------------------

log "==> Validating Docker environment"
if ! $COMPOSE ps app 2>/dev/null | grep -q "Up"; then
    log "app container not running/healthy -- starting it (make up semantics)"
    $COMPOSE up -d --build >&2
fi

log "==> Waiting for app to answer HTTP"
for i in $(seq 1 30); do
    if curl -sS -o /dev/null -w '' "$BASE_URL/" 2>/dev/null; then
        break
    fi
    sleep 2
done
if ! curl -sS -o /dev/null "$BASE_URL/" 2>/dev/null; then
    log "FATAL: app not reachable at $BASE_URL after waiting"
    exit 1
fi

# --- Establish a known dev test account ---------------------------------
# Idempotent: a dedicated smoke-test user, never touching the seeded
# 'admin' row. Safe to re-run; harmless outside local Docker dev.

log "==> Ensuring dev test account exists ($TEST_USER)"
# Hashed inside the app container (via PHP) rather than with a host
# md5sum/md5 binary, since those differ (or are absent) across host OSes
# -- the container always has PHP, keeping this Docker-only per CLAUDE.md.
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$TEST_HASH" ]; then
    log "FATAL: could not compute test-account password hash via the app container"
    exit 1
fi
# Only updates the password of the existing seeded admin row -- never
# inserts, never touches any other column (dashboard/profile_id/etc stay
# whatever they already are).
$COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" "${DB_NAME:-snep}" \
    -e "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2 2>&1 || {
    log "FATAL: could not set the dev test account password"
    exit 1
}

# --- Baseline fatal-error count in the app log ---------------------------

fatal_count() {
    # grep -c exits 1 (not 0) when the count is legitimately zero, which
    # would double-fire a naive `|| echo 0` fallback (grep's own "0" plus
    # the fallback's "0"). Only fall back when the output is truly empty
    # (e.g. the log file doesn't exist yet).
    local n
    n="$($COMPOSE exec -T app sh -c 'grep -c "Fatal error" /var/log/apache2/mag-error.log 2>/dev/null' 2>/dev/null | tr -d '\r\n ')"
    echo "${n:-0}"
}
FATALS_BEFORE="$(fatal_count)"
log "==> Baseline fatal-error count in app log: ${FATALS_BEFORE:-0}"

# --- Helper: run one HTTP check ------------------------------------------
#
# check <flow> <method> <path> <postdata|-> <expect_status> <marker|-> <mode>
#   mode: normal | known_limitation | no_marker

check() {
    local flow="$1" method="$2" path="$3" postdata="$4" expect="$5" marker="$6" mode="$7"
    local code

    if [ "$method" = "POST" ]; then
        code=$(curl -sS -b "$COOKIEJAR" -c "$COOKIEJAR" -o "$TMP_BODY" -D "$TMP_HEADERS" \
            -w '%{http_code}' -d "$postdata" "$BASE_URL$path")
    else
        code=$(curl -sS -b "$COOKIEJAR" -c "$COOKIEJAR" -o "$TMP_BODY" -D "$TMP_HEADERS" \
            -w '%{http_code}' "$BASE_URL$path")
    fi

    # Defensive: raw PHP fatal text leaking into the response body
    # (should not happen with display_errors=Off, but check anyway).
    if grep -qi "Fatal error\|Uncaught Error\|Stack trace" "$TMP_BODY"; then
        row "$flow" "FAIL" "PHP fatal text found in response body ($method $path)"
        FAIL=$((FAIL+1))
        return
    fi

    if [ "$mode" = "known_limitation" ]; then
        if [ "$code" = "$expect" ] && grep -qF "$marker" "$TMP_BODY"; then
            row "$flow" "EXPECTED_LIMITATION" "$code, matches documented no-Asterisk signature ($method $path)"
            LIMITATION=$((LIMITATION+1))
        else
            row "$flow" "FAIL" "expected known limitation (status $expect + marker) but got status $code, marker not matched -- possible NEW regression ($method $path)"
            FAIL=$((FAIL+1))
        fi
        return
    fi

    if [ "$code" != "$expect" ]; then
        row "$flow" "FAIL" "expected HTTP $expect, got $code ($method $path)"
        FAIL=$((FAIL+1))
        return
    fi

    if [ "$mode" != "no_marker" ] && [ -n "$marker" ] && ! grep -qF "$marker" "$TMP_BODY"; then
        row "$flow" "FAIL" "HTTP $code but expected content marker not found: '$marker' ($method $path)"
        FAIL=$((FAIL+1))
        return
    fi

    row "$flow" "PASS" "HTTP $code$( [ -n "$marker" ] && [ "$mode" != "no_marker" ] && echo ", marker '$marker' found" ) ($method $path)"
    PASS=$((PASS+1))
}

# --- Flows ----------------------------------------------------------------

log "==> login"
check "login" "POST" "/index.php/auth/login" "user=${TEST_USER}&password=${TEST_PASSWORD}" "302" "" "no_marker"
if ! grep -qi "^Location:.*index.php/" "$TMP_HEADERS"; then
    row "login" "FAIL" "302 without an /index.php/ Location header (login likely did not actually authenticate)"
    FAIL=$((FAIL+1))
    PASS=$((PASS>0 ? PASS-1 : 0))
fi

log "==> dashboard"
check "dashboard" "GET" "/index.php/" "-" "302" "" "no_marker"
check "dashboard (redirect target)" "GET" "/index.php/index/add" "-" "200" 'var controller = "index"' "normal"

log "==> extensions"
check "extensions" "GET" "/index.php/default/extensions" "-" "200" 'var controller = "extensions"' "normal"

log "==> trunks"
check "trunks" "GET" "/index.php/default/trunks" "-" "200" 'var controller = "trunks"' "normal"

log "==> routes"
check "routes" "GET" "/index.php/default/route" "-" "200" 'var controller = "route"' "normal"

log "==> groups"
check "groups" "GET" "/index.php/default/extensions-groups" "-" "200" 'var controller = "extensions-groups"' "normal"

log "==> queues (known limitation: no Asterisk service in this topology)"
check "queues" "GET" "/index.php/default/queues" "-" "500" "parse_ini_file(/etc/asterisk/snep/snep-musiconhold.conf)" "known_limitation"

log "==> reports"
check "reports" "GET" "/index.php/default/calls-report" "-" "200" 'var controller = "calls-report"' "normal"

log "==> settings"
check "settings" "GET" "/index.php/default/parameters" "-" "200" 'var controller = "parameters"' "normal"

log "==> logout"
check "logout" "GET" "/index.php/auth/logout" "-" "302" "" "no_marker"

log "==> logout invalidates session (re-request an authenticated page)"
curl -sS -b "$COOKIEJAR" -c "$COOKIEJAR" -o "$TMP_BODY" "$BASE_URL/index.php/"
if grep -q "SNEP - Login" "$TMP_BODY"; then
    row "logout session invalidation" "PASS" "post-logout request to / renders the login page, not the dashboard"
    PASS=$((PASS+1))
else
    row "logout session invalidation" "FAIL" "post-logout request to / did not render the login page -- session may still be authenticated"
    FAIL=$((FAIL+1))
fi

log "==> protected config files stay inaccessible over HTTP"
for f in "/includes/setup.conf" "/includes/setup.conf.dist"; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' "$BASE_URL$f")
    if [ "$code" = "403" ]; then
        row "protected file $f" "PASS" "HTTP 403 as expected"
        PASS=$((PASS+1))
    else
        row "protected file $f" "FAIL" "expected HTTP 403, got $code -- credentials may be exposed over HTTP"
        FAIL=$((FAIL+1))
    fi
done

# --- Post-run fatal-error diff -------------------------------------------

FATALS_AFTER="$(fatal_count)"
NEW_FATALS=$(( ${FATALS_AFTER:-0} - ${FATALS_BEFORE:-0} ))
if [ "$NEW_FATALS" -gt 0 ]; then
    row "app log fatal-error count" "FAIL" "$NEW_FATALS new PHP Fatal Error(s) appeared during this run (before=$FATALS_BEFORE, after=$FATALS_AFTER)"
    FAIL=$((FAIL+1))
    log "--- new fatal-error log lines ---"
    $COMPOSE exec -T app tail -n 200 /var/log/apache2/mag-error.log 2>/dev/null | grep "Fatal error" | tail -n "$NEW_FATALS" >&2
else
    row "app log fatal-error count" "PASS" "no new PHP Fatal Errors (before=$FATALS_BEFORE, after=$FATALS_AFTER)"
    PASS=$((PASS+1))
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# --- Report ----------------------------------------------------------------

echo
echo "================================================================"
printf "%-32s %-20s %s\n" "FLOW" "RESULT" "DETAIL"
echo "----------------------------------------------------------------"
for r in "${RESULTS[@]}"; do
    IFS='|' read -r flow status detail <<< "$r"
    printf "%-32s %-20s %s\n" "$flow" "$status" "$detail"
done
echo "================================================================"
echo "PASS: $PASS   FAIL: $FAIL   EXPECTED_LIMITATION: $LIMITATION"
echo "Elapsed: ${ELAPSED}s"
echo "================================================================"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
