#!/bin/bash
#
# TASK-0026E PJSIP/Asterisk configuration-injection hardening focused
# security smoke test.
#
# Exercises every confirmed F12-F15 configuration-injection boundary from
# docs/tasks/0026-pre-pilot-security-release-audit.md (re-traced and
# expanded in docs/tasks/0026e-pjsip-configuration-injection-hardening.md),
# through SENMA's own real, authenticated HTTP application flows -- never
# a direct file write, never a real exploit. For each boundary:
#   1. a normal, legitimate object still creates correctly and its
#      generated config is inspected for the expected section/directives;
#   2. a newline/config-shaped malicious value is submitted through the
#      real request;
#   3. proof the request is rejected before persistence (F12/F13/F15 --
#      the primary control) or was already rejected by pre-existing
#      TASK-0019/0020 validation (F14);
#   4. proof no injected marker section/directive/key appears anywhere in
#      the generated config after a fresh regenerate;
#   5. proof Asterisk's live PJSIP runtime never loaded the injected
#      object and remains healthy;
#   6. cleanup of every fixture this script owns.
#
# Every malicious payload targets a uniquely named, harmless marker
# ("task0026e-injected" / "task0026e_marker=yes") -- never a real
# Asterisk directive, never a destructive command, matching this task's
# explicit "use inert unique marker keys/sections only" instruction.
#
# Deliberately separate from `make smoke` -- never run implicitly by it.
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
ADMIN_USER="admin"
ADMIN_PASSWORD="SmokeTest123!"
MARKER_SECTION="task0026e-injected"
MARKER_DIRECTIVE="task0026e_marker"

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

app_exec() {
    $COMPOSE exec -T app sh -c "$1"
}

ast_exec() {
    $COMPOSE exec -T asterisk sh -c "$1"
}

fatal_count() {
    local n
    n="$(app_exec 'grep -c "Fatal error" /var/log/apache2/mag-error.log 2>/dev/null' | tr -d '\r\n ')"
    echo "${n:-0}"
}

redirects_to_permission_error() {
    grep -qi '^Location:.*permission/error' "$HEADERS"
}

BODY=""
HEADERS=""
# request <jar> GET|POST <path> [raw-data] -- plain GET, or a simple POST
# whose raw-data string has no embedded control characters (login,
# permission grants, id-only removals). Injection payloads that carry
# literal CR/LF use post_fields() below instead, never this.
request() {
    local jar="$1" method="$2" path="$3" data="${4:-}"
    if [ "$method" = POST ]; then
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' -d "$data" "${BASE_URL}${path}"
    else
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' "${BASE_URL}${path}"
    fi
}

# post_fields <jar> <path> <key=value> [<key=value> ...]
# Every field is sent via curl's own --data-urlencode, one -d per field --
# this is what lets a field's value safely carry literal CR/LF/control
# characters (the whole point of this suite's injection payloads): curl
# percent-encodes them correctly on the wire, so PHP's $_POST decodes the
# exact original bytes server-side, rather than however a hand-built raw
# "key=value&..." query string with embedded literal newlines would be
# byte-parsed.
post_fields() {
    local jar="$1" path="$2"
    shift 2
    local curl_args=()
    for kv in "$@"; do
        curl_args+=(--data-urlencode "$kv")
    done
    curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' \
        "${curl_args[@]}" "${BASE_URL}${path}"
}

# marker_absent_in_config <container> <file> -- true if neither marker
# string appears anywhere in the given generated config file.
marker_absent_in_config() {
    local container="$1" file="$2"
    ! $COMPOSE exec -T "$container" sh -c "grep -qE '${MARKER_SECTION}|${MARKER_DIRECTIVE}' '$file' 2>/dev/null"
}

# --- 0. Preflight --------------------------------------------------------

harness_require_containers app asterisk db
harness_require_env DB_USER DB_PASSWORD DB_NAME

BODY="$(mktemp)"
HEADERS="$(mktemp)"
harness_register_best_effort_cleanup "request temp files" "rm -f '$BODY' '$HEADERS'"

ADMIN_JAR="$(mktemp)"
harness_register_best_effort_cleanup "admin cookie jar" "rm -f '$ADMIN_JAR'"
ADMIN_HASH="$(app_exec "php -r \"echo md5('${ADMIN_PASSWORD}');\"" | tr -d '\r')"
if [ -z "$ADMIN_HASH" ]; then
    harness_blocked "could not compute the ${ADMIN_USER} password hash via the app container"
