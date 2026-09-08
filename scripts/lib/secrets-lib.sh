#!/bin/bash
#
# Shared secret-rotation/drift-detection helpers (TASK-0033C).
#
# Sourced by scripts/secrets-check.sh, scripts/rotate-secrets.sh,
# scripts/secrets-consistency-smoke-test.sh and
# scripts/secret-rotation-smoke-test.sh. Bash-3.2 compatible on purpose
# (same host-shell constraint as scripts/lib/harness.sh and
# scripts/lib/backup-lib.sh -- no associative arrays, no `readarray`,
# no `${var,,}`).
#
# NON-DISCLOSURE CONTRACT (see docs/tasks/
# 0033c-secret-rotation-contract.md LOGGING SAFETY): every function here
# that handles a secret VALUE either (a) never prints it, only a
# MATCH/DRIFT/UNKNOWN classification or a sha256 hash, or (b) passes it
# to a container exclusively via stdin/MYSQL_PWD, never as a `docker
# compose exec`/shell CLI argument. Grep this file for `slib_die` calls
# passing raw secret variables before adding a new one -- there should
# be none.
#
# CONTRACT VOCABULARY (see docs/tasks/0033c-secret-rotation-contract.md
# SOURCE OF TRUTH): every rotation-affecting outcome in this project is
# exactly one of:
#   ROTATED_SUCCESSFULLY           -- declared value is now the active,
#                                      coherent value everywhere.
#   ROTATION_REJECTED              -- an explicit rotation attempt did
#                                      not apply (validation/connectivity/
#                                      verification failure); rolled back
#                                      to the previous coherent state
#                                      where a change had already begun.
#   ROTATION_PENDING_EXPLICIT_ACTION -- surfaced by a container entrypoint
#                                      at startup: the declared (.env)
#                                      value disagrees with the persisted
#                                      value this container is about to
#                                      rely on, and no rotation has been
#                                      run yet. The container refuses to
#                                      start silently on stale state.
#   DRIFT_DETECTED                 -- surfaced by `secrets-check`/
#                                      `rotate-secrets` reporting for a
#                                      steady-state (non-startup) read: a
#                                      declared/persisted mismatch exists
#                                      right now.
# Never silently ignored: every code path here ends in one of the four.

SECRETS_LIB_LOADED=1

# slib_run_sh <container> <script> -- runs a PURE FILESYSTEM operation
# (read/write/backup/restore a config file in that service's own
# volumes/mounts) via `docker compose run --rm --no-deps --entrypoint
# sh`, never `docker compose exec` against the currently-running
# container.
#
# This matters specifically because of this task's own STARTUP POLICY
# (docker/entrypoint.sh / docker/asterisk-entrypoint.sh now refuse to
# start -- ROTATION_PENDING_EXPLICIT_ACTION -- when a declared secret
# disagrees with what's already persisted): a container that is
# crash-looping for exactly that reason is NOT reliably attachable via
# `docker compose exec` (it cycles between "Restarting" and a brief
# "running" window). `docker compose run --rm --no-deps --entrypoint
# sh` starts a fresh, disposable container from the same image, sharing
# the same volumes/bind-mounts, but bypassing the image's normal
# ENTRYPOINT (and therefore its coherence check) entirely -- so a
# remediation command (`secrets-check`/`rotate-secrets`) keeps working
# precisely in the scenario it exists to recover from. This is the same
# pattern scripts/backup.sh already established for reading the
# asterisk-etc volume without booting Asterisk.
#
# Live-service checks (AMI login, DB/root auth, `manager reload`,
# `odbc show all`) are NOT filesystem operations -- they need the real
# running process and correctly stay on `docker compose exec` elsewhere
# in this file.
slib_run_sh() {
    local container="$1" script="$2"
    $COMPOSE run --rm --no-deps -T --entrypoint sh "$container" -c "$script" 2>/dev/null
}

slib_log() { printf '%s\n' "$*" >&2; }

slib_die() {
    slib_log "ERROR: $*"
    exit 1
}

# slib_sha256_stdin -- reads stdin, prints the sha256 hex digest. Same
# GNU/BSD portability fallback as blib_sha256 (scripts/lib/backup-lib.sh),
# but operating on stdin so callers never need a temp file for a value
# that must not touch disk.
slib_sha256_stdin() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        slib_die "neither sha256sum nor shasum is available on this host"
    fi
}

