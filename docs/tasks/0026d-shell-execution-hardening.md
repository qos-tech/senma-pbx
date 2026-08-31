# TASK-0026D — Shell/command execution hardening (F2–F5)

## Status

Implementation complete and validated. Two consecutive full `make
regression` passes both PASS. Not committed.

## Scope

TASK-0026 (the pre-pilot security audit) recorded four shell/command-
injection findings in root-cause group A: F2 (Sound Files), F3 (Music on
Hold), F4 (System Logs), F5 (CNL Update). This task remediates exactly
those four, using the current tree and live application behavior as
authoritative rather than the audit's historical line numbers and
reachability guesses. It does not touch: F6–F11 (SQL injection, already
handled by TASK-0026C), PJSIP configuration injection (TASK-0026E),
authorization, session/CSRF, password hashing, or any unrelated command
execution outside these four controllers' own functional boundaries.

## 1. Finding inventory (re-verified against current code and live behavior)

| Finding | Entry point | User-controlled value | Command sink | Auth/permission | Current status |
|---|---|---|---|---|---|
| F2 | `SoundFilesController::addAction()`/`editAction()` | upload filename (`parseName()` only substitutes accents/space/@/!, no shell filtering) | `exec("sox ...")`, `exec("cp ...")` | requires `sound-files_write` (live-verified: zero-permission user gets 302→`/permission/error`) | **confirmed exploitable** |
| F3 | `MusicOnHoldController::addfileAction()`/`removefileAction()` | upload filename (same weak filter) + raw `arquivo`/`secao` POST fields | `exec("mv/sox ...")`, `exec("rm ...")` (2nd `rm` unconditional) | requires `music-on-hold_write` (live-verified) | **confirmed exploitable**; the audit's "reachable by ANY authenticated user" component is **already mitigated** — TASK-0026A's default-deny now gates these the same as any other write action (live-reconfirmed here) |
| F4 | `LogsController::viewAction()` → `Snep_Log::grepLog()` | `others`, `verbose`, and `hora_ini`/`hora_fim` (a sibling injection point this re-audit found, not named by the original audit) | `exec($cmd)` (awk/grep pipeline) | requires `logs_read` (live-verified) | **confirmed exploitable**, one sibling injection point added to scope |
| F5 | `CnlController::updateAction_76()` | upload filename (`Zend_File_Transfer_Adapter_Http::getFileName()`, unfiltered) | `` `which unzip` `` (literal backtick operator) + `exec("unzip ...")` | requires `cnl_read` (live-verified) | **incorrectly classified by the historical audit** — see below |

