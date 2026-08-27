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

PASS=0
FAIL=0
declare -a RESULTS=()
CREATED_A=0
CREATED_B=0
CONF_DIR=""
COOKIEJAR=""

log()  { printf '%s\n' "$*" >&2; }
row()  { RESULTS+=("$1|$2|$3"); }
ok()   { row "$1" "PASS" "$2"; PASS=$((PASS+1)); log "PASS: $1 -- $2"; }
bad()  { row "$1" "FAIL" "$2"; FAIL=$((FAIL+1)); log "FAIL: $1 -- $2"; }

print_report() {
    echo
    echo "================================================================"
    printf "%-40s %-8s %s\n" "CHECK" "RESULT" "DETAIL"
    echo "----------------------------------------------------------------"
    for r in "${RESULTS[@]}"; do
        IFS='|' read -r flow status detail <<< "$r"
        printf "%-40s %-8s %s\n" "$flow" "$status" "$detail"
    done
    echo "================================================================"
    echo "PASS: $PASS   FAIL: $FAIL"
    echo "================================================================"
}

stop() {
    log "STOP: $*"
    echo "STOP: $*"
    cleanup
    exit 1
}

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

http_login() {
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
        -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
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
    local ext="$1" httpcode
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${ext}" --data-urlencode "delete=Delete" \
        "${BASE_URL}/index.php/default/extensions/remove")"
    [ "$httpcode" = "302" ]
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

cleanup() {
    trap - EXIT
    log "==> cleanup"
    docker rm -f senma-restartsmoke-a senma-restartsmoke-b >/dev/null 2>&1
    [ -n "$CONF_DIR" ] && rm -rf "$CONF_DIR"
    if [ -n "$COOKIEJAR" ]; then
        if [ "$CREATED_A" = "1" ]; then
            delete_extension "$EXT_A" && log "removed fixture extension ${EXT_A}" \
                || log "WARNING: HTTP delete of ${EXT_A} did not return 302 -- may need manual cleanup"
        fi
        if [ "$CREATED_B" = "1" ]; then
            delete_extension "$EXT_B" && log "removed fixture extension ${EXT_B}" \
                || log "WARNING: HTTP delete of ${EXT_B} did not return 302 -- may need manual cleanup"
        fi
        rm -f "$COOKIEJAR"
    fi
}
trap cleanup EXIT

# --- 0. Safety guards: confirm the controlled dev topology, refuse otherwise --

log "==> checking required containers"
ALL_UP=1
for svc in app asterisk db; do
    if ! $COMPOSE ps "$svc" 2>/dev/null | grep -q "Up"; then
        ALL_UP=0
    fi
done
if [ "$ALL_UP" != "1" ]; then
    bad "containers healthy" "one or more of app/asterisk/db not Up -- run 'make up' first"
    cleanup; trap - EXIT; exit 1
fi
ok "containers healthy" "app, asterisk, db all Up"

: "${DB_USER:?DB_USER must be set (source .env first)}"
: "${DB_PASSWORD:?DB_PASSWORD must be set (source .env first)}"
: "${DB_NAME:?DB_NAME must be set (source .env first)}"

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
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
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
for pair in "${EXT_A}:${SECRET_A}:CREATED_A" "${EXT_B}:${SECRET_B}:CREATED_B"; do
    IFS=':' read -r ext secret flagvar <<< "$pair"
    existing_canal="$(db_query "SELECT canal FROM peers WHERE name='${ext}';")"
    if [ -n "$existing_canal" ]; then
        stop "peers row for extension '${ext}' already exists (canal='${existing_canal}') -- refusing to overwrite. Remove it manually before running make restart-smoke."
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
if echo "$TRANSPORTS_AFTER" | grep -q 'Objects found: 2'; then
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

print_report
cleanup
trap - EXIT
[ "$FAIL" -eq 0 ]
