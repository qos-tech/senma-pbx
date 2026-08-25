# TASK-0009: First real PJSIP internal call

## Goal

Prove the smallest real call path through the existing SENMA runtime, using
PJSIP as the channel technology instead of chan_sip:

```
PJSIP/1000 -> existing extensions.conf -> existing SENMA AGI (snep/snep.php)
  -> existing PBX_Rules/PBX_Dialplan rule engine -> PBX_Rule_Action_DiscarRamal
  -> PBX_Asterisk_Interface_PJSIP -> Dial(PJSIP/1001) -> answered call
  -> real cdr_adaptive_odbc CDR row -> existing SENMA report reads it back
```

This is a development proof, not the PJSIP provisioning architecture. No
trunks, inbound routes, queues, voicemail, IVR, realtime PJSIP tables, or
`Snep_InterfaceConf` changes are part of this task.

Builds on TASK-0007 (ODBC/CDR backend) and TASK-0008 (runtime audit, which
mapped the call-routing architecture this task exercises for the first time
with a real channel).

## Result

`make call-smoke` passes 13/13 from a fully clean rebuild (both `asterisk-etc`
and `astvarlibdir` volumes wiped, images rebuilt, no manual patches). `make
smoke` remains 16 PASS / 0 FAIL / 0 EXPECTED_LIMITATION.

## 1. AGI runtime

### Filesystem

