#!/bin/bash
#
# Destructive readiness-detection and recovery proof (TASK-0033E).
#
# Deliberately NOT part of `make regression` -- unlike scripts/
# readiness-smoke-test.sh (safe, non-mutating, runs there). This suite
# stops db/asterisk on the real dev stack (restoring each before moving
# on) and spins up a throwaway, fully isolated Compose project (its own
# network/volumes, torn down at the end) to prove the DB-schema-missing
# case without ever touching the real development database. Mirrors
# the same safe/destructive split precedent scripts/secret-rotation-
# smoke-test.sh and scripts/doctor-failure-smoke-test.sh already
# established.
#
# Restores every stopped/corrupted condition and tears down the
# isolated project before finishing (required cleanup, not best-effort)
# so a developer's working stack is left exactly as found, regardless
# of pass/fail.
#
# Proves, in order:
#   1.  DB port-open-but-schema-missing does not become READY (isolated
#       throwaway project -- the real dev database is never touched)
#   2.  app without DB does not report READY (container stays running,
#       health transitions to unhealthy -- not process-dead)
#   3.  app recovers automatically when DB returns (no recreate needed)
#   4.  Asterisk process with a PJSIP transport mismatch (the exact
#       TASK-0028V class of defect, reproduced deterministically by
#       declaring a transport that isn't actually loaded, rather than
#       racing a timing window) does not report READY
#   5.  Asterisk recovers once the mismatch is corrected
#   6.  AMI failure makes Asterisk NOT_READY (this task's own chosen
#       classification -- see docs/tasks/
#       0033e-readiness-contract-hardening.md AMI CLASSIFICATION)
#   7.  Asterisk recovers once AMI is restored
#   8.  WSS listener failure makes Asterisk NOT_READY when a wss
#       transport is declared (conditional requirement)
#   9.  Asterisk recovers once the WSS listener is restored, and the
#       TLS certificate/key are confirmed byte-identical throughout
#       (never touched by any step above)
#   10. `docker compose up -d --force-recreate` (full stack) converges
#       deterministically back to healthy
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
log() { harness_log "$@"; }

log "==> checking required containers"
harness_require_containers app asterisk db
harness_require_env DB_PASSWORD DB_ROOT_PASSWORD AMI_PASSWORD

container_health() { $COMPOSE ps "$1" --format '{{.Health}}' 2>/dev/null; }
container_state() { $COMPOSE ps -a "$1" --format '{{.State}}' 2>/dev/null; }
wait_healthy() { local svc="$1" tries="${2:-20}"; harness_retry "$tries" 3 -- bash -c "[ \"\$($COMPOSE ps '$svc' --format '{{.Health}}' 2>/dev/null)\" = healthy ]"; }

ISOLATED_PROJECT="senma-readiness-failtest-$$"
ISOLATED_OVERRIDE=""

