# TASK-0006A — System Status loopback fix

## Objective
Fix the confirmed root cause of `SystemstatusController::indexAction()`'s
500 error in the current Docker/Asterisk topology: an internal loopback
HTTP request that targeted the wrong port. Scope deliberately narrowed to
`SystemstatusController.php` only — see "Not resolved by this task" below
for why `systemstatus` still isn't a full PASS.

## Original 500 — root cause

`indexAction()` fetches `lib/linfo/index.php?out=xml` via an internal
loopback HTTP request (`Zend_Http_Client`), to populate `$this->sysInfo`
with OS/CPU/memory data before rendering. The URL was built as:
```php
$serverport = $_SERVER['SERVER_PORT'];
$linfoData = new Zend_Http_Client('http://localhost:'.$serverport . ... );
```
Reproduced live: this produced `http://localhost:8080/lib/linfo/index.php?out=xml`,
which fails with `Zend_Http_Client_Adapter_Exception`:
`Unable to Connect to tcp://localhost:8080. Error #111: Connection refused`
(confirmed message text matches `snep/lib/Zend/Http/Client/Adapter/Socket.php:236`
exactly). The exception was never caught (see below), so it propagated
uncaught up to Zend's own front-controller error handler, which rendered
the generic 500 page.

## Why `SERVER_PORT` was wrong in Docker