`./snep` is bind-mounted read-only into the `asterisk` service at the same
absolute path the `app` service already uses, `/var/www/html/snep`
(`compose.yaml`) -- not copied into the image. Several config values
hardcode that exact path (`voicemail.conf`'s `externnotify=/var/www/html/
snep/agi/voicemail-notify.php`, `setup.conf`'s `path_voz`), and
`Bootstrap.php` needs its natural sibling directories (`../lib`,
`../includes`) present, not just `agi/` in isolation.

**astagidir was NOT repointed at `.../snep/agi`.** extensions.conf/
snep-features.conf call AGI scripts with a `snep/` prefix baked in (e.g.
`AGI(snep/snep.php)`), so Asterisk resolves `<astagidir>/snep/snep.php`.
Repointing `astagidir` directly at `.../snep/agi` produces a real, confirmed
double path (`.../snep/agi/snep/snep.php`, "File does not exist"). Instead
`astagidir` stays at the default `/var/lib/asterisk/agi-bin`, and
`asterisk-entrypoint.sh` creates `agi-bin/snep` as a symlink to
`/var/www/html/snep/agi` on every boot (`ln -sfn`, unconditional/idempotent,
in the `astvarlibdir` volume). This is the same "symlink farm" pattern
TASK-0001/0008 found in the legacy (non-Docker) install, not a new
invention.

### `[directories](!)` was a silent no-op -- found and fixed

`docker/asterisk-config/asterisk.conf` inherited `[directories](!)` verbatim
from the vendored `snep/install/etc/asterisk/asterisk.conf`. `(!)` marks a
category as a *template* in Asterisk's config parser; templates are excluded
from normal category lookups unless something else explicitly inherits from
them, which nothing here did. Every value in that section was a silent
no-op. This went unnoticed since TASK-0005 because `astetcdir`/`astmoddir`/
`astvarlibdir`/etc. all happened to match Asterisk's own compiled-in FHS
defaults. `astagidir`'s compiled-in default (`/var/lib/asterisk/agi-bin`,
always empty) does not, which is what surfaced it: a live call failed with
`Failed to execute '/var/lib/asterisk/agi-bin/snep/snep.php': File does not
exist` even though the file on disk already said the (initially, incorrectly
chosen) new path -- `core show settings` confirmed the running process was
using the compiled-in default, not the file. Fixed by removing `(!)`,
making it a normal category (`[directories]`).

### PHP interpreter -- traced, not copied from app.Dockerfile

The `asterisk` container had no PHP interpreter at all before this task.
Rather than installing what `app.Dockerfile` installs, the actual
Bootstrap.php + internal-call code path was traced:

- `Snep_Db::getInstance()` uses Zend_Db's `Pdo_Mysql` adapter -> needs
  `pdo_mysql`.
- `Snep_Modules::registerModule()` (called from every single AGI's
  `Bootstrap::startModules()`) calls `simplexml_load_file()` on every
  module's `info.xml`/`resources.xml` -> needs `dom`/`simplexml`/`xml`.
- `Bootstrap.php`/`snep.php` call `pcntl_signal()`.
- `Snep_Locale` uses `Zend_Locale`/`Zend_Translate` -- pure-PHP, no
  `ext-intl` calls found (`Zend_Locale::isLocale()` etc. are hand-rolled,
  not ICU-backed).

No `mb_*`, `ZipArchive`, or other extension-specific calls were found on
this path. `ext-intl`/`ext-zip`/`ext-mbstring` (which `app.Dockerfile`
installs for the web UI) are genuinely unused here and were **not**
installed.

Installed (Debian 13 packages): `php8.4-cli` (`/usr/bin/php`), `php8.4-cgi`
(`/usr/bin/php-cgi` -- both AGI shebangs verified to resolve), `php8.4-mysql`
(`pdo_mysql`+`mysqli`, one package, can't be split further), `php8.4-xml`
(`dom`+`simplexml`+`xml`+`xmlreader`+`xmlwriter`). `pcntl`, `posix`,
`session`, `sockets`, `ctype`, `json`, etc. come bundled with
`php8.4-cli`/`php8.4-common` at no extra cost.

### `register_argc_argv` -- PHP 8.4 runtime config gap, not a SENMA bug

The first live call produced a clean AGI exit (rc=0) but never dialed.
`/var/log/snep/agi.log` (see below) showed:

```
ERR (3):argv is not available, because ini option 'register_argc_argv' is set Off
```

`snep.php`/several other AGI entrypoints parse their own argv
(`Zend_Console_Getopt`) for the `-x`/`-o`/`-v` flags Asterisk's dialplan
passes. CLI SAPI always forces `register_argc_argv` on regardless of ini;
CGI SAPI (what `snep.php`'s `#!/usr/bin/php-cgi` shebang uses) honors the
ini setting and defaults it Off. `Zend_Console_Getopt::parse()` throws
immediately, caught by `snep.php`'s own catch block, which logs and exits
-- before the dialplan rule engine ever runs. This is a PHP **runtime
configuration** requirement (a deployment `php.ini` directive), not a PHP
8.4 language-level incompatibility in SENMA's code -- fixed via
`docker/php-agi.ini` (`register_argc_argv = On`), installed into both the
cli and cgi `conf.d/` directories, within item 1's "install the minimum PHP
8.4 runtime" scope. No SENMA source was touched for this.

### `/var/log/snep` -- also needed in this container now

`Bootstrap::startLogger()` (run on every AGI invocation) unconditionally
opens `<path.log>/agi.log` via `Zend_Log_Writer_Stream`, independent of
Asterisk's own `/var/log/asterisk`. `app.Dockerfile` already creates
`/var/log/snep` (TASK-0001); `asterisk.Dockerfile` now does too -- it was
simply never needed there before real AGI execution existed.

### No PHP 8.4 SENMA code bugs found on this path

Static analysis was already clean here (TASK-0002/0004 covered
`Bootstrap.php`, `snep.php`, `PBX_Dialplan`/`PBX_Rules`, `DiscarRamal.php`,
`PBX_Usuarios.php`, `Asterisk_AGI.php`). Live execution confirmed it: the
full call trace (below) shows `snep.php` running, matching the rule,
dialing, and exiting cleanly with no PHP fatal or warning anywhere in the
AGI/dialplan path. The one real PHP 8.4 fatal this task's validation
surfaced (`CallsReportService.php`) is in the HTTP report layer, not the
AGI path -- see §7.

## 2. Shared Asterisk configuration permissions

Deterministic shared group, not an unexplained magic number: `senma-config`,
GID **3000**, created identically (`groupadd -g 3000 senma-config`, an
explicit fixed GID, not left to per-image auto-allocation) in both
`asterisk.Dockerfile` and `app.Dockerfile`. 3000 was chosen empirically: the
max auto-assigned system GID in either base image is 999 (checked via
`getent group`/`id`), so 3000 sits safely above both images' own
auto-assigned ranges and below the conventional 1000+ "real user" range,
minimizing collision risk in either direction. `asterisk` and `www-data`
are both added as supplementary members.

Only `/etc/asterisk/snep/` is made group-writable and setgid (`chmod 2775`,
`chgrp senma-config`) by `asterisk-entrypoint.sh`, on every first-boot
assembly. The rest of `/etc/asterisk` stays `0755 asterisk:asterisk`,
exclusively controlled by the Asterisk runtime. `compose.yaml`'s `app`
service mount changed from `:ro` to read-write (Docker doesn't support
per-subdirectory mount permissions on a single named volume), but real
write protection comes from filesystem permissions, not the mount flag.

Verified live (as the actual `www-data`/`asterisk` runtime users, not
root):

```
asterisk: uid=997(asterisk) gid=997(asterisk) groups=997(asterisk),3000(senma-config)
www-data: uid=33(www-data) gid=33(www-data) groups=33(www-data),3000(senma-config)

drwxrwsr-x asterisk senma-config  /etc/asterisk/snep

$ touch /etc/asterisk/snep/.test   (as www-data)  -> succeeds
$ touch /etc/asterisk/.test        (as www-data)  -> Permission denied
```

`Snep_InterfaceConf` itself is untouched -- this only makes the filesystem
architecture valid ahead of that future milestone.

## 3. PJSIP build

`docker/asterisk.Dockerfile` switched `./configure --without-pjproject-bundled`
(TASK-0005) to `--with-pjproject-bundled` (the Asterisk-documented default).
Debian 13 ships no system `pjproject` package at all (empty apt-cache
result), so this is the only viable path, not a preference.

Verified live during the build: pjproject **2.17** is downloaded from
`https://raw.githubusercontent.com/asterisk/third-party/master/pjproject/2.17/pjproject-2.17.tar.bz2`
and MD5-verified against `third-party/pjproject/pjproject-2.17.tar.bz2.md5`
-- a checksum file physically shipped inside the Asterisk 22.10.1 source
tarball itself, not fetched from the same server at build time. This pins
the pjproject version to this exact Asterisk release, not "whatever is
latest" -- the build stays reproducible.

`modules.conf`'s five `noload => res_pjsip*`/`chan_pjsip` lines were
removed; no new PJSIP-specific noload was added back. The full
`res_pjsip_*` family (registrar, digest authenticator, endpoint identifier,
etc.) autoloads and all 51 report `Running` -- these are needed even for
the minimal two-endpoint register+call scenario, and none of it activates
PJSIP realtime (that requires a `sorcery.conf` realtime backend, which does
not exist in this config; `pjsip.conf` is flat/static).

A new runtime dependency surfaced by the pjproject build itself:
`libasteriskpj.so.2` (Asterisk's own pjproject wrapper library, dynamically
loaded by `chan_pjsip.so`/`res_pjsip*`) was not being copied into the
runtime image stage -- added alongside the existing `libasteriskssl.so*`
copy.

## 4. Test-only PJSIP configuration

`docker/asterisk-config/pjsip.conf` (new) -- one `[transport-udp]`, and for
each of 1000/1001: an `endpoint`, `auth`, and `aor` section. Explicitly
headed as TASK-0009-only, will be replaced by the provisioning milestone.
Passwords templated by `asterisk-entrypoint.sh` from `PJSIP_TEST_1000_SECRET`
/ `PJSIP_TEST_1001_SECRET` (`.env`), same pattern as AMI/DB credentials.

**One real bug found and fixed during validation:** the AOR sections were
initially named `[1000-aor]`/`[1001-aor]`. `res_pjsip_registrar` looks up
the AOR to register against by matching the REGISTER request's URI username
*directly against an AOR object's own sorcery name* -- not just anything
listed in the endpoint's `aors=`. A live baresip REGISTER attempt reproduced
this exactly:

```
WARNING res_pjsip_registrar.c: AOR '' not found for endpoint '1000' (...)
-> 404 Not Found
```

Fixed by naming the AOR sections `[1000]`/`[1001]` (same name as the
endpoint -- legal and idiomatic: Asterisk's config parser treats each
`type=` as a separate sorcery namespace, and repeated same-named sections
differentiated by `type=` is the standard minimal pjsip.conf convention;
`module_tmp`/category-append confirmed via a live `pjsip show endpoints`
showing `Aor: 1000` correctly after the fix, and REGISTER succeeding with
`200 OK`).

## 5. SENMA runtime compatibility layer

Exactly the two files predicted by TASK-0008's audit, nothing more:

- `snep/lib/PBX/Asterisk/Interface/PJSIP.php` (new) -- mirrors
  `PBX_Asterisk_Interface_SIP` exactly (`getCanal()` returns
  `"PJSIP/" . username`). `getHost()` was deliberately not carried over --
  unused on this path.
- `snep/lib/PBX/Usuarios.php` -- one new `else if ($tech == "PJSIP")`
  branch in the existing tech-dispatch chain, identical shape to the `SIP`
  branch.

Confirmed empirically that nothing else on the plain internal-call path is
chan_sip-specific: `Asterisk_AGI::exec_dial()` builds a generic
`EXEC Dial "<channel>,<timeout>,<flags>"` string, technology-agnostic.
`DiscarRamal`'s only tech-conditional code (`SIPAddHeader` for diff-ring) is
`if ($tech == "SIP")`-gated and simply doesn't fire for `PJSIP` (no
compatibility shim needed, confirmed by the successful live call using
`diff_ring` off by default). `PBX_Interfaces::getChannelOwner()` (used to
identify the calling party from the raw Asterisk channel string) matches
via `preg_match` against the DB `canal` column value, also fully
technology-agnostic.

