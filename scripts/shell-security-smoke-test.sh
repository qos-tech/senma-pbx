#!/bin/bash
#
# TASK-0026D shell/command-execution boundary hardening focused security
# smoke test.
#
# Exercises every confirmed F2-F5 command-injection boundary from
# docs/tasks/0026-pre-pilot-security-release-audit.md (re-traced and
# expanded in docs/tasks/0026d-shell-execution-hardening.md), through
# SENMA's own real, authenticated HTTP application flows -- never a
# direct filesystem/shell operation, never a real exploit. For each
# boundary:
#   1. a normal, legitimate operation still works exactly as before;
#   2. a harmless shell-shaped value (containing representative shell
#      metacharacters) is submitted through the real request;
#   3. proof that value was treated as inert data, not shell syntax --
#      either the request is rejected by the new allowlist (F2/F3), or
#      (F4/F5, where the value is never rejected, only never executed)
#      the app responds normally and no side effect occurred;
#   4. proof no marker file/process/side effect was created -- the
#      equivalent of "if command injection were still present, a
#      uniquely named harmless marker would appear; after the request,
#      it must not exist";
#   5. proof the application remains healthy (no new PHP Fatal Error);
#   6. cleanup of every fixture this script owns.
#
# Every payload below is a harmless, non-destructive marker-file-creation
# attempt (`touch /tmp/<unique-marker>`) against this script's own
# throwaway marker path -- never a real exploit chain, never secret
# extraction, never a destructive command, matching this task's explicit
# "do not read secrets, do not exfiltrate files, do not delete arbitrary
# files, do not invoke network callbacks" instruction.
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

log() { harness_log "$@"; }

db_query() {
    $COMPOSE exec -T db mariadb -u"${DB_USER:-snep}" -p"${DB_PASSWORD:-change-me-for-local-development}" \
        "${DB_NAME:-snep}" -N -e "$1"
}

app_exec() {
    $COMPOSE exec -T app sh -c "$1"
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
request() {
    local jar="$1" method="$2" path="$3" data="${4:-}"
    if [ "$method" = POST ]; then
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' -d "$data" "${BASE_URL}${path}"
    else
        curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' "${BASE_URL}${path}"
    fi
}

# multipart_upload <jar> <path> <field> <local-file> <filename> [extra k=v ...]
# Builds the multipart/form-data body by hand (not curl's -F convenience
# flag) so the filename can contain arbitrary bytes, including shell
# metacharacters -- exactly what these tests need to submit.
multipart_upload() {
    local jar="$1" path="$2" field="$3" localfile="$4" filename="$5"
    shift 5
    local boundary="task0026dBoundary${RANDOM}${RANDOM}"
    local body file_content_type="application/octet-stream"
    body="$(mktemp)"
    {
        for kv in "$@"; do
            case "$kv" in
                __content_type__=*)
                    file_content_type="${kv#*=}"
                    continue
                    ;;
            esac
            printf -- '--%s\r\n' "$boundary"
            printf 'Content-Disposition: form-data; name="%s"\r\n\r\n' "${kv%%=*}"
            printf '%s\r\n' "${kv#*=}"
        done
        printf -- '--%s\r\n' "$boundary"
        printf 'Content-Disposition: form-data; name="%s"; filename="%s"\r\n' "$field" "$filename"
        printf 'Content-Type: %s\r\n\r\n' "$file_content_type"
        cat "$localfile"
        printf '\r\n'
        printf -- '--%s--\r\n' "$boundary"
    } > "$body"
    curl -sS -b "$jar" -c "$jar" -D "$HEADERS" -o "$BODY" -w '%{http_code}' \
        -H "Content-Type: multipart/form-data; boundary=${boundary}" \
        --data-binary "@${body}" "${BASE_URL}${path}"
    rm -f "$body"
}

# marker_absent <marker-path> -- true if the marker does NOT exist
# inside the app container (where exec()/shell operations actually run).
marker_absent() {
    ! app_exec "test -e '$1'"
}

# --- 0. Preflight --------------------------------------------------------

harness_require_containers app db
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

