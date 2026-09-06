#!/bin/bash
#
# SENMA Transport + shared runtime UX foundation smoke test (TASK-0032).
#
# TASK-0030's audit found the transport administration surface already
# solved "configuration saved" vs "runtime active" (TASK-0020) but used
# its own disjoint status vocabulary/markup, its own dependency-warning
# wording, and its own save/apply flash rendering -- each duplicated a
# third time alongside the Extensions/Trunks copies TASK-0031 had already
# deduplicated down to two. This suite proves the shared primitives this
# task introduced (Snep_View_Helper_StatusBadge/ApplyFeedback/
# DependencyWarning) actually unify all three surfaces against the real
# application/Asterisk stack -- never mocked:
#
#   transport list status column   -> ONE shared badge, carrying BOTH the
#                                      new data-runtime-status (shared
#                                      7-state vocabulary) and the
#                                      pre-existing data-runtime-state
#                                      (TASK-0020, unchanged) attributes
#   transport protocol disclosure  -> hidden/aria-hidden (not a
#                                      visible/invisible CSS class)
#   WSS vs native TLS wording      -> distinct certificate-ownership
#                                      explanation per protocol
#   transport Diagnostics          -> a real runtime-status badge on the
#                                      edit page (previously absent)
#   dependency-warning panel       -> "Cannot remove <type> '<name>'."
#                                      wording, no raw SQL/exception leak,
#                                      for extension/trunk/transport alike
#   delete success feedback        -> a real flash, for extension/trunk
#                                      delete (previously a silent 302)
#   responsive list columns        -> hidden-xs/hidden-sm on the
#                                      transport list's secondary columns
#   runtime-query failure          -> an explicit banner + UNKNOWN badges,
#                                      never a crash, never a fabricated
#                                      "no transports configured"
#
# See docs/tasks/0032-transport-shared-runtime-ux-foundation.md.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
TEST_USER="admin"
# TASK-0032: matches the documented "SmokeTest123!" dev baseline every
# other suite in this repo uses (confirmed by inspection --
# scripts/auth-hardening-security-smoke-test.sh's own comment calls it
# out explicitly, and scripts/preauth-security-smoke-test.sh relies on it
# being already set to this value without setting it itself). A
# different value here left the DB in a state that broke
# preauth-security-smoke-test.sh when this suite ran earlier in the same
# session outside the regular regression order -- never repeat that.
TEST_PASSWORD="SmokeTest123!"
FIXTURE_MARKER="task0032"

TEST_EXT="1291"
TEST_TRANSPORT_NAME="task0032-udp"
TEST_TRANSPORT_PORT="5091"

