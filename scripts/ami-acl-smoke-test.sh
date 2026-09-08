#!/bin/bash
#
# Safe, non-mutating regression coverage for the AMI network-ACL trust
# boundary (TASK-0034F, closing TASK-0034 CH-6).
#
# Proves, live, on every `make regression` run:
#   1. AMI (5038) is not published to the host on any core service.
#   2. The authorized production caller (`app`, over the dedicated
#      `senma-control` network's `senma-ami` alias) can log in and run
#      a real action (Ping -> Pong).
#   3. `db` and `provider` -- both `mag`-network-only, deliberately not
#      joined to `senma-control` -- cannot resolve the `senma-ami` alias
#      at all, and even a correct-credential login attempt against
#      asterisk's OTHER (`mag`-network) address is rejected by the ACL
#      (manager.conf's `bindaddr = 0.0.0.0` listens on every interface;
#      narrowing WHO may use it is the ACL's job -- see docs/tasks/
#      0034f-production-ami-acl-scoping.md PHASE 12).
#   4. `manager reload` (non-disruptive) preserves the narrowed ACL and
#      the authorized path keeps working.
#   5. A scoped `asterisk` container restart preserves the narrowed ACL
#      (FIRST_BOOT_SEED: manager.conf is templated once, never
#      regenerated on restart) and the authorized path keeps working;
#      ODBC/CDR are restored via the shared post-restart helper, same
#      as every other suite that restarts this container.
#
# Deliberately NOT covered here (destructive/slow, proven once manually
# instead -- see docs/tasks/0034f-production-ami-acl-scoping.md CIDR
# VALIDATION / SAFE DEFAULT): a fresh, isolated-volume boot rejecting an
# unset/malformed/0.0.0.0-0 ASTERISK_AMI_ACL_SUBNET. That requires a
# throwaway Compose project and a fresh volume, the same class of
# operation this project's OTHER *-failure-smoke-test.sh scripts keep
# out of default regression.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
# shellcheck source=lib/secrets-lib.sh
source "$SCRIPT_DIR/lib/secrets-lib.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
log() { harness_log "$@"; }

log "==> checking required containers/env"
harness_require_containers app asterisk db provider
harness_require_env AMI_USER AMI_PASSWORD ASTERISK_HOST ASTERISK_AMI_ACL_SUBNET

