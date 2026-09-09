#!/bin/bash
# TASK-0034I focused regression: proves the Asterisk runtime-resource
# persistence contract this task establishes for /var/lib/asterisk
# {moh,sounds} -- provisioned by docker/asterisk-entrypoint.sh, shared
# with the `app` container via the existing mag-asterisk-var named
# volume (compose.yaml). See docs/tasks/
# 0034i-system-status-dependency-runtime-resource-closure.md.
#
# Uses only test-owned marker files under a dedicated
# ".senma-storage-smoke" name -- never touches real customer MOH/sound
# content, and cleans up unconditionally (best-effort) even on an
# interrupted run. Restarts the `asterisk` service as part of its own
# proof (container-scoped, not host-wide); other services are
# untouched.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
MARKER_NAME=".senma-storage-smoke-marker"
MARKER_CONTENT="senma-runtime-storage-smoke-$$-$(date +%s)"

echo '==> Preflight'
harness_require_containers app asterisk

run_ast() { $COMPOSE exec -T asterisk sh -c "$1"; }
run_app() { $COMPOSE exec -T app sh -c "$1"; }

echo '==> Required directories provisioned with correct ownership/mode'
for dir in /var/lib/asterisk/moh /var/lib/asterisk/moh/tmp /var/lib/asterisk/moh/backup /var/lib/asterisk/sounds; do
    stat_out="$(run_ast "stat -c '%U:%G %a' '$dir' 2>/dev/null")"
    case "$stat_out" in
        asterisk:senma-config\ 2775) harness_ok "provisioned: $dir" "owner/mode $stat_out" ;;
        *) harness_bad "provisioned: $dir" "expected 'asterisk:senma-config 2775', got '${stat_out:-<missing>}'" ;;
    esac
done

echo '==> app container sees the same paths through the shared mag-asterisk-var volume'
if run_app "test -d /var/lib/asterisk/moh && test -d /var/lib/asterisk/sounds"; then
    harness_ok 'app-container visibility' '/var/lib/asterisk/{moh,sounds} both visible from app'
else
    harness_bad 'app-container visibility' 'app container cannot see one or both directories -- check the compose.yaml mag-asterisk-var mount on the app service'
fi

echo '==> www-data (app container) can actually create and remove an owned file'
if run_app "touch /var/lib/asterisk/moh/tmp/${MARKER_NAME}-app && rm /var/lib/asterisk/moh/tmp/${MARKER_NAME}-app"; then
    harness_ok 'app-container effective write permission' 'www-data created and removed an owned test file in /var/lib/asterisk/moh/tmp'
else
    harness_bad 'app-container effective write permission' 'www-data could not create+remove an owned file -- Unix mode bits alone are not proof, see CLAUDE.md WRITABLE CHECKS'
fi

echo '==> asterisk user can actually create and remove an owned file'
if run_ast "touch /var/lib/asterisk/sounds/${MARKER_NAME}-ast && rm /var/lib/asterisk/sounds/${MARKER_NAME}-ast"; then
    harness_ok 'asterisk-container effective write permission' 'asterisk created and removed an owned test file in /var/lib/asterisk/sounds'
else
    harness_bad 'asterisk-container effective write permission' 'asterisk user could not create+remove an owned file'
fi

echo '==> Persistence proof: owned marker survives a plain restart'
MARKER_PATH="/var/lib/asterisk/moh/${MARKER_NAME}"
if ! run_ast "printf '%s' '${MARKER_CONTENT}' > '${MARKER_PATH}'"; then
    harness_blocked "could not create the persistence-proof marker at ${MARKER_PATH}"
fi
harness_register_cleanup "remove persistence-proof marker" \
    "$COMPOSE exec -T asterisk sh -c \"rm -f '${MARKER_PATH}'\""

$COMPOSE restart asterisk >/dev/null 2>&1
harness_retry 15 2 -- bash -c "$COMPOSE exec -T asterisk asterisk -rx 'core show version' >/dev/null 2>&1" \
    || harness_blocked "asterisk did not become CLI-reachable again after restart"

got="$(run_ast "cat '${MARKER_PATH}' 2>/dev/null")"
if [ "$got" = "$MARKER_CONTENT" ]; then
    harness_ok 'marker survives restart' 'byte-identical after `docker compose restart asterisk`'
else
    harness_bad 'marker survives restart' "expected '${MARKER_CONTENT}', got '${got:-<missing>}'"
fi

echo '==> Persistence proof: owned marker survives force-recreate'
$COMPOSE up -d --force-recreate asterisk >/dev/null 2>&1
harness_retry 20 3 -- bash -c "$COMPOSE exec -T asterisk asterisk -rx 'core show version' >/dev/null 2>&1" \
    || harness_blocked "asterisk did not become CLI-reachable again after force-recreate"

got="$(run_ast "cat '${MARKER_PATH}' 2>/dev/null")"
if [ "$got" = "$MARKER_CONTENT" ]; then
    harness_ok 'marker survives force-recreate' 'byte-identical after `docker compose up -d --force-recreate asterisk`'
else
    harness_bad 'marker survives force-recreate' "expected '${MARKER_CONTENT}', got '${got:-<missing>}'"
fi

echo '==> Seeded content untouched by recreate (guarded, not re-extracted)'
count="$(run_ast "ls /var/lib/asterisk/sounds | wc -l" | tr -d ' \r\n')"
if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
    harness_ok 'seeded core sounds still present' "${count} entries under /var/lib/asterisk/sounds"
else
    harness_bad 'seeded core sounds still present' "expected a non-empty /var/lib/asterisk/sounds, got count='${count}'"
fi

echo '==> MOH stays a legitimate empty/no-content class (no false "populated" state introduced by this test)'
# Remove the marker explicitly here (the registered cleanup above is a
# best-effort backstop for an interrupted run, and runs AFTER this check
# via harness_complete, not before it).
run_ast "rm -f '${MARKER_PATH}'"
remaining="$(run_ast "ls -A /var/lib/asterisk/moh | grep -v '^tmp$\|^backup$' | wc -l" | tr -d ' \r\n')"
if [ "$remaining" = "0" ]; then
    harness_ok 'moh directory clean after proof' 'only tmp/ and backup/ remain'
else
    harness_bad 'moh directory clean after proof' "unexpected leftover entries (count=$remaining) -- marker cleanup may have failed"
fi

harness_complete
