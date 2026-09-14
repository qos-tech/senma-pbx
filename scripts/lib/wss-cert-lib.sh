#!/bin/bash
#
# SENMA WSS certificate trust/runtime verification library (TASK-0034E,
# closing TASK-0034's Finding CH-2).
#
# Shared by scripts/wss-cert-check.sh (the operator-facing `make
# cert-check`/`make wss-cert-check` tool) and scripts/doctor.sh's
# `check_certificate` -- ONE certificate-parsing/classification
# implementation, not two. Read-only: never mutates database rows,
# generated config, or Asterisk runtime state. Secret-safe: never prints
# private key bytes or PEM body content -- only metadata (subject,
# issuer, SAN, validity window, fingerprints, public-key hashes).
#
# Background (docs/tasks/0029a-tls-transport-certificate-management.md,
# SUPERSEDED IN PART by TASK-0035A):
# Public WSS TLS terminates at the SENMA reverse proxy (Apache in `app`).
# The public certificate lives at /etc/senma/certs/public-wss.crt by
# default (operator-mounted or DEV fixture). Asterisk receives private
# plain WS on the Docker network (ws://asterisk:8088/ws). Asterisk HTTP
# TLS (senma-http-tls.conf from a ws/wss row's cert_file) is optional and
# NOT the public WSS trust surface after TASK-0035A. Native SIP TLS
# (protocol=tls) remains a separate certificate lifecycle.
#
# See docs/tasks/0034e-production-wss-certificate-trust-runtime-verification.md
# for the full trust-state vocabulary and pilot-acceptance contract this
# library implements.

WCL_COMPOSE="${SMOKE_COMPOSE:-${COMPOSE:-docker compose}}"

wcl_log() { printf '%s\n' "$*" >&2; }

# wcl_cert_exec <shell-command-string> -- runs a read-only command
# inside the asterisk container. Every caller in this library only ever
# passes cat/openssl/stat/test -- never a mutating command.
wcl_asterisk_exec() {
    $WCL_COMPOSE exec -T asterisk bash -c "$1" 2>/dev/null
}

# wcl_app_exec <shell-command-string> -- read-only command inside the app
# container (TASK-0035A public WSS certificate owner).
wcl_app_exec() {
    $WCL_COMPOSE exec -T app bash -c "$1" 2>/dev/null
}

# wcl_cert_exec -- TASK-0035A: public WSS cert material is owned by app.
wcl_cert_exec() {
    wcl_app_exec "$1"
}

# wcl_host_exec <shell-command-string> -- runs directly on whatever host
# this script itself executes on (no docker exec) -- used only for
# --connect against a real externally-reachable pilot endpoint, where the
# whole point is to prove reachability from OUTSIDE the Docker network,
# not from inside the asterisk container.
wcl_host_exec() {
    bash -c "$1" 2>/dev/null
}

# --- DB access (the one source of truth for the configured wss transport) ---

# wcl_db_query <sql> -- tab-separated, header-free (-N) result. Requires
# DB_USER/DB_PASSWORD/DB_NAME already in the environment (sourced from
# .env by the caller, same convention as every other script in this
# repository -- see scripts/tls-cert-management-smoke-test.sh's own
# db_query()).
wcl_db_query() {
    $WCL_COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-}" \
        "${DB_NAME:-snep}" -N -e "$1" 2>/dev/null
}

# wcl_wss_transport_row -- the one enabled ws/wss transport row (0029A's
# own invariant: at most one may be enabled process-wide, enforced at
# save time). Fields joined with ASCII 0x1F (unit separator) -- a plain
# tab collapses/strips on empty fields under bash `read`'s default
# IFS-whitespace handling (domain/external_signaling_address are NULL on
# a fresh install), silently shifting every field after the first empty
# one. Parse with `IFS=$'\x1f' read -r ...` (a non-whitespace IFS
# character preserves empty fields correctly). Empty if none is enabled.
# Field order: id, protocol, bind_address, bind_port, domain,
# external_signaling_address, cert_file, priv_key_file, ca_list_file.
wcl_wss_transport_row() {
    wcl_db_query "SELECT CONCAT_WS(CHAR(31), id, protocol, bind_address, bind_port, COALESCE(domain,''), COALESCE(external_signaling_address,''), COALESCE(cert_file,''), COALESCE(priv_key_file,''), COALESCE(ca_list_file,'')) FROM pjsip_transports WHERE protocol IN ('wss','ws') AND enabled=1 LIMIT 1;"
}

