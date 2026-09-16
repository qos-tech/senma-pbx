#!/bin/bash
#
# TASK-0035E9: secure initial admin credential bootstrap lifecycle smoke.
#
# Proves:
#   - fresh sentinel -> secret file 0600 + canonical hash auth
#   - idempotent re-run (same secret, no regeneration)
#   - existing valid admin is not reset / no secret created
#   - restore-like state (valid admin, no secret) stays untouched
#   - retrieval / clear make targets
#   - no plaintext in bootstrap stdout
#   - known default admin123 / admin/admin hashes stay absent from seed
#   - backup path does not archive secrets/
#
# Touches the shared `admin` row only under harness cleanup that restores
# the SmokeTest123! MD5-era baseline used by this project's other suites.
# Never commits plaintext. Never weakens secret mode.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
ADMIN_USER="admin"
ADMIN_PASSWORD="SmokeTest123!"
SECRET_FILE="$REPO_ROOT/secrets/bootstrap-admin-password"
SEED_FILE="$REPO_ROOT/snep/install/database/system_data.sql"
BACKUP_SCRIPT="$REPO_ROOT/scripts/backup.sh"

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" -N -e "$1" 2>/dev/null | tr -d '\r'
}

app_exec() {
    $COMPOSE exec -T app sh -c "$1"
}

file_mode() {
    stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1"
}

harness_require_env DB_USER DB_PASSWORD DB_NAME
harness_require_containers app db

# Ensure secrets mount is present (compose.yaml TASK-0035E9).
if ! app_exec 'test -d /run/senma/secrets'; then
    harness_blocked "app container missing /run/senma/secrets mount -- recreate via ensure-dev-stack after compose.yaml change"
fi

ADMIN_HASH="$(printf '%s' "$ADMIN_PASSWORD" | md5sum | awk '{print $1}')"
ORIGINAL_HASH="$(db_query "SELECT password FROM users WHERE name='${ADMIN_USER}' LIMIT 1;")"
[ -n "$ORIGINAL_HASH" ] || harness_blocked "admin user row missing"

harness_register_cleanup "admin password restored" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"UPDATE users SET password='${ADMIN_HASH}' WHERE name='${ADMIN_USER}';\" >/dev/null"
harness_register_best_effort_cleanup "bootstrap secret removed" "rm -f '$SECRET_FILE'"

# -----------------------------------------------------------------------------
log "==> Negative: install seed must not ship known default credentials"
# -----------------------------------------------------------------------------
if ! grep -v '^--' "$SEED_FILE" | grep -q '0192023a7bbd73250516f069df18b500' \
    && grep -q 'SENMA-BOOTSTRAP-PENDING' "$SEED_FILE" \
    && ! grep -v '^--' "$SEED_FILE" | grep -qiE "VALUES[[:space:]]*\\([[:space:]]*'admin'[[:space:]]*,[[:space:]]*'admin"; then
    harness_ok "1: seed has sentinel, no admin123 md5, no admin/admin literal" "system_data.sql"
else
    harness_bad "1: seed has sentinel, no admin123 md5, no admin/admin literal" "unexpected seed content"
fi

if ! grep -q 'bootstrap-admin-password' "$BACKUP_SCRIPT" \
    && ! grep -qE '(^|[^a-zA-Z])secrets/bootstrap' "$BACKUP_SCRIPT"; then
    harness_ok "2: backup.sh does not include bootstrap plaintext secret" "no bootstrap-admin-password path in backup.sh"
else
    harness_bad "2: backup.sh does not include bootstrap plaintext secret" "backup.sh references bootstrap secret path"
fi

# -----------------------------------------------------------------------------
log "==> Fresh bootstrap"
# -----------------------------------------------------------------------------
db_query "UPDATE users SET password='!SENMA-BOOTSTRAP-PENDING!' WHERE name='${ADMIN_USER}';" >/dev/null
db_query "DELETE FROM login_attempts;" >/dev/null
rm -f "$SECRET_FILE"

OUT1="$(app_exec 'php /usr/local/bin/bootstrap-admin.php' 2>&1)"
if printf '%s' "$OUT1" | grep -qiE 'password:[[:space:]]*[0-9a-f]{16,}'; then
    harness_bad "3: fresh bootstrap does not print plaintext" "leaked in output: $(printf '%s' "$OUT1" | head -c 200)"
elif [ ! -f "$SECRET_FILE" ]; then
    harness_bad "3: fresh bootstrap writes secret file" "missing $SECRET_FILE; out=$(printf '%s' "$OUT1" | head -c 200)"
elif [ "$(file_mode "$SECRET_FILE")" != "600" ]; then
    harness_bad "3: fresh bootstrap secret mode 0600" "mode=$(file_mode "$SECRET_FILE")"
else
    harness_ok "3: fresh bootstrap writes 0600 secret, no plaintext logs" "mode=$(file_mode "$SECRET_FILE")"
fi

