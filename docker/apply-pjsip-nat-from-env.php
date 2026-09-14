<?php
/**
 * TASK-0035E2: optional PJSIP NAT field overrides from environment.
 *
 * When PJSIP_EXTERNAL_SIGNALING_ADDRESS / PJSIP_EXTERNAL_MEDIA_ADDRESS /
 * PJSIP_LOCAL_NET are set, update enabled pjsip_transports rows (and
 * replace pjsip_transport_networks for the local_net list). Empty env
 * vars leave DB state untouched — safe for bridge/dev defaults.
 *
 * Invoked from docker/entrypoint.sh after bootstrap; never prints
 * secrets. Does not hard-code pilot public IPs.
 */

function env_nonempty($name) {
    $v = getenv($name);
    if ($v === false) {
        return null;
    }
    $v = trim((string) $v);
    return $v === '' ? null : $v;
}

$extSig = env_nonempty('PJSIP_EXTERNAL_SIGNALING_ADDRESS');
$extMedia = env_nonempty('PJSIP_EXTERNAL_MEDIA_ADDRESS');
$localNet = env_nonempty('PJSIP_LOCAL_NET');

if ($extSig === null && $extMedia === null && $localNet === null) {
    exit(0);
}

$host = getenv('DB_HOST') ?: 'db';
$port = getenv('DB_PORT') ?: '3306';
$name = getenv('DB_NAME') ?: 'snep';
$user = getenv('DB_USER') ?: 'snep';
$pass = getenv('DB_PASSWORD') ?: '';

try {
    $pdo = new PDO(
        "mysql:host={$host};port={$port};dbname={$name};charset=utf8",
        $user,
        $pass,
        array(PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION)
    );
} catch (PDOException $e) {
    fwrite(STDERR, "[apply-pjsip-nat] DB unavailable, skipping NAT override: " . $e->getMessage() . "\n");
    exit(0);
}

$ids = $pdo->query('SELECT id FROM pjsip_transports WHERE enabled = 1')->fetchAll(PDO::FETCH_COLUMN);
if (!$ids) {
    fwrite(STDOUT, "[apply-pjsip-nat] no enabled transports; nothing to update\n");
    exit(0);
}

$sets = array();
$params = array();
if ($extSig !== null) {
    $sets[] = 'external_signaling_address = ?';
    $params[] = $extSig;
}
if ($extMedia !== null) {
    $sets[] = 'external_media_address = ?';
    $params[] = $extMedia;
}

if ($sets) {
    $sql = 'UPDATE pjsip_transports SET ' . implode(', ', $sets) . ' WHERE enabled = 1';
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
}

if ($localNet !== null) {
    $nets = preg_split('/\s*,\s*/', $localNet);
    $del = $pdo->prepare('DELETE FROM pjsip_transport_networks WHERE transport_id = ?');
    $ins = $pdo->prepare('INSERT INTO pjsip_transport_networks (transport_id, network) VALUES (?, ?)');
    foreach ($ids as $id) {
        $del->execute(array($id));
        foreach ($nets as $net) {
            $net = trim((string) $net);
            if ($net === '') {
                continue;
            }
            $ins->execute(array($id, $net));
        }
    }
}

fwrite(STDOUT, "[apply-pjsip-nat] applied env NAT overrides to " . count($ids) . " enabled transport(s)\n");
exit(0);