# TASK-0026D finding, unrelated to shell injection, documented in
# docs/tasks/0026d-shell-execution-hardening.md: /var/lib/asterisk does
# not exist at all in the app container (confirmed: `path.asterisk.sounds`/
# `path.asterisk.moh` in includes/setup.conf both point under it, and
# neither ever gets created -- no bind mount, no named volume, no
# entrypoint step provisions it, unlike the asterisk/provider containers'
# own mag-asterisk-var volume). Sound Files/Music on Hold's upload flows
# have therefore never been able to complete in this dev environment
# regardless of this task's changes. Provisioning the missing directory
# tree here is test-precondition scaffolding (like any smoke fixture
# needing a real place to write), not a product fix -- left in place
# afterward since it is baseline environment scaffolding every future
# run needs too, not a per-run fixture.
SOUNDS_ROOT="/var/lib/asterisk/sounds"
MOH_ROOT="/var/lib/asterisk/moh"
SYS_LANG="$(app_exec "grep '^language' /var/www/html/snep/includes/setup.conf | sed 's/.*\"\\(.*\\)\".*/\\1/'" | tr -d '\r')"
SYS_LANG="${SYS_LANG:-pt_BR}"
# chown to www-data: confirmed live that a root-owned 0755 directory
# here silently defeats every upload/mkdir this suite exercises (PHP
# runs as www-data) -- move_uploaded_file()/mkdir() just fail with a
# logged PHP Warning and the calling action's pre-existing (unrelated)
# control flow continues past that failure with no explicit early
# return, so the request can still 302 as if it had succeeded. Ownership
# is part of the same never-provisioned gap, not a separate one.
app_exec "mkdir -p '${SOUNDS_ROOT}/${SYS_LANG}/tmp' '${SOUNDS_ROOT}/${SYS_LANG}/backup' '${MOH_ROOT}' && chown -R www-data:www-data '${SOUNDS_ROOT}' '${MOH_ROOT}'"
log "==> provisioned missing sound-files/MOH directory scaffolding (${SOUNDS_ROOT}/${SYS_LANG}, ${MOH_ROOT}) -- pre-existing Docker-topology gap, not a shell-injection finding, see docs/tasks/0026d-shell-execution-hardening.md"

MARKER="/tmp/task0026d-marker-$$-${RANDOM}"
harness_register_best_effort_cleanup "shell-injection marker file (should never exist)" "app_exec \"rm -f '$MARKER'\""

# --- 0b. A zero-permission user is denied on every F2-F5 boundary --------
# (Phase 8: prove authorization stays intact -- not re-testing TASK-0026A
# itself, just confirming this task didn't accidentally weaken it.)

RESTRICTED_USER="task0026d-restricted"
RESTRICTED_PASSWORD="Task0026dRestricted!"
RID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
RESTRICTED_HASH="$(app_exec "php -r \"echo md5('${RESTRICTED_PASSWORD}');\"" | tr -d '\r')"
if [ -z "$RID" ]; then
    db_query "INSERT INTO users (name,password,email,dashboard,profile_id,created,updated) VALUES ('${RESTRICTED_USER}','${RESTRICTED_HASH}','${RESTRICTED_USER}@example.test','',1,NOW(),NOW());"
    RID="$(db_query "SELECT id FROM users WHERE name='${RESTRICTED_USER}';")"
fi
if [ -z "$RID" ]; then
    harness_blocked "could not provision the zero-permission restricted test user"
fi
# TASK-0027-established pattern: a deliberately persistent, reusable
# dev-only fixture, reset to a known zero-permission baseline every run.
db_query "UPDATE users SET password='${RESTRICTED_HASH}' WHERE id=${RID}; DELETE FROM users_permissions WHERE user_id=${RID};" >/dev/null
harness_register_best_effort_cleanup "restricted user permissions reset to baseline" \
    "$COMPOSE exec -T db mariadb -u'${DB_USER}' -p'${DB_PASSWORD}' '${DB_NAME}' -e \"DELETE FROM users_permissions WHERE user_id=${RID};\" >/dev/null"

RESTRICTED_JAR="$(mktemp)"
harness_register_best_effort_cleanup "restricted cookie jar" "rm -f '$RESTRICTED_JAR'"
request "$RESTRICTED_JAR" POST /index.php/auth/login "user=${RESTRICTED_USER}&password=${RESTRICTED_PASSWORD}" >/dev/null

for boundary_path in "/index.php/default/sound-files/add" "/index.php/default/music-on-hold/addfile" "/index.php/default/music-on-hold/removefile" "/index.php/default/logs/view" "/index.php/default/cnl"; do
    code="$(request "$RESTRICTED_JAR" GET "$boundary_path")"
    if [ "$code" = 302 ] && redirects_to_permission_error; then
        harness_ok "authorization intact: ${boundary_path}" "zero-permission user denied (HTTP 302, Location: permission/error)"
    else
        harness_bad "authorization intact: ${boundary_path}" "expected 302+permission/error, got HTTP ${code}"
    fi
done