PW1="$(tr -d '\r\n' < "$SECRET_FILE" 2>/dev/null || true)"
if [ "${#PW1}" -eq 48 ] && printf '%s' "$PW1" | grep -Eq '^[0-9a-f]{48}$'; then
    harness_ok "4: generated password is 192-bit hex (openssl rand -hex 24 shape)" "len=${#PW1}"
else
    harness_bad "4: generated password is 192-bit hex (openssl rand -hex 24 shape)" "len=${#PW1} value-shape unexpected"
fi

JAR1="$(mktemp)"
harness_register_best_effort_cleanup "fresh jar" "rm -f '$JAR1'"
code="$(curl -sS -c "$JAR1" -b "$JAR1" -o /dev/null -w '%{http_code}' \
    --data-urlencode "user=${ADMIN_USER}" --data-urlencode "password=${PW1}" \
    "${BASE_URL}/index.php/auth/login" 2>/dev/null || echo 000)"
if [ "$code" = "302" ]; then
    harness_ok "5: bootstrapped password authenticates via normal login" "HTTP $code"
else
    harness_bad "5: bootstrapped password authenticates via normal login" "HTTP $code"
fi

DEFAULT_LEAK=0
for bad in admin123 admin snep '1234' "$ADMIN_PASSWORD"; do
    j="$(mktemp)"
    c="$(curl -sS -c "$j" -b "$j" -o /dev/null -w '%{http_code}' \
        --data-urlencode "user=${ADMIN_USER}" --data-urlencode "password=${bad}" \
        "${BASE_URL}/index.php/auth/login" 2>/dev/null || echo 000)"
    rm -f "$j"
    if [ "$c" = "302" ]; then
        harness_bad "6: known defaults do not authenticate after bootstrap" "password='$bad' -> HTTP $c"
        DEFAULT_LEAK=1
        break
    fi
done
if [ "$DEFAULT_LEAK" != "1" ]; then
    harness_ok "6: known defaults do not authenticate after bootstrap" "admin123/admin/snep/1234/SmokeTest123! rejected"
fi

STORED="$(db_query "SELECT password FROM users WHERE name='${ADMIN_USER}';")"
if printf '%s' "$STORED" | grep -q '^\$2[aby]\$'; then
    harness_ok "7: stored admin password is password_hash()-shaped" "bcrypt-like prefix"
else
    harness_bad "7: stored admin password is password_hash()-shaped" "stored prefix unexpected"
fi

# -----------------------------------------------------------------------------
log "==> Idempotency"
# -----------------------------------------------------------------------------
HASH_BEFORE="$STORED"
OUT2="$(app_exec 'php /usr/local/bin/bootstrap-admin.php' 2>&1)"
PW2="$(tr -d '\r\n' < "$SECRET_FILE")"
HASH_AFTER="$(db_query "SELECT password FROM users WHERE name='${ADMIN_USER}';")"
if [ "$PW1" = "$PW2" ] && [ "$HASH_BEFORE" = "$HASH_AFTER" ] \
    && ! printf '%s' "$OUT2" | grep -q 'SENMA initial administrator credentials created'; then
    harness_ok "8: second bootstrap is a no-op (same secret + same hash)" "unchanged"
else
    harness_bad "8: second bootstrap is a no-op (same secret + same hash)" "regenerated or re-announced"
fi

OUTP="$(app_exec 'php /usr/local/bin/bootstrap-admin.php & php /usr/local/bin/bootstrap-admin.php & wait' 2>&1)"
PW3="$(tr -d '\r\n' < "$SECRET_FILE")"
if [ "$PW1" = "$PW3" ]; then
    harness_ok "9: concurrent re-entry does not change secret" "same plaintext"
else
    harness_bad "9: concurrent re-entry does not change secret" "secret changed under concurrency"
fi

# -----------------------------------------------------------------------------
log "==> Retrieval + clear"
# -----------------------------------------------------------------------------
RETRIEVE_OUT="$(bash "$REPO_ROOT/scripts/bootstrap-admin-credentials.sh" 2>&1)"
RETRIEVE_RC=$?
if [ "$RETRIEVE_RC" -eq 0 ] \
    && printf '%s' "$RETRIEVE_OUT" | grep -q '^Username: admin$' \
    && printf '%s' "$RETRIEVE_OUT" | grep -q "^Password: ${PW1}$"; then
    harness_ok "10: make bootstrap-admin-credentials prints username/password" "rc=0"
else
    harness_bad "10: make bootstrap-admin-credentials prints username/password" "rc=$RETRIEVE_RC out=$(printf '%s' "$RETRIEVE_OUT" | head -c 200)"
fi

CLEAR_OUT="$(bash "$REPO_ROOT/scripts/bootstrap-admin-credentials-clear.sh" 2>&1)"
CLEAR_RC=$?
if [ "$CLEAR_RC" -eq 0 ] && [ ! -f "$SECRET_FILE" ]; then
    harness_ok "11: clear removes plaintext secret only" "$CLEAR_OUT"
else
    harness_bad "11: clear removes plaintext secret only" "rc=$CLEAR_RC still_exists=$(test -f "$SECRET_FILE" && echo yes || echo no)"
