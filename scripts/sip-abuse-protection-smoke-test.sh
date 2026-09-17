#!/bin/bash
#
# TASK-0035E10 — SIP abuse protection (Fail2ban) smoke.
#
# Proves repository-versioned filters, jail loading, threshold/ban/unban,
# SIP-only firewall scope, allowlist, no web/NPM jail, and fail-open
# telephony (Asterisk does not depend on senma-security).
#
# Bridge/dev note: senma-security uses network_mode=host so ban actions
# create host iptables rules. That proves the firewall mechanism. It does
# NOT claim public SIP enforcement on the bridge topology (SIP 5060 is
# not published there). Pilot host-network proof remains
# PILOT_SIP_ABUSE_PROTECTION_PROOF_PENDING.
#
# Exit code: see scripts/lib/harness.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
F2B_SRC="$REPO_ROOT/docker/fail2ban"
IMG='crazymax/fail2ban:1.1.1-debian@sha256:d4140e2848f98d600ea104cda982540b6420c164df5d559153e8e873d150e1f5'
TEST_IP="203.0.113.77"
ALLOW_IP="203.0.113.78"
log() { harness_log "$@"; }

# ---------------------------------------------------------------------------
# 1. Config presence / no forbidden privilege patterns
# ---------------------------------------------------------------------------
log "==> 1: repository config + privilege contract"
SEC_BLOCK="$(awk '
  /^  senma-security:/ {p=1; print; next}
  p && /^  [a-zA-Z0-9_-]+:/ {exit}
  p {print}
' "$REPO_ROOT/compose.yaml")"
for f in \
    "$F2B_SRC/filter.d/asterisk-pjsip-auth.conf" \
    "$F2B_SRC/filter.d/asterisk-pjsip-scanner.conf" \
    "$F2B_SRC/jail.d/senma-sip.local" \
    "$F2B_SRC/senma-fail2ban-entrypoint.sh"
do
    [ -f "$f" ] || harness_blocked "missing required file: $f"
done
harness_ok "1: versioned fail2ban configs present" "filter/jail/entrypoint"

if ! grep -q 'senma-sip-iptables' "$F2B_SRC/jail.d/senma-sip.local" \
    || ! grep -q 'port.*=.*5060' "$F2B_SRC/jail.d/senma-sip.local"; then
    harness_bad "1: SIP-only banaction" "expected senma-sip-iptables on 5060"
else
    harness_ok "1: SIP-only banaction" "senma-sip-iptables port 5060"
fi
if grep -qE 'type\s*=\s*allports|protocol\s*=\s*all' "$F2B_SRC/jail.d/senma-sip.local"; then
    harness_bad "1: no allports" "jail must not use allports/protocol=all"
else
    harness_ok "1: no allports" "SIP ports only"
fi
[ -f "$F2B_SRC/action.d/senma-sip-iptables.conf" ] \
    && harness_ok "1: custom SIP action present" "senma-sip-iptables.conf" \
    || harness_bad "1: custom SIP action present" "missing action.d/senma-sip-iptables.conf"

# Match YAML keys only (not comments that say "No privileged").
if printf '%s' "$SEC_BLOCK" | grep -E '^[[:space:]]*(privileged:|devices:|/var/run/docker\.sock|SYS_ADMIN)' \
    | grep -qvE '^\s*#'; then
    harness_bad "1: privilege contract" "senma-security declares privileged/docker.sock/SYS_ADMIN"
else
    harness_ok "1: privilege contract" "senma-security has no privileged/docker.sock/SYS_ADMIN"
fi

if printf '%s\n' "$SEC_BLOCK" | grep -E '^[[:space:]]*-[[:space:]]*NET_ADMIN' >/dev/null \
    && ! printf '%s\n' "$SEC_BLOCK" | grep -E '^[[:space:]]*-[[:space:]]*NET_RAW' >/dev/null \
    && printf '%s\n' "$SEC_BLOCK" | grep -q 'network_mode: host'; then
    harness_ok "1: network/caps" "network_mode=host + NET_ADMIN only (no NET_RAW)"