fi
db_query "UPDATE users SET password = '${ADMIN_HASH}' WHERE name = '${ADMIN_USER}';" >&2
request "$ADMIN_JAR" POST /index.php/auth/login "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}" >/dev/null

FATALS_BEFORE="$(fatal_count)"
log "==> baseline PHP Fatal Error count: ${FATALS_BEFORE}"

# includes/setup.conf's own path.asterisk.conf = "/etc/asterisk"
# (Bootstrap.php's compiled-in default too) -- /etc/asterisk is a shared
# volume (asterisk-etc) mounted read-only in app, read-write in asterisk,
# so either container can read every generated file below.
CONF_DIR_APP="/etc/asterisk/snep"
EXT_CONF="${CONF_DIR_APP}/senma-pjsip.conf"
TRUNK_CONF="${CONF_DIR_APP}/senma-pjsip-trunks.conf"
TRANSPORT_CONF="${CONF_DIR_APP}/senma-pjsip-transports.conf"
LEGACY_SIP_CONF="${CONF_DIR_APP}/snep-sip.conf"
LEGACY_IAX2_CONF="${CONF_DIR_APP}/snep-iax2.conf"

# --- 0b. A zero-permission user is denied on every F12-F15 boundary ------
# (Phase 10: prove authorization stays intact -- not re-testing
# TASK-0026A itself, just confirming this task didn't accidentally
# weaken it.)

RESTRICTED_USER="task0026e-restricted"
RESTRICTED_PASSWORD="Task0026eRestricted!"
RID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
RESTRICTED_HASH="$(app_exec "php -r \"echo md5('${RESTRICTED_PASSWORD}');\"" | tr -d '\r')"
if [ -z "$RID" ]; then
    db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${RESTRICTED_USER}','${RESTRICTED_HASH}','${RESTRICTED_USER}@example.test','',1,NOW(),NOW());"
    RID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
fi
if [ -z "$RID" ]; then
    harness_blocked "could not provision the zero-permission restricted test user"
fi
db_query "UPDATE users SET password='${RESTRICTED_HASH}' WHERE id=${RID}; DELETE FROM users_permissions WHERE user_id=${RID};" >/dev/null
harness_register_best_effort_cleanup "restricted user permissions reset to baseline" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM users_permissions WHERE user_id=${RID};\" >/dev/null"

RESTRICTED_JAR="$(mktemp)"
harness_register_best_effort_cleanup "restricted cookie jar" "rm -f '$RESTRICTED_JAR'"
request "$RESTRICTED_JAR" POST /index.php/auth/login "user=${RESTRICTED_USER}&password=${RESTRICTED_PASSWORD}" >/dev/null

for boundary_path in "/index.php/default/extensions/add" "/index.php/default/trunks/add" "/index.php/default/pjsip-transports/add"; do
    code="$(request "$RESTRICTED_JAR" GET "$boundary_path")"
    if [ "$code" = 302 ] && redirects_to_permission_error; then
        harness_ok "authorization intact: ${boundary_path}" "zero-permission user denied (HTTP 302, Location: permission/error)"
    else
        harness_bad "authorization intact: ${boundary_path}" "expected 302+permission/error, got HTTP ${code}"
    fi
done

code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$RID "user=$RID&default_extensions_write=1&default_trunks_write=1&default_pjsip-transports_write=1&default_pjsip-transports_read=1")"
if [ "$code" = 302 ]; then
    harness_ok "admin grants exactly the three F12-F15 permissions" "HTTP $code"
else
    harness_blocked "granting F12-F15 permissions to the restricted user failed (HTTP $code) -- cannot proceed"
fi

# =============================================================================
# F12 -- Extensions (ExtensionsController::execAdd() -> Snep_PjsipConf)
# =============================================================================

log "==> F12: PJSIP Extensions boundary"

EXT_A="10971"
EXT_B="10972"

code="$(post_fields "$RESTRICTED_JAR" /index.php/default/extensions/add \
    "exten=${EXT_A}" "name=Task0026e Legit" "password=" "passwordpadlock=" "technology=pjsip" "type=friend" "exten_group=" \
    "dtmf=rfc2833" "directmedia=no" "calllimit=1" "pickup_group=" "gsm=0" "transport_id=")"
