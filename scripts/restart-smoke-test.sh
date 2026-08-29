#!/bin/bash
#
# SENMA explicit Asterisk restart control smoke test (TASK-0021).
#
# *** WARNING: THIS SCRIPT RESTARTS THE DEV ASTERISK CONTAINER MULTIPLE
# *** TIMES, INCLUDING WHILE A REAL CALL IS ACTIVE. It only ever does so
# *** through SENMA's own real, authenticated HTTP restart endpoints
# *** (SystemstatusController::restartDispatchAction()) -- never a raw
# *** `docker restart`/Docker socket/host command -- proving the actual
# *** feature works, not just the underlying Asterisk CLI capability
# *** already proven by TASK-0020/TASK-0021's own investigation.
#
# Deliberately kept SEPARATE from `make smoke`/`make transport-smoke`,
# per this task's own explicit instruction, and is NEVER invoked
# implicitly by either.
#
# Proves, end to end, against a running `make dev` Docker environment:
#
#   HTTP POST to SystemstatusController::restartDispatchAction()
#   -> Snep_Asterisk_Operations::dispatchGraceful()/dispatchNow()
#   -> a bounded, purpose-built AMI exchange (never the 60s-blocking
#      Asterisk_AMI::wait_response() default) issues the real
#      `core restart gracefully`/`core restart now` command
#   -> Snep_Asterisk_Operations::getRestartState(), polled via
#      SystemstatusController::restartStatusAction(), reports
#      RESTART_PENDING/RECOVERING/RUNNING derived from real,
#      independently-bounded AMI probes -- never DB state, never the
#      dispatch call's own (uninformative) return value
#
# A. idle graceful restart: dispatch, recovery, healthy again.
# B. active-call graceful restart: a real call (two baresip containers,
#    two SENMA-provisioned PJSIP extensions, exactly the mechanism
#    call-smoke-test.sh already established) stays up while the restart
#    is pending, the CLI genuinely locks out ("cannot be run during
#    shutdown"), the call is ended from the client side (mirroring
#    TASK-0021's own investigation -- there is no CLI/AMI way to force
#    this from the server side once pending), and only then does the
#    restart complete.
# C. immediate restart with an active call: the call is dropped
#    immediately and recovery still completes within budget.
#
# See docs/tasks/0021-asterisk-operational-restart.md for the full
# investigation and implementation evidence this script exercises.
#
# D. Existing suites recovering after a restart is validated by running
# `make call-smoke`/`make trunk-smoke`/`make transport-smoke` AFTER this
# script in the same environment -- not duplicated here, matching how
# the existing smoke scripts already avoid invoking each other.
#
# Exit code: 0 if every check PASSes; 1 if any check FAILs.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
BARESIP_IMAGE="senma-baresip-test:latest"
BARESIP_DOCKERFILE="docker/baresip-test.Dockerfile"
TEMPLATE_DIR="docker/baresip-test"
FIXTURE_SECRET_MARKER="task0021-fixture"
TEST_USER="admin"
TEST_PASSWORD="SmokeTest123!"
EXT_A=1096
EXT_B=1097
SECRET_A="${FIXTURE_SECRET_MARKER}-a"
SECRET_B="${FIXTURE_SECRET_MARKER}-b"

CREATED_A=0
CREATED_B=0
CONF_DIR=""
COOKIEJAR=""

log()  { harness_log "$@"; }
ok()   { harness_ok "$1" "$2"; }
bad()  { harness_bad "$1" "$2"; }

# stop() preserves every existing call site's syntax (`stop "reason"`)
# unchanged -- it now classifies BLOCKED (via the shared harness lib)
# instead of an ad hoc `cleanup; exit 1`.
stop() {
    harness_blocked "$*"
}

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
}

# login_fixture <user> <password> -- like http_login(), but for an
# arbitrary fixture user against whatever $COOKIEJAR currently points at
# (TASK-0022's authorization section swaps $COOKIEJAR between the admin
# jar and each fixture user's own jar).
login_fixture() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${1}&password=${2}" "${BASE_URL}/index.php/auth/login"
}

# asterisk_uptime_seconds -- parses `core show uptime`'s "System uptime:"
# line into total seconds. TASK-0022's own investigation proved this is
# a reliable ground-truth marker: a real restart resets it to single
# digits, while a rejected request leaves it climbing normally.
asterisk_uptime_seconds() {
    local raw d=0 h=0 m=0 s=0
    raw="$($COMPOSE exec -T asterisk asterisk -rx 'core show uptime' 2>&1)"
    d="$(echo "$raw" | grep -oE '[0-9]+ day' | grep -oE '[0-9]+' | head -1)"
    h="$(echo "$raw" | grep -oE '[0-9]+ hour' | grep -oE '[0-9]+' | head -1)"
    m="$(echo "$raw" | grep -oE '[0-9]+ minute' | grep -oE '[0-9]+' | head -1)"
    s="$(echo "$raw" | grep -oE '[0-9]+ second' | grep -oE '[0-9]+' | head -1)"
    echo $(( ${d:-0}*86400 + ${h:-0}*3600 + ${m:-0}*60 + ${s:-0} ))
}

# restart_csrf_token -- scrape the confirmation page's one-shot token,
# exactly how the real browser page's own JS does (index.phtml's
# restartCsrfToken variable).
restart_csrf_token() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" "${BASE_URL}/index.php/default/systemstatus" \
        | grep -o 'restartCsrfToken = "[a-f0-9]*"' | sed -e 's/.*"\(.*\)"/\1/'
}

