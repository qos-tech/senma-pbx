#!/bin/bash
# TASK-0034I-R6: Recording report URL + timezone/date resolution smoke.
#
# Proves:
#   A. Root deployment URL is /arquivos/... (never /index.php/arquivos/...)
#   B. Front-controller getBaseUrl() may be /index.php but static URLs strip it
#   C. Direct WAV URL returns 200 + audio/x-wav + RIFF signature
#   D. Download href uses the same static URL; basename stays *.wav
#   E. Same-day case (calldate UTC hour vs local filename) resolves
#   F. Midnight-crossing case (local date != UTC CDR date) resolves via
#      userfield YYYYMMDD and/or UTC→system-TZ conversion
#   G. Historical fallback: userfield without date token still uses calldate
#   H. storage_* subdirectory lookup
#   I. Conference-room directory lookup (901-915)
#
# See docs/tasks/0034i-r6-recording-report-url-timezone-resolution.md.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"
harness_install_traps

BASE_URL="${SMOKE_BASE_URL:-http://127.0.0.1:${SENMA_HTTP_PORT:-${MAG_HTTP_PORT:-8080}}}"
COMPOSE="${SMOKE_COMPOSE:-docker compose}"
ADMIN_USER=admin
ADMIN_PASSWORD="SmokeTest123!"
ARQ_ROOT="/var/www/html/snep/arquivos"
PROBE_IN_APP="/tmp/r6-recording-report-probe.php"

TMPDIR_R6="$(mktemp -d)"
harness_register_best_effort_cleanup "temp working dir" "rm -rf '$TMPDIR_R6'"
JAR="$TMPDIR_R6/admin.cookies"
BODY="$TMPDIR_R6/body"
HEADERS="$TMPDIR_R6/headers"

UF_SAME="r6_1789754744_20260918_1505_1001_1002"
UF_MIDNIGHT="r6_midnight_20260918_2230_1001_1002"
UF_HIST="r6_historical_nodedate_token"
UF_STORAGE="r6_storage_only_fixture_0034ir6"
# conference[3] must be 901-915 (legacy explode("_") contract).
UF_CONF="r6_20260918_1200_901_1001"
STORAGE_DIR="storage_r6test"
DATE_LOCAL="2026-09-18"

cleanup_fixtures() {
    $COMPOSE exec -T -u www-data app sh -c "
        rm -f '${ARQ_ROOT}/${DATE_LOCAL}/${UF_SAME}.wav' \
              '${ARQ_ROOT}/${DATE_LOCAL}/${UF_MIDNIGHT}.wav' \
              '${ARQ_ROOT}/${DATE_LOCAL}/${UF_HIST}.wav' \
              '${ARQ_ROOT}/${STORAGE_DIR}/${DATE_LOCAL}/${UF_STORAGE}.wav' \
              '${ARQ_ROOT}/901/${UF_CONF}.wav' 2>/dev/null || true
        rm -rf '${ARQ_ROOT}/storage_r6' '${ARQ_ROOT}/${STORAGE_DIR}' 2>/dev/null || true
        rmdir '${ARQ_ROOT}/901' 2>/dev/null || true
        rm -f '${PROBE_IN_APP}' 2>/dev/null || true
    " >/dev/null 2>&1 || true
}
harness_register_cleanup "remove R6 recording fixtures" "cleanup_fixtures"

log() { harness_log "$@"; }

log "==> Preflight"
harness_require_containers app db asterisk || harness_blocked "required containers not running"