log() { harness_log "@$*"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

# --- 1. Preconditions ----------------------------------------------------

harness_require_containers app db asterisk

log "==> checking for leftover fixtures from a prior interrupted run"
LEFTOVER_EXT="$(db_query "SELECT name FROM peers WHERE name='${TEST_EXT}';")"
if [ -n "$LEFTOVER_EXT" ]; then
    harness_blocked "leftover extension fixture (${TEST_EXT}) found -- refusing to proceed"
fi
LEFTOVER_TRANSPORT="$(db_query "SELECT id FROM pjsip_transports WHERE name='${TEST_TRANSPORT_NAME}';")"
if [ -n "$LEFTOVER_TRANSPORT" ]; then
    harness_blocked "leftover transport fixture (${TEST_TRANSPORT_NAME}) found -- refusing to proceed"
fi

COOKIEJAR="$(mktemp)"
harness_register_best_effort_cleanup "cookie jar temp file" "rm -f '$COOKIEJAR'"
TEST_HASH="$($COMPOSE exec -T app php -r "echo md5('${TEST_PASSWORD}');" 2>/dev/null | tr -d '\r')"
if [ -z "$TEST_HASH" ]; then
    harness_blocked "could not compute the ${TEST_USER} password hash via the app container"
fi
db_query "UPDATE users SET password = '${TEST_HASH}' WHERE name = '${TEST_USER}';" >&2
curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -d "user=${TEST_USER}&password=${TEST_PASSWORD}" "${BASE_URL}/index.php/auth/login"
ADMIN_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
if [ -z "$ADMIN_CSRF" ]; then harness_blocked "could not read the admin session's CSRF token"; fi

fetch() {
    # fetch <url> <out_file> -- prints the HTTP status code.
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$2" -w '%{http_code}' "$1"
}

# =============================================================================
# PART A -- shared status badge on all three list pages
# =============================================================================

log "==> [A] extensions/trunks/transports list pages render the shared status vocabulary"
EXT_LIST="$(mktemp)"; harness_register_best_effort_cleanup "ext list temp file" "rm -f '$EXT_LIST'"
TRUNK_LIST="$(mktemp)"; harness_register_best_effort_cleanup "trunk list temp file" "rm -f '$TRUNK_LIST'"
# extensions/trunks data-runtime-status presence is checked in PART D,
# once real row fixtures exist -- an empty table renders no <tr> at all,
# so checking on the CURRENT (possibly empty) DB state here would be
# meaningless, not a product check.

TRANSPORT_LIST="$(mktemp)"; harness_register_best_effort_cleanup "transport list temp file" "rm -f '$TRANSPORT_LIST'"
fetch "${BASE_URL}/index.php/default/pjsip-transports" "$TRANSPORT_LIST" >/dev/null
if grep -q 'data-runtime-status="ACTIVE"' "$TRANSPORT_LIST" && grep -q 'data-runtime-state="active"' "$TRANSPORT_LIST"; then
    harness_ok "transport list status column carries BOTH attributes" "shared data-runtime-status=\"ACTIVE\" AND legacy data-runtime-state=\"active\" coexist on the merged status cell (scripts/transport-smoke-test.sh's own t20_runtime_badge() still finds what it expects)"
else
    harness_bad "transport list status column carries BOTH attributes" "expected both data-runtime-status=\"ACTIVE\" and data-runtime-state=\"active\" somewhere on the list page (a seeded enabled transport should be ACTIVE) -- got: $(grep -o 'data-runtime-stat[a-z]*="[A-Za-z_]*"' "$TRANSPORT_LIST" | tr '\n' ' ')"
fi

if grep -qE '<th class="text-center">Status</th>' "$TRANSPORT_LIST" && ! grep -qE '<th class="text-center">Runtime</th>' "$TRANSPORT_LIST"; then
    harness_ok "transport list has ONE merged Status column" "the separate Runtime column header is gone -- Phase 4/12's merged-column decision"
else
    harness_bad "transport list has ONE merged Status column" "expected a single 'Status' header and no separate 'Runtime' header"
fi

log "==> [A] transport list responsive priority columns"
if grep -qE '<th class="text-center hidden-xs' "$TRANSPORT_LIST"; then
    harness_ok "transport list has responsive secondary columns" "hidden-xs/hidden-sm utility classes present (Phase 12), matching the pattern TASK-0031 already used for Extensions/Trunks"
else
    harness_bad "transport list has responsive secondary columns" "no hidden-xs/hidden-sm column found"
fi

# =============================================================================
# PART B -- transport protocol-specific disclosure (hidden/aria-hidden)
# =============================================================================

log "==> [B] transport add page: TLS fieldset hidden for the udp default, via the hidden attribute"
ADD_PAGE="$(mktemp)"; harness_register_best_effort_cleanup "transport add page temp file" "rm -f '$ADD_PAGE'"
fetch "${BASE_URL}/index.php/default/pjsip-transports/add" "$ADD_PAGE" >/dev/null
if grep -q 'id="transport_tls_group" hidden aria-hidden="true"' "$ADD_PAGE"; then
    harness_ok "TLS fieldset uses hidden/aria-hidden, not a visible/invisible class" "udp (the default protocol) correctly hides it server-side, before any JS runs"
else
    harness_bad "TLS fieldset uses hidden/aria-hidden, not a visible/invisible class" "expected fieldset#transport_tls_group to carry hidden+aria-hidden=true for the udp default"
fi
if grep -q 'className = "visible"\|className = "invisible"' "$ADD_PAGE"; then
    harness_bad "no leftover visible/invisible className toggling" "found the old CSS-class-toggle pattern TASK-0030 flagged as an accessibility gap -- should be gone from this form"
else
    harness_ok "no leftover visible/invisible className toggling" "senmaTransportShowTls() now toggles hidden/aria-hidden only"
fi

# =============================================================================
# PART C -- WSS vs native TLS certificate ownership wording (Phase 16)
# =============================================================================

log "==> [C] existing seeded wss transport: certificate-ownership wording is WSS-specific"
WSS_ID="$(db_query "SELECT id FROM pjsip_transports WHERE protocol='wss' LIMIT 1;")"
if [ -z "$WSS_ID" ]; then
    harness_bad "wss transport fixture available" "no protocol='wss' row found -- expected the TASK-0018/0029A seed row to still exist"
else
    WSS_EDIT="$(mktemp)"; harness_register_best_effort_cleanup "wss edit page temp file" "rm -f '$WSS_EDIT'"
    fetch "${BASE_URL}/index.php/default/pjsip-transports/edit/id/${WSS_ID}" "$WSS_EDIT" >/dev/null
    if grep -q "process-wide HTTP/TLS listener" "$WSS_EDIT" && ! grep -q "applies directly to this transport's own PJSIP TLS context" "$WSS_EDIT"; then
        harness_ok "WSS edit page shows WSS-specific certificate wording" "correctly distinguishes the global HTTP/TLS listener model from a per-transport TLS context (Phase 16)"
    else
        harness_bad "WSS edit page shows WSS-specific certificate wording" "expected the WSS-specific explanation, not the native-TLS one"
    fi
    if grep -q '<span class="label label-' "$WSS_EDIT" && grep -qE "Diagnostics" "$WSS_EDIT"; then
        harness_ok "transport edit page has a Diagnostics section with a runtime badge" "Phase 9 -- previously absent from the edit page entirely"
    else
        harness_bad "transport edit page has a Diagnostics section with a runtime badge" "expected a Diagnostics <details> block containing a status badge"
    fi
fi

# =============================================================================
# PART D -- shared dependency-warning panel (extension/trunk/transport)
# =============================================================================

log "==> [D] creating extension ${TEST_EXT} pinned to a new transport, to prove the transport dependency-block panel"
create_transport() {
    local body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=${TEST_TRANSPORT_NAME}" \
        --data-urlencode "protocol=udp" \
        --data-urlencode "bind_address=0.0.0.0" \
        --data-urlencode "bind_port=${TEST_TRANSPORT_PORT}" \
        --data-urlencode "domain=" \
        --data-urlencode "external_signaling_address=" \
        --data-urlencode "external_signaling_port=" \
        --data-urlencode "external_media_address=" \
        --data-urlencode "local_net=" \
        --data-urlencode "allow_reload=1" \
        --data-urlencode "enabled=1" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/pjsip-transports/add")"
    rm -f "$body"
    [ "$httpcode" = "302" ]
}
if create_transport; then
    harness_ok "transport fixture created" "${TEST_TRANSPORT_NAME}:${TEST_TRANSPORT_PORT}"