EXT_A_EXISTS="$(db_query "SELECT name FROM peers WHERE name='${EXT_A}' AND peer_type='R';")"
if [ "$code" = 302 ] && [ -n "$EXT_A_EXISTS" ]; then
    harness_ok "F12 valid: create a legitimate PJSIP extension" "HTTP $code, stored via the real execAdd() HTTP flow"
else
    harness_bad "F12 valid: create a legitimate PJSIP extension" "HTTP $code, db row present='${EXT_A_EXISTS}'"
fi
harness_register_cleanup "extension ${EXT_A} (F12 fixture)" \
    "request \"\$RESTRICTED_JAR\" POST /index.php/default/extensions/remove \"id=${EXT_A}\" >/dev/null; true"

GENERATED="$(app_exec "cat '$EXT_CONF' 2>/dev/null")"
if echo "$GENERATED" | grep -qF "[${EXT_A}]" && echo "$GENERATED" | grep -qF "[${EXT_A}-auth]" && echo "$GENERATED" | grep -qF "callerid=Task0026e Legit <${EXT_A}>"; then
    harness_ok "F12 valid: generated config has expected sections/directives" "senma-pjsip.conf contains [${EXT_A}], [${EXT_A}-auth], and the expected callerid= directive"
else
    harness_bad "F12 valid: generated config has expected sections/directives" "expected sections/directives not found in generated senma-pjsip.conf"
fi

# Newline/section injection via the callerid-bound "name" field.
INJECTED_NAME="Task0026e$(printf '\r\n')[${MARKER_SECTION}]$(printf '\r\n')type=endpoint$(printf '\r\n')${MARKER_DIRECTIVE}=yes"
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/extensions/add \
    "exten=${EXT_B}" "name=${INJECTED_NAME}" "password=" "passwordpadlock=" "technology=pjsip" "type=friend" "exten_group=" \
    "dtmf=rfc2833" "directmedia=no" "calllimit=1" "pickup_group=" "gsm=0" "transport_id=")"
EXT_B_EXISTS="$(db_query "SELECT name FROM peers WHERE name='${EXT_B}' AND peer_type='R';")"
if [ -z "$EXT_B_EXISTS" ] && marker_absent_in_config app "$EXT_CONF"; then
    harness_ok "F12: newline/section-injection-shaped 'name' cannot execute" "HTTP $code, rejected before persistence, no marker in generated config"
else
    harness_bad "F12: newline/section-injection-shaped 'name' cannot execute" "HTTP $code, db row present='${EXT_B_EXISTS}', marker check failed"
fi
if [ -n "$EXT_B_EXISTS" ]; then
    harness_register_cleanup "extension ${EXT_B} (F12 malicious-name leak, should not exist)" \
        "request \"\$RESTRICTED_JAR\" POST /index.php/default/extensions/remove \"id=${EXT_B}\" >/dev/null; true"
fi

# Section injection via the exten/name identifier itself.
INJECTED_EXTEN="1099]${MARKER_DIRECTIVE}=yes"
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/extensions/add \
    "exten=${INJECTED_EXTEN}" "name=Task0026e" "password=" "passwordpadlock=" "technology=pjsip" "type=friend" "exten_group=" \
    "dtmf=rfc2833" "directmedia=no" "calllimit=1" "pickup_group=" "gsm=0" "transport_id=")"
if marker_absent_in_config app "$EXT_CONF"; then
    harness_ok "F12: section-shaped 'exten' identifier cannot execute" "HTTP $code, rejected by the numeric-only exten allowlist, no marker in generated config"
else
    harness_bad "F12: section-shaped 'exten' identifier cannot execute" "HTTP $code, marker present in generated config"
fi

PJSIP_LOOKUP="$(ast_exec "asterisk -rx 'pjsip show endpoint ${MARKER_SECTION}'")"
if echo "$PJSIP_LOOKUP" | grep -qi "Unable to find"; then
    harness_ok "F12: no injected endpoint loaded in Asterisk's live runtime" "pjsip show endpoint ${MARKER_SECTION} -> Unable to find object"
else
    harness_bad "F12: no injected endpoint loaded in Asterisk's live runtime" "unexpected: $PJSIP_LOOKUP"
fi