log "==> Creating owned recording fixtures"
$COMPOSE exec -T -u www-data app php -r '
function r6_write_wav($path) {
  $data = "RIFF" . pack("V", 36+1600) . "WAVEfmt " . pack("V", 16)
    . pack("v", 1) . pack("v", 1) . pack("V", 8000) . pack("V", 16000)
    . pack("v", 2) . pack("v", 16) . "data" . pack("V", 1600) . str_repeat("\0", 1600);
  $dir = dirname($path);
  if (!is_dir($dir) && !@mkdir($dir, 0770, true) && !is_dir($dir)) {
    fwrite(STDERR, "mkdir failed: $dir\n");
    exit(2);
  }
  if (file_put_contents($path, $data) === false) {
    fwrite(STDERR, "write failed: $path\n");
    exit(2);
  }
  echo "OK $path\n";
}
$r = "/var/www/html/snep/arquivos";
r6_write_wav($r . "/2026-09-18/r6_1789754744_20260918_1505_1001_1002.wav");
r6_write_wav($r . "/2026-09-18/r6_midnight_20260918_2230_1001_1002.wav");
r6_write_wav($r . "/2026-09-18/r6_historical_nodedate_token.wav");
r6_write_wav($r . "/storage_r6test/2026-09-18/r6_storage_only_fixture_0034ir6.wav");
r6_write_wav($r . "/901/r6_20260918_1200_901_1001.wav");
' > "$TMPDIR_R6/create.out" 2>"$TMPDIR_R6/create.err" || {
    harness_bad "create fixtures" "exit nonzero: $(head -c 300 "$TMPDIR_R6/create.err")"
    harness_complete
}
harness_ok "create fixtures" "$(tr '\n' ' ' < "$TMPDIR_R6/create.out" | head -c 200)"

# Install probe script inside the app container (bind-mounted /tmp is fine).
cat > "$TMPDIR_R6/probe.php" <<'PHP'
<?php
$_SERVER["SCRIPT_NAME"] = "/index.php";
$_SERVER["PHP_SELF"] = "/index.php";
$_SERVER["REQUEST_URI"] = "/index.php/default/calls-report";
$_SERVER["SCRIPT_FILENAME"] = "/var/www/html/snep/index.php";
$_SERVER["HTTP_HOST"] = "localhost";
$_SERVER["DOCUMENT_ROOT"] = "/var/www/html/snep";
$_SERVER["REQUEST_METHOD"] = "GET";
chdir("/var/www/html/snep");
set_include_path("/var/www/html/snep/lib" . PATH_SEPARATOR . get_include_path());
require_once "Zend/Controller/Request/Http.php";
require_once "Zend/Controller/Front.php";
require_once "Zend/Registry.php";
require_once "Snep/Config.php";
Snep_Config::setConfigFile("/var/www/html/snep/includes/setup.conf");
$config = Snep_Config::getConfig();
Zend_Registry::set("config", $config);
$req = new Zend_Controller_Request_Http();
$front = Zend_Controller_Front::getInstance();
$front->setRequest($req);
require_once "Zend/Config.php";
require_once "Snep/Manutencao.php";

$case = isset($argv[1]) ? $argv[1] : "resolve";
$calldate = isset($argv[2]) ? $argv[2] : "";
$userfield = isset($argv[3]) ? $argv[3] : "";

if ($case === "baseurl") {
    echo "GETBASEURL=" . $front->getBaseUrl() . "\n";
    echo "PUBLICBASE=" . Snep_Manutencao::publicAssetBaseUrl() . "\n";
    exit(0);
}
if ($case === "subdir") {
    // setup.conf Zend_Config is read-only; clone writable for path.web proof.
    $arr = $config->toArray();
    $arr["system"]["path"]["web"] = "/snep";
    $writable = new Zend_Config($arr, true);
    Zend_Registry::set("config", $writable);
    $url = Snep_Manutencao::arquivoExiste($calldate, $userfield);
    echo "URL=" . ($url === false ? "false" : $url) . "\n";
    exit(0);
}

$url = Snep_Manutencao::arquivoExiste($calldate, $userfield);
echo "GETBASEURL=" . $front->getBaseUrl() . "\n";
echo "URL=" . ($url === false ? "false" : $url) . "\n";
$cands = Snep_Manutencao::recordingDateCandidates($calldate, $userfield);
echo "CANDS=" . implode(",", $cands) . "\n";
PHP

