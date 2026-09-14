#!/bin/bash
#
# TASK-0033E: application readiness contract.
#
# A bare `curl -f http://localhost/` (the pre-existing check) only
# proves Apache answers a socket -- it does not prove PHP bootstrap
# succeeded or that DB connectivity works (confirmed in TASK-0033's own
# audit, and reproduced again during this task's own validation: with
# the `db` container stopped, `curl -f http://localhost/` alone would
# still report an HTTP response, just a 500 one). READY here means the
# login page actually RENDERS its expected content -- SENMA's login
# page reads system/company settings from the database as part of
# normal rendering, so a successful render is real evidence the PHP
# application bootstrapped AND reached the database, not just that
# Apache is listening.
#
# No dedicated readiness endpoint was added: the existing login page is
# already a safe (unauthenticated, read-only, no side effects), cheap,
# stable content signature to assert against -- adding a new endpoint
# would be unjustified extra surface for the same evidence this task's
# own investigation already confirmed the existing page provides (see
# docs/tasks/0033e-readiness-contract-hardening.md APPLICATION
# READINESS CONTRACT).
#
# Secret safety: no credential is used by this check at all.
#
# Exit 0 + "READY: ..." when the page renders as expected; exit 1 + a
# single concise "FAIL: <reason>" line otherwise.

set -uo pipefail

BODY="$(curl -sS --max-time 4 "${APP_HEALTHCHECK_URL:-http://localhost/}" 2>&1)"
RC=$?
if [ "$RC" -ne 0 ]; then
    echo "FAIL: HTTP request to ${APP_HEALTHCHECK_URL:-http://localhost/} failed (curl exit $RC)"
    exit 1
fi

if ! printf '%s' "$BODY" | grep -q '<title>SNEP - Login</title>'; then
    echo "FAIL: login page did not render as expected (possible DB/bootstrap failure)"
    exit 1
fi

echo "READY: login page rendered"
exit 0