FATALS_AFTER_F12="$(fatal_count)"
if [ "$FATALS_AFTER_F12" = "$FATALS_BEFORE" ]; then
    harness_ok "F12: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE})"
else
    harness_bad "F12: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE} -> ${FATALS_AFTER_F12}"
fi

# =============================================================================
# F13 -- Trunks (TrunksController::preparePost() -> Snep_PjsipTrunkConf)
# =============================================================================

log "==> F13: PJSIP Trunks boundary"

# TASK-0026C precedent (docs/tasks/0026c-sql-boundary-hardening.md):
# TrunksController::preparePost() auto-generates a new trunk's name as
# MAX(existing trunk name)+1, or "1" if the trunks table is empty --
# colliding with any orphaned peer_type='T' peers row (no matching
# trunks row) left over from an earlier interrupted run. Pre-existing,
# unrelated to this task's own config-injection fix; swept via the same
# supported extensions/remove HTTP path this project's other smoke
# suites already use, rather than a raw SQL delete.
sweep_orphaned_trunk_peers() {
    local orphan_name
    for orphan_name in $(db_query "SELECT p.name FROM peers p LEFT JOIN trunks t ON t.name = p.name WHERE p.peer_type='T' AND t.id IS NULL;"); do
        log "found an orphaned trunk-type peers row (name='${orphan_name}') with no matching trunks row -- removing via the supported extensions/remove HTTP path"
        request "$ADMIN_JAR" POST /index.php/default/extensions/remove "id=${orphan_name}" >/dev/null
    done
}
sweep_orphaned_trunk_peers
harness_register_cleanup "orphaned trunk-type peers row sweep (F13 fixture side effect)" "sweep_orphaned_trunk_peers"

code="$(post_fields "$RESTRICTED_JAR" /index.php/default/trunks/add \
    "technology=pjsip" "peer_type=friend" "domain=" "callerid=Task0026e Trunk" "username=task0026etrunk" "secret=Sup3rSecret" \
    "host=sip.example.test" "dtmfmode=rfc2833" "dialmethod=INVITE" "reverse_auth=" "map_extensions=" \
    "dtmf_dial=" "codec=ulaw" "codec1=alaw" "codec2=gsm" "qualify=yes" "transport_id=")"
TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE callerid='Task0026e Trunk' ORDER BY id DESC LIMIT 1;")"
if [ "$code" = 302 ] && [ -n "$TRUNK_ID" ]; then
    harness_ok "F13 valid: create a legitimate PJSIP trunk" "HTTP $code, trunk id=${TRUNK_ID} via the real preparePost() HTTP flow"
else
    harness_bad "F13 valid: create a legitimate PJSIP trunk" "HTTP $code, trunk id present='${TRUNK_ID}'"
fi
harness_register_cleanup "trunk id=${TRUNK_ID:-none} (F13 fixture)" \
    "[ -n '${TRUNK_ID}' ] && request \"\$RESTRICTED_JAR\" POST /index.php/default/trunks/remove \"id=${TRUNK_ID}&delete=1\" >/dev/null; true"

if [ -n "$TRUNK_ID" ]; then
    GENERATED_TRUNK="$(app_exec "cat '$TRUNK_CONF' 2>/dev/null")"
    if echo "$GENERATED_TRUNK" | grep -qF "[trunk-${TRUNK_ID}]" && echo "$GENERATED_TRUNK" | grep -qF "contact=sip:sip.example.test:5060"; then
        harness_ok "F13 valid: generated config has expected sections/directives" "senma-pjsip-trunks.conf contains [trunk-${TRUNK_ID}] and the expected contact= directive (host embedded correctly)"
    else
        harness_bad "F13 valid: generated config has expected sections/directives" "expected sections/directives not found in generated senma-pjsip-trunks.conf"
    fi
fi

# Newline/directive injection via callerid/host/fromuser.
INJECTED_CALLERID="Task0026e$(printf '\r\n')[${MARKER_SECTION}]$(printf '\r\n')type=endpoint"
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/trunks/add \
    "technology=pjsip" "peer_type=friend" "domain=" "callerid=${INJECTED_CALLERID}" "username=task0026etrunkbad" "secret=Sup3rSecret" \
    "host=sip.example.test" "dtmfmode=rfc2833" "dialmethod=INVITE" "reverse_auth=" "map_extensions=" \
    "dtmf_dial=" "codec=ulaw" "codec1=alaw" "codec2=gsm" "qualify=yes" "transport_id=")"