# --- Hostname source of truth (Phase 7) --------------------------------
#
# Precedence: an explicit --hostname override (caller-supplied, used by
# isolated negative-test fixtures) > WSS_PUBLIC_HOSTNAME (.env -- the
# authoritative pilot deployment setting, TASK-0034E) > the wss
# transport's own external_signaling_address > its own domain column.
# Empty means "not configured" -- callers must treat that as an explicit
# gap, never silently skip-and-pass.
wcl_public_hostname() {
    local override="$1" ext_addr="$2" domain="$3"
    if [ -n "$override" ]; then echo "$override"; return; fi
    if [ -n "${WSS_PUBLIC_HOSTNAME:-}" ]; then echo "$WSS_PUBLIC_HOSTNAME"; return; fi
    if [ -n "$ext_addr" ]; then echo "$ext_addr"; return; fi
    if [ -n "$domain" ]; then echo "$domain"; return; fi
    echo ""
}

# --- File-level checks (Phase 8/9/10/18) -------------------------------

wcl_file_exists() {
    [ "$(wcl_cert_exec "[ -f '$1' ] && echo yes || echo no")" = "yes" ]
}

wcl_file_mode() {
    wcl_cert_exec "stat -c %a '$1' 2>/dev/null" | tr -d '\r\n'
}

wcl_cert_parses() {
    wcl_cert_exec "openssl x509 -in '$1' -noout" >/dev/null 2>&1
}

wcl_cert_field_subject() { wcl_cert_exec "openssl x509 -in '$1' -noout -subject" | sed -e 's/^subject=//'; }
wcl_cert_field_issuer()  { wcl_cert_exec "openssl x509 -in '$1' -noout -issuer"  | sed -e 's/^issuer=//'; }
wcl_cert_field_notbefore() { wcl_cert_exec "openssl x509 -in '$1' -noout -startdate" | sed -e 's/^notBefore=//'; }
wcl_cert_field_notafter()  { wcl_cert_exec "openssl x509 -in '$1' -noout -enddate"   | sed -e 's/^notAfter=//'; }
wcl_cert_field_fingerprint() { wcl_cert_exec "openssl x509 -in '$1' -noout -fingerprint -sha256" | sed -e 's/^.*Fingerprint=//'; }

# wcl_cert_sans <path> -- raw "DNS:x, IP:y" content (empty if no SAN
# extension present at all -- CN-fallback callers must check for this).
wcl_cert_sans() {
    wcl_cert_exec "openssl x509 -in '$1' -noout -ext subjectAltName 2>/dev/null" \
        | grep -v "X509v3 Subject Alternative Name" | tr -d ' \r' | tr -d '\n'
}

# wcl_cert_not_yet_valid / wcl_cert_expired -- exact date-boundary
# checks, distinguished per Phase 10 (never collapsed into one generic
# "invalid" state).
wcl_cert_not_yet_valid() {
    # openssl -checkend only ever compares notAfter -- notBefore has no
    # equivalent flag, so it is compared directly against the
    # container's own current time instead.
    local notbefore now
    notbefore="$(wcl_cert_exec "date -d \"\$(openssl x509 -in '$1' -noout -startdate | sed 's/^notBefore=//')\" +%s" 2>/dev/null)"
    now="$(wcl_cert_exec "date +%s")"
    [ -n "$notbefore" ] && [ -n "$now" ] && [ "$notbefore" -gt "$now" ]
}