# slib_hash_of_value <value> -- sha256 of a literal string, computed
# entirely via bash/POSIX-sh BUILTINS (printf), never handing the value
# to a separate process's argv (a separate process's argv is visible to
# any other process on the same host via `ps`/`/proc`; a builtin runs
# inside the calling shell itself, so nothing new appears in the process
# table). Only the resulting hash is ever returned/printed.
slib_hash_of_value() {
    printf '%s' "$1" | slib_sha256_stdin
}

# slib_validate_secret <value> -- Phase 29 (failure injection: invalid
# desired secret format). Every consumer file this project templates
# secrets into is a plain-text ini-style file edited with `sed`
# (docker/entrypoint.sh, docker/asterisk-entrypoint.sh) using `|` as the
# sed delimiter and, for setup.conf, wrapping the value in double quotes;
# the DB application-password rotation path (Snep_/rotate-secrets.sh)
# also embeds the value as a single-quoted SQL string literal in an
# `ALTER USER ... IDENTIFIED BY '...'` statement. A secret containing
# '"', '|', a backslash, a single quote, or a newline/CR would break one
# of those three templating contexts -- either corrupting the config
# file it's templated into or, for the SQL path, escaping the string
# literal (a real injection risk, not just a corruption one). Reject
# those up front, before any file or DB state is touched -- this is a
# pure, side-effect-free precondition check. This is a format
# constraint on what THIS TOOL accepts, not a password-policy redesign
# (explicitly out of scope, see docs/tasks/
# 0033c-secret-rotation-contract.md SCOPE).
slib_validate_secret() {
    local v="$1"
    if [ -z "$v" ]; then
        slib_log "invalid secret: empty value"
        return 1
    fi
    case "$v" in
        *'"'*)   slib_log "invalid secret: contains a double-quote character"; return 1 ;;
        *"'"*)   slib_log "invalid secret: contains a single-quote character"; return 1 ;;
        *'|'*)   slib_log "invalid secret: contains a '|' character"; return 1 ;;
        *'\'*)   slib_log "invalid secret: contains a backslash character"; return 1 ;;
    esac
    case "$(printf '%s' "$v" | tr -d '\n\r')" in
        "$v") ;;
        *) slib_log "invalid secret: contains a newline/carriage-return character"; return 1 ;;
    esac
    if [ "${#v}" -gt 255 ]; then
        slib_log "invalid secret: longer than 255 characters"
        return 1
    fi
    return 0
}

# slib_compare <declared-value> <container> <extract-shell-snippet>
# Runs a FIXED, non-secret shell snippet (grep/sed only -- the snippet
# text itself never contains a secret) inside <container> to pull out
# one config value, holds it ONLY in a local shell variable (never
# echoed, never passed to another process as a CLI argument -- captured
# purely via the command-substitution pipe, the same mechanism this
# script already uses to hold the DECLARED value from `.env`), hashes
# both sides with the identical slib_hash_of_value function so a
# transport-added trailing newline can never cause a false DRIFT, and
# unsets the extracted copy immediately after comparing. Prints exactly
# one of MATCH / DRIFT / UNKNOWN -- never a value or a hash.
slib_compare() {
    local declared="$1" container="$2" snippet="$3" remote_value result
    remote_value="$(slib_remote_extract_value "$container" "$snippet")"
    if [ -z "$remote_value" ]; then
        result="UNKNOWN"
    elif [ "$(slib_hash_of_value "$declared")" = "$(slib_hash_of_value "$remote_value")" ]; then
        result="MATCH"
    else
        result="DRIFT"
    fi
    unset remote_value
    echo "$result"
}

# slib_remote_extract_value <container> <extract-shell-snippet>
# Runs a FIXED, non-secret snippet and returns its output (CR/LF
# trimmed) directly -- the raw value, not a hash. Held only in the
# caller's own local shell variable, never printed/logged; needed for
# the narrow, legitimate case of capturing a PRE-rotation value purely
# to support rolling a DB account back to it if a later verification
# step fails (see scripts/rotate-secrets.sh rotate_db_password). Prefer
# slib_compare (hash-only) wherever the raw value itself isn't actually
# needed.
slib_remote_extract_value() {
    local container="$1" snippet="$2" v
    v="$(slib_run_sh "$container" "$snippet")"
    printf '%s' "$v" | tr -d '\r\n'
}