**F5 reclassification.** The audit concluded "not linked from the
current UI... not live-verified either way" based on a grep of
`Snep_Menu.php`/`resources.xml` finding no `cnl` reference. That is no
longer true of the current tree: `resources.xml` registers a `cnl`
resource with a label and icon (the exact same pattern as the
confirmed-reachable `sound-files`/`music-on-hold` resources), and live
testing confirms a real sidebar entry —
`<li id="default_configs_cnl"><a href="/index.php/default/cnl">Atualizar CNL</a></li>`,
next to Music on Hold and Module Settings — and a 200 OK render of the
upload form for an authenticated user. **Reclassified from P1-pending-
reachability to CONFIRMED exploitable**, matching F2–F4. (Whether this
resource registration predates or postdates the original F5 write-up was
not determined; only current reachability was in scope here, per this
task's own instruction to use current tracing as authoritative.)

**Sibling occurrences found in the same functional boundaries (fixed
alongside their named findings, not a broader sweep):**
- `Snep_SoundFiles_Manager::addClass()`/`removeClass()` — MOH *class*
  (category) management, `exec("mkdir ...")`/`exec("rm -rf ...")` on a
  `directory` value built in `MusicOnHoldController::addAction()` from
  raw, unvalidated `base`+`directory` POST fields. Same root cause as
  F3, via a different action pair (`music-on-hold/add`, `.../remove`)
  than the two the audit named.
- `SoundFilesController::removeAction()`/`restoreAction()` —
  `exec("rm -f ...")`/`exec("mv ...")` operating on filenames read back
  from the DB; not independently exploitable once F2's upload-time
  filename is constrained, but converted anyway since they need no
  external command at all.

**Confirmed out of scope (found via the primitive sweep below,
verified non-dynamic or unrelated to F2–F5), classified `DEFER`:**
`ConferenceRoomsController.php` (3 `exec()` calls, fully static
strings), `SystemstatusController.php` (`popen()`/`exec()` for system
info display), `Snep_Locale::setExtensionsLanguage()` (already gated by
TASK-0026B's finite-language allowlist before its `exec()`), the
vendored `linfo` library (system-info dashboard, fixed command names
throughout), and every `$asterisk->exec(...)` call in `AGI.php`/
`PBX/Rule.php`/action classes (Asterisk's own AGI-protocol `EXEC`
command — not a PHP shell primitive at all, a grep false-positive worth
noting explicitly since the name is easy to confuse with PHP's
`exec()`).

## 2. Security principle applied

"Untrusted application data must not become shell syntax" — not
"escape dangerous characters." Preferred order actually used:

1. **REMOVE_SHELL** where a native operation exists: `Snep_Log::grepLog()`
   (awk/grep → PHP line filtering), `CnlController` (`unzip` →
   `ZipArchive`), `Snep_SoundFiles_Manager::addClass()`/`removeClass()`
   (`mkdir`/`rm -rf` → `mkdir()`/a small recursive-delete helper),
   `SoundFilesController::removeAction()`/`restoreAction()`/`editAction()`'s
   backup (`rm`/`mv`/`cp` → `unlink()`/`rename()`/`copy()`),
   `MusicOnHoldController::addfileAction()`'s upload move (`mv` →
   `move_uploaded_file()`), `.../removefileAction()` (`rm` → `unlink()`).
2. **FIXED_COMMAND_ARGUMENTS** where sox is genuinely still required:
   every remaining `exec("sox ...")` call now wraps every dynamic
   argument in `escapeshellarg()`.
3. **FINITE_ALLOWLIST** / **PATH_VALIDATION** for every dynamic
   identifier: a strict filename-shape allowlist
   (`Snep_SoundFiles_Manager::isSafeFilename()`,
   `^[A-Za-z0-9_-]+\.[A-Za-z0-9]+$`) for every upload filename reaching
   a shell command or filesystem path; a bare-directory-name allowlist
   (`isSafeDirectoryName()`, `^[A-Za-z0-9_-]+$`) for MOH class
   directories; the server's own configured MOH root used unconditionally
   instead of ever trusting a client-supplied "base" path; a real,
   enumerated list of existing MOH class names for `secao` validation
   (not a hand-picked allowlist — the actual finite domain the
   application itself defines); a Zip Slip per-entry check (reject any
   zip entry whose own stored name contains `..` or starts with `/`)
   before ZipArchive ever extracts anything.

No remediation relies on blacklisting, regex removal of shell
metacharacters, `strip_tags`, or partial `addslashes`.

## 3. F2 — Sound Files boundary

**Current call path:** `SoundFilesController::addAction()`/`editAction()`
built `exec("sox " . $arq_tmp . " ...", $result)` /
`exec("cp " . $arq_dst . " " . $arq_bkp, $result)` from
`$originalName = Snep_SoundFiles_Manager::parseName($_FILES['inputFile']['name'])`
— `parseName()` only substitutes a curated set of accented
characters/space/@/!, leaving every shell metacharacter untouched.
`checkType()` only ever inspected the substring after the last `.`
(`pathinfo(..., PATHINFO_EXTENSION)`), so a name ending in `.wav`
passed regardless of what preceded it.

**Fix (`snep/modules/default/controllers/SoundFilesController.php`):**
`Snep_SoundFiles_Manager::isSafeFilename()` (new) is checked immediately
after `parseName()`/`checkType()` in both `addAction()` and
`editAction()`, rejecting with a clear form error before any exec()/path
construction if the whole name doesn't match `^[A-Za-z0-9_-]+\.[A-Za-z0-9]+$`.
Every remaining `exec("sox ...")` call wraps its dynamic path arguments
in `escapeshellarg()` (defense-in-depth on top of the allowlist).
`removeAction()`'s `exec("rm -f ...")` → `unlink()`; `restoreAction()`'s
`exec("mv ...")` → `rename()`; `editAction()`'s backup
`exec("cp ...")` → `copy()` — none of these three need an external
command at all.

**Classification:** confirmed exploitable, fixed (REMOVE_SHELL where
possible, FIXED_COMMAND_ARGUMENTS for the remaining `sox` calls).

## 4. F3 — Music on Hold boundary

**Current call path (file-level, the two the audit named):**
`addfileAction()` built `exec("mv $uploadName $arq_tmp")`/
`exec("sox $arq_tmp ...")` from an upload filename filtered by the same
weak, curated substitution as F2 (independently duplicated inline, not
even calling the shared `parseName()`). `removefileAction()` built
`exec("rm {$file_remove}")` from raw `arquivo`/`secao` POST fields with
zero validation — the second `exec("rm {$file_remove} ")` ran
*unconditionally*, with no `file_exists()` gate at all, exactly as the
audit described.

**Current call path (class-level, a sibling this re-audit found):**
`MusicOnHoldController::addAction()` (create a MOH class/category) built
`$dados['directory'] = $dados['base'] . '/' . $dados['directory']` from
two entirely untrusted POST fields, then passed it to
`Snep_SoundFiles_Manager::addClass()`, which ran
`exec("mkdir {$class['directory']}")` three times. `editAction()` had
the same shape for its `folder`/`base` fields (feeding `editClass()`,
which does not itself shell out but stores the value for
`removeClass()`/`addfileAction()` to read back later).

**Fix (`snep/modules/default/controllers/MusicOnHoldController.php`,
`snep/lib/Snep/SoundFiles/Manager.php`):**
- `addAction()`/`editAction()`: the client's `base` field is discarded
  entirely — the server's own `Zend_Registry::get('config')->system->path->asterisk->moh`
  is used unconditionally instead (matching the view's own intent: that
  field is rendered `disabled`, a fixed display value, never meant to be
  attacker-settable). `directory`/`folder` are validated against
  `isSafeDirectoryName()` before being used at all.
- `Snep_SoundFiles_Manager::addClass()`: `exec("mkdir ...")` × 3 →
  `mkdir()` × 3.
- `Snep_SoundFiles_Manager::removeClass()`: `exec("rm -rf ...")` → a new
  `removeDirectoryRecursive()` helper (`RecursiveDirectoryIterator` +
  `RecursiveIteratorIterator::CHILD_FIRST`, deleting files then
  directories bottom-up) — recursive delete has no single native PHP
  function, so this is a small local helper rather than a shell-out,
  per this task's REMOVE_SHELL preference over merely escaping.
- `addfileAction()`: rejects up front if `section` doesn't resolve to a
  real MOH class (previously, an unrecognized section silently
  collapsed the target directory to `/tmp`); the same
  `isSafeFilename()` allowlist as F2 gates the upload filename;
  `exec("mv ...")` → `move_uploaded_file()` (matching
  `SoundFilesController::addAction()`'s own existing safe pattern for
  the identical operation); the remaining `exec("sox ...")` calls wrap
  their dynamic arguments in `escapeshellarg()`.
- `removefileAction()`: `secao` is validated against the real, current
  list of configured MOH class names (`'default'` plus
  `Snep_SoundFiles_Manager::getClasses()`'s own names) — a true
  FINITE_ALLOWLIST, not an invented one; `arquivo` is validated against
  `isSafeFilename()`, which also rules out `/`/`..` and therefore
  traversal, not just shell metacharacters. Both `exec("rm ...")` calls
  → a single, correctly-gated `unlink()` — the audit-flagged
  unconditional second `exec()` cannot be preserved once converted to a
  single native call, since there is nothing left to be unconditional
  about.

**Classification:** confirmed exploitable, fixed on both the file-level
(explicitly audited) and class-level (sibling, found during re-tracing)
paths. The "reachable by any authenticated user" component of the
original finding no longer holds — live-reconfirmed that
`music-on-hold/addfile` and `.../removefile` now redirect a
zero-permission user to `/permission/error`, identically to every other
write action, courtesy of TASK-0026A's prior, independent work.

## 5. F4 — System Logs boundary

**Current call path:** `LogsController::viewAction()` passed
`others`/`verbose` (named by the audit) and, this re-audit found,
`hora_ini`/`hora_fim` (an unnamed sibling — the raw time-of-day token
produced by splitting the date-range form field on a space, with zero
further processing) straight into `Snep_Log::grepLog()`, which built
`awk '...' | grep $others | grep "VERBOSE[$verbose]" $arquivo > $out`
and ran it via `exec($cmd)`. `others` was spliced in with **no quoting
at all**, so a value could inject arbitrary `grep` flags in addition to
arbitrary shell syntax.

**A real pre-existing command-construction bug was found and had to be
understood before it could be faithfully replaced:** direct
reproduction of the exact shell pipeline showed that whenever `verbose`
is set, only the `VERBOSE[...]` filter ever actually applies (against
the *raw* file — date range and `others` are silently discarded); else
if `others` is set, only that filter applies (date range discarded);
the date/time range only ever took effect when *both* were empty. This
happens because the log filename, appended at the very end of the whole
piped command string, always binds to the *last* stage of the pipe,
which then reads the file directly instead of its piped stdin.

**Fix (`snep/lib/Snep/Log.php`):** the entire awk/grep/`exec()`
pipeline is replaced with plain PHP line-by-line filtering — no shell
involved at all. The replacement **intentionally reproduces the exact
observable three-way precedence above**, rather than the "obviously
more correct" combined filter, per this project's "preserve behavior
before modernizing" rule: `verbose` (if set) wins outright as a literal
substring match against `"VERBOSE[$verbose]"`; else `others` (if set)
wins outright as a literal substring match; else the date/time range
applies via a plain string comparison against each line's own leading
timestamp. `others`/`verbose` can no longer inject grep flags or shell
syntax — they are now always literal data, matched with `strpos()`.

**Classification:** confirmed exploitable (three dynamic fields, not
two), fixed via REMOVE_SHELL.

## 6. F5 — CNL Update boundary

**Current call path:**
`CnlController::updateAction_76()` ran a literal backtick shell-exec
operator, `` `which unzip` ``, then
`exec("unzip {$_fileName} -d /tmp")`, where `$_fileName =
$adapter->getFileName()` preserves the client-supplied upload filename
verbatim (`Zend_File_Transfer_Adapter_Http` does not sanitize it).

**Fix (`snep/modules/default/controllers/CnlController.php`):** PHP's
own `ZipArchive` extension (confirmed present in this environment)
extracts the zip natively — no shell, no `exec()`, no backtick operator
at all. Only the `basename()` of the uploaded path is trusted, then
reconstructed against the known-fixed upload destination (`/tmp/`)
rather than trusting whatever the adapter reports, and required to end
in `.zip` (the only shape this feature has ever accepted) — both keep
the resolved target inside `/tmp` independent of `ZipArchive`'s own
handling. A Zip Slip defense-in-depth check rejects the whole archive
if any entry's own stored name contains `..` or starts with `/`, before
anything is extracted — a related risk this re-audit identified while
implementing the fix (a malicious zip could otherwise place files
outside `/tmp` via its own internal entry names, independent of the
upload filename).

**Classification:** confirmed exploitable (see reclassification above),
fixed via REMOVE_SHELL.

## 7. Files changed

```
snep/lib/Snep/Log.php                                          F4
snep/lib/Snep/SoundFiles/Manager.php                            F2/F3 (new allowlist helpers, mkdir/rm -rf -> native)
snep/modules/default/controllers/SoundFilesController.php      F2
snep/modules/default/controllers/MusicOnHoldController.php     F3
snep/modules/default/controllers/CnlController.php              F5
scripts/shell-security-smoke-test.sh                            new -- Phase 6 focused harness
Makefile                                                        + shell-security-smoke target
scripts/regression.sh                                           + shell-security suite, after sql-security
```

No other application file was modified. No TASK-0026A/B/C file was
touched.

## 8. Focused security smoke — `scripts/shell-security-smoke-test.sh`

Built on `scripts/lib/harness.sh` (TASK-0027 conventions): PASS/FAIL/
BLOCKED/INCONCLUSIVE, signal-safe idempotent cleanup, fixture ownership.
Registered as `make shell-security-smoke` and as the `shell-security`
stage in `make regression`, immediately after `sql-security` and before
`authorization-coverage`.

Preflight: confirms a zero-permission user is denied on all five F2–F5
boundaries (`sound-files/add`, `music-on-hold/addfile`,
`.../removefile`, `logs/view`, `cnl`), then grants exactly the four
real, minimum permissions a non-superuser pilot role would need
(`default_sound-files_write`, `default_music-on-hold_write`,
`default_logs_read`, `default_cnl_read`) to a dedicated
`task0026d-restricted` fixture user (the same persistent-fixture,
reset-to-baseline-every-run pattern TASK-0026A/C already established),
and exercises every F2–F5 body through that account — proving
"authorized user can perform the normal action" and "authorized
malicious-looking input still cannot alter command syntax" through a
genuinely limited account, not a superuser bypass.

The negative proof matches this task's own required shape: a uniquely
named marker path (`/tmp/task0026d-marker-<pid>-<random>`) is targeted
by every shell-shaped payload (backtick command substitution embedded
in an upload filename, a `secao`/`arquivo`/date-field value, etc.); the
suite asserts the marker never exists, inside the `app` container where
`exec()`/shell operations actually run, after every single check, plus
one final aggregate check at the end. No destructive payload, no secret
read, no exfiltration, no network callback — matching this task's
explicit constraints.

Per finding: a normal legitimate operation through the real UI; a
harmless shell-shaped value; proof it is rejected outright by the new
allowlist (F2/F3) or, where nothing is ever rejected and only never
executed (F4/F5), that the app responds normally with the value treated
as inert data; proof no marker was created; proof the app stayed
healthy; cleanup via the same LIFO, dependency-safe ordering
established in TASK-0027/0026C. **Result: PASS, 28/28**, reproduced
across multiple independent runs.

Building this harness surfaced three genuine, pre-existing environment/
product gaps unrelated to shell injection — see
[Deferred](#9-deferred--not-in-scope-here) below; the harness works
around each as documented test-precondition scaffolding, never as a
product change.

## 9. Deferred — not in scope here

- **`/var/lib/asterisk` does not exist in the `app` container at all.**
  `path.asterisk.sounds`/`path.asterisk.moh` (`includes/setup.conf`)
  point under it; nothing mounts or provisions it there (it is a named
  volume, `mag-asterisk-var`, mounted only in the `asterisk`/`provider`
  containers per `compose.yaml`). Sound Files/Music on Hold's upload
  flows have therefore never been able to write anywhere in this dev
  environment, for a reason completely unrelated to this task, first
  surfaced because nothing had previously exercised these HTTP flows
  end-to-end. The focused suite provisions the missing directory tree
  (with `www-data` ownership — also confirmed missing) as harness
  scaffolding; not fixed in the product. A real fix belongs in the
  Docker-bootstrap phase (a shared volume or bind mount), not here.
- **`sounds.secao` is `varchar(30) NOT NULL` with no default and is
  part of the table's own `PRIMARY KEY`**, but
  `Snep_SoundFiles_Manager::add()`'s INSERT for AST-type (non-MOH)
  files never sets it, so every legitimate F2 upload's final DB insert
  throws `SQLSTATE[HY000]: 1364` (a strict-SQL/schema mismatch, category
  D in this project's own PHP 8.4 migration taxonomy). Confirmed the
  file itself still converts and lands on disk correctly (the part this
  task's fix actually touches) before this unrelated insert fails. Not
  fixed here — a Phase 2 (PHP 8.4 compatibility) task's concern, not a
  shell-injection one.
- **`Zend_File_Transfer_Adapter_Http::receive()` fatals under PHP 8.4
  on every upload attempt**, valid or malicious:
  `Zend_Validate_File_Upload::isValid()` calls
  `count($this->_messages)` where that property is `null` instead of an
  array in this code path (`Uncaught TypeError: count(): Argument #1
  ($value) must be of type Countable|array, null given`, thrown inside
  `receive()` itself, before any of this task's code runs).
  `CnlController` is the only controller in this codebase using this
  adapter (Sound Files/Music on Hold read `$_FILES` directly), so this
  uniquely and completely blocks F5's real HTTP path regardless of this
  task's fix. First surfaced here because nothing in this project's
  history had previously exercised a real HTTP upload to this
  controller. The fix's own logic (basename validation, Zip Slip
  rejection, `ZipArchive` extraction) is instead verified directly
  (replicating exactly what the controller does once `receive()` would
  have succeeded) — see the smoke test's F5 section. Not fixed here — a
  Phase 2 (PHP 8.4 compatibility) task's concern.
- **`path.log` (`/var/log/snep/`) never contains a `full` file at all**
  in this dev environment — real Asterisk logs live under
  `/var/log/asterisk` on the `asterisk` container's own volume, never
  shared with or copied into the `app` container. `Snep_Log`'s
  constructor also cannot surface this as a real error to its caller:
  its own `file_exists()` check result is discarded, since PHP
  constructors always return the new instance regardless of what the
  constructor body itself returns (a second, separate, pre-existing
  bug). The focused suite provisions a small, harness-owned log fixture
  with real content as test-precondition scaffolding; not fixed in the
  product.
- **`MusicOnHoldController::removefileAction()` builds its target path
  from `secao` — the MOH class's own *name* — not its independently-
  settable *directory*.** `addAction()` allows a class to be created
  with any name/directory combination; when they differ,
  `removefileAction()`'s `file_exists()` check on the wrong path is
  simply false, so its delete is silently skipped while the DB row is
  still removed and the request still redirects as success, orphaning
  the real file. Pre-existing in the code this task touched (this
  task's own fix changed *how* the file is removed — `unlink()` instead
  of `exec("rm ...")` — not *which* path is computed), never previously
  exercised with a name-differs-from-directory MOH class. The focused
  suite avoids triggering it (using the same value for both) rather
  than masking it; documented here, not fixed.
- **`SoundFilesController::editAction()`'s upload branch has an
  inverted condition** (`if (move_uploaded_file(...))` shows "Unable to
  upload file" on *success*, and does not explicitly stop before
  falling through to the backup/convert logic regardless). Pre-existing,
  unrelated to injection, not fixed.
- **Log content is echoed unescaped** in `logs/view.phtml`
  (`echo trim($buffer)`) — a potential stored-XSS surface via log
  content, unrelated to shell/command injection, not evaluated further
  or fixed here.
- **Raw SQL string interpolation in `Snep_SoundFiles_Manager::edit()`/
  `remove()`/`editClassFile()`** (e.g.
  `"arquivo = '{$file['arquivo']}' and language = '{$this->lang}'"`) —
  the same SQL-injection root cause TASK-0026C fixed for Extensions/
  Users/Profiles/Trunks/CSV/Export, but Sound Files was never in that
  task's F7–F11 scope. A new, separate, deferred SQL-injection finding;
  out of scope for this shell-injection task.

## 10. Post-remediation execution audit (Phase 9)

Repeating the same primitive sweep (`exec(`, `shell_exec(`, `system(`,
`passthru(`, `popen(`, `proc_open(`, backticks) across the five touched
files:

- `snep/lib/Snep/Log.php`: zero remaining occurrences (all comment
  references). **REMOVE_SHELL, fully done.**
- `snep/modules/default/controllers/CnlController.php`: zero remaining
  occurrences. **REMOVE_SHELL, fully done.**
- `snep/lib/Snep/SoundFiles/Manager.php`: zero remaining occurrences
  (the `mkdir`/`rm -rf` call sites are now `mkdir()`/
  `removeDirectoryRecursive()`). **REMOVE_SHELL, fully done.**
- `snep/modules/default/controllers/SoundFilesController.php`: 4
  remaining `exec("sox ...")` calls, every dynamic argument
  `escapeshellarg()`-wrapped, fed only by filenames already constrained
  by `isSafeFilename()`. **FIXED_COMMAND_ARGUMENTS, validated.**
- `snep/modules/default/controllers/MusicOnHoldController.php`: 2
  remaining `exec("sox ...")` calls, same treatment.
  **FIXED_COMMAND_ARGUMENTS, validated.**

No unexplained raw request-to-shell path remains in F2–F5 scope. Every
other shell/process-execution primitive found in the initial repository
sweep (`ConferenceRoomsController`, `SystemstatusController`,
`Snep_Locale`, the vendored `linfo` library, every `$asterisk->exec(...)`
AGI-protocol call) was individually inspected and classified `SAFE_STATIC`
or `DEFER` (see §1) — none were mechanically altered.

## Validation

- `php -l` on every touched file: clean.
- `make lint`: PASS (17 shell scripts, up from 16).
- `make shell-security-smoke`: PASS, 28/28, reproduced across multiple
  independent runs with clean fixture teardown each time.
- `make regression`, first run: 14/15 suites PASS; `transport-smoke`
  FAILed on its own restart-recovery timing check
  ("renamed transport active, old name absent"), unrelated to shell/
  command execution and matching the same class of transient inter-suite
  timing flake already documented in TASK-0027A. An immediate re-run
  with no code changes produced a clean 15/15 PASS; that re-run stands
  as this task's first official run. `shell-security` itself passed
  cleanly (28/28) in both the failing and passing aggregate runs,
  confirming the transport-smoke failure was unrelated.
- `make regression`, second consecutive run (since a flaky condition
  was observed, even though unrelated to this task's own changes): 
  **15/15 PASS**, byte-for-byte the same result.
- Cleanup/health: `app`/`asterisk`/`db`/`provider` all `Up`/`healthy`;
  `res_pjsip.so` loaded and `Running`; AMI responsive; the 3 baseline
  PJSIP transports (`tcp`, `udp`, `wss`) intact; ODBC DSN `snep`
  connected; 0 active channels; the only PHP Fatal Error present is the
  one documented, pre-existing Zend upload-validator bug (§9), triggered
  by `shell-security-smoke-test.sh`'s own F5 HTTP call, not a new
  regression; no `task0026d`-named fixture/marker remains anywhere
  (database, `/var/lib/asterisk`, `/var/log/snep`, `/tmp`); no leftover
  smoke processes.
- `git diff --check`: clean.
- `git diff --stat` / `git status --short`: exactly the 7 modified files
  plus the new smoke script listed in [Files changed](#7-files-changed)
  — full diff reviewed line-by-line, every change is either a validation
  addition, a shell-to-native conversion, or `escapeshellarg()` defense-
  in-depth; no unrelated refactoring, no TASK-0026A/B/C file touched.
