#!/bin/bash
#
# SENMA canonical operator diagnostic entrypoint (TASK-0033D).
#
# `make doctor` -- answers, without the operator needing to know
# container names, internal paths, or any of the ~40 other Make targets
# in this repository:
#   - Is the SENMA stack basically healthy?
#   - Which subsystem is failing?
#   - Where should I look next?
#
# READ-ONLY / SAFE / ACTIONABLE / SECRET-SAFE / DETERMINISTIC (see
# docs/tasks/0033d-diagnostics-logging-storage-lifecycle.md DOCTOR
# CONTRACT). This script NEVER mutates state to inspect it: no module
# reload, no config regeneration, no container restart, no secret
# rotation, no reconcile-apply. It may recommend those operations by
# name (e.g. "run 'make rotate-secrets'"); it never runs them itself.
#
# Reuses, rather than reimplements, the existing operational contracts:
#   - scripts/lib/secrets-lib.sh's slib_db_user_auth_check/
#     slib_ami_auth_check for the live DB/AMI auth checks (same
#     primitives scripts/secrets-check.sh itself uses)
#   - scripts/secrets-check.sh as a whole, for the Secrets section
#   - docker/reconcile-pjsip.php --check (TASK-0033B), for the PJSIP
#     section
# No second implementation of secret-drift or PJSIP-drift detection
# exists in this file.
#
# Usage:
#   scripts/doctor.sh [--verbose]
#   VERBOSE=1 scripts/doctor.sh
#
# Result vocabulary (see docs/tasks/
# 0033d-diagnostics-logging-storage-lifecycle.md RESULT VOCABULARY):
#   PASS    -- verified healthy
#   WARN    -- degraded/notable but not an outage; doctor stays usable
#              in automation (exit 0 contribution)
#   FAIL    -- broken or a security-relevant coherence failure
#   UNKNOWN -- could not be determined (dependency unreachable, ran
#              into an unexpected error) -- never silently treated as
#              PASS or FAIL
#   SKIP    -- deliberately not checked (precondition not met, e.g. a
#              container that doesn't exist at all)
#
# Exit code: 0 if no check is FAIL, nonzero (1) if any check is FAIL.
# WARN/UNKNOWN/SKIP never affect the exit code -- see docs/tasks/
# 0033d-diagnostics-logging-storage-lifecycle.md EXIT CODES for the
# full rationale (this keeps `make doctor` usable in scripts/CI without
# every routine warning breaking automation).
#
# Failure isolation: every check is independently guarded. A FAIL/
# UNKNOWN in one check (e.g. the database being down) never prevents
# any other check (Asterisk, storage, logs, secrets) from running and
# reporting its own real result.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/secrets-lib.sh
source "$SCRIPT_DIR/lib/secrets-lib.sh"
# shellcheck source=lib/wss-cert-lib.sh
source "$SCRIPT_DIR/lib/wss-cert-lib.sh"

COMPOSE="${SMOKE_COMPOSE:-docker compose}"
# `VERBOSE=1 scripts/doctor.sh` and `scripts/doctor.sh --verbose` both
# work identically -- default to whatever the environment already
# declared (0 if unset), then let the CLI flag force it on.
VERBOSE="${VERBOSE:-0}"
case "${1:-}" in
    --verbose) VERBOSE=1 ;;
esac

RESULT_NAMES=()
RESULT_STATES=()
RESULT_REASONS=()
RESULT_VERBOSE=()

record() {
    RESULT_NAMES+=("$1")
    RESULT_STATES+=("$2")
    RESULT_REASONS+=("$3")
    RESULT_VERBOSE+=("${4:-}")
}