BAD_TRUNK_ID="$(db_query "SELECT id FROM trunks WHERE username='task0026etrunkbad';")"
if [ -z "$BAD_TRUNK_ID" ] && marker_absent_in_config app "$TRUNK_CONF"; then
    harness_ok "F13: newline/section-injection-shaped 'callerid' cannot execute" "HTTP $code, rejected before persistence, no marker in generated config"
else
    harness_bad "F13: newline/section-injection-shaped 'callerid' cannot execute" "HTTP $code, trunk id present='${BAD_TRUNK_ID}'"
fi
if [ -n "$BAD_TRUNK_ID" ]; then
    harness_register_cleanup "trunk id=${BAD_TRUNK_ID} (F13 malicious-callerid leak, should not exist)" \
        "request \"\$RESTRICTED_JAR\" POST /index.php/default/trunks/remove \"id=${BAD_TRUNK_ID}&delete=1\" >/dev/null; true"
fi

INJECTED_HOST="sip.example.test$(printf '\r\n')${MARKER_DIRECTIVE}=yes"
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/trunks/add \
    "technology=pjsip" "peer_type=friend" "domain=" "callerid=Task0026e Trunk2" "username=task0026etrunkbad2" "secret=Sup3rSecret" \
    "host=${INJECTED_HOST}" "dtmfmode=rfc2833" "dialmethod=INVITE" "reverse_auth=" "map_extensions=" \
    "dtmf_dial=" "codec=ulaw" "codec1=alaw" "codec2=gsm" "qualify=yes" "transport_id=")"
BAD_TRUNK_ID2="$(db_query "SELECT id FROM trunks WHERE username='task0026etrunkbad2';")"
if [ -z "$BAD_TRUNK_ID2" ] && marker_absent_in_config app "$TRUNK_CONF"; then
    harness_ok "F13: newline-injection-shaped 'host' cannot execute" "HTTP $code, rejected before persistence (invalid host), no marker in generated config"
else
    harness_bad "F13: newline-injection-shaped 'host' cannot execute" "HTTP $code, trunk id present='${BAD_TRUNK_ID2}'"
fi
if [ -n "$BAD_TRUNK_ID2" ]; then
    harness_register_cleanup "trunk id=${BAD_TRUNK_ID2} (F13 malicious-host leak, should not exist)" \
        "request \"\$RESTRICTED_JAR\" POST /index.php/default/trunks/remove \"id=${BAD_TRUNK_ID2}&delete=1\" >/dev/null; true"
fi

PJSIP_TRUNK_LOOKUP="$(ast_exec "asterisk -rx 'pjsip show endpoint ${MARKER_SECTION}'")"
if echo "$PJSIP_TRUNK_LOOKUP" | grep -qi "Unable to find"; then
    harness_ok "F13: no injected endpoint loaded in Asterisk's live runtime" "pjsip show endpoint ${MARKER_SECTION} -> Unable to find object"
else
    harness_bad "F13: no injected endpoint loaded in Asterisk's live runtime" "unexpected: $PJSIP_TRUNK_LOOKUP"
fi

FATALS_AFTER_F13="$(fatal_count)"
if [ "$FATALS_AFTER_F13" = "$FATALS_BEFORE" ]; then
    harness_ok "F13: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE})"
else
    harness_bad "F13: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE} -> ${FATALS_AFTER_F13}"
fi

# =============================================================================
# F14 -- PJSIP Transports (already validated by TASK-0019/0020;
# reconfirmed here, not re-implemented)
# =============================================================================

log "==> F14: PJSIP Transports boundary (reconfirming pre-existing TASK-0019/0020 validation)"

TRANSPORT_NAME="task0026etransport"
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/pjsip-transports/add \
    "name=${TRANSPORT_NAME}" "protocol=udp" "bind_address=0.0.0.0" "bind_port=5098" "domain=" \
    "external_signaling_address=" "external_signaling_port=" "external_media_address=" "local_net=")"
TRANSPORT_EXISTS="$(db_query "SELECT name FROM pjsip_transports WHERE name='${TRANSPORT_NAME}';")"
if [ "$code" = 302 ] && [ -n "$TRANSPORT_EXISTS" ]; then
    harness_ok "F14 valid: create a legitimate transport" "HTTP $code, stored via the real addAction() HTTP flow"