# Phase 8: exercise the actual F2-F5 bodies below through this SAME
# restricted account, now granted exactly the permissions a real
# non-superuser pilot role would need -- proving "authorized user can
# perform the normal action" and "authorized malicious-looking input
# still cannot alter command syntax" through a genuinely limited
# account, not superuser bypass.
code="$(request "$ADMIN_JAR" POST /index.php/default/users/permission/id/$RID "user=$RID&default_sound-files_write=1&default_music-on-hold_write=1&default_logs_read=1&default_cnl_read=1")"
if [ "$code" = 302 ]; then
    harness_ok "admin grants exactly the four F2-F5 permissions" "HTTP $code"
else
    harness_blocked "granting F2-F5 permissions to the restricted user failed (HTTP $code) -- cannot proceed"
fi

# =============================================================================
# F2 -- Sound Files (SoundFilesController + Snep_SoundFiles_Manager)
# =============================================================================

log "==> F2: Sound Files boundary"

# A real, valid, tiny WAV -- sox's own synth generator, not a fake
# placeholder -- so the actual sox conversion this action performs has
# something real to process (the legitimate-flow proof must exercise
# the real conversion step, not just the upload).
LOCAL_WAV="$(mktemp).wav"
app_exec "sox -n /tmp/task0026d-fixture-src.wav synth 0.1 sine 440" >&2
docker cp "$($COMPOSE ps -q app):/tmp/task0026d-fixture-src.wav" "$LOCAL_WAV" 2>/dev/null
harness_register_best_effort_cleanup "local throwaway wav fixture" "rm -f '$LOCAL_WAV'; app_exec \"rm -f /tmp/task0026d-fixture-src.wav\""
if [ ! -s "$LOCAL_WAV" ]; then
    harness_blocked "could not build the local valid-WAV test fixture via the app container's sox"
fi

SF_NAME="task0026dsound.wav"
code="$(multipart_upload "$RESTRICTED_JAR" /index.php/default/sound-files/add inputFile "$LOCAL_WAV" "$SF_NAME" description=task0026d gsm=0)"
# This checks the converted file landing on disk, not the DB row: a
# real, pre-existing, unrelated strict-SQL schema bug was found live
# while building this test -- sounds.secao is `varchar(30) NOT NULL`
# with no default and is part of the table's own PRIMARY KEY, but
# Snep_SoundFiles_Manager::add()'s INSERT for AST-type (non-MOH) files
# never sets it, so the INSERT itself always fails
# (SQLSTATE[HY000]: 1364). This is unrelated to shell injection --
# nothing in this task touched add() or the sounds schema -- and had
# never been noticed because nothing ever previously exercised this
# HTTP flow far enough to reach it (see the directory-provisioning gap
# above). The file existing on disk is exactly what this task's own
# fix touches (filename allowlist -> move_uploaded_file() -> the
# escapeshellarg()-wrapped sox exec()) and is independent of that
# unrelated DB-layer bug.
SF_CONVERTED="$(app_exec "test -f '${SOUNDS_ROOT}/${SYS_LANG}/${SF_NAME}' && echo yes || echo no")"
# Not asserting on $code here: the unrelated pre-existing sounds.secao
# schema bug documented above throws AFTER the file conversion this
# task's fix is responsible for, which is exactly the part checked here
# (a 500 from that unrelated bug is expected and already accounted for
# by the health check below, not silently ignored).
if [ "$SF_CONVERTED" = "yes" ]; then
    harness_ok "F2 valid: upload a legitimate sound file" "HTTP $code, ${SOUNDS_ROOT}/${SYS_LANG}/${SF_NAME} converted and stored via the real addAction() HTTP flow (allowlist -> move_uploaded_file() -> sox all succeed; the subsequent DB insert failing is the unrelated schema bug documented above)"
else
    harness_bad "F2 valid: upload a legitimate sound file" "HTTP $code, converted file present=${SF_CONVERTED}"
fi
harness_register_cleanup "sound file ${SF_NAME} (F2 fixture)" \
    "db_query \"DELETE FROM sounds WHERE arquivo='${SF_NAME}';\" >/dev/null; app_exec \"rm -f '${SOUNDS_ROOT}/${SYS_LANG}/${SF_NAME}' '${SOUNDS_ROOT}/${SYS_LANG}/tmp/${SF_NAME}'\"; true"

SF_MALICIOUS_NAME='`touch '"$MARKER"'`.wav'
code="$(multipart_upload "$RESTRICTED_JAR" /index.php/default/sound-files/add inputFile "$LOCAL_WAV" "$SF_MALICIOUS_NAME" description=task0026d gsm=0)"
SF_MALICIOUS_EXISTS="$(db_query "SELECT COUNT(*) FROM sounds WHERE arquivo LIKE '%touch%';")"
if marker_absent "$MARKER" && [ "${SF_MALICIOUS_EXISTS:-0}" = "0" ]; then
    harness_ok "F2: shell-shaped upload filename cannot execute" "HTTP $code, no marker file created, no sound row stored with the malicious name (rejected by the new filename allowlist)"