# restart_status -- one JSON snapshot from the real polling endpoint.
restart_status() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" "${BASE_URL}/index.php/default/systemstatus/restart-status"
}

restart_status_field() {
    restart_status | grep -o "\"$1\":\"[^\"]*\"" | head -1 | sed -e "s/\"$1\":\"//" -e 's/"$//'
}

# dispatch_restart <mode> -- POST to the real restartDispatchAction()
# using a freshly-scraped CSRF token, exactly like the real page.
dispatch_restart() {
    local mode="$1" token
    token="$(restart_csrf_token)"
    if [ -z "$token" ]; then
        log "dispatch_restart(${mode}): could not scrape a CSRF token from the confirmation page"
        return 1
    fi
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -X POST \
        --data-urlencode "mode=${mode}" --data-urlencode "csrf_token=${token}" \
        "${BASE_URL}/index.php/default/systemstatus/restart-dispatch"
}

# wait_for_restart_state <expected_state> <max_seconds> -- polls
# restart-status once per second. Bounded, never hammering faster than
# once/second and never unbounded, per this task's own explicit
# instruction.
wait_for_restart_state() {
    local expected="$1" max="$2" attempt state
    for attempt in $(seq 1 "$max"); do
        state="$(restart_status_field state)"
        if [ "$state" = "$expected" ]; then
            return 0
        fi
        sleep 1
    done
    log "wait_for_restart_state(${expected}): last observed state was '${state}' after ${max}s"
    return 1
}

create_extension() {
    local ext="$1" secret="$2" body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA restart-smoke ${ext}" \
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
        "${BASE_URL}/index.php/default/extensions/add")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "create_extension ${ext} failed (HTTP $httpcode): $(head -c 300 "$body")"
    rm -f "$body"
    return 1
}

delete_extension() {
    local ext="$1" httpcode body
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "id=${ext}" --data-urlencode "delete=Delete" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    if [ "$httpcode" = "302" ]; then
        rm -f "$body"
        return 0
    fi
    log "delete_extension ${ext} failed (HTTP $httpcode): $(grep -o 'Server Message[^<]*' "$body" || head -c 300 "$body")"
    rm -f "$body"
    return 1
}

wait_registered() {
    local ext="$1" attempt
    for attempt in $(seq 1 15); do
        if $COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoint ${ext}" 2>&1 | grep -q "Contact:.*${ext}/sip:"; then
            return 0
        fi
        sleep 1
    done
    return 1
}

baresip_dial() {
    local container="$1" target="$2" payload len
    payload="{\"command\":\"dial\",\"params\":\"${target}\"}"
    len=${#payload}
    docker run --rm --network "$NETWORK_NAME" "$BARESIP_IMAGE" sh -c \
        "printf '%s:%s,' '$len' '$payload' | timeout 10 nc ${container} 4444" 2>&1
}

baresip_hangup() {
    local container="$1" payload len
    payload='{"command":"hangup"}'
    len=${#payload}
    docker run --rm --network "$NETWORK_NAME" "$BARESIP_IMAGE" sh -c \
        "printf '%s:%s,' '$len' '$payload' | timeout 6 nc ${container} 4444" >/dev/null 2>&1
}

# delete_extension_with_retry <ext> -- this suite's whole purpose is to
# restart the shared Asterisk instance multiple times right up until the
# moment cleanup runs; a config-reload-dependent delete
# (ExtensionsController::removeAction() -> Snep_PjsipConf::loadConfFromDb()
# -> AMI "module reload res_pjsip.so") can race a restart's last few
# seconds of settling even after Snep_Asterisk_Operations::getRestartState()
# has already reported RUNNING (TASK-0027 finding, live-observed:
# uptime 37s at the moment of a delete failure right after this suite's
# own final restart). A short bounded retry absorbs exactly that benign
# timing window without touching TASK-0021's restart-readiness product
# code or masking a genuine, persistent delete failure.
delete_extension_with_retry() {
    local ext="$1" attempt
    for attempt in 1 2 3; do
        if delete_extension "$ext"; then
            return 0
        fi
        log "delete of extension ${ext} did not return 302 (attempt ${attempt}/3) -- Asterisk may still be settling after this suite's own restarts, retrying in 2s"
        sleep 2
    done
    return 1
}

cleanup() {
    log "==> cleanup"
    local failed=0
    docker rm -f senma-restartsmoke-a senma-restartsmoke-b >/dev/null 2>&1
    [ -n "$CONF_DIR" ] && rm -rf "$CONF_DIR"
    if [ -n "$COOKIEJAR" ]; then
        if [ "$CREATED_A" = "1" ]; then
            if delete_extension_with_retry "$EXT_A"; then
                log "removed fixture extension ${EXT_A}"
            else
                log "WARNING: HTTP delete of ${EXT_A} did not return 302 after retries -- may need manual cleanup"
                failed=1
            fi
        fi
        if [ "$CREATED_B" = "1" ]; then
            if delete_extension_with_retry "$EXT_B"; then
                log "removed fixture extension ${EXT_B}"
            else
                log "WARNING: HTTP delete of ${EXT_B} did not return 302 after retries -- may need manual cleanup"
                failed=1
            fi
        fi
        rm -f "$COOKIEJAR"
    fi
    return "$failed"
}
harness_register_cleanup "restart-smoke fixtures (sections A-D)" "cleanup"

# --- 0. Safety guards: confirm the controlled dev topology, refuse otherwise --

log "==> checking required containers"
harness_require_containers app asterisk db

harness_require_env DB_USER DB_PASSWORD DB_NAME

ASTERISK_CID="$($COMPOSE ps -q asterisk)"
ASTERISK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{.Name}}' | sed 's#^/##')"
NETWORK_NAME="$(docker inspect "$ASTERISK_CID" --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
if [ -z "$ASTERISK_NAME" ] || [ -z "$NETWORK_NAME" ]; then
    stop "could not resolve the asterisk container's name/network via docker inspect"
fi
case "$ASTERISK_NAME" in
    *asterisk*) : ;;
    *) stop "resolved container name '${ASTERISK_NAME}' does not look like this project's dev asterisk service -- refusing to restart an unexpected container" ;;
