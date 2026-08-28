<?php
/**
 * TASK-0024: a controlled local endpoint used only by
 * `make external-failure-smoke` to deterministically simulate the
 * vendor API's known failure shapes (HTTP error status, malformed
 * payload, empty/null payload) without ever depending on -- or being
 * able to affect -- the real vendor. Never started outside that test
 * target. DNS failure / connection refused / blackhole timeout / TLS
 * failure are simulated without this server at all (a `.invalid`
 * hostname, a closed local port, an RFC 5737 address, and an
 * https:// request against this same plain-HTTP server, respectively)
 * -- see docs/tasks/0024-external-api-failure-isolation.md §7/§17.
 *
 * Started as: php -S 127.0.0.1:<port> router.php
 *
 * Both real callers (Snep_Notifications::getAll(), Snep_Version::
 * getNewVersions()) APPEND a path/query suffix to whatever
 * core_config value they're given (a session uuid, or
 * "/version/latest?version=X") -- so the mode selector here is read
 * from a fixed "/mode/<value>/..." PATH PREFIX via REQUEST_URI, never
 * a bare query string, since a query string placed in core_config
 * would otherwise get corrupted by that appended suffix.
 * core_config's host_notification/update_server should be set to
 * e.g. "http://127.0.0.1:<port>/mode/500" for this to work.
 */

$mode = 'ok';
if (preg_match('#/mode/([a-z0-9_]+)#', $_SERVER['REQUEST_URI'] ?? '', $m)) {
    $mode = $m[1];
}

switch ($mode) {
    case 'ok':
        // A well-formed notifications-shaped payload.
        header('Content-Type: application/json');
        echo json_encode(array(
            array(
                'id' => 1,
                'title' => 'External failure smoke fixture',
                'message' => 'This is a controlled, local, non-vendor test payload.',
                'creation_date' => date('c'),
                'status' => 'unread',
            ),
        ));
        break;

    case 'version_ok':
        // A well-formed update_server-shaped payload -- deliberately
        // reports the current SNEP_VERSION so getNewVersions() computes
        // "no newer version" (null) rather than fabricating an update.
        header('Content-Type: application/json');
        echo json_encode(array('version' => $_GET['version'] ?? '0.0.0'));
        break;

    case '500':
        http_response_code(500);
        echo 'Internal Server Error';
        break;

    case 'malformed':
        header('Content-Type: application/json');
        echo '{not valid json!!';
        break;

    case 'empty':
        // 200, deliberately empty body.
        break;

    case 'null':
        header('Content-Type: application/json');
        echo 'null';
        break;

    default:
        http_response_code(400);
}