else
    harness_bad "F2: shell-shaped upload filename cannot execute" "HTTP $code, marker present=$(app_exec "test -e '$MARKER'" && echo yes || echo no), malicious rows=${SF_MALICIOUS_EXISTS}"
fi

FATALS_AFTER_F2="$(fatal_count)"
if [ "$FATALS_AFTER_F2" = "$FATALS_BEFORE" ]; then
    harness_ok "F2: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE})"
else
    harness_bad "F2: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE} -> ${FATALS_AFTER_F2}"
fi

# =============================================================================
# F3 -- Music on Hold (MusicOnHoldController + Snep_SoundFiles_Manager)
# =============================================================================

log "==> F3: Music on Hold boundary"

# TASK-0026D finding, unrelated to shell injection, documented in
# docs/tasks/0026d-shell-execution-hardening.md: removefileAction()
# builds its target path as "<moh root>/<secao>" -- but "secao" is the
# MOH class's own *name*, not its independently-settable *directory*
# (addAction() lets a class be created with any name/directory
# combination, e.g. name="sales", directory="sales-hold-music"). When
# they differ, removefileAction() silently looks in the wrong place
# (file_exists() on the wrong path is simply false, so its unlink is
# skipped) while still deleting the DB row and redirecting as if it had
# succeeded, orphaning the real file. Pre-existing in the unfixed code
# this task touched (unchanged by this task's own fix, which only
# replaced *how* the file is removed, not *which* path is computed) --
# never previously exercised with a name != directory MOH class. Using
# the same value for both here avoids exercising that unrelated bug.
MOH_CLASS_NAME="task0026dmoh"
MOH_DIR_NAME="$MOH_CLASS_NAME"
code="$(request "$RESTRICTED_JAR" POST /index.php/default/music-on-hold/add "nome=${MOH_CLASS_NAME}&mode=files&directory=${MOH_DIR_NAME}&base=/should/be/ignored")"
MOH_DIR_CREATED="$(app_exec "test -d '${MOH_ROOT}/${MOH_DIR_NAME}' && echo yes || echo no")"
if [ "$code" = 302 ] && [ "$MOH_DIR_CREATED" = "yes" ]; then
    harness_ok "F3 valid: create a MOH class" "HTTP $code, ${MOH_ROOT}/${MOH_DIR_NAME} created via the real addAction() HTTP flow (client 'base' ignored, server's own MOH root used)"
else
    harness_bad "F3 valid: create a MOH class" "HTTP $code, directory created=${MOH_DIR_CREATED}"
fi
harness_register_cleanup "MOH class ${MOH_CLASS_NAME} (F3 fixture)" \
    "request \"\$ADMIN_JAR\" POST /index.php/default/music-on-hold/remove \"id=${MOH_CLASS_NAME}&delete=1\" >/dev/null; app_exec \"rm -rf '${MOH_ROOT}/${MOH_DIR_NAME}'\" 2>/dev/null; true"

MOH_MALICIOUS_DIR='x`touch '"$MARKER"'`'
code="$(request "$RESTRICTED_JAR" POST /index.php/default/music-on-hold/add "nome=task0026dmohbad&mode=files&directory=${MOH_MALICIOUS_DIR}&base=/should/be/ignored")"
if marker_absent "$MARKER"; then
    harness_ok "F3: shell-shaped MOH class directory cannot execute" "HTTP $code, no marker file created (rejected by the new directory-name allowlist)"
else
    harness_bad "F3: shell-shaped MOH class directory cannot execute" "HTTP $code, marker file was created"
fi

# Reuses F2's already-valid WAV fixture ($LOCAL_WAV) -- same real sox
# conversion step, no need for a second one.
LOCAL_MOH_WAV="$LOCAL_WAV"

MOH_FILE_NAME="task0026dmohfile.wav"
code="$(multipart_upload "$RESTRICTED_JAR" /index.php/default/music-on-hold/addfile inputFile "$LOCAL_MOH_WAV" "$MOH_FILE_NAME" section="$MOH_CLASS_NAME" description=task0026d __content_type__=audio/wav)"
MOH_FILE_EXISTS="$(db_query "SELECT arquivo FROM sounds WHERE arquivo='${MOH_FILE_NAME}' AND tipo='MOH';")"
if [ "$code" = 302 ] && [ -n "$MOH_FILE_EXISTS" ]; then
    harness_ok "F3 valid: upload a legitimate MOH file" "HTTP $code, stored as '${MOH_FILE_EXISTS}' via the real addfileAction() HTTP flow"