esac
log "asterisk container: $ASTERISK_NAME  network: $NETWORK_NAME (this script WILL restart it multiple times)"

# --- 1. Log in ---------------------------------------------------------

COOKIEJAR="$(mktemp)"
# NOT separately registered here: cleanup() (registered above, right
# after its own definition) already removes $COOKIEJAR itself as its
# last step, AFTER using it to authenticate the extension deletes.
# TASK-0027 finding, live-reproduced: a separate best-effort registration
# for this same file, added here, ran in LIFO order BEFORE cleanup()
# (registered earlier = runs later) and deleted the admin cookiejar out
# from under it -- every subsequent delete_extension call in cleanup()
# then went out unauthenticated (silently rendering the login page,
# HTTP 200) and "failed cleanup" was actually "cleanup never had a
# valid session to act with." Fixed by removing the redundant
# registration entirely -- cleanup() already owns this file's lifecycle.
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$TEST_HASH" ]; then
    harness_blocked "could not compute the ${TEST_USER} password hash via the app container"
fi
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
http_login
ok "authenticated session" "logged in as ${TEST_USER}"

# --- A. idle graceful restart -------------------------------------------

log "==> A: idle graceful restart"
IDLE_CALLS="$($COMPOSE exec -T asterisk asterisk -rx 'core show channels count' 2>&1 | grep -o '^[0-9]* active calls' | grep -o '^[0-9]*')"
if [ "${IDLE_CALLS:-0}" != "0" ]; then
    stop "expected 0 active calls before the idle restart test, found ${IDLE_CALLS} -- refusing to proceed against a non-idle environment"
fi
DISPATCH_A="$(dispatch_restart graceful)"
if echo "$DISPATCH_A" | grep -q '"ok":true'; then
    ok "idle graceful dispatch accepted" "$DISPATCH_A"
else
    bad "idle graceful dispatch accepted" "$DISPATCH_A"
fi
if wait_for_restart_state RUNNING 30; then
    ok "idle graceful recovery" "reached RUNNING within 30s"
else
    bad "idle graceful recovery" "did not reach RUNNING within 30s"
fi

# --- B. active-call graceful restart ------------------------------------

log "==> B: active-call graceful restart"
# TASK-0027: previously a hard stop() with no recovery attempt at all --
# a stale fixture from any prior interrupted run permanently blocked
# every later run (live-confirmed during TASK-0027's own validation:
# extension 1096, secret 'task0021-fixture-a', was found left over from
# an earlier interrupted run). Now mirrors call-smoke-test.sh/
# trunk-smoke-test.sh's own established recovery pattern: only a peers
# row carrying this script's own fixture-secret marker is removed, via
# the supported HTTP delete path, before re-creating.
for pair in "${EXT_A}:${SECRET_A}:CREATED_A" "${EXT_B}:${SECRET_B}:CREATED_B"; do
    IFS=':' read -r ext secret flagvar <<< "$pair"
    existing_canal="$(db_query "SELECT canal FROM peers WHERE name='${ext}';")"
    existing_secret="$(db_query "SELECT secret FROM peers WHERE name='${ext}';")"
    if [ -n "$existing_canal" ]; then
        if [ "$existing_canal" = "PJSIP/${ext}" ] && [[ "$existing_secret" == "${FIXTURE_SECRET_MARKER}"* ]]; then
            log "extension ${ext} is a leftover restart-smoke fixture from a prior interrupted run -- removing via the supported HTTP delete flow before re-creating"
            delete_extension "$ext" || stop "found a leftover restart-smoke fixture for extension ${ext} but the supported HTTP delete flow did not return 302 -- refusing to proceed with a raw SQL fallback"
        else
            stop "peers row for extension '${ext}' already exists (canal='${existing_canal}') and is NOT a restart-smoke fixture. Refusing to overwrite real/unknown data. Remove it manually before running make restart-smoke."
        fi
    fi
    if create_extension "$ext" "$secret"; then
        printf -v "$flagvar" '1'
    else
        stop "creating extension ${ext} via the real UI flow failed"
    fi
done
ok "call fixtures provisioned" "${EXT_A}/${EXT_B} via the real ExtensionsController::addAction() HTTP flow"

docker build -q -t "$BARESIP_IMAGE" -f "$BARESIP_DOCKERFILE" docker >/dev/null
CONF_DIR="$(mktemp -d)"
for pair in "${EXT_A}:${SECRET_A}:manual:a" "${EXT_B}:${SECRET_B}:auto:b"; do
    IFS=':' read -r ext secret answermode label <<< "$pair"
    mkdir -p "$CONF_DIR/$label"
    cp "$TEMPLATE_DIR/config.template" "$CONF_DIR/$label/config"
    sed -e "s|__EXTEN__|${ext}|g" -e "s|__ASTERISK_HOST__|${ASTERISK_NAME}|g" \
        -e "s|__SECRET__|${secret}|g" -e "s|__ANSWERMODE__|${answermode}|g" \
        "$TEMPLATE_DIR/accounts.template" > "$CONF_DIR/$label/accounts"