**No new Route/rule was created.** The `regras_negocio` table already had
a seeded, generic, active rule (`"Internas - Ramal para Ramal"`,
`origem=G:all`, `destino=G:all`) whose actions are exactly
`PBX_Rule_Action_CCustos` then `PBX_Rule_Action_DiscarRamal` -- this is
what actually ran the call, unmodified.

## 6. Development DB fixtures

`scripts/call-smoke-test.sh` creates two `peers` rows only if they don't
already exist, marked with `secret='task0009-fixture'` (a clearly
non-production value). If an extension 1000/1001 row already exists and is
**not** this exact fixture marker, the script **STOPs** (exit 1, no write)
with an actionable message rather than overwriting anything -- verified
live by pre-inserting a real-looking `SIP/1000` row and confirming the
script refused to touch it. Rows the script itself created are deleted in
an `EXIT` trap-based cleanup (self-disarming against double-invocation),
so a normal run leaves no residue; rows that already existed as
someone else's fixture are left alone entirely.

Neither `schema.sql` nor `system_data.sql` was touched -- these are pure
runtime fixtures, not seed data.

## 7. Test endpoint tooling

**Correction of TASK-0008's own recommendation:** SIPp is not packaged for
Debian 13 at all (`apt-cache policy sipp` / `apt list` both empty,
re-verified during this task). `baresip` 1.1.0-3 and `sipsak` 0.9.8.1-1
both are real Debian 13 packages.

