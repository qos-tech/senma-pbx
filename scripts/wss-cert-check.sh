#!/bin/bash
#
# SENMA WSS certificate trust / runtime verification tool (TASK-0034E,
# closing TASK-0034's Finding CH-2).
#
# `make cert-check` / `make wss-cert-check` -- the one operator-facing
# answer to: "which certificate is the live WSS listener actually
# presenting, is it trustworthy, and is it acceptable for this pilot?"
#
# READ-ONLY / SECRET-SAFE / RUNTIME-AWARE:
#   - never mutates a database row, generated config file, or Asterisk
#     runtime state;
#   - never prints private key bytes or PEM body content -- only
#     metadata (subject, issuer, SAN, validity window, fingerprints,
#     public-key hashes);
#   - the certificate axis (file-level checks: existence, pair match,
#     validity window, hostname/SAN, fixture classification) is combined
#     with a REAL live connection to the actual listener (Phase 11's own
#     "a certificate path in http.conf is not sufficient proof" --
#     Finding CH-2's whole point).
#
# TASK-0035A: by default verifies the PUBLIC reverse-proxy WSS
# certificate on the `app` container (/etc/senma/certs/public-wss.crt)
# and peeks the live TLS handshake at app:443 (or --connect). An
# enabled ws/wss pjsip_transports row must still exist (signaling path),
# but Asterisk-side cert_file is NOT the public trust surface when TLS
# terminates at the proxy. Overrides remain for isolated testing.
#
# See docs/tasks/0034e-production-wss-certificate-trust-runtime-verification.md
# for the full trust-state vocabulary and pilot-acceptance contract.
#
# Usage:
#   scripts/wss-cert-check.sh [options]
#
# Options:
#   --pilot                 evaluate and print PILOT_ACCEPTANCE; exit
#                           nonzero if NOT_ACCEPTABLE_FOR_PILOT (default:
#                           informational only, always exit per trust
#                           state, never fails merely for being a dev
#                           fixture)
#   --cert PATH             override the configured cert_file (in-container path)
#   --key PATH              override the configured priv_key_file
#   --ca PATH               override the configured ca_list_file
#   --hostname HOST         override the authoritative WSS public hostname
#   --connect HOST:PORT     override the runtime endpoint to peek at --
#                           connects directly from wherever this script
#                           runs (NOT via docker exec) -- use this to
#                           prove the actual externally-reachable pilot
#                           listener, e.g. --connect pilot.example.com:443
#   --sni NAME              override the TLS SNI name sent (default: the
#                           connect host, or the hostname if set)
#   --no-runtime            skip the live runtime connection entirely
#                           (file-level checks only -- used by isolated
#                           negative-test fixtures where nothing is bound)
#   --warn-days N           EXPIRING_SOON threshold (default 30, matches
#                           the pre-existing doctor.sh threshold)
#
# Exit codes:
#   0  no problem found (and, with --pilot, PILOT_ACCEPTABLE)
#   1  a real trust-state problem was found (MISSING/UNREADABLE/
#      PAIR_MISMATCH/EXPIRED/NOT_YET_VALID/HOSTNAME_MISMATCH/
#      RUNTIME_MISMATCH/RUNTIME_UNREACHABLE), or --pilot was given and
#      the certificate is NOT_ACCEPTABLE_FOR_PILOT
#   2  could not evaluate at all (asterisk/db container not running, no
#      enabled ws/wss transport row, app/asterisk/db unreachable) -- UNKNOWN,
#      never silently treated as PASS

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/wss-cert-lib.sh
source "$SCRIPT_DIR/lib/wss-cert-lib.sh"

PILOT=0
OVERRIDE_CERT=""
OVERRIDE_KEY=""
OVERRIDE_CA=""
OVERRIDE_HOSTNAME=""
OVERRIDE_CONNECT=""
OVERRIDE_SNI=""
NO_RUNTIME=0
WARN_DAYS=30

