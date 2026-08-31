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
    # Bash 3.2 (the macOS host shell every caller here runs on) treats
    # "${arr[@]}" on a *truly empty* array as an unbound-variable error
    # under `set -u` -- fixed in bash 4.4+, but every caller of this
    # library sets -u. This fires for real whenever harness_finalize is
    # reached before a single harness_ok/harness_bad call has run (e.g.
    # harness_blocked firing on the very first check, such as
    # harness_require_containers finding a container not yet Up).
    # ${#arr[@]} (a length check, not an element expansion) is always
    # safe on an empty array even in bash 3.2, so it guards the loop.
    if [ "${#_HARNESS_ROWS[@]}" -gt 0 ]; then
        for r in "${_HARNESS_ROWS[@]}"; do
            IFS='|' read -r flow status detail <<< "$r"
            printf "%-40s %-8s %s\n" "$flow" "$status" "$detail"
        done
    fi
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

# harness_cdr_report_window <calldate> [margin_minutes] -- sets
# HARNESS_REPORT_START_DATE/_START_HOUR/_END_DATE/_END_HOUR to a tight
# [calldate - margin, calldate + margin] window (default margin: 5
# minutes), expressed in calldate's own string format/timezone -- never
# derived from "now" or from the harness shell's own local calendar day.
#
# TASK-0027A: call-smoke-test.sh/trunk-smoke-test.sh previously computed
# the CallsReport API's start_date/end_date from the *container's local*
# `date`, while `cdr.calldate` is stored in a different timezone (see
# docs/tasks/0027a-timezone-safe-cdr-regression.md) -- during the ~3
# hours of each local day where the local calendar day and calldate's
# own calendar day disagree, that silently asked the report for the
# wrong day entirely and the assertion failed. Anchoring the window on
# the CDR row's own already-confirmed calldate value sidesteps the
# question of which timezone it is in: whatever it is, offsetting *that
# exact value* by a few minutes and formatting with the same tool stays
# self-consistent, and CallsReportService.php's plain calldate>=/<=
# string-range query spans a real midnight boundary correctly with no
# special-casing needed on either side.
#
# Requires $COMPOSE (already set by the caller, same convention as
# harness_require_containers) -- a running `asterisk` container supplies
# GNU date for the relative-date parsing below. Two portability/parsing
# pitfalls this deliberately avoids, both confirmed live:
#   - the host shell's own `date` may be the non-GNU BSD variant (no
#     `-d`), which is why this always execs into the container instead;
#   - GNU date's own leading-sign relative syntax is itself ambiguous:
#     `date -d "<timestamp> -5 minutes"` silently mis-parses the "-5" as
#     a UTC-5 timezone marker rather than a relative offset, producing a
#     wildly wrong result with no error. The unambiguous natural-language
#     forms "N minutes ago" / "N minutes" (no leading sign) are used
#     instead and were verified correct across an ordinary daytime value
#     and both directions of a real midnight crossing.
# An empty/missing calldate is rejected explicitly (rather than passed
# to `date -d`) because GNU date silently treats a blank/whitespace-only
# `-d` string as "now" instead of failing -- which would otherwise make
# a caller's missing-CDR bug look like a valid (but wrong) window instead
# of a clear failure.
harness_cdr_report_window() {
    local calldate="$1" margin="${2:-5}" start end
    if [ -z "$calldate" ]; then
        return 1
    fi
    start="$($COMPOSE exec -T asterisk date -d "$calldate ${margin} minutes ago" +"%Y-%m-%d %H:%M:%S" 2>/dev/null | tr -d '\r')"
    end="$($COMPOSE exec -T asterisk date -d "$calldate ${margin} minutes" +"%Y-%m-%d %H:%M:%S" 2>/dev/null | tr -d '\r')"
    if [ -z "$start" ] || [ -z "$end" ]; then
        return 1
    fi
    HARNESS_REPORT_START_DATE="${start%% *}"
    HARNESS_REPORT_START_HOUR="${start#* }"
    HARNESS_REPORT_END_DATE="${end%% *}"
    HARNESS_REPORT_END_HOUR="${end#* }"
    return 0
}

_harness_container_up() {
    $COMPOSE ps "$1" 2>/dev/null | grep -q "Up"
}

# harness_require_containers svc1 svc2 ... -- BLOCKED if any is not Up.
# Expects $COMPOSE to already be set by the caller.
#
# TASK-0027A finding: a one-shot check here raced a genuinely transient
# post-cleanup state -- confirmed live, `docker compose ps` briefly
# reported a container not yet "Up" for the very next suite's first
# check, one second after the previous suite's own cleanup (fixture
# removal, PJSIP config regeneration/reload) -- the exact same class of
# transient-check race pjsip_modules_running's callers already retry
# around (see call-smoke-test.sh/trunk-smoke-test.sh/transport-smoke-test.sh),
# just never applied to this specific check before. Reusing the same
# harness_retry bound (5 attempts, 2s apart -- up to 8s worst case) here
# closes that gap without adding any new sleep/timing mechanism.
harness_require_containers() {
    local all_up=1 svc
    for svc in "$@"; do
        if ! harness_retry 5 2 -- _harness_container_up "$svc"; then
            all_up=0
        fi
    done
    if [ "$all_up" = "1" ]; then
        harness_ok "containers healthy" "$* all Up"
    else
        harness_blocked "one or more of [$*] not Up -- run 'make up' first"
    fi
}