done
docker rm -f senma-restartsmoke-a senma-restartsmoke-b >/dev/null 2>&1
docker run -d --name senma-restartsmoke-a --network "$NETWORK_NAME" \
    -v "$CONF_DIR/a:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >/dev/null
docker run -d --name senma-restartsmoke-b --network "$NETWORK_NAME" \
    -v "$CONF_DIR/b:/root/.baresip" "$BARESIP_IMAGE" baresip -f /root/.baresip >/dev/null

if wait_registered "$EXT_A" && wait_registered "$EXT_B"; then
    ok "baresip endpoints registered" "${EXT_A} and ${EXT_B} both show a Contact"
else
    stop "baresip endpoints did not register within 15s -- cannot proceed with the active-call cases"
fi

DIAL_B="$(baresip_dial senma-restartsmoke-a "$EXT_B")"
if echo "$DIAL_B" | grep -q '"type":"CALL_ESTABLISHED"'; then
    ok "call established" "${EXT_A} -> ${EXT_B}"
else
    stop "call did not reach CALL_ESTABLISHED: $DIAL_B"
fi

DISPATCH_B="$(dispatch_restart graceful)"
CALLS_AT_DISPATCH="$(echo "$DISPATCH_B" | grep -o '"active_calls_at_dispatch":[0-9]*' | grep -o '[0-9]*$')"
if [ "$CALLS_AT_DISPATCH" = "1" ]; then
    ok "active call count captured at dispatch" "active_calls_at_dispatch=1"
else
    bad "active call count captured at dispatch" "expected 1, got '${CALLS_AT_DISPATCH}' ($DISPATCH_B)"
fi

sleep 3
STATE_WHILE_ACTIVE="$(restart_status_field state)"
CHANNELS_WHILE_PENDING="$($COMPOSE exec -T asterisk asterisk -rx 'core show channels count' 2>&1)"
# TASK-0021 evidence: once genuinely RESTART_PENDING, the Asterisk CLI
# itself locks out ("cannot be run during shutdown") for EVERY command,
# including a plain channel count -- this is the documented, expected
# lockout, not a sign the call dropped. "2 active channels" is only
# observable in the brief window before the lockout begins; the lockout
# message itself is the (indirect) proof the restart is still waiting.
if [ "$STATE_WHILE_ACTIVE" = "RESTART_PENDING" ] \
    && { echo "$CHANNELS_WHILE_PENDING" | grep -q '^2 active channels' \
      || echo "$CHANNELS_WHILE_PENDING" | grep -q 'cannot be run during shutdown'; }; then
    ok "graceful restart waits for the active call" "state=RESTART_PENDING; CLI: $(echo "$CHANNELS_WHILE_PENDING" | head -1)"
else
    bad "graceful restart waits for the active call" "state='${STATE_WHILE_ACTIVE}', channels: $(echo "$CHANNELS_WHILE_PENDING" | head -1)"
fi

baresip_hangup senma-restartsmoke-a
if wait_for_restart_state RUNNING 30; then
    ok "graceful restart completes after call ends" "reached RUNNING within 30s of hangup"
else
    bad "graceful restart completes after call ends" "did not reach RUNNING within 30s"
fi

FINAL_CHANNELS_B="$($COMPOSE exec -T asterisk asterisk -rx 'core show channels count' 2>&1)"
if echo "$FINAL_CHANNELS_B" | grep -q '^0 active channels'; then
    ok "no stale channel after graceful restart" "0 active channels"
else
    bad "no stale channel after graceful restart" "$(echo "$FINAL_CHANNELS_B" | head -1)"
fi

# --- C. immediate restart with an active call ---------------------------

log "==> C: immediate restart with an active call"
if wait_registered "$EXT_A" && wait_registered "$EXT_B"; then
    ok "endpoints re-registered after graceful restart" "${EXT_A} and ${EXT_B} both show a Contact again"
else
    bad "endpoints re-registered after graceful restart" "did not re-register within 15s"
fi

DIAL_C="$(baresip_dial senma-restartsmoke-a "$EXT_B")"
if echo "$DIAL_C" | grep -q '"type":"CALL_ESTABLISHED"'; then
    ok "second call established" "${EXT_A} -> ${EXT_B}"
else
    stop "second call did not reach CALL_ESTABLISHED: $DIAL_C"
fi

DISPATCH_C="$(dispatch_restart now)"
if echo "$DISPATCH_C" | grep -q '"ok":true'; then
    ok "immediate dispatch accepted" "$DISPATCH_C"
else
    bad "immediate dispatch accepted" "$DISPATCH_C"
fi

if wait_for_restart_state RUNNING 30; then
    ok "immediate restart recovery" "reached RUNNING within 30s"
else
    bad "immediate restart recovery" "did not reach RUNNING within 30s"
fi

FINAL_CHANNELS_C="$($COMPOSE exec -T asterisk asterisk -rx 'core show channels count' 2>&1)"
if echo "$FINAL_CHANNELS_C" | grep -q '^0 active channels'; then
    ok "immediate restart dropped the active call" "0 active channels after recovery"
else
    bad "immediate restart dropped the active call" "$(echo "$FINAL_CHANNELS_C" | head -1)"
