#!/bin/bash
#
# TASK-0026I information-disclosure and contained-path-traversal focused
# security smoke test.
#
# Exercises the F25/F26/F28 findings from
# docs/tasks/0026-pre-pilot-security-release-audit.md (re-traced and
# remediated in
# docs/tasks/0026i-disclosure-path-traversal-hardening.md):
#
#   F25 (unconditional exception-message disclosure): error/error.phtml's
#   "Server Message" line was shown on every non-404 error regardless of
#   APPLICATION_ENV. Now gated by the same 'development' == APPLICATION_ENV
#   check the fuller trace/params block already used; the full detail is
#   still written server-side via error_log() in ErrorController.
#
#   F26 (information disclosure): (a) X-Powered-By exposed the exact PHP
#   version -- fixed via expose_php=Off; (b) CallsReportService/
#   ServicesReportService echoed the generated SQL text ("select"/
#   "selectcont"/"selectcount") back in their JSON responses -- the
#   sibling disclosure instance TASK-0026F1 Sec.5 deferred by name. Both
#   fields are now dropped; the functional payload is unchanged.
#
#   F28 (path traversal in the Documentation viewer): DocsController
#   built a filesystem path directly from a raw REQUEST PARAMETER NAME
#   (strtoupper($key).'.md', no traversal stripping, contained only by
#   the unconditional ".md" suffix). Replaced with a fixed allowlist
#   mapping the 7 real button names to their exact on-disk filenames,
#   plus a realpath()-based containment check as defense in depth (which
#   this suite also proves catches a symlink escape even for an
#   allowlisted slot).
#
# Every payload below is harmless: real, disposable, test-owned fixtures
# (a temporary symlink over a doc file that is restored byte-for-byte, an
# inert marker file outside the docs root, deleted afterward) or already-
# reproducible, non-destructive, read-only conditions (errors-tdm's
# pre-existing no-Khomp-hardware 500 in this dev environment, GET only,
# no state mutated). No real sensitive file (/etc/passwd, secrets, keys)
# is ever targeted -- traversal payloads either never reach the
# filesystem at all (rejected by the allowlist lookup itself) or target
# only this suite's own marker file.
#
# Deliberately separate from `make smoke` -- never run implicitly by it.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
API_URL="${BASE_URL}/modules/default/api/index.php"
ADMIN_USER="admin"
ADMIN_PASSWORD="SmokeTest123!"

log() { harness_log "$@"; }

app_exec() {
    $COMPOSE exec -T app sh -c "$1"
}

fatal_count() {
    local n
    n="$(app_exec 'grep -c "Fatal error" /var/log/apache2/mag-error.log 2>/dev/null' | tr -d '\r\n ')"
    echo "${n:-0}"
}

BODY=""
HEADERS=""
request() {
    local jar="$1" method="$2" path="$3" data="${4:-}"
    if [ "$method" = POST ]; then
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' -d "$data" "${BASE_URL}${path}"
    else
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' "${BASE_URL}${path}"
    fi
}

# --- 0. Preflight --------------------------------------------------------

harness_require_containers app db

BODY="$(mktemp)"
HEADERS="$(mktemp)"
harness_register_best_effort_cleanup "request temp files" "rm -f '$BODY' '$HEADERS'"

FATALS_BEFORE="$(fatal_count)"
log "==> baseline PHP Fatal Error count: ${FATALS_BEFORE}"

ADMIN_JAR="$(mktemp)"
harness_register_best_effort_cleanup "admin cookie jar" "rm -f '$ADMIN_JAR'"
code="$(request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}")"
if [ "$code" != "302" ]; then
    harness_blocked "admin login failed (HTTP ${code}) -- cannot proceed without an authenticated session"
fi
ADMIN_CSRF="$(harness_csrf_token "$ADMIN_JAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then
    harness_blocked "could not read the admin session's CSRF token"
fi

# =============================================================================
# 1. Disclosure -- F26(a): X-Powered-By / expose_php
# =============================================================================

log "==> F26(a): X-Powered-By header"

request "$ADMIN_JAR" GET /index.php/index/add >/dev/null
if ! grep -qi '^X-Powered-By:' "$HEADERS"; then
    harness_ok "1: X-Powered-By header is absent (expose_php=Off)" "no X-Powered-By header on an authenticated response"
else
    harness_bad "1: X-Powered-By header is absent (expose_php=Off)" "header present: $(grep -i '^X-Powered-By:' "$HEADERS")"
fi