docker cp "$TMPDIR_R6/probe.php" "$( $COMPOSE ps -q app | head -1 ):${PROBE_IN_APP}" >/dev/null

run_probe() {
    $COMPOSE exec -T app php -d display_errors=0 "$PROBE_IN_APP" "$@" 2>/dev/null
}

log "==> C/A: direct /arquivos WAV"
HDR="$TMPDIR_R6/wav.hdr"
curl -sS -D "$HDR" -o "$TMPDIR_R6/wav.bin" \
    "${BASE_URL}/arquivos/${DATE_LOCAL}/${UF_SAME}.wav" >/dev/null
code="$(awk 'NR==1{print $2}' "$HDR")"
ctype="$(grep -i '^Content-Type:' "$HDR" | head -1 | tr -d '\r')"
sig="$(od -An -tx1 -N4 "$TMPDIR_R6/wav.bin" | tr -d ' \n')"
if [ "$code" = "200" ] && echo "$ctype" | grep -qi 'audio/x-wav' && [ "$sig" = "52494646" ]; then
    harness_ok "direct /arquivos WAV" "HTTP $code $ctype RIFF"
else
    harness_bad "direct /arquivos WAV" "HTTP ${code:-?} ctype=${ctype:-?} sig=${sig:-?}"
fi

log "==> wrong front-controller path must NOT serve WAV"
curl -sS -D "$HDR" -o "$TMPDIR_R6/wrong.bin" \
    "${BASE_URL}/index.php/arquivos/${DATE_LOCAL}/${UF_SAME}.wav" >/dev/null
code="$(awk 'NR==1{print $2}' "$HDR")"
ctype="$(grep -i '^Content-Type:' "$HDR" | head -1 | tr -d '\r')"
sig="$(od -An -tx1 -N4 "$TMPDIR_R6/wrong.bin" 2>/dev/null | tr -d ' \n')"
if echo "$ctype" | grep -qi 'audio/x-wav' || [ "$sig" = "52494646" ]; then
    harness_bad "/index.php/arquivos must not be audio" "HTTP $code $ctype sig=$sig"
else
    harness_ok "/index.php/arquivos is not static audio" "HTTP $code $ctype (HTML/app, not WAV)"
fi

log "==> B: getBaseUrl under /index.php context"
BASE_OUT="$(run_probe baseurl)"
echo "$BASE_OUT" | grep -q 'GETBASEURL=/index.php' \
    && harness_ok "getBaseUrl is /index.php under FC" "$(echo "$BASE_OUT" | tr '\n' ' ')" \
    || harness_bad "getBaseUrl is /index.php under FC" "$BASE_OUT"

log "==> E: same-day UTC calldate + userfield local date"
SAME_OUT="$(run_probe resolve "2026-09-18 18:05:00" "$UF_SAME")"
SAME_URL="$(echo "$SAME_OUT" | sed -n 's/^URL=//p')"
if [ "$SAME_URL" = "/arquivos/${DATE_LOCAL}/${UF_SAME}.wav" ]; then
    harness_ok "same-day resolver URL" "$SAME_URL"
else
    harness_bad "same-day resolver URL" "got=$SAME_URL out=$SAME_OUT"
fi
echo "$SAME_URL" | grep -q 'index.php' \
    && harness_bad "same-day URL must not include index.php" "$SAME_URL" \
    || harness_ok "same-day URL has no index.php" "$SAME_URL"

log "==> F: midnight boundary (CDR UTC next day, file under local date)"
MID_OUT="$(run_probe resolve "2026-09-19 01:30:00" "$UF_MIDNIGHT")"
MID_URL="$(echo "$MID_OUT" | sed -n 's/^URL=//p')"
if [ "$MID_URL" = "/arquivos/${DATE_LOCAL}/${UF_MIDNIGHT}.wav" ]; then
    harness_ok "midnight-boundary resolver URL" "$MID_URL"