# --- Live authentication checks -------------------------------------------
#
# These are the authoritative signal for "is the DECLARED value the
# ACTUAL active credential" for the three accounts that authenticate
# rather than merely being read from a config file (the MariaDB
# application user, the MariaDB root account, the AMI user). Secrets
# reach the target container exclusively via stdin (a bash here-string,
# `<<<`) -- the `docker compose exec` argv on the HOST and the target
# process's argv INSIDE the container are both fixed, non-secret
# strings; nothing new shows up in `ps`/`docker top` output on either
# side. See docs/tasks/0033c-secret-rotation-contract.md
# PROCESS/TEMPFILE SAFETY.

# slib_db_user_auth_check <container> <db-user> <secret-value>
# Prints MATCH (auth succeeded), DRIFT (access denied -- a real,
# distinguishable auth failure), or UNKNOWN (any other error: container
# unreachable, DB not up, etc).
slib_db_user_auth_check() {
    local container="$1" user="$2" secret="$3" out status
    out="$($COMPOSE exec -T "$container" sh -c \
        'read -r PW; MYSQL_PWD="$PW" mariadb -u"'"$user"'" -e "SELECT 1;" 2>&1 1>/dev/null' \
        <<< "$secret")"
    status=$?
    if [ "$status" -eq 0 ]; then
        echo "MATCH"
    elif printf '%s' "$out" | grep -qi "Access denied"; then
        echo "DRIFT"
    else
        slib_log "db auth check: unexpected result: $(printf '%s' "$out" | tr -d '\r')"
        echo "UNKNOWN"
    fi
}

# slib_db_root_auth_check <container> <secret-value>
slib_db_root_auth_check() {
    local container="$1" secret="$2" out status
    out="$($COMPOSE exec -T "$container" sh -c \
        'read -r PW; MYSQL_PWD="$PW" mariadb-admin -uroot ping 2>&1' \
        <<< "$secret")"
    status=$?
    if [ "$status" -eq 0 ] && printf '%s' "$out" | grep -qi "mysqld is alive"; then
        echo "MATCH"
    elif printf '%s' "$out" | grep -qi "Access denied"; then
        echo "DRIFT"
    else
        slib_log "db root auth check: unexpected result: $(printf '%s' "$out" | tr -d '\r')"
        echo "UNKNOWN"
    fi
}

# slib_ami_auth_check <container> <ami-user> <ami-secret>
# Speaks the AMI text protocol directly over /dev/tcp inside
# <container> (the asterisk service; AMI is never published to the
# host, TASK-0005) -- independent of SENMA's own PHP AMI client, so a
# rotation regression in Asterisk_AMI/setup.conf plumbing can never mask
# (or be masked by) this check. Both the username and secret are fed
# over stdin as two lines; the remote script text embedded below
# contains no secret literal.
slib_ami_auth_check() {
    local container="$1" user="$2" secret="$3" out status
    # shellcheck disable=SC2016
    # Connects to the container's OWN address on the dedicated
    # `senma-control` network (TASK-0034F, closing TASK-0034 CH-6), not
    # 127.0.0.1/loopback and not a plain "$(hostname)" lookup: this
    # container is on two networks (`mag` and `senma-control`), and
    # `getent hosts "$(hostname)"` would return an ambiguous mix of
    # addresses across both -- manager.conf's ACL now permits only
    # `senma-control`'s own pinned subnet (172.29.0.0/24 by default) and
    # denies everything else, including loopback and the `mag`-network
    # address -- confirmed live (a correct-credential login over
    # 127.0.0.1, or over the `mag`-network address, is rejected with
    # "Authentication failed" purely on ACL grounds, not the secret).
    # `$ASTERISK_HOST` names the `senma-ami` alias that exists on
    # `senma-control` alone (same alias the app container's own AMI
    # client, and manager.conf's own ACL, are both scoped to) --
    # inherited automatically from this container's own environment
    # (env_file: .env on the asterisk service), so `docker compose exec`
    # sees it with no extra plumbing.
    local remote_script='
trap "" PIPE
read -r AMI_USER
read -r AMI_SECRET
[ -n "${ASTERISK_HOST:-}" ] || { echo "AMI_CONNECT_ERROR"; exit 2; }
SELF_IP="$(getent hosts "$ASTERISK_HOST" | awk "{print \$1}" | head -1)"
[ -n "$SELF_IP" ] || { echo "AMI_CONNECT_ERROR"; exit 2; }
exec 3<>/dev/tcp/"$SELF_IP"/5038 || { echo "AMI_CONNECT_ERROR"; exit 2; }
IFS= read -r -t 5 banner <&3 || { echo "AMI_CONNECT_ERROR"; exit 2; }
printf "Action: Login\r\nUsername: %s\r\nSecret: %s\r\nEvents: off\r\n\r\n" "$AMI_USER" "$AMI_SECRET" >&3 2>/dev/null
resp=""
while IFS= read -r -t 5 line <&3; do
    line="${line%$'"'"'\r'"'"'}"
    resp="$resp$line|"
    [ -z "$line" ] && break
done
# Asterisk closes the socket immediately on an auth failure -- a
# subsequent Logoff write would raise SIGPIPE; ignored above (trap ""
# PIPE) and suppressed here so this is never mistaken for a real error.
printf "Action: Logoff\r\n\r\n" >&3 2>/dev/null
exec 3<&- 3>&- 2>/dev/null
case "$resp" in
    *"Response: Success"*) echo "AMI_AUTH_OK" ;;
    *"Response: Error"*)   echo "AMI_AUTH_REJECTED" ;;
    *)                     echo "AMI_AUTH_UNKNOWN" ;;
