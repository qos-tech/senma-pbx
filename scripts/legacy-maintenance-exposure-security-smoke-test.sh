#!/bin/bash
#
# TASK-0026S legacy-maintenance-exposure focused security smoke test.
#
# Exercises the finding disclosed prominently in
# docs/tasks/0026r-full-residual-sql-remediation.md (Status section, §9,
# §12): `snep/install/database/update/betha/convert-data-rc3.php` --  a
# one-time, PDO-based DB migration script from the "betha"/rc3 pre-release
# cycle -- was directly, unauthenticatedly web-reachable (Apache serves
# `snep/install/` with no access restriction, since DocumentRoot is
# `snep/` itself) and capable of destructive DDL (its own first statement
# is `ALTER TABLE peers DROP FOREIGN KEY ...`). A plain unauthenticated
# `curl` GET was enough to trigger real execution against the live dev
# database; it happened to fail immediately only because the referenced
# constraint does not exist in the current schema.
#
# This is not a SQL-injection finding (every interpolated value is
# DB-derived, never request-controlled) -- it is an unauthenticated
# web-reachable destructive-action finding, a different vulnerability
# class, remediated here by denying HTTP access to the entire
# `snep/install/` subtree at the web-server layer
# (snep/install/.htaccess, `Require all denied`), the same Apache
# 2.4-native pattern snep/includes/.htaccess and
# snep/lib/linfo/*/.htaccess already established. This closes both the
# known finding and its one PHP sibling
# (database/update/3.01/updateCallerid.php), plus every other file in the
# subtree (SQL fixtures, Asterisk config templates), in one fix at the
# broadest safe layer -- not a query-string password or IP check inside
# the script itself.
#
# Every check below is read-only reachability probing (GET/POST expected
# to be rejected at the Apache access-control layer, before PHP ever
# runs) or passive DB/log verification. No destructive SQL is ever
# deliberately executed by this suite.
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

KNOWN_SCRIPT="/install/database/update/betha/convert-data-rc3.php"
SIBLING_SCRIPT="/install/database/update/3.01/updateCallerid.php"
KNOWN_SCRIPT_FS="install/database/update/betha/convert-data-rc3.php"
SIBLING_SCRIPT_FS="install/database/update/3.01/updateCallerid.php"

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

BODY=""
HEADERS=""
request() {
    local method="$1" path="$2"
    if [ "$method" = POST ]; then
        curl -sS -D "$HEADERS" -o "$BODY" -w '%{http_code}' -X POST "${BASE_URL}${path}"
    else
        curl -sS -D "$HEADERS" -o "$BODY" -w '%{http_code}' "${BASE_URL}${path}"
    fi
}

# --- 0. Preflight --------------------------------------------------------

harness_require_containers app db
harness_require_env DB_USER DB_PASSWORD DB_NAME

BODY="$(mktemp)"
HEADERS="$(mktemp)"
harness_register_best_effort_cleanup "request temp files" "rm -f '$BODY' '$HEADERS'"

FATALS_BEFORE="$(fatal_count)"
log "==> baseline PHP Fatal Error count: ${FATALS_BEFORE}"

PEER_GROUPS_BEFORE="$(db_query 'SELECT COUNT(*) FROM core_peer_groups;' | tr -d '\r\n ')"
log "==> baseline core_peer_groups row count: ${PEER_GROUPS_BEFORE}"

# =============================================================================
# 1. Known finding: convert-data-rc3.php cannot be invoked over HTTP
# =============================================================================

log "==> known finding: ${KNOWN_SCRIPT}"

code="$(request GET "$KNOWN_SCRIPT")"
if [ "$code" = "403" ]; then
    harness_ok "1: known script HTTP GET is blocked" "HTTP $code"
else
    harness_bad "1: known script HTTP GET is blocked" "HTTP $code (expected 403) -- body=$(head -c 200 "$BODY")"
fi

code="$(request POST "$KNOWN_SCRIPT")"
if [ "$code" = "403" ]; then
    harness_ok "2: known script HTTP POST is blocked" "HTTP $code"
else
    harness_bad "2: known script HTTP POST is blocked" "HTTP $code (expected 403) -- body=$(head -c 200 "$BODY")"
fi

# =============================================================================
# 2. Sibling migration script (database/update/3.01/updateCallerid.php)
# =============================================================================

log "==> sibling script: ${SIBLING_SCRIPT}"

code="$(request GET "$SIBLING_SCRIPT")"
if [ "$code" = "403" ]; then
    harness_ok "3: sibling script HTTP GET is blocked" "HTTP $code"
else
    harness_bad "3: sibling script HTTP GET is blocked" "HTTP $code (expected 403) -- body=$(head -c 200 "$BODY")"
fi

code="$(request POST "$SIBLING_SCRIPT")"
if [ "$code" = "403" ]; then
    harness_ok "4: sibling script HTTP POST is blocked" "HTTP $code"
else
    harness_bad "4: sibling script HTTP POST is blocked" "HTTP $code (expected 403) -- body=$(head -c 200 "$BODY")"
fi

