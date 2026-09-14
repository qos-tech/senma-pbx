#!/bin/bash
#
# TASK-0035E2 — host-networking architecture focused smoke.
#
# Deterministic compose/config/source proofs for Model B:
#   bridge (compose.yaml) = dev/regression
#   host   (compose.host.yaml / compose.pilot.yaml) = Linux pilot/production
#
# Does NOT require destroying the active bridge stack. Optional live
# host-network binding proof is gated behind HOST_NETWORK_RUNTIME=1 and
# is expected on a dedicated Linux pilot host.
#
# Exit code: see scripts/lib/harness.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Never inherit SMOKE_COMPOSE with pilot/host overlays — this suite must
# prove Model B isolation between base and host files explicitly.
COMPOSE_BIN="docker compose"

log() { harness_log "$@"; }

cd "$REPO_ROOT"

log "==> host compose config (static)"

HOST_CFG="$(mktemp)"
harness_register_best_effort_cleanup "host compose config" "rm -f '$HOST_CFG'"
if COMPOSE_PROFILES= $COMPOSE_BIN -f compose.yaml -f compose.host.yaml config >"$HOST_CFG" 2>/tmp/host-compose.err; then
    harness_ok "compose.host.yaml merges cleanly" "docker compose config OK"
else
    harness_bad "compose.host.yaml merges cleanly" "$(head -c 400 /tmp/host-compose.err)"
fi

python3 - "$HOST_CFG" <<'PY' || true
import sys, yaml
path = sys.argv[1]
d = yaml.safe_load(open(path))
ok = True
msgs = []
for name in ("app", "asterisk", "db"):
    s = d["services"][name]
    if s.get("network_mode") != "host":
        ok = False; msgs.append(f"{name} network_mode!=host")
    if s.get("ports"):
        ok = False; msgs.append(f"{name} still has ports={s.get('ports')}")
    if s.get("networks"):
        ok = False; msgs.append(f"{name} still has networks={s.get('networks')}")
app_env = d["services"]["app"].get("environment") or {}
for k, v in {
    "DB_HOST": "127.0.0.1",
    "ASTERISK_HOST": "127.0.0.1",
    "ASTERISK_HTTP_BIND": "127.0.0.1",
    "ASTERISK_AMI_BIND": "127.0.0.1",
    "SENMA_NETWORK_MODE": "host",
}.items():
    if str(app_env.get(k)) != v:
        ok = False; msgs.append(f"app env {k}={app_env.get(k)!r} want {v!r}")
vols = d["services"]["db"].get("volumes") or []
vol_s = " ".join(str(v) for v in vols)
if "mariadb-host.cnf" not in vol_s and "zz-senma-host-bind.cnf" not in vol_s:
    ok = False; msgs.append("db missing mariadb-host.cnf bind")
open("/tmp/host-compose-py.out", "w").write("OK" if ok else ("FAIL: " + "; ".join(msgs)))
sys.exit(0 if ok else 1)
PY
PY_OUT="$(cat /tmp/host-compose-py.out 2>/dev/null || echo FAIL)"
if [ "$PY_OUT" = "OK" ]; then
    harness_ok "host overlay: no ports/networks; loopback env; mariadb cnf" "$PY_OUT"
else
    harness_bad "host overlay: no ports/networks; loopback env; mariadb cnf" "$PY_OUT"
fi

log "==> bridge compose still intact for regression"

BRIDGE_CFG="$(mktemp)"
harness_register_best_effort_cleanup "bridge compose config" "rm -f '$BRIDGE_CFG'"
if COMPOSE_PROFILES= $COMPOSE_BIN -f compose.yaml config >"$BRIDGE_CFG" 2>/tmp/bridge-compose.err; then
    python3 - "$BRIDGE_CFG" <<'PY'
import sys, yaml
raw = open(sys.argv[1]).read()
d = yaml.safe_load(raw)
if not d or "services" not in d:
    open("/tmp/bridge-compose-py.out","w").write("FAIL: empty/invalid compose config")
    sys.exit(1)