else
    harness_blocked "could not create the transport fixture -- cannot proceed with dependency checks"
fi
TRANSPORT_ID="$(db_query "SELECT id FROM pjsip_transports WHERE name='${TEST_TRANSPORT_NAME}';")"
harness_register_cleanup "transport fixture (${TEST_TRANSPORT_NAME})" \
    "curl -sS -c '$COOKIEJAR' -b '$COOKIEJAR' -o /dev/null --data-urlencode id=${TRANSPORT_ID} --data-urlencode snep_csrf_token=\$(harness_csrf_token '$COOKIEJAR' '$BASE_URL') '${BASE_URL}/index.php/default/pjsip-transports/remove'"

create_extension_on_transport() {
    local body httpcode
    body="$(mktemp)"
    httpcode="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$body" -w '%{http_code}' \
        --data-urlencode "name=SENMA ${FIXTURE_MARKER}" \
        --data-urlencode "exten=${TEST_EXT}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "password=${FIXTURE_MARKER}Secret1!" \
        --data-urlencode "passwordpadlock=" \
        --data-urlencode "email=" \
        --data-urlencode "exten_group[]=1" \
        --data-urlencode "pickup_group=" \
        --data-urlencode "transport_id=${TRANSPORT_ID}" \
        --data-urlencode "nat_no=1" \
        --data-urlencode "qualify=1" \
        --data-urlencode "directmedia=no" \
        --data-urlencode "dtmf=rfc2833" \
        --data-urlencode "codec=alaw" --data-urlencode "codec1=ulaw" --data-urlencode "codec2=gsm" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/extensions/add")"
    rm -f "$body"
    [ "$httpcode" = "302" ]
}
if create_extension_on_transport; then
    harness_ok "extension fixture created, pinned to the transport" "${TEST_EXT} -> ${TEST_TRANSPORT_NAME}"
