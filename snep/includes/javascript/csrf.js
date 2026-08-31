/**
 * TASK-0026G (F20): shared CSRF-token delivery for every POST form and
 * jQuery AJAX mutation in the app, so individual view scripts do not each
 * need their own hidden-field edit. Loaded on every page (see
 * snep/Bootstrap.php::_initViewHelpers()); reads the token from the
 * "csrf-token" <meta> tag layouts/layout.phtml emits from
 * Snep_Security_Csrf::getToken(). See
 * docs/tasks/0026g-session-cookie-csrf-hardening.md.
 *
 * Fails closed on purpose: if this script does not run (JS disabled,
 * blocked, or the meta tag is absent -- e.g. the pre-authentication login
 * layout), forms simply submit without a token and the server-side
 * Snep_CsrfPlugin rejects them with 403, exactly as it must for any other
 * missing/invalid token.
 */
(function ($) {
    if (!$) {
        return;
    }

    var token = $('meta[name="csrf-token"]').attr('content');
    if (!token) {
        return;
    }

    var FIELD = 'snep_csrf_token';

    $(document).on('submit', 'form', function () {
        var $form = $(this);
        if (($form.attr('method') || 'get').toLowerCase() !== 'post') {
            return;
        }
        if ($form.find('input[name="' + FIELD + '"]').length) {
            return;
        }
        $('<input>', {type: 'hidden', name: FIELD, value: token}).appendTo($form);
    });

    // Covers jQuery.post()/.ajax() mutations that do not submit a real
    // <form> element (e.g. route/index.phtml's status-toggle call).
    // ajaxPrefilter (not the ajaxSend event) is used deliberately: it runs
    // early enough in jQuery's own pipeline for a settings.data mutation
    // here to actually reach the outgoing request.
    $.ajaxPrefilter(function (options) {
        var method = (options.type || options.method || 'GET').toUpperCase();
        if (method !== 'POST') {
            return;
        }
        if (typeof options.data === 'string') {
            if (options.data.indexOf(FIELD + '=') !== -1) {
                return;
            }
            options.data = options.data ? options.data + '&' + FIELD + '=' + encodeURIComponent(token) : FIELD + '=' + encodeURIComponent(token);
        } else if (options.data && typeof options.data === 'object') {
            if (!(FIELD in options.data)) {
                options.data[FIELD] = token;
            }
        } else {
            options.data = FIELD + '=' + encodeURIComponent(token);
        }
    });
})(window.jQuery);