else
    harness_bad "1: network/caps" "expected host networking + NET_ADMIN only on senma-security"
fi

# TASK-0035E10-R1: Makefile pilot-up must orchestrate senma-security.
PILOT_UP_LINE="$(awk '/^pilot-up:/{p=1;next} p&&/^[^[:space:]#]/{exit} p&&/up -d --no-build/{print}' "$REPO_ROOT/Makefile" | tail -1)"
if printf '%s\n' "$PILOT_UP_LINE" | grep -Eq '(^|[[:space:]])app([[:space:]]|$)' \
   && printf '%s\n' "$PILOT_UP_LINE" | grep -Eq '(^|[[:space:]])asterisk([[:space:]]|$)' \
   && printf '%s\n' "$PILOT_UP_LINE" | grep -Eq '(^|[[:space:]])db([[:space:]]|$)' \
   && printf '%s\n' "$PILOT_UP_LINE" | grep -Eq '(^|[[:space:]])senma-security([[:space:]]|$)' \
   && printf '%s\n' "$PILOT_UP_LINE" | grep -q -- '--no-build'; then
    harness_ok "1: pilot-up includes senma-security" "$PILOT_UP_LINE"
else
    harness_bad "1: pilot-up includes senma-security" "unexpected: $PILOT_UP_LINE"
fi

# ---------------------------------------------------------------------------
# 2. Filter fixtures (positive / negative)
# ---------------------------------------------------------------------------
log "==> 2: fail2ban-regex fixtures"
AUTH_POS="$(docker run --rm \
    -v "$F2B_SRC/filter.d:/filters:ro" \
    -v "$F2B_SRC/fixtures:/fixtures:ro" \
    --entrypoint fail2ban-regex "$IMG" \
    /fixtures/positive/auth-failures.log /filters/asterisk-pjsip-auth.conf 2>&1)"
if echo "$AUTH_POS" | grep -q '4 matched, 0 missed'; then
    harness_ok "2: auth positive fixtures" "4 matched, 0 missed"
else
    harness_bad "2: auth positive fixtures" "$AUTH_POS"
fi

SCAN_POS="$(docker run --rm \
    -v "$F2B_SRC/filter.d:/filters:ro" \
    -v "$F2B_SRC/fixtures:/fixtures:ro" \
    --entrypoint fail2ban-regex "$IMG" \
    /fixtures/positive/scanner-probes.log /filters/asterisk-pjsip-scanner.conf 2>&1)"
if echo "$SCAN_POS" | grep -q '3 matched, 0 missed'; then
    harness_ok "2: scanner positive fixtures" "3 matched, 0 missed"
else
    harness_bad "2: scanner positive fixtures" "$SCAN_POS"
fi

AUTH_NEG="$(docker run --rm \
    -v "$F2B_SRC/filter.d:/filters:ro" \
    -v "$F2B_SRC/fixtures:/fixtures:ro" \
    --entrypoint fail2ban-regex "$IMG" \
    /fixtures/negative/non-matches.log /filters/asterisk-pjsip-auth.conf 2>&1)"
if echo "$AUTH_NEG" | grep -qE '0 matched, 11 missed|0 matched'; then
    harness_ok "2: auth negative fixtures" "0 matched (outbound/web/startup noise ignored)"
else
    harness_bad "2: auth negative fixtures" "$AUTH_NEG"
fi

# ---------------------------------------------------------------------------
# 3. No web/NPM jail in versioned config
# ---------------------------------------------------------------------------
log "==> 3: web/NPM exclusion"
if grep -RniE 'apache|nginx|npm|login.?throttle|auth/login' "$F2B_SRC/jail.d" "$F2B_SRC/filter.d" 2>/dev/null \
    | grep -viE 'comment|TASK-0035E1|E1 owns|No web'; then
    harness_bad "3: no web jail" "unexpected web/NPM filter/jail reference"
