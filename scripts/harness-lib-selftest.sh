#!/bin/bash
#
# harness-lib-selftest.sh -- TASK-0027A remediation.
#
# Deterministic proof that scripts/lib/harness.sh's PASS/FAIL/BLOCKED/
# INCONCLUSIVE classification and summary printing work correctly on
# this project's actual bash 3.2 host shell (macOS ships /bin/bash 3.2;
# every caller of this library runs `set -u`/`set -uo pipefail`).
#
# Covers the exact live crash found during TASK-0027A's own regression
# run: bash 3.2 treats "${arr[@]}" on a *truly empty* array as an
# unbound-variable error under `set -u` (fixed in bash >=4.4) --
# harness_print_summary's row loop hit this whenever harness_finalize
# ran before a single harness_ok/harness_bad call, e.g.
# trunk-smoke-test.sh's harness_require_containers failing as the very
# first check. See docs/tasks/0027a-timezone-safe-cdr-regression.md.
#
# No live containers/services needed -- this only exercises the shared
# library's own bash-level state machine, each scenario in an isolated
# child bash process (harness.sh's global state is meant to be used
# once per process, same as any real caller).
#
# A pure, self-contained, no-environment-dependency check, like
# authorization-coverage-check.sh: exit 0 (PASS) or 1 (FAIL) only, per
# the same accepted variant of the shared PASS/FAIL/BLOCKED/INCONCLUSIVE
# vocabulary scripts/regression.sh already documents for that script.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_LIB="$SCRIPT_DIR/lib/harness.sh"

PASS_COUNT=0
FAIL_COUNT=0

# check <label> <expected_exit_code> <expected_output_substring> <body>
check() {
    local label="$1" expected_exit="$2" expected_pattern="$3" body="$4"
    local out exit_code
    out="$(bash -c "set -uo pipefail; source '$HARNESS_LIB'; harness_install_traps; $body" 2>&1)"
    exit_code=$?
    if echo "$out" | grep -qi "unbound variable"; then
        echo "FAIL: $label -- crashed with an unbound-variable error: $out"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi
    if [ "$exit_code" != "$expected_exit" ]; then
        echo "FAIL: $label -- expected exit $expected_exit, got $exit_code: $out"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi
    if ! echo "$out" | grep -qF "$expected_pattern"; then
        echo "FAIL: $label -- expected to find '$expected_pattern' in output: $out"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi
    echo "PASS: $label -- exit=$exit_code"
    PASS_COUNT=$((PASS_COUNT + 1))
}

echo "==> harness.sh state-machine self-test (running under bash ${BASH_VERSION})"

# 1. BLOCKED with zero rows recorded -- the exact crash scenario found
#    live (harness_require_containers failing as the very first check,
#    before any harness_ok/harness_bad has ever run).
check "BLOCKED with zero rows does not crash" 2 "RESULT: BLOCKED" \
    'harness_blocked "no rows yet"'

# 2. PASS with zero rows recorded -- same empty-row summary path,
#    different classification (a script that never calls
#    harness_ok/harness_bad at all before harness_complete).
check "PASS with zero rows does not crash" 0 "RESULT: PASS" \
    'harness_complete'

# 3. PASS with one real row -- the summary must still render the row
#    correctly, not just avoid crashing on the empty case.
check "PASS with one row renders correctly" 0 "some check" \
    'harness_ok "some check" "worked"; harness_complete'

# 4. FAIL -- classification and summary both correct with a mix of
#    passing and failing rows.
check "FAIL with mixed rows classifies FAIL" 1 "RESULT: FAIL" \
    'harness_ok "check one" "fine"; harness_bad "check two" "broken"; harness_complete'

# 5. INCONCLUSIVE -- the script exits without ever calling
#    harness_complete/harness_blocked (e.g. an uncaught error mid-script);
#    the EXIT trap must still finalize cleanly, on the same empty-row
#    path as case 1, and classify INCONCLUSIVE rather than crashing or
#    silently disappearing.
check "unfinished run classifies INCONCLUSIVE" 3 "RESULT: INCONCLUSIVE" \
    'true'

# 6-7. harness_require_containers's new bounded retry (TASK-0027A
#    remediation of the transient container-settling race): still
#    PASSes immediately when a container is genuinely up, and still
#    BLOCKS -- boundedly, not infinitely -- when one never comes up, via
#    a fake $COMPOSE so this needs no real Docker containers.
check "harness_require_containers PASSes when already up" 0 "containers healthy" \
    'COMPOSE="fake_compose_up"; fake_compose_up() { echo "svc Up"; }; harness_require_containers svc; harness_complete'

check "harness_require_containers BLOCKS (bounded) when never up" 2 "RESULT: BLOCKED" \
    'COMPOSE="fake_compose_down"; fake_compose_down() { echo "svc Exited"; }; harness_require_containers svc; harness_complete'

echo
echo "================================================================"
echo "PASS: $PASS_COUNT   FAIL: $FAIL_COUNT"
echo "================================================================"
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "RESULT: PASS (harness-lib-selftest.sh)"
    exit 0
else
    echo "RESULT: FAIL (harness-lib-selftest.sh)"
    exit 1
fi