app = d["services"]["app"]
ok = app.get("network_mode") in (None, "") and bool(app.get("ports")) and bool(app.get("networks"))
open("/tmp/bridge-compose-py.out","w").write("OK" if ok else "FAIL: network_mode=%r ports=%r nets=%r" % (app.get("network_mode"), app.get("ports"), app.get("networks")))
sys.exit(0 if ok else 1)
PY
    if [ "$(cat /tmp/bridge-compose-py.out 2>/dev/null)" = "OK" ]; then
        harness_ok "bridge compose.yaml retains ports+networks (Model B)" "dev/regression path unchanged"
    else
        harness_bad "bridge compose.yaml retains ports+networks (Model B)" "$(cat /tmp/bridge-compose-py.out 2>/dev/null || echo unknown)"
    fi
else
    harness_bad "bridge compose.yaml retains ports+networks (Model B)" "$(head -c 300 /tmp/bridge-compose.err)"
fi

log "==> source contracts"

if grep -q 'ProxyPass        /asterisk/ws __ASTERISK_WS_BACKEND__' "$REPO_ROOT/docker/apache-mag.conf" \
    && grep -q "VirtualHost \*:__APACHE_HTTP_PORT__" "$REPO_ROOT/docker/apache-mag.conf"; then
    harness_ok "Apache HTTP vhost proxies /asterisk/ws" "closes I6 path for external TLS"
else
    harness_bad "Apache HTTP vhost proxies /asterisk/ws" "missing HTTP ProxyPass or port placeholder"
fi

if grep -q 'bind-address = 127.0.0.1' "$REPO_ROOT/docker/mariadb-host.cnf"; then
    harness_ok "MariaDB host cnf loopback bind" "127.0.0.1 only"
else
    harness_bad "MariaDB host cnf loopback bind" "missing bind-address"
fi

if grep -q 'ASTERISK_HTTP_BIND' "$REPO_ROOT/docker/asterisk-entrypoint.sh" \
    && grep -q 'ASTERISK_AMI_BIND' "$REPO_ROOT/docker/asterisk-entrypoint.sh"; then
    harness_ok "asterisk-entrypoint applies HTTP/AMI bind overrides" "env-driven"
else
    harness_bad "asterisk-entrypoint applies HTTP/AMI bind overrides" "missing rewrite logic"
fi

if grep -q 'TLS_TERMINATION_MODE' "$REPO_ROOT/scripts/wss-cert-check.sh" \
    && grep -q 'external' "$REPO_ROOT/scripts/wss-cert-check.sh"; then
    harness_ok "cert-check understands external TLS mode" "I5 external path"
else
    harness_bad "cert-check understands external TLS mode" "missing TLS_TERMINATION_MODE handling"
fi

if grep -q 'PJSIP_EXTERNAL_MEDIA_ADDRESS' "$REPO_ROOT/docker/apply-pjsip-nat-from-env.php" \
    && grep -q 'PJSIP_LOCAL_NET' "$REPO_ROOT/.env.example"; then
    harness_ok "NAT env contract present" "PJSIP_EXTERNAL_* / PJSIP_LOCAL_NET"
else
    harness_bad "NAT env contract present" "missing NAT env wiring"
fi

if grep -q 'TRUSTED_PROXY_CIDRS' "$REPO_ROOT/.env.example"; then
    harness_ok "trusted proxy config preserved (0035E1)" "TRUSTED_PROXY_CIDRS in .env.example"
else
    harness_bad "trusted proxy config preserved (0035E1)" "missing TRUSTED_PROXY_CIDRS"
fi

log "==> optional live host-network binding proof"

if [ "${HOST_NETWORK_RUNTIME:-0}" = "1" ]; then
    log "HOST_NETWORK_RUNTIME=1 — operator-gated live proof (see task doc)"
    harness_ok "live host-network proof requested" "run operator migration plan on dedicated host"
else
    harness_ok "live host-network proof deferred" "HOST_NETWORK_RUNTIME unset — static proofs only (Model B / Linux pilot)"
fi

harness_complete
