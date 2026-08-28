<?php
/**
 * TASK-0025: a controlled local endpoint used only by
 * `make external-content-smoke` to deterministically serve MALICIOUS
 * vendor-shaped payloads (never real, never the real vendor) to prove
 * every vendor-controlled rendering sink treats remote content as data,
 * not trusted HTML. Kept separate from
 * docker/external-failure-test/router.php (TASK-0024, which simulates
 * transport/HTTP failures, not content). See
 * docs/tasks/0025-vendor-content-xss-hardening.md §8/§9.
 *
 * Started as: php -S 127.0.0.1:<port> router.php
 *
 * Mode is read from a fixed "/mode/<value>/..." PATH PREFIX (matching
 * docker/external-failure-test/router.php's own established
 * convention), never a bare query string, since the real callers
 * (Snep_Notifications, Snep_Version) append a path suffix
 * (uuid, /uuid/id, or ?version=X) after whatever core_config value
 * they're given.
 */

$mode = 'ok';
if (preg_match('#/mode/([a-z0-9_]+)#', $_SERVER['REQUEST_URI'] ?? '', $m)) {
    $mode = $m[1];
}

// The exact payload set from docs/tasks/0025-vendor-content-xss-hardening.md
// §8 -- applied to every free-text vendor field.
$XSS_PAYLOAD = '<script>alert(1)</script><img src=x onerror=alert(1)>"><svg/onload=alert(1)><a href="javascript:alert(1)">click</a> plain: < > " \' &';

switch ($mode) {

    // Snep_Notifications::fetchFromVendor() -- GET {host_notification}/{uuid}
    // Expects a JSON array of notification objects.
    case 'xss_notif_list':
        header('Content-Type: application/json');
        echo json_encode(array(
            array(
                'id' => 1001,
                'title' => $XSS_PAYLOAD,
                'from' => $XSS_PAYLOAD,
                'message' => $XSS_PAYLOAD,
                'creation_date' => date('c'),
                'status' => 'unread',
            ),
            // A second entry whose title is itself a JSON-looking string,
            // to prove no double-decoding occurs anywhere in the pipeline.
            array(
                'id' => 1002,
                'title' => '{"nested":"looks-like-json","evil":"<script>alert(2)</script>"}',
                'from' => 'Sender & Co. <ops@example.invalid>',
                'message' => 'Plain ampersand & quotes " \' test',
                'creation_date' => date('c'),
                'status' => 'read',
            ),
        ));
        break;

    // Snep_Notifications::getNotification($id) -- GET
    // {host_notification}/{uuid}/{id}. Live, uncached, single object.
    case 'xss_notif_single':
        header('Content-Type: application/json');
        echo json_encode(array(
            'id' => 1001,
            'title' => $XSS_PAYLOAD,
            'from' => $XSS_PAYLOAD,
            'message' => $XSS_PAYLOAD,
            'creation_date' => date('c'),
            'status' => 'unread',
        ));
        break;

    // Snep_Version::fetchLatestVersionFromVendor() / getChangelog() --
    // both GET {update_server}/version/latest?version=X.
    case 'xss_version':
        header('Content-Type: application/json');
        echo json_encode(array(
            // A version string that is itself a newer-looking, malicious value.
            'version' => '999.999.999' . $XSS_PAYLOAD,
            'changelog' => "Line one\nLine two with " . $XSS_PAYLOAD . "\nLine three",
        ));
        break;

    // Client-side Announce sink (snep/includes/javascript/notifications.js).
    // Never reached via Snep_Request -- served here only so the fixture
    // is deterministic/local for the static + one-time interactive check
    // described in §9/§21.
    case 'xss_announce':
        header('Content-Type: application/json');
        echo json_encode(array(
            'link' => 'javascript:alert(document.cookie)',
            'image' => 'data:text/html,<script>alert(1)</script>',
            'text' => $XSS_PAYLOAD,
        ));
        break;

    // A harmless control fixture -- ordinary text with special characters,
    // used to prove no double-escaping / display corruption (§17).
    case 'plain_text':
        header('Content-Type: application/json');
        echo json_encode(array(
            array(
                'id' => 2001,
                'title' => 'Café résumé — naïve',
                'from' => 'Ops & Support',
                'message' => 'Quotes: "double" \'single\' and <not a tag> here',
                'creation_date' => date('c'),
                'status' => 'unread',
            ),
        ));
        break;

    // Same fixture as 'plain_text' above, but shaped as a single object
    // -- matches Snep_Notifications::getNotification($id)'s expected
    // response shape (GET {host_notification}/{uuid}/{id}), which is
    // the only live path that actually receives the `from` field (the
    // cached getAll() path never populates it -- see
    // docs/tasks/0025-vendor-content-xss-hardening.md §3).
    case 'plain_text_single':
        header('Content-Type: application/json');
        echo json_encode(array(
            'id' => 2001,
            'title' => 'Café résumé — naïve',
            'from' => 'Ops & Support',
            'message' => 'Quotes: "double" \'single\' and <not a tag> here',
            'creation_date' => date('c'),
            'status' => 'unread',
        ));
        break;

    default:
        http_response_code(400);
}