else
    harness_blocked "could not create the extension fixture -- cannot proceed with the transport dependency check"
fi
fetch "${BASE_URL}/index.php/default/extensions" "$EXT_LIST" >/dev/null
if grep -q 'data-runtime-status=' "$EXT_LIST"; then
    harness_ok "extensions list carries data-runtime-status" "shared badge attribute present on the fixture row"
else
    harness_bad "extensions list carries data-runtime-status" "attribute missing -- shared badge helper not wired?"
fi
delete_extension() {
    local csrf
    csrf="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
    curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null -w '%{http_code}' \
        --data-urlencode "id=${TEST_EXT}" --data-urlencode "snep_csrf_token=${csrf}" \
        "${BASE_URL}/index.php/default/extensions/remove" | grep -q "^302$"
}
harness_register_cleanup "extension fixture (${TEST_EXT})" "delete_extension"

TRANSPORT_BLOCK="$(mktemp)"; harness_register_best_effort_cleanup "transport block page temp file" "rm -f '$TRANSPORT_BLOCK'"
fetch "${BASE_URL}/index.php/default/pjsip-transports/remove/id/${TRANSPORT_ID}" "$TRANSPORT_BLOCK" >/dev/null
if grep -qi "SQLSTATE\|PDOException\|Fatal error" "$TRANSPORT_BLOCK"; then
    harness_bad "transport dependency-warning (extension reference)" "raw SQL/exception text leaked into the dependency-blocked page"
elif grep -qF "Cannot remove transport '${TEST_TRANSPORT_NAME}'." "$TRANSPORT_BLOCK" && grep -qF "${TEST_EXT}" "$TRANSPORT_BLOCK"; then
    harness_ok "transport dependency-warning (extension reference)" "canonical 'Cannot remove transport ...' wording, extension ${TEST_EXT} listed, no leak"
else
    harness_bad "transport dependency-warning (extension reference)" "expected the canonical dependency-warning wording naming the transport and extension ${TEST_EXT}"
fi

log "==> [D] extension delete-blocked-by-route + trunk delete-blocked-by-route (shared panel, reusing an existing route fixture)"
ROUTE_ID="$(db_query "SELECT id FROM regras_negocio LIMIT 1;")"
if [ -z "$ROUTE_ID" ]; then
    log "no existing route row to attach a dependency to -- skipping extension/trunk dependency-panel checks (not this task's own fixture data)"