esac
'
    out="$($COMPOSE exec -T "$container" bash -c "$remote_script" <<< "$user
$secret" 2>&1)"
    status=$?
    case "$out" in
        *AMI_AUTH_OK*)       echo "MATCH" ;;
        *AMI_AUTH_REJECTED*) echo "DRIFT" ;;
        *)
            slib_log "ami auth check: unexpected result (exit $status): $(printf '%s' "$out" | tr -d '\r')"
            echo "UNKNOWN"
            ;;
    esac
}

# --- Backup/rollback helpers -----------------------------------------------
#
# slib_remote_backup <container> <path> -- copies <path> to
# <path>.rotate-bak.<pid> inside the container (same filesystem, so the
# eventual restore is a plain rename, never a partial cross-device
# write). Prints the backup path on success.
slib_remote_backup() {
    local container="$1" path="$2" bak="${2}.rotate-bak.$$"
    slib_run_sh "$container" "cp -p '$path' '$bak'" >/dev/null \
        || { slib_log "could not back up $path in $container"; return 1; }
    echo "$bak"
}

slib_remote_restore() {
    local container="$1" bak="$2" path="$3"
    slib_run_sh "$container" "mv -f '$bak' '$path'" >/dev/null
}

slib_remote_discard_backup() {
    local container="$1" bak="$2"
    slib_run_sh "$container" "rm -f '$bak'" >/dev/null
}

# slib_remote_template_line <container> <file> <awk-match-regex> <awk-new-line-expr> <value> [owner] [mode]
#
# Rewrites the one line in <file> (inside <container>) matching
# <awk-match-regex> to the line produced by evaluating
# <awk-new-line-expr> (a literal, non-secret AWK expression -- e.g.
# `"db.password = \"" ENVIRON["SLIB_NEWVAL"] "\""`). <value> reaches
# the container over stdin ONLY, is `read` into a variable, `export`ed,
# and referenced from inside the AWK program via ENVIRON -- never
# interpolated into the AWK program text itself, and therefore never a
# CLI argument to any process, on the host or in the container (`export`
# only affects a child process's environ block, which plain `ps`/`docker
# top` output does not show -- see docs/tasks/
# 0033c-secret-rotation-contract.md PROCESS/TEMPFILE SAFETY). Writes to
# a same-directory temp file first, `mv`s over the original only if awk
# succeeds (atomic rename, never a torn write). Takes its own backup
# first (mode/ownership preserved via `cp -p`) and returns that backup's
# path on success for the caller to discard once the whole rotation is
# verified, or restore on failure.
#
# [owner]/[mode] are OPTIONAL explicit "user:group"/octal-mode values to
# apply to the new file instead of copying them from the file being
# replaced. Pass these for a file this project documents a REQUIRED,
# known-correct ownership for regardless of current state (setup.conf
# must always end up www-data:www-data 664 -- see docker/entrypoint.sh's
# own unconditional chown/chmod immediately after its first-boot block).
# Omit them (the default) to preserve whatever ownership/mode the file
# already had -- correct for manager.conf/res_odbc.conf, which the
# asterisk-etc volume already owns correctly by construction (asterisk-
# entrypoint.sh's first-boot block runs as the image's own `USER
# asterisk`, confirmed live) and which this project defines no separate
# required-ownership contract for.
#
# mawk (the /bin/sh `awk` in every SENMA image, confirmed live) supports
# ENVIRON -- a POSIX awk feature, not GNU-specific.
slib_remote_template_line() {
    local container="$1" file="$2" match_regex="$3" new_line_expr="$4" value="$5" owner="${6:-}" mode="${7:-}"
    local bak script tmp_suffix="rotate-new.$$"
    bak="$(slib_remote_backup "$container" "$file")" || {
        slib_log "could not back up $file in $container -- aborting before any write"
        return 1
    }
    script=$(cat <<REMOTE
set -e
read -r SLIB_NEWVAL
export SLIB_NEWVAL
SLIB_OWNER="${owner:-\$(stat -c '%U:%G' '$file')}"
SLIB_MODE="${mode:-\$(stat -c '%a' '$file')}"
awk -v pat='$match_regex' '\$0 ~ pat { print $new_line_expr; next } { print }' '$file' > '$file.$tmp_suffix'
grep -q . '$file.$tmp_suffix'
chown "\$SLIB_OWNER" '$file.$tmp_suffix'
chmod "\$SLIB_MODE" '$file.$tmp_suffix'
mv '$file.$tmp_suffix' '$file'
REMOTE
)
    if printf '%s\n' "$value" | slib_run_sh "$container" "$script" >/dev/null; then
        echo "$bak"
        return 0
    else
        slib_log "templating $file in $container failed -- restoring from backup"
        slib_remote_restore "$container" "$bak" "$file"
        return 1
    fi
}