container_state() {
    # Prints "MISSING" / "<Status text>" for the named service. `-a` is
    # required: plain `docker compose ps` only lists RUNNING containers
    # by default, making a cleanly-stopped container (`docker compose
    # stop`) indistinguishable from one that was never created at all
    # (confirmed live during this task's own validation) -- `-a`
    # surfaces "exited"/"created" states too, which check_container()
    # below classifies as FAIL, not SKIP.
    local svc="$1" line
    line="$($COMPOSE ps -a "$svc" --format '{{.State}}' 2>/dev/null)"
    [ -n "$line" ] && echo "$line" || echo "MISSING"
}

container_health() {
    local svc="$1"
    $COMPOSE ps -a "$svc" --format '{{.Health}}' 2>/dev/null
}

# =============================================================================
# Docker / runtime
# =============================================================================

check_prerequisites() {
    if ! command -v docker >/dev/null 2>&1; then
        record "Docker CLI" "FAIL" "docker command not found"
    else
        record "Docker CLI" "PASS" "found"
    fi
    if docker compose version >/dev/null 2>&1; then
        record "Docker Compose v2" "PASS" "found"
    else
        record "Docker Compose v2" "FAIL" "'docker compose version' failed -- Compose v2 required"
    fi
    if [ -f "$REPO_ROOT/.env" ]; then
        record ".env file" "PASS" "present"
    else
        record ".env file" "FAIL" ".env missing -- run 'cp .env.example .env'"
    fi
    if $COMPOSE config >/dev/null 2>&1; then
        record "compose.yaml valid" "PASS" "'docker compose config' succeeded"
    else
        record "compose.yaml valid" "FAIL" "'docker compose config' failed -- see 'docker compose config' output directly"
    fi
}

check_docker_daemon() {
    if docker info >/dev/null 2>&1; then
        record "Docker daemon" "PASS" "reachable"
    else
        record "Docker daemon" "FAIL" "not reachable -- is Docker running?"
    fi
}

check_container() {
    # TASK-0034C: `provider` (compose.yaml) is a DEVELOPMENT_ONLY/TEST_ONLY
    # fixture gated behind Compose profiles -- MISSING is its expected,
    # correct state on any host where nobody opted into `dev`/`test`
    # (including a normal `make dev` and every pilot host), not a defect.
    # A RUNNING provider is not wrong either (a developer/regression run
    # may have opted in deliberately) but is worth calling out by name so
    # an operator glancing at `make doctor` on a suspect host immediately
    # sees "fixture active", not just "running" indistinguishable from
    # app/asterisk/db. Classification logic itself (PASS/WARN/FAIL) is
    # unchanged for every state -- only the reason text gains an
    # annotation for this one known fixture service.
    local svc="$1" state health fixture_note=""
    [ "$svc" = "provider" ] && fixture_note=" -- DEVELOPMENT_ONLY/TEST_ONLY fixture (TASK-0034C); confirm this is intentional before a production/pilot release"
    state="$(container_state "$svc")"
    if [ "$state" = "MISSING" ]; then
        if [ "$svc" = "provider" ]; then
            record "Container: $svc" "SKIP" "no container for this service -- expected unless 'dev'/'test' was explicitly opted into (make dev-up, or FIXTURE_PROFILE=dev/test)"
        else
            record "Container: $svc" "SKIP" "no container for this service (run 'make up' to create it)"
        fi
        return
    fi
    health="$(container_health "$svc")"
    case "$state" in
        running)
            case "$health" in
                healthy|"") record "Container: $svc" "PASS" "running${health:+, $health}${fixture_note}" ;;
                starting)   record "Container: $svc" "WARN" "running, health check still starting${fixture_note}" ;;
                unhealthy)  record "Container: $svc" "FAIL" "running but unhealthy${fixture_note}" ;;
                *)          record "Container: $svc" "WARN" "running, health state: $health${fixture_note}" ;;
            esac
            ;;
        restarting) record "Container: $svc" "FAIL" "restarting (crash-looping) -- check 'docker compose logs $svc'" ;;
        exited|dead) record "Container: $svc" "FAIL" "not running ($state)" ;;
        *) record "Container: $svc" "UNKNOWN" "unexpected state: $state" ;;
    esac
}