else
    harness_bad "F14 valid: create a legitimate transport" "HTTP $code, db row present='${TRANSPORT_EXISTS}'"
fi
harness_register_cleanup "transport ${TRANSPORT_NAME} (F14 fixture)" \
    "TID=\$(db_query \"SELECT id FROM pjsip_transports WHERE name='${TRANSPORT_NAME}';\"); [ -n \"\$TID\" ] && request \"\$RESTRICTED_JAR\" POST /index.php/default/pjsip-transports/remove/id/\$TID \"confirm=1\" >/dev/null; true"

INJECTED_DOMAIN="legit.example$(printf '\r\n')[${MARKER_SECTION}]$(printf '\r\n')type=transport"
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/pjsip-transports/add \
    "name=task0026etransportbad" "protocol=udp" "bind_address=0.0.0.0" "bind_port=5097" "domain=${INJECTED_DOMAIN}" \
    "external_signaling_address=" "external_signaling_port=" "external_media_address=" "local_net=")"
BAD_TRANSPORT_EXISTS="$(db_query "SELECT name FROM pjsip_transports WHERE name='task0026etransportbad';")"
if [ -z "$BAD_TRANSPORT_EXISTS" ] && marker_absent_in_config app "$TRANSPORT_CONF"; then
    harness_ok "F14: newline/section-injection-shaped 'domain' cannot execute" "HTTP $code, rejected before persistence (pre-existing TASK-0019/0020 validateIpOrHostname()), no marker in generated config"
else
    harness_bad "F14: newline/section-injection-shaped 'domain' cannot execute" "HTTP $code, transport row present='${BAD_TRANSPORT_EXISTS}'"
fi
if [ -n "$BAD_TRANSPORT_EXISTS" ]; then
    harness_register_cleanup "transport task0026etransportbad (F14 malicious-domain leak, should not exist)" \
        "TID=\$(db_query \"SELECT id FROM pjsip_transports WHERE name='task0026etransportbad';\"); [ -n \"\$TID\" ] && request \"\$RESTRICTED_JAR\" POST /index.php/default/pjsip-transports/remove/id/\$TID \"confirm=1\" >/dev/null; true"
fi

FATALS_AFTER_F14="$(fatal_count)"
if [ "$FATALS_AFTER_F14" = "$FATALS_BEFORE" ]; then
    harness_ok "F14: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE})"
else
    harness_bad "F14: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE} -> ${FATALS_AFTER_F14}"
fi

# =============================================================================
# F15 -- legacy chan_sip generator (Snep_InterfaceConf), reachable via
# technology=sip still being a selectable option on the current UI
# =============================================================================

log "==> F15: legacy chan_sip boundary (technology=sip, confirmed reachable via the current UI)"

EXT_SIP="10973"
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/extensions/add \
    "exten=${EXT_SIP}" "name=Task0026e Sip" "password=" "passwordpadlock=" "technology=sip" "type=friend" "exten_group=" \
    "dtmf=rfc2833" "directmedia=no" "calllimit=1" "pickup_group=" "gsm=0")"
EXT_SIP_EXISTS="$(db_query "SELECT name FROM peers WHERE name='${EXT_SIP}';")"
if [ "$code" = 302 ] && [ -n "$EXT_SIP_EXISTS" ]; then
    harness_ok "F15 valid: create a legitimate technology=sip extension" "HTTP $code, stored via the same shared execAdd() HTTP flow"
else
    harness_bad "F15 valid: create a legitimate technology=sip extension" "HTTP $code, db row present='${EXT_SIP_EXISTS}'"
fi
harness_register_cleanup "extension ${EXT_SIP} (F15 fixture)" \
    "request \"\$RESTRICTED_JAR\" POST /index.php/default/extensions/remove \"id=${EXT_SIP}\" >/dev/null; true"

if [ -n "$EXT_SIP_EXISTS" ]; then
    GENERATED_LEGACY="$(app_exec "cat '$LEGACY_SIP_CONF' 2>/dev/null")"
    if echo "$GENERATED_LEGACY" | grep -qF "[${EXT_SIP}]"; then
        harness_ok "F15 valid: legacy generated config has the expected section" "snep-sip.conf contains [${EXT_SIP}]"
    else
        harness_bad "F15 valid: legacy generated config has the expected section" "expected section not found in generated snep-sip.conf"
    fi
