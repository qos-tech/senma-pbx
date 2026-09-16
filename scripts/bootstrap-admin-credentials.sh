#!/bin/bash
#
# TASK-0035E9: explicit operator retrieval of the fresh-install admin
# bootstrap plaintext credential.
#
# Reads ONLY the operator-local secret file
#   secrets/bootstrap-admin-password
# relative to the repository root. Never regenerates, never queries or
# mutates the database, never weakens file permissions.
#
# Exit codes:
#   0 -- secret present; username + password printed
#   1 -- secret absent / unreadable / empty (clear refusal; no side effects)
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRET_FILE="${SENMA_BOOTSTRAP_ADMIN_SECRET_HOST:-$REPO_ROOT/secrets/bootstrap-admin-password}"

if [ ! -f "$SECRET_FILE" ]; then
    echo "ERROR: bootstrap admin secret not found:" >&2
    echo "  $SECRET_FILE" >&2
    echo >&2
    echo "This is expected after 'make bootstrap-admin-credentials-clear'," >&2
    echo "or on an installation that was never fresh-bootstrapped on this host." >&2
    echo "No password was generated or changed." >&2
    exit 1
fi

if [ ! -r "$SECRET_FILE" ]; then
    echo "ERROR: bootstrap admin secret exists but is not readable by $(id -un):" >&2
    echo "  $SECRET_FILE" >&2
    echo "Fix ownership/mode (expected 0600, operator-owned) without weakening to world-readable." >&2
    exit 1
fi

PASSWORD="$(tr -d '\r\n' < "$SECRET_FILE")"
if [ -z "$PASSWORD" ]; then
    echo "ERROR: bootstrap admin secret file is empty: $SECRET_FILE" >&2
    echo "No password was generated or changed." >&2
    exit 1
fi

printf 'Username: admin\n'
printf 'Password: %s\n' "$PASSWORD"
