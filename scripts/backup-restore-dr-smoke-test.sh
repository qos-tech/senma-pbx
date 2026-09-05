#!/bin/bash
#
# SENMA real disaster-recovery proof (TASK-0033A, Phases 15-18/26/27).
#
# Deliberately NOT part of `make regression` -- unlike every other suite
# in scripts/regression.sh, this one actually destroys and recreates the
# mag-db, asterisk-etc, and mag-asterisk-var volumes plus the
# setup.conf/arquivos host paths, then rebuilds the whole stack from a
# real backup. Running that on every regression pass would (a) make
# every other suite's shared fixtures/CDR history disappear from under
# them mid-run, since suites in this repo deliberately run serially
# against ONE shared dev stack (see regression.sh's own header), and (b)
# take far longer than an ordinary smoke suite for no proportional
# benefit on every single lint/regression invocation. This is an
# explicit, occasionally-run operational gate: `make backup-restore-smoke`.
# scripts/backup-smoke-test.sh (part of `make regression`) covers the
# safe, non-destructive subset of this same contract on every run.
#
# What this proves, end to end, against a real running dev stack:
#   1. two real PJSIP extensions provisioned through SENMA's own
#      ExtensionsController HTTP flow (not SQL, not hand-written config)
#   2. a real call between them, producing a real CDR row
#   3. `make backup` captures all of it
#   4. the target is ACTUALLY destroyed: mag-db, asterisk-etc, and
#      mag-asterisk-var volumes removed; setup.conf deleted; arquivos/
#      emptied -- not merely restarted
#   5. `make restore` brings a fresh target back to the exact
#      pre-destruction state: the same DB rows (including the
#      pre-destruction CDR row, by uniqueid), the same generated PJSIP
#      config, the same TLS certificate (by checksum), the same secrets
#      (proven indirectly: ODBC/AMI actually reconnect)
#   6. the SAME two extensions re-register (same secrets -- not
#      recreated) and complete a SECOND real call, producing a NEW CDR
#      row, proving the restored provisioning is live and functional,
#      not merely present in a dump
#   7. `docker compose up -d --force-recreate` afterward does not lose
#      any of the restored state (Phase 17)
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
# shellcheck source=lib/backup-lib.sh
source "$SCRIPT_DIR/lib/backup-lib.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
BARESIP_IMAGE="senma-baresip-test:latest"
BARESIP_DOCKERFILE="docker/baresip-test.Dockerfile"
TEMPLATE_DIR="docker/baresip-test"
FIXTURE_MARKER="task0033a-dr-fixture"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
EXT_A=1096
EXT_B=1097
SECRET_A="${FIXTURE_MARKER}-a"
SECRET_B="${FIXTURE_MARKER}-b"

log() { harness_log "$@"; }

harness_require_env DB_NAME DB_ROOT_PASSWORD COMPOSE_PROJECT_NAME