`docker/baresip-test.Dockerfile` (new, not part of `compose.yaml` -- no
permanent service, built on demand by the smoke script) + two disposable,
unpublished containers on the same Docker network as `asterisk`
(`--network`, resolved dynamically from the running asterisk container's
own network, not hardcoded). `docker/baresip-test/config.template` +
`accounts.template` (new, checked in) drive them:

- `audio_player`/`audio_source` switched from `alsa` (no device in a
  headless container) to `ausine`, baresip's built-in sine-wave generator.
- `ausrc_srate`/`auplay_srate` forced to 48000 -- ausine's only supported
  rate; baresip's own resampler handles the down-convert to the negotiated
  8000Hz PCMU/PCMA. Omitting this produced a real, confirmed
  `audio: start_source failed (ausine.440): Operation not supported` that
  silently blocked call answer despite the callee logging its intent to
  answer.
- `module_tmp uuid.so`/`account.so` -- confirmed **not optional**: a
  hand-minimized config that omitted these silently skipped UUID/account
  initialization entirely (no error logged, no registration ever
  attempted). The committed template is baresip's own generated template,
  patched, not hand-rolled from scratch.
- `ctrl_tcp` module (JSON-over-netstring-framed TCP, port 4444) drives
  `/dial` programmatically -- this image has no interactive TTY. One real
  gotcha: `ctrl_tcp` keeps the connection open streaming RTCP stats every
  ~2s once a call is established, so `nc -w N`'s *idle* timeout never
  fires under continuous traffic; the script uses `timeout N nc ...`
  (a hard cutoff) instead.
