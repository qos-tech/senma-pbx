#!/bin/bash
#
# Shared stateful-harness lifecycle library (TASK-0027).
#
# Sourced by every stateful smoke script (call/trunk/transport/restart/
# authorization/preauth-security/external-*-smoke). Provides one uniform
# preflight -> create -> exercise -> verify -> cleanup -> summary lifecycle
# with explicit PASS/FAIL/BLOCKED/INCONCLUSIVE classification,
# dependency-ordered cleanup, and signal-safe finalization. See
# docs/tasks/0027-regression-harness-reliability.md for the full contract.
#
# Exit codes -- the contract every caller (including scripts/regression.sh)
# relies on:
#   0 = PASS          behavior verified, required cleanup completed
#   1 = FAIL          product behavior did not meet expectations, or
#                      required cleanup failed
#   2 = BLOCKED       could not validly execute (environment/fixture/
#                      dependency/precondition problem)
#   3 = INCONCLUSIVE  interrupted, or exited before reaching its own
#                      designed completion point; not enough evidence to
#                      call PASS or FAIL
#
# Bash-3.2 compatible on purpose: these scripts run on the developer's
# HOST shell (macOS ships /bin/bash 3.2), not inside a container -- no
# associative arrays, no `readarray`, no `${var,,}`, no `${!var:-x}`.
#
# Usage contract for a sourcing script:
#   1. source this file
#   2. call harness_install_traps as the FIRST thing after sourcing,
#      before any fixture is created
#   3. record every fixture's cleanup via harness_register_cleanup /
#      harness_register_best_effort_cleanup IMMEDIATELY after that
#      fixture is confirmed created -- cleanup runs in reverse
#      (last-created-first) order, which is exactly dependency-safe
#      order for every fixture graph in this repo (a dependent object,
#      e.g. a route, is always created after the object it references,
#      e.g. a trunk)
#   4. use harness_ok / harness_bad for every check
#   5. use harness_blocked "<reason>" for any precondition/environment
#      problem that means the test cannot validly proceed (replaces the
#      old ad hoc stop()/exit 1 pattern)
#   6. call harness_complete as the LAST statement of the script

HARNESS_PASS=0
HARNESS_FAIL=1
HARNESS_BLOCKED=2
HARNESS_INCONCLUSIVE=3

_HARNESS_PASS_COUNT=0
_HARNESS_FAIL_COUNT=0
_HARNESS_ROWS=()
_HARNESS_CLEANUP_DESCS=()
_HARNESS_CLEANUP_CMDS=()
_HARNESS_CLEANUP_REQUIRED=()
_HARNESS_CLEANUP_RAN=0
_HARNESS_CLEANUP_FAILED=0
_HARNESS_BLOCKED_REASON=""
_HARNESS_INTERRUPTED=""
_HARNESS_NORMAL_COMPLETION=0
_HARNESS_FINALIZED=0
_HARNESS_LABEL="${0##*/}"

harness_log() { printf '%s\n' "$*" >&2; }

harness_row() { _HARNESS_ROWS+=("$1|$2|$3"); }

harness_ok() {
    harness_row "$1" "PASS" "$2"
    _HARNESS_PASS_COUNT=$((_HARNESS_PASS_COUNT + 1))
    harness_log "PASS: $1 -- $2"
}

harness_bad() {
    harness_row "$1" "FAIL" "$2"
    _HARNESS_FAIL_COUNT=$((_HARNESS_FAIL_COUNT + 1))
    harness_log "FAIL: $1 -- $2"
}

# harness_register_cleanup <description> <command-string>
# A failed required cleanup step downgrades an otherwise-PASS run to FAIL
# (a harness must not report PASS if required fixture cleanup failed).
harness_register_cleanup() {
    _HARNESS_CLEANUP_DESCS+=("$1")
    _HARNESS_CLEANUP_CMDS+=("$2")
    _HARNESS_CLEANUP_REQUIRED+=("1")
}

