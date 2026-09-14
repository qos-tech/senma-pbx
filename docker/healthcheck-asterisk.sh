#!/bin/bash
#
# TASK-0033E: Asterisk readiness contract.
#
# Closes the TASK-0028V class of defect: the CLI can answer before
# res_pjsip.so finishes loading, so "the asterisk process exists" and
# "asterisk -rx works" are NOT sufficient evidence that SENMA can
# actually begin telephony operations. READY here means the minimal
# stable invariant this project's own runtime evidence supports:
#
#   core CLI available
#   + res_pjsip.so Running
#   + every SENMA-managed transport declared in the generated config
#     is actually bound live (closes TASK-0028V directly)
#   + AMI authenticates (required by runtime status, apply
#     verification, diagnostics, and reconcile -- see docs/tasks/
#     0033e-readiness-contract-hardening.md AMI CLASSIFICATION for why
#     this is NOT treated the same as TASK-0029B's app-side graceful
#     degradation)
#   + HTTP/WSS listener enabled, but ONLY if a wss transport is
#     actually declared (never a hard requirement on installs that
#     don't use it)
#
# Deliberately excluded from the pass/fail gate: ODBC (Asterisk-side
# CDR storage). Classified DEGRADED, not NOT_READY -- CDR failure does
# not prevent SENMA from processing calls, so it must not flip this
# container's own health status (see docs/tasks/
# 0033e-readiness-contract-hardening.md ODBC CLASSIFICATION). Surfaced
# instead as a WARN-level `make doctor` check.
#
# Cost: every check here is either a single fast Asterisk CLI query or
# a local file read -- no DB round-trip (Asterisk's own readiness must
# not depend on the database being reachable, see docs/tasks/
# 0033e-readiness-contract-hardening.md PHASE 17 evidence), no AGI/PHP
# bootstrap, no full PJSIP endpoint dump. Measured live at well under
# 200ms total (see that doc's RUNTIME COST section).
#
# Secret safety: AMI_USER/AMI_PASSWORD are read from this container's
# own environment (already set by asterisk-entrypoint.sh's own
# first-boot templating requirement), never passed as a healthcheck
# CLI argument -- `docker inspect .Config.Healthcheck.Test` shows the
# literal command below, not a secret value. The AMI login itself is
# fed over the raw socket, never through a shell argv.
#
# Exit 0 + "READY: ..." when every required condition holds; exit 1 +
# a single concise "FAIL: <reason>" line otherwise.

set -uo pipefail

CLI_OUT="$(asterisk -rx "core show version" 2>&1)"
if ! printf '%s' "$CLI_OUT" | grep -q "Asterisk"; then
    echo "FAIL: core CLI not responding"
    exit 1
fi

MODULE_OUT="$(asterisk -rx "module show like res_pjsip.so" 2>&1)"
if ! printf '%s' "$MODULE_OUT" | grep -q "Running"; then
    echo "FAIL: res_pjsip.so not Running"
    exit 1
fi

TRANSPORTS_CONF=/etc/asterisk/snep/senma-pjsip-transports.conf
EXPECTED_TRANSPORTS=""
if [ -f "$TRANSPORTS_CONF" ]; then
    EXPECTED_TRANSPORTS="$(grep -B1 '^type=transport' "$TRANSPORTS_CONF" 2>/dev/null \
        | grep '^\[' | tr -d '[]' | sort -u)"
fi

if [ -n "$EXPECTED_TRANSPORTS" ]; then
    ACTUAL_TRANSPORTS="$(asterisk -rx "pjsip show transports" 2>/dev/null \
        | grep '^Transport:  [a-z]' | awk '{print $2}' | sort -u)"
    MISSING="$(comm -23 <(printf '%s\n' "$EXPECTED_TRANSPORTS") <(printf '%s\n' "$ACTUAL_TRANSPORTS") 2>/dev/null | tr '\n' ',' | sed 's/,$//')"
    if [ -n "$MISSING" ]; then
        echo "FAIL: expected transport(s) not loaded: $MISSING"
        exit 1
    fi
fi

: "${AMI_USER:?AMI_USER must be set}"
: "${AMI_PASSWORD:?AMI_PASSWORD must be set}"
: "${ASTERISK_HOST:?ASTERISK_HOST must be set}"
# TASK-0034F / TASK-0035E2: resolve via ASTERISK_HOST. Bridge mode uses
# the `senma-ami` alias on senma-control. Host mode sets
# ASTERISK_HOST=127.0.0.1 (literal) — getent is unnecessary then and
# would fail on some images.
case "$ASTERISK_HOST" in
    *:*) SELF_IP="$ASTERISK_HOST" ;;  # IPv6 literal (rare)
    *)
        if printf '%s' "$ASTERISK_HOST" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
            SELF_IP="$ASTERISK_HOST"
        else
            SELF_IP="$(getent hosts "$ASTERISK_HOST" 2>/dev/null | awk '{print $1}' | head -1)"
        fi
        ;;
esac
if [ -z "$SELF_IP" ]; then
    echo "FAIL: could not resolve ASTERISK_HOST ($ASTERISK_HOST) for AMI check"
    exit 1
fi
AMI_RESULT="$(
    {
        exec 3<>/dev/tcp/"$SELF_IP"/5038 || exit 2
        IFS= read -r -t 3 _banner <&3 || exit 2
        printf "Action: Login\r\nUsername: %s\r\nSecret: %s\r\nEvents: off\r\n\r\n" "$AMI_USER" "$AMI_PASSWORD" >&3
        resp=""
        while IFS= read -r -t 3 line <&3; do
            line="${line%$'\r'}"
            resp="$resp$line|"
            [ -z "$line" ] && break
        done
        printf "Action: Logoff\r\n\r\n" >&3 2>/dev/null
        exec 3<&- 3>&- 2>/dev/null
        case "$resp" in
            *"Response: Success"*) echo "OK" ;;
            *) echo "FAILED" ;;
        esac
    } 2>/dev/null
)"
if [ "$AMI_RESULT" != "OK" ]; then
    echo "FAIL: AMI login did not succeed"
    exit 1
fi

if printf '%s' "$EXPECTED_TRANSPORTS" | grep -qx "wss"; then
    HTTP_OUT="$(asterisk -rx "http show status" 2>&1)"
    if ! printf '%s' "$HTTP_OUT" | grep -qi "Server Enabled"; then
        echo "FAIL: wss transport declared but HTTP server not enabled"
        exit 1
    fi
fi

TRANSPORTS_SUMMARY="$(printf '%s' "$EXPECTED_TRANSPORTS" | tr '\n' ',' | sed 's/,$//')"
echo "READY: core CLI, res_pjsip Running, transports [${TRANSPORTS_SUMMARY:-none}] loaded, AMI OK"
exit 0