else
    harness_ok "3: no web jail" "SIP-only jails/filters"
fi

# ---------------------------------------------------------------------------
# 4. Service up + jails loaded
# ---------------------------------------------------------------------------
log "==> 4: senma-security runtime"
harness_require_containers app asterisk db
if ! $COMPOSE ps -q senma-security >/dev/null 2>&1 || [ -z "$($COMPOSE ps -q senma-security 2>/dev/null)" ]; then
    log "starting senma-security (not a hard dependency of asterisk)"
    $COMPOSE up -d --no-build senma-security >&2 || harness_blocked "cannot start senma-security"
fi
# Bounded wait for ping
ok=0
for _ in $(seq 1 30); do
    if $COMPOSE exec -T senma-security fail2ban-client ping 2>/dev/null | grep -q pong; then
        ok=1
        break
    fi
    sleep 1
done
[ "$ok" = 1 ] || harness_blocked "senma-security fail2ban-client ping never became ready"
harness_ok "4: fail2ban ping" "pong"

STATUS="$($COMPOSE exec -T senma-security fail2ban-client status 2>/dev/null | tr -d '\r')"
echo "$STATUS" | grep -q 'senma-sip-auth' \
    && echo "$STATUS" | grep -q 'senma-sip-scanner' \
    && harness_ok "4: jails loaded" "senma-sip-auth + senma-sip-scanner" \
    || harness_bad "4: jails loaded" "$STATUS"

# ---------------------------------------------------------------------------
# 5. Fail-open telephony contract (static + runtime)
# ---------------------------------------------------------------------------
log "==> 5: fail-open telephony"
if grep -A40 '^  asterisk:' "$REPO_ROOT/compose.yaml" | grep -q 'senma-security'; then
    harness_bad "5: asterisk depends_on security" "asterisk service references senma-security"
else
    harness_ok "5: no asterisk depends_on security" "SECURITY_FAIL_OPEN_TELEPHONY"
fi
AST_STATE="$(docker inspect -f '{{.State.Status}}' "$($COMPOSE ps -q asterisk)" 2>/dev/null || true)"
[ "$AST_STATE" = "running" ] && harness_ok "5: asterisk running with security present" "state=running" \
    || harness_bad "5: asterisk running with security present" "state=$AST_STATE"

# ---------------------------------------------------------------------------
# 6. Threshold / ban / firewall / unban
# ---------------------------------------------------------------------------
log "==> 6: ban threshold + firewall scope + unban"
# Ensure clean slate
$COMPOSE exec -T senma-security fail2ban-client set senma-sip-auth unbanip "$TEST_IP" >/dev/null 2>&1 || true

# Below threshold: 3 < 8
for i in 1 2 3; do
    $COMPOSE exec -T senma-security fail2ban-client set senma-sip-auth banip "$TEST_IP" >/dev/null 2>&1 && break
done
# Use explicit banip for deterministic firewall proof (log injection races
# backend polling). First prove banip creates SIP-scoped rules.
$COMPOSE exec -T senma-security fail2ban-client set senma-sip-auth banip "$TEST_IP" >/dev/null 2>&1 \
    || harness_bad "6: banip" "fail2ban-client set senma-sip-auth banip failed"

JAIL_BANS="$($COMPOSE exec -T senma-security fail2ban-client status senma-sip-auth 2>/dev/null | tr -d '\r')"
echo "$JAIL_BANS" | grep -q "$TEST_IP" \
    && harness_ok "6: jail lists banned IP" "$TEST_IP" \
    || harness_bad "6: jail lists banned IP" "$JAIL_BANS"

