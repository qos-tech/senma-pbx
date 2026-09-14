#!/bin/bash
#
# TASK-0035E1 — trusted reverse-proxy client IP + login-throttle attribution.
#
# Proves Snep_Security_ClientIp resolution (unit cases A–G) and that
# LoginThrottle buckets use the resolved client IP (multi-client /
# multi-username). Also proves AuthController wires the helper and that
# an untrusted direct client cannot spoof throttle identity over HTTP
# via X-Forwarded-For / X-Real-IP.
#
# Deliberately separate from `make smoke` -- never run implicitly by it.
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
BASE_URL="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

app_exec() {
    $COMPOSE exec -T app sh -c "$1"
}

harness_require_containers app db

BODY="$(mktemp)"
HEADERS="$(mktemp)"
JAR="$(mktemp)"
harness_register_best_effort_cleanup "client-ip body" "rm -f '$BODY'"
harness_register_best_effort_cleanup "client-ip headers" "rm -f '$HEADERS'"
harness_register_best_effort_cleanup "client-ip jar" "rm -f '$JAR'"

request() {
    local jar="$1" method="$2" path="$3" data="${4:-}"
    shift 4 || true
    local extra_headers=("$@")
    local curl_args=(-sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}')
    local h
    for h in "${extra_headers[@]}"; do
        curl_args+=(-H "$h")
    done
    if [ "$method" = POST ]; then
        curl "${curl_args[@]}" -d "$data" "${BASE_URL}${path}"
    else
        curl "${curl_args[@]}" "${BASE_URL}${path}"
    fi
}

# =============================================================================
# 1. Helper unit coverage (php -r, same pattern as session-csrf 10b)
# =============================================================================

log "==> Snep_Security_ClientIp unit matrix"

UNIT_JSON="$(app_exec "php -d display_errors=0 -d error_reporting=0 -r '
require \"/var/www/html/snep/lib/Snep/Security/ClientIp.php\";
\$out = array();

putenv(\"TRUSTED_PROXY_CIDRS\");
\$out[\"A\"] = Snep_Security_ClientIp::resolveFromServer(array(
    \"REMOTE_ADDR\" => \"203.0.113.10\",
));

putenv(\"TRUSTED_PROXY_CIDRS\");
\$out[\"B\"] = Snep_Security_ClientIp::resolveFromServer(array(
    \"REMOTE_ADDR\" => \"203.0.113.10\",
    \"HTTP_X_FORWARDED_FOR\" => \"1.2.3.4\",
    \"HTTP_X_REAL_IP\" => \"5.6.7.8\",
));

putenv(\"TRUSTED_PROXY_CIDRS=10.60.20.20/32\");
\$out[\"C\"] = Snep_Security_ClientIp::resolveFromServer(array(
    \"REMOTE_ADDR\" => \"10.60.20.20\",
    \"HTTP_X_FORWARDED_FOR\" => \"201.89.219.213\",
));

putenv(\"TRUSTED_PROXY_CIDRS=10.60.20.20/32\");
\$out[\"D\"] = Snep_Security_ClientIp::resolveFromServer(array(
    \"REMOTE_ADDR\" => \"10.60.20.20\",
    \"HTTP_X_REAL_IP\" => \"201.89.219.213\",
));

putenv(\"TRUSTED_PROXY_CIDRS=10.60.20.20/32\");
\$out[\"E\"] = Snep_Security_ClientIp::resolveFromServer(array(
    \"REMOTE_ADDR\" => \"10.60.20.20\",
    \"HTTP_X_FORWARDED_FOR\" => \"not-an-ip\",
));

