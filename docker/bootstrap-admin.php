<?php
/**
 * TASK-0035E9 / TASK-0026H (F27): fresh-install admin credential bootstrap.
 *
 * Invoked from docker/entrypoint.sh on every app container start.
 * Idempotent and safe to run repeatedly: it only ever acts when the
 * `admin` row's stored password still exactly equals the install seed's
 * sentinel value ('!SENMA-BOOTSTRAP-PENDING!', see
 * snep/install/database/system_data.sql) -- which deliberately cannot
 * authenticate anything (Snep_Security_Password::verify() rejects it
 * against any submitted plaintext), so a fresh install has NO usable
 * admin credential at all until this runs once.
 *
 * TASK-0035E9: the generated plaintext is persisted ONLY in a durable
 * operator-side secret file (default host path: ./secrets/bootstrap-
 * admin-password, mounted at /run/senma/secrets inside the app
 * container). Plaintext is NEVER printed to stdout/stderr/container
 * logs. Retrieval is an explicit operator action
 * (`make bootstrap-admin-credentials`).
 *
 * Ordering (failure atomicity):
 *   1. flock exclusive lock on the secrets directory
 *   2. confirm admin still holds the sentinel
 *   3. ensure the secret file exists (reuse if a prior attempt wrote it
 *      before the DB update committed; otherwise generate + atomic publish)
 *   4. UPDATE users SET password=hash WHERE id=? AND password=SENTINEL
 *   5. announce path-only success (no plaintext)
 *
 * Restart / upgrade / restore of an already-bootstrapped admin never
 * regenerates credentials (non-sentinel password => immediate no-op).
 *
 * See docs/tasks/0035e9-secure-initial-admin-credential-bootstrap.md.
 */

require_once '/var/www/html/snep/lib/Snep/Security/Password.php';

const SENTINEL = '!SENMA-BOOTSTRAP-PENDING!';
const DEFAULT_SECRET_PATH = '/run/senma/secrets/bootstrap-admin-password';
const DEFAULT_LOCK_PATH = '/run/senma/secrets/bootstrap-admin.lock';
/** Host-relative path shown to operators (never a container-only path). */
const OPERATOR_SECRET_PATH = 'secrets/bootstrap-admin-password';
/** 24 bytes = 192 bits; hex encoding matches `openssl rand -hex 24`. */
const RANDOM_BYTES = 24;

function env($name, $default = null) {
    $value = getenv($name);
    return $value === false ? $default : $value;
}

function fail($message, $code = 1) {
    fwrite(STDERR, "[bootstrap-admin] ERROR: {$message}\n");
    exit($code);
}

function secret_path() {
    $path = env('SENMA_BOOTSTRAP_ADMIN_SECRET', DEFAULT_SECRET_PATH);
    return is_string($path) && $path !== '' ? $path : DEFAULT_SECRET_PATH;
}

function lock_path() {
    $path = env('SENMA_BOOTSTRAP_ADMIN_LOCK', DEFAULT_LOCK_PATH);
    return is_string($path) && $path !== '' ? $path : DEFAULT_LOCK_PATH;
}

/**
 * Publish $plaintext to $finalPath with mode 0600, owned like $dir.
 * Uses temp + rename so readers never see a partial file.
 */
function publish_secret($finalPath, $plaintext) {
    $dir = dirname($finalPath);
    if (!is_dir($dir)) {
        fail("secrets directory missing: {$dir} (expected bind of ./secrets)");
    }
    if (!is_writable($dir)) {
        fail("secrets directory not writable: {$dir}");
    }

    $tmp = $finalPath . '.tmp.' . bin2hex(random_bytes(8));
    $fh = @fopen($tmp, 'xb');
    if ($fh === false) {
        fail("cannot create temporary secret file at {$tmp}");
    }
    if (fwrite($fh, $plaintext) === false) {
        fclose($fh);
        @unlink($tmp);
        fail("cannot write temporary secret file at {$tmp}");
    }
    if (!fflush($fh)) {
        fclose($fh);
        @unlink($tmp);
        fail("cannot flush temporary secret file at {$tmp}");
    }
    fclose($fh);

    @chmod($tmp, 0600);
    $dirStat = @stat($dir);
    if (is_array($dirStat)) {
        @chown($tmp, $dirStat['uid']);
        @chgrp($tmp, $dirStat['gid']);
    }

    if (!@rename($tmp, $finalPath)) {
        @unlink($tmp);
        fail("cannot publish secret file at {$finalPath}");
    }
    @chmod($finalPath, 0600);
    if (is_array($dirStat)) {
        @chown($finalPath, $dirStat['uid']);
        @chgrp($finalPath, $dirStat['gid']);
    }

    clearstatcache(true, $finalPath);
    $mode = @fileperms($finalPath);
    if ($mode === false || (($mode & 0777) !== 0600)) {
        @unlink($finalPath);
        fail("secret file mode is not 0600 after publish (refusing world/group-readable secrets)");
    }
}

