# TASK-0024 — External API failure isolation and release hardening

## Status

**Implemented and validated.** §§1–30 below are the original,
unmodified investigation (still accurate — nothing in it turned out to
be wrong). The Implementation section (§31 onward) records what was
actually built, including one approved mid-implementation scope
extension (`CloudNotice()`/`host_inspect`, §34) discovered during the
mandatory "read every caller" step, not during the original
investigation. See §31 for the file list and §42 for final validation
totals.

<details>
<summary>Original investigation-phase status note (superseded by the
paragraph above)</summary>

Investigation only — not implemented. No runtime code, Docker/network
configuration, views, database schema, tests, or external integrations
were modified during this phase. Every finding below comes from reading
the current committed code (`HEAD` = `46add2c`, "fix: restore Users CRUD
on PHP 8.4 and strict SQL") and from live, controlled experiments
against the running `make dev` environment: a disposable local PHP
built-in web server (`php -S 127.0.0.1:8999`, inside the app container,
stopped and removed afterward) used to deterministically simulate every
failure mode in isolation, and several standalone PHP scripts calling
`Snep_Request::send_request()` directly with the exact same bootstrap
pattern used throughout this project's prior investigations. No DNS,
firewall, or Docker network configuration was changed — only
in-process PHP calls to controlled local/loopback/reserved-range targets.
`core_config`'s real `host_notification`/`update_server` rows were read
but never modified. Working tree is unchanged (`git status` clean).
Stopping here — awaiting approval before any implementation.

</details>

Goal: ensure non-essential external services can never be required for
core SENMA availability. **Not** merely "fix `count(null)`."

---

## 1. Reproduction of the known `Snep_Notifications` failure

Full call path, traced and confirmed live:

```
HTTP request (any layout-rendered page)
  → snep/modules/default/views/layouts/layout.phtml:111
      $noView = Snep_Notifications::getNoView();
  → Snep_Notifications::getNoView()        (snep/lib/Snep/Notifications.php:123)
  → Snep_Notifications::getAll()           (line 89)
      $configs = Snep_Config::getConfiguration('default','host_notification');
      $url = $configs['config_value'] . '/' . $_SESSION['uuid'];
      $ctx = Snep_Request::http_context(['timeout'=>5], 'GET');
      $request = Snep_Request::send_request($url, $ctx);
  → Snep_Request::send_request()           (snep/lib/Snep/Request.php:61)
      $raw_response = @file_get_contents($url, 0, $ctx);   -- failure silenced by @
      $headers = self::parseHeaders($http_response_header); -- undefined if the
                                                                 transport never
                                                                 produced a response
  → Snep_Request::parseHeaders()           (line 71)
      count($headers)     -- line 73
  → PHP 8 Fatal error: Uncaught TypeError: count(): Argument #1 ($value)
    must be of type Countable|array, null given
  → uncaught, propagates through getAll()/getNoView()/the layout
  → HTTP 500 for the entire page, not just the notification widget
```

**Config source**: `core_config` table, `config_module='default'`,
`config_name='host_notification'`, current value
`http://api.opens.com.br/v2/notifications` (a live, current, real
value — confirmed via direct read, not modified).

**HTTP client mechanism**: PHP's native `http://`/`https://` stream
wrapper via `file_get_contents()` with a `stream_context_create()`
context (`Snep_Request::http_context()`) — not cURL, not
`Zend_Http_Client`.

**Return types**: `Snep_Request::send_request()`'s documented-by-code
contract is `['response' => string|false, 'response_code' => int]`
— but only when the transport succeeds far enough to populate PHP's
magic `$http_response_header` variable at all (§7/§8 below).

**Exact PHP 8 fatal observed** (reproduced this session against a
controlled unreachable local target, byte-for-byte identical to
TASK-0023's own log evidence):

```
PHP Warning:  Undefined variable $http_response_header in
/var/www/html/snep/lib/Snep/Request.php on line 63
PHP Fatal error:  Uncaught TypeError: count(): Argument #1 ($value)
must be of type Countable|array, null given in
/var/www/html/snep/lib/Snep/Request.php:73
```

Not fixed in this phase, per instruction.

---

## 2. Why the external call sits in the shared request path

`Snep_Notifications::getNoView()` is called from
**`layout.phtml:111`, unconditionally, for every page rendered through
the shared layout** — the notification bell icon in the top navbar.
This is not gated behind any feature flag, cache check, or
`try`/`catch`.

- **Which pages invoke it**: every controller action that does **not**
  call `$this->_helper->layout()->disableLayout()`. Confirmed via
  `layout.phtml`'s own top-of-file conditional (`if ($controller !=
  'auth')`) that this guards only the `<head>` asset includes, **not**
  line 111's notification call — meaning even some `auth`-controller
  pages using the default layout would still hit it (the login page
  itself is unaffected only because `AuthController::loginAction()`
  explicitly switches to a **separate** `'login'` layout via
  `Zend_Layout::getMvcInstance()->setLayout('login')`, confirmed by
  reading that action — login does not use `layout.phtml` at all).
- **AJAX/layout-disabled responses**: confirmed to skip it entirely.
  `SystemstatusController::indexAction()` (and every JSON-returning
  action across the app that calls `disableLayout()`) never reaches
  line 111 — but see the second, independent exposure below.
- **A second, independent exposure — `Snep_Version`**: `Snep_Version::
  getNewVersions()` (`snep/lib/Snep/Version.php:45`) is called
  **directly** from `SystemstatusController::indexAction()` (line
  129), through the identical vulnerable `Snep_Request::send_request()`
  path, using a **different** config key (`update_server`, currently
  `http://api.opens.com.br/snep`). Because this call is inline in the
  controller action itself, **disabling the layout does not protect
  it** — `/systemstatus` (and its dashboard-widget AJAX fragment, and
  therefore every page that embeds it) is exposed via this second,
  separate call site even though it never touches `layout.phtml`.
  `NewversionController` (`/newversion`, an explicit user-navigated
  page) is the only other caller, of `Snep_Version::getChangelog()`.
- **Login itself**: not exposed (separate layout, confirmed above).
- **Caching**: none exists on the live-fetch path (§13).
- **Once or more than once per request**: `getNoView()` calls `getAll()`
  exactly once per page render; `Snep_Version::getNewVersions()` is a
  single call per `/systemstatus` render. No request triggers either
  call more than once.

**Blast radius, precisely**: any layout-rendered page (essentially the
entire authenticated application surface — extensions, trunks, routes,
groups, queues, reports, settings, and more) **or** any request to
`SystemstatusController::indexAction()`/`NewversionController`, which
together account for every page TASK-0023's own `make smoke` observed
failing intermittently (`reports`, `trunks`, `systemstatus` — the first
two via the layout/notifications path, the third via the direct
`Snep_Version` call). **This project's own `restart-smoke-test.sh`
repeatedly requests `/systemstatus` directly** (to scrape a fresh CSRF
token before every dispatch, dozens of times per run) — meaning
`restart-smoke`'s own clean `37/37` results to date have been exposed
to this exact same risk via the `Snep_Version` path the whole time,
independent of and in addition to `make smoke`'s notification-path
exposure. This was not previously documented.

---

## 3. Complete first-party outbound-dependency inventory

Searched `snep/lib`, `snep/modules`, `snep/includes` (excluding
vendored `Zend`/`linfo` third-party library internals except where
directly relevant) for `file_get_contents` with a URL, `curl_init`,
`Zend_Http_Client`, `fsockopen`/`stream_socket_client`, and
SOAP/XML-RPC.

| # | File | Mechanism | Target | Class |
|---|---|---|---|---|
| 1 | `snep/lib/Snep/Notifications.php` → `Snep_Request` | `file_get_contents` (stream wrapper) | `host_notification` config, `api.opens.com.br` | **C — vendor** |
| 2 | `snep/lib/Snep/Version.php` → `Snep_Request` | `file_get_contents` (stream wrapper) | `update_server` config, `api.opens.com.br` | **C — vendor** |
| 3 | `snep/modules/default/controllers/RegisterController.php` | `curl_*`, explicit `CURLOPT_TIMEOUT=3`/`CURLOPT_CONNECTTIMEOUT=3` | vendor cloud registration API | **C — vendor**, but explicit-action-only (§5) |
| 4 | `snep/modules/portability/actions/PortabilityAction.php` | `curl_*`, explicit `CURLOPT_TIMEOUT=6`/`CURLOPT_CONNECTTIMEOUT=6` | `api.opens.com.br/api/v1/portability/consult` | **C — vendor**, but dialplan-rule-scoped only (§5) |
| 5 | `snep/lib/PBX/Rule.php` | `file_get_contents` | **local file** `/etc/asterisk/snep/snep-agents.conf` | A — not network |
| 6 | `snep/lib/Snep/Bootstrap.php` | `file_get_contents` | **local file**, `configs/snep_version` | A — not network |
| 7 | `snep/lib/Snep/Rest/Controller.php` | `file_get_contents` | **`php://input`** (the current request's own body) | A — not network |
| 8 | `snep/modules/default/controllers/DocsController.php` | `file_get_contents` | **local file**, `docs/*.md` | A — not network |
| 9 | `snep/modules/default/controllers/ModuleSettingsController.php` | `file_get_contents` | **local file**, module `config.json` | A — not network |
| 10 | `snep/modules/default/controllers/SystemstatusController.php` | `Zend_Http_Client` | `http://127.0.0.1:80/...` — **same-container loopback** (TASK-0006's `linfo` call) | A — local/internal |
| 11 | `snep/lib/Asterisk/AMI.php`, `snep/lib/Snep/Asterisk/Operations.php` | `fsockopen` | Asterisk AMI, same Docker network | A — local/internal, required |
| 12 | `snep/lib/linfo/lib/class.GetMbMon.php`, `class.GetHddTemp.php` | `fsockopen`, wrapped in a thrown exception on failure | local hardware-sensor daemons (mbmon/hddtemp) | A — local/internal, already exception-safe, optional |
| 13 | `snep/lib/linfo/lib/class.ext_utorrent.php` | (linfo optional plugin, not evidenced as reachable/enabled in this app's own usage) | local uTorrent client | A — local/internal, unused in practice |
| 14 | `snep/includes/AMI.php` | `fsockopen` | — | **dead code** — a vendored, unrelated third-party AMI class with zero call sites anywhere else in the codebase (confirmed via `grep`); not part of any live path |
| 15 | SOAP/XML-RPC | — | — | none found anywhere in first-party code |

No internal infrastructure (MariaDB, AMI, the loopback `linfo` call) is
misclassified as "external vendor" — all three are correctly local per
this table.

---

## 4. Criticality classification

| Dependency | Classification | Why |
|---|---|---|
| `Snep_Notifications` (vendor) | **BACKGROUND/COSMETIC** | Purely a notification-bell UI element; the application defines its own graceful empty state already (`if($notifications){...}else{"You have no notifications"}`) — proven by code, not assumed. |
| `Snep_Version` (vendor update check) | **BACKGROUND/COSMETIC** | Purely an informational "new version available" banner; `getNewVersions()` already returns `null` on any non-200/unexpected case it can actually reach. |
| `RegisterController` (vendor cloud registration) | **OPTIONAL / FEATURE REQUIRED** (for that one feature only) | Only relevant to whoever explicitly visits `/register`; failure there legitimately surfaces on that one page (already has its own `$this->view->error_message` handling for non-200 codes). |
| `PortabilityAction` (vendor portability lookup) | **OPTIONAL / FEATURE REQUIRED** (for that one dialplan rule only) | Only executes when an administrator has explicitly configured a rule to use it; a real, already-present local `portability_cache` table exists for exactly this dependency. |
| MariaDB, Asterisk AMI, loopback `linfo` | **CORE REQUIRED** | The application cannot function at all without these — out of TASK-0024's scope, correctly so. |

---

## 5. Request-path classification

| Call site | Path |
|---|---|
| `Snep_Notifications::getNoView()` | **Implicit, every layout-rendered foreground page** |
| `Snep_Version::getNewVersions()` | **Implicit**, `SystemstatusController::indexAction()` (and therefore the dashboard widget that embeds it) |
| `Snep_Version::getChangelog()` | Explicit user action only (`/newversion`) |
| `RegisterController::indexAction()` | Explicit user action only (`/register`) |
| `PortabilityAction::execute()` | Explicit, but only when an administrator has configured a dialplan rule to invoke it — runs during real call handling for matching calls, not a foreground HTTP request at all |

**Two, and only two, external calls execute implicitly during
unrelated foreground requests**: `Snep_Notifications::getNoView()` and
`Snep_Version::getNewVersions()`. Both share the exact same underlying
defect (`Snep_Request`), which is why a request-layer fix
simultaneously closes both, rather than needing two separate
feature-layer patches.

---

## 6. Timeout audit

`Snep_Request::http_context()` **does** set an explicit
`timeout` in the stream context (`stream_context_create(['http' =>
['timeout' => $timeout, ...]])`), defaulting to **3 seconds** if the
caller doesn't override it. Callers observed: `Snep_Notifications::
getAll()` passes `5`, `Snep_Notifications::getNotification()` passes
`1`, `Snep_Version::getNewVersions()`/`getChangelog()` pass none
(3s default).

**Measured live, this session, against a genuinely non-responding
target** (`192.0.2.1`, RFC 5737 TEST-NET-1, guaranteed non-routable):
a call with an explicit 3-second timeout took **3.004 seconds** before
`file_get_contents()` gave up — the timeout **is** honored and bounds
the worst case correctly for a true network black hole. PHP's
`http://` stream wrapper applies this single value to the whole
connect+read operation (there is no separate connect-timeout knob
available through this API, unlike cURL's `CONNECTTIMEOUT`/`TIMEOUT`
pair).

**Measured live against a connection genuinely established but never
completing a response** (a local test server told to `sleep(15)`
before responding, called with an explicit 2-second timeout): returned
in **2.001 seconds**, also correctly bounded — but critically, **this
specific failure shape does not crash** (§7) — `file_get_contents()`
still initializes `$http_response_header` to an empty array in this
case, so `parseHeaders()`'s `count()` call succeeds; the crash is
specific to failures where no connection-level response was ever
initiated at all.

**DNS failure and connection-refused both fail near-instantly** (0.002s
and 0.06s measured) — not subject to the configured timeout at all,
since the failure happens before the stream wrapper even reaches the
point where a timeout would apply.

**Worst-case delay added to a single web request today**: bounded at
the caller's configured timeout (3–5 seconds depending on call site) —
**not unbounded** — but every one of those worst cases (except the
one "connection established, response never completes" shape) also
crashes the entire page with a fatal 500, which is strictly worse than
merely being slow.

---

## 7. Failure-mode matrix

All modes reproduced live this session via the disposable local test
server (E–M) or reserved/loopback targets (A–D), never against the
real vendor:

| Mode | Mechanism | Crashes? | Latency | Page still renders? |
|---|---|---|---|---|
| A. DNS resolution failure | `http://this-host-does-not-exist.invalid/` | **Yes — `count(null)` fatal** | 0.06s | No — 500 |
| B. Connection refused | `http://127.0.0.1:<closed-port>/` | **Yes — `count(null)` fatal** | ~0s | No — 500 |
| C. Timeout / blackhole | `http://192.0.2.1/` (RFC 5737) | **Yes — `count(null)` fatal**, after the full configured timeout | 3.004s (bounded by timeout) | No — 500 |
| D. TLS/connect failure | `https://` against a plain-HTTP-only port | **Yes — `count(null)` fatal** | 0.002s | No — 500 |
| E. HTTP 404 | local test server | No | ~0s | Yes — body/code returned normally (`ignore_errors=true` in the context) |
| F. HTTP 429 | local test server | No | ~0s | Yes |
| G. HTTP 500 | local test server | No | ~0s | Yes |
| H. HTTP 503 | local test server | No | ~0s | Yes |
| I. Empty response body | local test server, 200 + empty body | No | ~0s | Yes — `json_decode('')` → `null`, handled by the caller's own `if ($notifications)` |
| J. Malformed JSON | local test server, 200 + garbage body | No | ~0s | Yes — `json_decode()` → `null`, same graceful path |
| K. Valid JSON, `null` payload | local test server | No | ~0s | Yes |
| L. Valid JSON, scalar (`42`) instead of array | local test server | No (a downstream `foreach` on a non-iterable is a **warning**, not fatal, in PHP 8 — confirmed the same class of warning already found and left undisturbed in TASK-0023's `bond.phtml` finding) | ~0s | Yes |
| M. Very slow response, connection established | local test server, `sleep(15)`, explicit 2s timeout | **No** — a distinct, subtler bug (see below) | 2.001s (bounded) | Yes, degrades to `response_code: null` (via an *unrelated* second bug, a `Warning: Undefined array key "response_code"` at `Snep_Request.php:66` — non-fatal) |

**A precise, non-obvious distinction found this session**: whether
`Snep_Request` crashes depends on exactly which transport phase failed,
not on "did the call succeed." When absolutely no connection-level
response is ever initiated (A/B/C/D — DNS, refusal, blackhole timeout,
TLS failure), PHP never sets `$http_response_header` at all, and
`parseHeaders()`'s `count($headers)` fatals on the resulting `null`.
When a connection is established but the response body/status line
never arrives before the timeout (M), PHP **does** initialize
`$http_response_header` to an empty array, so `count()` succeeds — but
a **second**, independent, previously-undocumented bug at
`Snep_Request.php:66` (`$headers['response_code']`, an undefined-array-key
warning, not a crash) means this path degrades safely by accident, not
by design. Both bugs live in the same function and should be fixed
together.

---

## 8. `Snep_Request` contract

Read in full (`snep/lib/Snep/Request.php`, 91 lines). Its actual,
current, undocumented contract:

- **`http_context($data, $method='POST')`**: always succeeds, returns a
  `stream_context_create()` resource. No failure mode.
- **`send_request($url, $ctx)`**: intended return type
  `array{response: string|false, response_code: int}`. **Actual**
  return type: either that array (when a response was received, even
  an error one) **or an uncaught `TypeError` propagating out of
  `parseHeaders()`** when no connection-level response was ever
  initiated. Not documented anywhere; every caller (`Snep_Notifications`,
  `Snep_Version`) assumes the array shape unconditionally and never
  wraps the call in a `try`/`catch`.
- **`parseHeaders($headers)`**: assumes `$headers` is always a
  populated (or at least defined, even if empty) array. Crashes on
  `null` (§1/§7). Never checked for `isset()`/type before use.
- HTTP status **is** effectively checked by some callers
  (`Snep_Version` checks `response_code == 200`) but **not by
  `Snep_Notifications`**, which passes whatever body came back straight
  to `json_decode()` regardless of status — safe in practice only
  because `json_decode()` of an error page's HTML/text body reliably
  produces `null`, which the caller's `if ($notifications)` check
  already tolerates.
- Response parsing (`json_decode`) happens entirely in the **callers**,
  never in `Snep_Request` itself — confirming `Snep_Request` is meant
  to be a generic transport helper, not JSON-aware.
- **The `count(null)` bug is a caller-contract mismatch, not the true
  root cause.** The true root cause is architectural: `Snep_Request`
  was never designed to represent "the request failed at the transport
  level" as a value at all — it silently swallows the underlying
  `file_get_contents()` failure via `@` and then unconditionally
  assumes a response arrived. `count(null)` is the specific PHP 8
  surface symptom of that missing case; a `count($value ?? [])`-style
  patch would silence the symptom but the `$headers['response_code']`
  access at line 66 shows the same *class* of gap exists a second time
  in the same function, and would keep resurfacing anywhere else this
  contract is assumed. The fix belongs to establishing a real contract
  (§11), not merely guarding one `count()` call.

---

## 9. `Snep_Notifications` contract

Read in full (`snep/lib/Snep/Notifications.php`, 224 lines).

- **What it needs**: a JSON array of notification objects
  (`id`, `title`, `message`, `creation_date`, `status`) from the vendor
  API, keyed by the current session's `uuid`.
- **What it renders**: `getNotifications($url)` returns an HTML
  `<li>` fragment for the top-nav dropdown; `getNoView()` returns the
  subset with `status == 'unread'`, consumed by `layout.phtml:111` to
  decide whether to show an unread-count badge.
- **Zero-notifications empty state**: already explicitly implemented
  and correct — `getNotifications()` renders "You have no
  notifications" when `$notifications` is falsy; `getNoView()` simply
  returns `array()`.
- **Can remote failure be represented identically to "no remote
  notifications"?** **Yes, and this is exactly what the code already
  intends** — both `getAll()`'s `json_decode()`-of-garbage-or-empty
  path and a hypothetical "the vendor is unreachable" path should
  produce the same `null`/empty-array outcome the UI already handles
  gracefully. The only reason this doesn't happen today is that the
  crash in `Snep_Request` occurs **before** `Snep_Notifications` ever
  gets control back to apply its own already-correct `if ($notifications)`
  logic.
- **Does distinguishing "no notifications" from "service unavailable"
  matter?** Not for this UI element — a badge that would show "0" and
  one that would show "unavailable" both amount to "don't interrupt the
  administrator," and the existing text ("You have no notifications")
  is not misleading enough in the rare unavailable case to justify a
  second visual state, especially under the stronger constraint that
  the page must never fail outright. (Logging, §22, is the place to
  distinguish the two, not the UI.)
- A genuinely unused, seemingly vestigial local cache surface already
  exists: the `core_notifications` table (`id`, `id_itc`, `title`,
  `from`, `message`, `creation_date`, `read`, `reading_date`) — schema
  clearly designed to mirror vendor notifications locally, currently
  **zero rows**, and **`getAll()`/`getNoView()`/`getNotification()`
  never read or write it at all**. Two other methods in the same class
  (`getDateLastNotification()`, `getNotificationWarning()`) do query it
  — but **have zero callers anywhere in the codebase** (confirmed via
  `grep`), i.e. genuinely dead code. This table is the natural, already-
  present home for the caching strategy in §13 — no new table needed.

---

## 10. PHP 8.4 compatibility mechanism — precisely scoped

Confirmed via the isolated live reproductions in §7: the exact,
singular mechanism is **`count()` called on a value that is `null`
because an undefined variable (`$http_response_header`) was never
populated** — `TypeError: count(): Argument #1 ($value) must be of
type Countable|array, null given`, the identical class of bug already
fixed twice in TASK-0023 (`count($name_exist)`,
`array_diff($currentResourcesGroup, $dados['permission_id'])`). A
second, related-but-distinct instance in the same function
(`$headers['response_code']`, an undefined-array-key warning, not
fatal) was also found (§7/§8).

Searched only the immediate `Snep_Notifications`/`Snep_Request`
integration surface (not a broader sweep, per instruction): no other
`count()`/bareword-constant/removed-function/static-mismatch issue was
found in either file. `Snep_Notifications`'s own static-method
declarations already carry an explicit "PHP 8 compatibility... pulled
forward... because `getNoView()` is called from the shared page
layout, blocking every page" docblock from an earlier compatibility
pass (TASK-0002) — meaning the *static-call* class of PHP 8 issue was
already anticipated and fixed for this exact file; the transport-layer
`count(null)` issue is a different, later-discovered defect in the
same request path.

---

## 11. Failure isolation boundary — recommendation

**Recommend D: a combination of a narrow request-layer contract fix
plus feature-layer degradation** — not A (blanket global
normalization hiding all failures indiscriminately) and not merely C
(a layout-only guard, which would still leave `Snep_Version`'s direct
controller-level call exposed, per §2's finding).

Concretely:

- **Request layer (`Snep_Request::send_request()`/`parseHeaders()`)**:
  a small, targeted fix so the function **always** returns the
  documented `['response' => string|false, 'response_code' => int]`
  shape, never throws, regardless of which transport phase failed —
  guard `count()` against an unset/non-array `$http_response_header`,
  and default `response_code` (e.g. to `0`) when no real status line
  was ever parsed. This is a predictable, bounded **contract**, not a
  policy decision about what any particular feature should do with a
  failure — matching the instruction's own stated principle exactly.
- **Feature layer (`Snep_Notifications`, `Snep_Version`)**: no new
  logic needed at all — both already contain correct
  falsy/`response_code`-based degradation paths; once the request
  layer stops throwing, those paths simply become reachable, exactly
  the same shape of fix as TASK-0023's blocker 3 (making already-written,
  currently-unreachable safe-degradation code actually run).
- **Layout**: no wrapping needed once the above two are fixed — the
  call it makes (`getNoView()`) will simply return `array()` on
  failure, exactly like the already-correct "no notifications" case.

This does **not** make every external request optional by default —
`RegisterController`/`PortabilityAction` are unaffected and untouched,
since their own failure handling is already scoped correctly to the
one feature/call each belongs to (§4).

---

## 12. Timeout policy — recommendation

**Recommend 2 seconds** for `Snep_Notifications`'s and `Snep_Version`'s
foreground calls specifically (down from the current 3s
default/5s/1s spread), for concrete, measured reasons:

- The vendor host itself, when reachable, responds in well under
  200ms (TASK-0023 measured a `curl` round trip of ~0.1s against the
  same host this session).
- PHP's `http://` stream wrapper offers only a single combined
  connect+read timeout value (§6) — there is no way to set a separate,
  shorter connect timeout without switching HTTP clients, which is
  explicitly out of scope (no broad rewrite, §28).
- 2 seconds is long enough to absorb realistic internet latency/jitter
  for a fast JSON endpoint, while short enough that a full vendor
  outage adds at most 2 seconds to affected page loads — not
  "noticeably freezes every page," the instruction's own bar.
- This is **not** arbitrary: it is bounded by the measured
  fast-path latency (~0.1s) with roughly 20x headroom, matched against
  the instruction's own requirement to avoid an unreasonable per-request
  delay.

**Whether to avoid the foreground call entirely is the stronger,
preferred answer** — see §14: a short timeout only bounds the *worst
case*, it does not eliminate the *typical-case* added latency (up to
2 seconds on literally every page load whenever the vendor is simply
slow, not down). Given `Snep_Notifications`' own data changes rarely
(a human reads notifications occasionally, not every page load), caching
(§13) removes the foreground call from the hot path far more
effectively than any timeout value could.

---

## 13. Caching — recommendation

**No cache mechanism exists on the live path today** (§9) — the
`core_notifications` table exists, matches the vendor's own data shape
closely, and is currently unused by the live-fetch code at all.

**Recommended strategy**, using only existing infrastructure (no
Redis, no new service, per instruction):

```
remote succeeds
  → write/refresh a small number of rows into core_notifications
    (or a single last-fetch timestamp + serialized payload, whichever
    requires the smaller change) with a bounded TTL (e.g. 60s)
  → render from that local data

remote fails, or cached data is still within TTL
  → render from core_notifications' last-known-good contents
  → if no cached data has ever been successfully fetched, render the
    existing "You have no notifications" empty state -- not an error,
    matching §9's finding that the UI already treats these identically
```

A cache **read** failure (e.g., a DB hiccup) is already handled by the
existing pattern everywhere else in this codebase — a caught exception
or falsy `fetch()` result, degrading to the same empty state, not a
new failure mode to design for.

This directly avoids "one vendor request per page" — the single
biggest lever available for reducing both blast radius and typical-case
latency, well beyond what any timeout tuning alone can achieve.

---

## 14. Foreground vs. background — recommendation

**Recommend B: cached synchronous refresh** (§13), not a new
background job/cron (explicitly out of scope, §29) and not the
already-present-but-dead client-side `XMLHttpRequest` poller in
`snep/includes/javascript/notifications.js` (option D) — that
JavaScript function (`getNotifications(url, session)`) exists in the
codebase, calls the vendor directly from the browser, and is **never
invoked from anywhere** (confirmed via `grep` across every `.js`/
`.phtml` file) — genuinely dead, unfinished code, not a currently-working
alternative path. Reviving it would be a real, separate feature change
(a second, different notification-delivery architecture) — larger in
scope than this task's own smallest-robust-solution mandate. The
cached-synchronous-refresh approach (A short-circuited by a TTL check,
which is effectively "A but usually skipped") keeps the exact same
architecture the application already has, removes the vendor call from
the hot path on every page except roughly once per TTL window, and
requires no new moving parts.

---

## 15. Layout resilience — recommendation

**Establish the invariant specifically for the two known optional
integration boundaries found in this investigation
(`Snep_Notifications`, `Snep_Version`), not a blanket `catch
(Throwable)` around the whole layout.** Wrapping the entire layout
would silently swallow genuine application bugs anywhere in the page
(exactly what the instruction explicitly warns against). No existing
general layout-component error-isolation pattern was found elsewhere in
this codebase to reuse — this would be establishing the pattern for
the first time, scoped narrowly to these two call sites (via the
request-layer contract fix in §11, which already achieves this without
needing a `try`/`catch` in the layout at all, since a non-throwing
`Snep_Request` means there is nothing left to catch).

---

## 16. Offline-mode validation — test design

A deterministic offline-mode test should point `host_notification`/
`update_server` at an unreachable target (e.g., a reserved-range
address or a closed local port, exactly as used in this investigation's
own §7 reproductions) via `core_config`, then confirm, through the real
UI/HTTP flows already proven throughout this project's other smoke
suites:

- Login (unaffected — separate layout, §2).
- Dashboard render.
- Extensions list/add/edit/delete (the exact flow TASK-0023 already
  proved end-to-end).
- Trunks list/add/edit/delete.
- Local System Status (`/systemstatus` — exposed via `Snep_Version`
  today, §2; must remain healthy after the fix).
- Asterisk restart controls for an authorized user (TASK-0022's own
  proven flow).
- A local extension-to-extension call (`call-smoke-test.sh`'s own
  mechanism).
- Local CDR/report readback (`calls-report`, also layout-rendered —
  exposed today, must remain healthy after the fix).
- The trunk flow against the already-controlled, in-network `provider`
  simulator container (`trunk-smoke-test.sh`'s own mechanism) — this
  is **not** an Internet dependency at all (§25).

This is intentionally the same list, in the same spirit, as this
project's own existing smoke suites — no new topology needed, only a
temporary, reversible `core_config` value pointing at an unreachable
target for the duration of the test.

---

## 17. `make external-failure-smoke` — design

Proposed name matches the project's existing convention exactly
(`restart-smoke`'s own precedent). Deterministic, using the same
disposable local test server mechanism proven in this investigation
(§7) — no dependency on the real vendor being down, no privileged
Docker/network changes needed (the §28 stop condition was **not**
triggered — every failure mode in §7 was reproduced using only
loopback addresses, a reserved documentation-only IP range (RFC 5737),
and a plain local PHP built-in server, all available in the existing
container without any elevated privileges).

Minimum coverage, directly reusing §7's evidence:

- DNS-unreachable equivalent (a `.invalid` TLD hostname, RFC 2606).
- Connection refused (closed local port).
- Timeout/blackhole (`192.0.2.1`, bounded by the configured timeout).
- HTTP 500 (local test server).
- Malformed payload (local test server).
- Null/empty payload (local test server).

For each: assert an unrelated local page (e.g. `/extensions`) stays
non-500, assert latency stays within the recommended bound (§12),
assert zero new PHP Fatal Errors (the same `mag-error.log` diffing
convention every other smoke script already uses), assert the
notification component still renders its existing empty state.

Kept opt-in/regression-safe like `restart-smoke` — not run implicitly
by `make smoke`.

---

## 18. `make smoke` determinism — success criterion

Directly addressed by §11/§13: once `Snep_Request` never throws and
notification data is served from a TTL-bounded local cache, the vendor
API is contacted **at most roughly once per cache TTL window**, not
once per page — and even when contacted, a failure degrades to the
existing empty state rather than crashing. `make smoke`'s own 16 checks
touch layout-rendered pages well within a single run's duration, so
after implementation, repeated runs (the recommended minimum of 10
consecutive clean runs) should show **zero** vendor-related failures,
deterministically — not "retry until green." Prefer this deterministic
isolation over relying on the vendor happening to be reachable during
CI/dev runs at all.

---

## 19. Vendor unavailable at startup

No code path found anywhere that gates application/container startup
or a health check on `Snep_Notifications`/`Snep_Version`/
`RegisterController`/`PortabilityAction` reachability — confirmed via
the full inventory (§3) and via reading `docker/asterisk-entrypoint.sh`/
the app container's own startup sequence in prior tasks' investigations
(TASK-0001/0005), neither of which references any of these classes.
SENMA already becomes usable with the vendor unreachable at startup;
no change needed here, and no new startup dependency should ever be
introduced (a re-stated invariant, not a new finding).

---

## 20. Vendor fails after startup

Directly proven by this session's own live reproductions (§7): once the
request-layer fix (§11) lands, a vendor outage beginning mid-session
degrades exactly like "vendor was always unreachable" — the local
application remains healthy on every subsequent page (each request is
independent; there is no persistent broken state to get stuck in,
since `Snep_Request` holds no connection or state between requests).
Optional notification/version-check functionality degrades to its
existing empty state on each affected request.

---

## 21. Recovery behavior

**Recovers automatically, on the very next request after the vendor
becomes reachable again** (or the next cache-refresh attempt after TTL
expiry, once §13 is implemented) — there is no persistent "failed"
flag anywhere in `Snep_Notifications`/`Snep_Version`/`Snep_Request` to
get stuck in (each call is independent, stateless, per-request). No
container restart is required or would have any effect on this. This
holds true today even without any fix, for every failure mode that
doesn't crash (§7 E–M); the request-layer fix extends the same
already-correct recovery property to the four modes that currently
crash (A–D).

---

## 22. Observability — recommendation

Minimal logging, using the existing `error_log()`/`Snep_Audit_Manager`
mechanisms already established and proven throughout TASK-0019–0023
(never `Zend_Registry::get('log')`, still not registered in the real
bootstrap):

- Log once per **failure category transition** (e.g., first failure
  after a prior success, or first success after a prior failure), not
  once per page load — a simple in-request static/session-scoped flag
  or a comparison against the last cached fetch's own success/failure
  state is sufficient; no new deduplication framework needed, avoiding
  the "flood logs" risk explicitly called out.
- Fields: integration name (`notifications`/`version-check`), failure
  category (dns/refused/timeout/tls/http-status/malformed-payload),
  HTTP status where available, timestamp.
- **Never** log: credentials, authorization headers, full response
  bodies (a truncated/redacted snippet at most, if genuinely useful for
  debugging malformed-payload cases), session data — matching every
  prior task's own logging discipline in this project exactly.

---

## 23. Security behavior — audit

- **HTML escaping**: `Snep_Notifications::getNotifications()`
  concatenates `$notification['title']`/`['message']` directly into
  raw HTML (`$html .= "<div><strong>".$notification['title']...`) with
  **no escaping at all** — a genuine, directly-observed XSS trust
  boundary: the vendor API's own response content is rendered
  unescaped into every authenticated user's page. This is a real,
  pre-existing finding, reported here per the instruction ("report any
  directly observed dangerous trust boundary") but **not** proposed
  for a fix in this task — it is a content-trust issue orthogonal to
  availability/failure-isolation, and fixing it is a genuinely separate
  concern (the vendor is presumably trusted today by design intent, even
  though the code has no verification of that trust). Flagged as
  explicit follow-up debt, not absorbed into TASK-0024's own scope
  (§28's "do not recursively absorb unrelated debt").
- **Redirects/URLs from the remote payload**: the notification bell's
  own link (`href=".../notifications?id=".$notification['id']`) uses
  only the numeric `id` field from the payload, concatenated into a
  same-origin URL — not attacker-controlled in a way that changes the
  link's destination host.
- **`unserialize()`/`eval()`**: none found anywhere in the
  `Snep_Notifications`/`Snep_Request`/`Snep_Version` integration
  surface. (Unrelated: `Snep_Dashboard_Manager` uses PHP `serialize()`/
  `unserialize()` on `users.dashboard`, already investigated in
  TASK-0023 — that data is locally-written, not remote-payload-derived,
  so it is outside this audit's own scope.)

Not expanded into a broader XSS/security audit, per instruction.

---

## 24. Local-call independence — proof

`call-smoke-test.sh`'s own full flow (PJSIP registration → AGI →
`PBX_Rules`/`PBX_Dialplan` engine → `Dial()` → CDR via `cdr_adaptive_odbc`
→ SENMA's own reporting readback) was grepped end-to-end for any
reference to `notification`, `Snep_Version`, `update_server`,
`host_notification`, or `portability` — **zero matches** (the one
false-positive hit was the unrelated word "register" as in PJSIP
`wait_registered()`, confirmed by inspection). This call path shares
**no code** with any of the vendor-dependent classes in §3 — Asterisk's
own dialplan/AGI/ODBC-write pipeline has no dependency on
`Snep_Request` at all. Structurally proven, not merely asserted; no
live re-run against a deliberately-blocked vendor was necessary to
establish this, since the code paths are provably disjoint.

---

## 25. Trunk-test independence — proof

Same grep-based proof applied to `trunk-smoke-test.sh`: zero references
to any vendor-dependent class. The project's local `provider` simulator
(a separate, in-Docker-network container, per `compose.yaml`) requires
no public Internet access at runtime — it is reached entirely over the
Docker network, exactly like Asterisk's AMI. `make trunk-smoke`'s own
build-time requirement (pulling base images, `apt`/`pip` packages
during `docker compose up -d --build`) is a **separate, already-understood**
concern, correctly distinguished here from **runtime** requirements:
once images are built, `trunk-smoke` needs no Internet access to run.

---

## 26. Asterisk operational independence — proof

Same proof method applied to TASK-0021/0022's own restart
infrastructure (`Snep_Asterisk_Operations`, AMI, `SystemstatusController::
restartDispatchAction()`/`restartStatusAction()`): **zero** dependency
on any vendor-facing class for the AMI exchange, dispatch, or readiness
polling itself. The **one** real exposure already found and documented
precisely in §2/§7: `SystemstatusController::indexAction()` (the page
that *renders* the restart controls, and that `restart-smoke-test.sh`
itself polls repeatedly for a fresh CSRF token) calls `Snep_Version::
getNewVersions()` inline — meaning a vendor outage, **before this
task's fix**, could make the System Status *page itself* return 500,
which would in turn make it impossible to even reach the restart
controls or scrape a CSRF token, indirectly blocking restart
functionality despite AMI/dispatch/readiness themselves having no
vendor dependency at all. This is the single most operationally
important finding in this investigation: **today, a vendor outage can
transitively block Asterisk restart availability**, purely through the
System Status page's own unrelated version-check call — exactly the
kind of hidden coupling this task exists to eliminate.

---

## 27. Launch policy for outbound dependencies

| Category | Policy |
|---|---|
| **CORE INTERNAL** (MariaDB, Asterisk AMI, loopback `linfo`) | Failure surfaces because the requested local operation genuinely depends on it — unchanged, out of scope. |
| **USER-CONFIGURED EXTERNAL** (`RegisterController`, `PortabilityAction`) | Failure isolated to the one requested feature/call only — already correctly scoped today; no change needed. |
| **SENMA/VENDOR OPTIONAL** (`Snep_Notifications`, `Snep_Version`) | Short bounded timeout (2s, §12) **and** cached synchronous refresh (§13) **and** a request-layer contract that never throws (§11) — together guaranteeing no unrelated-page failure, ever, regardless of vendor state. |
| **BACKGROUND/COSMETIC** | Same two dependencies above — must never synchronously block a foreground request beyond the bounded timeout on a genuine cache miss. |

---

## 28. Stop conditions — assessed

- `Snep_Request` used by critical operations whose semantics would
  change under normalization — no; every real call site
  (`Snep_Notifications`, `Snep_Version`) is BACKGROUND/COSMETIC (§4);
  `RegisterController`/`PortabilityAction` don't use `Snep_Request` at
  all (they use raw cURL, §3). Not triggered.
- Safe isolation requires a broad HTTP-client rewrite — no; the fix is
  two small, targeted null/undefined-key guards in one 91-line file,
  the same scale as TASK-0023's own three fixes. Not triggered.
- Deterministic failure testing requires privileged Docker/network
  access — no; every failure mode in §7 was reproduced with only
  loopback addresses, one RFC 5737 reserved IP, and a plain unprivileged
  local PHP server. Not triggered.
- Caching requires schema changes or new infrastructure — no; the
  `core_notifications` table already exists, unused, with exactly the
  right shape (§9/§13). Not triggered.
- The vendor API is unexpectedly required for licensing/core operation
  — no; nothing in `Snep_Notifications`/`Snep_Version` gates any
  licensing or core feature (confirmed by reading both classes in
  full, §9). Not triggered.
- Another unrelated PHP 8.4 bug appeared — the XSS/unescaped-HTML
  finding in §23 is unrelated to PHP 8 compatibility specifically (it
  would exist under any PHP version) and is explicitly flagged as
  separate debt, not folded in. No new *compatibility* blocker
  appeared during this investigation.
- External dependency behavior cannot be tested safely — no; the local
  test-server methodology (§7) worked cleanly for every mode. Not
  triggered.

---

## 29. Explicitly deferred

New queue/message broker; Redis; broad microservice architecture; a
full observability platform; telemetry redesign; licensing redesign;
automatic Internet failover; Docker privileged networking; a general
security audit (beyond the one directly-observed XSS finding reported
in §23); CDR timezone fixes; RBAC redesign. Also explicitly not
addressed in this investigation's proposed scope: reviving the dead
client-side `notifications.js` poller (§14); fixing `RegisterController`/
`PortabilityAction` (already well-behaved, §4); the `core_notifications`
table's two genuinely dead reader methods (`getDateLastNotification()`,
`getNotificationWarning()`) — left as-is unless the caching
implementation phase finds it needs to touch them.

---

## 30. Answers

1. **Why can `Snep_Notifications` currently break unrelated pages?**
   Because it is invoked unconditionally from the shared page layout
   (`layout.phtml:111`) on every layout-rendered page, and its
   underlying HTTP client (`Snep_Request`) crashes with an uncaught
   PHP 8 `TypeError` whenever the vendor call fails at the transport
   level (DNS/refused/timeout/TLS) — a failure with zero relationship
   to whatever page happened to be rendering at the time (§1/§2).
2. **Root cause vs. the `count(null)` symptom?** The symptom is
   `count()` receiving `null` because PHP's magic
   `$http_response_header` variable was never populated. The root
   cause is architectural: `Snep_Request` has no defined contract for
   "the request failed before any response arrived" — it silently
   swallows the failure via `@` and then unconditionally assumes a
   response exists, a gap that resurfaces a second time in the same
   function (`$headers['response_code']`, §7/§8).
3. **Where should failure isolation live?** The request layer
   (`Snep_Request`) gets a small, non-throwing contract fix; the
   feature layer (`Snep_Notifications`, `Snep_Version`) needs no new
   code at all, since both already contain correct degradation logic
   that merely needs to become reachable (§11).
4. **What timeout policy?** 2 seconds, bounded, measured against this
   session's own live evidence of typical (~0.1s) and worst-case
   (timeout-limited) vendor latency (§12) — combined with caching so
   this bound is rarely even exercised.
5. **Should notification data be cached?** Yes — the `core_notifications`
   table already exists, unused, with exactly the right shape; a
   bounded-TTL cache removes the vendor call from nearly every page
   load entirely, not just bounding its worst case (§13).
6. **Should the vendor call remain in the synchronous layout path?**
   Yes, but as a TTL-gated cache read/refresh, not a raw per-request
   call — reviving the already-present-but-dead client-side JS poller
   would be a larger, separate architecture change, out of this task's
   smallest-robust-solution mandate (§14).
7. **What should the user see when the vendor is unavailable?** Exactly
   the same "You have no notifications" / no-version-banner empty
   state the application already renders for a genuinely empty
   response — no new UI state needed (§9).
8. **Any other non-essential external APIs currently capable of
   breaking unrelated pages?** No — `RegisterController` and
   `PortabilityAction` are the only other vendor-facing code, both use
   bounded cURL timeouts directly (not `Snep_Request`), and both are
   scoped to an explicit action/rule, never the shared layout or an
   implicit foreground path (§3/§5).
9. **Can SENMA operate normally with public Internet unavailable?**
   Yes, structurally proven for every core flow (login, CRUD, local
   calls, local reports, System Status, Asterisk restart) via disjoint
   code-path analysis against the existing smoke suites (§16/§24/§25/§26)
   — with one specific, now-documented exception that this task's
   implementation phase must close: `SystemstatusController::indexAction()`'s
   inline `Snep_Version` call can currently 500 the System Status page
   itself during a vendor outage, transitively affecting restart-control
   *availability* even though restart *functionality* has no real
   dependency on it (§26).
10. **What exact changes should the implementation phase make?**
    `snep/lib/Snep/Request.php` (the non-throwing contract fix, §11),
    `snep/lib/Snep/Notifications.php` (read/write the existing
    `core_notifications` table as a bounded-TTL cache, §13), a new
    `scripts/external-failure-smoke-test.sh` + `make
    external-failure-smoke` target (§17). `Snep_Version.php` needs no
    code change (its own `response_code == 200` check already becomes
    correct and reachable once `Snep_Request` stops throwing) but its
    exposure via `SystemstatusController::indexAction()` should be
    covered by the same smoke suite. No changes proposed to
    `RegisterController`, `PortabilityAction`, Docker/network
    configuration, or any schema.
11. **What deterministic test proves this class of release blocker is
    gone?** `make external-failure-smoke` (§17), run against controlled
    local failure simulations (never the real vendor), asserting zero
    PHP Fatal Errors and non-500 responses on unrelated pages across
    every failure mode in §7 — plus 10 consecutive clean `make smoke`
    runs (§18) as the project's own existing top-level regression
    signal that the probabilistic failure TASK-0023 observed is
    genuinely, deterministically gone, not merely less likely.

*(§§1–30 above are the original investigation report. Everything below
is new, added during and after implementation.)*

---

## 31. Implementation summary

Implemented exactly the approach recommended in §11/§13/§14/§17, plus
one approved scope extension (§34). Files changed:

| File | Change |
|---|---|
| `snep/lib/Snep/Request.php` | `send_request()` now always returns `['response'=>string\|false,'response_code'=>int]`, never throws (§32). `parseHeaders()` guards `is_array()` before `count()`. |
| `snep/lib/Snep/Config.php` | New `Snep_Config::setConfiguration($module,$key,$value)` — the write-side counterpart to the existing `getConfiguration()`, select-then-insert-or-update against `core_config` (no unique constraint on that table — confirmed via `SHOW CREATE TABLE` before writing this). |
| `snep/lib/Snep/Notifications.php` | `getAll()` rewritten as a TTL-gated cache reader/writer (§33). |
| `snep/lib/Snep/Version.php` | `getNewVersions()` given the identical TTL-gated cache treatment (§33). |
| `snep/modules/default/controllers/SystemstatusController.php` | `CloudNotice()`'s `host_inspect` call given the same TTL-gate pattern (§34 — the approved scope extension). |
| `Makefile` | New `external-failure-smoke: up` target (§17/§35). |
| `docker/external-failure-test/router.php` (new) | Controlled local endpoint for `make external-failure-smoke`'s HTTP-status/malformed/empty modes (§35). |
| `scripts/external-failure-smoke-test.sh` (new) | The smoke suite itself, 27 checks. |

No changes to `RegisterController`, `PortabilityAction`, Docker/network
configuration, or any database schema — exactly as scoped in §11/§28.

---

## 32. `Snep_Request` contract fix and caller-compatibility proof

```php
public static function send_request($url,$ctx){
    $raw_response = @file_get_contents($url,0,$ctx);
    if ($raw_response === false || !isset($http_response_header) || !is_array($http_response_header)) {
        return array(
            "response" => false,
            "response_code" => 0,
        );
    }
    $headers = self::parseHeaders($http_response_header);
    $response = array(
        "response" => $raw_response,
        "response_code" => $headers['response_code'] ?? 0,
    );
    return $response;
}

static function parseHeaders( $headers )	{
    $head = array();
    if(is_array($headers) && count($headers) > 0){
        foreach( $headers as $k=>$v ) { /* unchanged parsing */ }
    }
    return $head;
}
```

`response_code => 0` was chosen deliberately, not `null` and not a
re-thrown exception. Verified live before writing any caller code that
PHP's `switch()` uses loose (`==`) comparison, so `0 == false` is
`true` — meaning every existing caller's own pre-existing `case
false:`-style failure handling becomes reachable **unchanged**, with
zero caller-side code needing to change for the contract fix itself to
be safe. Every caller of `Snep_Request::send_request()` was read before
this change (`Snep_Notifications`, `Snep_Version`,
`SystemstatusController::CloudNotice()` — the only three; confirmed via
`grep -rn "Snep_Request::"`), and all three were then further updated
for the caching work in §33/§34 anyway.

All four crash-inducing transport phases from §7 (DNS, connection
refused, blackhole timeout, TLS failure) were re-verified live against
this fixed code: all now return the safe `response_code=>0` shape with
zero PHP fatals. The success path (§1) is unaffected: verified a normal
200 response still returns the correct body and `response_code` in
0.001s.

---

## 33. `Snep_Notifications` / `Snep_Version` caching implementation

Both follow the identical pattern, reusing only existing
infrastructure (`core_config` for the TTL marker, `core_notifications`
for `Snep_Notifications`' actual cached data) — no new table, no new
service, per §13/§28's own stop condition.

**`Snep_Notifications::getAll()`** (TTL 60s, `core_config` key
`notifications_synced_at`):

```
getAll()
  → cache fresh (within TTL)?  → return getCachedNotifications()
  → touchSyncTimestamp()   -- recorded BEFORE the fetch, so a failing
                               vendor still counts as "recently checked"
                               for the rest of the TTL window
  → fetchFromVendor()      -- returns null on ANY failure (transport,
                               non-200, or non-array decode)
  → success?  → replaceCachedNotifications($fresh); return getCachedNotifications()
  → failure?  → return getCachedNotifications()   -- last-known-good,
                               or empty array if nothing was ever cached
                               (identical to the app's own pre-existing
                               "no notifications" empty state, §9)
```

`getCachedNotifications()` reads `core_notifications` and reshapes each
row into the exact `stdClass{id,title,message,creation_date,status}`
shape `getNoView()` already expects (`$value->status`), so no caller
above `getAll()` needed to change at all.
`replaceCachedNotifications()` does an idempotent delete+insert of the
whole (small) table on every successful refresh — confirmed during
investigation (§9) that `core_notifications` has zero other live
readers/writers, so this is safe. Timeout for the live fetch reduced
5s→2s (§12's own recommendation).

**`Snep_Version::getNewVersions()`** (TTL 300s, `core_config` keys
`update_server_synced_at` / `update_server_latest_version`): identical
shape, except the cached "data" is just the version string itself (or
empty string for "no newer version"), stored directly in `core_config`
rather than a table — `fetchLatestVersionFromVendor()` returns `false`
(never `null`) on any failure, since `null` is itself a legitimate
"vendor says no newer version" success result and must stay
distinguishable from "couldn't ask." Timeout reduced 3s(default)→2s.

Both log via `error_log()` (never `Zend_Registry::get('log')`, per
§22/prior tasks' own established finding that it's unregistered in the
real bootstrap) at most once per TTL window — bounded automatically by
the same "record the attempt before fetching" ordering, so a prolonged
outage never floods the log.

---

## 34. Scope extension: `SystemstatusController::CloudNotice()` / `host_inspect`

**Not part of the original investigation (§1–30).** Discovered during
implementation's own mandatory "read every caller of `Snep_Request`"
step (§32): `CloudNotice()` makes a third implicit foreground vendor
call, on `/systemstatus` itself — the same page the original
investigation already flagged (§26) as operationally critical because
it renders the Asterisk restart controls. This directly contradicted
TASK-0024's own named success criterion for that exact page.

**Measured before any fix**: cold cache, first `/systemstatus` visit,
all three vendor endpoints (`host_notification`, `update_server`,
`host_inspect`) simultaneously unavailable — worst-case **~6.2 seconds**
(3 sequential bounded timeouts stacking: Notifications + Version +
host_inspect, each ~2–3s at the time of measurement).

Implementation was stopped at this point and the user was asked
explicitly (via `AskUserQuestion`) whether to extend TASK-0024's scope
to cover this newly-found third call, rather than silently expanding
scope or silently leaving it unfixed. The user explicitly approved
extending TASK-0024, with a detailed 7-point pre-modification checklist
and an explicit architectural directive: reuse the same
cache/TTL-marker pattern already proven for
Notifications/Version, not a new caching architecture.

**Pre-modification checklist, as answered before writing any code:**

1. **Read the complete method and every caller.** `CloudNotice()` is
   `private`, called from exactly one place —
   `indexAction()`, itself gated by a pre-existing
   `$_SESSION['cloud_noticed']` once-per-session flag.
2. **What does `host_inspect` data represent?** Nothing rendered to the
   user at all — it is a fire-and-forget telemetry **push** (SENMA
   reports local host info **to** the vendor). Its own return value is
   a dead assignment in `indexAction()` (`$put_request`/`$request` are
   never read afterward).
3. **Can the response safely be cached?** N/A — there is no response
   *data* to cache, only an "attempt frequency" to gate, since nothing
   is displayed. This is the key distinction from Notifications/
   Version (which fetch data to *display*): only the TTL-gating half of
   the existing pattern applies here, not the data-caching half.
4. **Cache key/identity?** A single global `core_config` marker
   (`host_inspect_synced_at`), not per-session/per-user — matches
   `Snep_Config::setConfiguration()`'s own module/key shape exactly,
   the same mechanism already used for the other two TTL markers.
5. **Any security-sensitive/per-session value incorrectly shared
   through the cache?** No — nothing is cached at all (point 3); the
   payload itself (`api_key`/`client_key` via
   `Snep_Register_Manager::get()`) is a purely local DB read, unrelated
   to the new TTL marker.
6. **Cache freshness requirements?** None apply to a push with no
   displayed data — only "don't attempt too often" matters, so a
   300-second TTL (matching Version's own bound) was chosen.
7. **Current once-per-session behavior — still necessary after
   caching?** Yes, and left **completely unchanged** —
   `indexAction()`'s own `$_SESSION['cloud_noticed']` gate is untouched.
   The new TTL marker is an **additional**, independent, *global* gate
   that also protects a brand-new session (which the old per-session-only
   gate never did) — whichever gate is more restrictive wins.

**Implementation** (`SystemstatusController.php`):

```php
const HOST_INSPECT_CACHE_TTL_SECONDS = 300;
const HOST_INSPECT_SYNC_CONFIG_NAME = 'host_inspect_synced_at';

private static function hostInspectSyncDue() {
    $configs = Snep_Config::getConfiguration('default', self::HOST_INSPECT_SYNC_CONFIG_NAME);
    if (!$configs || $configs['config_value'] === '') {
        return true;
    }
    return (time() - (int) $configs['config_value']) >= self::HOST_INSPECT_CACHE_TTL_SECONDS;
}

private static function touchHostInspectSyncTimestamp() {
    Snep_Config::setConfiguration('default', self::HOST_INSPECT_SYNC_CONFIG_NAME, (string) time());
}
```

```php
if($configs['config_value'] && self::hostInspectSyncDue()){
  self::touchHostInspectSyncTimestamp();
  $tdm['timeout'] = 2;   // was 3
  $ctx = Snep_Request::http_context($tdm);
  $request = Snep_Request::send_request("{$configs['config_value']}/snep/host/info/{$_SESSION['uuid']}",$ctx);
  if($request['response_code'] == 0){
    error_log('External integration degraded -- integration=host-inspect category=transport_failure http_status=0');
  }elseif($request['response_code'] == 401){
    $ctx = Snep_Request::http_context($tdm,"PUT");
    $put_request = Snep_Request::send_request("{$configs['config_value']}/snep/host/info/{$_SESSION['uuid']}",$ctx);
  }
}
```

**Measured after the fix**: worst case (cold cache, all three vendors
down) **5.259s** (bound asserted at 8s in `external-failure-smoke`'s
own §I) — reduced from ~6.229s, and critically now **bounded and
deterministic** rather than growing further if more implicit calls were
ever added unnoticed. Warm-cache same-session and brand-new-session
subsequent requests: **~1.2–1.25s**, i.e. near local-rendering baseline
— previously the per-session-only gate meant *every new session* paid
the full vendor round-trip at least once; the new global TTL now
protects even a session that has never visited `/systemstatus` before,
as long as the global TTL window is still fresh.

No other independent vendor call was found during this extension —
per the approval's own boundary, this did not become a license to
re-audit the whole codebase again; the check was scoped to
`Snep_Request`'s three actual call sites (§32), all three of which are
now covered.

---

## 35. `make external-failure-smoke` — results

`scripts/external-failure-smoke-test.sh`, run directly against
`docker/external-failure-test/router.php` and reserved/loopback
targets — never the real vendor. Covers modes A–J from §17 plus §I
(added for the CloudNotice extension): cold-cache worst case, warm-cache
same-session, and brand-new-session global-TTL protection, each
asserting HTTP 200, a latency bound, and zero new PHP Fatal Errors on
both `/extensions` and `/systemstatus`.

**Result: 27/27 PASS**, re-confirmed clean on the final combined
codebase (re-run after the transport-smoke diagnostic work in §38 to
rule out any shared-state interaction):

```
PASS: 27   FAIL: 0
```

Notable individual results: blackhole/timeout mode bounded at ~3.07s/
~3.26s (matches the configured timeout); cold-cache-all-vendors-down
worst case 5.259s (bound 8s); warm-cache 1.25s; brand-new-session
1.23s; vendor-recovery checks (§J) both healthy with no restart
required.

---

## 36. Startup independence — proof (executed, not just inferred)

§19's investigation claim (no code path gates startup on vendor
reachability) was additionally **tested**, not just read: with
`host_notification`/`update_server`/`host_inspect` all pointed at an
unreachable local port, the `app` container was force-recreated
(`docker compose up -d --force-recreate app`). Result: container
reported `healthy` in 6 seconds; a fresh login (`POST
/index.php/auth/login`) followed by a dashboard request both succeeded
(final HTTP 200 after redirects, correct `<title>SNEP` page rendered).
Vendor config restored immediately afterward.

---

## 37. Recovery behavior — evidence

Proven at two levels:
- **Page-availability level** (`external-failure-smoke`'s §J, §35
  above): vendor unavailable → local pages healthy → vendor becomes
  available again → next request is healthy with no container restart.
- **Cache-refresh level** (standalone script exercising
  `Snep_Notifications`/`Snep_Version` directly against a controlled
  local server, pre-CloudNotice-extension): cache miss populates
  `core_notifications`/`core_config`; a call within the TTL window
  never re-attempts the network; forcing staleness with the vendor down
  correctly falls back to last-known-good cached data; `getNoView()`
  continues to filter correctly on the cached shape.

No persistent "failed" flag exists anywhere in `Snep_Notifications`/
`Snep_Version`/`SystemstatusController`'s new code — each TTL check is
a fresh, independent read of `core_config`, so recovery requires
nothing beyond the TTL naturally elapsing or the cache already being
fresh.

---

## 38. `make smoke` — 10x healthy, 10x vendor-unavailable

Per the launch policy in §18 (deterministic, not "retry until green"):

- **10 consecutive runs, vendor healthy (real config)**: `PASS: 16
  FAIL: 0` all 10 times, ~4–5s each.
- **10 consecutive runs, vendor unavailable** (`host_notification`/
  `update_server`/`host_inspect` pointed at a closed local port,
  `192.168.0.1` — actually `127.0.0.1:1`, connection-refused, all TTL
  markers and the notification cache cleared first): `PASS: 16 FAIL: 0`
  all 10 times, ~4–5s each — **identical to the healthy baseline**,
  confirming the fix genuinely removes vendor reachability as a factor
  in `make smoke`'s determinism, not merely makes failure less likely.
  25 "External integration degraded" log lines were recorded during
  this run (confirmed via `grep -c` on the app's error log), proving
  failures are observable, not silently swallowed, even while every
  page stays healthy.

Vendor config restored to its real value after each run.

---

## 39. Full regression suite — results

| Suite | Result | Notes |
|---|---|---|
| `make smoke` | 16/16, repeated 10x+10x (§38) | clean |
| `make call-smoke` | 17/18 PASS | 1 known, pre-existing, out-of-scope failure — CDR/report timezone artifact, not a regression (§40) |
| `make trunk-smoke` | 21/23 PASS | 2 instances of the same known CDR/report timezone artifact (outbound + inbound reporting checks), not a regression (§40) |
| `make transport-smoke` | 63/63 | clean, after two unrelated operational diagnostics (§41) |
| `make restart-smoke` | 37/37 | clean |
| `make external-failure-smoke` | 27/27 | clean (§35) |

No test failure traced to any TASK-0024 code change
(`Snep_Request`/`Snep_Notifications`/`Snep_Version`/`Snep_Config`/
`SystemstatusController::CloudNotice()`). Not fixed, per this task's own
scope and the project's established precedent for pre-existing/unrelated
debt (TASK-0023's own bounded-retry handling of the
`Snep_Notifications` flake): the CDR/report timezone artifact (§40),
RBAC debt, user-management cosmetic warnings, transport restart
semantics, and the vendor-content XSS finding (§23, unchanged).

---

## 40. CDR/report timezone artifact — evidence (not fixed, pre-existing)

Both `call-smoke`/`trunk-smoke` "SENMA reporting path can read it"
checks failed identically and reproducibly during this session's final
regression pass: the CDR row itself was created and stored correctly
(the immediately-preceding "CDR row exists and is correct" check always
passed), but the reporting API's own day-range filter (`calldate
BETWEEN '<today> 00:00:00' AND '<today> 23:59:59'`) computed a
different calendar day than the CDR row's own `calldate`. Root cause,
confirmed live:

```
$ date                              # host + all containers agree
Thu Aug 27 21:29:54 -03 2026
$ SELECT NOW();                     -- MariaDB session, time_zone=SYSTEM
2026-08-27 21:30:53                 -- local, matches host
$ php -r 'echo date("c");'          -- PHP's own default timezone
2026-08-28T00:30:50+00:00           -- UTC, 3 hours ahead
```

PHP's default timezone is UTC while MariaDB's `time_zone` is `SYSTEM`
(local, `-03`). A CDR row for a call placed at 21:28 local
(`2026-08-27`) gets a `calldate` computed via PHP as `2026-08-28
00:28:36` (UTC), which falls **outside** a report query's
locally-anchored "today" range whenever the two clocks disagree about
which calendar day it currently is — a ~3-hour nightly window
(21:00–00:00 local = the first 3 hours of the next UTC day) in which
any call's CDR row appears to have happened "tomorrow" from the
report's point of view. This session's final regression pass happened
to run inside that exact window. Reproduced twice (once per suite);
both failures share this identical, single root cause. This matches
the "CDR timezone artifact" already named as explicitly out of scope in
§29/the approved implementation spec — confirmed here with concrete
evidence rather than merely asserted, but intentionally **not fixed**,
per instruction.

---

## 41. Operational diagnostics during final validation (not code regressions)

Two unrelated environmental issues were hit and resolved while running
the final regression pass, neither caused by any TASK-0024 code change:

1. **Leftover fixture from an earlier interrupted `make transport-smoke`
   run.** An orphaned `peers` row (`id=87`, `name='1'`, `callerid`
   matching the disposable `task0018-transport-smoke t20 lifecycle
   trunk fixture` marker) survived a prior manual cleanup because that
   cleanup's HTTP delete call used the wrong `name` value —
   `TrunksController::removeAction()` deletes the `peers` row by
   whatever `name` the delete form posts (looked up correctly by
   `delete_trunk_fixture()`'s own helper, but not when a manual
   HTTP delete is constructed by hand). This caused a real, reproduced
   `SQLSTATE[23000]... Duplicate entry '1' for key 'name'` on the next
   trunk-fixture creation (`trunks`/`peers.name` is a genuine `UNIQUE`
   column). Confirmed disposable via its `callerid` marker and the fact
   that the `trunks` table itself had zero rows (fully orphaned, no
   live trunk referenced it), then removed via direct SQL. Verified
   zero `task00xx`-prefixed fixtures remained anywhere afterward.
2. **Container-recreate race on `PJSIP module Running`.** `make
   transport-smoke`'s `up` prerequisite (`docker compose up -d
   --build`) recreates the `asterisk` container on every invocation
   (BuildKit's own provenance/attestation manifest changes even with
   every layer cached, which is enough for Compose to consider the
   image "changed"). The test script's own PJSIP-module readiness check
   has no retry/wait built in, and ran once, immediately after `docker
   compose ps` reported the container `healthy` — before `res_pjsip.so`
   had finished loading. Confirmed via a direct `asterisk -rx "module
   show like res_pjsip.so"` poll (ready within 1 second) that this was
   purely a timing race, not a functional failure; re-running the test
   script directly (bypassing another `up --build` recreate cycle)
   passed cleanly (63/63).

Neither issue touches `Snep_Request`/`Snep_Notifications`/
`Snep_Version`/`Snep_Config`/`CloudNotice()` or any file this task
modified — both are pre-existing environmental/test-infrastructure
characteristics, surfaced only because this was an unusually long,
multiply-interrupted validation session. Not fixed, per this task's own
scope (no unrelated test-infrastructure changes).

---

## 42. Final validation totals / commit checkpoint

- `make external-failure-smoke`: **27/27**
- `make smoke`: **16/16 × 10 (vendor healthy)**, **16/16 × 10 (vendor
  unavailable)**
- `make call-smoke`: **17/18** (1 known CDR/report timezone artifact, §40)
- `make trunk-smoke`: **21/23** (2 instances of the same artifact, §40)
- `make transport-smoke`: **63/63**
- `make restart-smoke`: **37/37**
- Startup independence: proven (§36)
- Recovery behavior: proven (§37)
- XSS finding (§23): unchanged, documentation-only follow-up debt
- Scope: no changes to `RegisterController`, `PortabilityAction`,
  Docker/network configuration, or database schema

Stopping at the TASK-0024 commit checkpoint, as instructed. Do not
begin TASK-0025.
