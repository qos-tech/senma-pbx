#!/bin/bash
#
# Canonical serial release-regression gate (TASK-0027, Phase 10).
#
# Runs every canonical smoke/lint suite in one documented, deterministic
# order and prints a single final matrix. This is the one command a
# release-readiness check should run -- see
# docs/tasks/0027-regression-harness-reliability.md.
#
# Every suite below already implements the shared PASS/FAIL/BLOCKED/
# INCONCLUSIVE contract from scripts/lib/harness.sh (exit codes
# 0/1/2/3), except authorization-coverage-check.sh, a pure static check
# with no environment dependency that only ever produces 0 (PASS) or 1
# (FAIL) -- both already fit the same vocabulary. This runner never
# treats a nonzero exit as PASS, and never silently skips a suite.
#
# Suites run strictly serially, in the order below, on purpose --
# multiple suites share the same dev Asterisk/app/db containers, and
# running stateful telephony suites concurrently against that shared
# state produces spurious failures (confirmed during this task's own
# validation: running external-content-smoke while restart-smoke was
# mid-restart produced an HTTP 500 with no product defect behind it).
#
# Exit code: 0 if every suite PASSed, 1 if any suite did not (FAIL,
# BLOCKED, or INCONCLUSIVE all count as non-green here).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

classification_name() {
    case "$1" in
        0) echo "PASS" ;;
        1) echo "FAIL" ;;
        2) echo "BLOCKED" ;;
        3) echo "INCONCLUSIVE" ;;
        *) echo "UNKNOWN(exit $1)" ;;
    esac
}

SUITE_NAMES=()
SUITE_CODES=()

run_suite() {
    local name="$1" script="$2"
    echo
    echo "################################################################"
    echo "### REGRESSION: starting ${name} ($(date '+%Y-%m-%d %H:%M:%S'))"
    echo "################################################################"
    bash "$SCRIPT_DIR/$script"
    local code=$?
    SUITE_NAMES+=("$name")
    SUITE_CODES+=("$code")
    echo "### REGRESSION: ${name} -> $(classification_name "$code") (exit $code)"
}

run_suite "lint"                   "lint.sh"
# TASK-0027A: proves the shared harness library's own state machine
# (used by every suite below) is sound on this project's actual bash
# 3.2 host shell before anything that depends on it runs. Pure
# self-contained check, no Docker dependency -- placed right after
# lint for the same reason.
run_suite "harness-lib-selftest"   "harness-lib-selftest.sh"
run_suite "preauth-security"       "preauth-security-smoke-test.sh"
# TASK-0026C: placed right after preauth-security and before
# authorization -- both are pre-/independent-of-authorization SQL-
# boundary proofs; sql-security additionally needs an authenticated
# admin session for most of its checks, same precondition
# authorization-smoke/authorization-coverage need next.
run_suite "sql-security"           "sql-security-smoke-test.sh"
run_suite "authorization-coverage" "authorization-coverage-check.sh"
run_suite "authorization-smoke"    "authorization-smoke-test.sh"
run_suite "http-smoke"             "smoke-test.sh"
# TASK-0027A: fixed-timestamp proof of harness_cdr_report_window(),
# which call-smoke/trunk-smoke's own CDR report-readback checks depend
# on -- placed immediately before them so a regression in the shared
# window logic itself is caught here rather than only showing up as a
# confusing report-readback failure two suites later.
run_suite "cdr-window-selftest"    "cdr-window-selftest.sh"
run_suite "call-smoke"             "call-smoke-test.sh"
run_suite "trunk-smoke"            "trunk-smoke-test.sh"
run_suite "transport-smoke"        "transport-smoke-test.sh"
run_suite "restart-smoke"          "restart-smoke-test.sh"
run_suite "external-failure-smoke" "external-failure-smoke-test.sh"
run_suite "external-content-smoke" "external-content-smoke-test.sh"

echo
echo "================================================================"
printf "%-30s %s\n" "SUITE" "RESULT"
echo "----------------------------------------------------------------"
overall=0
for i in "${!SUITE_NAMES[@]}"; do
    name="${SUITE_NAMES[$i]}"
    code="${SUITE_CODES[$i]}"
    result="$(classification_name "$code")"
    printf "%-30s %s\n" "$name" "$result"
    [ "$code" -ne 0 ] && overall=1
done
echo "----------------------------------------------------------------"
if [ "$overall" -eq 0 ]; then
    printf "%-30s %s\n" "REGRESSION" "PASS"
else
    printf "%-30s %s\n" "REGRESSION" "FAIL"
fi
echo "================================================================"

exit "$overall"