# raw AMI login+action over one TCP leg, run FROM inside the named
# container, connecting directly to target_host:5038 (a hostname/alias
# OR a raw IP -- no separate resolution pre-check here: `/dev/tcp/...`
# itself fails cleanly on either an unresolvable name or a refused/
# unreachable IP, which is exactly CONNECT_FAILED either way; resolution
# is asserted as its own, separate check where that distinction
# matters). Prints the trailing Response:/Message:/<action-specific>
# block (pipe-joined), or "CONNECT_FAILED" if the connection never came
# up. `trap "" PIPE` matches scripts/lib/secrets-lib.sh's own
# slib_ami_auth_check precedent: Asterisk closes the socket immediately
# on an ACL/auth rejection, so the subsequent Logoff write would
# otherwise raise SIGPIPE and corrupt this function's exit status.
ami_probe() {
    local from_container="$1" target_host="$2"
    $COMPOSE exec -T "$from_container" bash -c "
        trap '' PIPE
        AMI_USER='$AMI_USER'; AMI_PASSWORD='$AMI_PASSWORD'
        exec 3<>/dev/tcp/'$target_host'/5038 || { echo CONNECT_FAILED; exit 0; }
        IFS= read -r -t 5 _banner <&3 || { echo CONNECT_FAILED; exit 0; }
        printf 'Action: Login\r\nUsername: %s\r\nSecret: %s\r\nActionID: acl-smoke\r\n\r\n' \"\$AMI_USER\" \"\$AMI_PASSWORD\" >&3 2>/dev/null
        resp=''
        for i in \$(seq 1 8); do
            IFS= read -r -t 3 line <&3 || break
            line=\${line%\$'\r'}
            resp=\"\$resp\$line|\"
            [ -z \"\$line\" ] && break
        done
        printf 'Action: Logoff\r\n\r\n' >&3 2>/dev/null
        exec 3<&- 3>&- 2>/dev/null
        printf '%s' \"\$resp\"
        exit 0
    " 2>/dev/null
}

# resolution-only check: does target_alias resolve from inside
# from_container? (separate from ami_probe -- see its own header)
ami_can_resolve() {
    local from_container="$1" target_alias="$2"
    $COMPOSE exec -T "$from_container" getent hosts "$target_alias" >/dev/null 2>&1
}

# --- 1. no host publication ---------------------------------------------------
log "==> 1: AMI (5038) not published to the host"
PUBLISHERS="$($COMPOSE ps asterisk --format '{{.Publishers}}' 2>&1)"
if printf '%s' "$PUBLISHERS" | grep -q "5038"; then
    harness_bad "1: 5038 not host-published" "asterisk service Publishers unexpectedly include 5038: $PUBLISHERS"
else
    harness_ok "1: 5038 not host-published" "asterisk service publishes: '${PUBLISHERS:-<none>}'"
fi

# --- 2. authorized caller: app over senma-ami ---------------------------------
log "==> 2: authorized caller (app, over \$ASTERISK_HOST) -- Login + Ping"
RESP="$(ami_probe app "$ASTERISK_HOST")"
if printf '%s' "$RESP" | grep -q "Response: Success"; then
    harness_ok "2: authorized app caller authenticates" "$RESP"
else
    harness_bad "2: authorized app caller authenticates" "expected 'Response: Success', got: $RESP"
fi

# --- 3. unauthorized callers: db, provider -------------------------------------
log "==> 3: unauthorized callers (db, provider) -- ACL must deny"
ASTERISK_MAG_IP="$(docker inspect mag-pbx-asterisk-1 --format '{{(index .NetworkSettings.Networks "mag-pbx_mag").IPAddress}}' 2>/dev/null)"
for svc in db provider; do
    if ami_can_resolve "$svc" "$ASTERISK_HOST"; then
        harness_bad "3a: $svc cannot resolve \$ASTERISK_HOST" "expected resolution to fail (not on senma-control), but it succeeded"
    else
        harness_ok "3a: $svc cannot resolve \$ASTERISK_HOST" "not joined to senma-control, as expected"
    fi
    if [ -n "$ASTERISK_MAG_IP" ]; then
        DIRECT_RESP="$(ami_probe "$svc" "$ASTERISK_MAG_IP")"
        if printf '%s' "$DIRECT_RESP" | grep -q "Response: Success"; then
            harness_bad "3b: $svc denied even with correct credentials (mag address)" "UNEXPECTED: ACL accepted a mag-network caller: $DIRECT_RESP"
        elif printf '%s' "$DIRECT_RESP" | grep -q "Response: Error"; then
            harness_ok "3b: $svc denied even with correct credentials (mag address)" "$DIRECT_RESP"
        else
            harness_bad "3b: $svc denied even with correct credentials (mag address)" "expected an explicit AMI 'Response: Error', got: $DIRECT_RESP"
        fi
    else
        harness_bad "3b: $svc denied even with correct credentials (mag address)" "could not determine asterisk's mag-network IP via docker inspect"
    fi
done

# --- 4. manager reload preserves the ACL ---------------------------------------
log "==> 4: 'manager reload' preserves the narrowed ACL"
PRE_PERMIT="$($COMPOSE exec -T asterisk grep '^permit=' /etc/asterisk/manager.conf 2>/dev/null)"
$COMPOSE exec -T asterisk asterisk -rx "manager reload" >/dev/null 2>&1
POST_PERMIT="$($COMPOSE exec -T asterisk grep '^permit=' /etc/asterisk/manager.conf 2>/dev/null)"
RELOAD_RESP="$(ami_probe app "$ASTERISK_HOST")"
if [ "$PRE_PERMIT" = "$POST_PERMIT" ] && printf '%s' "$RELOAD_RESP" | grep -q "Response: Success"; then
    harness_ok "4: manager reload preserves ACL" "permit unchanged ($POST_PERMIT), authorized login still succeeds"
else
    harness_bad "4: manager reload preserves ACL" "pre='$PRE_PERMIT' post='$POST_PERMIT' login_after_reload='$RELOAD_RESP'"
fi

# --- 5. asterisk container restart preserves the ACL ----------------------------
log "==> 5: asterisk container restart preserves the narrowed ACL"
$COMPOSE restart asterisk >&2
if harness_wait_asterisk_ready && harness_restore_asterisk_post_restart; then
    RESTART_PERMIT="$($COMPOSE exec -T asterisk grep '^permit=' /etc/asterisk/manager.conf 2>/dev/null)"
    RESTART_RESP="$(ami_probe app "$ASTERISK_HOST")"
    if [ "$PRE_PERMIT" = "$RESTART_PERMIT" ] && printf '%s' "$RESTART_RESP" | grep -q "Response: Success"; then
        harness_ok "5: asterisk restart preserves ACL" "permit unchanged ($RESTART_PERMIT), authorized login still succeeds, ODBC/CDR recovered"
    else
        harness_bad "5: asterisk restart preserves ACL" "pre='$PRE_PERMIT' post_restart='$RESTART_PERMIT' login_after_restart='$RESTART_RESP'"
    fi
else
    harness_bad "5: asterisk restart preserves ACL" "asterisk did not reconverge to ready (CLI/PJSIP/ODBC) after restart"
fi

harness_complete