db_query() {
    $COMPOSE exec -T db mariadb -uroot -p"${DB_ROOT_PASSWORD}" "${DB_NAME}" -N -e "$1"
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

create_extension() {
    local ext="$1" secret="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA DR-smoke ${ext}" \
        --data-urlencode "exten=${ext}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "password=${secret}" \
        --data-urlencode "passwordpadlock=" \
        --data-urlencode "calllimit=1" \
        --data-urlencode "email=" \
        --data-urlencode "exten_group[]=1" \
        --data-urlencode "pickup_group=" \
        --data-urlencode "nat_force_rport=1" \
        --data-urlencode "nat_comedia=1" \
        --data-urlencode "qualify=1" \
        --data-urlencode "type=friend" \
        --data-urlencode "directmedia=no" \
        --data-urlencode "dtmf=rfc2833" \
        --data-urlencode "codec=alaw" \
        --data-urlencode "codec1=ulaw" \
        --data-urlencode "codec2=gsm" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/add")"
    if [ "$httpcode" = "302" ]; then rm -f "$body"; return 0; fi
    log "create_extension ${ext} failed (HTTP $httpcode): $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}

delete_extension() {
    local ext="$1" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" \
        --data-urlencode "delete=Delete" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
}

wait_registered() {
    local ext="$1" tries=15
    while [ "$tries" -gt 0 ]; do
        $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${ext}" 2>&1 | grep -q "Contact:.*${ext}/sip:" && return 0
        sleep 1; tries=$((tries-1))
    done
    return 1
}

place_call_and_verify() {
    # Places EXT_A -> EXT_B, verifies ring/answer/establish, hangs up,
    # returns the new CDR row's uniqueid on stdout. Assumes both baresip
    # containers are already running and registered.
    local label="$1"
    local payload len events
    payload="{\"command\":\"dial\",\"params\":\"${EXT_B}\"}"
    len=${#payload}
    events="$(harness_timeout 20 docker run --rm --network "$NETWORK_NAME" "$BARESIP_IMAGE" sh -c \
        "printf '%s:%s,' '$len' '$payload' | timeout 10 nc senma-drsmoke-1096 4444" 2>&1)"

    if echo "$events" | grep -q '"response":true,"ok":true'; then harness_ok "$label: call placed" "dial accepted"; else harness_bad "$label: call placed" "$events"; fi
    if echo "$events" | grep -q '"type":"CALL_RINGING"'; then harness_ok "$label: destination rings" "CALL_RINGING observed"; else harness_bad "$label: destination rings" "no CALL_RINGING"; fi
    if echo "$events" | grep -q '"type":"CALL_ANSWERED"'; then harness_ok "$label: destination answers" "CALL_ANSWERED observed"; else harness_bad "$label: destination answers" "no CALL_ANSWERED"; fi
    if echo "$events" | grep -q '"type":"CALL_ESTABLISHED"'; then harness_ok "$label: call established" "CALL_ESTABLISHED observed"; else harness_bad "$label: call established" "no CALL_ESTABLISHED"; fi

    sleep 5
    $COMPOSE exec -T asterisk asterisk -rx "channel request hangup all" >&2
    sleep 3

    db_query "SELECT uniqueid FROM cdr WHERE src='${EXT_A}' AND dst='${EXT_B}' AND disposition='ANSWERED' ORDER BY calldate DESC, uniqueid DESC LIMIT 1;"
}

# =====================================================================
# 1. Preflight
# =====================================================================

log "==> checking required containers"
harness_require_containers app asterisk db

pjsip_modules_running() {
    $COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>&1 | grep -q "Running" \
        && $COMPOSE exec -T asterisk asterisk -rx 'module show like chan_pjsip.so' 2>&1 | grep -q "Running"
}
harness_retry 5 2 -- pjsip_modules_running || harness_blocked "PJSIP modules not Running -- cannot provision fixtures"

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
NETWORK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
ASTERISK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{.Name}}' | sed 's#^/##')"
[ -n "$NETWORK_NAME" ] && [ -n "$ASTERISK_NAME" ] || harness_blocked "could not resolve the asterisk container's name/network"

# =====================================================================
# 2. Known-state fixtures: two extensions, one pre-destruction call
# =====================================================================

COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "cookie jar" "rm -f '$COOKIEJAR'"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
[ -n "$TEST_HASH" ] || harness_blocked "could not compute admin password hash"
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
[ -n "$ADMIN_CSRF" ] || harness_blocked "could not read admin CSRF token"

log "==> provisioning known-state fixtures: extensions ${EXT_A}/${EXT_B}"
for pair in "${EXT_A}:${SECRET_A}" "${EXT_B}:${SECRET_B}"; do
    IFS=':' read -r ext secret <<< "$pair"
    existing="$(db_query "SELECT canal FROM peers WHERE name='${ext}';")"
    if [ -n "$existing" ]; then
        harness_blocked "peers row for extension '${ext}' already exists (canal='${existing}') -- refusing to overwrite; remove it manually or pick different EXT_A/EXT_B before running make backup-restore-smoke"
    fi
    create_extension "$ext" "$secret" || harness_blocked "provisioning extension ${ext} failed"
    harness_register_cleanup "extension ${ext} (DR-smoke fixture)" "delete_extension ${ext}"
done
harness_ok "fixtures provisioned" "${EXT_A}/${EXT_B} via the real ExtensionsController HTTP flow"

for ext in "$EXT_A" "$EXT_B"; do
    endpoint_visible() { $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${ext}" 2>&1 | grep -q "Endpoint:  ${ext}/${ext}"; }
    harness_retry 5 1 -- endpoint_visible || harness_bad "pjsip endpoint ${ext} visible" "not found after reload"
done
[ "$_HARNESS_FAIL_COUNT" -gt 0 ] && { log "fixture provisioning did not reach Asterisk -- aborting before backup"; harness_complete; }

CERT_SHA_BEFORE="$($COMPOSE exec -T asterisk sha256sum /etc/asterisk/keys/wss-test-cert.pem 2>/dev/null | awk '{print $1}')"
TRANSPORT_COUNT_BEFORE="$(db_query "SELECT COUNT(*) FROM pjsip_transports;")"

log "==> building baresip test image"
harness_timeout 180 docker build -q -t "$BARESIP_IMAGE" -f "$BARESIP_DOCKERFILE" docker >&2 \
    || harness_blocked "failed to build $BARESIP_IMAGE"

CONF_DIR="$(mktemp -d)"
harness_register_best_effort_cleanup "baresip config dir" "rm -rf '$CONF_DIR'"
for pair in "${EXT_A}:${SECRET_A}:manual" "${EXT_B}:${SECRET_B}:auto"; do
    IFS=':' read -r ext secret answermode <<< "$pair"
    mkdir -p "$CONF_DIR/$ext"
    cp "$TEMPLATE_DIR/config.template" "$CONF_DIR/$ext/config"
    sed -e "s|__EXTEN__|${ext}|g" -e "s|__ASTERISK_HOST__|${ASTERISK_NAME}|g" \
        -e "s|__SECRET__|${secret}|g" -e "s|__ANSWERMODE__|${answermode}|g" \
        "$TEMPLATE_DIR/accounts.template" > "$CONF_DIR/$ext/accounts"
done

log "==> starting baresip endpoints (pre-destruction call)"
docker rm -f senma-drsmoke-1096 senma-drsmoke-1097 >/dev/null 2>&1
docker run -d --name senma-drsmoke-1096 --network "$NETWORK_NAME" -v "$CONF_DIR/${EXT_A}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip senma-drsmoke-1096" "docker rm -f senma-drsmoke-1096 >/dev/null 2>&1"
docker run -d --name senma-drsmoke-1097 --network "$NETWORK_NAME" -v "$CONF_DIR/${EXT_B}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
harness_register_best_effort_cleanup "baresip senma-drsmoke-1097" "docker rm -f senma-drsmoke-1097 >/dev/null 2>&1"

wait_registered "$EXT_A" && harness_ok "pre-destruction: ${EXT_A} registered" "contact bound" || harness_bad "pre-destruction: ${EXT_A} registered" "no contact within 15s"
wait_registered "$EXT_B" && harness_ok "pre-destruction: ${EXT_B} registered" "contact bound" || harness_bad "pre-destruction: ${EXT_B} registered" "no contact within 15s"
[ "$_HARNESS_FAIL_COUNT" -gt 0 ] && { log "pre-destruction registration failed -- aborting before backup"; harness_complete; }

PRE_CDR_UNIQUEID="$(place_call_and_verify "pre-destruction")"
if [ -n "$PRE_CDR_UNIQUEID" ]; then
    harness_ok "pre-destruction CDR row exists" "uniqueid=$PRE_CDR_UNIQUEID"
else
    harness_bad "pre-destruction CDR row exists" "no matching CDR row after the pre-destruction call"
fi
[ "$_HARNESS_FAIL_COUNT" -gt 0 ] && { log "pre-destruction call did not produce a CDR row -- aborting before backup"; harness_complete; }

docker rm -f senma-drsmoke-1096 senma-drsmoke-1097 >/dev/null 2>&1

# =====================================================================
# 3. Backup
# =====================================================================

BACKUP_DEST="$(mktemp -d)"
harness_register_best_effort_cleanup "backup destination" "rm -rf '$BACKUP_DEST'"
log "==> running make backup equivalent (scripts/backup.sh)"
if bash "$SCRIPT_DIR/backup.sh" --dest "$BACKUP_DEST" >&2; then
    harness_ok "backup completed" "$(ls "$BACKUP_DEST")"
else
    harness_blocked "backup.sh failed -- refusing to proceed to a destructive test with no backup"
fi
ARCHIVE="$(find "$BACKUP_DEST" -maxdepth 1 -name 'senma-backup-*.tar.gz' | head -1)"
[ -n "$ARCHIVE" ] || harness_blocked "no backup archive produced"

if bash "$SCRIPT_DIR/restore.sh" "$ARCHIVE" --validate-only >&2; then
    harness_ok "backup archive validates" "checksums and manifest OK before destruction"
else
    harness_blocked "backup archive failed its own validation -- refusing to proceed to a destructive test with an unverified backup"
fi

# =====================================================================
# 4. REAL destruction -- past this point the target is actually gone.
# =====================================================================

log "==> DESTROYING target state: mag-db, asterisk-etc, mag-asterisk-var volumes; setup.conf; arquivos/ contents"
$COMPOSE stop app asterisk db >&2
$COMPOSE rm -f app asterisk db >&2 || true
for short in mag-db asterisk-etc mag-asterisk-var; do
    vol="$(blib_volume_name "$short" 2>/dev/null)" || continue
    docker volume rm "$vol" >&2 || true
    log "    removed volume: $vol"
done
rm -f "$REPO_ROOT/snep/includes/setup.conf"
rm -rf "${REPO_ROOT:?}/snep/arquivos"
mkdir -p "$REPO_ROOT/snep/arquivos"
harness_ok "target actually destroyed" "mag-db/asterisk-etc/mag-asterisk-var volumes removed, setup.conf deleted, arquivos/ emptied"

# =====================================================================
# 5. Restore
# =====================================================================

log "==> running make restore equivalent (scripts/restore.sh --confirm)"
if bash "$SCRIPT_DIR/restore.sh" "$ARCHIVE" --confirm >&2; then
    harness_ok "restore completed" "db/asterisk/app started and passed restore.sh's own readiness checks"
else
    harness_bad "restore completed" "restore.sh reported failure -- see output above. The target may be in a partial state; do not treat this stack as usable."
fi
[ "$_HARNESS_FAIL_COUNT" -gt 0 ] && { log "restore failed -- skipping further verification (already FAIL)"; harness_complete; }

# The app container was stopped/removed and recreated by restore.sh --
# any pre-restore PHP session is gone with it (session storage is not on
# a persisted path). Re-login now: the SAME admin row (and its password
# hash set earlier) came back via the DB restore, so the same
# TEST_USER/TEST_PASSWORD still works. Everything below that needs an
# authenticated cookie session (including the extension-delete cleanup
# registered above, which reads $COOKIEJAR/$ADMIN_CSRF by reference at
# cleanup time, not by value at registration time) picks up this fresh
# session automatically.
log "==> re-authenticating against the restored app (fresh session, same restored admin credentials)"
http_login
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
if [ -n "$ADMIN_CSRF" ]; then
    harness_ok "re-authenticated after restore" "fresh session established with the restored admin account"
else
    harness_bad "re-authenticated after restore" "could not read a CSRF token from the restored app -- fixture cleanup below will likely fail too"
fi

# =====================================================================
# 6. DB restore proof (Phase 12) -- not just a psql/mariadb exit code
# =====================================================================

log "==> verifying DB restore: known rows exist, application can query them"
RESTORED_SECRET_A="$(db_query "SELECT secret FROM peers WHERE name='${EXT_A}';")"
RESTORED_SECRET_B="$(db_query "SELECT secret FROM peers WHERE name='${EXT_B}';")"
if [ "$RESTORED_SECRET_A" = "$SECRET_A" ] && [ "$RESTORED_SECRET_B" = "$SECRET_B" ]; then
    harness_ok "extension rows restored with correct secrets" "${EXT_A}/${EXT_B} match pre-destruction values (not freshly recreated)"
else
    harness_bad "extension rows restored with correct secrets" "expected ${SECRET_A}/${SECRET_B}, got '${RESTORED_SECRET_A}'/'${RESTORED_SECRET_B}'"
fi

RESTORED_PRE_CDR="$(db_query "SELECT uniqueid FROM cdr WHERE uniqueid='${PRE_CDR_UNIQUEID}';")"
if [ "$RESTORED_PRE_CDR" = "$PRE_CDR_UNIQUEID" ]; then
    harness_ok "pre-destruction CDR row survived restore" "uniqueid=$PRE_CDR_UNIQUEID"
else
    harness_bad "pre-destruction CDR row survived restore" "uniqueid $PRE_CDR_UNIQUEID not found after restore"
fi

RESTORED_TRANSPORT_COUNT="$(db_query "SELECT COUNT(*) FROM pjsip_transports;")"
if [ "$RESTORED_TRANSPORT_COUNT" = "$TRANSPORT_COUNT_BEFORE" ]; then
    harness_ok "pjsip_transports row count preserved" "$RESTORED_TRANSPORT_COUNT (matches pre-destruction)"
else
    harness_bad "pjsip_transports row count preserved" "expected $TRANSPORT_COUNT_BEFORE, got $RESTORED_TRANSPORT_COUNT"
fi

REPORT_JSON="$(curl -sS -u "${TEST_USER}:${TEST_PASSWORD}" "${BASE_URL}/modules/default/api/index.php?service=CallsReport&start_date=2020-01-01&start_hour=00:00&end_date=2030-01-01&end_hour=23:59&report_type=analytic&status_answered=1&src=${EXT_A}&order_src=equal" 2>&1)"
if echo "$REPORT_JSON" | grep -qF "\"uniqueid\":\"${PRE_CDR_UNIQUEID}\""; then
    harness_ok "application can query restored data" "CallsReport API returned the pre-destruction CDR row"
else
    harness_bad "application can query restored data" "CallsReport API did not return uniqueid=$PRE_CDR_UNIQUEID"
fi

# =====================================================================
# 7. Asterisk config + certificate restore proof (Phase 13/14)
# =====================================================================

log "==> verifying Asterisk config restore: generated PJSIP sections, certificate"
GENERATED_CONF="$($COMPOSE exec -T asterisk cat /etc/asterisk/snep/senma-pjsip.conf 2>/dev/null)"
if echo "$GENERATED_CONF" | grep -q "^\[${EXT_A}\]" && echo "$GENERATED_CONF" | grep -q "^\[${EXT_B}\]"; then
    harness_ok "generated PJSIP config restored" "senma-pjsip.conf contains [${EXT_A}] and [${EXT_B}]"
else
    harness_bad "generated PJSIP config restored" "expected sections not found in restored senma-pjsip.conf"
fi

CUSTOM_CONF_PRESENT="$($COMPOSE exec -T asterisk sh -c 'test -f /etc/asterisk/custom/preagi.conf && test -f /etc/asterisk/custom/posagi.conf && echo yes' 2>/dev/null | tr -d '\r')"
[ "$CUSTOM_CONF_PRESENT" = "yes" ] && harness_ok "customer custom/ dialplan config restored" "custom/preagi.conf and posagi.conf present" \
    || harness_bad "customer custom/ dialplan config restored" "custom/*.conf missing after restore"

CERT_SHA_AFTER="$($COMPOSE exec -T asterisk sha256sum /etc/asterisk/keys/wss-test-cert.pem 2>/dev/null | awk '{print $1}')"
if [ -n "$CERT_SHA_BEFORE" ] && [ "$CERT_SHA_AFTER" = "$CERT_SHA_BEFORE" ]; then
    harness_ok "TLS certificate restored byte-identical" "sha256 matches pre-destruction ($CERT_SHA_AFTER)"
else
    harness_bad "TLS certificate restored byte-identical" "before=$CERT_SHA_BEFORE after=$CERT_SHA_AFTER"
fi

KEY_MODE="$($COMPOSE exec -T asterisk stat -c '%a' /etc/asterisk/keys/wss-test-key.pem 2>/dev/null | tr -d '\r')"
[ "$KEY_MODE" = "600" ] && harness_ok "TLS private key permissions correct" "mode 600" \
    || harness_bad "TLS private key permissions correct" "expected 600, got '$KEY_MODE'"

WSS_BOUND="$($COMPOSE exec -T asterisk asterisk -rx 'pjsip show transports' 2>&1 | grep -c 'Transport:  *wss ')"
[ "${WSS_BOUND:-0}" -gt 0 ] && harness_ok "WSS transport bound after restore" "pjsip show transports lists wss" \
    || harness_bad "WSS transport bound after restore" "no wss transport listed"

HTTP_TLS_STATUS="$($COMPOSE exec -T asterisk asterisk -rx 'http show status' 2>&1)"
if echo "$HTTP_TLS_STATUS" | grep -qi 'HTTPS Server Enabled'; then
    harness_ok "HTTPS/WSS listener enabled after restore" "http show status reports HTTPS Server Enabled"
else
    harness_bad "HTTPS/WSS listener enabled after restore" "$HTTP_TLS_STATUS"
fi

# See restore.sh's odbc_ready for why this checks active-connection
# count rather than a literal "Connected" string (odbc show all never
# prints one).
odbc_connected() { $COMPOSE exec -T asterisk asterisk -rx 'odbc show all' 2>&1 | grep -qE 'Number of active connections: [1-9]'; }
harness_retry 5 1 -- odbc_connected && harness_ok "ODBC reconnected after restore" "at least one active DSN connection (restored res_odbc.conf matches current .env)" \
    || harness_bad "ODBC reconnected after restore" "no active ODBC connection -- see restore.sh's own diagnostic about credential-rotation mismatch"

# =====================================================================
# 8. Telephony proof (Phase 15) -- same secrets, real re-registration,
#    real second call
# =====================================================================

log "==> post-restore telephony proof: same fixtures re-register, place a second real call"
docker run -d --name senma-drsmoke-1096 --network "$NETWORK_NAME" -v "$CONF_DIR/${EXT_A}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2
docker run -d --name senma-drsmoke-1097 --network "$NETWORK_NAME" -v "$CONF_DIR/${EXT_B}:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >&2

REG_A_OK=0; REG_B_OK=0
if wait_registered "$EXT_A"; then
    harness_ok "post-restore: ${EXT_A} re-registers with restored secret" "contact bound within 15s, fixture not recreated"
    REG_A_OK=1
else
    harness_bad "post-restore: ${EXT_A} re-registers with restored secret" "no contact within 15s"
fi
if wait_registered "$EXT_B"; then
    harness_ok "post-restore: ${EXT_B} re-registers with restored secret" "contact bound within 15s"
    REG_B_OK=1
else
    harness_bad "post-restore: ${EXT_B} re-registers with restored secret" "no contact within 15s"
fi

if [ "$REG_A_OK" -eq 1 ] && [ "$REG_B_OK" -eq 1 ]; then
    POST_CDR_UNIQUEID="$(place_call_and_verify "post-restore")"
    if [ -n "$POST_CDR_UNIQUEID" ] && [ "$POST_CDR_UNIQUEID" != "$PRE_CDR_UNIQUEID" ]; then
        harness_ok "post-restore call produced a NEW CDR row" "uniqueid=$POST_CDR_UNIQUEID (distinct from pre-destruction row)"
    else
        harness_bad "post-restore call produced a NEW CDR row" "got '$POST_CDR_UNIQUEID', expected a new uniqueid distinct from $PRE_CDR_UNIQUEID"
    fi
else
    harness_bad "post-restore call produced a NEW CDR row" "skipped -- one or both endpoints did not re-register"
fi

# =====================================================================
# 9. Container-recreate proof (Phase 17)
# =====================================================================

log "==> proving docker compose up -d --force-recreate does not lose restored state"
$COMPOSE up -d --force-recreate app asterisk db >&2
recreate_ready() { $COMPOSE ps app asterisk db 2>/dev/null | grep -c "(healthy)" | grep -q '^3$'; }
if harness_retry 30 2 -- recreate_ready; then
    harness_ok "stack healthy after --force-recreate" "app/asterisk/db all healthy again"
else
    harness_bad "stack healthy after --force-recreate" "not all three reported healthy within ~60s"
fi

RECREATE_SECRET_A="$(db_query "SELECT secret FROM peers WHERE name='${EXT_A}';")"
[ "$RECREATE_SECRET_A" = "$SECRET_A" ] && harness_ok "restored extension survives --force-recreate" "secret unchanged" \
    || harness_bad "restored extension survives --force-recreate" "expected $SECRET_A, got '$RECREATE_SECRET_A'"

# --force-recreate above just replaced the app container again -- another
# fresh session, same reasoning as the post-restore re-login. Cleanup's
# delete_extension calls (registered earlier, read $COOKIEJAR/$ADMIN_CSRF
# by reference at cleanup time) need this to still work.
log "==> re-authenticating once more after --force-recreate (for fixture cleanup below)"
http_login
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
[ -n "$ADMIN_CSRF" ] || log "WARNING: could not re-establish a session after --force-recreate -- fixture cleanup below will likely fail and need manual removal via the admin UI"

# =====================================================================
# 10. Cleanup -- harness_complete runs the registered extension deletes
#     (HTTP flow) and best-effort baresip/tempdir cleanup, LIFO.
# =====================================================================

harness_complete