# =============================================================================
# Database
# =============================================================================

# Pure TCP-level reachability -- deliberately credential-free, so it
# distinguishes "the DB service isn't even listening" from "it's
# listening but rejected these credentials" (the latter is the Secrets
# section's job, via slib_db_user_auth_check below).
check_db_reachable() {
    if [ "$(container_state db)" != "running" ]; then
        record "Database reachable" "SKIP" "db container is not running"
        return
    fi
    local out
    out="$($COMPOSE exec -T db bash -c '
        exec 3<>/dev/tcp/127.0.0.1/3306 2>/dev/null && { echo OK; exec 3<&- 3>&-; } || echo FAIL
    ' 2>/dev/null)"
    if [ "$out" = "OK" ]; then
        record "Database reachable" "PASS" "TCP connect to 127.0.0.1:3306 succeeded"
    else
        record "Database reachable" "FAIL" "TCP connect to 127.0.0.1:3306 failed"
    fi
}

check_db_auth() {
    if [ "$(container_state db)" != "running" ]; then
        record "Application DB authentication" "SKIP" "db container is not running"
        return
    fi
    if [ -z "${DB_USER:-}" ] || [ -z "${DB_PASSWORD:-}" ]; then
        record "Application DB authentication" "UNKNOWN" "DB_USER/DB_PASSWORD not set (source .env first)"
        return
    fi
    local status
    status="$(slib_db_user_auth_check db "$DB_USER" "$DB_PASSWORD" 2>/dev/null)"
    case "$status" in
        MATCH) record "Application DB authentication" "PASS" "declared DB_PASSWORD authenticates" ;;
        DRIFT) record "Application DB authentication" "FAIL" "declared DB_PASSWORD does not authenticate -- see Secrets section" ;;
        *) record "Application DB authentication" "UNKNOWN" "could not determine (see Secrets section for detail)" ;;
    esac
}

check_db_schema() {
    if [ "$(container_state db)" != "running" ]; then
        record "Expected schema present" "SKIP" "db container is not running"
        return
    fi
    if [ -z "${DB_USER:-}" ] || [ -z "${DB_PASSWORD:-}" ] || [ -z "${DB_NAME:-}" ]; then
        record "Expected schema present" "UNKNOWN" "DB_USER/DB_PASSWORD/DB_NAME not set (source .env first)"
        return
    fi
    local out
    out="$($COMPOSE exec -T db sh -c "read -r PW; MYSQL_PWD=\"\$PW\" mariadb -u'${DB_USER}' '${DB_NAME}' -N -e \"SHOW TABLES LIKE 'core_config';\"" <<< "$DB_PASSWORD" 2>/dev/null)"
    if [ "$(printf '%s' "$out" | tr -d '\r\n')" = "core_config" ]; then
        record "Expected schema present" "PASS" "core_config table present in '${DB_NAME}'"
    else
        record "Expected schema present" "FAIL" "core_config table not found in '${DB_NAME}' -- schema may not be imported"
    fi
}

# TASK-0033F: reuses docker/migrate.php's own detection logic (invoked
# via `make migrate-check`'s exact command inside the app container)
# rather than reimplementing schema-version comparison here (Phase 38's own explicit
# instruction: "do not duplicate migration detection logic inside
# doctor"). Exit codes: 0 CURRENT, 2 UNKNOWN, 3 BEHIND, 4 AHEAD.
check_db_migration_status() {
    if [ "$(container_state app)" != "running" ]; then
        record "Database schema" "SKIP" "app container is not running"
        return
    fi
    local out rc
    out="$($COMPOSE exec -T app php /usr/local/bin/migrate.php --check 2>&1)"
    rc=$?
    case "$rc" in
        0) record "Database schema" "PASS" "CURRENT -- $(printf '%s' "$out" | grep '^Current schema:')" ;;
        3) record "Database schema" "WARN" "BEHIND -- $(printf '%s' "$out" | grep -c '^  ') pending migration(s), run 'make migrate-check' for detail" ;;
        4) record "Database schema" "FAIL" "AHEAD -- database has migrations this codebase does not ship; see 'make migrate-check'" ;;
        2) record "Database schema" "FAIL" "UNKNOWN -- structural fingerprint did not match any known baseline; see 'make migrate-check'" ;;
        *) record "Database schema" "UNKNOWN" "migrate.php --check exited $rc: $(printf '%s' "$out" | tail -1)" ;;
    esac
}