# =============================================================================
# 3. Whole-tree containment: non-PHP assets under install/ are equally
#    blocked, and the directory itself is not listable -- proves the fix
#    is a boundary at snep/install/, not a per-file patch
# =============================================================================

log "==> whole-tree containment"

code="$(request GET "/install/index.html")"
if [ "$code" = "403" ]; then
    harness_ok "5: a non-PHP static asset under install/ is also blocked" "HTTP $code"
else
    harness_bad "5: a non-PHP static asset under install/ is also blocked" "HTTP $code (expected 403)"
fi

code="$(request GET "/install/database/schema.sql")"
if [ "$code" = "403" ]; then
    harness_ok "6: a raw .sql fixture under install/ is also blocked" "HTTP $code"
else
    harness_bad "6: a raw .sql fixture under install/ is also blocked" "HTTP $code (expected 403)"
fi

code="$(request GET "/install/")"
if [ "$code" = "403" ]; then
    harness_ok "7: the install/ directory itself is not browsable" "HTTP $code"
else
    harness_bad "7: the install/ directory itself is not browsable" "HTTP $code (expected 403)"
fi

# =============================================================================
# 4. No disclosure in the blocked response
# =============================================================================

log "==> blocked-response disclosure check"

request GET "$KNOWN_SCRIPT" >/dev/null
if ! grep -qiE '/var/www|Fatal error|Stack trace|SQLSTATE|<\?php' "$BODY"; then
    harness_ok "8: blocked response discloses no source/path/SQL-error detail" "generic 403 body only"
else
    harness_bad "8: blocked response discloses no source/path/SQL-error detail" "body=$(head -c 300 "$BODY")"
fi

# =============================================================================
# 5. No schema/data mutation occurred (this suite's own probing included)
# =============================================================================

log "==> integrity verification"

PEER_GROUPS_AFTER="$(db_query 'SELECT COUNT(*) FROM core_peer_groups;' | tr -d '\r\n ')"
if [ "$PEER_GROUPS_AFTER" = "$PEER_GROUPS_BEFORE" ]; then
    harness_ok "9: core_peer_groups row count unchanged" "still ${PEER_GROUPS_AFTER} rows"
else
    harness_bad "9: core_peer_groups row count unchanged" "changed: ${PEER_GROUPS_BEFORE} -> ${PEER_GROUPS_AFTER}"
fi

FK_COUNT="$(db_query "SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='peers' AND CONSTRAINT_TYPE='FOREIGN KEY';" | tr -d '\r\n ')"
if [ "$FK_COUNT" = "0" ]; then
    harness_ok "10: peers table foreign-key state unchanged" "0 foreign keys (matches the pre-existing, already-documented schema state)"
else
    harness_bad "10: peers table foreign-key state unchanged" "found ${FK_COUNT} foreign key(s) -- unexpected schema change"
fi

FATALS_AFTER="$(fatal_count)"
if [ "$FATALS_AFTER" = "$FATALS_BEFORE" ]; then
    harness_ok "11: no new PHP Fatal Error was produced by this suite's own probing" "Fatal Error count unchanged (${FATALS_BEFORE})"
else
    harness_bad "11: no new PHP Fatal Error was produced by this suite's own probing" "Fatal Error count changed: ${FATALS_BEFORE} -> ${FATALS_AFTER}"
fi

# =============================================================================
# 6. Ordinary application route still works
# =============================================================================

log "==> ordinary application route"

code="$(request GET "/")"
if [ "$code" = "200" ]; then
    harness_ok "12: the ordinary application login route still works" "HTTP $code"
else
    harness_bad "12: the ordinary application login route still works" "HTTP $code (expected 200)"
fi

# =============================================================================
# 7. Filesystem/CLI availability preserved -- the boundary is HTTP-only.
#    docker-entrypoint-initdb.d's own bind mount (compose.yaml) reads
#    snep/install/database directly off the filesystem, never through
#    Apache, so an HTTP-layer deny rule cannot break it; confirmed here by
#    proving the files are still present and syntactically valid on disk.
# =============================================================================

log "==> filesystem/CLI availability preserved"

if $COMPOSE exec -T app test -f "$KNOWN_SCRIPT_FS"; then
    harness_ok "13: known script remains present on disk for filesystem/CLI use" "$KNOWN_SCRIPT_FS exists"
else
    harness_bad "13: known script remains present on disk for filesystem/CLI use" "$KNOWN_SCRIPT_FS missing"
fi

if $COMPOSE exec -T app php -l "$KNOWN_SCRIPT_FS" >/dev/null 2>&1; then
    harness_ok "14: known script is still syntactically valid (php -l)" "no syntax errors"
else
    harness_bad "14: known script is still syntactically valid (php -l)" "php -l reported an error"
fi

if $COMPOSE exec -T db test -f /docker-entrypoint-initdb.d/snep-install/schema.sql; then
    harness_ok "15: db container's install/database bind mount is unaffected" "schema.sql present via the existing read-only volume"
else
    harness_bad "15: db container's install/database bind mount is unaffected" "schema.sql not found at the expected bind-mount path"
fi

harness_complete
