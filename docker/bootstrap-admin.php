<?php
/**
 * TASK-0026H (F27): fresh-install admin credential bootstrap.
 *
 * Invoked from docker/entrypoint.sh on every app container start.
 * Idempotent and safe to run repeatedly: it only ever acts when the
 * `admin` row's stored password still exactly equals the install seed's
 * sentinel value ('!SENMA-BOOTSTRAP-PENDING!', see
 * snep/install/database/system_data.sql) -- which deliberately cannot
 * authenticate anything (Snep_Security_Password::verify() rejects it
 * against any submitted plaintext), so a fresh install has NO usable
 * admin credential at all until this runs once. Once it replaces the
 * sentinel with a real password_hash()'d random password, every later
 * invocation (container restart, `docker compose up` again, ...) finds a
 * non-sentinel value and does nothing.
 *
 * This is a standalone script, not part of the web application's own
 * request path -- it needs only a raw PDO connection and
 * Snep_Security_Password, not the full Zend/MVC bootstrap.
 *
 * See docs/tasks/0026h-authentication-default-install-hardening.md.
 */

require_once '/var/www/html/snep/lib/Snep/Security/Password.php';

const SENTINEL = '!SENMA-BOOTSTRAP-PENDING!';

function env($name, $default = null) {
    $value = getenv($name);
    return $value === false ? $default : $value;
}

$host = env('DB_HOST', 'db');
$port = env('DB_PORT', '3306');
$name = env('DB_NAME', 'snep');
$user = env('DB_USER', 'snep');
$pass = env('DB_PASSWORD', '');

try {
    $pdo = new PDO(
        "mysql:host={$host};port={$port};dbname={$name};charset=utf8",
        $user,
        $pass,
        array(PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION)
    );
} catch (PDOException $e) {
    // TASK-0026H: do not block application startup on this -- the app
    // container's own health check / the rest of entrypoint.sh already
    // depends on the db service being healthy first; a transient
    // connection issue here should be visible in logs, not fatal to boot.
    fwrite(STDERR, "[bootstrap-admin] could not connect to the database, skipping: " . $e->getMessage() . "\n");
    exit(0);
}

$stmt = $pdo->prepare('SELECT id, password FROM users WHERE name = ? LIMIT 1');
$stmt->execute(array('admin'));
$row = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$row) {
    // No seeded admin row at all (e.g. a database restored from
    // elsewhere) -- nothing for this bootstrap step to do.
    exit(0);
}

if ($row['password'] !== SENTINEL) {
    // Already bootstrapped (or changed by an operator) -- idempotent no-op.
    exit(0);
}

$plaintext = bin2hex(random_bytes(16));
$hash = Snep_Security_Password::hash($plaintext);

$update = $pdo->prepare('UPDATE users SET password = ? WHERE id = ?');
$update->execute(array($hash, $row['id']));

fwrite(STDOUT, "\n");
fwrite(STDOUT, "================================================================\n");
fwrite(STDOUT, "SENMA PBX: initial admin credential generated (TASK-0026H, F27)\n");
fwrite(STDOUT, "----------------------------------------------------------------\n");
fwrite(STDOUT, "  username: admin\n");
fwrite(STDOUT, "  password: {$plaintext}\n");
fwrite(STDOUT, "----------------------------------------------------------------\n");
fwrite(STDOUT, "This is shown ONCE. Log in and change it via Users > admin.\n");
fwrite(STDOUT, "================================================================\n");
fwrite(STDOUT, "\n");