while [ $# -gt 0 ]; do
    case "$1" in
        --pilot) PILOT=1 ;;
        --cert) OVERRIDE_CERT="$2"; shift ;;
        --key) OVERRIDE_KEY="$2"; shift ;;
        --ca) OVERRIDE_CA="$2"; shift ;;
        --hostname) OVERRIDE_HOSTNAME="$2"; shift ;;
        --connect) OVERRIDE_CONNECT="$2"; shift ;;
        --sni) OVERRIDE_SNI="$2"; shift ;;
        --no-runtime) NO_RUNTIME=1 ;;
        --warn-days) WARN_DAYS="$2"; shift ;;
        -h|--help)
            sed -n '2,60p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

unknown() {
    echo "TRUST_STATE: UNKNOWN"
    echo "PILOT_ACCEPTANCE: SKIPPED ($1)"
    echo "REASON: $1" >&2
    exit 2
}

if ! $WCL_COMPOSE ps -a asterisk --format '{{.State}}' 2>/dev/null | grep -q '^running$'; then
    unknown "asterisk container is not running"
fi
if ! $WCL_COMPOSE ps -a app --format '{{.State}}' 2>/dev/null | grep -q '^running$'; then
    unknown "app container is not running (public WSS TLS terminates here -- TASK-0035A)"
fi
if ! $WCL_COMPOSE ps -a db --format '{{.State}}' 2>/dev/null | grep -q '^running$'; then
    unknown "db container is not running"
fi

CERT="$OVERRIDE_CERT"
KEY="$OVERRIDE_KEY"
CAFILE="$OVERRIDE_CA"
BIND_PORT=""
DOMAIN=""
EXT_ADDR=""
SIGNALING_PROTOCOL=""

# TASK-0035A: require an enabled ws/wss signaling transport, but do NOT
# treat its Asterisk-side cert_file as the public WSS certificate when
# reverse-proxy termination is in use (the supported model).
ROW="$(wcl_wss_transport_row)"
if [ -z "$ROW" ]; then
    unknown "no enabled ws/wss pjsip_transports row -- WSS signaling is not configured/enabled"
fi
IFS=$'\x1f' read -r _ROW_ID SIGNALING_PROTOCOL _ROW_BIND_ADDR _ROW_BIND_PORT _ROW_DOMAIN _ROW_EXT_ADDR _ROW_CERT _ROW_KEY _ROW_CA <<< "$ROW"
BIND_PORT="$_ROW_BIND_PORT"
DOMAIN="$_ROW_DOMAIN"
EXT_ADDR="$_ROW_EXT_ADDR"

# Public cert ownership (proxy). Env overrides match docker/entrypoint.sh.
DEFAULT_PUBLIC_CERT="${PUBLIC_WSS_CERT_FILE:-/etc/senma/certs/public-wss.crt}"
DEFAULT_PUBLIC_KEY="${PUBLIC_WSS_KEY_FILE:-/etc/senma/certs/public-wss.key}"
if [ -z "$CERT" ]; then CERT="$DEFAULT_PUBLIC_CERT"; fi
if [ -z "$KEY" ]; then KEY="$DEFAULT_PUBLIC_KEY"; fi
if [ -z "$CAFILE" ]; then CAFILE="$_ROW_CA"; fi

HOSTNAME_VALUE="$(wcl_public_hostname "$OVERRIDE_HOSTNAME" "$EXT_ADDR" "$DOMAIN")"

echo "CERT_PATH: $CERT"
echo "KEY_PATH: $KEY"
echo "CA_LIST_FILE: ${CAFILE:-(none configured)}"
echo "HOSTNAME: ${HOSTNAME_VALUE:-(not configured)}"
echo "SIGNALING_TRANSPORT: id=${_ROW_ID} protocol=${SIGNALING_PROTOCOL:-?} bind=${_ROW_BIND_ADDR}:${BIND_PORT}"
TLS_MODE="${TLS_TERMINATION_MODE:-senma}"
echo "TLS_TERMINATION_MODE: $TLS_MODE"
if [ "$TLS_MODE" = "external" ]; then
    echo "TERMINATION_MODEL: external (public TLS at external proxy/NPM; SENMA HTTP backend + /asterisk/ws -> private WS)"