restore_all() {
    local rc=0
    log "==> restoring db/asterisk and tearing down the isolated project (required cleanup)"
    $COMPOSE start db asterisk >&2 2>/dev/null || true
    wait_healthy db 20 || rc=1
    wait_healthy asterisk 20 || rc=1
    # Undo any injected corruption in case an earlier phase failed
    # before its own restore step ran.
    $COMPOSE exec -T asterisk sh -c '
        [ -f /tmp/senma-pjsip-transports.conf.bak ] && cp -p /tmp/senma-pjsip-transports.conf.bak /etc/asterisk/snep/senma-pjsip-transports.conf && rm -f /tmp/senma-pjsip-transports.conf.bak
        [ -f /tmp/manager.conf.bak ] && cp -p /tmp/manager.conf.bak /etc/asterisk/manager.conf && rm -f /tmp/manager.conf.bak
        [ -f /tmp/http.conf.bak ] && cp -p /tmp/http.conf.bak /etc/asterisk/http.conf && rm -f /tmp/http.conf.bak
        true
    ' >/dev/null 2>&1
    $COMPOSE exec -T asterisk asterisk -rx "manager reload" >/dev/null 2>&1 || true
    $COMPOSE exec -T asterisk asterisk -rx "module reload http" >/dev/null 2>&1 || true
    # TASK-0033E finding: unlike the app's per-request PDO connection
    # (which reconnects fresh on the very next page load), Asterisk's
    # own res_odbc pooled connection does NOT automatically re-establish
    # itself after `db` is stopped and restarted (confirmed live: `odbc
    # show all` showed 0 active connections and a "Last fail connection
    # attempt" entry well after `db` was healthy again, until `module
    # reload res_odbc.so` was run) -- left unaddressed here, step 2/3's
    # own `db stop`/`db start` would silently leave Asterisk's CDR path
    # broken for every suite that runs after this one. See docs/tasks/
    # 0033e-readiness-contract-hardening.md ODBC CLASSIFICATION/
    # REMAINING DEBT -- this is exactly why ODBC is classified DEGRADED
    # (Asterisk itself stays healthy throughout) rather than NOT_READY,
    # and exactly why it still needs an explicit, deliberate recovery
    # step here rather than an assumed automatic one.
    $COMPOSE exec -T asterisk asterisk -rx "module reload res_odbc.so" >/dev/null 2>&1 || true
    if [ -n "$ISOLATED_OVERRIDE" ]; then
        $COMPOSE -p "$ISOLATED_PROJECT" -f "$REPO_ROOT/compose.yaml" -f "$ISOLATED_OVERRIDE" down -v >/dev/null 2>&1 || true
        rm -rf "$(dirname "$ISOLATED_OVERRIDE")"
        docker rmi "${ISOLATED_PROJECT}-app:latest" "${ISOLATED_PROJECT}-asterisk:latest" "${ISOLATED_PROJECT}-provider:latest" >/dev/null 2>&1 || true
    fi
    if bash "$SCRIPT_DIR/doctor.sh" >/dev/null 2>&1; then
        log "restore_all: doctor confirms exit 0 (fully recovered)"
    else
        log "restore_all: doctor still reports FAIL after restore -- see 'make doctor'"
        rc=1
    fi
    return "$rc"
}
harness_register_cleanup "restore db/asterisk and tear down isolated project" restore_all

# --- 1. DB schema missing (isolated, throwaway project) ---------------------
log "==> 1: DB port-open-but-schema-missing (isolated throwaway project)"
ISOLATED_DIR="$(mktemp -d)"
ISOLATED_OVERRIDE="$ISOLATED_DIR/subnet-override.yaml"
cat > "$ISOLATED_OVERRIDE" <<'EOF'
networks:
  mag:
    ipam:
      config:
        - subnet: 172.31.0.0/16
EOF
wait_healthy_isolated() { [ "$($COMPOSE -p "$ISOLATED_PROJECT" ps db --format '{{.Health}}' 2>/dev/null)" = "healthy" ]; }
if $COMPOSE -p "$ISOLATED_PROJECT" -f "$REPO_ROOT/compose.yaml" -f "$ISOLATED_OVERRIDE" up -d db >&2; then
    if harness_retry 15 2 -- wait_healthy_isolated; then
        $COMPOSE -p "$ISOLATED_PROJECT" exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -uroot -e 'DROP TABLE snep.core_config;'" <<< "$DB_ROOT_PASSWORD" >&2
        ISO_OUT="$($COMPOSE -p "$ISOLATED_PROJECT" exec -T db bash /usr/local/bin/healthcheck-db.sh 2>&1)"
        ISO_RC=$?
        if [ "$ISO_RC" -ne 0 ] && printf '%s' "$ISO_OUT" | grep -q "schema not ready"; then
            harness_ok "1: DB with missing schema does not report READY" "healthcheck-db.sh: $ISO_OUT"
        else
            harness_bad "1: DB with missing schema does not report READY" "expected a schema FAIL, got exit $ISO_RC: $ISO_OUT"
        fi
    else
        harness_bad "1: DB with missing schema does not report READY" "isolated db never became healthy to begin with"
    fi
else
    harness_bad "1: DB with missing schema does not report READY" "could not start isolated db service"
fi
$COMPOSE -p "$ISOLATED_PROJECT" -f "$REPO_ROOT/compose.yaml" -f "$ISOLATED_OVERRIDE" down -v >/dev/null 2>&1
docker rmi "${ISOLATED_PROJECT}-app:latest" "${ISOLATED_PROJECT}-asterisk:latest" "${ISOLATED_PROJECT}-provider:latest" >/dev/null 2>&1 || true
rm -rf "$ISOLATED_DIR"
ISOLATED_OVERRIDE=""