# =============================================================================
# Application
# =============================================================================

check_app_http() {
    if [ "$(container_state app)" != "running" ]; then
        record "Application HTTP reachable" "SKIP" "app container is not running"
        return
    fi
    local base_url code
    base_url="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "${base_url}/" 2>/dev/null)"
    if [ "$code" = "200" ]; then
        record "Application HTTP reachable" "PASS" "HTTP 200 at ${base_url}/"
    elif [ -n "$code" ] && [ "$code" != "000" ]; then
        record "Application HTTP reachable" "WARN" "HTTP ${code} at ${base_url}/ (reachable, unexpected status)"
    else
        record "Application HTTP reachable" "FAIL" "no response from ${base_url}/"
    fi
}

check_app_content() {
    if [ "$(container_state app)" != "running" ]; then
        record "Application renders login page" "SKIP" "app container is not running"
        return
    fi
    local base_url body
    base_url="${SMOKE_BASE_URL:-http://localhost:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
    body="$(curl -s --max-time 5 "${base_url}/" 2>/dev/null)"
    if printf '%s' "$body" | grep -q '<title>SNEP - Login</title>'; then
        record "Application renders login page" "PASS" "expected login-page title present"
    else
        record "Application renders login page" "FAIL" "expected login-page title not found -- read-only check, no data modified"
    fi
}

# =============================================================================
# Asterisk
# =============================================================================

check_asterisk_cli() {
    if [ "$(container_state asterisk)" != "running" ]; then
        record "Asterisk CLI reachable" "SKIP" "asterisk container is not running"
        return
    fi
    local out
    out="$($COMPOSE exec -T asterisk asterisk -rx "core show version" 2>/dev/null)"
    if printf '%s' "$out" | grep -q "Asterisk"; then
        record "Asterisk CLI reachable" "PASS" "$(printf '%s' "$out" | head -1 | cut -c1-60)"
    else
        record "Asterisk CLI reachable" "FAIL" "CLI did not respond"
    fi
}

check_asterisk_pjsip_module() {
    if [ "$(container_state asterisk)" != "running" ]; then
        record "PJSIP module loaded" "SKIP" "asterisk container is not running"
        return
    fi
    local out
    out="$($COMPOSE exec -T asterisk asterisk -rx "module show like res_pjsip.so" 2>/dev/null)"
    if printf '%s' "$out" | grep -q "Running"; then
        record "PJSIP module loaded" "PASS" "res_pjsip.so Running"
    else
        record "PJSIP module loaded" "FAIL" "res_pjsip.so not Running -- see 'docker compose logs asterisk'"
    fi
}

check_asterisk_http_wss() {
    if [ "$(container_state asterisk)" != "running" ]; then
        record "Asterisk HTTP/WSS listener" "SKIP" "asterisk container is not running"
        return
    fi
    local out
    out="$($COMPOSE exec -T asterisk asterisk -rx "http show status" 2>/dev/null)"
    if printf '%s' "$out" | grep -qi "Server Enabled"; then
        local https_line
        https_line="$(printf '%s' "$out" | grep -i "HTTPS Server" | head -1)"
        record "Asterisk HTTP/WSS listener" "PASS" "${https_line:-HTTP server enabled}"
    else
        record "Asterisk HTTP/WSS listener" "WARN" "HTTP server not reported enabled (WSS/media-over-websocket unavailable)"
    fi
}