# =============================================================================
# 2. Disclosure -- F26(b): raw SQL text in API JSON responses
# =============================================================================

log "==> F26(b): raw SQL text in CallsReportService/ServicesReportService"

API_CODE="$(curl -sS -o "$BODY" -w '%{http_code}' -u "${ADMIN_USER}:${ADMIN_PASSWORD}" -G "$API_URL" \
    --data-urlencode "service=CallsReport" \
    --data-urlencode "start_date=2026-01-01" --data-urlencode "start_hour=00:00:00" \
    --data-urlencode "end_date=2026-12-31" --data-urlencode "end_hour=23:59:59")"
if [ "$API_CODE" = "200" ] && grep -q '"status":"ok"' "$BODY"; then
    harness_ok "2: legitimate CallsReport request succeeds" "HTTP $API_CODE, status=ok"
else
    harness_bad "2: legitimate CallsReport request succeeds" "HTTP ${API_CODE}, body=$(head -c 200 "$BODY")"
fi
if ! grep -qE '"select(cont)?"[[:space:]]*:' "$BODY" && ! grep -qi 'SELECT ' "$BODY"; then
    harness_ok "3: CallsReport response contains no raw SQL text" "no select/selectcont field, no SELECT text in body"
else
    harness_bad "3: CallsReport response contains no raw SQL text" "body=$(head -c 300 "$BODY")"
fi

API_CODE="$(curl -sS -o "$BODY" -w '%{http_code}' -u "${ADMIN_USER}:${ADMIN_PASSWORD}" -G "$API_URL" \
    --data-urlencode "service=ServicesReport" \
    --data-urlencode "start_date=2026-01-01" --data-urlencode "start_hour=00:00:00" \
    --data-urlencode "end_date=2026-12-31" --data-urlencode "end_hour=23:59:59")"
if [ "$API_CODE" = "200" ] && grep -qE '"status":"(ok|empty)"' "$BODY"; then
    harness_ok "4: legitimate ServicesReport request succeeds" "HTTP $API_CODE, body=$(head -c 120 "$BODY")"
else
    harness_bad "4: legitimate ServicesReport request succeeds" "HTTP ${API_CODE}, body=$(head -c 200 "$BODY")"
fi
if ! grep -qE '"select(count)?"[[:space:]]*:' "$BODY" && ! grep -qi 'SELECT ' "$BODY"; then
    harness_ok "5: ServicesReport response contains no raw SQL text" "no select/selectcount field, no SELECT text in body"
else
    harness_bad "5: ServicesReport response contains no raw SQL text" "body=$(head -c 300 "$BODY")"
fi

# =============================================================================
# 3. Disclosure -- F25: exception-message / stack-trace / absolute-path
#    disclosure on a real, reproducible, non-destructive 500
# =============================================================================

log "==> F25: exception disclosure on a real 500 (errors-tdm, no Khomp hardware in this dev env, TASK-0026A doc)"

FATALS_BEFORE_TDM="$(fatal_count)"
code="$(request "$ADMIN_JAR" GET /index.php/default/errors-tdm)"
if [ "$code" = "500" ]; then
    harness_ok "6: the known no-Khomp condition still reproduces a real 500" "HTTP $code (see docs/tasks/0026a-authorization-default-deny.md)"
else
    harness_bad "6: the known no-Khomp condition still reproduces a real 500" "HTTP $code -- disclosure checks below need a real 500 to be meaningful"
fi

if ! grep -qi 'Server Message' "$BODY"; then
    harness_ok "7: 500 response does not show the internal exception message" "no 'Server Message' text in body"
else
    harness_bad "7: 500 response does not show the internal exception message" "body=$(head -c 300 "$BODY")"
fi

if ! grep -qE '/var/www|/usr/local|Stack trace|getTraceAsString|Classe:|Request Parameters' "$BODY"; then
    harness_ok "8: 500 response does not expose absolute paths or a stack trace" "no filesystem path / trace markers in body"
else
    harness_bad "8: 500 response does not expose absolute paths or a stack trace" "body=$(head -c 300 "$BODY")"
fi

if [ "$code" = "500" ] && grep -qi 'history.back\|Get me out of here\|Erro Interno\|Internal Error' "$BODY"; then
    harness_ok "9: the controlled error path still produces a usable client response" "HTTP $code, generic controlled error page rendered"
else
    harness_bad "9: the controlled error path still produces a usable client response" "HTTP $code, body=$(head -c 200 "$BODY")"
fi