else
    echo "TERMINATION_MODEL: reverse-proxy (public TLS at app:443 /asterisk/ws -> private Asterisk WS)"
fi
echo "ASTERISK_CERT_FILE_REF: ${_ROW_CERT:-(none -- expected for private WS)}"

# TASK-0035E2: external TLS termination — public certificate belongs to
# NPM/proxy, not SENMA's local fixture. Pilot acceptance evaluates the
# public endpoint (WSS_PUBLIC_HOSTNAME:443) and must not fail solely
# because the local DEV fixture still exists on the HTTP backend host.
if [ "$TLS_MODE" = "external" ] && [ "$PILOT" = "1" ]; then
    if [ -z "$HOSTNAME_VALUE" ]; then
        echo "TRUST_STATE: UNKNOWN"
        echo "PILOT_ACCEPTANCE: NOT_ACCEPTABLE_FOR_PILOT (external TLS mode requires WSS_PUBLIC_HOSTNAME)"
        exit 1
    fi
    EXT_CONNECT="${OVERRIDE_CONNECT:-${HOSTNAME_VALUE}:443}"
    EXT_SNI="${OVERRIDE_SNI:-$HOSTNAME_VALUE}"
    echo "EXTERNAL_RUNTIME_ENDPOINT: $EXT_CONNECT (SNI=$EXT_SNI)"
    EXT_FP=""
    EXT_SUBJECT=""
    if EXT_PEM="$(echo | timeout 8 openssl s_client -connect "$EXT_CONNECT" -servername "$EXT_SNI" 2>/dev/null | openssl x509 2>/dev/null)"; then
        EXT_FP="$(printf '%s\n' "$EXT_PEM" | openssl x509 -noout -fingerprint -sha256 2>/dev/null | sed 's/^.*=//')"
        EXT_SUBJECT="$(printf '%s\n' "$EXT_PEM" | openssl x509 -noout -subject 2>/dev/null)"
        EXT_SANS="$(printf '%s\n' "$EXT_PEM" | openssl x509 -noout -ext subjectAltName 2>/dev/null | tr '\n' ' ')"
        echo "EXTERNAL_SUBJECT: $EXT_SUBJECT"
        echo "EXTERNAL_FINGERPRINT_SHA256: $EXT_FP"
        if printf '%s' "$EXT_SUBJECT$EXT_SANS" | grep -qi "$HOSTNAME_VALUE"; then
            EXT_HOST_MATCH="yes"
        else
            EXT_HOST_MATCH="no"
        fi
        echo "EXTERNAL_HOSTNAME_MATCH: $EXT_HOST_MATCH"
        if printf '%s' "$EXT_SUBJECT" | grep -qi 'senma-public-wss-dev'; then
            echo "TRUST_STATE: SELF_SIGNED"
            echo "PILOT_ACCEPTANCE: NOT_ACCEPTABLE_FOR_PILOT (public endpoint still presents SENMA local fixture — external terminator misconfigured)"
            exit 1
        fi
        if [ "$EXT_HOST_MATCH" != "yes" ]; then
            echo "TRUST_STATE: HOSTNAME_MISMATCH"
            echo "PILOT_ACCEPTANCE: NOT_ACCEPTABLE_FOR_PILOT (public certificate does not cover WSS_PUBLIC_HOSTNAME)"
            exit 1
        fi
        # Local fixture presence is informational only in external mode.
        echo "LOCAL_FIXTURE_NOTE: ignored for pilot acceptance under TLS_TERMINATION_MODE=external"
        echo "TRUST_STATE: TRUSTED (external terminator)"
        echo "PILOT_ACCEPTANCE: PILOT_ACCEPTABLE"
        exit 0
    else
        echo "TRUST_STATE: RUNTIME_UNREACHABLE"
        echo "PILOT_ACCEPTANCE: NOT_ACCEPTABLE_FOR_PILOT (could not fetch public certificate at $EXT_CONNECT)"
        exit 1
    fi