# --- DB account mutation ----------------------------------------------------
#
# Both functions below authenticate as root (never needing the target
# account's OLD password -- root can always ALTER USER any account) and
# feed EVERY secret (the authenticating root password, and the new
# password(s) embedded in the SQL body) over stdin as a single heredoc:
# line 1 is consumed by `read -r PW` for MYSQL_PWD, and the mariadb
# client -- invoked with no `-e`, so it reads its SQL script from
# whatever remains on stdin -- consumes the rest directly. The `docker
# compose exec` argv (host-visible) and the container's own `sh -c`/
# `mariadb` argv are both the fixed, non-secret text below; no secret
# value is ever a CLI argument. Both new-value inputs must already have
# passed slib_validate_secret (rejects the single quote this embeds
# the value inside) before calling these.

# slib_db_alter_user_password <container> <root_password> <db_user> <new_password>
slib_db_alter_user_password() {
    local container="$1" root_password="$2" db_user="$3" new_password="$4"
    local remote_script='read -r PW; MYSQL_PWD="$PW" mariadb -uroot'
    $COMPOSE exec -T "$container" sh -c "$remote_script" <<SQL
$root_password
ALTER USER '$db_user'@'%' IDENTIFIED BY '$new_password';
FLUSH PRIVILEGES;
SQL
}

# slib_db_alter_root_password <container> <current_root_password> <new_root_password>
# Rotates BOTH root@% and root@localhost (confirmed live, both exist on
# this image's default MariaDB bootstrap) so a plain `docker compose
# exec db mariadb -uroot` (Unix-socket, matches root@localhost) and a
# TCP/`-h 127.0.0.1` connection (matches root@%, which is also what the
# db service's own healthcheck in compose.yaml uses) stay coherent with
# each other, not just with whichever one happens to be tested.
slib_db_alter_root_password() {
    local container="$1" current_root_password="$2" new_root_password="$3"
    local remote_script='read -r PW; MYSQL_PWD="$PW" mariadb -uroot'
    $COMPOSE exec -T "$container" sh -c "$remote_script" <<SQL
$current_root_password
ALTER USER 'root'@'%' IDENTIFIED BY '$new_root_password';
ALTER USER 'root'@'localhost' IDENTIFIED BY '$new_root_password';
FLUSH PRIVILEGES;
SQL
}

# slib_require_containers svc1 svc2 ... -- plain non-harness precondition
# check (secrets-check.sh/rotate-secrets.sh are operator commands, not
# harness-based smoke tests, so they don't source scripts/lib/harness.sh).
slib_require_containers() {
    local svc
    for svc in "$@"; do
        $COMPOSE ps "$svc" 2>/dev/null | grep -q "Up" \
            || slib_die "service '$svc' is not Up -- run 'make up' first"
    done
}