Confirmed empirically, not assumed: `$_SERVER['SERVER_PORT']` reflects the
**client-supplied `Host:` header's port**, not Apache's actual listening
port. Proved by sending a request with a fabricated `Host: localhost:9999`
header — `SERVER_PORT` reported `9999`. This is Apache's documented
default behavior under `UseCanonicalName Off` (the default; not
overridden anywhere in `docker/apache-mag.conf`). Separately confirmed
the container's actual, fixed internal listening port is unconditionally
**80** — `docker/apache-mag.conf:1`: `<VirtualHost *:80>`. The externally
visible `8080` is purely the host-side Docker publish mapping
(`compose.yaml`'s `"${MAG_HTTP_PORT:-8080}:80"`) and has no meaning
inside the container — nothing listens on 8080 there. The code was
written assuming `SERVER_PORT` reliably reflects the server's own
listening port (true on a traditional bare-metal host, false here, and
trivially spoofable regardless of Docker).

## Why `HttpException` was the wrong exception type

`indexAction()` caught `catch (HttpException $ex)`. Confirmed via
`class_exists('HttpException')` inside the app container → **`false`** —
this class (the PECL `pecl_http` extension's) does not exist anywhere in
this PHP environment. `Zend_Http_Client::request()`/its adapters only
ever throw `Zend_Http_Client_Exception` or its subclass
`Zend_Http_Client_Adapter_Exception` (confirmed via every `throw` site in
`snep/lib/Zend/Http/Client.php` and `Client/Adapter/{Socket,Curl}.php`).
Since the thrown exception was never an instance of a class that doesn't
exist, PHP's catch-type matching never matched, and the exception simply
propagated past the `try`/`catch` uncaught — no separate fatal, just a
catch block that could never fire.

## Fix applied

`snep/modules/default/controllers/SystemstatusController.php`, 2 changes:
1. Loopback URL now targets `http://127.0.0.1:80` explicitly, with a
   comment explaining why (loopback to the same Apache container;
   `MAG_HTTP_PORT`/8080 has no meaning inside the container;
   `SERVER_PORT` reflects the client's `Host` header, proven above, and
   must not be used here). The base-path handling
   (`str_replace("/index.php", "", $this->getFrontController()->getBaseUrl())`)
   is unchanged — it's derived from `$_SERVER['SCRIPT_NAME']`
   (`Bootstrap.php:45`), which is path-only and was never affected by the
   port bug.
2. `catch (HttpException $ex)` → `catch (Zend_Http_Client_Exception $ex)`
   — the exact common parent covering every real throw site of the
   wrapped `Zend_Http_Client` call (proven above), not a broadening to
   `Exception`/`Throwable`. The existing fallback behavior inside the
   catch block (`echo $ex;`, then continue rendering with whatever
   `$this->sysInfo` ended up as) is unchanged.

## Validated post-fix behavior

- `php -l`: clean.
- `GET /lib/linfo/index.php?out=xml` from inside the app container, via
  `127.0.0.1:80` explicitly: HTTP 200, valid parseable XML (confirmed via
  `simplexml_load_file()`, not just eyeballed).
- Authenticated `GET /index.php/default/systemstatus`: **HTTP 200** (was
  500). Response is a real rendered HTML fragment, not an error page or a
  raw exception dump. linfo-derived data genuinely present and correct:
  `Debian GNU/Linux 13`, `Linux 6.12.54-linuxkit` (kernel), uptime
  ("Tempo Ligado"), memory usage, disk usage, installed module list,
  SNEP version, MySQL/MariaDB version.
- `make smoke`: **15 PASS, 0 FAIL, 0 EXPECTED_LIMITATION** — unchanged
  from the TASK-0005 baseline. `scripts/smoke-test.sh` was not modified;
  `systemstatus` was deliberately not added to it (see below). App log
  fatal-error count: `0 → 0`, zero new PHP Fatal Errors.

## New finding: AMI "Command" response-format incompatibility — not fixed here

Investigated why the Asterisk-derived field was still empty
(`Asterisk - `, no version) after the loopback fix, using a temporary
debug trace (added, inspected, then fully removed — the committed diff
contains only the two changes above). Root cause, confirmed via a raw AMI
protocol exchange that bypassed the PHP client entirely:

```
Action: Command
Command: core show version

Response: Success
Message: Command output follows
Output: Asterisk 22.10.1 built by root @ buildkitsandbox on a aarch64 running Linux ...
```

`Asterisk_AMI::wait_response()` (`snep/lib/Asterisk/AMI.php:112-181`) only
recognizes the legacy AMI "Command" response shape it was written against
(its own docblock: "tested on asterisk 1.6.x and 1.8.x") — a header
literally valued `Follows` (`Response: Follows`), payload accumulated
under a `data` key until a `--END COMMAND--` sentinel line. Asterisk 22
replies `Response: Success` / `Message: Command output follows` /
`Output: <content>` instead — a different shape entirely.
`wait_response()` never populates `$parameters['data']` for this shape,
so `AsteriskInfo::status_asterisk()` silently returns `''` for **every**
AMI "Command" action, with no exception and no error — just empty data.

**Blast radius**: `status_asterisk()` (and thus this exact bug) is also
used by `TrunksController`, `TdmLinksController`, `KhompLinksController`,
`ExtensionsController`, `ErrorsKhompController`, `ErrorsTdmController` —
most of the application's Khomp/TDM/trunk status-monitoring surface, not
only `systemstatus`.

This lives entirely in `snep/lib/Asterisk/AMI.php`, a different file, and
is a real AMI-protocol-version-compatibility investigation in its own
right — explicitly out of this task's `SystemstatusController.php`-only
scope. Not touched. Not attempted.

## `systemstatus` is not yet PASS

**Explicit note, as instructed**: `systemstatus` returns HTTP 200 with
real, meaningful linfo-derived content, which is genuine, validated
progress over the prior 500 — but it is **not** considered a full PASS.
The Asterisk-version/AMI-derived data required for that is still missing
(`Asterisk - ` renders empty; the status indicator shows red/"off"),
blocked by the AMI response-format incompatibility above. Accordingly:
- `scripts/smoke-test.sh` was **not** modified — `systemstatus` was not
  added as a smoke-tested flow.
- `make smoke`'s baseline is unchanged from TASK-0005: 15 PASS / 0 FAIL /
  0 EXPECTED_LIMITATION.
- Reaching genuine `systemstatus: PASS` (with real AMI data present)
  requires a follow-up task scoped to `snep/lib/Asterisk/AMI.php`'s
  `wait_response()` parsing logic — not part of this task.

## Files changed
- `snep/modules/default/controllers/SystemstatusController.php` — 2
  sites: loopback URL construction, caught exception type.

## Not modified (per instruction, in TASK-0006A)
`snep/lib/Asterisk/AMI.php`, `scripts/smoke-test.sh`, Asterisk
configuration, ODBC, PJSIP, AGI runtime.

---

# TASK-0006B — AMI Command response compatibility

## Objective
Fix the AMI response-parsing incompatibility identified in TASK-0006A:
`Asterisk_AMI::wait_response()` only understood the legacy AMI "Command"
response shape, so every caller reading `['data']` got silently empty
results against Asterisk 22.

## Legacy AMI framing (what this class was written against)
```
Response: Follows
<raw multi-line command output>
--END COMMAND--
```
`wait_response()` detects this only by checking, on the *first* line of a
response block, whether that header's *value* is literally `"Follows"` —
then switches to reading raw, un-trimmed lines into `$parameters['data']`
until a `--END ` line appears.

## Asterisk 22 framing (captured live, raw protocol, bypassing the PHP client)
```
Response: Success
Message: Command output follows
Output: <line 1>
Output: <line 2>
...
```
— confirmed across single-line (`core show version`), multi-line
(`core show codecs`, 50 lines), and **error** cases (`khomp summary
concise` → `Response: Error` + the same `Output:`-per-line framing).
Confirmed via 5 other action types (`Login`, `Ping`, `Status`,
`CoreStatus`, `QueueStatus`) that `Output:` headers **never** appear
outside the Command action, success or failure — the presence of an
`Output:` header, not the `Response:` value, is what actually indicates
"this is Command output."

## Compatibility contract implemented
`snep/lib/Asterisk/AMI.php`, `wait_response()` only, purely additive next
to the existing "store parameter" line (the legacy `Follows` branch above
it is untouched):
```php
$key = substr($buffer, 0, $a);
$value = substr($buffer, $a + 2);
$parameters[$key] = $value;

if ($key === 'Output') {
    $parameters['data'] = ($parameters['data'] ?? '') . $value . "\n";
}
```
`$parameters['Output']` still gets set exactly as before (last value,
unchanged, unused by any caller but preserved). Gated strictly on the
literal key `Output`, not on `Response`'s value — so `Response: Error`
Command replies populate `data` exactly like `Response: Success` ones,
proven below. `wait_event()`/`process_event()` were not touched; traced
and confirmed they never receive Command-shaped (`Output:`-framed)
responses at all — they're used only for the separate `Agents`/`Status`
AMI actions, which respond via event streams.

## Multi-line handling
Every repeated `Output:` line is appended, in order, joined by `"\n"`,
with a trailing `"\n"` after the final line — reproducing the legacy
`Follows`-branch's trailing-newline behavior, which `PBX_Khomp_Info::
boardInfo()` depends on (`array_pop($lines)` after `explode("\n", ...)`
to drop the expected trailing empty element).

## Validation performed
- `php -l`: clean. Diff confined to `wait_response()`; `wait_event()`
  unchanged (confirmed via `git diff`).
- AMI login via SENMA's own `Asterisk_AMI::connect()`: still succeeds.
- `Ping` (non-Command action) via the real client: unchanged shape
  (`Response`, `Ping`, `Timestamp`), **no** `data` key introduced —
  confirms the fix cannot fire on non-Command responses.
- `Command("core show version")` via the real client: `data` present,
  contains `22.10.1`, ends with a newline.
- `Command("core show codecs")` (50-line multi-output) via the real
  client: `data` contains all 50 lines in original order (first line
  "Disclaimer: this command is...", last line the `siren14` codec row),
  both `ulaw` and `opus` present, single trailing newline — proves
  accumulation, not last-value-wins.
- `Command("khomp summary concise")` (error-producing, no Khomp module in
  this image): `Response` remains `Error`, `Message` remains available,
  `Output` remains available (single value, existing behavior preserved),
  **and** `data` correctly contains the "No such command..." text — proves
  the fix is gated on `Output:` framing, not on `Response: Success`.
- `PBX_Interfaces::getCodecs()` exercised through the real, unmodified
  SENMA code path (`GET /index.php/default/extensions/add`, authenticated):
  real codec `<option>` tags rendered (`alaw`, `ulaw`, `gsm`, `opus`,
  correct `selected` defaults) — proves the fix works through an actual
  first-party caller, not just direct AMI calls. (That same page later
  hits an unrelated, pre-existing PHP 8 bareword-constant fatal in
  `modules/default/views/scripts/extensions/addedit.phtml:344` —
  confirmed unrelated to AMI/this change, out of scope, not fixed.)
- Authenticated `systemstatus`: **HTTP 200**, `Asterisk - 22.10.1`
  genuinely rendered (was `Asterisk - ` empty), status indicator now green
  (`#96d190`, was red `#f0625f`), no raw exception/fallback output.
- `scripts/smoke-test.sh`: added a `systemstatus` check using the real
  AMI-derived version string (`'Asterisk - 22.10.1'`) as the marker —
  deliberately not HTTP 200 alone, and deliberately not a generic HTML
  marker, since only a genuinely-working AMI round-trip can produce it.
- `make smoke`, run twice: **16 PASS, 0 FAIL, 0 EXPECTED_LIMITATION**,
  identical both times (`queues` and `systemstatus` both PASS). App log
  fatal-error count: `0 → 0` both runs. Asterisk log
  (`/var/log/asterisk/full`): only the same expected missing-optional-
  config declines from TASK-0005's minimal config, no new errors.

## `systemstatus` is now PASS
Unlike TASK-0006A, all stated requirements are met: HTTP 200, meaningful
linfo data, genuine AMI-derived Asterisk version, correct running
indicator, no fallback output. `make smoke` reflects this as a real PASS.

## Files changed
- `snep/lib/Asterisk/AMI.php` — `wait_response()`, ~15 lines
  (implementation + explanatory comment).
- `scripts/smoke-test.sh` — new `systemstatus` check.

## Remaining AMI runtime debt
- `extensions/addedit.phtml:344`'s unrelated bareword-constant fatal
  (found incidentally while validating `getCodecs()`) — not fixed, not
  part of this task; a PHP 8 compatibility item for a future batch.
- Reload-only AMI Command callers (`ConferenceRoomsController`,
  `Snep_InterfaceConf`, `Snep_Locale`) were not individually re-validated
  beyond confirming they never read `['data']` — they were unaffected by
  the original bug and remain unaffected by this fix.
- Everything else already recorded as out of scope in TASK-0005/0006A:
  ODBC, PJSIP, AGI runtime, Asterisk configuration.