- 1000: `answermode=manual` (it originates). 1001: `answermode=auto` (it
  receives and auto-answers, matching "destination answers" without a
  human).

`sipsak` was not additionally used -- the two-endpoint baresip proof
already fully covers registration/call/answer/hangup; nothing sipsak adds
was needed to close out this task.

## 8. Real call trace

Actual Asterisk log excerpt from a validation run (channel/uniqueid
numbers vary per run):

```
INVITE sip:1001@... (from PJSIP/1000, digest-authenticated)
Executing [1001@default:1] NoOp(..., "LIGACAO DE 1000 PARA 1001 NO CANAL PJSIP/1000-...")
Executing [1001@default:10] AGI(..., "snep/snep.php")
Launched AGI Script /var/lib/asterisk/agi-bin/snep/snep.php
snep.php: 1000 -> 1001 INFO: Identified source: 1000 (Snep_Exten)
snep.php: 1000 -> 1001 INFO: Connection attempt from 1000 (PJSIP/1000-...) to 1001
snep.php: 1000 -> 1001 INFO: Rule Date is Valid
snep.php: 1000 -> 1001 INFO: Running the rule 1:Internas - Ramal para Ramal
snep.php: 1000 -> 1001 INFO: Definindo centro de custos para 9.
snep.php: 1000 -> 1001 INFO: Discando para ramal 1001 no canal PJSIP/1001.
AGI Script Executing Application: (Dial) Options: (PJSIP/1001,60,twk)
Called PJSIP/1001
PJSIP/1001-... is ringing
```

followed by baresip's own ctrl_tcp event stream on the 1000 side:
`CALL_LOCAL_SDP` -> `CALL_RINGING` -> `CALL_ANSWERED` -> `CALL_REMOTE_SDP`
-> `CALL_ESTABLISHED` -> `CALL_RTPESTAB` -> periodic `CALL_RTCP` (real RTP
flowing, zero packet loss observed). This is the existing SENMA AGI and
rule engine actually running -- not a test-only `Dial(PJSIP/1001)`
bypass; §5 confirms no bypass was needed.

## 9. CDR evidence

A second real bug, found and fixed via the actual CDR row this call wrote:

```
calldate             src   dst   disposition duration billsec uniqueid        channel
0000-00-00 00:00:00  1000  1001  ANSWERED    132      131     1787678290.2    PJSIP/1000-...
```