fi

# --- Existence / permissions -------------------------------------------

CERT_EXISTS="no"; KEY_EXISTS="no"
wcl_file_exists "$CERT" && CERT_EXISTS="yes"
wcl_file_exists "$KEY" && KEY_EXISTS="yes"
echo "CERT_EXISTS: $CERT_EXISTS"
echo "KEY_EXISTS: $KEY_EXISTS"

if [ "$CERT_EXISTS" != "yes" ] || [ "$KEY_EXISTS" != "yes" ]; then
    echo "TRUST_STATE: MISSING"
    if [ "$PILOT" = "1" ]; then
        echo "PILOT_ACCEPTANCE: NOT_ACCEPTABLE_FOR_PILOT (certificate or key file missing)"
        exit 1
    fi
    echo "PILOT_ACCEPTANCE: NOT_EVALUATED (pass --pilot to evaluate)"
    exit 1
fi

KEY_MODE="$(wcl_file_mode "$KEY")"
KEY_MODE_SAFE="no"
case "$KEY_MODE" in
    600|400) KEY_MODE_SAFE="yes" ;;
esac
echo "KEY_MODE: ${KEY_MODE:-unknown}"
echo "KEY_MODE_SAFE: $KEY_MODE_SAFE"

# --- Parse / metadata ----------------------------------------------------

if ! wcl_cert_parses "$CERT"; then
    echo "TRUST_STATE: UNREADABLE"
    if [ "$PILOT" = "1" ]; then
        echo "PILOT_ACCEPTANCE: NOT_ACCEPTABLE_FOR_PILOT (certificate does not parse as valid X.509)"
        exit 1
    fi
    echo "PILOT_ACCEPTANCE: NOT_EVALUATED (pass --pilot to evaluate)"
    exit 1
fi

SUBJECT="$(wcl_cert_field_subject "$CERT")"
ISSUER="$(wcl_cert_field_issuer "$CERT")"
NOT_BEFORE="$(wcl_cert_field_notbefore "$CERT")"
NOT_AFTER="$(wcl_cert_field_notafter "$CERT")"
CONFIGURED_FP="$(wcl_cert_field_fingerprint "$CERT")"
SANS="$(wcl_cert_sans "$CERT")"

echo "SUBJECT: $SUBJECT"
echo "ISSUER: $ISSUER"
echo "SAN: ${SANS:-(none)}"
echo "NOT_BEFORE: $NOT_BEFORE"
echo "NOT_AFTER: $NOT_AFTER"
echo "CONFIGURED_FINGERPRINT_SHA256: $CONFIGURED_FP"

# --- Pair match (Phase 8) -- public-key hash comparison only ------------

CERT_PUBHASH="$(wcl_cert_pubkey_hash "$CERT")"; CERT_PUBHASH_RC=$?
KEY_PUBHASH="$(wcl_key_pubkey_hash "$KEY")"; KEY_PUBHASH_RC=$?

if [ $CERT_PUBHASH_RC -ne 0 ] || [ $KEY_PUBHASH_RC -ne 0 ]; then
    PAIR_MATCH="unknown"
elif [ "$CERT_PUBHASH" = "$KEY_PUBHASH" ]; then
    PAIR_MATCH="yes"
else
    PAIR_MATCH="no"
fi
echo "PAIR_MATCH: $PAIR_MATCH"

# --- Validity window (Phase 10) -----------------------------------------

VALIDITY="valid"
if wcl_cert_not_yet_valid "$CERT"; then
    VALIDITY="NOT_YET_VALID"
elif wcl_cert_expired "$CERT"; then
    VALIDITY="EXPIRED"