check_asterisk_ami() {
    if [ "$(container_state asterisk)" != "running" ]; then
        record "AMI reachable" "SKIP" "asterisk container is not running"
        return
    fi
    if [ -z "${AMI_USER:-}" ] || [ -z "${AMI_PASSWORD:-}" ]; then
        record "AMI reachable" "UNKNOWN" "AMI_USER/AMI_PASSWORD not set (source .env first)"
        return
    fi
    local status
    status="$(slib_ami_auth_check asterisk "$AMI_USER" "$AMI_PASSWORD" 2>/dev/null)"
    case "$status" in
        MATCH) record "AMI reachable" "PASS" "declared AMI_PASSWORD authenticates" ;;
        DRIFT) record "AMI reachable" "FAIL" "declared AMI_PASSWORD does not authenticate -- see Secrets section" ;;
        *) record "AMI reachable" "UNKNOWN" "could not determine (see Secrets section for detail)" ;;
    esac
}

# =============================================================================
# PJSIP (reconcile-check integration, TASK-0033B -- no second implementation)
# =============================================================================

check_pjsip_reconcile() {
    if [ "$(container_state asterisk)" != "running" ]; then
        record "PJSIP configuration" "SKIP" "asterisk container is not running"
        return
    fi
    local out rc
    out="$($COMPOSE exec -T asterisk php /usr/local/bin/reconcile-pjsip.php --check 2>&1)"
    rc=$?
    case "$rc" in
        0) record "PJSIP configuration" "PASS" "IN_SYNC (make reconcile-check)" "$out" ;;
        3) record "PJSIP configuration" "WARN" "DRIFTED -- run 'make reconcile' to regenerate from the database" "$out" ;;
        *) record "PJSIP configuration" "UNKNOWN" "reconcile-check exited $rc -- see 'make reconcile-check' for detail" "$out" ;;
    esac
}

check_pjsip_snapshot() {
    if [ "$(container_state asterisk)" != "running" ]; then
        record "PJSIP runtime snapshot" "SKIP" "asterisk container is not running"
        return
    fi
    local endpoints regs transports channels
    endpoints="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show endpoints" 2>/dev/null | grep -c '^ Endpoint:')"
    regs="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show registrations" 2>/dev/null | grep -c '^ Registration:')"
    transports="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show transports" 2>/dev/null | grep -c '^Transport:  [a-z]')"
    channels="$($COMPOSE exec -T asterisk asterisk -rx "core show channels count" 2>/dev/null | head -1)"
    record "PJSIP runtime snapshot" "PASS" "endpoints=${endpoints:-0} registrations=${regs:-0} transports=${transports:-0}; ${channels:-unknown}"

    # PLATFORM HEALTH (above: transports/modules bound) is deliberately
    # separate from TELEPHONY EXTERNAL STATUS (below): a real customer
    # trunk failing to register against a carrier is an external-
    # dependency condition, never a SENMA platform defect, and must
    # never flip doctor's own exit code.
    if [ "${regs:-0}" != "0" ]; then
        local reg_detail unregistered
        reg_detail="$($COMPOSE exec -T asterisk asterisk -rx "pjsip show registrations" 2>/dev/null)"
        unregistered="$(printf '%s' "$reg_detail" | grep -ciE 'Rejected|Unregistered')"
        if [ "${unregistered:-0}" -gt 0 ]; then
            record "Telephony: trunk registrations" "WARN" "${unregistered} of ${regs} registration(s) not Registered -- external dependency, not a platform defect"
        else
            record "Telephony: trunk registrations" "PASS" "${regs} registration(s), all Registered"
        fi
    fi
}

# =============================================================================
# Secrets (TASK-0033C integration -- no second implementation)
# =============================================================================