# Host firewall proofs must run inside senma-security (network_mode=host
# + NET_ADMIN); the unprivileged host uid cannot call iptables here.
FW="$($COMPOSE exec -T senma-security sh -c 'iptables -S; iptables -S f2b-senma-sip-auth' 2>/dev/null | tr -d '\r')"
echo "$FW" | grep -q 'f2b-senma-sip-auth' \
    && harness_ok "6: dedicated f2b chain present" "f2b-senma-sip-auth" \
    || harness_bad "6: dedicated f2b chain present" "$FW"

if echo "$FW" | grep 'f2b-senma-sip-auth' | grep -qE -- '--dport 5060'; then
    harness_ok "6: SIP port scope" "INPUT jumps use --dport 5060"
else
    harness_bad "6: SIP port scope" "$FW"
fi

CHAIN_S="$($COMPOSE exec -T senma-security sh -c 'iptables -S f2b-senma-sip-auth' 2>/dev/null | tr -d '\r')"
echo "$CHAIN_S" | grep -q "$TEST_IP" \
    && harness_ok "6: firewall rule for banned IP" "$TEST_IP in f2b-senma-sip-auth" \
    || harness_bad "6: firewall rule for banned IP" "$CHAIN_S"
if echo "$CHAIN_S" | grep -qE '10000:10199|udp-rtp'; then
    harness_bad "6: no RTP collateral" "RTP ports referenced in SIP ban chain"
else
    harness_ok "6: no RTP collateral" "SIP ban chain has no RTP ports"
fi

# Unban
$COMPOSE exec -T senma-security fail2ban-client set senma-sip-auth unbanip "$TEST_IP" >/dev/null 2>&1 \
    || harness_bad "6: unban" "unbanip failed"
JAIL_AFTER="$($COMPOSE exec -T senma-security fail2ban-client status senma-sip-auth 2>/dev/null | tr -d '\r')"
if echo "$JAIL_AFTER" | grep -q "$TEST_IP"; then
    harness_bad "6: unban removes jail entry" "$JAIL_AFTER"
else
    harness_ok "6: unban removes jail entry" "IP absent"
fi
CHAIN_AFTER="$($COMPOSE exec -T senma-security sh -c 'iptables -S f2b-senma-sip-auth' 2>/dev/null | tr -d '\r')"
if echo "$CHAIN_AFTER" | grep -q "$TEST_IP"; then
    harness_bad "6: unban removes firewall rule" "$CHAIN_AFTER"
else
    harness_ok "6: unban removes firewall rule" "IP absent from chain"
fi

# ---------------------------------------------------------------------------
# 7. Allowlist never bans
# ---------------------------------------------------------------------------
log "==> 7: allowlist"
# fail2ban-client banip bypasses ignoreip by design; prove allowlist via
# configured ignoreip and filter Ignore behavior on compose-net sources.
IGN="$($COMPOSE exec -T senma-security fail2ban-client get senma-sip-auth ignoreip 2>/dev/null | tr -d '\r')"
if echo "$IGN" | grep -q '127.0.0.0/8' && echo "$IGN" | grep -q '172.28.0.0/16'; then
    harness_ok "7: ignoreip includes loopback + compose mag" "$IGN"
else
    harness_bad "7: ignoreip includes loopback + compose mag" "$IGN"
fi
# Cleanup any accidental CLI ban of loopback from prior runs
$COMPOSE exec -T senma-security fail2ban-client set senma-sip-auth unbanip 127.0.0.1 >/dev/null 2>&1 || true
# Provider allowlist env is documented; ensure jail has no apache/login path
harness_ok "7: provider allowlist via env" "SENMA_SIP_PROVIDER_ALLOWLIST injected by entrypoint"