# --- 2/3. app without DB, then recovery --------------------------------------
log "==> 2: app without DB does not report READY"
$COMPOSE stop db >&2
if harness_retry 20 3 -- bash -c "$COMPOSE ps app --format '{{.Status}}' 2>/dev/null | grep -q unhealthy"; then
    harness_ok "2: app becomes unhealthy without DB" "confirmed via 'docker compose ps app'"
else
    harness_bad "2: app becomes unhealthy without DB" "app did not report unhealthy within 60s"
fi
if [ "$(container_state app)" = "running" ]; then
    harness_ok "2b: app container stays running (not process-dead)" "state=running while unhealthy"
else
    harness_bad "2b: app container stays running (not process-dead)" "state=$(container_state app)"
fi

log "==> 3: app recovers automatically when DB returns"
$COMPOSE start db >&2
if wait_healthy db 20 && wait_healthy app 10; then
    harness_ok "3: app recovers when DB returns" "both db and app healthy again, no recreate performed"
else
    harness_bad "3: app recovers when DB returns" "db or app did not reconverge to healthy"
fi

# --- 4/5. Asterisk PJSIP transport mismatch (TASK-0028V class), recovery ----
log "==> 4: Asterisk with a PJSIP transport mismatch does not report READY"
$COMPOSE exec -T asterisk sh -c 'cp -p /etc/asterisk/snep/senma-pjsip-transports.conf /tmp/senma-pjsip-transports.conf.bak && printf "\n[fake-missing-transport]\ntype=transport\nprotocol=tcp\nbind=0.0.0.0:9999\n" >> /etc/asterisk/snep/senma-pjsip-transports.conf'
AST_MISMATCH_OUT="$($COMPOSE exec -T asterisk bash /usr/local/bin/healthcheck-asterisk.sh 2>&1)"; AST_MISMATCH_RC=$?
if [ "$AST_MISMATCH_RC" -ne 0 ] && printf '%s' "$AST_MISMATCH_OUT" | grep -q "transport(s) not loaded"; then
    harness_ok "4: transport mismatch detected" "$AST_MISMATCH_OUT"
else
    harness_bad "4: transport mismatch detected" "expected a transport-mismatch FAIL, got exit $AST_MISMATCH_RC: $AST_MISMATCH_OUT"
fi

log "==> 5: Asterisk recovers once the mismatch is corrected"
$COMPOSE exec -T asterisk sh -c 'cp -p /tmp/senma-pjsip-transports.conf.bak /etc/asterisk/snep/senma-pjsip-transports.conf && rm -f /tmp/senma-pjsip-transports.conf.bak'
AST_RECOVER_OUT="$($COMPOSE exec -T asterisk bash /usr/local/bin/healthcheck-asterisk.sh 2>&1)"; AST_RECOVER_RC=$?
if [ "$AST_RECOVER_RC" -eq 0 ]; then
    harness_ok "5: recovers after transport mismatch corrected" "$AST_RECOVER_OUT"
else
    harness_bad "5: recovers after transport mismatch corrected" "exit $AST_RECOVER_RC: $AST_RECOVER_OUT"
fi

# --- 6/7. AMI failure classification, recovery -------------------------------
log "==> 6: AMI failure makes Asterisk NOT_READY (this task's chosen classification)"
$COMPOSE exec -T asterisk sh -c 'cp -p /etc/asterisk/manager.conf /tmp/manager.conf.bak && sed -i "s/^secret = .*/secret = deliberately-wrong-for-readiness-failure-test/" /etc/asterisk/manager.conf'
$COMPOSE exec -T asterisk asterisk -rx "manager reload" >/dev/null 2>&1
AMI_FAIL_OUT="$($COMPOSE exec -T asterisk bash /usr/local/bin/healthcheck-asterisk.sh 2>&1)"; AMI_FAIL_RC=$?
if [ "$AMI_FAIL_RC" -ne 0 ] && printf '%s' "$AMI_FAIL_OUT" | grep -q "AMI login did not succeed"; then
    harness_ok "6: AMI failure detected as NOT_READY" "$AMI_FAIL_OUT"
else
    harness_bad "6: AMI failure detected as NOT_READY" "expected an AMI FAIL, got exit $AMI_FAIL_RC: $AMI_FAIL_OUT"