check_secrets() {
    if [ "$(container_state db)" != "running" ]; then
        record "Secrets" "SKIP" "db container is not running"
        return
    fi
    local out rc
    out="$(bash "$SCRIPT_DIR/secrets-check.sh" 2>&1)"
    rc=$?
    case "$rc" in
        0) record "Secrets" "PASS" "all declared secrets MATCH their active/persisted value" "$out" ;;
        3) record "Secrets" "FAIL" "DRIFT -- run 'make secrets-check' for which secret, then 'make rotate-secrets'" "$out" ;;
        *) record "Secrets" "UNKNOWN" "secrets-check.sh exited $rc" "$out" ;;
    esac
}

# =============================================================================
# Release identity (TASK-0034D integration -- no second implementation)
# =============================================================================

check_release_identity() {
    if [ "$(container_state app)" != "running" ] && [ "$(container_state asterisk)" != "running" ]; then
        record "Release artifact identity" "SKIP" "app/asterisk not running"
        return
    fi
    local out rc
    out="$(bash "$SCRIPT_DIR/release-info.sh" --summary 2>&1)"
    rc=$?
    case "$rc" in
        0)
            if printf '%s' "$out" | grep -q "UNKNOWN"; then
                record "Release artifact identity" "SKIP" "no release-manifest.json recorded yet -- expected for a dev build; run 'make release-build VERSION=vX.Y.Z' before a pilot/production deploy" "$out"
            else
                record "Release artifact identity" "PASS" "MATCH -- running images match the recorded release (see 'make release-info')" "$out"
            fi
            ;;
        1) record "Release artifact identity" "FAIL" "DRIFT -- run 'make release-info' for detail" "$out" ;;
        *) record "Release artifact identity" "UNKNOWN" "release-info.sh exited $rc" "$out" ;;
    esac
}

# =============================================================================
# Storage
# =============================================================================

check_disk_free() {
    local avail_kb avail_human
    avail_kb="$(df -Pk "$REPO_ROOT" 2>/dev/null | awk 'NR==2 {print $4}')"
    if [ -z "$avail_kb" ]; then
        record "Host disk free space" "UNKNOWN" "could not determine free space at $REPO_ROOT"
        return
    fi
    avail_human="$(df -Ph "$REPO_ROOT" 2>/dev/null | awk 'NR==2 {print $4}')"
    if [ "$avail_kb" -lt 1048576 ]; then
        record "Host disk free space" "FAIL" "${avail_human} free at $REPO_ROOT -- below 1 GiB"
    elif [ "$avail_kb" -lt 5242880 ]; then
        record "Host disk free space" "WARN" "${avail_human} free at $REPO_ROOT -- below 5 GiB"
    else
        record "Host disk free space" "PASS" "${avail_human} free at $REPO_ROOT"
    fi
}

# blib-style volume size probe (same technique scripts/backup.sh's own
# vol_size_kb helper uses: a throwaway read-only mount, no image beyond
# `alpine`, which this host may need to pull once).
volume_size_human() {
    local short="$1" vol
    vol="$(docker volume ls -q --filter "label=com.docker.compose.project=${COMPOSE_PROJECT_NAME:-mag-pbx}" --filter "label=com.docker.compose.volume=${short}" 2>/dev/null)"
    [ -n "$vol" ] || { echo "N/A"; return; }
    docker run --rm -v "${vol}:/vol:ro" alpine du -sh /vol 2>/dev/null | awk '{print $1}'
}

check_volumes() {
    local db_size log_size etc_size
    db_size="$(volume_size_human mag-db)"
    log_size="$(volume_size_human mag-asterisk-log)"
    etc_size="$(volume_size_human asterisk-etc)"
    record "Named volume usage" "PASS" "mag-db=${db_size:-N/A} mag-asterisk-log=${log_size:-N/A} asterisk-etc=${etc_size:-N/A}"
}

# =============================================================================
# Logs
# =============================================================================

log_size_bytes() {
    local container="$1" path="$2"
    $COMPOSE exec -T "$container" sh -c "stat -c %s '$path' 2>/dev/null" 2>/dev/null
}