elif wcl_cert_expiring_soon "$CERT" "$WARN_DAYS"; then
    VALIDITY="EXPIRING_SOON"
fi
echo "VALIDITY: $VALIDITY"

# --- SAN/hostname validation (Phase 9) -- SAN first, CN fallback --------

HOSTNAME_MATCH="SKIPPED (no hostname configured)"
if [ -n "$HOSTNAME_VALUE" ]; then
    if [ -n "$SANS" ]; then
        case ",${SANS}," in
            *",DNS:${HOSTNAME_VALUE},"*|*",IP Address:${HOSTNAME_VALUE},"*|*",IP:${HOSTNAME_VALUE},"*)
                HOSTNAME_MATCH="yes"
                ;;
            *)
                HOSTNAME_MATCH="no"
                ;;
        esac
    else
        # CN fallback only when no SAN extension exists at all (Phase 9's
        # explicit compatibility allowance -- modern clients ignore CN
        # entirely when a SAN extension is present, so this branch never
        # runs for any certificate that has one).
        case "$SUBJECT" in
            *"CN=${HOSTNAME_VALUE}"*|*"CN = ${HOSTNAME_VALUE}"*) HOSTNAME_MATCH="yes (CN fallback -- no SAN extension present)" ;;
            *) HOSTNAME_MATCH="no (CN fallback -- no SAN extension present)" ;;
        esac
    fi
fi
echo "HOSTNAME_MATCH: $HOSTNAME_MATCH"

# --- Fixture classification (Phase 16) ----------------------------------

FIXTURE="no"
FIXTURE_REASON=""
if FIXTURE_REASON="$(wcl_is_fixture_certificate "$CERT" "$SUBJECT")"; then
    FIXTURE="yes"
fi
echo "FIXTURE: $FIXTURE${FIXTURE_REASON:+ ($FIXTURE_REASON)}"

# --- Chain-of-trust (Phase 6/11) -----------------------------------------

SELF_SIGNED="no"
wcl_is_self_signed "$SUBJECT" "$ISSUER" && SELF_SIGNED="yes"
CA_VERIFIED="no"
if [ "$SELF_SIGNED" != "yes" ] && wcl_cert_verifies_against_ca "$CERT" "$CAFILE"; then
    CA_VERIFIED="yes"
fi
echo "SELF_SIGNED: $SELF_SIGNED"
echo "CA_VERIFIED: $CA_VERIFIED${CAFILE:+ (against configured ca_list_file)}"

# --- Runtime verification (Phase 11 -- mandatory) -----------------------

RUNTIME_MATCH="SKIPPED"
RUNTIME_FP=""
CHAIN_DEPTH="0"
if [ "$NO_RUNTIME" != "1" ]; then
    # Default: peek the public proxy listener from inside app (loopback
    # :443). --connect switches to a host-side peek of an external URL.
    if [ -n "$OVERRIDE_CONNECT" ]; then
        CONNECT="$OVERRIDE_CONNECT"
        VIA="via-host"
    else
        CONNECT="127.0.0.1:443"
        VIA="via-app"
    fi
    SNI="${OVERRIDE_SNI:-${HOSTNAME_VALUE:-localhost}}"
    PEEK="$(wcl_runtime_peek "$CONNECT" "$SNI" "$VIA")"
    IFS=$'\t' read -r RUNTIME_FP CHAIN_DEPTH RUNTIME_STATUS <<< "$PEEK"
    echo "RUNTIME_ENDPOINT: $CONNECT (SNI=$SNI)"
    if [ "$RUNTIME_STATUS" != "OK" ]; then
        RUNTIME_MATCH="UNREACHABLE"
    elif [ "$RUNTIME_FP" = "$CONFIGURED_FP" ]; then
        RUNTIME_MATCH="MATCH"
    else
        RUNTIME_MATCH="RUNTIME_MISMATCH"
    fi