else
    ROUTE_DESC="$(db_query "SELECT \`desc\` FROM regras_negocio WHERE id=${ROUTE_ID};")"
    DESTINO_BACKUP="$(db_query "SELECT destino FROM regras_negocio WHERE id=${ROUTE_ID};")"
    restore_route() {
        local escaped="${DESTINO_BACKUP//\'/\'\'}"
        db_query "UPDATE regras_negocio SET destino='${escaped}' WHERE id=${ROUTE_ID};" >&2
    }
    harness_register_best_effort_cleanup "restore route ${ROUTE_ID} destino" "restore_route"

    # -- extension case --
    db_query "UPDATE regras_negocio SET destino='R:${TEST_EXT}' WHERE id=${ROUTE_ID};" >&2
    EXT_BLOCK="$(mktemp)"; harness_register_best_effort_cleanup "ext block page temp file" "rm -f '$EXT_BLOCK'"
    fetch "${BASE_URL}/index.php/default/extensions/remove/id/${TEST_EXT}" "$EXT_BLOCK" >/dev/null
    if grep -qi "SQLSTATE\|PDOException\|Fatal error" "$EXT_BLOCK"; then
        harness_bad "extension dependency-warning (route reference)" "raw SQL/exception text leaked into the dependency-blocked page"
    elif grep -qF "Cannot remove extension '${TEST_EXT}'." "$EXT_BLOCK" && grep -qF "${ROUTE_ID} - ${ROUTE_DESC}" "$EXT_BLOCK"; then
        harness_ok "extension dependency-warning (route reference)" "canonical 'Cannot remove extension ...' wording, route ${ROUTE_ID} listed, no leak"
    else
        harness_bad "extension dependency-warning (route reference)" "expected the canonical dependency-warning wording naming extension ${TEST_EXT} and route ${ROUTE_ID} - ${ROUTE_DESC}"
    fi
    restore_route

    # -- trunk case (own short-lived trunk fixture) --
    TRUNK_CALLERID="${FIXTURE_MARKER}-trunk"
    TRUNK_BODY="$(mktemp)"
    TRUNK_CODE="$(curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o "$TRUNK_BODY" -w '%{http_code}' \
        --data-urlencode "callerid=${TRUNK_CALLERID}" \
        --data-urlencode "technology=pjsip" \
        --data-urlencode "reverse_auth=" \
        --data-urlencode "host=203.0.113.20" \
        --data-urlencode "username=" --data-urlencode "secret=" \
        --data-urlencode "domain=" --data-urlencode "fromuser=" --data-urlencode "fromdomain=" \
        --data-urlencode "qualify=no" \
        --data-urlencode "transport_id=" \
        --data-urlencode "nat_no=1" --data-urlencode "dtmfmode=rfc2833" \
        --data-urlencode "codec=ulaw" --data-urlencode "codec1=alaw" --data-urlencode "codec2=gsm" \
        --data-urlencode "telco=" \
        --data-urlencode "peer_type=friend" --data-urlencode "insecure=" --data-urlencode "call-limit=1" --data-urlencode "dialmethod=normal" \
        --data-urlencode "snep_csrf_token=${ADMIN_CSRF}" \
        "${BASE_URL}/index.php/default/trunks/add")"
    rm -f "$TRUNK_BODY"
    if [ "$TRUNK_CODE" = "302" ]; then
        TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
        TRUNK_NAME="$(db_query "SELECT name FROM trunks WHERE callerid='${TRUNK_CALLERID}';")"
        harness_ok "trunk fixture created" "${TRUNK_CALLERID} (id=${TRUNK_ID})"

        fetch "${BASE_URL}/index.php/default/trunks" "$TRUNK_LIST" >/dev/null
        if grep -q 'data-runtime-status=' "$TRUNK_LIST"; then
            harness_ok "trunks list carries data-runtime-status" "shared badge attribute present on the fixture row"
        else
            harness_bad "trunks list carries data-runtime-status" "attribute missing -- shared badge helper not wired?"
        fi

        db_query "UPDATE regras_negocio SET destino='T:${TRUNK_ID}' WHERE id=${ROUTE_ID};" >&2
        TRUNK_BLOCK="$(mktemp)"; harness_register_best_effort_cleanup "trunk block page temp file" "rm -f '$TRUNK_BLOCK'"
        fetch "${BASE_URL}/index.php/default/trunks/remove/id/${TRUNK_ID}/name/${TRUNK_NAME}" "$TRUNK_BLOCK" >/dev/null
        if grep -qi "SQLSTATE\|PDOException\|Fatal error" "$TRUNK_BLOCK"; then
            harness_bad "trunk dependency-warning (route reference)" "raw SQL/exception text leaked into the dependency-blocked page"
        elif grep -qF "Cannot remove trunk '${TRUNK_CALLERID}'." "$TRUNK_BLOCK" && grep -qF "${ROUTE_ID} - ${ROUTE_DESC}" "$TRUNK_BLOCK"; then
            harness_ok "trunk dependency-warning (route reference)" "canonical 'Cannot remove trunk ...' wording, route ${ROUTE_ID} listed, no leak"
        else
            harness_bad "trunk dependency-warning (route reference)" "expected the canonical dependency-warning wording naming trunk ${TRUNK_CALLERID} and route ${ROUTE_ID} - ${ROUTE_DESC}"
        fi
        restore_route

        # -- delete success feedback (Phase 13) --
        TRUNK_CSRF="$(harness_csrf_token "$COOKIEJAR" "$BASE_URL")"
        curl -sS -c "$COOKIEJAR" -b "$COOKIEJAR" -o /dev/null \
            --data-urlencode "id=${TRUNK_ID}" --data-urlencode "name=${TRUNK_NAME}" --data-urlencode "snep_csrf_token=${TRUNK_CSRF}" \
            "${BASE_URL}/index.php/default/trunks/remove" >/dev/null
        TRUNK_LIST_AFTER="$(mktemp)"; harness_register_best_effort_cleanup "trunk list after delete" "rm -f '$TRUNK_LIST_AFTER'"
        fetch "${BASE_URL}/index.php/default/trunks" "$TRUNK_LIST_AFTER" >/dev/null
        if grep -qF "deleted successfully" "$TRUNK_LIST_AFTER"; then
            harness_ok "trunk delete shows a success flash" "Phase 13 -- previously a silent 302"
        else
            harness_bad "trunk delete shows a success flash" "no 'deleted successfully' flash found after a successful trunk delete"
        fi
    else
        harness_bad "trunk fixture created" "HTTP ${TRUNK_CODE} -- skipping trunk dependency-panel/delete-flash checks"
    fi
fi

# -- extension delete success feedback (Phase 13) --
delete_extension
EXT_LIST_AFTER="$(mktemp)"; harness_register_best_effort_cleanup "ext list after delete" "rm -f '$EXT_LIST_AFTER'"
fetch "${BASE_URL}/index.php/default/extensions" "$EXT_LIST_AFTER" >/dev/null
if grep -qF "deleted successfully" "$EXT_LIST_AFTER"; then
    harness_ok "extension delete shows a success flash" "Phase 13 -- previously a silent 302"
else
    harness_bad "extension delete shows a success flash" "no 'deleted successfully' flash found after a successful extension delete"
fi

# =============================================================================
# PART E -- runtime-query failure never crashes, never fabricates state
# =============================================================================

ensure_asterisk_started_and_healthy() {
    $COMPOSE start asterisk >/dev/null 2>&1
    local i h
    for i in $(seq 1 30); do
        h="$($COMPOSE ps asterisk --format '{{.Health}}' 2>/dev/null)"
        [ "$h" = "healthy" ] && return 0
        sleep 2
    done
    return 1
}

log "==> [E] stopping asterisk to prove the transport list degrades explicitly, never crashes, never fabricates state"
$COMPOSE stop asterisk >&2
harness_register_cleanup "asterisk container (restart after Part E)" "ensure_asterisk_started_and_healthy"

DOWN_TRANSPORT_LIST="$(mktemp)"; harness_register_best_effort_cleanup "down transport list temp file" "rm -f '$DOWN_TRANSPORT_LIST'"
DOWN_CODE="$(fetch "${BASE_URL}/index.php/default/pjsip-transports" "$DOWN_TRANSPORT_LIST")"
if [ "$DOWN_CODE" != "200" ]; then
    harness_bad "transport list survives an AMI outage" "expected HTTP 200 with a degraded banner, got HTTP ${DOWN_CODE}"
elif grep -qi "Fatal error\|Uncaught" "$DOWN_TRANSPORT_LIST"; then
    harness_bad "transport list survives an AMI outage" "page rendered a fatal error while Asterisk was stopped -- Phase 10's own regression target"
elif grep -q "could not be queried right now" "$DOWN_TRANSPORT_LIST" && grep -q 'data-runtime-status="UNKNOWN"' "$DOWN_TRANSPORT_LIST"; then
    harness_ok "transport list survives an AMI outage" "explicit runtime-unavailable banner + UNKNOWN badges, HTTP 200, no crash"
else
    harness_bad "transport list survives an AMI outage" "expected the runtime-unavailable banner and UNKNOWN badges; got neither"
fi

log "==> [E] restarting asterisk"
$COMPOSE start asterisk >&2
asterisk_healthy() { $COMPOSE ps asterisk --format '{{.Health}}' 2>/dev/null | grep -q '^healthy$'; }
if harness_retry 30 2 -- asterisk_healthy; then
    harness_ok "asterisk recovers after restart" "container healthy again"
else
    harness_bad "asterisk recovers after restart" "did not become healthy within 60s"
fi
pjsip_modules_running() {
    $COMPOSE exec -T asterisk asterisk -rx 'module show like res_pjsip.so' 2>&1 | grep -q "Running"
}
harness_retry 10 2 -- pjsip_modules_running

# --- post-restart ODBC/CDR recovery (TASK-0033E1) ----------------------------
#
# `$COMPOSE stop asterisk` + `$COMPOSE start asterisk` above never
# touches `db` -- live-confirmed (docs/tasks/
# 0033e1-asterisk-restart-harness-odbc-recovery.md) to self-heal
# reliably, since `start` honors the `asterisk -> db: condition:
# service_healthy` gate exactly like `up`. Verified explicitly anyway so
# this suite's own pass/fail contract does not silently depend on that
# self-healing behavior continuing to hold under a future change.
if harness_wait_asterisk_ready && harness_restore_asterisk_post_restart; then
    harness_ok "ODBC/CDR ready after restart" "active ODBC connection and cdr_adaptive_odbc.so Running confirmed"