else
    harness_bad "midnight-boundary resolver URL" "got=$MID_URL out=$MID_OUT"
fi

log "==> G: historical fallback (no YYYYMMDD in userfield)"
HIST_OUT="$(run_probe resolve "2026-09-18 12:00:00" "$UF_HIST")"
HIST_URL="$(echo "$HIST_OUT" | sed -n 's/^URL=//p')"
if [ "$HIST_URL" = "/arquivos/${DATE_LOCAL}/${UF_HIST}.wav" ]; then
    harness_ok "historical calldate fallback" "$HIST_URL"
else
    harness_bad "historical calldate fallback" "got=$HIST_URL out=$HIST_OUT"
fi

log "==> H: storage subdirectory"
STOR_OUT="$(run_probe resolve "2026-09-18 12:00:00" "$UF_STORAGE")"
STOR_URL="$(echo "$STOR_OUT" | sed -n 's/^URL=//p')"
if [ "$STOR_URL" = "/arquivos/${STORAGE_DIR}/${DATE_LOCAL}/${UF_STORAGE}.wav" ]; then
    harness_ok "storage subdirectory lookup" "$STOR_URL"
else
    harness_bad "storage subdirectory lookup" "got=$STOR_URL out=$STOR_OUT"
fi

log "==> I: conference room directory"
CONF_OUT="$(run_probe resolve "2026-09-18 12:00:00" "$UF_CONF")"
CONF_URL="$(echo "$CONF_OUT" | sed -n 's/^URL=//p')"
if [ "$CONF_URL" = "/arquivos/901/${UF_CONF}.wav" ]; then
    harness_ok "conference directory lookup" "$CONF_URL"
else
    harness_bad "conference directory lookup" "got=$CONF_URL out=$CONF_OUT"
fi

log "==> A (subdir): path.web=/snep prefixes /snep/arquivos"
SUB_OUT="$(run_probe subdir "2026-09-18 18:05:00" "$UF_SAME")"
SUB_URL="$(echo "$SUB_OUT" | sed -n 's/^URL=//p')"
if [ "$SUB_URL" = "/snep/arquivos/${DATE_LOCAL}/${UF_SAME}.wav" ]; then
    harness_ok "subdirectory deployment URL" "$SUB_URL"
else
    harness_bad "subdirectory deployment URL" "got=$SUB_URL out=$SUB_OUT"
fi

log "==> D: calls-report analytic HTML uses /arquivos"
curl -sS -c "$JAR" -b "$JAR" -o /dev/null \
    -d "user=${ADMIN_USER}&password=${ADMIN_PASSWORD}" \
    "${BASE_URL}/index.php/auth/login" || true

UNIQUEID="r6.$(date +%s).1"
$COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
    "${DB_NAME:-snep}" -e "
INSERT INTO cdr (calldate, clid, src, dst, dcontext, channel, dstchannel, lastapp, lastdata,
  duration, billsec, disposition, amaflags, accountcode, uniqueid, userfield)
VALUES ('2026-09-18 18:05:00', 'R6 <1001>', '1001', '1002', 'default', 'PJSIP/1001', 'PJSIP/1002',
  'Dial', 'PJSIP/1002', 10, 8, 'ANSWERED', 3, '', '${UNIQUEID}', '${UF_SAME}');
" >/dev/null 2>&1 || true
harness_register_cleanup "remove R6 CDR fixture" \
    "$COMPOSE exec -T db mariadb -u\"\${DB_USER:-snep}\" -p\"\${DB_PASSWORD:-change-me-for-local-development}\" \"\${DB_NAME:-snep}\" -e \"DELETE FROM cdr WHERE uniqueid='${UNIQUEID}' OR userfield LIKE 'r6_%';\" >/dev/null 2>&1 || true"

