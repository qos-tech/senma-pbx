<?php
/**
 * TASK-0033F: SENMA-native database schema migration runner.
 *
 * Usage:
 *   migrate.php           apply every pending migration, in order, stop
 *                         on first failure ("make migrate")
 *   migrate.php --check   read-only: report current/expected schema
 *                         version and pending migrations ("make migrate-check")
 *
 * Exit codes:
 *   0 = SCHEMA_CURRENT (apply: everything applied; check: nothing pending)
 *   1 = migration application failed (apply mode only)
 *   2 = SCHEMA_UNKNOWN -- structural fingerprint did not match any known
 *       baseline; refuses to guess or act (docs/tasks/
 *       0033f-database-bootstrap-resilience-upgrade-path.md
 *       UNKNOWN-SCHEMA HANDLING)
 *   3 = SCHEMA_BEHIND (check mode only -- pending migrations exist)
 *   4 = SCHEMA_AHEAD -- schema_migrations records an id with no matching
 *       file in this codebase's own migrations/ directory (rolled-back
 *       app code against an already-migrated database); refuses to act
 *   5 = could not acquire the migration lock within the bounded timeout
 *       (another runner is already in progress)
 *
 * Standalone script, no Zend/MVC bootstrap -- same convention as
 * docker/bootstrap-admin.php (raw PDO only).
 *
 * Secret safety (Phase 40/41): credentials come only from this
 * container's own environment (the same DB_USER/DB_PASSWORD/DB_NAME
 * setup.conf already uses -- TASK-0033C's post-rotation model, no
 * separate/stale credential path). Never printed. PDO exception
 * messages are driver/SQLSTATE text, not credential-bearing, since no
 * credential ever appears inside a migration file's SQL body. Output
 * never includes a migration file's SQL content, only its id.
 */

const MIGRATIONS_DIR = '/var/www/html/snep/install/database/migrations';
const LOCK_NAME = 'senma_schema_migrations';
const LOCK_TIMEOUT_SECONDS = 10;

function env(string $name, ?string $default = null): ?string {
    $value = getenv($name);
    return $value === false ? $default : $value;
}

function out(string $line): void {
    fwrite(STDOUT, $line . "\n");
}

function err(string $line): void {
    fwrite(STDERR, $line . "\n");
}

/**
 * The one-time structural fingerprint for migration "0000-baseline":
 * the minimum set of tables/columns that must exist for this database
 * to be considered "at least the pre-TASK-0033F current schema" (Phase
 * 7). Deliberately representative, not exhaustive -- every table/column
 * added by a schema-touching commit since this project's Docker-first
 * architecture began (TASK-0018 pjsip_transports, TASK-0026H password
 * widening + login_attempts, TASK-0029A TLS certificate fields).
 *
 * Returns an empty array if the fingerprint matches, or a list of the
 * specific missing tables/columns otherwise (never a boolean alone --
 * an operator seeing SCHEMA_UNKNOWN must be told exactly what is
 * missing, not left to guess).
 */
function fingerprintBaselineMissing(PDO $pdo): array {
    $missing = [];
    $tables = ['core_config', 'users', 'pjsip_transports', 'cdr', 'peers', 'trunks', 'login_attempts'];
    foreach ($tables as $t) {
        $stmt = $pdo->query("SHOW TABLES LIKE " . $pdo->quote($t));
        if (!$stmt->fetch()) {
            $missing[] = "table:{$t}";
        }
    }
    if (!in_array('table:pjsip_transports', $missing, true)) {
        $stmt = $pdo->query("SHOW COLUMNS FROM pjsip_transports LIKE 'cert_file'");
        if (!$stmt->fetch()) {
            $missing[] = 'column:pjsip_transports.cert_file';
        }
    }
    if (!in_array('table:users', $missing, true)) {
        $stmt = $pdo->prepare(
            "SELECT CHARACTER_MAXIMUM_LENGTH FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'password'"
        );
        $stmt->execute();
        $len = $stmt->fetchColumn();
        if ($len === false || (int)$len < 255) {
            $missing[] = 'column:users.password(<255)';
        }
    }
    return $missing;
}

/**
 * The fingerprint for migration "0001-add-cdr-uniqueid-index": does the
 * index this migration adds already exist? True on a fresh install
 * (schema.sql declares it directly, kept in sync with the migration
 * file -- see that file's own header), false on an install provisioned
 * before this task.
 */
function fingerprint0001Missing(PDO $pdo): array {
    $stmt = $pdo->query("SHOW INDEX FROM cdr WHERE Key_name = 'uniqueid'");
    return $stmt->fetch() ? [] : ['index:cdr.uniqueid'];
}