else
    harness_bad "ODBC/CDR ready after restart" "Asterisk restarted successfully but ODBC/CDR runtime did not recover"
fi

RECOVERED_LIST="$(mktemp)"; harness_register_best_effort_cleanup "recovered transport list temp file" "rm -f '$RECOVERED_LIST'"
transport_recovered() {
    fetch "${BASE_URL}/index.php/default/pjsip-transports" "$RECOVERED_LIST" >/dev/null
    grep -q 'data-runtime-status="ACTIVE"' "$RECOVERED_LIST"
}
if harness_retry 10 2 -- transport_recovered; then
    harness_ok "transport status reporting resumes after Asterisk recovers" "ACTIVE badges return, no lingering UNKNOWN state"
else
    harness_bad "transport status reporting resumes after Asterisk recovers" "still no ACTIVE badge after recovery + retries"
fi

# =============================================================================
# PART F -- no secret/private-key leakage in the new/changed markup
# =============================================================================

log "==> [F] no private key content, no raw AMI payload, in any page this task changed"
LEAK_FOUND=0
for f in "$EXT_LIST" "$TRUNK_LIST" "$TRANSPORT_LIST" "$ADD_PAGE"; do
    if grep -qi "BEGIN PRIVATE KEY\|BEGIN RSA PRIVATE KEY" "$f" 2>/dev/null; then
        LEAK_FOUND=1
    fi
