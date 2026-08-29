#!/bin/bash
#
# Canonical lint/static-check gate (TASK-0027, Phase 9).
#
# Docker-first per CLAUDE.md -- host PHP is not required. Every PHP-aware
# check runs inside the already-running app container against the
# bind-mounted source tree; only plain bash/git checks (assumed present
# for any dev workflow on this project) run on the host.
#
# Checks:
#   1. `php -l` across every PHP file under snep/ (inside the app
#      container).
#   2. `bash -n` across every harness script under scripts/ and
#      scripts/lib/ (on the host).
#   3. XML well-formedness for every resources.xml (inside the app
#      container, via PHP's DOMDocument -- no xmllint binary is
#      installed in the image and none is added for this).
#   4. `git diff --check` for the current working-tree diff (whitespace
#      errors: trailing whitespace, conflict markers).
#
# Deliberately lightweight -- no external lint framework introduced.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log() { harness_log "$@"; }

harness_require_containers app

# --- 1. PHP syntax check (php -l) inside the app container -----------------

log "==> php -l across snep/ (inside the app container, project code only)"
# TASK-0027 finding: `xargs -0 -n1 php -l` stops at the FIRST syntax
# error and silently never checks the rest of the tree -- `php -l` exits
# 255 on a parse error, and GNU xargs' documented behavior is to abort
# immediately (no further input read) the moment any invocation exits
# 255. Live-confirmed: with 2828 PHP files under snep/, xargs silently
# stopped after only 101. A plain read loop has no such special-exit-code
# abort behavior and always finishes the whole list.
#
# snep/lib/Zend (Zend Framework 1) and snep/lib/linfo (Linfo, (c)
# 2010-2015 Joseph Gillotti) are third-party vendored libraries with
# their own upstream copyright, not "relevant project PHP files" per
# this phase's own instruction. Excluding them is not hiding a defect:
# php -l against the full tree found exactly one pre-existing failure,
# snep/lib/Zend/Validate/Isbn.php using the `$str{$i}` curly-brace
# string-offset syntax PHP 8 removed -- CLAUDE.md's own "Current
# operating rule" explicitly defers "curly-brace migration" to a future,
# separately-authorized task. Documented in
# docs/tasks/0027-regression-harness-reliability.md, not fixed here.
PHP_LINT_OUTPUT="$($COMPOSE exec -T app sh -c "find /var/www/html/snep -name '*.php' -not -path '*/lib/Zend/*' -not -path '*/lib/linfo/*' | while IFS= read -r f; do php -l \"\$f\" 2>&1; done")"
PHP_LINT_ERROR_LINES="$(echo "$PHP_LINT_OUTPUT" | grep -c "^PHP Parse error\|^Errors parsing" || true)"
PHP_FILE_COUNT="$(echo "$PHP_LINT_OUTPUT" | grep -c "No syntax errors detected" || true)"
if [ "${PHP_LINT_ERROR_LINES:-0}" -eq 0 ] && [ "${PHP_FILE_COUNT:-0}" -gt 0 ]; then
    harness_ok "php -l (snep/)" "${PHP_FILE_COUNT} PHP files, 0 syntax errors"
else
    harness_bad "php -l (snep/)" "${PHP_LINT_ERROR_LINES:-0} file(s) with syntax errors (checked ${PHP_FILE_COUNT:-0}): $(echo "$PHP_LINT_OUTPUT" | grep "^PHP Parse error\|^Errors parsing" | head -5)"
fi

# --- 2. bash -n across every harness script (host) --------------------------

log "==> bash -n across scripts/"
BASH_LINT_FAIL=0
BASH_LINT_COUNT=0
for f in "$ROOT"/scripts/*.sh "$ROOT"/scripts/lib/*.sh; do
    [ -f "$f" ] || continue
    BASH_LINT_COUNT=$((BASH_LINT_COUNT + 1))
    if ! err="$(bash -n "$f" 2>&1)"; then
        harness_bad "bash -n $(basename "$f")" "$err"
        BASH_LINT_FAIL=1
    fi
done
[ "$BASH_LINT_FAIL" = "0" ] && harness_ok "bash -n (scripts/)" "${BASH_LINT_COUNT} shell scripts parse cleanly"

# --- 3. XML well-formedness for resources.xml (inside the app container) ---

log "==> XML well-formedness for resources.xml (inside the app container, via PHP DOMDocument)"
XML_FAIL=0
XML_COUNT=0
for f in "$ROOT"/snep/modules/*/resources.xml; do
    [ -f "$f" ] || continue
    XML_COUNT=$((XML_COUNT + 1))
    rel="/var/www/html/snep/modules/$(basename "$(dirname "$f")")/resources.xml"
    label="modules/$(basename "$(dirname "$f")")/resources.xml"
    if err="$($COMPOSE exec -T app php -r '
        libxml_use_internal_errors(true);
        $d = new DOMDocument();
        if (!$d->load($argv[1])) {
            foreach (libxml_get_errors() as $e) { fwrite(STDERR, trim($e->message) . "\n"); }
            exit(1);
        }
        exit(0);
    ' -- "$rel" 2>&1)"; then
        :
    else
        harness_bad "xml well-formed: $label" "$err"
        XML_FAIL=1
    fi
done
[ "$XML_FAIL" = "0" ] && harness_ok "XML well-formedness (resources.xml)" "${XML_COUNT} resources.xml files parse as well-formed XML"

# --- 4. git diff --check (host) ---------------------------------------------

log "==> git diff --check"
cd "$ROOT"
if diff_check_output="$(git diff --check 2>&1)"; then
    harness_ok "git diff --check" "no whitespace errors in the working-tree diff"
else
    harness_bad "git diff --check" "$diff_check_output"
fi

harness_complete