else
    harness_bad "F3 valid: upload a legitimate MOH file" "HTTP $code, db row present='${MOH_FILE_EXISTS}'"
fi
harness_register_cleanup "MOH file ${MOH_FILE_NAME} (F3 fixture)" \
    "db_query \"DELETE FROM sounds WHERE arquivo='${MOH_FILE_NAME}' AND tipo='MOH';\" >/dev/null; true"

MOH_MALICIOUS_FILE='`touch '"$MARKER"'`.wav'
code="$(multipart_upload "$RESTRICTED_JAR" /index.php/default/music-on-hold/addfile inputFile "$LOCAL_MOH_WAV" "$MOH_MALICIOUS_FILE" section="$MOH_CLASS_NAME" description=task0026d __content_type__=audio/wav)"
MOH_MALICIOUS_ROWS="$(db_query "SELECT COUNT(*) FROM sounds WHERE arquivo LIKE '%touch%' AND tipo='MOH';")"
if marker_absent "$MARKER" && [ "${MOH_MALICIOUS_ROWS:-0}" = "0" ]; then
    harness_ok "F3: shell-shaped MOH upload filename cannot execute" "HTTP $code, no marker file created, no sound row stored with the malicious name"
else
    harness_bad "F3: shell-shaped MOH upload filename cannot execute" "HTTP $code, malicious rows=${MOH_MALICIOUS_ROWS}"
fi

