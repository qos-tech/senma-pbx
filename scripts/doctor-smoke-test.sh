#!/bin/bash
#
# Safe, non-mutating regression coverage for `make doctor` (TASK-0033D).
#
# Included in `make regression` -- unlike scripts/doctor-failure-smoke-
# -test.sh (which stops real services, injects secret/PJSIP drift, and
# forces a live log rotation; deliberately kept out of default
# regression -- see that script's own header and docs/tasks/
# 0033d-diagnostics-logging-storage-lifecycle.md REGRESSION SPLIT for
# why). This suite never stops a container, never touches a volume,
# never mutates .env or any persisted secret -- it only:
#   1. runs scripts/doctor.sh against this healthy dev install and
#      asserts exit 0 with zero FAIL lines;
#   2. asserts every mandatory check name actually appears in the
#      output (a silently-dropped check is itself a regression);
#   3. asserts non-disclosure: greps the full output (normal AND
#      --verbose) for all three live secret values plus the WSS
#      private-key file's own content, none present;
#   4. asserts --verbose adds strictly more output than normal mode,
#      without changing the PASS/FAIL verdict of any check;
#   5. asserts doctor.sh itself never invokes a mutating command
#      (module reload, reconcile (non-check), rotate-secrets, restart/
#      recreate) -- a static source-text assertion, not a behavioral
#      one, but cheap and directly enforces the READ-ONLY contract.
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

log "==> running scripts/doctor.sh against a healthy installation"
DOCTOR_OUT="$(bash "$SCRIPT_DIR/doctor.sh" 2>&1)"
DOCTOR_RC=$?

if [ "$DOCTOR_RC" -eq 0 ]; then
    harness_ok "1: doctor exits 0 on a healthy stack" "exit $DOCTOR_RC"
else
    harness_bad "1: doctor exits 0 on a healthy stack" "expected exit 0, got $DOCTOR_RC -- output:\n$DOCTOR_OUT"
fi

if printf '%s' "$DOCTOR_OUT" | grep -q '^\[FAIL'; then
    harness_bad "2: no FAIL lines on a healthy stack" "found at least one [FAIL] line"
else
    harness_ok "2: no FAIL lines on a healthy stack" "zero [FAIL] lines"
fi

log "==> asserting every mandatory check name is present"
MANDATORY_CHECKS=(
    "Docker daemon" "Container: app" "Container: asterisk" "Container: db"
    "Database reachable" "Application DB authentication" "Expected schema present"
    "Administrator account" "Bootstrap admin secret file"
    "Application HTTP reachable" "Application renders login page"
    "Asterisk CLI reachable" "Asterisk console logger" "PJSIP module loaded" "Asterisk HTTP/WS backend" "AMI reachable"
    "PJSIP configuration" "Secrets" "Host disk free space" "Named volume usage"
    "Asterisk full log" "Application error log" "Backup destination" "TLS/WSS certificate"
)
MISSING=""
for chk in "${MANDATORY_CHECKS[@]}"; do
    printf '%s' "$DOCTOR_OUT" | grep -qF "$chk" || MISSING="$MISSING|$chk"
done
if [ -z "$MISSING" ]; then
    harness_ok "3: every mandatory check ran" "all ${#MANDATORY_CHECKS[@]} expected check names found in output"
else
    harness_bad "3: every mandatory check ran" "missing:$MISSING"
fi

log "==> checking non-disclosure (normal and --verbose)"
DOCTOR_VERBOSE_OUT="$(bash "$SCRIPT_DIR/doctor.sh" --verbose 2>&1)"
WSS_KEY_CONTENT="$($COMPOSE exec -T asterisk sh -c 'cat /etc/asterisk/keys/wss-test-key.pem 2>/dev/null' | head -3 | tail -1)"
DISCLOSED=0
for v in "$DB_PASSWORD" "$DB_ROOT_PASSWORD" "$AMI_PASSWORD"; do
    printf '%s' "$DOCTOR_OUT" | grep -qF "$v" && DISCLOSED=1
    printf '%s' "$DOCTOR_VERBOSE_OUT" | grep -qF "$v" && DISCLOSED=1
done
if [ -n "$WSS_KEY_CONTENT" ]; then
    printf '%s' "$DOCTOR_VERBOSE_OUT" | grep -qF "$WSS_KEY_CONTENT" && DISCLOSED=1
fi
if [ "$DISCLOSED" -eq 0 ]; then
    harness_ok "4: no secret disclosure in normal or verbose output" "grepped both for all three live secrets and the WSS private key body, none found"
else
    harness_bad "4: no secret disclosure in normal or verbose output" "at least one secret value or key-body line appeared verbatim"
fi

log "==> asserting --verbose adds detail without changing verdicts"
NORMAL_LINES="$(printf '%s' "$DOCTOR_OUT" | grep -c '^\[')"
VERBOSE_LINES="$(printf '%s' "$DOCTOR_VERBOSE_OUT" | wc -l | tr -d ' ')"
NORMAL_TOTAL_LINES="$(printf '%s' "$DOCTOR_OUT" | wc -l | tr -d ' ')"
VERBOSE_VERDICT_LINES="$(printf '%s' "$DOCTOR_VERBOSE_OUT" | grep -c '^\[')"
if [ "$VERBOSE_LINES" -gt "$NORMAL_TOTAL_LINES" ] && [ "$VERBOSE_VERDICT_LINES" -eq "$NORMAL_LINES" ]; then
    harness_ok "5: --verbose adds detail, same verdicts" "normal=${NORMAL_TOTAL_LINES} lines/${NORMAL_LINES} checks, verbose=${VERBOSE_LINES} lines/${VERBOSE_VERDICT_LINES} checks"
else
    harness_bad "5: --verbose adds detail, same verdicts" "normal=${NORMAL_TOTAL_LINES}/${NORMAL_LINES}, verbose=${VERBOSE_LINES}/${VERBOSE_VERDICT_LINES}"
fi

log "==> asserting doctor.sh's own source contains no mutating command"
# Deliberately a source-text check, not a behavioral one -- cheap,
# direct enforcement of the READ-ONLY contract (docs/tasks/
# 0033d-diagnostics-logging-storage-lifecycle.md DOCTOR CONTRACT).
# `reconcile-pjsip.php --check` and `secrets-check.sh` themselves are
# non-mutating by their own established contracts (TASK-0033B/0033C)
# and are explicitly allowed; only doctor.sh's OWN non-comment source
# lines are inspected (a mention inside a comment, like this file's
# own header, must not trip the check).
BAD=0
DOCTOR_SRC="$(grep -vE '^\s*#' "$SCRIPT_DIR/doctor.sh")"
for pattern in 'module reload' 'logger rotate' 'manager reload' 'rotate-secrets.sh' \
               'reconcile-pjsip.php[^-]*$' 'compose restart' 'compose stop' 'compose rm' \
               'force-recreate'; do
    if printf '%s' "$DOCTOR_SRC" | grep -qE "$pattern"; then
        log "forbidden pattern found in doctor.sh: $pattern"
        BAD=1
    fi
done
if [ "$BAD" -eq 0 ]; then
    harness_ok "6: doctor.sh contains no mutating command" "no module reload/rotate-secrets/reconcile-apply/restart/recreate pattern found"
else
    harness_bad "6: doctor.sh contains no mutating command" "see log above for which pattern matched"
fi

harness_complete