# Detail must still reach the server-side log even though the client no
# longer sees it -- ErrorController::errorAction() now error_log()s it.
sleep 1
if app_exec 'grep -q "ErrorController: uncaught" /var/log/apache2/mag-error.log 2>/dev/null'; then
    harness_ok "10: full exception detail is still recorded server-side" "ErrorController: uncaught ... line present in the app error log"
else
    harness_bad "10: full exception detail is still recorded server-side" "no 'ErrorController: uncaught' line found in the app error log"
fi

FATALS_AFTER_TDM="$(fatal_count)"
if [ "$FATALS_AFTER_TDM" = "$FATALS_BEFORE_TDM" ]; then
    harness_ok "11: the reproduced 500 is a handled exception, not a new PHP Fatal Error" "Fatal Error count unchanged (${FATALS_BEFORE_TDM})"
else
    harness_bad "11: the reproduced 500 is a handled exception, not a new PHP Fatal Error" "Fatal Error count changed: ${FATALS_BEFORE_TDM} -> ${FATALS_AFTER_TDM}"
fi

# =============================================================================
# 4. Path traversal -- F28: DocsController legitimate access
# =============================================================================

log "==> F28: DocsController legitimate access"

code="$(request "$ADMIN_JAR" POST /index.php/default/docs "changelog=changelog&snep_csrf_token=${ADMIN_CSRF}")"
if [ "$code" = "200" ] && grep -qi 'Changelog Snep' "$BODY"; then
    harness_ok "12: legitimate allowlisted doc (changelog) renders" "HTTP $code, real Changelog content present"
else
    harness_bad "12: legitimate allowlisted doc (changelog) renders" "HTTP $code, body=$(head -c 200 "$BODY")"
fi

code="$(request "$ADMIN_JAR" POST /index.php/default/docs "install_guide=install_guide&snep_csrf_token=${ADMIN_CSRF}")"
if [ "$code" = "200" ] && grep -qi 'Bem vindo' "$BODY"; then
    harness_ok "13: a second, distinct allowlisted doc (install_guide) also renders" "HTTP $code, real Install Guide content present -- the allowlist is not special-casing just one entry"
else
    harness_bad "13: a second, distinct allowlisted doc (install_guide) also renders" "HTTP $code, body=$(head -c 200 "$BODY")"
fi

# =============================================================================
# 5. Path traversal -- F28: traversal/absolute/encoded/outside-root rejection
# =============================================================================

log "==> F28: traversal, encoded traversal, absolute path, outside-root rejection"

# 14. Simple ../ traversal as the PARAMETER NAME (the actual F28 shape --
# $key, not a value). Never resolves to the real filesystem at all: the
# allowlist lookup rejects any name that isn't one of the 7 known keys
# before any path is built, so this is inherently safe -- no real file is
# ever targeted.
code="$(curl -sS -b "$ADMIN_JAR" -c "$ADMIN_JAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "../../../../etc/passwd=x" --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/docs")"
if [ "$code" = "200" ] && ! grep -qi 'root:.*:0:0' "$BODY"; then
    harness_ok "14: simple ../ traversal in the parameter name is rejected" "HTTP $code, no doc content rendered, no /etc/passwd leakage"
else
    harness_bad "14: simple ../ traversal in the parameter name is rejected" "HTTP $code, body=$(head -c 200 "$BODY")"
fi

# 15. Encoded traversal (%2e%2e%2f) as the parameter name -- the fix is an
# exact-match allowlist lookup, not a string-transform-then-compare, so
# any encoded variant simply never equals one of the 7 allowed keys.
code="$(curl -sS -b "$ADMIN_JAR" -c "$ADMIN_JAR" -o "$BODY" -w '%{http_code}' \
    --data "%2e%2e%2f%2e%2e%2fetc%2fpasswd=x&snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/docs")"
if [ "$code" = "200" ] && ! grep -qi 'root:.*:0:0' "$BODY"; then
    harness_ok "15: encoded traversal (%2e%2e%2f) in the parameter name is rejected" "HTTP $code, no doc content rendered"
else
    harness_bad "15: encoded traversal (%2e%2e%2f) in the parameter name is rejected" "HTTP $code, body=$(head -c 200 "$BODY")"
fi

# 16. Absolute path as the parameter name.
code="$(curl -sS -b "$ADMIN_JAR" -c "$ADMIN_JAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "/etc/passwd=x" --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/docs")"
if [ "$code" = "200" ] && ! grep -qi 'root:.*:0:0' "$BODY"; then
    harness_ok "16: absolute-path parameter name is rejected" "HTTP $code, no doc content rendered"
