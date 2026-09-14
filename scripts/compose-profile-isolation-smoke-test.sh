#!/bin/bash
#
# Focused, non-mutating regression coverage for TASK-0034C's Compose
# profile isolation (closing TASK-0034 Finding CH-3): the `provider`
# dev/test-only SIP-trunk-simulator fixture must never be reachable
# through the production/pilot Compose workflow by default, and must be
# reachable through exactly one explicit, documented opt-in that
# survives an operator's shell already carrying an unrelated inherited
# COMPOSE_PROFILES value.
#
# Included in `make regression` -- this is pure `docker compose ...
# config` static-merge inspection (plus one `make pilot-config` call,
# also non-mutating). It never starts, stops, or mutates any container,
# volume, or file, and therefore does not depend on `up` -- placed early
# in scripts/regression.sh, alongside lint/harness-lib-selftest, since it
# has no container-state dependency at all.
#
# Proves:
#   1. plain `docker compose config` (compose.yaml alone, no profile)
#      excludes `provider` -- the base/dev-onboarding default is
#      fixture-free (Phase 7).
#   2. the pilot overlay (`-f compose.yaml -f compose.pilot.yaml`), no
#      profile, also excludes `provider`, still excludes AMI (5038) and
#      the database (3306) from published ports, and still publishes
#      exactly TASK-0034B's RTP contract (10000-10199, not the
#      10000-20000 dev range -- Phase 34's over-publication guard).
#   3. `make pilot-config`'s own `COMPOSE_PROFILES=` override defeats a
#      shell that already exports COMPOSE_PROFILES=dev -- the real
#      Makefile recipe is exercised directly, not reimplemented here
#      (Phase 24 environment-contamination proof).
#   4. this repo's own opt-in variable, FIXTURE_PROFILE=dev and
#      FIXTURE_PROFILE=test (see Makefile's own header comment above the
#      `up` target), each explicitly include `provider` -- the
#      documented developer/regression opt-in actually works (Phase 15).
#
# Exit code: see scripts/lib/harness.sh (0=PASS 1=FAIL 2=BLOCKED 3=INCONCLUSIVE).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
log() { harness_log "$@"; }

if [ ! -f "$REPO_ROOT/.env" ]; then
    harness_blocked ".env missing -- run 'cp .env.example .env' first (docker compose config needs it for variable substitution)"
fi

cd "$REPO_ROOT" || harness_blocked "could not cd into repo root $REPO_ROOT"

# --- 1. default base config excludes provider --------------------------
log "==> 1: default compose.yaml (no profile) excludes provider"
SERVICES_DEFAULT="$(env -u COMPOSE_PROFILES $COMPOSE config --services 2>/dev/null)"
if [ -z "$SERVICES_DEFAULT" ]; then
    harness_blocked "docker compose config produced no output -- is Docker/Compose available and .env valid?"
fi
if printf '%s\n' "$SERVICES_DEFAULT" | grep -qx "provider"; then
    harness_bad "1: default excludes provider" "provider present with no profile activated: $(printf '%s' "$SERVICES_DEFAULT" | tr '\n' ' ')"
else
    harness_ok "1: default excludes provider" "services: $(printf '%s' "$SERVICES_DEFAULT" | tr '\n' ' ')"
fi

# --- 2. pilot overlay, no profile: excludes provider, AMI, DB; RTP intact
log "==> 2: pilot overlay (no profile) excludes provider/AMI/DB, RTP range unchanged"
PILOT_SERVICES="$(env -u COMPOSE_PROFILES $COMPOSE -f compose.yaml -f compose.pilot.yaml config --services 2>/dev/null)"
if printf '%s\n' "$PILOT_SERVICES" | grep -qx "provider"; then
    harness_bad "2: pilot excludes provider" "provider present in pilot config: $(printf '%s' "$PILOT_SERVICES" | tr '\n' ' ')"
else
    harness_ok "2: pilot excludes provider" "services: $(printf '%s' "$PILOT_SERVICES" | tr '\n' ' ')"
fi

PILOT_FULL="$(env -u COMPOSE_PROFILES $COMPOSE -f compose.yaml -f compose.pilot.yaml config 2>/dev/null)"
if printf '%s' "$PILOT_FULL" | grep -q '"5038' || printf '%s' "$PILOT_FULL" | grep -qE '5038:5038'; then
    harness_bad "2: AMI not published" "a 5038 port mapping appears in pilot config"
else
    harness_ok "2: AMI not published" "no 5038 port mapping found"
fi
if printf '%s' "$PILOT_FULL" | grep -qE '3306:3306'; then
    harness_bad "2: DB not published" "a 3306 port mapping appears in pilot config"
else
    harness_ok "2: DB not published" "no 3306 port mapping found"
fi
# TASK-0035E2: pilot overlay uses host networking — RTP is no longer a
# Docker port map. Accept either the historical publish window OR host
# mode with rtp.conf still declaring 10000-10199 (no 20000 widen).
if printf '%s' "$PILOT_FULL" | grep -q "20000"; then
    harness_bad "2: RTP range matches TASK-0034B/E2 contract" "found a reference to the old 10000-20000 dev range in published pilot config — Phase 34 over-publication regression"
elif printf '%s' "$PILOT_FULL" | grep -q "network_mode: host" \
    && grep -q 'rtpstart=10000' docker/asterisk-config/rtp.conf \
    && grep -q 'rtpend=10199' docker/asterisk-config/rtp.conf; then
    harness_ok "2: RTP range matches TASK-0034B/E2 contract" "host networking; rtp.conf 10000-10199; no Docker RTP publish; 20000 absent"
elif printf '%s' "$PILOT_FULL" | grep -q "10199"; then
    harness_ok "2: RTP range matches TASK-0034B/E2 contract" "10000-10199 present, 20000 absent"
else
    harness_bad "2: RTP range matches TASK-0034B/E2 contract" "expected host-network RTP contract or 10000-10199 publish map"
fi

# --- 3. make pilot-config resists a contaminated COMPOSE_PROFILES --------
log "==> 3: make pilot-config ignores an inherited COMPOSE_PROFILES=dev"
CONTAMINATED="$(COMPOSE_PROFILES=dev make -s pilot-config 2>/dev/null)"
if [ -z "$CONTAMINATED" ]; then
    harness_bad "3: pilot-config resists contamination" "'COMPOSE_PROFILES=dev make -s pilot-config' produced no output"
elif printf '%s' "$CONTAMINATED" | grep -qE '^  provider:'; then
    harness_bad "3: pilot-config resists contamination" "a provider: service block is present even with an inherited COMPOSE_PROFILES=dev"
else
    harness_ok "3: pilot-config resists contamination" "provider absent even with COMPOSE_PROFILES=dev inherited from the calling shell"
fi

# --- 4. explicit opt-in: FIXTURE_PROFILE=dev / =test include provider ----
log "==> 4: FIXTURE_PROFILE=dev/test explicitly include provider"
for prof in dev test; do
    SVCS="$(env -u COMPOSE_PROFILES COMPOSE_PROFILES="$prof" $COMPOSE config --services 2>/dev/null)"
    if printf '%s\n' "$SVCS" | grep -qx "provider"; then
        harness_ok "4: COMPOSE_PROFILES=$prof includes provider" "services: $(printf '%s' "$SVCS" | tr '\n' ' ')"
    else
        harness_bad "4: COMPOSE_PROFILES=$prof includes provider" "provider missing with COMPOSE_PROFILES=$prof: $(printf '%s' "$SVCS" | tr '\n' ' ')"
    fi
done

harness_complete