fi

# --- D. post-restart platform health -------------------------------------

log "==> D: post-restart platform health"
TRANSPORTS_AFTER="$($COMPOSE exec -T asterisk asterisk -rx 'pjsip show transports' 2>&1)"
# TASK-0027 finding: this previously asserted the literal 'Objects
# found: 2', which was already stale before this task -- the seeded
# install data (snep/install/database/system_data.sql) has shipped a
# third default transport (wss, for WebRTC) since TASK-0017/0018, well
# before this restart-smoke check existed, so the literal count could
# never again pass. Checking for the two named transports this check
# actually cares about (udp/tcp) is both correct today and resilient to
# a future additional default transport, unlike a brittle total count.
if echo "$TRANSPORTS_AFTER" | grep -q '^Transport:  tcp ' && echo "$TRANSPORTS_AFTER" | grep -q '^Transport:  udp '; then
    ok "pjsip transports intact" "udp/tcp transports present after restarts"
else
    bad "pjsip transports intact" "$TRANSPORTS_AFTER"
fi
ODBC_AFTER="$($COMPOSE exec -T asterisk asterisk -rx 'odbc show all' 2>&1)"
if echo "$ODBC_AFTER" | grep -q 'Number of active connections: 1'; then
    ok "odbc reconnected" "1 active connection after restarts"
else
    bad "odbc reconnected" "$ODBC_AFTER"