# harness_register_best_effort_cleanup <description> <command-string>
# For external/cosmetic artifacts (disposable baresip test containers,
# temp files/dirs) rather than real application-owned fixtures. A
# failure here is logged but never turns a PASS into a FAIL.
harness_register_best_effort_cleanup() {
    _HARNESS_CLEANUP_DESCS+=("$1")
    _HARNESS_CLEANUP_CMDS+=("$2")
    _HARNESS_CLEANUP_REQUIRED+=("0")
}

harness_run_cleanup() {
    [ "$_HARNESS_CLEANUP_RAN" = "1" ] && return
    _HARNESS_CLEANUP_RAN=1
    local count=${#_HARNESS_CLEANUP_DESCS[@]}
    [ "$count" -eq 0 ] && return
    harness_log "==> cleanup (most-recently-created fixture first -- dependency-safe order)"
    local i=$((count - 1))
    while [ "$i" -ge 0 ]; do
        local desc="${_HARNESS_CLEANUP_DESCS[$i]}"
        local cmd="${_HARNESS_CLEANUP_CMDS[$i]}"
        local required="${_HARNESS_CLEANUP_REQUIRED[$i]}"
        if eval "$cmd"; then
            harness_log "cleanup OK: $desc"
        elif [ "$required" = "1" ]; then
            harness_log "CLEANUP FAILED (required): $desc -- may need manual/UI cleanup"
            _HARNESS_CLEANUP_FAILED=1
        else
            harness_log "cleanup WARNING (best-effort, not fixture-blocking): $desc"
        fi
        i=$((i - 1))
    done
}

harness_print_summary() {
    echo
    echo "================================================================"
    printf "%-40s %-8s %s\n" "CHECK" "RESULT" "DETAIL"
    echo "----------------------------------------------------------------"
    local r flow status detail
    for r in "${_HARNESS_ROWS[@]}"; do
        IFS='|' read -r flow status detail <<< "$r"
        printf "%-40s %-8s %s\n" "$flow" "$status" "$detail"
    done
    echo "================================================================"
    echo "PASS: $_HARNESS_PASS_COUNT   FAIL: $_HARNESS_FAIL_COUNT"
    echo "================================================================"
}

# harness_blocked <reason> -- the test cannot validly execute (environment,
# stale fixture that could not be safely recovered, dependency problem).
# Runs cleanup, prints the summary, exits 2. Never returns.
harness_blocked() {
    _HARNESS_BLOCKED_REASON="$1"
    harness_log "BLOCKED: $1"
    echo "BLOCKED: $1"
    harness_finalize
}

# harness_complete -- call as the LAST statement of a script that reached
# its own designed end (whether checks passed or failed). Distinguishes a
# script that ran to completion from one that exited early/unexpectedly
# (set -u abort, uncaught error, etc.), which must never be classified PASS.
harness_complete() {
    _HARNESS_NORMAL_COMPLETION=1
    harness_finalize
}

harness_finalize() {
    [ "$_HARNESS_FINALIZED" = "1" ] && return
    _HARNESS_FINALIZED=1
    trap - EXIT INT TERM
    harness_run_cleanup
    harness_print_summary

    local classification code
    if [ -n "$_HARNESS_BLOCKED_REASON" ]; then
        classification="BLOCKED"; code=$HARNESS_BLOCKED
    elif [ -n "$_HARNESS_INTERRUPTED" ]; then
        if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then
            classification="FAIL"; code=$HARNESS_FAIL
        else
            classification="INCONCLUSIVE"; code=$HARNESS_INCONCLUSIVE
            harness_log "NOTE: interrupted by ${_HARNESS_INTERRUPTED} before completion -- classifying INCONCLUSIVE, not PASS"
        fi
    elif [ "$_HARNESS_NORMAL_COMPLETION" != "1" ]; then
        if [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then
            classification="FAIL"; code=$HARNESS_FAIL
        else
            classification="INCONCLUSIVE"; code=$HARNESS_INCONCLUSIVE
            harness_log "NOTE: harness exited before reaching its own designed completion point -- classifying INCONCLUSIVE, not PASS"
        fi
    elif [ "$_HARNESS_FAIL_COUNT" -gt 0 ]; then
        classification="FAIL"; code=$HARNESS_FAIL
    elif [ "$_HARNESS_CLEANUP_FAILED" = "1" ]; then
        classification="FAIL"; code=$HARNESS_FAIL
        harness_log "NOTE: every check passed but required cleanup failed -- classifying FAIL, not PASS"
    else
        classification="PASS"; code=$HARNESS_PASS
    fi
    echo "RESULT: $classification ($_HARNESS_LABEL)"
    exit "$code"
}

_harness_on_signal() {
    _HARNESS_INTERRUPTED="$1"
    harness_log "INTERRUPTED by $1 -- attempting cleanup, then finalizing"
    harness_finalize
}

# harness_install_traps -- call once, immediately after sourcing, before
# any fixture is created. EXIT is the safety net for any exit path this
# library doesn't already control (e.g. an unset-variable abort under
# `set -u`); INT/TERM guarantee an interruption still attempts cleanup and
# always prints a classified summary, never silently disappearing.
harness_install_traps() {
    trap 'harness_finalize' EXIT
    trap '_harness_on_signal INT' INT
    trap '_harness_on_signal TERM' TERM
}

# harness_require_env VAR1 VAR2 ... -- BLOCKED (not a raw shell abort) if
# any is unset/empty. Replaces the `: "${VAR:?msg}"` idiom, which would
# exit before this library's classification ever runs.
harness_require_env() {
    local missing="" v val
    for v in "$@"; do
        eval "val=\"\${$v:-}\""
        [ -z "$val" ] && missing="$missing $v"
    done
    if [ -n "$missing" ]; then
        harness_blocked "required environment variable(s) not set:$missing (source .env first)"
    fi
}

# harness_timeout <seconds> <command...> -- portable host-side bound on a
# command that could otherwise hang forever. GNU coreutils `timeout` is
# NOT reliably present on the macOS host these scripts run on (confirmed
# live during TASK-0027: `timeout: command not found` on a stock macOS
# shell) -- this reimplements it with plain job control instead. Only
# needed for HOST-side commands; commands already run *inside* a Debian
# container via `docker exec`/`docker run ... sh -c "..."` can keep using
# the real `timeout` binary there, since that container has coreutils.
harness_timeout() {
    local secs="$1"; shift
    "$@" &
    local cmd_pid=$!
    ( sleep "$secs"; kill -TERM "$cmd_pid" 2>/dev/null ) &
    local watchdog_pid=$!
    local status=0
    wait "$cmd_pid" 2>/dev/null || status=$?
    kill "$watchdog_pid" 2>/dev/null
    wait "$watchdog_pid" 2>/dev/null
    return "$status"
}

# harness_retry <attempts> <sleep_seconds> -- <command...> -- retries a
# precondition check a bounded number of times before giving up. Added
# after a live, reproducible finding (TASK-0027): querying `asterisk -rx
# 'module show like res_pjsip.so'` via a fresh `docker compose exec`
# immediately after another suite's own PJSIP config write/reload can
# transiently see incomplete output while that reload is still
# in-flight -- confirmed by `make regression` running two independent
# suites back-to-back with no settling gap. A short bounded retry here
# is cheaper and more targeted than an unconditional inter-suite delay
# in the aggregate runner.
harness_retry() {
    local attempts="$1" delay="$2"
    shift 2
    [ "$1" = "--" ] && shift
    local i
    for i in $(seq 1 "$attempts"); do
        if "$@"; then
            return 0
        fi
        [ "$i" -lt "$attempts" ] && sleep "$delay"
    done
    return 1
}

# harness_require_containers svc1 svc2 ... -- BLOCKED if any is not Up.
# Expects $COMPOSE to already be set by the caller.
harness_require_containers() {
    local all_up=1 svc
    for svc in "$@"; do
        if ! $COMPOSE ps "$svc" 2>/dev/null | grep -q "Up"; then
            all_up=0
        fi
    done
    if [ "$all_up" = "1" ]; then
        harness_ok "containers healthy" "$* all Up"
    else
        harness_blocked "one or more of [$*] not Up -- run 'make up' first"
    fi
}