fi
echo "RUNTIME_FINGERPRINT_SHA256: ${RUNTIME_FP:-(not checked)}"
echo "CHAIN_DEPTH: $CHAIN_DEPTH"
echo "RUNTIME_MATCH: $RUNTIME_MATCH"

# --- Overall TRUST_STATE (Phase 5) -- most severe first, never collapsed
#     into a single generic ERROR ----------------------------------------

TRUST_STATE="UNKNOWN"
if [ "$PAIR_MATCH" = "no" ]; then
    TRUST_STATE="PAIR_MISMATCH"
elif [ "$VALIDITY" = "NOT_YET_VALID" ]; then
    TRUST_STATE="NOT_YET_VALID"
elif [ "$VALIDITY" = "EXPIRED" ]; then
    TRUST_STATE="EXPIRED"
elif [ "$HOSTNAME_MATCH" = "no" ] || [[ "$HOSTNAME_MATCH" == no\ * ]]; then
    TRUST_STATE="HOSTNAME_MISMATCH"
elif [ "$RUNTIME_MATCH" = "RUNTIME_MISMATCH" ]; then
    TRUST_STATE="RUNTIME_MISMATCH"
elif [ "$RUNTIME_MATCH" = "UNREACHABLE" ]; then
    TRUST_STATE="RUNTIME_UNREACHABLE"
elif [ "$SELF_SIGNED" = "yes" ]; then
    TRUST_STATE="SELF_SIGNED"
elif [ "$CA_VERIFIED" = "yes" ]; then
    TRUST_STATE="TRUSTED"
else
    TRUST_STATE="UNKNOWN"
fi
if [ "$VALIDITY" = "EXPIRING_SOON" ] && [[ "$TRUST_STATE" =~ ^(TRUSTED|SELF_SIGNED)$ ]]; then
    TRUST_STATE="${TRUST_STATE} (EXPIRING_SOON)"
fi
echo "TRUST_STATE: $TRUST_STATE"

# --- Pilot acceptance (Phase 6/42) ---------------------------------------

if [ "$PILOT" != "1" ]; then
    echo "PILOT_ACCEPTANCE: NOT_EVALUATED (pass --pilot to evaluate)"
    case "$TRUST_STATE" in
        TRUSTED*) exit 0 ;;
        SELF_SIGNED*) exit 0 ;;
        *) exit 1 ;;
    esac
fi

REASONS=()
[ "$PAIR_MATCH" != "yes" ] && REASONS+=("certificate/key pair does not match")
[ "$VALIDITY" != "valid" ] && [ "$VALIDITY" != "EXPIRING_SOON" ] && REASONS+=("certificate is not currently valid ($VALIDITY)")
[ -z "$HOSTNAME_VALUE" ] && REASONS+=("no public WSS hostname configured (set WSS_PUBLIC_HOSTNAME)")
[ -n "$HOSTNAME_VALUE" ] && { [ "$HOSTNAME_MATCH" = "no" ] || [[ "$HOSTNAME_MATCH" == no\ * ]]; } && REASONS+=("certificate does not cover the configured hostname")
[ "$RUNTIME_MATCH" != "MATCH" ] && REASONS+=("live runtime does not confirm this certificate ($RUNTIME_MATCH)")
[ "$FIXTURE" = "yes" ] && REASONS+=("known fixture/test-only certificate")
[ "$KEY_MODE_SAFE" != "yes" ] && REASONS+=("private key permissions are not restrictive (mode ${KEY_MODE:-unknown}, expected 600/400)")

if [ "${#REASONS[@]}" -eq 0 ]; then
    echo "PILOT_ACCEPTANCE: PILOT_ACCEPTABLE"
    exit 0
else
    JOINED=""
    for r in "${REASONS[@]}"; do
        JOINED="${JOINED:+$JOINED; }$r"
    done
    printf 'PILOT_ACCEPTANCE: NOT_ACCEPTABLE_FOR_PILOT (%s)\n' "$JOINED"
    exit 1
fi