check_logs() {
    local ast_full ast_full_h app_err app_err_h
    if [ "$(container_state asterisk)" = "running" ]; then
        ast_full="$(log_size_bytes asterisk /var/log/asterisk/full)"
        if [ -n "$ast_full" ]; then
            ast_full_h="$(( ast_full / 1024 / 1024 ))MB"
            if [ "$ast_full" -ge 104857600 ]; then
                record "Asterisk full log" "WARN" "${ast_full_h} -- at/above the 100 MiB rotation threshold (docker/log-rotate-asterisk.sh rotates on its next check cycle)"
            else
                record "Asterisk full log" "PASS" "${ast_full_h}"
            fi
        else
            record "Asterisk full log" "UNKNOWN" "could not stat /var/log/asterisk/full"
        fi
    else
        record "Asterisk full log" "SKIP" "asterisk container is not running"
    fi

    if [ "$(container_state app)" = "running" ]; then
        app_err="$(log_size_bytes app /var/log/apache2/mag-error.log)"
        if [ -n "$app_err" ]; then
            app_err_h="$(( app_err / 1024 ))KB"
            if [ "$app_err" -ge 52428800 ]; then
                record "Application error log" "WARN" "${app_err_h} -- at/above the 50 MiB rotation threshold"
            else
                record "Application error log" "PASS" "${app_err_h}"
            fi
        else
            record "Application error log" "UNKNOWN" "could not stat /var/log/apache2/mag-error.log"
        fi
    else
        record "Application error log" "SKIP" "app container is not running"
    fi
}

# =============================================================================
# Backup diagnostics (TASK-0033A destination, no backup taken)
# =============================================================================

check_backup_destination() {
    local dest="$REPO_ROOT/backups"
    if [ ! -d "$dest" ]; then
        record "Backup destination" "WARN" "$dest does not exist yet -- created on first 'make backup'"
        return
    fi
    if [ ! -w "$dest" ]; then
        record "Backup destination" "FAIL" "$dest exists but is not writable"
        return
    fi
    local avail_human
    avail_human="$(df -Ph "$dest" 2>/dev/null | awk 'NR==2 {print $4}')"
    record "Backup destination" "PASS" "$dest exists, writable, ${avail_human:-unknown} free"
}

# =============================================================================
# Certificate diagnostics (TASK-0034E, closing TASK-0034's Finding CH-2)
#
# Reuses scripts/wss-cert-check.sh (itself built on scripts/lib/
# wss-cert-lib.sh) rather than re-implementing certificate parsing here
# -- this is the SAME trust-state vocabulary and the SAME live-runtime
# verification `make cert-check` exposes to an operator directly. Prior
# to TASK-0034E this check was hardcoded to the dev-fixture path
# (/etc/asterisk/keys/wss-test-cert.pem) and could never detect "pilot
# went live still pointed at the fixture cert" -- it now reads whichever
# certificate the live `wss`/`ws` transport is ACTUALLY configured to
# use, straight from the database, and confirms what the live listener
# actually presents.
# =============================================================================