/**
 * Pre-tracker migrations that MAY already be structurally present
 * (baseline candidates). Every migration authored after TASK-0033F is
 * genuinely new -- it is never already present, so it is never listed
 * here and always executes for real the first time it is pending.
 */
function baselineFingerprints(): array {
    return [
        '0000-baseline' => 'fingerprintBaselineMissing',
        '0001-add-cdr-uniqueid-index' => 'fingerprint0001Missing',
    ];
}

function discoverMigrationFiles(): array {
    $files = glob(MIGRATIONS_DIR . '/*.sql');
    sort($files, SORT_STRING);
    $out = [];
    foreach ($files as $f) {
        $id = basename($f, '.sql');
        $out[$id] = $f;
    }
    return $out;
}

function isDestructive(string $path): bool {
    $head = file_get_contents($path, false, null, 0, 4096);
    return $head !== false && str_contains($head, 'SENMA-DESTRUCTIVE');
}

function executeMigrationFile(PDO $pdo, string $path): void {
    $sql = file_get_contents($path);
    if ($sql === false) {
        throw new RuntimeException("could not read migration file");
    }
    // Deliberately simple statement splitting (Phase 19 authoring rule):
    // migrations in this repo are single-purpose DDL/DML with no
    // semicolons inside string literals -- a real multi-statement SQL
    // parser would be more machinery than this small, SENMA-native
    // runner needs (Phase 14/expected-architecture-preference). Comment
    // lines (`--`) are stripped first so a semicolon inside a comment
    // never mis-splits a statement.
    $noComments = preg_replace('/^\s*--.*$/m', '', $sql);
    $statements = array_filter(array_map('trim', explode(';', $noComments)));
    foreach ($statements as $stmt) {
        $pdo->exec($stmt);
    }
}