putenv(\"TRUSTED_PROXY_CIDRS=10.60.20.0/24\");
\$out[\"F_in\"] = Snep_Security_ClientIp::resolveFromServer(array(
    \"REMOTE_ADDR\" => \"10.60.20.50\",
    \"HTTP_X_FORWARDED_FOR\" => \"198.51.100.7\",
));
\$out[\"F_out\"] = Snep_Security_ClientIp::resolveFromServer(array(
    \"REMOTE_ADDR\" => \"10.60.21.50\",
    \"HTTP_X_FORWARDED_FOR\" => \"198.51.100.7\",
));
\$out[\"F_exact\"] = Snep_Security_ClientIp::ipInCidr(\"10.60.20.20\", \"10.60.20.20/32\") ? \"yes\" : \"no\";

putenv(\"TRUSTED_PROXY_CIDRS=2001:db8::1/128\");
\$out[\"G\"] = Snep_Security_ClientIp::resolveFromServer(array(
    \"REMOTE_ADDR\" => \"2001:db8::1\",
    \"HTTP_X_FORWARDED_FOR\" => \"2001:db8:abcd::9\",
));

putenv(\"TRUSTED_PROXY_CIDRS=10.60.20.20/32\");
\$out[\"chain\"] = Snep_Security_ClientIp::resolveFromServer(array(
    \"REMOTE_ADDR\" => \"10.60.20.20\",
    \"HTTP_X_FORWARDED_FOR\" => \"203.0.113.50, 10.60.20.20\",
));

putenv(\"TRUSTED_PROXY_CIDRS=0.0.0.0/0\");
\$out[\"wild\"] = Snep_Security_ClientIp::resolveFromServer(array(
    \"REMOTE_ADDR\" => \"10.60.20.20\",
    \"HTTP_X_FORWARDED_FOR\" => \"1.2.3.4\",
));

putenv(\"TRUSTED_PROXY_CIDRS\");
echo json_encode(\$out);
' 2>/dev/null")"

expect_unit() {
    local key="$1" want="$2"
    if echo "$UNIT_JSON" | grep -q "\"${key}\":\"${want}\""; then
        harness_ok "unit ${key}" "=> ${want}"
    else
        harness_bad "unit ${key}" "expected ${want}; got ${UNIT_JSON}"
    fi
}

expect_unit A "203.0.113.10"
expect_unit B "203.0.113.10"
expect_unit C "201.89.219.213"
expect_unit D "201.89.219.213"
expect_unit E "10.60.20.20"
expect_unit F_in "198.51.100.7"
expect_unit F_out "10.60.21.50"
expect_unit F_exact "yes"
expect_unit G "2001:db8:abcd::9"
expect_unit chain "203.0.113.50"
expect_unit wild "10.60.20.20"

# =============================================================================
# 2. AuthController wiring (source contract)
# =============================================================================

log "==> AuthController wiring"

AUTH_SRC="$REPO_ROOT/snep/modules/default/controllers/AuthController.php"
if grep -q 'Snep_Security_ClientIp::resolveFromServer' "$AUTH_SRC" \
    && ! grep -q "REMOTE_ADDR.*?? 'unknown'" "$AUTH_SRC"; then
    harness_ok "AuthController uses ClientIp helper" "resolveFromServer(); no direct REMOTE_ADDR throttle binding"
else
    harness_bad "AuthController uses ClientIp helper" "missing ClientIp call or leftover REMOTE_ADDR binding"
fi

if ! grep -qE 'HTTP_X_FORWARDED_FOR|HTTP_X_REAL_IP|HTTP_FORWARDED' "$AUTH_SRC"; then
    harness_ok "AuthController has no blind proxy-header reads" "no direct XFF/X-Real-IP/Forwarded use"
else
    harness_bad "AuthController has no blind proxy-header reads" "unexpected header reads in AuthController"
fi

# =============================================================================
# 3. LoginThrottle multi-client attribution (resolved IPs)
# =============================================================================

log "==> LoginThrottle multi-client buckets via resolved client IPs"

db_query "DELETE FROM login_attempts WHERE username LIKE 'task0035e1-%' OR ip_address IN ('198.51.100.10','198.51.100.11','198.51.100.20');" >/dev/null
harness_register_cleanup "task0035e1 login_attempts rows" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER:-snep}' -p'${DB_PASSWORD:-change-me-for-local-development}' '${DB_NAME:-snep}' -N -e \"DELETE FROM login_attempts WHERE username LIKE 'task0035e1-%' OR ip_address IN ('198.51.100.10','198.51.100.11','198.51.100.20');\" >/dev/null"

THROTTLE_JSON="$(app_exec "php -d display_errors=0 -d error_reporting=0 -r '
set_include_path(\"/var/www/html/snep/lib\" . PATH_SEPARATOR . get_include_path());
require \"Zend/Loader/Autoloader.php\";
Zend_Loader_Autoloader::getInstance();
require \"/var/www/html/snep/lib/Snep/Security/ClientIp.php\";
require \"/var/www/html/snep/lib/Snep/Security/LoginThrottle.php\";

\$cfg = parse_ini_file(\"/var/www/html/snep/includes/setup.conf\", true);
\$db = Zend_Db::factory(\"Pdo_Mysql\", array(
    \"host\" => \$cfg[\"ambiente\"][\"db.host\"],
    \"username\" => \$cfg[\"ambiente\"][\"db.username\"],
    \"password\" => \$cfg[\"ambiente\"][\"db.password\"],
    \"dbname\" => \$cfg[\"ambiente\"][\"db.dbname\"],
));

putenv(\"TRUSTED_PROXY_CIDRS=10.60.20.20/32\");
\$ipA = Snep_Security_ClientIp::resolveFromServer(array(
    \"REMOTE_ADDR\" => \"10.60.20.20\",
    \"HTTP_X_FORWARDED_FOR\" => \"198.51.100.10\",
));
\$ipB = Snep_Security_ClientIp::resolveFromServer(array(
    \"REMOTE_ADDR\" => \"10.60.20.20\",
    \"HTTP_X_FORWARDED_FOR\" => \"198.51.100.11\",
));

for (\$i = 0; \$i < 5; \$i++) {
    Snep_Security_LoginThrottle::recordFailure(\$db, \"task0035e1-user-a\", \$ipA);
}
\$out = array(
    \"ipA\" => \$ipA,
    \"ipB\" => \$ipB,
    \"A_throttled\" => Snep_Security_LoginThrottle::isThrottled(\$db, \"task0035e1-user-a\", \$ipA) ? \"yes\" : \"no\",
    \"B_same_user\" => Snep_Security_LoginThrottle::isThrottled(\$db, \"task0035e1-user-a\", \$ipB) ? \"yes\" : \"no\",
    \"B_other_user\" => Snep_Security_LoginThrottle::isThrottled(\$db, \"task0035e1-user-b\", \$ipB) ? \"yes\" : \"no\",
);

for (\$i = 0; \$i < 20; \$i++) {
    Snep_Security_LoginThrottle::recordFailure(\$db, \"task0035e1-u\" . (\$i % 3), \"198.51.100.20\");
}
\$out[\"ip_cap\"] = Snep_Security_LoginThrottle::isThrottled(\$db, \"task0035e1-fresh\", \"198.51.100.20\") ? \"yes\" : \"no\";

Snep_Security_LoginThrottle::clearAccount(\$db, \"task0035e1-user-a\", \$ipA);
\$out[\"cleared\"] = Snep_Security_LoginThrottle::isThrottled(\$db, \"task0035e1-user-a\", \$ipA) ? \"yes\" : \"no\";

echo json_encode(\$out);
' 2>/dev/null")"

if echo "$THROTTLE_JSON" | grep -q '"ipA":"198.51.100.10"' \
    && echo "$THROTTLE_JSON" | grep -q '"ipB":"198.51.100.11"' \
    && echo "$THROTTLE_JSON" | grep -q '"A_throttled":"yes"' \
    && echo "$THROTTLE_JSON" | grep -q '"B_same_user":"no"' \
    && echo "$THROTTLE_JSON" | grep -q '"B_other_user":"no"' \
    && echo "$THROTTLE_JSON" | grep -q '"ip_cap":"yes"' \
    && echo "$THROTTLE_JSON" | grep -q '"cleared":"no"'; then
    harness_ok "multi-client throttle buckets stay separate; IP cap + clearAccount preserved" "$THROTTLE_JSON"
else
    harness_bad "multi-client throttle buckets stay separate; IP cap + clearAccount preserved" "$THROTTLE_JSON"
fi

# =============================================================================
# 4. HTTP spoof: direct client cannot choose throttle identity
# =============================================================================

log "==> HTTP spoof protection (TRUSTED_PROXY_CIDRS empty / default)"

SPOOF_USER="task0035e1-spoof"
db_query "DELETE FROM login_attempts WHERE username='${SPOOF_USER}';" >/dev/null

code="$(request "$JAR" POST /index.php/auth/login \
    "user=${SPOOF_USER}&password=wrong-spoof" \
    "X-Forwarded-For: 1.2.3.4" \
    "X-Real-IP: 5.6.7.8" \
    "Forwarded: for=9.9.9.9")"
RECORDED_IP="$(db_query "SELECT ip_address FROM login_attempts WHERE username='${SPOOF_USER}' ORDER BY id DESC LIMIT 1;" | tr -d '\r')"

if [ "$code" = "200" ] \
    && [ -n "$RECORDED_IP" ] \
    && [ "$RECORDED_IP" != "1.2.3.4" ] \
    && [ "$RECORDED_IP" != "5.6.7.8" ] \
    && [ "$RECORDED_IP" != "9.9.9.9" ]; then
    harness_ok "HTTP spoof headers ignored when proxy untrusted" "login_attempts.ip_address=${RECORDED_IP} (not attacker headers), HTTP ${code}"
else
    harness_bad "HTTP spoof headers ignored when proxy untrusted" "HTTP ${code}, recorded='${RECORDED_IP}'"
fi

db_query "DELETE FROM login_attempts WHERE username='${SPOOF_USER}';" >/dev/null

harness_complete
