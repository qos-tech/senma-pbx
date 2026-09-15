#!/bin/bash
#
# TASK-0035E6 — status detail messages & operational feedback UX.
#
# Deterministic proofs (no telephony behavior change):
#   1. Presenter hides detail for healthy ACTIVE
#   2. Presenter keeps concise offline / unavailable / unknown / error detail
#   3. Presenter suppresses redundant primary-echo details
#   4. Presenter suppresses exception / diagnostic leakage
#   5. Presenter truncates overlong detail
#   6. Manager source no longer emits "Registered -- reachable" success prose
#   7. StatusBadge routes detail through Presenter (source contract)
#   8. Extensions Diagnostics uses shared statusBadge (no local maps)
#   9. Transport ACTIVE normalizeStatus uses empty detail
#  10. System-status RUNNING healthy detail is empty
#
# Does not depend on a destructive restore or real pilot host.
#
# Exit code: see scripts/lib/harness.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

cd "$REPO_ROOT" || harness_blocked "could not cd into repo root"

log() { harness_log "$@"; }

COMPOSE="${SMOKE_COMPOSE:-docker compose}"

# ---------------------------------------------------------------------------
# PHP Presenter matrix (runs inside app container; no AMI required)
# ---------------------------------------------------------------------------
log "==> Presenter operatorDetail matrix"
PRESENTER_OUT="$(mktemp)"
harness_register_best_effort_cleanup "presenter out" "rm -f '$PRESENTER_OUT'"

$COMPOSE exec -T app php <<'PHP' >"$PRESENTER_OUT"
<?php
require_once '/var/www/html/snep/lib/Snep/PjsipStatus/Manager.php';
require_once '/var/www/html/snep/lib/Snep/PjsipStatus/Presenter.php';

function assert_eq($name, $got, $want) {
    if ($got === $want) {
        echo "PASS|$name|$got\n";
    } else {
        echo "FAIL|$name|got=" . var_export($got, true) . " want=" . var_export($want, true) . "\n";
    }
}

$P = 'Snep_PjsipStatus_Presenter';
$M = 'Snep_PjsipStatus_Manager';

// 1. Healthy ACTIVE → empty (even if producer sent success prose)
assert_eq('healthy-active-empty', $P::operatorDetail($M::ACTIVE, ''), '');
assert_eq('healthy-active-strips-reachable', $P::operatorDetail($M::ACTIVE, 'Registered -- reachable (12ms)'), '');
assert_eq('healthy-active-strips-qualify-off', $P::operatorDetail($M::ACTIVE, 'Registered -- reachability not monitored (qualify disabled)'), '');

// 2. Offline / unavailable / unknown / error keep concise detail
assert_eq('inactive-no-contact', $P::operatorDetail($M::INACTIVE, 'No SIP contact registered'), 'No SIP contact registered');
assert_eq('unknown-unavailable', $P::operatorDetail($M::UNKNOWN, 'Runtime status unavailable'), 'Runtime status unavailable');
assert_eq('error-rejected', $P::operatorDetail($M::ERROR, 'Registration rejected by provider'), 'Registration rejected by provider');
assert_eq('degraded-not-responding', $P::operatorDetail($M::DEGRADED, 'Not responding to reachability checks'), 'Not responding to reachability checks');
assert_eq('pending-reachability', $P::operatorDetail($M::PENDING, 'Reachability check pending'), 'Reachability check pending');

// 3. Redundant primary echo → empty
assert_eq('redundant-offline', $P::operatorDetail($M::INACTIVE, 'Offline'), '');
assert_eq('redundant-endpoint-offline', $P::operatorDetail($M::INACTIVE, 'Endpoint is offline'), '');
assert_eq('redundant-error', $P::operatorDetail($M::ERROR, 'Error'), '');

// 4. Exception / diagnostic leakage → safe fallback (not raw text)
$leak = $P::operatorDetail($M::UNKNOWN, 'PDOException: SQLSTATE[HY000] in /var/www/foo.php on line 42');
if ($leak !== '' && stripos($leak, 'PDOException') === false && stripos($leak, 'SQLSTATE') === false) {
    echo "PASS|leak-suppressed|$leak\n";
} else {
    echo "FAIL|leak-suppressed|got=" . var_export($leak, true) . "\n";
}
$nullish = $P::operatorDetail($M::ERROR, 'null');
if ($nullish !== '' && strtolower($nullish) !== 'null') {
    echo "PASS|nullish-suppressed|$nullish\n";
} else {
    echo "FAIL|nullish-suppressed|got=" . var_export($nullish, true) . "\n";
}

// 5. Truncation
$long = str_repeat('x', 200);
$trunc = $P::operatorDetail($M::PENDING, $long);
$len = function_exists('mb_strlen') ? mb_strlen($trunc) : strlen($trunc);
$endsOk = (function_exists('mb_substr') && mb_substr($trunc, -1) === '…')
    || substr($trunc, -3) === '...'
    || substr($trunc, -1) === '…';
if ($len <= 120 && $endsOk) {
    echo "PASS|truncation|$len\n";
} else {
    echo "FAIL|truncation|len=$len endsOk=" . var_export($endsOk, true) . " val=" . var_export($trunc, true) . "\n";
}

