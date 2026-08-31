#!/bin/bash
#
# cdr-window-selftest.sh -- TASK-0027A
#
# Deterministic proof for scripts/lib/harness.sh's harness_cdr_report_window(),
# the function call-smoke-test.sh/trunk-smoke-test.sh use to build a
# timezone-safe CallsReport lookup window anchored on a CDR's own calldate
# value instead of on the harness shell's local calendar day (see
# docs/tasks/0027a-timezone-safe-cdr-regression.md for the full story).
#
# The bug this replaces only manifested naturally during a ~3-hour nightly
# window (local calendar day vs. calldate's own calendar day disagreeing),
# so waiting for that window to prove a fix is not repeatable on demand.
# harness_cdr_report_window() never reads "now" -- given the same calldate
# string, it always produces the same [calldate-margin, calldate+margin]
# window -- so it can be exercised here with fixed, hand-picked calldate
# values covering the boundary shapes that matter, at any time of day.
#
# This does not replace running the real call-smoke/trunk-smoke suites; it
# proves the shared window-calculation logic itself is correct in isolation.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
log() { harness_log "$@"; }

harness_require_containers asterisk

# assert_window <label> <calldate> <margin> <expected_start_date> <expected_start_hour> <expected_end_date> <expected_end_hour>
assert_window() {
    local label="$1" calldate="$2" margin="$3"
    local exp_start_date="$4" exp_start_hour="$5" exp_end_date="$6" exp_end_hour="$7"

    if ! harness_cdr_report_window "$calldate" "$margin"; then
        harness_bad "$label" "harness_cdr_report_window failed for calldate='$calldate' margin=$margin"
        return
    fi

    if [ "$HARNESS_REPORT_START_DATE" = "$exp_start_date" ] \
        && [ "$HARNESS_REPORT_START_HOUR" = "$exp_start_hour" ] \
        && [ "$HARNESS_REPORT_END_DATE" = "$exp_end_date" ] \
        && [ "$HARNESS_REPORT_END_HOUR" = "$exp_end_hour" ]; then
        harness_ok "$label" "calldate='$calldate' margin=$margin -> [${HARNESS_REPORT_START_DATE} ${HARNESS_REPORT_START_HOUR}, ${HARNESS_REPORT_END_DATE} ${HARNESS_REPORT_END_HOUR}]"
    else
        harness_bad "$label" "calldate='$calldate' margin=$margin -> got [${HARNESS_REPORT_START_DATE} ${HARNESS_REPORT_START_HOUR}, ${HARNESS_REPORT_END_DATE} ${HARNESS_REPORT_END_HOUR}], expected [${exp_start_date} ${exp_start_hour}, ${exp_end_date} ${exp_end_hour}]"
    fi
}

log "==> deterministic timezone-boundary cases"

# 1. Normal daytime -- no boundary anywhere nearby; both ends stay on the
#    same calendar day as calldate itself.
assert_window "normal daytime" \
    "2026-06-15 14:30:00" 5 \
    "2026-06-15" "14:25:00" "2026-06-15" "14:35:00"

# 2. Immediately before local midnight -- the +margin end must roll over
#    to the next calendar day; the old $TODAY-based code would have used
#    only the *start* day for both ends and missed this.
assert_window "immediately before local midnight" \
    "2026-08-29 23:58:00" 5 \
    "2026-08-29" "23:53:00" "2026-08-30" "00:03:00"

# 3. Immediately after local midnight -- the -margin start must roll back
#    to the previous calendar day.
assert_window "immediately after local midnight" \
    "2026-08-30 00:02:00" 5 \
    "2026-08-29" "23:57:00" "2026-08-30" "00:07:00"

# 4. A real value from this project's own investigation: the exact UTC
#    calldate recorded for a call placed at local 22:06:02 -03 on
#    2026-08-29 (calldate is stored ~3h ahead of local wall time here --
#    see the doc). The old code computed $TODAY from the *local*
#    calendar day (2026-08-29) and would have missed this UTC-dated row
#    entirely; this function needs no notion of "local" or "UTC" at all
#    to get it right, since it only ever offsets calldate's own value.
assert_window "local/UTC calendar-day divergence case" \
    "2026-08-30 01:06:02" 5 \
    "2026-08-30" "01:01:02" "2026-08-30" "01:11:02"

# 5. Empty calldate must fail closed, not silently default to "now"
#    (GNU date's own behavior for a blank -d string) -- a caller bug
#    (missing CDR) must surface as a failure, never as a bogus window.
if harness_cdr_report_window "" 5; then
    harness_bad "empty calldate fails closed" "harness_cdr_report_window unexpectedly succeeded for an empty calldate"
else
    harness_ok "empty calldate fails closed" "harness_cdr_report_window correctly returned failure for an empty calldate"
fi

harness_complete
