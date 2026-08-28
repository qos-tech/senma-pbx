# TASK-0025 — Vendor-controlled content XSS hardening

## Status

**Phase A investigation complete; bounded remediation loop (max 5
iterations) in progress/complete — see §16 onward.** Mode: BOUNDED LOOP
MODE, max 5 remediation iterations, per instruction.

Scope: **only** first-party vendor/API response data and the rendering
paths that consume it (`Snep_Notifications`, `Snep_Version`,
`SystemstatusController::CloudNotice()`, and one additional vendor
integration discovered while tracing the required shared-layout reading
— §6). Not a whole-application XSS audit.

Release principle: **remote content is data, not trusted HTML.**

---

## 1. Read first — confirmed read in full before any edit

`CLAUDE.md`, `docs/tasks/0024-external-api-failure-isolation.md`,
`snep/lib/Snep/Notifications.php`, `snep/lib/Snep/Version.php`,
`SystemstatusController::CloudNotice()` (and the surrounding
`indexAction()`), `snep/modules/default/views/layouts/layout.phtml`,
`snep/modules/default/views/layouts/login.phtml`,
`snep/lib/Snep/Request.php`, `snep/modules/default/controllers/
NotificationsController.php`, `snep/modules/default/views/scripts/
notifications/index.phtml`, `snep/modules/default/controllers/
NewversionController.php`, `snep/modules/default/views/scripts/
newversion/index.phtml`, `snep/includes/javascript/notifications.js`.

---

## 2. Existing escaping facilities (§8) — inventory

- **`Zend_View_Abstract::escape($var)`**, available in every view
  script as `$this->escape(...)` and in every controller as
  `$this->view->escape(...)`: confirmed by reading
  `snep/lib/Zend/View/Abstract.php` to be
  `htmlspecialchars($var, ENT_COMPAT, $this->_encoding)`, with
  `_escape` defaulting to `'htmlspecialchars'` and `_encoding`
  defaulting to `'UTF-8'` — **no app-level override found anywhere**
  (`grep -rn "setEscape\|setEncoding"` across `snep/lib/Snep` and
  `snep/includes`: zero matches).
- **`ENT_COMPAT` matters**: escapes `"` but **not** `'`. Safe for every
  sink found in this investigation because every vendor-field sink
  identified below sits inside a **double-quoted** attribute or a
  plain text node — never a single-quoted attribute. Noted explicitly
  because it would **not** be sufficient if a single-quoted attribute
  sink existed (none found).
- **Charset**: confirmed live — `curl -I` against a real page returns
  `Content-Type: text/html; charset=UTF-8`, matching `Zend_View`'s
  `'UTF-8'` default exactly. No mismatch.
- **`nl2br()`**: PHP built-in, used for the one field genuinely
  requiring line-break formatting (§10).
- **`json_encode()` with the `JSON_HEX_*` flags**: PHP built-in,
  used for the one field embedded in inline JavaScript (§11).