fi
# Worst case is (retries+1) x interval = 7 x 10s = 70s (a check can be
# mid-flight, already past, the instant the failure is injected) --
# confirmed live during this task's own manual validation at ~51s;
# 30 x 3s = 90s gives comfortable margin above that worst case without
# being unboundedly patient.
if harness_retry 30 3 -- bash -c "$COMPOSE ps asterisk --format '{{.Status}}' 2>/dev/null | grep -q unhealthy"; then
    harness_ok "6b: Docker's own health status reflects the AMI failure" "confirmed via 'docker compose ps asterisk'"
else
    harness_bad "6b: Docker's own health status reflects the AMI failure" "asterisk did not report unhealthy within 90s"
fi

log "==> 7: Asterisk recovers once AMI is restored"
$COMPOSE exec -T asterisk sh -c 'cp -p /tmp/manager.conf.bak /etc/asterisk/manager.conf && rm -f /tmp/manager.conf.bak'
$COMPOSE exec -T asterisk asterisk -rx "manager reload" >/dev/null 2>&1
if wait_healthy asterisk 15; then
    harness_ok "7: recovers after AMI restored" "asterisk healthy again"
else
    harness_bad "7: recovers after AMI restored" "did not become healthy within 45s"
fi

# --- 8/9. WSS listener failure, recovery, cert integrity ---------------------
log "==> 8: WSS listener failure makes Asterisk NOT_READY"
CERT_SHA_BEFORE="$($COMPOSE exec -T asterisk sh -c 'sha256sum /etc/asterisk/keys/wss-test-cert.pem /etc/asterisk/keys/wss-test-key.pem' 2>/dev/null)"
$COMPOSE exec -T asterisk sh -c 'cp -p /etc/asterisk/http.conf /tmp/http.conf.bak && sed -i "s/^enabled=yes/enabled=no/" /etc/asterisk/http.conf'
$COMPOSE exec -T asterisk asterisk -rx "module reload http" >/dev/null 2>&1
WSS_FAIL_OUT="$($COMPOSE exec -T asterisk bash /usr/local/bin/healthcheck-asterisk.sh 2>&1)"; WSS_FAIL_RC=$?
if [ "$WSS_FAIL_RC" -ne 0 ] && printf '%s' "$WSS_FAIL_OUT" | grep -q "HTTP server not enabled"; then
    harness_ok "8: WSS listener failure detected as NOT_READY" "$WSS_FAIL_OUT"
else
    harness_bad "8: WSS listener failure detected as NOT_READY" "expected an HTTP/WSS FAIL, got exit $WSS_FAIL_RC: $WSS_FAIL_OUT"
fi

log "==> 9: Asterisk recovers once the WSS listener is restored; cert untouched"
$COMPOSE exec -T asterisk sh -c 'cp -p /tmp/http.conf.bak /etc/asterisk/http.conf && rm -f /tmp/http.conf.bak'
$COMPOSE exec -T asterisk asterisk -rx "module reload http" >/dev/null 2>&1
if wait_healthy asterisk 15; then
    harness_ok "9a: recovers after WSS listener restored" "asterisk healthy again"
else
    harness_bad "9a: recovers after WSS listener restored" "did not become healthy within 45s"
fi
CERT_SHA_AFTER="$($COMPOSE exec -T asterisk sh -c 'sha256sum /etc/asterisk/keys/wss-test-cert.pem /etc/asterisk/keys/wss-test-key.pem' 2>/dev/null)"
if [ "$CERT_SHA_BEFORE" = "$CERT_SHA_AFTER" ] && [ -n "$CERT_SHA_BEFORE" ]; then
    harness_ok "9b: TLS certificate/key untouched throughout" "sha256 unchanged"
else
    harness_bad "9b: TLS certificate/key untouched throughout" "hash mismatch or empty -- before=[$CERT_SHA_BEFORE] after=[$CERT_SHA_AFTER]"
fi

# --- 10. force-recreate convergence ------------------------------------------
log "==> 10: full-stack force-recreate converges deterministically"
$COMPOSE up -d --force-recreate >&2
all_healthy() {
    for svc in app asterisk db provider; do
        [ "$(container_health "$svc")" = "healthy" ] || return 1
    done
    return 0
}
if harness_retry 25 3 -- all_healthy; then
    harness_ok "10: force-recreate converges" "all four services healthy again"
else
    harness_bad "10: force-recreate converges" "not all services healthy within 75s of --force-recreate"
fi

harness_complete