fi
AUDIT_ROWS="$(db_query "SELECT COUNT(*) FROM logs_users WHERE \`table\`='asterisk' AND datetime >= NOW() - INTERVAL 5 MINUTE;")"
if [ "${AUDIT_ROWS:-0}" -ge 3 ]; then
    ok "audit trail recorded" "${AUDIT_ROWS} restart audit rows in the last 5 minutes"
else
    bad "audit trail recorded" "expected at least 3 rows, found '${AUDIT_ROWS}'"
fi

# --- E. authorization (TASK-0022) ----------------------------------------
#
# docs/tasks/0022-system-administration-authorization.md. Proves that
# authentication alone (section A-D used the seeded superuser, admin,
# id_user==1) is NOT sufficient to restart Asterisk: a genuinely
# restricted, non-superuser, zero-permission user is rejected with 403
# before any Asterisk contact, while a DIFFERENT non-superuser user
# holding an explicit default_asterisk-operations_write grant can
# restart successfully -- proving the new permission itself works, not
# merely the id_user==1 bypass every earlier section relies on.

log "==> E: authorization for restart dispatch"

RESTRICTED_USER="restartsmoke-unauthorized"
AUTHORIZED_USER="restartsmoke-authorized"
FIXTURE_PASSWORD="RestartSmoke123!"
RESTRICTED_ID=""
AUTHORIZED_ID=""
RESTRICTED_JAR=""
AUTHORIZED_JAR=""
ADMIN_JAR="$COOKIEJAR"

authz_cleanup() {
    log "==> authorization fixture cleanup"
    # These two users are created via direct SQL (see the comment at
    # their INSERT below -- both UsersController::addAction() and
    # Snep_Users_Manager::add() were found to fatal under PHP 8.4/strict
    # SQL, a pre-existing, separately-documented product defect, not
    # fixed here), so removing them the same way is the only available
    # path, not a "raw SQL cleanup fallback" for a UI-created fixture.
    if [ -n "$RESTRICTED_ID" ]; then
        db_query "DELETE FROM users_permissions WHERE user_id=${RESTRICTED_ID};" >/dev/null 2>&1
        db_query "DELETE FROM users WHERE id=${RESTRICTED_ID};" >/dev/null 2>&1
    fi
    if [ -n "$AUTHORIZED_ID" ]; then
        db_query "DELETE FROM users_permissions WHERE user_id=${AUTHORIZED_ID};" >/dev/null 2>&1
        db_query "DELETE FROM users WHERE id=${AUTHORIZED_ID};" >/dev/null 2>&1
    fi
    [ -n "$RESTRICTED_JAR" ] && rm -f "$RESTRICTED_JAR"
    [ -n "$AUTHORIZED_JAR" ] && rm -f "$AUTHORIZED_JAR"
    return 0
}
# Registered right after cleanup() at definition time -- harness_finalize
# runs registered cleanups LIFO, so authz_cleanup (registered second)
# runs BEFORE cleanup(), matching transport-smoke-test.sh's own
# established convention for combining multiple cleanup phases.
harness_register_cleanup "restart-smoke authorization fixtures (section E)" "authz_cleanup"

for existing_name in "$RESTRICTED_USER" "$AUTHORIZED_USER"; do
    existing="$(db_query "SELECT id FROM users WHERE name='${existing_name}';")"
    if [ -n "$existing" ]; then
        stop "a user named '${existing_name}' already exists (id=${existing}) -- refusing to overwrite. Remove it manually before running make restart-smoke."
    fi
done

# TASK-0022's investigation found the real Users-management HTTP flow
# (UsersController::addAction()) and the manager layer
# (Snep_Users_Manager::add()) both fatal under PHP 8.4/MariaDB strict
# mode, on two genuine, unrelated, pre-existing bugs (a count() on a
# non-Countable return value, and a NOT NULL `dashboard` column with no
# default that add() never populates) -- see
# docs/tasks/0022-system-administration-authorization.md §8. Both are
# documented as separate technical debt, NOT fixed here. Direct SQL,
# supplying every NOT NULL column explicitly, is therefore the lowest
# safe fixture layer, exactly as the investigation used and justified.
FIXTURE_HASH="$($COMPOSE exec -T app php -r "echo md5('${FIXTURE_PASSWORD}');" 2>/dev/null | tr -d '\r')"
db_query "INSERT INTO users (name, password, email, dashboard, profile_id, created, updated)
    VALUES ('${RESTRICTED_USER}', '${FIXTURE_HASH}', 'restartsmoke-unauthorized@example.test', '', 1, NOW(), NOW());" >&2
db_query "INSERT INTO users (name, password, email, dashboard, profile_id, created, updated)
    VALUES ('${AUTHORIZED_USER}', '${FIXTURE_HASH}', 'restartsmoke-authorized@example.test', '', 1, NOW(), NOW());" >&2
RESTRICTED_ID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
AUTHORIZED_ID="$(db_query "SELECT id FROM users WHERE name='${AUTHORIZED_USER}';")"
if [ -z "$RESTRICTED_ID" ] || [ -z "$AUTHORIZED_ID" ]; then
    stop "could not provision authorization test fixtures via direct SQL"
fi
# Both fixtures share profile_id=1 (the only profile that exists, and
# the one that grants nothing -- confirmed empty in the investigation);
# only AUTHORIZED_ID gets an explicit per-user override below. Neither
# fixture is user id 1 and neither inherits any unrestricted behavior.
db_query "INSERT INTO users_permissions (user_id, permission_id, allow, created, updated)
    VALUES (${AUTHORIZED_ID}, 'default_asterisk-operations_write', 1, NOW(), NOW());" >&2
ok "authorization fixtures provisioned" "restricted user id=${RESTRICTED_ID} (profile_id=1, zero grants), authorized user id=${AUTHORIZED_ID} (explicit default_asterisk-operations_write grant)"

PRE_AUTHZ_PROFILES_PERMISSIONS="$(db_query "SELECT COUNT(*) FROM profiles_permissions;")"

# --- E1. AUTHN: unauthenticated dispatch never reaches the action --------

UPTIME_BEFORE_UNAUTH="$(asterisk_uptime_seconds)"
UNAUTH_BODY="$(curl -sS -X POST \
    --data-urlencode "mode=graceful" --data-urlencode "csrf_token=whatever" \
    "${BASE_URL}/index.php/default/systemstatus/restart-dispatch")"
sleep 2
UPTIME_AFTER_UNAUTH="$(asterisk_uptime_seconds)"
if echo "$UNAUTH_BODY" | grep -qi "Login" && [ "$UPTIME_AFTER_UNAUTH" -ge "$UPTIME_BEFORE_UNAUTH" ]; then
    ok "unauthenticated dispatch never reaches restartDispatchAction" "Snep_AuthPlugin rewrote the request to the login page (POST body/method preserved, still just renders the login form); uptime ${UPTIME_BEFORE_UNAUTH}s -> ${UPTIME_AFTER_UNAUTH}s, no reset"
else
    bad "unauthenticated dispatch never reaches restartDispatchAction" "body did not look like the login page, or uptime moved backward (${UPTIME_BEFORE_UNAUTH}s -> ${UPTIME_AFTER_UNAUTH}s)"
fi

# --- E2. AUTHZ: restricted user, graceful, rejected with zero effect -----

RESTRICTED_JAR="$(mktemp)"
COOKIEJAR="$RESTRICTED_JAR"
login_fixture "$RESTRICTED_USER" "$FIXTURE_PASSWORD"

RESTRICTED_TOKEN="$(restart_csrf_token)"
if [ -z "$RESTRICTED_TOKEN" ]; then
    stop "could not scrape a CSRF token for the restricted fixture user -- cannot proceed with authorization checks"
fi

UPTIME_BEFORE_E2="$(asterisk_uptime_seconds)"
RESTRICTED_GRACEFUL_HTTP="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /tmp/restartsmoke-e2.json -w '%{http_code}' -X POST \
    --data-urlencode "mode=graceful" --data-urlencode "csrf_token=${RESTRICTED_TOKEN}" \
    "${BASE_URL}/index.php/default/systemstatus/restart-dispatch")"
RESTRICTED_GRACEFUL_BODY="$(cat /tmp/restartsmoke-e2.json)"
rm -f /tmp/restartsmoke-e2.json
sleep 2
UPTIME_AFTER_E2="$(asterisk_uptime_seconds)"
if [ "$RESTRICTED_GRACEFUL_HTTP" = "403" ] && echo "$RESTRICTED_GRACEFUL_BODY" | grep -q '"ok":false' \
    && [ "$UPTIME_AFTER_E2" -ge "$UPTIME_BEFORE_E2" ]; then
    ok "restricted user graceful restart rejected" "HTTP 403, uptime ${UPTIME_BEFORE_E2}s -> ${UPTIME_AFTER_E2}s (no reset), no RESTART_PENDING created"
else
    bad "restricted user graceful restart rejected" "HTTP ${RESTRICTED_GRACEFUL_HTTP}, body: ${RESTRICTED_GRACEFUL_BODY}, uptime ${UPTIME_BEFORE_E2}s -> ${UPTIME_AFTER_E2}s"
fi

RESTRICTED_STATE_AFTER="$(restart_status_field state)"
if [ "$RESTRICTED_STATE_AFTER" = "RUNNING" ]; then
    ok "no restart-pending state after rejected dispatch" "restart-status still reports RUNNING"
else
    bad "no restart-pending state after rejected dispatch" "restart-status reports '${RESTRICTED_STATE_AFTER}', expected RUNNING"
fi

# --- E3. AUTHZ: restricted user, immediate, with a real call held open ---
# Item 10's explicit "if practical, keep a real test call active" --
# reuses the same baresip fixtures sections B/C already established.

if wait_registered "$EXT_A" && wait_registered "$EXT_B"; then
    DIAL_E3="$(baresip_dial senma-restartsmoke-a "$EXT_B")"
else
    DIAL_E3=""
fi

if echo "$DIAL_E3" | grep -q '"type":"CALL_ESTABLISHED"'; then
    ok "call established for the unauthorized-immediate-restart proof" "${EXT_A} -> ${EXT_B}"

    RESTRICTED_TOKEN2="$(restart_csrf_token)"
    UPTIME_BEFORE_E3="$(asterisk_uptime_seconds)"
    RESTRICTED_NOW_HTTP="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /tmp/restartsmoke-e3.json -w '%{http_code}' -X POST \
        --data-urlencode "mode=now" --data-urlencode "csrf_token=${RESTRICTED_TOKEN2}" \
        "${BASE_URL}/index.php/default/systemstatus/restart-dispatch")"
    RESTRICTED_NOW_BODY="$(cat /tmp/restartsmoke-e3.json)"
    rm -f /tmp/restartsmoke-e3.json
    CHANNELS_AFTER_E3="$($COMPOSE exec -T asterisk asterisk -rx 'core show channels count' 2>&1)"
    UPTIME_AFTER_E3="$(asterisk_uptime_seconds)"

    if [ "$RESTRICTED_NOW_HTTP" = "403" ] && echo "$RESTRICTED_NOW_BODY" | grep -q '"ok":false' \
        && echo "$CHANNELS_AFTER_E3" | grep -q '^2 active channels' \
        && [ "$UPTIME_AFTER_E3" -ge "$UPTIME_BEFORE_E3" ]; then
        ok "restricted user immediate restart rejected, active call survives" "HTTP 403, call still up (2 active channels), uptime ${UPTIME_BEFORE_E3}s -> ${UPTIME_AFTER_E3}s (no reset)"
    else
        bad "restricted user immediate restart rejected, active call survives" "HTTP ${RESTRICTED_NOW_HTTP}, channels: $(echo "$CHANNELS_AFTER_E3" | head -1), uptime ${UPTIME_BEFORE_E3}s -> ${UPTIME_AFTER_E3}s"
    fi

    baresip_hangup senma-restartsmoke-a
    sleep 1
else
    bad "call established for the unauthorized-immediate-restart proof" "could not establish a call to test against (endpoints may not have re-registered) -- immediate-restart-rejection still proven without an active call below"
    RESTRICTED_TOKEN2="$(restart_csrf_token)"
    UPTIME_BEFORE_E3B="$(asterisk_uptime_seconds)"
    RESTRICTED_NOW_HTTP="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' -X POST \
        --data-urlencode "mode=now" --data-urlencode "csrf_token=${RESTRICTED_TOKEN2}" \
        "${BASE_URL}/index.php/default/systemstatus/restart-dispatch")"
    sleep 2
    UPTIME_AFTER_E3B="$(asterisk_uptime_seconds)"
    if [ "$RESTRICTED_NOW_HTTP" = "403" ] && [ "$UPTIME_AFTER_E3B" -ge "$UPTIME_BEFORE_E3B" ]; then
        ok "restricted user immediate restart rejected (no call fixture)" "HTTP 403, uptime not reset"
    else
        bad "restricted user immediate restart rejected (no call fixture)" "HTTP ${RESTRICTED_NOW_HTTP}"
    fi
fi

# --- E4. direct-request bypass shape: wrong method, still 405 -----------

RESTRICTED_GET_HTTP="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
    "${BASE_URL}/index.php/default/systemstatus/restart-dispatch")"
if [ "$RESTRICTED_GET_HTTP" = "405" ]; then
    ok "GET restart-dispatch still 405 for a restricted user" "method rejection happens before authorization is even consulted"
else
    bad "GET restart-dispatch still 405 for a restricted user" "HTTP ${RESTRICTED_GET_HTTP}"
fi

# --- E5. READ-ONLY: restricted user keeps the current System Status audience ---

RESTRICTED_STATUS_HTTP="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' "${BASE_URL}/index.php/default/systemstatus")"
RESTRICTED_POLL_BODY="$(restart_status)"
if [ "$RESTRICTED_STATUS_HTTP" = "200" ] && echo "$RESTRICTED_POLL_BODY" | grep -q '"state"'; then
    ok "restricted user retains read-only System Status access" "systemstatus/index HTTP 200, restart-status still returns a valid state"
else
    bad "restricted user retains read-only System Status access" "systemstatus HTTP ${RESTRICTED_STATUS_HTTP}, restart-status body: ${RESTRICTED_POLL_BODY}"
fi

RESTRICTED_PAGE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" "${BASE_URL}/index.php/default/systemstatus")"
if ! echo "$RESTRICTED_PAGE" | grep -q '<button[^>]*id="btnShowGraceful"'; then
    ok "destructive restart buttons hidden for a restricted user" "no <button id=\"btnShowGraceful\"> in the rendered page"
else
    bad "destructive restart buttons hidden for a restricted user" "button markup present despite lacking the permission"
fi

# --- E6. CSRF remains independent of the new permission -------------------

AUTHORIZED_JAR="$(mktemp)"
COOKIEJAR="$AUTHORIZED_JAR"
login_fixture "$AUTHORIZED_USER" "$FIXTURE_PASSWORD"

AUTHORIZED_PAGE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" "${BASE_URL}/index.php/default/systemstatus")"
if echo "$AUTHORIZED_PAGE" | grep -q '<button[^>]*id="btnShowGraceful"'; then
    ok "restart buttons visible for the explicitly-permissioned user" "server-side can_restart_asterisk flag rendered the controls"
else
    bad "restart buttons visible for the explicitly-permissioned user" "buttons missing despite an explicit default_asterisk-operations_write grant"
fi

NO_TOKEN_HTTP="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' -X POST \
    --data-urlencode "mode=graceful" "${BASE_URL}/index.php/default/systemstatus/restart-dispatch")"
INVALID_TOKEN_HTTP="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' -X POST \
    --data-urlencode "mode=graceful" --data-urlencode "csrf_token=not-a-real-token" \
    "${BASE_URL}/index.php/default/systemstatus/restart-dispatch")"
if [ "$NO_TOKEN_HTTP" = "403" ] && [ "$INVALID_TOKEN_HTTP" = "403" ]; then
    ok "permission does not substitute for CSRF" "missing token -> 403, invalid token -> 403, even with explicit restart permission"
else
    bad "permission does not substitute for CSRF" "missing token -> HTTP ${NO_TOKEN_HTTP}, invalid token -> HTTP ${INVALID_TOKEN_HTTP} (expected 403/403)"
fi

# --- E7. PERMISSION: the explicit grant actually works, both modes ------

AUTHORIZED_TOKEN="$(restart_csrf_token)"
DISPATCH_E7A="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -X POST \
    --data-urlencode "mode=graceful" --data-urlencode "csrf_token=${AUTHORIZED_TOKEN}" \
    "${BASE_URL}/index.php/default/systemstatus/restart-dispatch")"
if echo "$DISPATCH_E7A" | grep -q '"dispatched":true'; then
    ok "non-superuser with explicit permission: graceful dispatch accepted" "$DISPATCH_E7A"
else
    bad "non-superuser with explicit permission: graceful dispatch accepted" "$DISPATCH_E7A"
fi
if wait_for_restart_state RUNNING 30; then
    ok "non-superuser with explicit permission: graceful recovery" "reached RUNNING within 30s"
else
    bad "non-superuser with explicit permission: graceful recovery" "did not reach RUNNING within 30s"
fi

AUTHORIZED_TOKEN2="$(restart_csrf_token)"
DISPATCH_E7B="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -X POST \
    --data-urlencode "mode=now" --data-urlencode "csrf_token=${AUTHORIZED_TOKEN2}" \
    "${BASE_URL}/index.php/default/systemstatus/restart-dispatch")"
if echo "$DISPATCH_E7B" | grep -q '"dispatched":true'; then
    ok "non-superuser with explicit permission: immediate dispatch accepted" "$DISPATCH_E7B"
else
    bad "non-superuser with explicit permission: immediate dispatch accepted" "$DISPATCH_E7B"
fi
if wait_for_restart_state RUNNING 30; then
    ok "non-superuser with explicit permission: immediate recovery" "reached RUNNING within 30s"
else
    bad "non-superuser with explicit permission: immediate recovery" "did not reach RUNNING within 30s"
fi

# --- E8. superuser compatibility: id_user=1 still bypasses, unmodified --

COOKIEJAR="$ADMIN_JAR"
ADMIN_TOKEN="$(restart_csrf_token)"
DISPATCH_E8="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -X POST \
    --data-urlencode "mode=graceful" --data-urlencode "csrf_token=${ADMIN_TOKEN}" \
    "${BASE_URL}/index.php/default/systemstatus/restart-dispatch")"
POST_AUTHZ_PROFILES_PERMISSIONS="$(db_query "SELECT COUNT(*) FROM profiles_permissions;")"
if echo "$DISPATCH_E8" | grep -q '"dispatched":true' && [ "$POST_AUTHZ_PROFILES_PERMISSIONS" = "$PRE_AUTHZ_PROFILES_PERMISSIONS" ]; then
    ok "id_user=1 superuser bypass still works, no profiles_permissions rows added" "admin dispatched successfully; profiles_permissions row count unchanged (${PRE_AUTHZ_PROFILES_PERMISSIONS} -> ${POST_AUTHZ_PROFILES_PERMISSIONS})"
else
    bad "id_user=1 superuser bypass still works, no profiles_permissions rows added" "dispatch: $DISPATCH_E8, profiles_permissions ${PRE_AUTHZ_PROFILES_PERMISSIONS} -> ${POST_AUTHZ_PROFILES_PERMISSIONS}"
fi
if wait_for_restart_state RUNNING 30; then
    ok "admin restart recovery after authorization suite" "reached RUNNING within 30s"
else
    bad "admin restart recovery after authorization suite" "did not reach RUNNING within 30s"
fi

# --- E9. audit trail includes the rejected attempts ----------------------

DENIED_ROWS="$(db_query "SELECT COUNT(*) FROM logs_users WHERE action='RestartDenied' AND datetime >= NOW() - INTERVAL 5 MINUTE;")"
if [ "${DENIED_ROWS:-0}" -ge 2 ]; then
    ok "authorization denials audited" "${DENIED_ROWS} RestartDenied rows in the last 5 minutes"
else
    bad "authorization denials audited" "expected at least 2 RestartDenied rows, found '${DENIED_ROWS}'"
fi

harness_complete