curl -sS -c "$JAR" -b "$JAR" -o "$BODY" "${BASE_URL}/index.php/default/calls-report" >/dev/null
CSRF="$(grep -o 'name="csrf-token" content="[^"]*"' "$BODY" 2>/dev/null | head -1 | sed 's/.*content="//;s/"$//')"
if [ -z "$CSRF" ]; then
    CSRF="$(grep -oE 'name="snep_csrf_token"[^>]*value="[^"]+"|snep_csrf_token" value="[^"]+"' "$BODY" 2>/dev/null | head -1 | sed 's/.*value="//;s/"$//')"
fi

# Period format: "dd/mm/yyyy HH:MM - dd/mm/yyyy HH:MM" (single field).
curl -sS -c "$JAR" -b "$JAR" -o "$BODY" -w '%{http_code}' \
    --data-urlencode "report_type=analytic" \
    --data-urlencode "period=18/09/2026 00:00 - 18/09/2026 23:59" \
    --data-urlencode "selectSrc=0" --data-urlencode "order_src=equal" \
    --data-urlencode "groupSrc=" \
    --data-urlencode "selectDst=0" --data-urlencode "order_dst=equal" \
    --data-urlencode "groupDst=" \
    --data-urlencode "duration_init=" --data-urlencode "duration_end=" \
    --data-urlencode "ANSWERED=on" --data-urlencode "NOANSWER=on" \
    --data-urlencode "BUSY=on" --data-urlencode "FAILED=on" \
    --data-urlencode "record=on" \
    --data-urlencode "snep_csrf_token=${CSRF}" \
    "${BASE_URL}/index.php/default/calls-report" > "$TMPDIR_R6/httpcode" || true

REPORT_CODE="$(cat "$TMPDIR_R6/httpcode")"

if [ "$REPORT_CODE" = "200" ]; then
    harness_ok "calls-report analytic HTTP 200" "HTTP $REPORT_CODE"
else
    harness_bad "calls-report analytic HTTP 200" "HTTP $REPORT_CODE body=$(head -c 180 "$BODY")"
fi

if grep -q 'index.php/arquivos' "$BODY"; then
    harness_bad "no /index.php/arquivos in report HTML" "found index.php/arquivos"
else
    harness_ok "no /index.php/arquivos in report HTML" "clean"
fi

if grep -qE "src=['\"]/arquivos/${DATE_LOCAL}/${UF_SAME}\\.wav['\"]" "$BODY"; then
    harness_ok "report audio src is /arquivos/..." "present"
else
    harness_bad "report audio src is /arquivos/..." "missing snippet=$(grep -oE '.{0,30}'"${UF_SAME}"'.{0,60}' "$BODY" | head -1)"
fi

if grep -qE "href=['\"]/arquivos/${DATE_LOCAL}/${UF_SAME}\\.wav['\"]" "$BODY"; then
    harness_ok "report download href is /arquivos/..." "present"
else
    harness_bad "report download href is /arquivos/..." "missing"
fi

if grep -qE "download=['\"]${UF_SAME}\\.wav['\"]" "$BODY"; then
    harness_ok "report download basename attribute" "${UF_SAME}.wav"
else
    harness_bad "report download basename attribute" "missing"
fi

curl -sS -D "$HDR" -o "$TMPDIR_R6/dl.bin" \
    "${BASE_URL}/arquivos/${DATE_LOCAL}/${UF_SAME}.wav" >/dev/null
code="$(awk 'NR==1{print $2}' "$HDR")"
ctype="$(grep -i '^Content-Type:' "$HDR" | head -1 | tr -d '\r')"
if [ "$code" = "200" ] && echo "$ctype" | grep -qi 'audio/x-wav'; then
    harness_ok "download HTTP audio/x-wav" "HTTP $code $ctype"
else
    harness_bad "download HTTP audio/x-wav" "HTTP ${code:-?} $ctype"
fi

harness_complete