$host = env('DB_HOST', 'db');
$port = env('DB_PORT', '3306');
$name = env('DB_NAME', 'snep');
$user = env('DB_USER', 'snep');
$pass = env('DB_PASSWORD', '');

$secretPath = secret_path();
$lockPath = lock_path();
$secretDir = dirname($secretPath);

if (!is_dir($secretDir)) {
    // Do not create a host-invisible path inside the container filesystem
    // and treat it as durable -- without the bind mount the operator
    // cannot retrieve the credential.
    fail("secrets directory missing: {$secretDir} (mount ./secrets at /run/senma/secrets)");
}

$lockFh = @fopen($lockPath, 'c+');
if ($lockFh === false) {
    fail("cannot open lock file {$lockPath}");
}
if (!flock($lockFh, LOCK_EX)) {
    fclose($lockFh);
    fail("cannot acquire exclusive lock on {$lockPath}");
}

try {
    try {
        $pdo = new PDO(
            "mysql:host={$host};port={$port};dbname={$name};charset=utf8",
            $user,
            $pass,
            array(PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION)
        );
    } catch (PDOException $e) {
        // TASK-0026H: do not block application startup on transient DB
        // unavailability -- leave the sentinel in place for a later boot.
        fwrite(STDERR, "[bootstrap-admin] could not connect to the database, skipping: " . $e->getMessage() . "\n");
        exit(0);
    }

    $stmt = $pdo->prepare('SELECT id, password FROM users WHERE name = ? LIMIT 1 FOR UPDATE');
    // FOR UPDATE requires a transaction on InnoDB.
    $pdo->beginTransaction();
    $stmt->execute(array('admin'));
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        $pdo->commit();
        // No seeded admin row (e.g. restored DB without users) -- nothing
        // for this bootstrap step to do.
        exit(0);
    }

    if ($row['password'] !== SENTINEL) {
        $pdo->commit();
        // Already bootstrapped or operator-changed -- never regenerate.
        exit(0);
    }

    $plaintext = null;
    if (is_file($secretPath) && is_readable($secretPath)) {
        $existing = file_get_contents($secretPath);
        if (is_string($existing)) {
            $existing = trim($existing);
            // Reject empty / newline-only leftovers.
            if ($existing !== '' && strlen($existing) >= Snep_Security_Password::MIN_LENGTH) {
                $plaintext = $existing;
            }
        }
    }

    if ($plaintext === null) {
        $plaintext = bin2hex(random_bytes(RANDOM_BYTES));
        publish_secret($secretPath, $plaintext);
    }

    $hash = Snep_Security_Password::hash($plaintext);

    $update = $pdo->prepare('UPDATE users SET password = ? WHERE id = ? AND password = ?');
    $update->execute(array($hash, $row['id'], SENTINEL));
    if ($update->rowCount() !== 1) {
        $pdo->rollBack();
        fail("admin credential was changed concurrently; refusing to continue (sentinel no longer present)");
    }
    $pdo->commit();

    fwrite(STDOUT, "\n");
    fwrite(STDOUT, "================================================================\n");
    fwrite(STDOUT, "SENMA initial administrator credentials created.\n");
    fwrite(STDOUT, "\n");
    fwrite(STDOUT, "User: admin\n");
    fwrite(STDOUT, "Password file:\n");
    fwrite(STDOUT, "  " . OPERATOR_SECRET_PATH . "\n");
    fwrite(STDOUT, "\n");
    fwrite(STDOUT, "Change the password after first login.\n");
    fwrite(STDOUT, "Retrieve with: make bootstrap-admin-credentials\n");
    fwrite(STDOUT, "================================================================\n");
    fwrite(STDOUT, "\n");
} finally {
    flock($lockFh, LOCK_UN);
    fclose($lockFh);
}