done
if [ "$WSS_ID" != "" ] && [ -f "${WSS_EDIT:-/nonexistent}" ] && grep -qi "BEGIN PRIVATE KEY\|BEGIN RSA PRIVATE KEY" "$WSS_EDIT" 2>/dev/null; then
    LEAK_FOUND=1
fi
if [ "$LEAK_FOUND" = "1" ]; then
    harness_bad "no private key content leaked" "found PEM private key material in rendered HTML"
else
    harness_ok "no private key content leaked" "certificate paths are shown; key/certificate byte content never is (TASK-0029A's own model, unchanged)"
fi

# =============================================================================
# Unauthenticated access renders no shared-primitive content
# =============================================================================

log "==> [G] unauthenticated request renders no status/dependency data"
NOAUTH_JAR="$(mktemp)"
harness_register_best_effort_cleanup "noauth cookie jar" "rm -f '$NOAUTH_JAR'"
NOAUTH_BODY="$(mktemp)"
harness_register_best_effort_cleanup "noauth body temp file" "rm -f '$NOAUTH_BODY'"
curl -sS -c "$NOAUTH_JAR" -b "$NOAUTH_JAR" -o "$NOAUTH_BODY" "${BASE_URL}/index.php/default/pjsip-transports"
if grep -q 'data-runtime-status=' "$NOAUTH_BODY"; then
    harness_bad "unauthenticated request renders no transport status data" "found data-runtime-status on an unauthenticated response"
else
    harness_ok "unauthenticated request renders no transport status data" "no status markup reached an unauthenticated session"
fi

harness_complete