Every field was correct **except** `calldate` -- a zero-date. Root cause:
`cdr_adaptive_odbc` auto-discovers DB columns by name and, for dates, only
recognizes the standard CDR field names `start`/`answer`/`end`
(`cdr_adaptive_odbc.c`) -- the table's date column is `calldate` (the
`cdr_odbc`-era convention this schema predates), which is neither one of
those names nor a real CDR variable, so it was silently dropped from every
INSERT and MariaDB filled the `NOT NULL` column from its own
`DEFAULT '0000-00-00 00:00:00'`. TASK-0007 had assumed (untested, since no
channel existed then) that no column aliasing was needed -- that assumption
was wrong for this one column. Fixed with one line in
`docker/asterisk-config/cdr_adaptive_odbc.conf`:

```
alias start => calldate
```

After the fix, a real call produced a fully correct row:

```
calldate             src   dst   disposition duration billsec uniqueid        channel            dstchannel
2026-08-25 17:35:13  1000  1001  ANSWERED    12       12      1787679313.12   PJSIP/1000-...     PJSIP/1001-...
```

`src`/`dst`/`disposition`/`duration`/`billsec`/`uniqueid`/`calldate` all
verified correct; `channel`/`dstchannel` both `PJSIP/...`, confirming PJSIP
(not chan_sip) technology was actually used for the call that produced this
row. No row was ever inserted manually.

## 10. Report-readback evidence

Exercised the real, existing HTTP API endpoint
(`GET /modules/default/api/index.php?service=CallsReport&...`, HTTP Basic
Auth against the `users` table, the same code the `calls-report` web page's
JS calls), not a raw SQL query:

```
$ curl -u admin:*** ".../api/index.php?service=CallsReport&start_date=2026-08-25&...&src=1000"
{"status":"ok","data":[{"disposition":"ANSWERED","billsec":12,"src":"1000","dst":"1001",
  "uniqueid":"1787679313.12","calldate":"2026-08-25 17:35:13","dstchannel":"PJSIP/1001-...", ...}], ...}
```

The returned `uniqueid` matches the CDR row Asterisk itself wrote in §9.

**A third, real, pre-existing PHP 8.4 bug was found and fixed to reach this
endpoint at all** -- unrelated to the AGI/PJSIP path (a different
subsystem, the HTTP report layer, never previously exercised with real
data), so not covered by item 9's AGI-specific stop rule, but blocking this
exact validation step:

```
PHP Fatal error: Uncaught TypeError: count(): Argument #1 ($value) must be
of type Countable|array, Zend_Db_Statement_Pdo given in
CallsReportService.php:343
```

The same PHP 7-to-8 `count()`-on-non-Countable class of bug TASK-0002/0004
already fixed elsewhere in this codebase. `$cont = count($stmt)` counted
the PDO statement object itself; `$stmt->fetch()` was already being looped
into `$row` two lines later. Fixed by moving the count after that loop,
using `count($row)` (the actual fetched rows) instead -- a one-line,
behavior-preserving fix, not a redesign.

**Also found, not fixed (out of scope, pre-existing, unrelated to
PJSIP/AGI):** `CallsReportService.php`'s date-range WHERE clause
string-concatenates `$_GET['start_date']`/`end_date` directly into SQL with
zero reformatting, unlike the web UI's `CallsReportController`
(which pre-formats via `Snep_Reports::fmt_date()` to `yyyy-MM-dd` first).
Callers of the standalone API must already send ISO `YYYY-MM-DD` --
`DD/MM/YYYY` (a reasonable first guess, Brazilian locale) silently fails to
parse (`CAST('25/08/2026...' AS DATETIME)` returns `NULL` in MariaDB) and
produces wrong/empty result sets with no error. The smoke script uses the
correct ISO format; the underlying inconsistency between the two report
code paths (web controller vs. standalone API) is flagged here, not fixed.

## 11. `make call-smoke`