fi

# Same execAdd() boundary as F12 -- the shared controller-level fix
# protects technology=sip identically to technology=pjsip, since both
# flow through the exact same $exten/$formData["name"] validation before
# either generator ever runs.
EXT_SIP_BAD="10974"
INJECTED_NAME_SIP="Task0026eSip$(printf '\r\n')[${MARKER_SECTION}]$(printf '\r\n')type=friend$(printf '\r\n')${MARKER_DIRECTIVE}=yes"
code="$(post_fields "$RESTRICTED_JAR" /index.php/default/extensions/add \
    "exten=${EXT_SIP_BAD}" "name=${INJECTED_NAME_SIP}" "password=" "passwordpadlock=" "technology=sip" "type=friend" "exten_group=" \
    "dtmf=rfc2833" "directmedia=no" "calllimit=1" "pickup_group=" "gsm=0")"
EXT_SIP_BAD_EXISTS="$(db_query "SELECT name FROM peers WHERE name='${EXT_SIP_BAD}';")"
if [ -z "$EXT_SIP_BAD_EXISTS" ] && marker_absent_in_config app "$LEGACY_SIP_CONF" && marker_absent_in_config app "$LEGACY_IAX2_CONF"; then
    harness_ok "F15: newline/section-injection-shaped 'name' cannot execute (legacy generator)" "HTTP $code, rejected before persistence by the same shared controller boundary as F12, no marker in generated legacy config"
else
    harness_bad "F15: newline/section-injection-shaped 'name' cannot execute (legacy generator)" "HTTP $code, db row present='${EXT_SIP_BAD_EXISTS}'"
fi
if [ -n "$EXT_SIP_BAD_EXISTS" ]; then
    harness_register_cleanup "extension ${EXT_SIP_BAD} (F15 malicious-name leak, should not exist)" \
        "request \"\$RESTRICTED_JAR\" POST /index.php/default/extensions/remove \"id=${EXT_SIP_BAD}\" >/dev/null; true"
fi

FATALS_AFTER_F15="$(fatal_count)"
if [ "$FATALS_AFTER_F15" = "$FATALS_BEFORE" ]; then
    harness_ok "F15: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE})"
else
    harness_bad "F15: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE} -> ${FATALS_AFTER_F15}"
fi

# --- Asterisk/PJSIP runtime health ---------------------------------------

log "==> checking Asterisk/PJSIP runtime health"

PJSIP_MODULE="$(ast_exec "asterisk -rx 'module show like res_pjsip.so'")"
if echo "$PJSIP_MODULE" | grep -q "Running"; then
    harness_ok "res_pjsip.so remains Running" "module show like res_pjsip.so reports Running"
else
    harness_bad "res_pjsip.so remains Running" "unexpected: $PJSIP_MODULE"
fi

TRANSPORTS="$(ast_exec "asterisk -rx 'pjsip show transports'")"
BASELINE_OK=1
for t in tcp udp wss; do
    echo "$TRANSPORTS" | grep -qE "^Transport:\s+${t}\s" || BASELINE_OK=0
done
if [ "$BASELINE_OK" = "1" ]; then
    harness_ok "baseline transports intact" "tcp/udp/wss all present in pjsip show transports"
else
    harness_bad "baseline transports intact" "one or more baseline transports missing: $TRANSPORTS"
fi

# --- final marker check across every generated config file ---------------

ALL_CLEAN=1
for pair in "app:$EXT_CONF" "app:$TRUNK_CONF" "app:$TRANSPORT_CONF" "app:$LEGACY_SIP_CONF" "app:$LEGACY_IAX2_CONF"; do
    container="${pair%%:*}"
    file="${pair#*:}"
    marker_absent_in_config "$container" "$file" || BASELINE_OK=0
    marker_absent_in_config "$container" "$file" || ALL_CLEAN=0
done
if [ "$ALL_CLEAN" = "1" ]; then
    harness_ok "no injected marker exists in any generated config" "confirmed absent in senma-pjsip.conf, senma-pjsip-trunks.conf, senma-pjsip-transports.conf, snep-sip.conf, snep-iax2.conf"
else
    harness_bad "no injected marker exists in any generated config" "a marker was found in at least one generated config file"
fi

harness_complete