fi

db_query "DELETE FROM login_attempts;" >/dev/null

JAR2="$(mktemp)"
harness_register_best_effort_cleanup "post-clear jar" "rm -f '$JAR2'"
code="$(curl -sS -c "$JAR2" -b "$JAR2" -o /dev/null -w '%{http_code}' \
    --data-urlencode "user=${ADMIN_USER}" --data-urlencode "password=${PW1}" \
    "${BASE_URL}/index.php/auth/login" 2>/dev/null || echo 000)"
if [ "$code" = "302" ]; then
    harness_ok "12: DB credential still authenticates after clear" "HTTP $code"
else
    harness_bad "12: DB credential still authenticates after clear" "HTTP $code"
fi

CLEAR2_OUT="$(bash "$REPO_ROOT/scripts/bootstrap-admin-credentials-clear.sh" 2>&1)"
if printf '%s' "$CLEAR2_OUT" | grep -qi 'already absent'; then
    harness_ok "13: clear is idempotent when secret already gone" "ok"
else
    harness_bad "13: clear is idempotent when secret already gone" "$CLEAR2_OUT"
fi

ABSENT_RC=0
ABSENT_OUT="$(bash "$REPO_ROOT/scripts/bootstrap-admin-credentials.sh" 2>&1)" || ABSENT_RC=$?
if [ "$ABSENT_RC" -ne 0 ] && printf '%s' "$ABSENT_OUT" | grep -qi 'not found'; then
    harness_ok "14: retrieval refuses clearly when secret absent" "rc=$ABSENT_RC"
else
    harness_bad "14: retrieval refuses clearly when secret absent" "rc=$ABSENT_RC out=$ABSENT_OUT"
fi

if [ ! -f "$SECRET_FILE" ] && [ "$(db_query "SELECT password FROM users WHERE name='${ADMIN_USER}';")" = "$HASH_AFTER" ]; then
    harness_ok "15: failed retrieval does not regenerate/reset anything" "unchanged"
else
    harness_bad "15: failed retrieval does not regenerate/reset anything" "side effect detected"
fi

# -----------------------------------------------------------------------------
log "==> Existing admin / restore-like: must not reset"
# -----------------------------------------------------------------------------
db_query "UPDATE users SET password='${ADMIN_HASH}' WHERE name='${ADMIN_USER}';" >/dev/null
rm -f "$SECRET_FILE"
OUT_EXISTING="$(app_exec 'php /usr/local/bin/bootstrap-admin.php' 2>&1)"
AFTER_EXISTING="$(db_query "SELECT password FROM users WHERE name='${ADMIN_USER}';")"
if [ "$AFTER_EXISTING" = "$ADMIN_HASH" ] && [ ! -f "$SECRET_FILE" ] \
    && ! printf '%s' "$OUT_EXISTING" | grep -q 'SENMA initial administrator credentials created'; then
    harness_ok "16: existing valid admin is not reset; no secret created" "hash unchanged"
else
    harness_bad "16: existing valid admin is not reset; no secret created" "hash or secret changed"
fi

OUT_RESTART="$(app_exec 'php /usr/local/bin/bootstrap-admin.php' 2>&1)"
AFTER_RESTART="$(db_query "SELECT password FROM users WHERE name='${ADMIN_USER}';")"
if [ "$AFTER_RESTART" = "$ADMIN_HASH" ] && [ ! -f "$SECRET_FILE" ]; then
    harness_ok "17: restart/bootstrap lifecycle does not change existing admin" "unchanged"
else
    harness_bad "17: restart/bootstrap lifecycle does not change existing admin" "changed"
fi

if ! grep -E 'password: \{\$plaintext\}|password: \{\$|password: \"\{\$' "$REPO_ROOT/docker/bootstrap-admin.php"; then
    harness_ok "18: bootstrap source has no plaintext password log template" "ok"
else
    harness_bad "18: bootstrap source has no plaintext password log template" "template still present"
fi

db_query "UPDATE users SET password='!SENMA-BOOTSTRAP-PENDING!' WHERE name='${ADMIN_USER}';" >/dev/null
rm -f "$SECRET_FILE"
app_exec 'php /usr/local/bin/bootstrap-admin.php' >/dev/null 2>&1 || true
MODE="$(file_mode "$SECRET_FILE" 2>/dev/null || echo missing)"
if [ "$MODE" = "600" ]; then
    harness_ok "19: secret permission contract is 0600 (not group/world readable)" "mode=$MODE"
else
    harness_bad "19: secret permission contract is 0600 (not group/world readable)" "mode=$MODE"
fi

if [ "$MODE" != "666" ] && [ "$MODE" != "777" ] && [ "$MODE" != "644" ] && [ "$MODE" != "664" ]; then
    harness_ok "20: secret is not 0644/0664/0666/0777" "mode=$MODE"
else
    harness_bad "20: secret is not 0644/0664/0666/0777" "mode=$MODE"
fi

harness_complete