wcl_cert_expired() {
    ! wcl_cert_exec "openssl x509 -in '$1' -noout -checkend 0" >/dev/null 2>&1
}

# wcl_cert_expiring_soon <path> <warn_days> -- true if valid now but
# expires within warn_days. Mirrors doctor.sh's pre-existing 30-day
# threshold (Phase 10's "EXPIRING_SOON" warning window).
wcl_cert_expiring_soon() {
    local path="$1" warn_days="$2"
    wcl_cert_expired "$path" && return 1
    ! wcl_cert_exec "openssl x509 -in '$path' -noout -checkend $((warn_days * 86400))" >/dev/null 2>&1
}

# --- Pair validation (Phase 8) -- public-key hash comparison only, the
# private key's bytes are never read into a variable or printed. -------

# wcl_cert_pubkey_hash / wcl_key_pubkey_hash <path> -- print the hash and
# return 0 on success. On any failure (missing file, wrong permissions,
# not a valid cert/key), return NONZERO -- callers MUST check the exit
# code, not just emptiness of the output: `set -o pipefail` in the
# remote command makes the overall exit code correctly reflect an
# upstream `openssl` failure, but sha256sum/awk further down the same
# pipe still run (on empty stdin) and still print sha256("")'s fixed
# hash text regardless -- checking only "is the string non-empty" would
# silently mistake that fixed hash for a real one.
wcl_cert_pubkey_hash() {
    local path="$1"
    wcl_cert_exec "set -o pipefail; openssl x509 -in '$path' -noout -pubkey 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | sha256sum | awk '{print \$1}'"
}

wcl_key_pubkey_hash() {
    local path="$1"
    wcl_cert_exec "set -o pipefail; openssl pkey -in '$path' -pubout -outform DER 2>/dev/null | sha256sum | awk '{print \$1}'"
}

# --- Fixture identification (Phase 16) ----------------------------------
#
# Two independent signals, either one is sufficient -- deliberately NOT
# "any self-signed certificate is a fixture" (Phase 16/17: a private
# enterprise CA is a legitimate production choice, and a native `tls`
# transport's own admin-generated self-signed cert is a distinct,
# unrelated case this check must never flag).
WCL_FIXTURE_PATH="/etc/senma/certs/public-wss.crt"
WCL_FIXTURE_CN_MARKER="senma-public-wss-dev"
WCL_LEGACY_ASTERISK_FIXTURE_PATH="/etc/asterisk/keys/wss-test-cert.pem"
WCL_LEGACY_ASTERISK_FIXTURE_CN="senma-wss-test"

wcl_is_fixture_certificate() {
    local path="$1" subject="$2"
    # TASK-0035A: operators mount real certificates at the public path.
    # Path alone must not classify a certificate as a fixture — require
    # the known CN marker (or the legacy Asterisk fixture path+CN).
    case "$subject" in
        *"CN=${WCL_FIXTURE_CN_MARKER}"*|*"CN = ${WCL_FIXTURE_CN_MARKER}"*)
            echo "subject carries the public-WSS fixture marker (CN=${WCL_FIXTURE_CN_MARKER})"
            return 0
            ;;
        *"CN=${WCL_LEGACY_ASTERISK_FIXTURE_CN}"*|*"CN = ${WCL_LEGACY_ASTERISK_FIXTURE_CN}"*)
            echo "subject carries the legacy Asterisk WSS fixture marker (CN=${WCL_LEGACY_ASTERISK_FIXTURE_CN})"
            return 0
            ;;
    esac
    if [ "$path" = "$WCL_LEGACY_ASTERISK_FIXTURE_PATH" ]; then
        echo "legacy Asterisk WSS fixture path ($WCL_LEGACY_ASTERISK_FIXTURE_PATH) -- not the public WSS trust surface after TASK-0035A"
        return 0
    fi
    return 1
}

