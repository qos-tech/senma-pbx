#!/bin/bash
#
# TASK-0035E9: remove only the operator-local bootstrap plaintext secret.
#
# Does NOT change the database password, does NOT regenerate credentials,
# and is idempotent when the file is already absent.
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRET_FILE="${SENMA_BOOTSTRAP_ADMIN_SECRET_HOST:-$REPO_ROOT/secrets/bootstrap-admin-password}"
SECRET_DIR="$(dirname "$SECRET_FILE")"

removed=0
if [ -e "$SECRET_FILE" ]; then
    rm -f -- "$SECRET_FILE"
    removed=1
fi

# Drop leftover temp/lock files from interrupted bootstrap attempts.
# Never touches unrelated files in secrets/.
shopt -s nullglob
for f in \
    "$SECRET_DIR"/bootstrap-admin-password.tmp.* \
    "$SECRET_DIR"/bootstrap-admin.lock
do
    rm -f -- "$f" || true
done
shopt -u nullglob

if [ "$removed" = "1" ]; then
    echo "Removed bootstrap admin plaintext secret:"
    echo "  $SECRET_FILE"
    echo "Database administrator password was NOT changed."
else
    echo "Bootstrap admin plaintext secret already absent:"
    echo "  $SECRET_FILE"
    echo "Nothing to do. Database administrator password was NOT changed."
fi