`scripts/call-smoke-test.sh` (new), wired via `make call-smoke` (depends on
`up`, mirrors `make smoke`'s structure), kept fully separate from
`scripts/smoke-test.sh`. Validates, strictly, in order: containers healthy
-> PJSIP modules Running -> fixtures available (create-or-stop) -> endpoint
1000 registered -> endpoint 1001 registered -> call placed -> destination
receives call -> destination answers -> call remains established -> hangup
succeeds -> AGI/rule path was exercised (log-trace assertion, scoped to
this call via a log-line-count marker) -> CDR row exists and is correct ->
SENMA reporting path can read it -> cleanup (fixtures + containers, via an
EXIT trap, safe even on early abort). Exit 1 on any FAIL.

Verified passing 13/13 from a **fully clean rebuild** (both the
`asterisk-etc` and `astvarlibdir` named volumes wiped, images rebuilt from
scratch) -- not just against a container already patched live during
development.

## 12. Regression

`make smoke`: 16 PASS / 0 FAIL / 0 EXPECTED_LIMITATION, re-verified after
the full clean rebuild, `before=0/after=0` new PHP Fatal Errors.

## Files changed

- `compose.yaml` -- `asterisk` service: added `./snep:/var/www/html/snep:ro`,
  `./snep/install/etc/asterisk:/snep-asterisk-dialplan-src:ro`; `app`
  service: `/etc/asterisk` mount `:ro` -> read-write.
- `.env.example`, `.env` -- `PJSIP_TEST_1000_SECRET`/`PJSIP_TEST_1001_SECRET`.
- `docker/asterisk.Dockerfile` -- `--with-pjproject-bundled`;
  `php8.4-cli`/`cgi`/`mysql`/`xml`; `senma-config` group (GID 3000);
  `/var/log/snep`; `libasteriskpj.so*`; `docker/php-agi.ini` copied into
  both cli/cgi `conf.d/`.
- `docker/app.Dockerfile` -- `senma-config` group (GID 3000), `www-data`
  added.
- `docker/php-agi.ini` (new) -- `register_argc_argv = On`.
- `docker/asterisk-config/asterisk.conf` -- `[directories](!)` ->
  `[directories]` (template-marker bug fix); `astagidir` comment updated
  (value unchanged, default).
- `docker/asterisk-config/modules.conf` -- removed the five PJSIP
  `noload` lines.
- `docker/asterisk-config/pjsip.conf` (new) -- test/bootstrap PJSIP config.
- `docker/asterisk-config/cdr_adaptive_odbc.conf` -- `alias start =>
  calldate`.
- `docker/asterisk-entrypoint.sh` -- deploys `extensions.conf`+`custom/`;
  creates the `agi-bin/snep` symlink every boot; sets up
  `/etc/asterisk/snep`'s group/setgid; templates PJSIP passwords.
- `docker/baresip-test.Dockerfile`, `docker/baresip-test/config.template`,
  `docker/baresip-test/accounts.template` (new) -- test endpoint tooling.
- `snep/lib/PBX/Asterisk/Interface/PJSIP.php` (new).
- `snep/lib/PBX/Usuarios.php` -- PJSIP tech-dispatch branch.
- `snep/modules/default/api/actions/CallsReportService.php` -- `count()`
  PHP 8.4 fix (§10).
- `scripts/call-smoke-test.sh` (new).
- `Makefile` -- `call-smoke` target.

## Remaining PJSIP provisioning debt (explicitly out of scope here)

- `Snep_InterfaceConf` still only generates chan_sip/IAX2 config
  (`snep-sip.conf`/`snep-iax2.conf`). Production PJSIP provisioning needs
  it extended to generate a static (or later, realtime) `pjsip.conf` from
  the `peers` table, replacing today's hand-written test-only file.
  Requires the now-valid writable-`/etc/asterisk/snep` filesystem
  architecture from §2, but was not itself invoked or changed.
- `ExtensionsController`/the extensions UI has no PJSIP option yet --
  today's fixtures are created by direct SQL, not through the app.
- No trunks, inbound routes, queues, voicemail, or IVR were touched or
  proven with PJSIP -- only the plain internal-call path.
- The `CallsReportService.php` date-format inconsistency (§10) is
  unresolved.