check_certificate() {
    if [ "$(container_state asterisk)" != "running" ]; then
        record "TLS/WSS certificate" "SKIP" "asterisk container is not running"
        return
    fi
    if [ "$(container_state db)" != "running" ]; then
        record "TLS/WSS certificate" "SKIP" "db container is not running (needed to read the configured wss transport)"
        return
    fi
    if [ -z "${DB_USER:-}" ] || [ -z "${DB_PASSWORD:-}" ]; then
        record "TLS/WSS certificate" "UNKNOWN" "DB_USER/DB_PASSWORD not set (source .env first)"
        return
    fi

    local out trust fixture
    out="$(SMOKE_COMPOSE="$COMPOSE" bash "$SCRIPT_DIR/wss-cert-check.sh" 2>/dev/null)"
    if [ -z "$out" ]; then
        record "TLS/WSS certificate" "UNKNOWN" "scripts/wss-cert-check.sh produced no output"
        return
    fi
    trust="$(printf '%s\n' "$out" | sed -n 's/^TRUST_STATE: //p')"
    fixture="$(printf '%s\n' "$out" | sed -n 's/^FIXTURE: //p')"

    case "$trust" in
        "")
            record "TLS/WSS certificate" "UNKNOWN" "no enabled ws/wss transport, or check could not run -- see 'make cert-check'"
            ;;
        MISSING)
            record "TLS/WSS certificate" "WARN" "certificate or key file missing -- see 'make cert-check'"
            ;;
        UNREADABLE|PAIR_MISMATCH|EXPIRED|NOT_YET_VALID)
            record "TLS/WSS certificate" "FAIL" "$trust -- see 'make cert-check' for detail (never prints key material)"
            ;;
        HOSTNAME_MISMATCH)
            record "TLS/WSS certificate" "WARN" "certificate does not cover the configured WSS_PUBLIC_HOSTNAME -- see 'make cert-check'"
            ;;
        RUNTIME_MISMATCH)
            record "TLS/WSS certificate" "WARN" "the configured certificate file changed but the live listener has not picked it up yet -- re-apply the HTTP/TLS config (see docs/tasks/0029a-tls-transport-certificate-management.md), then re-check"
            ;;
        RUNTIME_UNREACHABLE)
            record "TLS/WSS certificate" "WARN" "could not confirm the live WSS listener's certificate (connection failed) -- see 'make cert-check'"
            ;;
        SELF_SIGNED*)
            case "$fixture" in
                yes*) record "TLS/WSS certificate" "WARN" "dev-fixture certificate in use -- must be replaced before pilot go-live (docs/operations/production-release-runbook.md step 4)" ;;
                *) record "TLS/WSS certificate" "WARN" "self-signed certificate -- confirm this is intentional (private CA deployments should set ca_list_file)" ;;
            esac
            ;;
        TRUSTED*)
            case "$trust" in
                *EXPIRING_SOON*) record "TLS/WSS certificate" "WARN" "trusted certificate is expiring soon -- see 'make cert-check' for the exact date" ;;
                *) record "TLS/WSS certificate" "PASS" "trusted certificate, live runtime confirmed" ;;
            esac
            ;;
        *)
            record "TLS/WSS certificate" "UNKNOWN" "unrecognized trust state '$trust' -- see 'make cert-check'"
            ;;
    esac
}

# =============================================================================
# Run everything -- every call is independently guarded (each function
# above returns via `record`, never exits/dies), so a crash in one
# check cannot prevent the rest from running.
# =============================================================================

check_prerequisites
check_docker_daemon
for svc in app asterisk db provider; do check_container "$svc"; done
check_db_reachable
check_db_auth
check_db_schema
check_db_migration_status
check_app_http
check_app_content
check_asterisk_cli
check_asterisk_pjsip_module
check_asterisk_http_wss
check_asterisk_ami
check_pjsip_reconcile
check_pjsip_snapshot
check_secrets
check_release_identity
check_disk_free
check_volumes
check_logs
check_backup_destination
check_certificate

# =============================================================================
# Report
# =============================================================================

echo
i=0
FAIL_COUNT=0
while [ "$i" -lt "${#RESULT_NAMES[@]}" ]; do
    name="${RESULT_NAMES[$i]}"
    state="${RESULT_STATES[$i]}"
    reason="${RESULT_REASONS[$i]}"
    printf "[%-7s] %s: %s\n" "$state" "$name" "$reason"
    if [ "$VERBOSE" = "1" ] && [ -n "${RESULT_VERBOSE[$i]}" ]; then
        printf '%s\n' "${RESULT_VERBOSE[$i]}" | sed 's/^/    /'
    fi
    [ "$state" = "FAIL" ] && FAIL_COUNT=$((FAIL_COUNT + 1))
    i=$((i + 1))
done

echo
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "doctor: no FAIL -- exit 0"
    exit 0
else
    echo "doctor: ${FAIL_COUNT} FAIL -- exit 1"
    exit 1
fi