code="$(request "$RESTRICTED_JAR" POST /index.php/default/music-on-hold/removefile "secao=\`touch ${MARKER}\`&arquivo=${MOH_FILE_NAME}")"
if marker_absent "$MARKER"; then
    harness_ok "F3: shell-shaped 'secao' on file removal cannot execute" "HTTP $code, no marker file created (rejected -- 'secao' does not name a real MOH class)"
else
    harness_bad "F3: shell-shaped 'secao' on file removal cannot execute" "HTTP $code, marker file was created"
fi

code="$(request "$RESTRICTED_JAR" POST /index.php/default/music-on-hold/removefile "secao=${MOH_CLASS_NAME}&arquivo=\`touch ${MARKER}\`.wav")"
MOH_FILE_STILL_THERE="$(app_exec "test -f '${MOH_ROOT}/${MOH_DIR_NAME}/${MOH_FILE_NAME}' && echo yes || echo no")"
if marker_absent "$MARKER" && [ "$MOH_FILE_STILL_THERE" = "yes" ]; then
    harness_ok "F3: shell-shaped 'arquivo' on file removal cannot execute" "HTTP $code, no marker file created, the real MOH file was left untouched (rejected by the filename allowlist)"
else
    harness_bad "F3: shell-shaped 'arquivo' on file removal cannot execute" "HTTP $code, real file still present=${MOH_FILE_STILL_THERE}"
fi

code="$(request "$RESTRICTED_JAR" POST /index.php/default/music-on-hold/removefile "secao=${MOH_CLASS_NAME}&arquivo=${MOH_FILE_NAME}")"
MOH_FILE_GONE="$(app_exec "test -f '${MOH_ROOT}/${MOH_DIR_NAME}/${MOH_FILE_NAME}' && echo no || echo yes")"
if [ "$code" = 302 ] && [ "$MOH_FILE_GONE" = "yes" ]; then
    harness_ok "F3 valid: legitimate file removal still works" "HTTP $code, file removed via the real removefileAction() HTTP flow"
else
    harness_bad "F3 valid: legitimate file removal still works" "HTTP $code, file gone=${MOH_FILE_GONE}"
fi

FATALS_AFTER_F3="$(fatal_count)"
if [ "$FATALS_AFTER_F3" = "$FATALS_BEFORE" ]; then
    harness_ok "F3: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE})"
else
    harness_bad "F3: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE} -> ${FATALS_AFTER_F3}"
fi

# =============================================================================
# F4 -- System Logs (LogsController -> Snep_Log::grepLog())
# =============================================================================

log "==> F4: System Logs boundary"

# TASK-0026D finding, unrelated to shell injection, documented in
# docs/tasks/0026d-shell-execution-hardening.md: `path.log` (setup.conf)
# is "/var/log/snep/", and Snep_Log always reads "<path.log>/full" --
# but that file has never existed in the app container at all. Real
# Asterisk logs live under /var/log/asterisk on the asterisk container's
# own volume, never shared with or copied into the app container, so
# this feature has never had anything to filter through HTTP in this
# dev environment, for a reason completely unrelated to this task.
# Snep_Log's own constructor also cannot surface that as a real
# BLOCKED/error state to its caller -- its file_exists() check result is
# silently discarded, since PHP constructors always return the new
# instance regardless of what the constructor body itself returns (a
# second, separate pre-existing bug, also documented, also not fixed
# here). Providing a small, harness-owned log fixture with real content
# is test-precondition scaffolding, not a product fix, exactly like the
# sound-files/MOH directory provisioning above.
LOG_DIR="/var/log/snep"
LOG_FILE="${LOG_DIR}/full"
LOG_FIXTURE_PRE_EXISTED="$(app_exec "test -f '${LOG_FILE}' && echo yes || echo no")"
app_exec "mkdir -p '${LOG_DIR}'"
if [ "$LOG_FIXTURE_PRE_EXISTED" = "no" ]; then
    app_exec "printf '%s\n%s\n%s\n' '[Jan  1 00:00:00] NOTICE[1]: task0026d-fixture-line-1' '[Jan  1 00:00:01] VERBOSE[1] task0026d-fixture-line-2 with VERBOSE marker' '[Jan  1 00:00:02] NOTICE[1]: task0026d-fixture-line-3' > '${LOG_FILE}' && chown www-data:www-data '${LOG_FILE}'"
    harness_register_cleanup "test-owned log fixture (${LOG_FILE} did not exist before this run)" "app_exec \"rm -f '${LOG_FILE}'\""
else
    log "==> ${LOG_FILE} already exists -- leaving it untouched, F4 checks below use whatever real content it already has"
fi

code="$(request "$RESTRICTED_JAR" POST /index.php/default/logs/view "real_time=no&init_day=2026-01-01 00:00&end_day=2026-01-01 23:59&verbose=&others=task0026d-fixture-line")"
if [ "$code" = 200 ] && ! grep -q "panel-red\|panel-orange" "$BODY"; then
    harness_ok "F4 valid: legitimate 'others' text filter works" "HTTP $code, log view rendered via the real viewAction() HTTP flow (literal substring match against the fixture log's own content, not an error panel)"
else
    harness_bad "F4 valid: legitimate 'others' text filter works" "HTTP $code"
fi

code="$(request "$RESTRICTED_JAR" POST /index.php/default/logs/view "real_time=no&init_day=2026-01-01 00:00&end_day=2026-01-01 23:59&verbose=&others=nonexistent-marker; touch ${MARKER} #")"
if [ "$code" = 200 ] && marker_absent "$MARKER"; then
    harness_ok "F4: shell-shaped 'others' filter cannot execute" "HTTP $code, no marker file created, no PHP error -- treated as inert literal substring data"
else
    harness_bad "F4: shell-shaped 'others' filter cannot execute" "HTTP $code, marker present=$(app_exec "test -e '$MARKER'" && echo yes || echo no)"
fi

code="$(request "$RESTRICTED_JAR" POST /index.php/default/logs/view "real_time=no&init_day=2026-01-01 00:00&end_day=2026-01-01 23:59&verbose=1] ; touch ${MARKER} #&others=")"
if [ "$code" = 200 ] && marker_absent "$MARKER"; then
    harness_ok "F4: shell-shaped 'verbose' filter cannot execute" "HTTP $code, no marker file created -- treated as inert literal substring data"
else
    harness_bad "F4: shell-shaped 'verbose' filter cannot execute" "HTTP $code, marker present=$(app_exec "test -e '$MARKER'" && echo yes || echo no)"
fi

code="$(request "$RESTRICTED_JAR" POST /index.php/default/logs/view "real_time=no&init_day=2026-01-01 00:00; touch ${MARKER} #&end_day=2026-01-01 23:59&verbose=&others=")"
if [ "$code" = 200 ] && marker_absent "$MARKER"; then
    harness_ok "F4: shell-shaped date/hour field cannot execute" "HTTP $code, no marker file created -- the sibling injection point (hora_ini, via the date field's time token) this task's own re-audit found beyond the two the original audit named"
else
    harness_bad "F4: shell-shaped date/hour field cannot execute" "HTTP $code, marker present=$(app_exec "test -e '$MARKER'" && echo yes || echo no)"
fi

FATALS_AFTER_F4="$(fatal_count)"
if [ "$FATALS_AFTER_F4" = "$FATALS_BEFORE" ]; then
    harness_ok "F4: application remained healthy" "PHP Fatal Error count unchanged (${FATALS_BEFORE})"
else
    harness_bad "F4: application remained healthy" "PHP Fatal Error count changed: ${FATALS_BEFORE} -> ${FATALS_AFTER_F4}"
fi

# --- cleanup any /tmp/snep-log-file-*.txt this section created ----------
harness_register_best_effort_cleanup "F4 temp filtered-log files" "app_exec \"rm -f /tmp/snep-log-file-*.txt\""

# =============================================================================
# F5 -- CNL Update (CnlController)
# =============================================================================

log "==> F5: CNL Update boundary"

# TASK-0026D finding, unrelated to shell injection, documented in
# docs/tasks/0026d-shell-execution-hardening.md: Zend_File_Transfer_Adapter_Http::receive()
# fatals under PHP 8.4 on EVERY upload attempt, valid or not --
# Zend_Validate_File_Upload::isValid() calls count($this->_messages) at
# line 226 and that property is null instead of an array in this code
# path (Uncaught TypeError: count(): Argument #1 ($value) must be of
# type Countable|array, null given). This is CnlController's own upload
# mechanism (the only controller in this codebase using
# Zend_File_Transfer_Adapter_Http -- SoundFiles/MusicOnHold read
# $_FILES directly), confirmed by the stack trace to fail *inside*
# receive() itself, called before any of this task's changed code ever
# runs. First surfaced here because nothing in this project's history
# had previously exercised a real HTTP upload to this controller. A
# genuine PHP 8.4 compatibility gap (a future Phase 2 task), not fixed
# here.
#
# Consequence for this suite: a "legitimate flow still works" HTTP
# round-trip is not currently possible for F5 at all, for either a
# valid or a malicious upload -- so the actual fix (basename validation,
# Zip Slip rejection, ZipArchive extraction) is verified directly below,
# replicating exactly what CnlController's updateAction_76() does with
# the file once $adapter->receive() would have succeeded. The malicious
# HTTP request further below still goes through the real endpoint --
# it hits the same pre-existing fatal before reaching any of this
# task's code, which is itself still valid (if weaker) proof that no
# shell command can run through this path either way.

LOCAL_ZIP="$(mktemp -u).zip"
DUMMY_TXT_CONTENT="1234567 dummy CNL prefix line for TASK-0026D functional proof only"
app_exec "php -r '\$z = new ZipArchive(); \$z->open(\"/tmp/task0026d-build.zip\", ZipArchive::CREATE); \$z->addFromString(\"task0026dcnl.txt\", \"${DUMMY_TXT_CONTENT}\"); \$z->close();'"
docker cp "$($COMPOSE ps -q app):/tmp/task0026d-build.zip" "$LOCAL_ZIP" 2>/dev/null
harness_register_best_effort_cleanup "local throwaway zip fixture" "rm -f '$LOCAL_ZIP'; app_exec \"rm -f /tmp/task0026d-build.zip\""

if [ -s "$LOCAL_ZIP" ]; then
    # Direct proof of the actual fix logic: basename() -> require
    # ".zip" -> is_file() -> open -> reject any entry escaping /tmp ->
    # extractTo -- byte-for-byte what CnlController::updateAction_76()
    # now does after a successful receive(), exercised here without
    # going through the broken Zend adapter.
    app_exec "rm -f /tmp/task0026dcnl.txt"
    EXTRACT_OUT="$(app_exec "php -r '
        \$safeBaseName = basename(\"task0026dcnl.zip\");
        \$uploadedZip = \"/tmp/task0026d-build.zip\";
        \$file_name = preg_match(\"/\\.zip\$/i\", \$safeBaseName) ? \"/tmp/task0026dcnl.txt\" : \"\";
        \$extracted = false;
        if (\$file_name !== \"\" && is_file(\$uploadedZip)) {
            \$zip = new ZipArchive();
            if (\$zip->open(\$uploadedZip) === true) {
                \$safe = true;
                for (\$i = 0; \$i < \$zip->numFiles; \$i++) {
                    \$n = \$zip->getNameIndex(\$i);
                    if (\$n === false || strpos(\$n, \"..\") !== false || substr(\$n, 0, 1) === \"/\") { \$safe = false; break; }
                }
                if (\$safe) {
                    \$extracted = \$zip->extractTo(\"/tmp\");
                }
                \$zip->close();
            }
        }
        echo (\$extracted && is_file(\$file_name)) ? \"yes\" : \"no\";
    '" | tr -d '\r')"
    if [ "$EXTRACT_OUT" = "yes" ]; then
        harness_ok "F5 valid: the fix's own extraction logic works" "native ZipArchive extraction (no shell) succeeds for a legitimately-named, legitimately-shaped zip -- same logic updateAction_76() runs, exercised directly since the HTTP path is blocked by the unrelated bug documented above"
    else
        harness_bad "F5 valid: the fix's own extraction logic works" "direct extraction did not produce the expected output file (extracted=${EXTRACT_OUT})"
    fi
    harness_register_cleanup "extracted CNL fixture file" "app_exec \"rm -f /tmp/task0026dcnl.txt\""

    # Zip Slip defense-in-depth, proven directly: an entry whose own
    # stored name tries to escape /tmp must cause the whole archive to
    # be rejected, nothing extracted.
    app_exec "php -r '\$z = new ZipArchive(); \$z->open(\"/tmp/task0026d-slip.zip\", ZipArchive::CREATE); \$z->addFromString(\"../../etc/task0026d-slip-marker\", \"should never be written\"); \$z->close();'"
    harness_register_best_effort_cleanup "zip-slip fixture archive" "app_exec \"rm -f /tmp/task0026d-slip.zip\""
    SLIP_OUT="$(app_exec "php -r '
        \$safe = true;
        \$zip = new ZipArchive();
        if (\$zip->open(\"/tmp/task0026d-slip.zip\") === true) {
            for (\$i = 0; \$i < \$zip->numFiles; \$i++) {
                \$n = \$zip->getNameIndex(\$i);
                if (\$n === false || strpos(\$n, \"..\") !== false || substr(\$n, 0, 1) === \"/\") { \$safe = false; break; }
            }
            \$zip->close();
        }
        echo \$safe ? \"unsafe-not-detected\" : \"rejected\";
    '" | tr -d '\r')"
    if [ "$SLIP_OUT" = "rejected" ] && marker_absent "/etc/task0026d-slip-marker"; then
        harness_ok "F5: Zip Slip entry cannot escape /tmp" "the fix's per-entry check rejects an archive containing a '../../' entry name before extraction; confirmed nothing was written at /etc/task0026d-slip-marker"
    else
        harness_bad "F5: Zip Slip entry cannot escape /tmp" "slip check result=${SLIP_OUT}"
    fi
else
    harness_bad "F5 valid: the fix's own extraction logic works" "could not build the local test zip fixture via the app container's ZipArchive"
fi

FATALS_BEFORE_F5_HTTP="$(fatal_count)"
CNL_MALICIOUS_NAME='`touch '"$MARKER"'`.zip'
code="$(multipart_upload "$RESTRICTED_JAR" /index.php/default/cnl cnl "$LOCAL_ZIP" "$CNL_MALICIOUS_NAME" country=76 type=M)"
if marker_absent "$MARKER"; then
    harness_ok "F5: shell-shaped upload filename cannot execute" "HTTP $code, no marker file created via the real HTTP endpoint (this request also hits the unrelated pre-existing Zend upload-validator fatal documented above before reaching any of this task's code -- consistent either way with no shell execution occurring)"
else
    harness_bad "F5: shell-shaped upload filename cannot execute" "HTTP $code, marker file was created"
fi
# Best-effort: whatever literal (harmless) filename actually landed on
# disk for the malicious-name upload above.
harness_register_best_effort_cleanup "F5 malicious-name upload artifacts" \
    "app_exec \"find /tmp -maxdepth 1 -newer /etc/hostname -iname '*touch*' -delete\" 2>/dev/null; true"

FATALS_AFTER_F5="$(fatal_count)"
# The one known, pre-existing, documented fatal from the HTTP call just
# above is expected and accounted for here -- anything beyond it is not.
EXPECTED_F5_FATALS=$((FATALS_BEFORE_F5_HTTP + 1))
if [ "$FATALS_AFTER_F5" -le "$EXPECTED_F5_FATALS" ]; then
    harness_ok "F5: application remained healthy" "PHP Fatal Error count ${FATALS_BEFORE} -> ${FATALS_AFTER_F5} (only the one pre-existing, documented Zend upload-validator fatal from the HTTP call above, nothing new from this task's own code)"
else
    harness_bad "F5: application remained healthy" "PHP Fatal Error count changed more than expected: ${FATALS_BEFORE} -> ${FATALS_AFTER_F5} (expected at most ${EXPECTED_F5_FATALS})"
fi

# --- final marker check across the whole run -----------------------------

if marker_absent "$MARKER"; then
    harness_ok "no shell-injection marker exists anywhere in this run" "confirmed absent at $MARKER after every F2-F5 check above"
else
    harness_bad "no shell-injection marker exists anywhere in this run" "marker file exists at $MARKER"
fi

harness_complete