- **No HTML purifier/sanitizer library is bundled** anywhere in
  `snep/lib` (confirmed via `find`/`grep` for `purifier`, `htmlpurifier`,
  `sanitiz`). Not needed — no sink in this investigation requires
  preserving arbitrary vendor markup (§5's "default assumption: plain
  text" holds for every field found).

No new dependency added. Every fix in this task uses only
`htmlspecialchars()` (via the existing `$this->escape()`/`$this->
view->escape()` helper), `nl2br()`, `json_encode()`, or the browser's
native `URL` parser (client-side) — all already present.

---

## 3. `Snep_Notifications` — trust-boundary map

Vendor contract fields observed (from the live, uncached
`getNotification($id)` path, which returns the raw vendor JSON
un-reshaped — the most complete view of the actual contract):
`id`, `title`, `from`, `message`, `creation_date`, `status`.

| Field | Parsing | PHP repr. | Transform | View/helper | Final context | Classification |
|---|---|---|---|---|---|---|
| `title` | `json_decode()` | `string` (stdClass prop) | none | `NotificationsController::indexAction()` (controller-built string) → `notifications/index.phtml` (`echo`) | HTML text node | **A** |
| `from` | `json_decode()` | `string` | none | same two sinks | HTML text node | **A** |
| `message` | `json_decode()` | `string` | `substr(...,0,30)` in both sinks | same two sinks | HTML text node | **A** |
| `creation_date` | `json_decode()` | `string` | `strtotime()` → `date('d/m/Y G:i:s', ...)` | same two sinks | HTML text node, but **PHP-computed**, not raw pass-through | **A, already safe** |
| `id` (→ cached as `id_itc`) | `json_decode()` | `int`/`string` | stored in `core_notifications.id_itc` (`int(11)`) | `notifications/index.phtml` (`href="...?id=<?php echo $notification->id ?>"`) | HTML attribute (double-quoted) | **B** |
| `status` | `json_decode()` | `string` | compared with `=='unread'`/`=='read'` | never echoed, only branched on | — | **F** |

Two independent rendering paths consume this data:
1. **`Snep_Notifications::getAll()`** (TASK-0024-cached, TTL 60s) →
   `NotificationsController::indexAction()`'s `id=all` branch →
   `notifications/index.phtml`'s table.
2. **`Snep_Notifications::getNotification($id)`** (live, **uncached**,
   1s timeout, untouched by TASK-0024's caching work) →
   `NotificationsController::indexAction()`'s single-notification
   branch → a raw HTML string built directly in the **controller**
   (`$html[$cont] .= "<h2>".$notification->title."</h2>"` etc.) →
   echoed verbatim by `notifications/index.phtml`'s
   `foreach($this->html as $key => $html): echo $html; endforeach;`.

**Zero escaping in either path before this task.** `layout.phtml`
itself only reads `Snep_Notifications::getNoView()` for an unread
**count** (`count($noView)`) — it does **not** render any
title/message content directly, so the shared-layout blast radius for
notification *content* (not just presence) is narrower than TASK-0024's
own §2 finding implied; the actual content-rendering sinks are
`/notifications` itself (an explicit, authenticated, user-navigated
page), not every layout-rendered page.

**Dead code found, not live, not fixed** (documented, matching this
project's existing dead-code-identification convention from TASK-0024):
`Snep_Notifications::getNotifications($url)` — a full unescaped-HTML-
string builder for the exact same fields — has **zero callers anywhere
in the codebase** (`grep -rn "getNotifications("` across every
`.php`/`.phtml`/`.js` file: the only two matches are its own
declaration and an unrelated same-named client-side JS function, also
already confirmed dead by TASK-0024 §14). Classification: **F — not
rendered.** Left as-is; a future reactivation of this method would
need the same treatment applied below.

**Pre-existing, unrelated debt found, documented, not fixed**: TASK-
0024's `getCachedNotifications()` never populates `->from` (the
`core_notifications` table has a `from` column, `replaceCachedNotifications()`
never writes it) — so `notifications/index.phtml`'s "all" table always
renders an empty sender for cached (i.e. `id=all`) notifications, a
functionality gap, not a security issue. Out of this task's scope
(XSS only); noted for a future task.

---

## 4. `Snep_Version` — trust-boundary map

| Field | Parsing | PHP repr. | Transform | View/helper | Final context | Classification |
|---|---|---|---|---|---|---|
| `version` (→ `getNewVersions()`'s return) | `json_decode()` | `string` | `version_compare()`-gated (only returned if genuinely newer) | `SystemstatusController::indexAction()` → `layout.phtml:100` (`echo $this->new_version`) | HTML text node | **A** |
| same field, same value | — | `string` | — | `systemstatus/index.phtml:414` (`var new_version = "<?php echo $this->new_version; ?>";`) | **inline JavaScript string literal** | **D** |
| `changelog` (→ `getChangelog()`'s return) | `json_decode()` | `string` | `preg_replace("/\n/","<br>", ...)` — **deliberately converts to HTML before this task** | `newversion/index.phtml` (`echo $this->changelog`) | HTML **raw fragment** | **E** |

No download/release URL field exists in the vendor contract observed
(only `version` and `changelog` are read anywhere in `Snep_Version.php`
— confirmed by reading the full 169-line file). §10 (URL handling)
therefore has **no applicable field** for `Snep_Version`.

`layout.phtml:100`'s sink is reachable on **every** layout-rendered
page in principle, but `$this->new_version` is a view property set
**only** by `SystemstatusController::indexAction()` (confirmed via
`grep -rn "new_version"`: the only assignment site) — so in practice it
only ever carries a non-empty vendor value when the current request
*is* `/systemstatus`; on every other page the property is simply unset
(Zend_View returns an empty string, no crash, nothing rendered).

---

## 5. `SystemstatusController::CloudNotice()` — trust-boundary map

Read in full (§ TASK-0024's own implementation, unchanged by this
task). `CloudNotice()` is a fire-and-forget telemetry **push** — it
sends local host info **to** the vendor. Its HTTP response
(`$request`/`$put_request`) is assigned but **never read again beyond
`$request['response_code']`** — confirmed via the complete method body:
no `$request['response']`, no `json_decode()` of the response, no view
property ever set from it. **Classification: F — not rendered, for
every field, because the response body is never parsed or used at
all.** TASK-0024's own finding stands; caching (TASK-0024) does not
change this, since there is no cached data-for-display here in the
first place (only a TTL "attempt frequency" marker, itself
locally-generated, not vendor content).

---

## 6. Additional vendor integration discovered while tracing shared layout code

**Not one of the three originally named integrations.** Found while
reading `login.phtml` (required reading: "shared layout/view code that
renders vendor data") and its script dependency,
`snep/includes/javascript/notifications.js`.

`notifications.js` defines `announce_url =
'http://api.opens.com.br/announce'` — the **same vendor host** as
`host_notification`/`update_server`/`host_inspect`, but a **fourth,
independent endpoint**, called **client-side**, directly from the
browser (`XMLHttpRequest`, not `Snep_Request` — entirely outside PHP,
entirely outside TASK-0024's server-side failure-isolation work).

**Live call chain, confirmed via `grep`:**
```
login.phtml:32   <body onload="getAnnounce(session);">
                 -- session here is $this->language (a server-rendered
                    language code, e.g. "pt_BR"), NOT the PHP session
                    object -- confirmed by reading login.phtml:21
                    (var session = "<?php echo $this->language; ?>";)
notifications.js:58   getAnnounce(language)
                 -> XMLHttpRequest GET http://api.opens.com.br/announce/<language>
                 -> handlerAnnounce() on load
notifications.js:86-116  handlerAnnounce()
                 var data = { image: response.image, link: response.link, text: response.text };
                 if (data.image && data.link) {
                   element.setAttribute("href", data.link);     // <a id="announce">
                   element.setAttribute("alt", data.text);
                   imageElement.setAttribute("src", data.image); // <img id="announce-img">
                 } else { useDefaultAnnounce(); }
```
`login.phtml:65-67` confirms the target elements exist and are real,
live DOM nodes on the **unauthenticated** login page:
```html
<a id="announce" target=_blank><img id="announce-img"></a>
```

| Field | Parsing | Sink | Final context | Classification |
|---|---|---|---|---|
| `link` | `JSON.parse()` (browser) | `element.setAttribute("href", data.link)` on a real `<a>` | **URL/href** | **C** |
| `image` | `JSON.parse()` | `imageElement.setAttribute("src", data.image)` on a real `<img>` | **URL/src** | **C** |
| `text` | `JSON.parse()` | `element.setAttribute("alt", data.text)` | HTML attribute, but **set via the DOM API, not string concatenation** — `setAttribute()` cannot inject markup or break out of the element regardless of content; no escaping is meaningful or needed here | **B, already safe by construction** |

**`link`/`image` are genuine active-URL sinks**: `setAttribute("href",
"javascript:...")` on an `<a>` element creates a real, clickable link
that executes arbitrary JavaScript in the SENMA origin when activated
by any visitor to the **pre-authentication** login page — exactly the
scenario item 10/23 exist to prevent. `<img src="javascript:...">`
does not execute in current browsers, but is still tightened for
defense-in-depth using the same fix.

This is squarely **vendor-controlled data** (`api.opens.com.br`, the
same vendor as every other integration in scope), discovered while
reading exactly the files this task's own "Read first" list required,
and does not require a generic sanitizer, CSP, or new dependency to
fix — the browser's own `URL` parser (already available, zero new
dependencies) is sufficient for scheme validation. No stop condition
(§23) is triggered. Included in the remediation loop as iteration 5.

**Also confirmed dead, not live, not touched**:
`snep/modules/default/views/layouts/login-old.phtml` (`onload=
"getAnnounce()"`, same unsafe pattern) — `grep -rn "setLayout"` across
every controller confirms **only** `'login'` (never `'login-old'`) is
ever selected as the login layout (`AuthController.php`, 3 call sites,
all `'login'`). `login-old.phtml` is unreachable dead markup.

**Not investigated further, explicitly out of this task's named
scope** (§1's exact integration list + §6's own discovery boundary):
`RegisterController`'s vendor cloud-registration call and
`PortabilityAction`'s vendor portability lookup — both already
classified by TASK-0024 as separate, explicit-action-only integrations
with their own failure handling; neither was encountered while tracing
the required reading list for this task. Recorded as remaining debt
(§26).

---

## 7. Cache trust boundary (§7 of the instructions)

Explicitly confirmed: **remote → cache does NOT mean trusted.**
`core_notifications` (TASK-0024's cache table) stores the vendor's
**raw, canonical, unescaped** text — `replaceCachedNotifications()`
writes `(string) ($entry->title ?? '')` etc. with no transformation.
This is the **correct** design per this task's own §7 guidance ("prefer
storing canonical data and escaping at output") — it does *not* need
to change. The fix in this task adds escaping **only** at the two
render-time sinks (§3), never at the cache-write layer, so:
- the same cached row can be safely rendered in any future context
  without re-deriving canonical data, and
- no risk of storing an "escaped for HTML" representation that would
  be wrong if ever rendered somewhere else (e.g. inside an email, a
  JSON API response, or a JS string).

`Snep_Version`'s cache (`core_config`'s `update_server_latest_version`)
is likewise raw/canonical — a bare version string, escaped only at
each of its two render sites (§4), independently, using the
context-correct method for each (`escape()` for the HTML text node,
`json_encode()` for the JS string) — proving the "escape at output,
not storage" principle handles even a single cached value rendered in
two *different* contexts correctly, which a single stored
"pre-escaped" representation could not.

---

## 8. Malicious fixture design (§13)

New, dedicated, deterministic local endpoint —
`docker/external-content-test/router.php` — **never the real vendor**,
kept **separate from** `docker/external-failure-test/` (TASK-0024's own
fixture), matching this task's own instruction to keep the smoke
target narrowly named and separate.

Payload set (applied to every free-text vendor field —
`title`/`from`/`message`/`changelog`/`version`):
```
<script>alert(1)</script>
<img src=x onerror=alert(1)>
"><svg/onload=alert(1)>
javascript:alert(1)
<a href="javascript:alert(1)">click</a>
plain text containing: < > " ' &
```
Plus a syntactically-valid-but-hostile nested JSON shape (a
notification whose `title` is itself a JSON-looking string, to confirm
no double-decoding occurs) and a scheme-malicious `announce` fixture
(`link`/`image` set to `javascript:alert(document.cookie)` and
`data:text/html,<script>alert(1)</script>`) for the client-side sink.

`id`/`id_itc` fields in the malicious notification fixtures are kept as
plain integers deliberately — **not** part of this task's payload set.
Reason: `core_notifications.id_itc` is `int(11)`; a non-numeric vendor
`id` is a separate, pre-existing, strict-SQL-adjacent concern (same
class as TASK-0023's own findings), not an XSS concern, and mixing it
into this fixture would conflate two unrelated failure classes. Noted
as discovered-but-out-of-scope debt (§26), not tested or fixed here.

---

## 9. `make external-content-smoke` — design (§14)

New target, deliberately separate from `make external-failure-smoke`.
Deterministic, no Internet dependency, uses only
`docker/external-content-test/router.php`.

**What it can prove via deterministic server-output assertions**
(§15 — "prefer deterministic server-output assertions first"):
- The malicious fixture reaches the real HTTP response body (proves the
  test is exercising the real code path, not a mock).
- `<script>` tags from vendor fields never appear unescaped in the
  response HTML (`grep -c '<script>alert(1)</script>' body` must be
  **zero** in the raw form; the **escaped** form
  `&lt;script&gt;alert(1)&lt;/script&gt;` must be present, proving
  the payload reached the sink and was neutralized, not silently
  dropped).
- `onerror=`/`onload=` from vendor fields never appear as **live**
  attributes on a real tag (same escaped-vs-raw distinction).
- The `id`-in-href attribute cannot be used to break out of the
  `href="..."` attribute.
- Ordinary text (`café`, `naïve`, accented/UTF-8 content) still
  displays correctly (round-trips through `htmlspecialchars(...,
  ENT_QUOTES, 'UTF-8')` unchanged in *meaning*, only entity-encoded
  where required).
- `& < > " '` individually render as their correct visible characters
  after browser entity-decoding (verified by checking the **encoded**
  form is the correct single-level encoding — `&amp;`, `&lt;`, `&gt;`,
  `&quot;`, `&#039;` — not double-encoded `&amp;lt;`).
- The cached (`id=all`) path and the live single-fetch path are **both**
  covered with the same payload set.
- Shared layout still renders (unrelated pages stay 200).
- System Status still renders with a malicious `new_version` value,
  both the HTML text-node sink and the inline-JS sink.
- `newversion` page renders a malicious `changelog` as inert text with
  preserved line breaks.

**Gap explicitly acknowledged, per §15's own instruction to STOP and
report rather than claim unproven coverage**: the §6 client-side
Announce sink's fix (a JavaScript `URL`-based scheme check) cannot be
proven by a server-output assertion alone, because the vulnerable (and
now fixed) code executes **in the browser**, not on the server — the
server only ever serves the JS *source file* and the malicious JSON
fixture; whether `setAttribute("href", "javascript:...")` actually gets
called is a client-side runtime fact. `make external-content-smoke`
proves, deterministically and without a browser: (a) the shipped
`notifications.js` contains the scheme-validation function guarding
both `setAttribute` calls (a static source-content assertion), and (b)
the fixture endpoint serves the exact malicious `link`/`image` payloads
unmodified (proving the test exercises the real fixture, not a
simplified stand-in). The dynamic claim — "the browser never actually
sets a `javascript:` href" — was additionally verified once,
interactively, using real browser automation (Claude in Chrome, already
available to this session; **not** added to the project's own
dependencies or `make` targets) against the same fixture. See §21 for
that result. This is the gap called out by this task's own §15
instruction, resolved by combining a static assertion with a one-time
interactive verification rather than either alone, and rather than
adding Playwright/Selenium to the project.

---

## 16. Bounded remediation loop — iteration log

5 of 5 iterations used (task maximum). Every iteration: syntax-checked
(`php -l`), tested against the malicious fixture via the real HTTP
flow, then confirmed via `make external-content-smoke` at the end (§17).
No stop condition (§23) was triggered at any point — every sink found
was vendor-controlled, same trust-boundary class, same task scope, and
fixable with an existing facility.

### Iteration 1 — `NotificationsController.php`, single-notification HTML

- **Source field**: `title`/`from`/`message`, from `Snep_Notifications::
  getNotification($id)` (live, uncached vendor fetch).
- **Output context**: HTML text node (`<h2>`/`<h5>`/`<p>`), built as a
  raw string directly in the controller.
- **Unsafe behavior before**: `"<h2>".$notification->title."</h2>"` —
  zero escaping.
- **Fix**: `$this->view->escape((string) $notification->title)` (and
  `->from`, `->message`), casting to `(string)` first so a
  null/failed fetch degrades to `""` rather than emitting a new PHP
  8.1+ deprecation notice. `creation_date` deliberately left untouched
  (already PHP-computed, not raw vendor text).
- **Verified**: `curl` against the real `/notifications?id=1` flow with
  the `xss_notif_single` fixture — zero raw `<script>`/`<img
  onerror>`/`<svg onload>`/`javascript:` href, escaped form present,
  zero new PHP Fatal Errors.

### Iteration 2 — `notifications/index.phtml`, "all notifications" table

- **Source field**: `from`/`title`/`message` (text nodes) and `id`
  (HTML attribute, inside `href="...?id=..."`), from
  `Snep_Notifications::getAll()` (TASK-0024-cached).
- **Output context**: HTML text node (A) for from/title/message; HTML
  attribute (B) for id.
- **Unsafe behavior before**: all four echoed raw.
- **Fix**: `$this->escape((string) (...))` for every field, applied
  **after** `substr()` truncation (so a multi-byte/entity boundary is
  never split mid-entity), including `id` even though it is normally
  numeric.
- **Verified**: `curl` against `/notifications?id=all` with the
  `xss_notif_list` fixture (two entries: the full payload set, and a
  JSON-looking nested-string title) — zero raw markup, escaped form
  present, both fixture ids reachable as safe attribute values, the
  nested-JSON title renders as fully inert single-encoded text (no
  double-decoding).

### Iteration 3 — `Snep_Version::getChangelog()`

- **Source field**: `changelog`, from the `update_server` vendor
  endpoint.
- **Output context**: HTML raw fragment (E) — the only field in this
  investigation where the *original* code deliberately converted
  vendor text into HTML (`\n` → `<br>`).
- **Unsafe behavior before**: `preg_replace("/\n/","<br>",
  $changelog->changelog)` on **unescaped** text, then echoed raw in
  `newversion/index.phtml`.
- **Fix**: escape first (`htmlspecialchars(..., ENT_QUOTES, 'UTF-8')`),
  **then** `nl2br()` (replacing the manual `preg_replace`) — preserves
  the one genuine formatting need (line breaks) while treating
  everything else as inert text. Added an `is_object()`/`isset()` guard
  so a malformed 200 response degrades to `"No changelog update"`
  rather than a null-property warning.
- **Intentional UX difference (§19)**: a changelog containing literal
  HTML (e.g. `<b>text</b>`) now displays as visible literal text, not
  bold — the vendor contract never promised markup beyond line breaks,
  so this narrows to the behavior already intended, not a feature loss.
- **Verified**: `curl` against `/newversion` with the `xss_version`
  fixture — zero raw `<script>`, escaped form present, `<br />` line
  breaks preserved.

### Iteration 4 — `new_version`: `layout.phtml` text node + `systemstatus/index.phtml` JS string

- **Source field**: the same `Snep_Version::getNewVersions()` return
  value, rendered in **two different contexts**.
- **Output context**: HTML text node (A) in `layout.phtml:100`; inline
  JavaScript string literal (D) in `systemstatus/index.phtml:414`.
- **Unsafe behavior before**: `echo $this->new_version;` (text node,
  unescaped) and `var new_version = "<?php echo $this->new_version;
  ?>";` (JS string, unescaped — a `"` in the vendor value would break
  out of the string; `</script>` would break out of the element).
- **Fix**: `$this->escape((string) $this->new_version)` for the text
  node; `json_encode((string) $this->new_version, JSON_HEX_TAG |
  JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT)` — **no manual
  surrounding quotes**, since `json_encode()` already produces a
  self-quoting literal — for the JS string, per this task's own §11
  instruction to prefer JSON encoding over HTML escaping in JS context.
- **Verified**: `curl` against `/systemstatus` with the `xss_version`
  fixture — the JS line shows every dangerous character as `<`/
  `>`/`"`/`'`/`&`, zero `</script>` breakout, zero
  raw `<script>`. Also confirmed an unrelated layout-rendered page
  (`/extensions`) still renders HTTP 200 with `$this->new_version`
  simply unset (no error from calling `escape()` on an unset property).
- **Noted, not a live-reachability claim**: `SystemstatusController::
  indexAction()` — the only code that ever sets `$this->view->
  new_version` — calls `disableLayout()`, so `layout.phtml` is never
  actually rendered in the same request. The `layout.phtml` fix is
  therefore likely defensive (protects against a future caller setting
  this property on a layout-enabled page) rather than closing a
  currently-reachable path — fixed anyway, since "remote content is
  data, not trusted HTML" is a blanket principle, not a
  reachability-gated one.

### Iteration 5 — `notifications.js`, Announce handler (§6's new-discovery integration)

- **Source field**: `link`, `image` (both URL sinks), from
  `http://api.opens.com.br/announce/<language>` — a fourth vendor
  integration found while reading the required shared-layout files,
  not one of the three originally named.
- **Output context**: URL/href (C) via `element.setAttribute("href",
  data.link)` on a real `<a>`; URL/src (C) via `imageElement.
  setAttribute("src", data.image)` on a real `<img>`. (`text` → `alt`
  via `setAttribute` needed no fix — the DOM API cannot be used to
  inject markup regardless of content.)
- **Unsafe behavior before**: no scheme validation at all — a vendor
  response with `"link": "javascript:..."` created a real, clickable,
  script-executing link on the **unauthenticated** login page.
- **Fix**: `isSafeAnnounceUrl(value)`, using the browser's native `URL`
  parser (`new URL(value, window.location.href)`) to resolve the
  effective scheme and allow only `http:`/`https:` — deliberately a
  scheme check only, not a domain allowlist (§10: no stable vendor
  domain contract was established, and none was requested). Both
  `setAttribute` calls now gated on `isSafeAnnounceUrl(data.link) &&
  isSafeAnnounceUrl(data.image)`; on failure, falls back to the
  existing `useDefaultAnnounce()` path (same UX as "vendor didn't
  respond usefully").
- **Verified two ways** (§9's own documented gap resolution):
  1. **Static**: `make external-content-smoke` asserts the shipped
     `notifications.js` contains `isSafeAnnounceUrl` guarding both
     `setAttribute` calls, and that the fixture endpoint serves the
     exact malicious payload unmodified.
  2. **Interactive, one-time** (Claude in Chrome, not added to the
     project): loaded the real login page, invoked the **actual
     shipped** `handlerAnnounce()`/`isSafeAnnounceUrl()` functions
     in-page against a malicious fixture
     (`link="javascript:alert(document.cookie)"`,
     `image="data:text/html,<script>alert(1)</script>"`) — result: the
     `#announce`/`#announce-img` DOM attributes were **never** updated
     with the malicious values (fell through to
     `useDefaultAnnounce()`'s safe default, unchanged). A **benign**
     `https://` fixture was then applied and correctly **did** update
     both attributes — confirming legitimate functionality still
     works. Direct scheme-check probes additionally confirmed
     `javascript:`, `data:`, `vbscript:`, leading-whitespace-obfuscated
     (`"   javascript:..."`), tab-obfuscated (`"java\tscript:..."`),
     and newline-obfuscated variants are all correctly rejected, while
     `http:`/`https:` (including case-insensitive `HTTPS:`) and
     relative paths (correctly inheriting the current page's safe
     scheme) are correctly allowed — evidence that the native `URL`
     parser is robust against exactly the obfuscation tricks a
     hand-rolled regex would typically miss.

---

## 17. `make external-content-smoke` — final results

```
PASS: 14   FAIL: 0
```

All 5 iterations' server-rendered assertions pass, plus the two
double-escaping checks (§18) and the shared-layout/System-Status
sanity checks. Full transcript available by re-running `make
external-content-smoke`.

---

## 18. Double-escaping validation (§17 of the instructions)

Verified explicitly, using a dedicated `plain_text`/`plain_text_single`
fixture (UTF-8 accented text, `&`, quotes, a literal `<not a tag>`):
- `Café résumé — naïve` (title) renders byte-for-byte unchanged — UTF-8
  text outside the five characters `htmlspecialchars()` touches is
  never altered.
- `Ops & Support` (from, live single-fetch path) renders as `Ops &amp;
  Support` — a **single** level of encoding, not `&amp;amp;`.
- `Quotes: "double" 'single' and <not a tag> here` (message, truncated
  to 30 chars by `substr()` before escaping) renders as `Quotes:
  &quot;double&quot; 'single' and` — double quotes correctly encoded
  (matters for the double-quoted attribute sink, §2's `ENT_COMPAT`
  finding), single quotes correctly left as literal `'` (safe and
  correct in a text-node context; `ENT_COMPAT`, not `ENT_QUOTES`, is
  what `$this->escape()` uses, and no single-quoted attribute sink
  exists anywhere in this investigation to require otherwise).
- No `&amp;amp;`, `&amp;lt;`, or `&amp;quot;` found anywhere in either
  response — proving the cache round-trip (§7: raw canonical text
  stored, escaped only at render) never accidentally escapes twice.

---

## 19. Availability regression check (§18 of the instructions)

`make external-failure-smoke` re-run in full after every fix landed:

```
PASS: 27   FAIL: 0
```

Confirms TASK-0025's escaping changes do not regress TASK-0024's core
requirement — vendor unavailability still degrades to the existing
safe/empty states, still within the same latency bounds, no new
failure mode introduced by adding `escape()`/`json_encode()`/`nl2br()`
calls (all of which safely handle `""`/`null`-cast-to-`""` inputs,
already exercised by TASK-0024's own transport-failure paths since a
failed fetch now returns empty/false values through the exact same
render code this task modified).

---

## 20. Full regression suite (§22 of the instructions)

| Suite | Result | Notes |
|---|---|---|
| `make smoke` | 16/16 | clean |
| `make call-smoke` | 17/18 | 1 known, pre-existing CDR/report timezone artifact (docs/tasks/0024-external-api-failure-isolation.md §40) — session re-entered the same nightly UTC/local day-boundary skew window; not a TASK-0025 regression |
| `make trunk-smoke` | 21/23 | 2 instances of the same artifact (outbound + inbound reporting checks); not a regression |
| `make transport-smoke` | 63/63 | clean |
| `make restart-smoke` | 37/37 | clean |
| `make external-failure-smoke` | 27/27 | clean (§19) |
| `make external-content-smoke` | 14/14 | clean (§17) |

No test failure traced to any TASK-0025 code change. The CDR/report
timezone artifact is the exact same pre-existing, documented,
out-of-scope issue TASK-0024 already recorded — reproduced again here
only because this session's wall-clock time happened to fall inside
the same ~3-hour nightly skew window; not re-investigated further, not
fixed, per this task's own scope and CLAUDE.md's bug/debt policy.

**Operational note**: during validation, a manual debugging step
temporarily pointed `host_notification` at the local test router and
was not restored before the final `make external-content-smoke` run,
which — faithfully following its own backup/restore design — backed up
and restored that incorrect value instead of the real one. Caught by
inspecting `git status`/the live `core_config` table before finalizing
this document (this project's own established pre-commit discipline),
not by the test suite itself (which has no way to know what the "real"
vendor value should be). Corrected via direct SQL restore
(`host_notification` → `http://api.opens.com.br/v2/notifications`),
re-verified with a clean `make smoke` run afterward. Recorded here
transparently rather than omitted, per this project's own
"correct documentation when later evidence disproves an earlier
assumption" rule (CLAUDE.md).

---

## 21. Answers

1. **Can vendor content currently execute arbitrary browser script?**
   No, not after this task. Before this task: yes, in five confirmed
   ways — three server-rendered HTML/JS-string sinks
   (`Snep_Notifications`' title/from/message, `Snep_Version`'s
   changelog and new-version string) and one client-side URL-scheme
   sink (`notifications.js`'s Announce handler, reachable
   pre-authentication on the login page).
2. **Which exact sinks were vulnerable?** All five listed in §16's
   iteration log: (1) `NotificationsController.php`'s controller-built
   single-notification HTML; (2) `notifications/index.phtml`'s "all
   notifications" table; (3) `Snep_Version::getChangelog()`'s raw
   `\n`→`<br>` HTML fragment; (4) `new_version` in both `layout.phtml`
   (HTML text node) and `systemstatus/index.phtml` (inline JS string);
   (5) `notifications.js`'s `handlerAnnounce()` `href`/`src`
   `setAttribute` calls.
3. **Is all vendor content now treated as data by default?** Yes, for
   every field found in the four vendor integrations traced (§3–§6).
   `CloudNotice()`/`host_inspect` needed no change — its response body
   is never parsed or rendered at all (context F, confirmed by reading
   the complete method).
4. **Are any fields still allowed to contain markup?** Only one,
   narrowly: `Snep_Version::getChangelog()`'s line breaks (`\n` →
   `<br>`), and only that single, code-controlled transformation — the
   vendor's own text is fully escaped first, so the vendor cannot
   introduce any markup beyond what our own `nl2br()` call adds.
   Nothing else accepts vendor-supplied markup.
5. **How are vendor URLs validated?** The only vendor-controlled URL
   sink found (`notifications.js`'s Announce `link`/`image`) is
   validated by scheme only (`http:`/`https:` allowed, everything else
   — `javascript:`, `data:`, `vbscript:`, obfuscated variants —
   rejected) using the browser's native `URL` parser. No domain
   allowlist was implemented (none was requested, and no stable vendor
   domain contract was established during investigation — §10). No
   other vendor field in this investigation is a URL (`Snep_Notifications`
   has no link field reaching a live sink; `Snep_Version` has no
   download/release URL field at all).
6. **Does cached vendor content remain untrusted at render time?**
   Yes, by construction (§7) — `core_notifications`/`core_config`
   store raw canonical vendor text; every fix in this task escapes at
   the render call site, never at the cache-write site, so a cached
   value is exactly as untrusted on read as a live fetch would be.
7. **Can malicious vendor content break or alter unrelated SENMA
   pages?** No — confirmed via `make external-content-smoke` (§17):
   malicious content in any of the four integrations renders as inert
   text on the pages that display it, and does not affect any other
   page (`/extensions` stays clean regardless of vendor payload
   content, §9's own layout-safety check). This was already
   structurally true before this task for *page-level* isolation (a
   vendor 500/malformed response never 500'd an unrelated page, per
   TASK-0024) — this task closes the remaining *content*-level gap
   (a 200 response with malicious content rendering live markup).
8. **What security work remains outside this narrow trust boundary?**
   Not investigated or touched, explicitly deferred per this task's
   own scope (§24 of the instructions) and CLAUDE.md's debt policy:
   `RegisterController`'s vendor cloud-registration rendering and
   `PortabilityAction`'s vendor portability-lookup rendering (neither
   was encountered while tracing this task's required reading list,
   §6); the pre-existing `Snep_Notifications` cache gap where `->from`
   is never populated for cached entries (a functionality bug, not a
   security issue, §3); a whole-application XSS audit; CSP; an HTML
   sanitizer/purifier dependency; user-generated-content sanitization;
   CSRF/RBAC work; SQL-injection audit; security-header hardening;
   iframe policy; a general URL-reputation system; dependency
   vulnerability scanning.

Stopping at the TASK-0025 commit checkpoint, as instructed. Do not
begin TASK-0026.