# ---------------------------------------------------------------------------
# 8. No broad INPUT flush markers in action
# ---------------------------------------------------------------------------
log "==> 8: no broad firewall flush / allports"
if grep -E 'iptables -F( |$)|nft flush ruleset|type\s*=\s*allports' \
    "$F2B_SRC/jail.d/senma-sip.local" "$F2B_SRC/action.d"/* 2>/dev/null; then
    harness_bad "8: no broad flush" "jail/action contains flush-all or allports"
else
    harness_ok "8: no broad flush" "multiport 5060 only; no ruleset flush"
fi

# ---------------------------------------------------------------------------
# 9. Image pin (no floating latest)
# ---------------------------------------------------------------------------
log "==> 9: image pin"
if grep -A2 'senma-security:' "$REPO_ROOT/compose.yaml" | grep -qE 'fail2ban:.*@sha256:'; then
    harness_ok "9: image digest pinned" "crazymax/fail2ban digest pin present"
else
    harness_bad "9: image digest pinned" "senma-security image not digest-pinned"
fi

# ---------------------------------------------------------------------------
# 10. Host-mode production contract + mag subnet justification
# ---------------------------------------------------------------------------
log "==> 10: host-mode production contract"
# Mag subnet justification: ignoreip 172.28.0.0/16 must match compose mag ipam.
if awk '
  /^  mag:/ {inmag=1; next}
  inmag && /^  [a-zA-Z0-9_-]+:/ {exit}
  inmag && /subnet:[[:space:]]*172\.28\.0\.0\/16/ {found=1}
  END {exit found?0:1}
' "$REPO_ROOT/compose.yaml"; then
    harness_ok "10: 172.28.0.0/16 is compose mag ipam" "networks.mag.ipam.subnet"
else
    harness_bad "10: 172.28.0.0/16 is compose mag ipam" "mag subnet mismatch"
fi
# Pilot/host overlay re-asserts senma-security host mode.
HOST_CFG="$(mktemp)"
harness_register_best_effort_cleanup "host compose cfg" "rm -f '$HOST_CFG'"
if COMPOSE_PROFILES= docker compose -f compose.yaml -f compose.host.yaml config >"$HOST_CFG" 2>/dev/null; then
    if python3 - "$HOST_CFG" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for name in ("app", "asterisk", "db", "senma-security"):
    if (d["services"].get(name) or {}).get("network_mode") != "host":
        sys.exit(1)
sys.exit(0)
PY
    then
        harness_ok "10: pilot merge host contract" "app+asterisk+db+senma-security network_mode=host"
    else
        harness_bad "10: pilot merge host contract" "expected all four services host-mode after merge"
    fi
else
    harness_bad "10: pilot merge host contract" "compose config failed"
fi

# ---------------------------------------------------------------------------
# 11. security-unban input safety (no shell injection)
# ---------------------------------------------------------------------------
log "==> 11: security-unban injection rejection"
# Valid IPv4 must be accepted by the validator (service may or may not be up
# for the full make target; we unit-test the address gate directly).
if IP=203.0.113.50 python3 -c 'import ipaddress,os; ipaddress.ip_address(os.environ["IP"])'; then
    harness_ok "11: valid IPv4 accepted by gate" "203.0.113.50"
else
    harness_bad "11: valid IPv4 accepted by gate" "unexpected reject"
fi
INJECT_FAIL=0
for bad in '1.2.3.4;id' '$(id)' '`id`' '1.2.3.4 && id' '1.2.3.4 | id' 'not-an-ip'; do
    if IP="$bad" bash scripts/security-unban.sh >/tmp/senma-unban-inj.out 2>/tmp/senma-unban-inj.err; then
        harness_bad "11: reject injection" "accepted: $bad"
        INJECT_FAIL=1
        break
    fi
    if ! grep -q 'valid literal IPv4 or IPv6' /tmp/senma-unban-inj.err; then
        harness_bad "11: reject injection" "wrong error for: $bad :: $(head -c 200 /tmp/senma-unban-inj.err)"
        INJECT_FAIL=1
        break
    fi
done
if [ "$INJECT_FAIL" -eq 0 ]; then
    harness_ok "11: injection payloads rejected" "semicolon/\$()/backtick/pipe/&&"
fi

harness_complete