else
    harness_bad "16: absolute-path parameter name is rejected" "HTTP $code, body=$(head -c 200 "$BODY")"
fi

# 17. Sibling/outside-root target: a test-owned inert marker file placed
# one level above the docs root, targeted via a non-allowlisted parameter
# name. Proves containment, not just "the 7 literal known names happen to
# work" -- and never touches any real/sensitive file.
MARKER_CONTENT="TASK-0026I-OUTSIDE-MARKER-$$-DO-NOT-SERVE"
MARKER_FILE="$REPO_ROOT/snep/OUTSIDE-MARKER.md"
printf '%s\n' "$MARKER_CONTENT" > "$MARKER_FILE"
harness_register_cleanup "outside-root marker file removed" "rm -f '$MARKER_FILE'"

code="$(curl -sS -b "$ADMIN_JAR" -c "$ADMIN_JAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "../OUTSIDE-MARKER=x" --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
    "${BASE_URL}/index.php/default/docs")"
if [ "$code" = "200" ] && ! grep -q "$MARKER_CONTENT" "$BODY"; then
    harness_ok "17: sibling/outside-root marker file is not disclosed" "HTTP $code, marker content absent from response"
else
    harness_bad "17: sibling/outside-root marker file is not disclosed" "HTTP $code, body=$(head -c 200 "$BODY")"
fi

# =============================================================================
# 6. Path traversal -- F28: symlink escape (Phase 8), test-owned fixture
# =============================================================================

log "==> F28: symlink escape through an ALLOWLISTED slot"

TRANSLATION_FILE="$REPO_ROOT/snep/docs/TRANSLATION.md"
TRANSLATION_BACKUP="$(mktemp)"
cp "$TRANSLATION_FILE" "$TRANSLATION_BACKUP"
harness_register_best_effort_cleanup "TRANSLATION.md backup tempfile" "rm -f '$TRANSLATION_BACKUP'"
harness_register_cleanup "TRANSLATION.md restored to its original content" \
    "rm -f '$TRANSLATION_FILE' && cp '$TRANSLATION_BACKUP' '$TRANSLATION_FILE'"

# Relative symlink so it resolves identically whether read from the host
# bind-mount path or the container's /var/www/html/snep path.
rm -f "$TRANSLATION_FILE"
ln -s ../OUTSIDE-MARKER.md "$TRANSLATION_FILE"

code="$(request "$ADMIN_JAR" POST /index.php/default/docs "translation=translation&snep_csrf_token=${ADMIN_CSRF}")"
if [ "$code" = "200" ] && ! grep -q "$MARKER_CONTENT" "$BODY"; then
    harness_ok "18: a symlink planted at an allowlisted slot cannot escape the docs root" "HTTP $code, realpath()-based containment rejected the resolved target, marker content not served"
else
    harness_bad "18: a symlink planted at an allowlisted slot cannot escape the docs root" "HTTP $code, body=$(head -c 200 "$BODY")"
fi

# Restore immediately (in addition to the registered cleanup).
rm -f "$TRANSLATION_FILE"
cp "$TRANSLATION_BACKUP" "$TRANSLATION_FILE"

# 19. The real file at that slot is restored byte-for-byte -- checked at
# the filesystem level, not via a fresh HTTP request: PHP's
# realpath_cache_ttl (120s, confirmed via `php -i` in this environment)
# means the SAME long-lived Apache worker that just resolved check 18's
# symlink can still return that stale resolution for a few seconds after
# the file is swapped back, which would make an immediate HTTP re-check
# of this exact path flaky for reasons unrelated to the security fix
# itself. A direct byte-for-byte diff against the pre-test backup is a
# deterministic proof that no fixture residue remains, independent of
# any cache timing.
if diff -q "$TRANSLATION_BACKUP" "$TRANSLATION_FILE" >/dev/null 2>&1 && [ ! -L "$TRANSLATION_FILE" ]; then
    harness_ok "19: TRANSLATION.md is restored byte-for-byte, not left as a symlink" "file content matches the pre-test backup exactly"
else
    harness_bad "19: TRANSLATION.md is restored byte-for-byte, not left as a symlink" "restored file differs from backup or is still a symlink"
fi

# =============================================================================
# Health
# =============================================================================

FATALS_AFTER="$(fatal_count)"
if [ "$FATALS_AFTER" = "$FATALS_BEFORE" ]; then
    harness_ok "application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE})"
else
    harness_bad "application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE} -> ${FATALS_AFTER}"
fi

harness_complete