function main(array $argv): int {
    $mode = (isset($argv[1]) && $argv[1] === '--check') ? 'check' : 'apply';

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
            [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
        );
    } catch (PDOException $e) {
        err("FAIL: could not connect to the database (" . $e->getMessage() . ")");
        return 2;
    }

    // Phase 24/25: bounded advisory lock, never an unbounded wait. Two
    // concurrent invocations of this script must never apply migrations
    // simultaneously -- the second one refuses/waits boundedly, never
    // silently proceeds.
    $lockStmt = $pdo->prepare('SELECT GET_LOCK(?, ?)');
    $lockStmt->execute([LOCK_NAME, LOCK_TIMEOUT_SECONDS]);
    if ((int)$lockStmt->fetchColumn() !== 1) {
        err("FAIL: migration already in progress (could not acquire the schema migration lock within " . LOCK_TIMEOUT_SECONDS . "s)");
        return 5;
    }
    register_shutdown_function(function () use ($pdo) {
        try {
            $pdo->prepare('SELECT RELEASE_LOCK(?)')->execute([LOCK_NAME]);
        } catch (Throwable $e) {
            // best-effort -- the lock also auto-releases when this
            // connection closes, which happens immediately after anyway.
        }
    });

    $pdo->exec(
        "CREATE TABLE IF NOT EXISTS schema_migrations (
            id VARCHAR(64) NOT NULL,
            applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            checksum VARCHAR(64) NOT NULL,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8"
    );

    $applied = [];
    foreach ($pdo->query('SELECT id, checksum FROM schema_migrations') as $row) {
        $applied[$row['id']] = $row['checksum'];
    }

    $files = discoverMigrationFiles();

    if (empty($applied)) {
        // First-ever run against this database (Phase 6: existing-
        // install baseline). Validate the structural fingerprint before
        // recording ANYTHING -- never blindly mark an unverified schema
        // as current (Phase 35/36).
        $missing = fingerprintBaselineMissing($pdo);
        if (!empty($missing)) {
            err("SCHEMA_UNKNOWN: this database matches neither an empty install nor the expected baseline schema.");
            err("Missing/mismatched: " . implode(', ', $missing));
            err("Refusing to guess -- see docs/tasks/0033f-database-bootstrap-resilience-upgrade-path.md UNKNOWN-SCHEMA HANDLING.");
            return 2;
        }

        $fingerprints = baselineFingerprints();
        $baselining = true;
        foreach ($files as $id => $path) {
            if ($baselining && isset($fingerprints[$id])) {
                $fn = $fingerprints[$id];
                if (empty($fn($pdo))) {
                    $checksum = hash_file('sha256', $path);
                    $ins = $pdo->prepare('INSERT INTO schema_migrations (id, checksum) VALUES (?, ?)');
                    $ins->execute([$id, $checksum]);
                    $applied[$id] = $checksum;
                    out("Baselined {$id} (already present, per structural fingerprint)");
                    continue;
                }
                // First migration whose effect is NOT already present --
                // stop baselining, this and everything after it is a
                // real, pending migration to actually apply below.
                $baselining = false;
            } else {
                $baselining = false;
            }
        }
    } else {
        // Phase 20: applied migrations are immutable. A drifted checksum
        // on an already-applied file is surfaced, not silently ignored --
        // WARN in check mode (diagnostic only), FAIL in apply mode
        // (the mutating path deserves the stricter gate).
        foreach ($applied as $id => $storedChecksum) {
            if (!isset($files[$id])) {
                continue; // handled as SCHEMA_AHEAD below
            }
            $current = hash_file('sha256', $files[$id]);
            if ($current !== $storedChecksum) {
                $msg = "applied migration '{$id}' has been modified since it was applied (checksum mismatch) -- applied migrations must be immutable; add a NEW migration instead of editing this one.";
                if ($mode === 'apply') {
                    err("FAIL: {$msg}");
                    return 1;
                }
                err("WARN: {$msg}");
            }
        }
    }

    $ahead = array_diff(array_keys($applied), array_keys($files));
    $pending = array_diff(array_keys($files), array_keys($applied));
    sort($pending, SORT_STRING);

    $currentId = empty($applied) ? '(none)' : max(array_keys($applied));
    $expectedId = empty($files) ? '(none)' : max(array_keys($files));

    if ($mode === 'check') {
        out("Current schema: {$currentId}");
        out("Expected schema: {$expectedId}");
        if (!empty($ahead)) {
            out("SCHEMA_AHEAD: schema_migrations records id(s) not present in this codebase's migrations/ directory:");
            foreach ($ahead as $id) {
                out("  {$id}");
            }
            return 4;
        }
        if (!empty($pending)) {
            out("Pending migrations:");
            foreach ($pending as $id) {
                out("  {$id}" . (isDestructive($files[$id]) ? ' (destructive -- see file header)' : ''));
            }
            return 3;
        }
        out("SCHEMA_CURRENT");
        return 0;
    }

    // apply mode
    if (!empty($ahead)) {
        err("FAIL: SCHEMA_AHEAD -- schema_migrations records id(s) not present in this codebase: " . implode(', ', $ahead));
        err("Refusing to apply further migrations against a database ahead of this code -- see docs/tasks/0033f-database-bootstrap-resilience-upgrade-path.md APP/SCHEMA COMPATIBILITY GATE.");
        return 4;
    }

    if (empty($pending)) {
        out("SCHEMA_CURRENT ({$currentId}) -- nothing to apply");
        return 0;
    }

    foreach ($pending as $id) {
        $path = $files[$id];
        if (isDestructive($path)) {
            out("WARNING: {$id} is marked destructive -- ensure a recent backup exists (make backup) before proceeding.");
        }
        out("Applying {$id}");
        try {
            // Deliberately NO explicit PDO transaction wrapper here.
            // Live-proven during this task: MariaDB/InnoDB DDL (this
            // migration's own `ALTER TABLE ... ADD INDEX`) causes an
            // implicit commit mid-statement, which silently ends any
            // PDO-tracked transaction -- a subsequent explicit commit()
            // then throws "There is no active transaction", and a
            // rollback() on failure would not undo the DDL anyway
            // (Phase 10: "do not claim atomic full-schema bootstrap
            // unless proven" -- reproduced, not assumed). The real
            // safety contract is per-statement idempotency (Phase 19):
            // if a migration fails partway, it is NOT recorded as
            // applied, and a retry re-executes the WHOLE file from the
            // top -- every statement a migration author writes MUST
            // therefore tolerate re-execution safely (this task's own
            // 0001 migration uses `ADD INDEX IF NOT EXISTS` for exactly
            // this reason).
            executeMigrationFile($pdo, $path);
            $checksum = hash_file('sha256', $path);
            $ins = $pdo->prepare('INSERT INTO schema_migrations (id, checksum) VALUES (?, ?)');
            $ins->execute([$id, $checksum]);
            out("Applied");
        } catch (Throwable $e) {
            err("FAIL: migration {$id} failed: " . $e->getMessage());
            err("{$id} was NOT recorded as applied. No later migration was attempted.");
            err("Fix the underlying cause, then rerun 'make migrate' -- every statement in this migration must be safe to re-execute (Phase 19).");
            return 1;
        }
    }

    out("SCHEMA_CURRENT (" . max($pending) . ")");
    return 0;
}

exit(main($argv));