// Transition semantics (same snapshot derivation): error→healthy clears;
// healthy→error adds detail. Presenter is pure; prove both directions.
assert_eq('transition-error-to-healthy', $P::operatorDetail($M::ACTIVE, 'Registration rejected by provider'), '');
assert_eq('transition-healthy-to-error', $P::operatorDetail($M::ERROR, 'Registration rejected by provider'), 'Registration rejected by provider');

// Malformed / missing
assert_eq('missing-detail', $P::operatorDetail($M::UNKNOWN, null), '');
assert_eq('empty-state', $P::operatorDetail('', 'something'), '');
PHP

PRESENTER_FAIL=0
while IFS='|' read -r result name detail; do
    [ -n "$result" ] || continue
    if [ "$result" = "PASS" ]; then
        harness_ok "presenter: $name" "$detail"
    else
        harness_bad "presenter: $name" "$detail"
        PRESENTER_FAIL=1
    fi
done < "$PRESENTER_OUT"

if [ ! -s "$PRESENTER_OUT" ]; then
    harness_bad "presenter matrix produced output" "empty — PHP may have failed"
fi

# ---------------------------------------------------------------------------
# Source contracts (no runtime mutation)
# ---------------------------------------------------------------------------
log "==> source contracts"

if ! grep -E "^[^/]*Registered -- reachable" "$REPO_ROOT/snep/lib/Snep/PjsipStatus/Manager.php" \
   && ! grep -E "return self::status\(self::ACTIVE, 'Registered" "$REPO_ROOT/snep/lib/Snep/PjsipStatus/Manager.php"; then
    harness_ok "manager: no Registered -- reachable prose" "success RTT detail removed at source"
else
    harness_bad "manager: no Registered -- reachable prose" "still present in Manager.php"
fi

if ! grep -q 'Could not query Asterisk runtime state' "$REPO_ROOT/snep/lib/Snep/PjsipStatus/Manager.php"; then
    harness_ok "manager: short unavailable wording" "legacy long AMI phrase removed"
else
    harness_bad "manager: short unavailable wording" "legacy phrase still present"
fi

if grep -q 'Snep_PjsipStatus_Presenter::operatorDetail' "$REPO_ROOT/snep/lib/Snep/View/Helper/StatusBadge.php"; then
    harness_ok "statusBadge uses Presenter" "operatorDetail gate present"
else
    harness_bad "statusBadge uses Presenter" "Presenter call missing"
fi

if grep -q 'snep-status-detail' "$REPO_ROOT/snep/lib/Snep/View/Helper/StatusBadge.php" \
   && grep -q 'snep-status-detail' "$REPO_ROOT/snep/css/snep.css"; then
    harness_ok "detail CSS class wired" "help-block snep-status-detail"
else
    harness_bad "detail CSS class wired" "class missing in badge and/or css"
fi

if grep -q 'statusBadge' "$REPO_ROOT/snep/modules/default/views/scripts/extensions/addedit.phtml" \
   && ! grep -q "badgeClass = array('ACTIVE'" "$REPO_ROOT/snep/modules/default/views/scripts/extensions/addedit.phtml"; then
    harness_ok "extensions Diagnostics uses statusBadge" "local maps removed"
else
    harness_bad "extensions Diagnostics uses statusBadge" "still has local badge maps or missing helper"
fi

if grep -q "case 'active':" -A3 "$REPO_ROOT/snep/modules/default/controllers/PjsipTransportsController.php" \
   | grep -q "'detail' => ''"; then
    harness_ok "transport ACTIVE detail empty" "normalizeStatus active → empty detail"
else
    # Fallback: read the switch block more loosely
    if python3 - <<'PY'
from pathlib import Path
t = Path("snep/modules/default/controllers/PjsipTransportsController.php").read_text()
i = t.find("case 'active':")
j = t.find("case 'restart_required':", i)
chunk = t[i:j]
raise SystemExit(0 if "detail' => ''" in chunk or 'detail" => ""' in chunk or "detail' => \"\"" in chunk else 1)
PY
    then
        harness_ok "transport ACTIVE detail empty" "normalizeStatus active → empty detail"
    else
        harness_bad "transport ACTIVE detail empty" "active case still has non-empty detail"
    fi
fi

if grep -n "return self::state('RUNNING'" "$REPO_ROOT/snep/lib/Snep/Asterisk/Operations.php" | head -5 \
   | grep -q "''"; then
    harness_ok "system-status RUNNING detail empty" "healthy RUNNING has no success prose"
else
    # Check both RUNNING returns
    if python3 - <<'PY'
from pathlib import Path
import re
t = Path("snep/lib/Snep/Asterisk/Operations.php").read_text()
# All RUNNING state() calls should use empty detail after E6 for healthy paths
matches = re.findall(r"self::state\('RUNNING',\s*([^,\)]+)", t)
ok = all(m.strip() in ("''", '""') for m in matches)
raise SystemExit(0 if ok and matches else 1)
PY
    then
        harness_ok "system-status RUNNING detail empty" "all RUNNING details empty"
    else
        harness_bad "system-status RUNNING detail empty" "RUNNING still has non-empty detail"
    fi
fi

if grep -q 'restartStateSep' "$REPO_ROOT/snep/modules/default/views/scripts/systemstatus/index.phtml" \
   && grep -q 'state.detail ||' "$REPO_ROOT/snep/modules/default/views/scripts/systemstatus/index.phtml"; then
    harness_ok "system-status poll clears stale detail" "applyState hides empty detail/sep"
else
    harness_bad "system-status poll clears stale detail" "applyState contract missing"
fi

harness_complete