# --- Runtime verification (Phase 11 -- mandatory) -----------------------
#
# wcl_runtime_peek <connect-host:port> [sni] [via-app|via-asterisk|via-host]
# -- prints three tab-separated fields: leaf fingerprint (sha256, colon
# form matching wcl_cert_field_fingerprint's own format), chain depth
# (count of certificates the server actually sent), and "OK"/"UNREACHABLE".
# Deliberately does NOT pass -CAfile / disable verification -- this is a
# metadata PEEK (reading a public certificate a server offers to anyone),
# not a trust decision; the trust decision is computed separately from
# the file-level checks above plus the SIP-over-WSS trusted-client proof
# (scripts/wss-certificate-runtime-smoke-test.sh), which DOES verify.
#
# TASK-0035A: default public WSS peek is via-app against app:443 (or
# 127.0.0.1:443 from inside app). via-asterisk remains available for
# optional direct Asterisk HTTP TLS experiments; via-host proves an
# externally published pilot endpoint.
wcl_runtime_peek() {
    local target="$1" sni="${2:-${1%%:*}}" via="${3:-via-app}" raw certs fp depth attempt
    local cmd="echo | timeout 8 openssl s_client -connect '$target' -servername '$sni' -showcerts 2>/dev/null"
    for attempt in 1 2; do
        case "$via" in
            via-host) raw="$(wcl_host_exec "$cmd")" ;;
            via-asterisk|via-container) raw="$(wcl_asterisk_exec "$cmd")" ;;
            *) raw="$(wcl_app_exec "$cmd")" ;; # via-app (TASK-0035A default)
        esac
        [ -n "$raw" ] && break
        [ "$attempt" = "1" ] && sleep 1
    done
    if [ -z "$raw" ]; then
        printf '\t0\tUNREACHABLE\n'
        return 1
    fi
    depth="$(printf '%s' "$raw" | grep -c '^-----BEGIN CERTIFICATE-----')"
    certs="$(printf '%s' "$raw" | awk '/-----BEGIN CERTIFICATE-----/{p=1} p{print} /-----END CERTIFICATE-----/{if(p){exit}}')"
    if [ -z "$certs" ]; then
        printf '\t0\tUNREACHABLE\n'
        return 1
    fi
    case "$via" in
        via-host)
            fp="$(printf '%s\n' "$certs" | openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed -e 's/^.*Fingerprint=//')"
            ;;
        via-asterisk|via-container)
            fp="$($WCL_COMPOSE exec -T asterisk bash -c "openssl x509 -noout -fingerprint -sha256" <<<"$certs" 2>/dev/null | sed -e 's/^.*Fingerprint=//')"
            ;;
        *)
            fp="$($WCL_COMPOSE exec -T app bash -c "openssl x509 -noout -fingerprint -sha256" <<<"$certs" 2>/dev/null | sed -e 's/^.*Fingerprint=//')"
            ;;
    esac
    printf '%s\t%s\tOK\n' "$fp" "$depth"
}

# --- Chain-of-trust check (Phase 6/11) ----------------------------------
#
# wcl_cert_verifies_against_ca <cert-path> <ca-file-path-or-empty> --
# true if the cert chain-verifies against an explicit private/enterprise
# CA bundle (ca_list_file, TASK-0029A's own existing column -- Phase 6's
# "support a private enterprise CA explicitly" requirement) or, if none
# is configured, against the container's own system CA trust store
# (covers a public-CA-issued certificate). Never treated as proof by
# itself -- combined with self-signed detection by the caller.
wcl_cert_verifies_against_ca() {
    local cert="$1" cafile="$2"
    # TASK-0035A: public WSS cert material lives on `app`.
    if [ -n "$cafile" ]; then
        wcl_cert_exec "openssl verify -CAfile '$cafile' '$cert'" 2>/dev/null | grep -q ": OK$"
    else
        wcl_cert_exec "openssl verify '$cert'" 2>/dev/null | grep -q ": OK$"
    fi
}

wcl_is_self_signed() {
    local subject="$1" issuer="$2"
    [ -n "$subject" ] && [ "$subject" = "$issuer" ]
}
