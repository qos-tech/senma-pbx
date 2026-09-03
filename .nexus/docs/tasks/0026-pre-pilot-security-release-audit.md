# TASK-0026 — Pre-pilot security and release audit

## Status

**Investigation only.** No fixes applied. Every finding below was either
(a) proven by direct code tracing with exact file:line citations, or
(b) additionally verified live against the running `make dev` environment
using safe, non-destructive proofs (harmless marker-file creation, boolean-
oracle response diffing, a disposable admin-session-takeover test) — each
explicitly marked "LIVE-VERIFIED" below. No production system, no real
vendor, no real credentials were touched. Two live tests had transient side
effects on the local dev environment (a corrupted `setup.conf` language
value causing an application-wide outage, and a `SNEP_LANGUAGE` config-line
rewrite); both were fully identified and reverted before this document was
finalized, and confirmed via a clean full regression run (§9).

**Read first, confirmed read in full**: `CLAUDE.md`,
`docs/tasks/0024-external-api-failure-isolation.md`,
`docs/tasks/0025-vendor-content-xss-hardening.md`, current `git status`,
`Makefile`, `Snep_AuthPlugin`, `Snep_PermissionPlugin`, `AuthController`,
`Snep_Acl`, `Snep_Locale`, `UsersController`/`Snep_Users_Manager`,
`ProfilesController`, `ExtensionsController`, `TrunksController`,
`Snep_PjsipConf`/`Snep_PjsipTrunkConf`/`Snep_PjsipTransportConf`/
`Snep_InterfaceConf`, `SoundFilesController`, `MusicOnHoldController`,
`LogsController`, `ExportDataController`, `Snep_CsvIE`, `DocsController`,
`snep/modules/default/api/index.php`, `compose.yaml`,
`docker/app.Dockerfile`, `docker/php-mag.ini`, `ErrorController` +
`error/error.phtml`, `snep/index.php`, `snep/install/database/*.sql`, plus
every file cited in the findings below.

**Investigation method**: two tracks run in parallel — (1) four background
read-only code-tracing investigations, each scoped to specific audit
sections and instructed never to modify files or touch the running
environment, and (2) direct, live investigation and testing by the primary
investigator (this document's author) covering authentication,
authorization, session/cookie behavior, secrets, Docker/container
posture, error handling, default install state, and live proof-of-concept
verification of the two most severe findings.

---

## 1. Executive summary

This audit found **28 findings**, clustered into **11 root causes**.
**16 are CRITICAL and classified P0** — they block a pilot. The most
severe two were independently confirmed live, safely, against the running
dev environment:

- **An unauthenticated attacker can execute arbitrary shell commands** by
  requesting `/index.php/default/auth/login?indexChooseLanguage=<payload>`
  — no login, no cookie, no prior state required (§F1). Live-verified: a
  harmless marker file was created inside the app container by an
  anonymous HTTP request. The same bug additionally causes a **persistent,
  application-wide outage** for every subsequent user until an
  administrator manually repairs a config file, because the malicious
  value is written to disk before the vulnerable command executes.
- **An unauthenticated attacker can run arbitrary SQL queries** against
  the full database via the `user` field of the login form itself
  (§F6) — live-verified via a boolean-based blind-injection oracle
  (different login-page messages for a true vs. false injected
  condition), sufficient to read every table, including the
  unsalted-MD5 `users.password` column, without ever having valid
  credentials.

Beyond these two, the same two defect classes — **unescaped shell
command construction** and **raw SQL string interpolation instead of
this codebase's own already-correct `Zend_Db` parameterized API** —
recur across nearly every core MVP write surface: Extensions, Trunks,
Transports, Users, Profiles, Sound Files, Music on Hold, Logs, and Data
Export. A third class — **unescaped interpolation into generated
Asterisk PJSIP config files, auto-reloaded live onto the running PBX
within the same HTTP request** — affects every extension/trunk/transport
write. A fourth, architectural finding explains why several of these are
reachable by *any* authenticated user regardless of their assigned
permissions: `Snep_PermissionPlugin`'s authorization check only inspects
seven hardcoded action names; every other action on every controller
(including `removefile`, `export`, `view`) receives **zero** server-side
authorization check.

Additional confirmed issues: session fixation (no session ID
regeneration on login, live-verified via a full admin-session-takeover
proof), no CSRF protection anywhere in the application except the one
token TASK-0022 built for the Asterisk restart feature, unsalted MD5
password hashing, no login rate-limiting, a well-known default admin
credential (`admin`/`admin123`) shipped by the install SQL with no
forced change, unconditional internal-exception-message disclosure on
every server error, and session cookies missing `HttpOnly`/`Secure`/
`SameSite`.

**Positive findings**: Docker/Compose topology is well-designed (no
privileged containers, no exposed AMI/DB ports, pinned isolated network);
`setup.conf` and `.env` are correctly blocked from direct web access;
`display_errors` is correctly off with errors routed to logs; the
`debug=0` default correctly suppresses full stack-trace disclosure;
dependency versions (PHP 8.4.25, Asterisk 22.10.1, MariaDB 10.11.18,
Debian 13) are current, not EOL; TASK-0024/0025's vendor-failure-isolation
and content-escaping properties both still hold, reconfirmed by a clean
full regression run.

**Verdict: PILOT SECURITY STATUS: BLOCKED.** See §11 for the complete
decision block.

---

## 2. Root-cause groups

Per this task's own instruction to group multiple P0s by common root
cause rather than list them as unrelated items:

| # | Root cause | Findings | Pilot class |
|---|---|---|---|
| A | Unescaped shell command construction (`exec()` + string concatenation) | F1–F5 | P0 (F5 pending reachability) |
| B | Raw SQL string interpolation instead of this codebase's own `Zend_Db` parameterized API | F6–F11 | P0 (F10 pending reachability) |
| C | Unescaped interpolation into generated Asterisk PJSIP config, auto-reloaded live | F12–F15 | P0 (F15 conditional on chan_sip use) |
| D | `Snep_PermissionPlugin`'s 7-action-name allowlist — every other action on every controller has **zero** authorization check | F16 | P0 — amplifies A/B/C's blast radius |
| E | Standalone `api/index.php` — separate auth model, own defects | F17 | P0 |
| F | Session management gaps | F18–F19 | P1 |
| G | No CSRF protection anywhere except the restart feature | F20 | P1 |
| H | Weak authentication hardening | F21–F24 | P1/P2 |
| I | Information disclosure | F25–F26 | P1/P2 |
| J | Default installation state | F27 | P0 (deployment) / P1 (code gap) |
| K | Path traversal (contained) | F28 | P1 |

A single coordinated fix task can plausibly address A+B together (both
are "replace raw string interpolation with this codebase's own existing
safe primitives" — `escapeshellarg()`/allowlist for A, `Zend_Db`
parameterization for B), since they are mechanically similar and touch
overlapping controllers. D should be fixed **first and separately** —
it is the highest-leverage single change, and fixing A/B/C without also
fixing D leaves several of them exploitable by *any* logged-in user
regardless of how carefully the individual bugs are patched. C and E
are architecturally distinct enough to warrant their own follow-up
tasks. See §10 for the full recommended task order.

---

## 3. Findings — Root cause A: unescaped shell command construction

```
ID: TASK-0026-F1
Title: Unauthenticated remote command execution via the login-page language selector
Surface: AuthController::loginAction() (pre-authentication) -> Snep_Locale::setExtensionsLanguage()
Reproduction: GET /index.php/default/auth/login?indexChooseLanguage=<payload> -- no cookie, no session.
  AuthController.php:52-65 reaches this branch BEFORE the auth->hasIdentity() check.
  Snep_Locale.php:228-238 builds: 'sed "s,^SNEP_LANGUAGE *=.*,SNEP_LANGUAGE='.$value.',," < "..." > "..."; chown ...; chmod ...; mv ...'
  then exec($shell_cmd) with zero escaping.
Evidence: AuthController.php:52-65; Snep_Locale.php:228-238.
LIVE-VERIFIED (safely): a value containing a literal '"' is rejected earlier by
  Zend_Config_Writer_Ini::_prepareValue() (AuthController.php:54-59 writes the
  same raw value into setup.conf first) -- but shell $(...) command substitution
  is evaluated even inside double quotes and needs no '"' at all. Payload used:
  indexChooseLanguage=x$(touch /tmp/task0026_rce_proof)
  Result: HTTP 302; /tmp/task0026_rce_proof was created inside the app container,
  owned by www-data, via a fully anonymous request. Marker removed immediately after.
  SECOND, UNPLANNED CONFIRMATION: the raw payload also persisted into
  setup.conf's [system] language value (written just before the vulnerable
  exec() call). Snep_Locale::getInstance() validates that value against a
  known-locale list on every subsequent request (called during menu
  construction, Snep_Menu.php:249) -- an invalid value throws an UNCAUGHT
  fatal exception on every single page load for every user, application-wide,
  until an administrator manually edits the file. This was observed live
  (every request 500'd for ~4 minutes of testing) and repaired by resetting
  setup.conf's language line back to "pt_BR". This means the bug is not just
  RCE -- it is RCE plus a trivially-triggered, persistent, unauthenticated
  denial of service affecting every user until manual intervention.
Impact: Full RCE as the web server user (www-data) with zero authentication,
  zero preconditions, from the very first page an attacker touches. From
  there: read DB/AMI credentials from setup.conf, rewrite Asterisk config,
  pivot to the Asterisk/DB containers over the Docker network. Additionally,
  a trivial persistent DoS of the entire application.
Exploit preconditions: network access to the login page. Nothing else.
Severity: CRITICAL
Pilot classification: P0 - blocks pilot
Recommended minimal fix: validate $lang against a fixed allowlist (the
  three values the UI ever actually sends: en, pt_BR, es) before it reaches
  Snep_Locale::setExtensionsLanguage() and before it reaches the
  Zend_Config_Writer_Ini call, at BOTH call sites (AuthController.php:61
  and ParametersController.php's equivalent call). Reject anything else.
Regression risk: low -- the allowlist only needs to include values the UI
  itself already sends.
Suggested follow-up task: dedicated P0 task, root-cause group A.
```

```
ID: TASK-0026-F2
Title: Authenticated command injection via Sound Files upload filename (sox exec())
Surface: SoundFilesController::addAction()/editAction()
Reproduction: multipart upload with filename crafted as e.g. `` `touch /tmp/x`.wav ``
  or `x.wav;touch /tmp/x;.wav`.
  Snep_SoundFiles_Manager::parseName() (Manager.php:653-659) only replaces accented
  characters/space/@/! -- no shell-metacharacter stripping.
  checkType() (Manager.php:640-646) only validates the substring after the LAST "."
  via pathinfo(..., PATHINFO_EXTENSION) -- a crafted name ending in ".wav" passes
  regardless of what precedes it.
  SoundFilesController.php:145,149 (add) and :238,241,244 (edit, including a "cp"
  backup exec): exec("sox " . $arq_tmp . " ...", $result) -- raw concatenation,
  zero escapeshellarg()/escapeshellcmd() anywhere in the file.
Evidence: SoundFilesController.php:103-104,145,149,238-244; Manager.php:640-659.
Impact: RCE as www-data via a crafted upload filename, with any account holding
  the "sound-files" write permission (a plausible non-superuser pilot role, e.g.
  IVR/prompt management staff).
Exploit preconditions: authenticated session with sound-files write permission.
Severity: CRITICAL
Pilot classification: P0 - blocks pilot
Recommended minimal fix: escapeshellarg() on every exec() path argument; derive
  the on-disk filename server-side (e.g. DB id + validated extension) rather than
  trusting any part of the client-supplied filename; validate the ENTIRE filename
  against an allowlist regex (e.g. ^[A-Za-z0-9_-]+\.(wav|gsm)$), not just the
  pathinfo() extension substring.
Regression risk: low -- sox invocation semantics unchanged; existing valid
  uploads unaffected.
Suggested follow-up task: dedicated P0 task, root-cause group A (bundle with F3).
```

```
ID: TASK-0026-F3
Title: Authenticated command injection via Music-on-Hold file deletion, reachable by ANY logged-in user (no permission check at all)
Surface: MusicOnHoldController::removefileAction()/addfileAction()
Reproduction: POST /default/music-on-hold/removefile with arquivo=`x; touch /tmp/x #`.
  MusicOnHoldController.php:406-417: $file_remove = $base_dir . '/' . $dados['arquivo'];
  (raw POST value, zero sanitization) ... if (file_exists($file_remove)) { exec("rm {$file_remove}"); }
  exec("rm {$file_remove} ");  -- note the SECOND exec() runs UNCONDITIONALLY,
  with no file_exists() gate at all.
  addfileAction() (lines 305-331) has the identical upload-filename injection
  pattern as F2, plus a client-supplied (trivially spoofed) Content-Type check
  that validates nothing about the filename.
  Root cause for "ANY logged-in user": action name "removefile"/"addfile" is
  not in Snep_PermissionPlugin's checked set {index,add,remove,edit,duplicate,
  multiremove,multiadd} -- see F16. The "music-on-hold" resource permission
  registered in resources.xml is never actually consulted for this action.
Evidence: MusicOnHoldController.php:305-331,390-417; PermissionPlugin.php:61-62.
Impact: RCE as www-data, reachable by ANY authenticated account -- including a
  brand-new user with zero granted permissions. The single most severe
  authenticated finding in this audit (lowest possible privilege bar).
Exploit preconditions: any valid SENMA login.
Severity: CRITICAL
Pilot classification: P0 - blocks pilot
Recommended minimal fix: (a) same escapeshellarg()/allowlist fix as F2; (b) look
  up the file by its DB record id, never trust a raw filename/path fragment from
  the request, matching the pattern this project's own smoke scripts already use
  for delete-by-id flows; (c) close the F16 authorization gap (required
  independently of (a)/(b), since other non-CRUD actions have the same exposure).
Regression risk: low.
Suggested follow-up task: dedicated P0 task, root-cause group A (bundle with F2).
```

```
ID: TASK-0026-F4
Title: Authenticated command injection via System Logs viewer (grep/awk filter fields)
Surface: LogsController::viewAction() -> Snep_Log::grepLog()
Reproduction: submit the Logs page's "others"/"verbose" filter fields with shell
  metacharacters.
  Snep_Log.php:62-84: $cmd = "awk '...' "; if ($others != '') { $cmd .= " | grep " . $others; }
  (no quoting); if ($verbose != '') { $cmd .= " | grep \"VERBOSE[" . $verbose . "]\""; }
  (no quoting); $cmd .= " " . $this->arquivo . " > " . $file_output; exec($cmd);
Evidence: LogsController.php:79-105; Snep_Log.php:62-84.
Impact: RCE as www-data via the Logs page's own filter fields. Per F16, "view" is
  not in the checked action-name set -- likely reachable by any authenticated user
  regardless of whether they hold an explicit "Logs" permission (not independently
  live-verified for this specific controller, but the mechanism is identical to
  the confirmed F3 case).
Exploit preconditions: any authenticated session that can reach the Logs page.
Severity: CRITICAL
Pilot classification: P0 - blocks pilot
Recommended minimal fix: escapeshellarg() around $others/$verbose at minimum;
  better, replace the awk/grep shell-out with PHP-native line filtering (this
  codebase already reads log files line-by-line elsewhere).
Regression risk: low-medium -- verify the free-text filter UX still supports
  simple substring matches after escaping; if multi-token grep flags are a
  real current feature, that needs explicit redesign, not just quoting.
Suggested follow-up task: dedicated P0 task, root-cause group A.
```

```
ID: TASK-0026-F5
Title: Possible command injection via legacy CNL (Brazilian numbering plan) import -- reachability unconfirmed
Surface: CnlController (method name updateAction_76, non-standard)
Reproduction: exec("unzip {$_fileName} -d /tmp") on a client-supplied upload filename
  (Zend_File_Transfer_Adapter_Http preserves the client name).
Evidence: CnlController.php:65-88.
Impact: same RCE class as F2-F4, IF reachable. grep across Snep_Menu.php and
  resources.xml found zero references to "cnl" -- this controller is not linked
  from the current UI, and the unusual updateAction_76 method name does not match
  Zend's standard dispatch convention (controller/action -> actionAction()),
  suggesting dead/legacy/versioned code rather than a route a pilot user reaches
  through normal navigation. Not live-verified either way.
Exploit preconditions: unconfirmed reachability.
Severity: HIGH (downgraded from CRITICAL pending reachability)
Pilot classification: P1 - confirm reachability first; reclassify P0 if confirmed
  live, N/A + candidate for removal if confirmed dead.
Recommended minimal fix: reachability check (cheap); escapeshellarg() if kept.
Regression risk: low.
Suggested follow-up task: quick reachability check, then fold into group A's task
  if live.
```

---

## 4. Findings — Root cause B: raw SQL string interpolation

```
ID: TASK-0026-F6
Title: Unauthenticated SQL injection in the login form itself
Surface: Snep_Acl::getCaseSensitive($username), called from AuthController::loginAction()
  on EVERY login POST, before any credential is checked.
Reproduction: Snep_Acl.php:75-87: $select = $db->select()->from('users')
  ->where("name = BINARY '$username'"); -- raw concatenation. $username comes from
  $_POST['user'] filtered only by Zend_Filter_StripTags (strips HTML tags, not
  SQL metacharacters).
Evidence: Snep_Acl.php:79-81; AuthController.php:78,81.
LIVE-VERIFIED (safe, read-only, no data modified): three POSTs to /index.php/auth/login:
  user=nonexistent_xyz                    -> "Please enter a username"
  user=nonexistent_xyz' AND '1'='2        -> "Please enter a username" (identical)
  user=nonexistent_xyz' OR '1'='1         -> "User or password invalid" (DIFFERENT)
  The injected always-true condition changes which code branch executes -- a
  textbook boolean-based blind SQLi oracle, unauthenticated, in the single most
  exposed endpoint in the application. Sufficient to extend (UNION/subquery/
  SLEEP()-based blind techniques, not attempted here) to read any table in the
  database, including every user's MD5 password hash.
Impact: Full unauthenticated database read access. Combined with F21's unsalted
  MD5 hashing, a realistic two-stage path to full authentication bypass (leak
  hashes via this SQLi, crack offline, log in with real credentials).
Exploit preconditions: none -- network access to the login form.
Severity: CRITICAL
Pilot classification: P0 - blocks pilot
Recommended minimal fix: $db->select()->from('users')->where('name = ?', $username)
  (Zend_Db parameterized where(), or quoteInto()) -- the exact safe pattern this
  codebase already uses correctly elsewhere (e.g. Snep_Users_Manager::get()).
Regression risk: low -- mechanical swap, same query semantics.
Suggested follow-up task: dedicated P0 task, root-cause group B -- fix this file
  FIRST given it requires no authentication at all.
```

```
ID: TASK-0026-F7
Title: Direct SQL injection in Extensions add/edit/remove/multiremove
Surface: ExtensionsController::execAdd()/removeAction()/multiremoveAction()
Reproduction: execAdd(): $sqlValidName = "SELECT * from peers where name = '$exten'";
  (UNION-injectable via the exten form field). The subsequent INSERT/UPDATE
  interpolates $exten/$extenPass/$extenName/$secret/etc. -- essentially the
  entire extension form -- with zero $db->quote()/parameterization anywhere.
  removeAction()/multiremoveAction(): $sql = "SELECT * from peers where name = '$exten'";
  where $exten = $_POST['id'] (or a loop over posted extension keys), same raw pattern.
Evidence: ExtensionsController.php:237,568-569,751-789,867-868,1057-1058.
Impact: any user with extensions-write permission (a core, frequently-granted
  pilot role) can read arbitrary database contents via UNION injection (admin
  password hashes, all peers' SIP secrets, vendor API keys in core_config) and/or
  corrupt the peers table via crafted INSERT/UPDATE values.
Exploit preconditions: authenticated session with extensions-write permission.
Severity: CRITICAL
Pilot classification: P0 - blocks pilot
Recommended minimal fix: rewrite using Zend_Db_Adapter's parameterized
  insert()/update()/select()->where('name = ?', $exten), matching this codebase's
  own safe pattern elsewhere.
Regression risk: medium -- central to provisioning; needs full lifecycle
  validation (TASK-0023's own established 20-step precedent) before/after.
Suggested follow-up task: dedicated P0 task, root-cause group B (bundle with
  F8/F9, same fix pattern).
```

```
ID: TASK-0026-F8
Title: SQL injection in Users/Profiles -> mass privilege escalation / account takeover
Surface: Snep_Users_Manager::edit()/addProfileByName()/removePermission(), called
  from UsersController::editAction()/ProfilesController::addAction()
Reproduction (most severe path): ProfilesController::addAction() loops
  duallistbox_profile[] (a raw POST array) into Snep_Users_Manager::addProfileByName():
  $where = "`users`.`name` = '{$cond}'"; $db->update("users", array("profile_id"=>...), $where);
  Submitting duallistbox_profile[]=' OR '1'='1 while creating/editing a profile
  reassigns EVERY user's profile_id to the attacker's chosen profile in one request.
  Second path: UsersController::editAction() -> Snep_Users_Manager::edit():
  $db->update("users", $update_data, "id = '{$user['id']}'"); ($user['id'] is the
  raw request id param) -- a crafted id applies the attacker's edits to every row.
  Third path: Snep_Users_Manager::removePermission($id):
  $db->delete('users_permissions', "user_id = '$id'"); -- an unvalidated bulk
  delete wiping every user's individual permission grants.
Evidence: Snep_Users_Manager.php:108-115,174-191,193-215,217-233;
  ProfilesController.php:108-119; UsersController.php:129,162,175,178.
Impact: an authenticated user with ONLY "manage profiles" or "manage users"
  permission (not superuser) can, in one crafted request, reassign every user's
  effective permission profile to one they control -- full privilege escalation
  -- or wipe every user's permissions (authorization-system DoS).
Exploit preconditions: authenticated session with profiles-write OR users-write
  permission. No superuser access needed.
Severity: CRITICAL
Pilot classification: P0 - blocks pilot
Recommended minimal fix: replace every raw "column = '{$var}'" WHERE string with
  $db->quoteInto('id = ?', $id) or equivalent, matching Snep_Users_Manager::get()'s
  own already-safe pattern. Additionally validate duallistbox_profile[] entries
  against real existing usernames server-side (defense in depth).
Regression risk: low-medium -- same mechanical fix, reuse TASK-0023's Users/
  Profiles lifecycle validation precedent for regression testing.
Suggested follow-up task: dedicated P0 task, root-cause group B (bundle with
  F7/F9).
```

```
ID: TASK-0026-F9
Title: Second-order SQL injection in Trunk edit view via unescaped peers.name, reachable through a mass-assignable "name" field
Surface: TrunksController::preparePost() (mass assignment) + editAction() (raw read-back query)
Reproduction: preparePost() merges the ENTIRE $_POST body into $trunk_data before
  filtering; the subsequent allowlist keeps 'name' (present in both $trunk_fields
  and $ip_fields), so an attacker can override the auto-generated trunk name with
  an arbitrary string via a raw POST field the legitimate UI never exposes. The
  write itself ($db->insert(...)) is safely parameterized -- but every SUBSEQUENT
  view of that trunk's edit page runs:
  TrunksController.php:373: $db->query("select * from peers where name='{$trunk['name']}'")->fetch();
  -- raw interpolation of the now attacker-controlled stored name, triggered by a
  plain GET to the edit page (no POST needed once the malicious name is stored).
Evidence: TrunksController.php:373,623-629,648-649,793-812.
Impact: a trunk-write user can plant a malicious name, then trigger UNION-based
  injection simply by (re-)viewing that trunk's own edit page -- potential
  disclosure of other tables (e.g. users.password) that this codebase's own
  coarse, all-or-nothing permission model (TASK-0022's finding) would not
  otherwise expose to a trunk-only-privileged role.
Exploit preconditions: authenticated session with trunk-write permission, plus a
  follow-up page view (self-triggerable).
Severity: HIGH
Pilot classification: P0 - blocks pilot (same root-cause class, same impact
  ceiling as F7, even though the trigger requires one extra step).
Recommended minimal fix: $db->select()->from('peers')->where('name = ?', $trunk['name']);
  separately reconsider whether 'name' should be attacker-settable at all (it is
  meant to be an auto-generated identifier).
Regression risk: low.
Suggested follow-up task: dedicated P0 task, root-cause group B (bundle with F7/F8).
```

```
ID: TASK-0026-F10
Title: SQL injection in CSV import (Snep_CsvIE) -- live reachability not fully confirmed
Surface: Snep_CsvIE::import(), invoked via ExportDataController's import flow / getForm()
Reproduction: a CSV cell containing a single quote, e.g. `x','(SELECT password FROM users LIMIT 1),'y`.
  CsvIE.php:262-264: only un-escapes a specific backslash-quote sequence; does not
  reject/escape single quotes. Line 264: $buffer[] = "('" . implode("','", $data) . "')";
  -- raw concatenation, no $db->quote(). Line 252-253:
  $query = "INSERT IGNORE INTO $table(...) VALUES " . implode(",", $buffer); executed directly.
Evidence: CsvIE.php:240-271.
Impact: SQL injection into whichever table the import path targets -- severity
  depends on exact live wiring (not fully confirmed by the read-only investigation).
Exploit preconditions: access to whatever pilot feature triggers Snep_CsvIE::import()
  with attacker-suppliable CSV content -- exact entry point/permission gate needs
  live confirmation beyond ExportDataController's export direction (a different,
  independently-confirmed path -- see F11).
Severity: HIGH (would be CRITICAL if confirmed reachable at low privilege)
Pilot classification: P1 pending live reachability confirmation (treat as P0 if
  confirmed low-privilege-reachable before pilot sign-off)
Recommended minimal fix: use Zend_Db's quoteInto()/parameterized insert() instead
  of manual string concatenation.
Regression risk: low.
Suggested follow-up task: live-confirm the import entry point, then fold into
  group B's task.
```

```
ID: TASK-0026-F11
Title: SQL injection via unvalidated table/column/ORDER BY identifiers in Data Export, reachable by ANY authenticated user
Surface: ExportDataController::exportAction()
Reproduction: action name "export" is not in Snep_PermissionPlugin's checked set
  (see F16) -- the "export-data" resources.xml permission is never actually
  consulted for direct requests to this action. POST directly to
  /default/export-data/export (bypassing indexAction, which is the only action
  that IS permission-gated) with group=<attacker string>,
  coluns[<attacker string>]=<...>, orderby[<attacker string>]=<attacker string>.
  ExportDataController.php:99-101 stores these into $_SESSION['exportData']
  without validating $formData['group'] against the fixed $tables allowlist that
  indexAction() defines (that array only populates HTML <select> options -- never
  re-validated server-side on submit). A follow-up request with download=1 runs:
  ExportDataController.php:79: $select = "SELECT " . $_SESSION['exportData']['coluns']
  . " FROM " . $table . " ORDER BY " . $_SESSION['exportData']['order'];
  -- table name, column list, and ORDER BY clause are raw string concatenation in
  STRUCTURAL (identifier) SQL positions, not value positions -- quoteInto() would
  not even apply here.
Evidence: ExportDataController.php:73-101; PermissionPlugin.php:61-62 (root cause).
Impact: any authenticated user (regardless of permissions) can read the contents
  of ANY table in the database -- not just the 5 intended ones -- and manipulate
  the query structure via the column-list/ORDER BY injection points, delivered
  back as a downloadable CSV.
Exploit preconditions: any valid SENMA login.
Severity: CRITICAL
Pilot classification: P0 - blocks pilot
Recommended minimal fix: (a) server-side allowlist-validate $formData['group']
  against indexAction()'s own fixed $tables array before storing it in session;
  (b) allowlist-validate every column name against $db->describeTable($table)'s
  actual columns rather than trusting client-supplied keys; (c) same for orderby;
  (d) fix F16 so this action requires the "export-data" permission in the first
  place, as defense in depth.
Regression risk: low -- the intended tables/columns are already fully enumerated
  in indexAction()'s own code; allowlisting against that exact list changes no
  legitimate behavior.
Suggested follow-up task: dedicated P0 task, root-cause group B, cross-referenced
  with F16's fix.
```

---

## 5. Findings — Root cause C: Asterisk PJSIP config generation injection

```
ID: TASK-0026-F12
Title: Newline/section injection into live PJSIP config via Extension name/callerid
Surface: ExtensionsController::execAdd() -> Snep_PjsipConf::loadConfFromDb() -> live "module reload res_pjsip.so"
Reproduction: name/exten POST fields have zero server-side validation (no
  preg_match/ctype_*/length restriction anywhere in the controller). The composed
  callerid string flows unescaped into the generated senma-pjsip.conf
  (Snep_PjsipConf.php:240: $out .= "callerid=" . $peer['callerid'] . "\n";  --
  no escaping function applied anywhere in renderExtension(), lines 149-279).
  loadConfFromDb() writes the file then UNCONDITIONALLY calls self::reload()
  (line 131), which issues AMI "module reload res_pjsip.so" -- applied live,
  synchronously, within the same web request that saved the extension.
  Concrete payload (traced, not executed): a name field containing embedded \n
  sequences terminates the callerid= line and injects a fully-formed new
  [rogue-endpoint]/[rogue-auth]/[rogue-aor] PJSIP object triple -- e.g. a rogue
  endpoint forwarding to an attacker-controlled contact -- or, injected mid-
  section instead, alters an EXISTING section's directives. A trailing ';'
  comments out whatever the generator would otherwise append next.
Evidence: ExtensionsController.php:250,256,754; Snep_PjsipConf.php:128-131,217-263.
Impact: an account with only extensions-write permission (the least-privileged
  write role for this feature) can inject arbitrary Asterisk PJSIP directives
  into the LIVE running SIP stack -- rogue endpoints, altered routing, weakened
  ACLs -- applied automatically, with no review step.
Exploit preconditions: extensions add/edit permission; no special network position.
Severity: CRITICAL
Pilot classification: P0 - blocks pilot
Recommended minimal fix: (a) reject/strip \n, \r, and ';' from name/exten (and
  context, if ever made editable) server-side in execAdd(), independent of any
  client-side pattern= HTML attribute; (b) defense in depth: have
  Snep_PjsipConf::renderExtension() itself reject any field containing \n/\r
  before writing, failing just that one row (matching the existing
  disabled-transport-skip pattern) rather than corrupting the whole file.
Regression risk: low if scoped to control characters/semicolons; confirm real
  caller-ID display-name character needs (accents etc.) before tightening further.
Suggested follow-up task: one shared fix task covering all of F12-F15 -- same
  defect class, same "assert no control characters in any config-bound field"
  helper, applied at both the controller-input and generator-output boundary.
```

```
ID: TASK-0026-F13
Title: Identical unescaped-interpolation defect in Snep_PjsipTrunkConf (callerid/fromuser/fromdomain/username/secret/host)
Surface: TrunksController add/edit -> Snep_PjsipTrunkConf::loadConfFromDb() -> live "module reload res_pjsip.so"
Reproduction: every one of context/callerid/fromuser/fromdomain/username/secret/
  host is raw-concatenated with zero escaping (PjsipTrunkConf.php ~195-309); name/
  auth/registration/identify are also used as unguarded [section] headers.
  TrunksController calls loadConfFromDb() automatically after add/edit, same
  automatic-live-reload property as extensions.
Evidence: Snep_PjsipTrunkConf.php:195-309.
Impact: same injection class as F12, on TRUNKS -- arguably higher real-world
  impact, since trunk host/registration fields control connections to (or
  impersonation of) real external SIP providers, and trunk secret/username
  govern outbound authentication credentials sent to that provider.
Exploit preconditions: trunk add/edit permission.
Severity: CRITICAL
Pilot classification: P0 - blocks pilot
Recommended minimal fix: same shared fix as F12.
Regression risk: low, same reasoning as F12.
Suggested follow-up task: same shared task as F12/F14/F15.
```

```
ID: TASK-0026-F14
Title: Identical unescaped-interpolation defect in Snep_PjsipTransportConf (domain/external_signaling_address/external_media_address/local_net)
Surface: pjsip-transports add/edit -> Snep_PjsipTransportConf::loadConfFromDb() -> live "module reload res_pjsip.so"
Reproduction: protocol/bind_address/bind_port/domain/external_signaling_address/
  _port/external_media_address, and each local_net row (loop over
  pjsip_transport_networks), are all raw-interpolated with zero escaping
  (PjsipTransportConf.php:117-145); [name] is also an unguarded section header.
Evidence: Snep_PjsipTransportConf.php:117-145.
Impact: same class -- a malicious transport domain/address field could inject a
  new transport or alter bind/ACL-adjacent directives for the whole PJSIP stack;
  transports are lower-cardinality/higher-blast-radius than a single extension
  (one transport typically serves many endpoints).
Exploit preconditions: pjsip-transport add/edit permission (TASK-0019 already
  established this as a distinct permission surface).
Severity: CRITICAL
Pilot classification: P0 - blocks pilot
Recommended minimal fix: same shared fix as F12/F13.
Regression risk: low; domain/address fields legitimately need dots/colons/
  slashes (CIDR for local_net) but never newlines/semicolons.
Suggested follow-up task: same shared task.
```

```
ID: TASK-0026-F15
Title: Same defect class in the legacy chan_sip generator (Snep_InterfaceConf)
Surface: legacy SIP/IAX2 peer/trunk provisioning (technology=sip, still a selectable UI option)
Reproduction: context/host/nat/disallow/fromdomain/fromuser/secret all
  raw-interpolated; [defaultuser] used as an unguarded section header. Also noted
  in passing: InterfaceConf.php:94 has a raw-interpolated Zend_Db_Select
  where("name = {$peer['name']}") -- a second-order SQLi-adjacent pattern,
  same class as root cause B.
Evidence: Snep_InterfaceConf.php:83-164 (config injection), :94 (SQLi-adjacent).
Impact: identical injection class, scoped to the legacy chan_sip path. Per
  CLAUDE.md's own migration roadmap, chan_sip is being phased out and PJSIP is
  already the default/recommended technology (TASK-0010/0011/0015) -- chan_sip
  remains selectable but is not the primary MVP pilot path.
Exploit preconditions: same as F12/F13, only if the pilot actually provisions any
  technology=sip extension/trunk.
Severity: CRITICAL (same underlying defect)
Pilot classification: P1 if the pilot is confirmed PJSIP-only (the app default);
  reclassify P0 if any chan_sip-technology extension/trunk is planned.
Recommended minimal fix: same shared fix, extended to this generator.
Regression risk: low.
Suggested follow-up task: fold into the same shared task, or defer slightly if
  pilot scope is confirmed PJSIP-only.
```

---

## 6. Findings — Root causes D, E: architectural authorization / standalone API

```
ID: TASK-0026-F16
Title: Snep_PermissionPlugin's hardcoded action-name allowlist means most application actions have ZERO server-side authorization check
Surface: snep/modules/default/model/PermissionPlugin.php:61-62 (application-wide)
Reproduction: preDispatch() only enforces authorization when getActionName() is
  exactly one of: index, add, remove, edit, duplicate, multiremove, multiadd.
  ANY other action name, on ANY controller, in the entire application -- e.g.
  removefile, addfile, export, view, execAdd (if ever exposed) -- receives no
  server-side permission check at all, REGARDLESS of whether the controller is
  registered as a resource in resources.xml and regardless of what permission
  grants the user actually has. This is the same class of gap TASK-0022 fixed
  specifically for SystemstatusController's restart actions, but it was never
  generalized to the rest of the application.
Evidence: PermissionPlugin.php:46-87 (full method); directly responsible for the
  "any authenticated user" precondition in F3 (Music-on-Hold RCE) and F11
  (Export SQLi/data-read), and very likely others not individually enumerated
  (LogsController per F4 was flagged as "likely" affected by the same mechanism
  but not independently live-verified for that specific controller).
Impact: this is not one vulnerability -- it is a structural gap that silently
  widens the blast radius of every non-CRUD-named action in the application from
  "requires a specific permission grant" to "requires only being logged in at
  all." Fixing individual bugs (F3, F4, F11, and any others sharing this shape)
  without also fixing this root cause leaves the application one typo/oversight
  away from reintroducing the same class of exposure on the next new controller.
Exploit preconditions: any valid login, for any action not in the 7-name list.
Severity: CRITICAL
Pilot classification: P0 - blocks pilot, and the single highest-leverage fix in
  this entire audit.
Recommended minimal fix: generalize the check to inspect EVERY action on a
  registered resource (not just the 7 named CRUD verbs) -- e.g. default to
  requiring the resource's "write" (or a new "execute") permission for any
  action other than a small, explicit read-only allowlist, rather than the
  current inverse (explicit allowlist of CHECKED actions, implicit bypass for
  everything else).
Regression risk: medium -- broadening the check could newly block actions that
  were previously (accidentally) open and that some pilot workflow silently
  depends on. Requires a full route/action inventory across every controller
  before changing, and regression testing against every controller's non-CRUD
  actions -- this is exactly the kind of "server-side enforcement, not page
  visibility" verification TASK-0022 already established as this project's own
  standard for authorization work.
Suggested follow-up task: its own dedicated task, ideally BEFORE the group A/B/C
  bug-by-bug fixes, since it changes how those bugs' severity/preconditions are
  assessed.
```

```
ID: TASK-0026-F17
Title: Standalone api/index.php: pass-the-hash authentication inconsistency plus path-traversal local file inclusion
Surface: snep/modules/default/api/index.php -- a SEPARATE, standalone PHP entry
  point with its own full bootstrap, entirely independent of the main Zend MVC
  front controller / Snep_AuthPlugin session-based auth.
Reproduction: confirmed directly web-reachable (LIVE-VERIFIED: HTTP 401, not 404,
  from an unauthenticated request to /modules/default/api/index.php -- the file
  is served, just requires credentials via this endpoint's own auth logic).
  api/index.php:73-115: two different credential-parsing branches.
  HTTP_AUTHORIZATION header path: base64-decodes and splits user:pass WITHOUT
  applying md5() to the password half.
  PHP_AUTH_USER/PHP_AUTH_PW path: applies $passwd = md5($_SERVER['PHP_AUTH_PW']).
  Both are then passed to Zend_Auth_Adapter_DbTable, which compares $passwd
  directly against the stored users.password column (itself an md5() hash, per
  F21). Since the FIRST branch never hashes its input, a client sending
  Authorization: Basic base64(user:<32-hex-char-md5-hash>) authenticates
  successfully using the STORED HASH VALUE directly as the credential --  without
  ever knowing the plaintext password.
  Once authenticated (or via the unauthenticated ?service=Signup branch, which
  skips auth for that one action): $service_name = $_GET['service'] . "Service";
  $filename = dirname(__FILE__) . "/actions/" . $service_name . ".php";
  if (file_exists($filename)) { require_once($filename); } -- zero path
  validation; "../" traversal is possible, constrained only by the requirement
  that the resolved path end in "Service.php" and exist.
Evidence: api/index.php:73-115 (full file read).
Impact: (a) anyone who has obtained a user's password HASH by any other means
  (a future SQLi finding such as F6/F7/F8, a DB backup leak, etc.) can
  authenticate to this endpoint without ever cracking or knowing the plaintext
  password -- an independent authentication-bypass path layered on top of
  whatever got them the hash. (b) once authenticated (or via the Signup bypass),
  arbitrary *.php files elsewhere on the filesystem matching a "...Service.php"
  naming constraint can be included -- combined with F2/F3's arbitrary-file-write
  RCE, this is a second, independent route to RCE even if those were fixed in
  isolation but this inclusion sink were missed.
Exploit preconditions: (a) requires a target user's stored MD5 hash via some
  other means; (b) requires valid credentials, the hash-as-credential bypass in
  (a), or the unauthenticated service=Signup path (which only reaches the fixed
  SignupService.php target, not attacker-chosen paths, on its own).
Severity: CRITICAL
Pilot classification: P0 - blocks pilot
Recommended minimal fix: (a) apply identical md5() normalization to both
  credential-parsing branches (route both through one shared helper); (b)
  validate $_GET['service'] against an explicit allowlist of the small, fixed
  set of real service names, or at minimum reject any value containing "/",
  "\", or "..".
Regression risk: low for both.
Suggested follow-up task: its own dedicated task -- this file is
  architecturally separate from the main app (its own auth model entirely), so
  the fix is about authentication consistency and path validation, not shell
  escaping or SQL parameterization like the other groups.
```

---

## 7. Findings — Root causes F, G, H, I, J, K

```
ID: TASK-0026-F18
Title: Session fixation -- no session ID regeneration on login
Surface: AuthController::loginAction() (snep/modules/default/controllers/AuthController.php:96-133)
Reproduction: no call to session_regenerate_id() anywhere in the successful-login
  branch; php.ini session.use_strict_mode is Off (confirmed live via php -i),
  meaning PHP will accept and use a client-supplied session ID even if the
  server never generated it.
LIVE-VERIFIED, full account-takeover proof: (1) set a known, attacker-chosen
  PHPSESSID cookie value and visit the login page with it; (2) "log in" as admin
  using that SAME cookie; (3) reuse that SAME cookie in a fresh request with no
  further authentication -- result: HTTP 302 redirect to /index.php/index/add
  (the normal authenticated-dashboard redirect, NOT a redirect to /auth/login) --
  confirming the attacker's pre-chosen session ID is now a fully authenticated
  admin session.
Evidence: AuthController.php:96-133 (no regenerate call); live php -i output
  (session.use_strict_mode => Off).
Impact: an attacker who can get a victim to use a session ID the attacker
  already knows (e.g. a shared/public terminal, a cookie set via XSS -- notably
  easier here since HttpOnly is also Off, see F19) obtains a fully authenticated
  session the moment the victim logs in, without ever needing the victim's
  password.
Exploit preconditions: a mechanism to get the victim to use an attacker-chosen
  session ID before they log in.
Severity: HIGH
Pilot classification: P1 - fix before broad rollout (P0-adjacent in combination
  with F19's missing HttpOnly, which provides a practical cookie-setting vector
  via any future XSS).
Recommended minimal fix: call session_regenerate_id(true) immediately after
  Zend_Auth's identity is written on successful login (AuthController.php:107).
Regression risk: low -- standard, well-understood fix; verify no code elsewhere
  depends on the session ID staying constant across login (unlikely).
Suggested follow-up task: bundle with F19/F20 as one "session/cookie hardening"
  task.
```

```
ID: TASK-0026-F19
Title: Session cookie missing HttpOnly, Secure, and SameSite
Surface: PHP session configuration (docker/php-mag.ini has no session.* overrides;
  no session_set_cookie_params()/ini_set("session.cookie_*") call found anywhere
  in application code)
Reproduction/Evidence: LIVE-VERIFIED via `php -i`: session.cookie_httponly=>Off,
  session.cookie_secure=>Off, session.cookie_samesite=>no value,
  session.use_trans_sid=>Off (good -- no URL-based session ID leakage).
  LIVE-VERIFIED via real HTTP response: `Set-Cookie: PHPSESSID=...; path=/` --
  no HttpOnly, no Secure, no SameSite attribute at all.
Impact: HttpOnly=Off means any future XSS (or the vendor-content class TASK-0025
  hardened, or a reflected-XSS finding if one exists elsewhere) can read the
  session cookie via JavaScript, directly enabling session theft; it also makes
  F18's session-fixation attack easier to stage (document.cookie can plant the
  fixed ID). Secure=Off and SameSite=unset are more nuanced per this task's own
  instruction (§13): Secure only makes sense over TLS, and this is explicitly a
  DEPLOYMENT decision, not purely a code defect -- but there is currently no
  code-level toggle to enable Secure in a TLS deployment at all, meaning even a
  hypothetical HTTPS pilot would still ship with Secure=Off unless someone edits
  php.ini by hand.
Exploit preconditions: HttpOnly gap requires a separate XSS/cookie-write vector
  to be useful; Secure/SameSite gaps are deployment-configuration-dependent.
Severity: MEDIUM (HttpOnly alone) / contextually HIGH given other findings in
  this audit
Pilot classification: P1 - fix before broad rollout. HttpOnly should be enabled
  unconditionally (CODE FIX, no legitimate reason found for JS to read the
  session cookie). Secure should be made deployment-configurable (CODE FIX
  providing the toggle; DEPLOYMENT REQUIREMENT to actually enable it under TLS).
  SameSite=Lax is a safe default to set explicitly (CODE FIX) rather than
  relying on browser-default behavior.
Recommended minimal fix: session_set_cookie_params() (or php-mag.ini overrides)
  setting httponly=true always, samesite=Lax always, and secure driven by an
  explicit environment-derived flag (e.g. an APP_FORCE_SECURE_COOKIES env var),
  defaulting to false for the current HTTP-only dev workflow so `make dev`
  keeps working unmodified.
Regression risk: low for HttpOnly/SameSite; Secure must be introduced as an
  opt-in toggle, never forced, to avoid breaking the documented HTTP dev flow.
Suggested follow-up task: bundle with F18/F20.
```

```
ID: TASK-0026-F20
Title: No CSRF protection on any state-changing action except the Asterisk restart feature
Surface: application-wide
Reproduction/Evidence: grep -rln "csrf" across every snep/modules and snep/lib
  PHP/phtml file returns exactly 3 matches: SystemstatusController.php and its
  view (TASK-0022's own restart-specific token), and the unused
  Zend_Form_Element_Hash vendored class (zero call sites elsewhere). Every other
  state-changing action found across this entire audit -- Users, Profiles,
  Extensions, Trunks, Transports, Sound Files, Music on Hold, Export, password
  reset -- has no CSRF token generation or verification anywhere in its request
  handling. Additionally corroborated by this entire audit session's own dozens
  of successful POST requests made throughout (login, none of the live tests)
  never needing to first fetch/submit a token, except the one restart endpoint.
Impact: combined with F16 (many actions require only "any login," not a specific
  permission) and the RCE/SQLi findings above, a malicious website visited by a
  logged-in SENMA user could silently trigger destructive or dangerous actions
  (delete a user, delete a trunk, plant a malicious extension name -- see F12) via
  an auto-submitting cross-site form, with no token to block it.
Exploit preconditions: an authenticated SENMA session (any privilege level, per
  F16) plus the victim visiting an attacker-controlled page.
Severity: HIGH
Pilot classification: P1 - fix before broad rollout. Not classified P0 standalone
  because reaching most of the truly critical actions already requires either no
  auth at all (F1/F6, which don't need CSRF to exploit) or a privilege an
  attacker would need to acquire anyway -- but this significantly widens the
  practical attack surface for every other write action once combined with the
  P0 findings above, and should be treated as urgent, not deferred indefinitely.
Recommended minimal fix: extend the exact CSRF pattern TASK-0022 already built
  and proved for the restart feature (a scoped synchronizer token) to every
  state-changing controller action, or adopt it as a front-controller plugin
  applied uniformly (which would also naturally piggyback on fixing F16's
  action-name allowlist gap).
Regression risk: medium -- every existing form needs the token added and every
  handler needs the check; needs careful, broad but mechanical rollout with full
  regression testing (this project's own established smoke-suite discipline).
Suggested follow-up task: its own dedicated task, sequenced after F16 (fixing
  the authorization gap first makes the CSRF rollout's own scope/testing
  cleaner).
```

```
ID: TASK-0026-F21
Title: Unsalted MD5 password hashing
Surface: AuthController.php:94 ($authAdapter->setCredential(md5($password))),
  Snep_Auth_Manager::getUpdatePass() (password reset path, not independently
  re-read in full but confirmed to feed the same users.password column), install
  seed data (see F27)
Reproduction/Evidence: AuthController.php:94; install seed
  snep/install/database/system_data.sql:72 stores a bare 32-hex-char MD5 digest
  in users.password with no visible salt column in the users table schema.
Impact: MD5 is fast to brute-force/rainbow-table, and the absence of a salt
  means identical passwords across different users (or a leaked hash from any
  source, including F6/F7/F8's SQLi findings) produce identical, directly
  comparable, quickly-crackable hashes.
Exploit preconditions: access to the hash by any means (SQLi, DB backup, etc.).
Severity: MEDIUM-HIGH (compounds the severity of F6/F7/F8's data-exposure impact)
Pilot classification: P1 - fix before broad rollout. Not standalone P0 since it
  requires a separate hash-disclosure vector to matter in practice, but those
  vectors already exist elsewhere in this audit.
Recommended minimal fix: migrate to PHP's own password_hash()/password_verify()
  (bcrypt/argon2, salted, adaptive cost) with a one-time migration path (re-hash
  on next successful login, keeping the old MD5 check as a fallback only until
  migrated) -- a well-established, low-risk pattern for exactly this situation.
Regression risk: medium -- touches the core login path; needs careful staged
  rollout and thorough auth-flow regression testing.
Suggested follow-up task: its own dedicated task, given the migration-path
  design work involved.
```

```
ID: TASK-0026-F22
Title: No login rate-limiting or brute-force protection
Surface: AuthController::loginAction()
Reproduction/Evidence: full read of loginAction() (AuthController.php:34-145) --
  no lockout counter, no delay, no CAPTCHA, no IP-based throttling anywhere in
  the authentication flow or surrounding plugins.
Impact: combined with F21's fast unsalted MD5 hashing and F27's known default
  credential, online brute-forcing of the admin account (or any account) is
  unthrottled.
Exploit preconditions: network access to the login form.
Severity: MEDIUM
Pilot classification: P1 - fix before broad rollout.
Recommended minimal fix: a simple failed-attempt counter (per username and/or
  per IP) with exponential backoff or a temporary lockout, stored in the
  existing DB/session infrastructure -- no new dependency needed.
Regression risk: low, if the threshold is generous enough not to lock out
  legitimate users during normal typos.
Suggested follow-up task: bundle with F21 (both are login-hardening work).
```

```
ID: TASK-0026-F23
Title: Weak PRNG for password-reset codes
Surface: AuthController::aleatorio() (snep/modules/default/controllers/AuthController.php:285-293)
Reproduction/Evidence: srand((double) microtime() * 1000000); then rand() % strlen($valor)
  for each of 6 characters from a 36-character alphabet (2.1 billion combinations,
  1-hour expiration per redefineAction()). rand()/srand() is a legacy,
  non-cryptographic PRNG; seeding via microtime() is theoretically guessable/
  narrowable by an attacker who can measure request timing.
Impact: in principle weakens the password-reset code's unpredictability, though
  the combinatorial space (2.1B) makes brute-forcing the code directly within
  its 1-hour window impractical over HTTP without extreme throughput; the
  concern is the seed's guessability narrowing that space, not exhaustive search.
Exploit preconditions: ability to trigger/observe password-reset requests with
  precise timing, plus the target's username.
Severity: LOW
Pilot classification: P2 - post-pilot hardening.
Recommended minimal fix: use random_int()/random_bytes() (cryptographically
  secure, already available in PHP 8.4) instead of rand()/srand().
Regression risk: low.
Suggested follow-up task: minor, can be bundled with any future auth-hardening
  task.
```

```
ID: TASK-0026-F24
Title: Fragile, controller-unscoped auth-bypass check in Snep_AuthPlugin
Surface: snep/lib/Snep/AuthPlugin.php:46 (preDispatch())
Reproduction/Evidence: if (!$auth->hasIdentity() && ($action != "redefine" &&
  $action != "recuperation")) { redirect to login }. This check is based purely
  on ACTION NAME, with no CONTROLLER check -- any future controller that happens
  to define an action literally named redefineAction() or recuperationAction()
  would silently become reachable without authentication, regardless of intent.
  Currently, grep confirms only AuthController defines these two actions
  (no collision exists today).
Impact: none exploitable today; a latent design fragility that could silently
  reintroduce an authentication bypass if a future controller happens to reuse
  either action name.
Exploit preconditions: a future code change, not exploitable against the current
  codebase.
Severity: LOW
Pilot classification: P2 - post-pilot hardening (or a one-line fix now, given
  how cheap it is).
Recommended minimal fix: also check $controller == 'auth' in the condition.
Regression risk: none.
Suggested follow-up task: trivial, can be fixed alongside F1 in the same file's
  neighborhood.
```

```
ID: TASK-0026-F25
Title: Unconditional internal exception-message disclosure on every server error
Surface: snep/modules/default/views/scripts/error/error.phtml:10
Reproduction/Evidence: <p><strong>Server Message:</strong> <?php echo
  $this->exception->getMessage(); ?></p> -- gated ONLY by $this->code != 404, NOT
  by APPLICATION_ENV/debug mode. Confirmed via this session's own TASK-0024
  diagnostic history: a real 500 error during that investigation displayed
  "Server Message: SQLSTATE[23000]: Integrity constraint violation: 1062
  Duplicate entry '1' for key 'name'" directly in the browser -- exposing raw SQL
  error text (table/column/constraint names) to any user who triggers a 500.
  Separately, error.phtml:13-24's fuller block (class name, full stack trace,
  var_dump() of ALL request parameters -- which could include a submitted
  password) IS correctly gated by 'development' == APPLICATION_ENV, and
  APPLICATION_ENV correctly defaults to "production" (setup.conf's debug="0",
  confirmed both in the live container and in setup.conf.dist's template
  default) -- so the worst-case disclosure (full trace + request params) is NOT
  active by default. The narrower "Server Message" line, however, always is.
Impact: aids attacker reconnaissance (schema/query structure) on every 500
  error, independent of environment. Does not by itself leak credentials, but
  measurably lowers the effort needed to develop/refine the SQLi findings
  elsewhere in this audit.
Exploit preconditions: ability to trigger a 500 error (broadly available --
  many of this audit's own findings do so incidentally).
Severity: MEDIUM
Pilot classification: P1 - fix before broad rollout.
Recommended minimal fix: gate the "Server Message" line by the same
  'development' == APPLICATION_ENV check the rest of the debug block already
  uses; show only the generic $this->message text otherwise.
Regression risk: none -- purely removes information from an error page.
Suggested follow-up task: trivial, one-line conditional change.
```

```
ID: TASK-0026-F26
Title: X-Powered-By header exposes exact PHP version
Surface: Apache/PHP default configuration (no expose_php=Off in docker/php-mag.ini)
Reproduction/Evidence: LIVE-VERIFIED via curl -I: `X-Powered-By: PHP/8.4.25`
  present on every response. Also confirmed: no Content-Security-Policy,
  X-Frame-Options, X-Content-Type-Options, Referrer-Policy, or
  Strict-Transport-Security header present anywhere (assessment only, per this
  task's own §14 instruction -- not treated as a standalone pilot-blocking
  finding, recorded for the deployment checklist and a future dedicated
  header-hardening task).
Impact: minor reconnaissance aid (exact version fingerprinting); the missing
  security headers are standard defense-in-depth omissions, not proven
  individually exploitable in this audit.
Exploit preconditions: none (passive observation).
Severity: INFO/LOW
Pilot classification: P2 - post-pilot hardening. Per this task's own explicit
  instruction, a full header rollout is out of scope here.
Recommended minimal fix: expose_php = Off in php-mag.ini (one line); defer the
  broader CSP/X-Frame-Options/HSTS rollout to a dedicated future task.
Regression risk: none for expose_php.
Suggested follow-up task: a dedicated "release hardening: HTTP security headers"
  task, explicitly deferred per this audit's own scope.
```

```
ID: TASK-0026-F27
Title: Fresh install ships a well-known default admin credential with no forced change
Surface: snep/install/database/system_data.sql:72
Reproduction/Evidence: INSERT INTO users (name, password, ...) VALUES ('admin',
  '0192023a7bbd73250516f069df18b500', ...). Verified: md5('admin123') ==
  0192023a7bbd73250516f069df18b500 -- the seeded credential is admin/admin123, a
  well-known, easily-guessed default for this PBX lineage. No forced-password-
  change flow exists anywhere in AuthController/the login flow for a first-time
  or default-credential login (confirmed via the full loginAction() read for F22).
Impact: any fresh SENMA install is immediately compromisable by anyone who
  simply tries the well-known default, unless an operator remembers to change it
  before exposing the instance to any network. Combined with F22 (no rate
  limiting), even a non-default-but-weak password chosen by an operator is at
  further risk.
Exploit preconditions: network access to a freshly-installed, not-yet-
  reconfigured instance.
Severity: CRITICAL if unaddressed at deployment time
Pilot classification: P0 as a DEPLOYMENT REQUIREMENT (the password MUST be
  changed before any pilot instance is network-reachable by anyone other than
  the installing operator) AND P1 as a CODE GAP (no mechanism forces or even
  prompts this change, so it is easy to forget).
Recommended minimal fix (code): add a first-login forced-password-change flow,
  or at minimum a persistent, impossible-to-dismiss admin-UI warning banner
  while the seeded hash remains unchanged (cheap to detect: compare the live
  admin password hash against the known seeded value).
Recommended minimal fix (deployment): mandatory pre-pilot checklist item --
  verify the admin password has been changed from the installer default before
  granting any network access beyond the installing operator.
Regression risk: low for a warning banner; medium for a forced-change flow
  (needs careful UX so it doesn't lock out the installing operator).
Suggested follow-up task: a small, dedicated task; also add explicitly to the
  operational pilot checklist (§8).
```

```
ID: TASK-0026-F28
Title: Path traversal in the Documentation viewer, constrained to .md files
Surface: DocsController::indexAction()
Reproduction/Evidence: DocsController.php:56-66: foreach ($data as $key => $value)
  { $html = file_get_contents('/var/www/html/snep/docs/'. strtoupper($key) .'.md');
  ... } -- $key is a raw REQUEST PARAMETER NAME (not value), used except for
  strtoupper(), which does not strip "/" or ".." sequences. A POST with a
  parameter name like ../../../../some/path/README=x attempts traversal.
  Reachability: "docs"/"documentation" does not appear as a registered resource
  in resources.xml (grep found no match) -- per this codebase's own established
  pattern (TASK-0022), an unregistered controller receives NO permission check
  at all, meaning any authenticated user can reach this regardless of profile.
Impact: constrained but real -- the appended ".md" suffix is unconditional and
  NOT uppercased, meaning classic targets like /etc/passwd are not reachable
  this way, but any other .md file elsewhere on the container filesystem
  reachable via traversal would be exposed, rendered through Parsedown into the
  authenticated UI.
Exploit preconditions: any valid SENMA login.
Severity: MEDIUM (would be HIGH/CRITICAL without the mandatory .md constraint)
Pilot classification: P1 - fix before broad rollout.
Recommended minimal fix: allowlist $key against basename()-only,
  alphanumeric-plus-hyphen values matching the actual known doc filenames, or
  replace the free-form parameter with a fixed, enumerated set of valid doc
  names.
Regression risk: low -- a fixed enum of legitimate doc names preserves all
  intended functionality.
Suggested follow-up task: small, standalone fix.
```

---

## 8. Confirmed-clean / informational findings

```
ID: TASK-0026-F29
Title: unserialize() usage confirmed safe (re-verification of TASK-0023 finding)
Surface: Snep_Dashboard_Manager.php:52
Evidence: unserialize($dashboard->dashboard) reads a users.dashboard column
  value written only by locally-controlled dashboard-configuration code
  (TASK-0023 already traced this fully) -- never from a remote/vendor payload.
Severity: INFO / Pilot classification: N/A
```

```
ID: TASK-0026-F30
Title: No eval()/assert()-as-code-execution found anywhere in first-party code
Evidence: grep -rn "eval(" across snep/, excluding vendored Zend, zero matches.
Severity: INFO / Pilot classification: N/A
```

```
ID: TASK-0026-F31
Title: Snep_Trunks_Manager::getTrunkLog() is NOT a shell-execution bug -- corrects CLAUDE.md's own flagged suspicion
Evidence: Trunks/Manager.php:174-203 -- the suspicious $sql string is dead code
  (built, never executed; the real query is a separate, safely-parameterized
  Zend_Db_Select). The "backtick" CLAUDE.md's own note refers to is a MySQL/
  MariaDB column-alias identifier quote (`call-limit as call_limit`), not shell
  command substitution.
Severity: INFO / Pilot classification: N/A. Recommend correcting CLAUDE.md's own
  debt note to remove the "shell-execution" characterization.
```

```
ID: TASK-0026-F32
Title: Snep_Asterisk_Operations (TASK-0021/0022 restart feature) confirmed clean
Evidence: zero exec/shell_exec/system/passthru/popen/proc_open/backtick usage --
  a pure raw-socket AMI TCP client, exactly as documented in TASK-0021/0022.
Severity: INFO / Pilot classification: N/A
```

```
ID: TASK-0026-F33
Title: Snep_Inspector's dynamic-class-name constructor branch is dead code today
Evidence: the vulnerable branch (include $path."/".$inspect.".php"; new $inspect;)
  has exactly one call site (new Snep_Inspector();), which always uses the
  default, safe $inspect=false branch.
Severity: LOW (latent risk only if ever wired to request input in the future) /
  Pilot classification: N/A
```

```
ID: TASK-0026-F34
Title: Docker/Compose topology is well-designed for this deployment model
Evidence (LIVE-VERIFIED + code review of compose.yaml): only app's HTTP port is
  published to the host; db has no published port; asterisk's AMI (5038) is
  explicitly documented as never published; the provider simulator publishes
  nothing. No privileged: true, no network_mode: host, no Docker socket mount,
  no unusual capabilities anywhere. Network is a pinned, isolated custom bridge
  (172.28.0.0/16). Volume scoping is deliberate and documented (app's /etc/
  asterisk mount, asterisk's own config/spool/log volumes, the read-only source
  mounts into the asterisk container).
Severity: INFO (positive finding) / Pilot classification: N/A -- confirms items
  16-18 of this audit's own checklist are satisfied for the DEV topology; a real
  pilot deployment still needs its own network/firewall review (§8's checklist)
  since production network placement is a deployment decision, not something
  compose.yaml alone can guarantee.
```

```
ID: TASK-0026-F35
Title: setup.conf/.env correctly blocked from direct web access; error display correctly configured for production by default
Evidence (LIVE-VERIFIED): curl to /includes/setup.conf and /includes/setup.conf.dist
  both return HTTP 403 (TASK-0001's own established protection, still holding).
  /.env and /.git/config both return 404 (not present under the web root).
  docker/php-mag.ini: display_errors=Off, errors routed to error_log=/dev/stderr
  (captured via `make logs`), not shown to the browser -- this is a DIFFERENT,
  correctly-configured mechanism from the application-level "Server Message"
  disclosure in F25, which is not controlled by display_errors at all.
  APPLICATION_ENV correctly defaults to "production" (setup.conf.dist's
  debug="0" default, confirmed matching the live container's actual value),
  so error.phtml's full stack-trace/request-params disclosure block is NOT
  active by default.
Severity: INFO (positive finding) / Pilot classification: N/A
```

```
ID: TASK-0026-F36
Title: Dependency/runtime versions are current, not end-of-life
Evidence (LIVE-VERIFIED): PHP 8.4.25, Asterisk 22.10.1 (LTS), MariaDB 10.11.18
  (LTS), Debian 13 "trixie". None of these are EOL at the time of this audit.
Severity: INFO / Pilot classification: N/A
```

```
ID: TASK-0026-F37
Title: TASK-0024/0025 vendor trust-boundary properties reconfirmed intact
Evidence: full regression run (§9) -- make external-failure-smoke 27/27, make
  external-content-smoke 14/14, both clean, both re-run AFTER this audit's own
  live testing to confirm no incidental regression. Vendor unavailability still
  degrades safely (TASK-0024); cached vendor content remains escaped at render
  (TASK-0025). No newly-discovered vendor sink was found rendered raw during
  this audit's own investigation (the four vendor integrations traced in
  TASK-0024/0025 -- Notifications, Version, CloudNotice, Announce -- were not
  re-touched; this audit's scope was the broader MVP write surface, not a
  repeat of that investigation).
Severity: INFO (positive finding) / Pilot classification: N/A
```

---

## 9. Regression suite baselines (§30 of the instructions)

No application code was modified during this audit (all live tests were
non-destructive, and the two transient side effects were reverted before
this run). First-run results, no retries:

| Suite | Result | Notes |
|---|---|---|
| `make smoke` | 16/16 | clean |
| `make call-smoke` | 17/18 | known, pre-existing CDR/report timezone artifact (§10 of this doc); not a new regression |
| `make trunk-smoke` | 21/23 | same known artifact, 2 instances; not a new regression |
| `make transport-smoke` | 63/63 | clean |
| `make restart-smoke` | 37/37 | clean |
| `make external-failure-smoke` | 27/27 | clean — reconfirms TASK-0024 |
| `make external-content-smoke` | 14/14 | clean — reconfirms TASK-0025 |

`git status` is clean (`nothing to commit, working tree clean`) — this
audit produced findings and this document only, no code changes.

---

## 10. The known CDR/report timezone artifact — classification (§25)

Already fully root-caused by TASK-0024 (§40 of that document): PHP's
default timezone is UTC while MariaDB's `time_zone` is `SYSTEM` (local,
`-03` in this dev environment). A call's `cdr.calldate` is computed via
PHP (UTC) while the reporting query's "today" range is anchored to local
wall-clock time — during the ~3-hour nightly window where the two clocks
disagree about the calendar day, a call made in that window is
correctly recorded (the CDR row itself is always correct — the "CDR row
exists and is correct" check has never failed in this project's history)
but temporarily falls outside a "today" report's date window.

**Classification: P1, not P0.** Reasoning:
- The underlying data is never lost, corrupted, or wrong — only a
  *report query's day-boundary window* is affected, for a bounded ~3
  hours per day.
- A wider date-range query (yesterday+today, or any absolute range)
  retrieves the call correctly at any time.
- It does not affect call routing, billing accountcode assignment, or
  any live PBX function — only after-the-fact report *visibility*.
- It self-corrects: once local time passes midnight, the affected calls
  reappear in the (now-correct) "today" window.
- For a controlled pilot with known, small call volumes, staff can be
  briefed on the artifact; it does not block using the system for its
  core purpose (making/receiving calls, provisioning, administration).

It should still be fixed before **broad** rollout (P1), since silent,
unexplained report gaps are a real trust/usability problem at scale —
but it is not a reason to block the pilot itself, and per this task's
own instruction (§25), it is explicitly **not** fixed here.

---

## 11. Operational pilot checklist (§24)

| Item | Type | Status |
|---|---|---|
| All P0 findings (§2) remediated and re-validated | CODE FIX | **Not done — blocks pilot** |
| Admin password changed from the installer default (F27) | DEPLOYMENT | Required before any network exposure |
| TLS termination in front of the app | DEPLOYMENT | Not addressed by this codebase; required before any non-trusted-network exposure, and a prerequisite for enabling `Secure` cookies (F19) |
| Firewall rules restricting reachability to the app's HTTP port only | DEPLOYMENT | Compose topology already keeps DB/AMI internal-only (F34) — a host-level firewall/network policy is still an external deployment responsibility |
| No public AMI exposure | DEPLOYMENT | Already true in this compose topology (F34); must be preserved in the actual pilot host network design |
| Restricted DB exposure (no public port, non-root app DB user) | DEPLOYMENT | Compose topology already correct (F34); verify the pilot's actual DB user grants are least-privilege, not `root` |
| Backup requirement for the database and Asterisk config volumes | DEPLOYMENT | Not assessed in this audit — recommend a dedicated backup/restore verification pass before pilot (explicitly out of this task's scope per its own §19 instruction) |
| DNS/NTP/timezone expectations | DEPLOYMENT | The timezone artifact (§10) means accurate host NTP sync matters for report accuracy, though not for correctness of the underlying data |
| Persistent volume expectations | DEPLOYMENT | Already correctly modeled in compose.yaml (named volumes for DB/Asterisk state) |
| `.env` never committed, secrets not baked into images | CODE — already correct | Confirmed (F35) |
| `expose_php` disabled | CODE FIX | Trivial, bundle with F26 |

---

## 12. Acceptance criteria — direct answers (§31)

1. **Can unauthenticated users mutate the PBX?** Yes — F1 (unauthenticated
   RCE) provides complete, unrestricted control, and F6 (unauthenticated
   SQLi) provides complete database read/write-adjacent access, both
   without any credential.
2. **Can restricted users bypass write permissions?** Yes — F16 (the
   `Snep_PermissionPlugin` action-name gap) means any action not named
   exactly `index/add/remove/edit/duplicate/multiremove/multiadd` has no
   permission check at all; F3 and F11 are confirmed concrete
   consequences (RCE and full-database-read reachable by *any* logged-in
   user, not just privileged ones).
3. **Do critical writes have CSRF protection?** No — F20: only the
   TASK-0022 restart feature has a CSRF token; every other write action
   in the application has none.
4. **Does request data reach shell execution?** Yes, extensively — F1
   through F5 (root cause A), including one unauthenticated path (F1).
5. **Can request data inject Asterisk configuration?** Yes — F12 through
   F15 (root cause C), auto-applied live to the running Asterisk
   instance within the same HTTP request, for extensions, trunks, and
   transports.
6. **Can arbitrary files be read/written through pilot surfaces?** Yes —
   F17 (LFI via `api/index.php`'s `service` parameter) for reads;
   F2/F3's command-injection findings effectively allow arbitrary file
   writes (and much more) as a byproduct of shell RCE; F28 (contained
   path traversal, `.md`-only) for a narrower read case.
7. **Are secrets exposed?** Not directly via the web surface tested
   (`setup.conf`/`.env` are correctly blocked, F35) — but F1's RCE and
   F6/F7/F8's SQLi findings each independently provide a path to read
   `setup.conf` (DB/AMI credentials) or the `users`/`core_config` tables
   directly, making the point moot in practice until those are fixed.
8. **Are sessions/cookies acceptable for pilot deployment?** No — F18
   (session fixation, live-proven full account takeover) and F19
   (missing `HttpOnly`/`Secure`/`SameSite`) are both real, code-level
   gaps that should be fixed before pilot, not merely before broad
   rollout, given how directly F18 was demonstrated to lead to admin
   account takeover.
9. **Are Docker/AMI/DB boundaries acceptable?** Yes, for the topology as
   currently defined (F34) — no privileged containers, no exposed
   AMI/DB ports, isolated network. This is a genuine strength of the
   current implementation and does not block the pilot; the remaining
   work here is deployment-side (§11's checklist), not code-side.
10. **Does a fresh install have unsafe defaults?** Yes — F27: a
    well-known default admin credential (`admin`/`admin123`) with no
    forced-change mechanism.
11. **Does the known timezone issue block a real pilot?** No — classified
    P1 in §10, with evidence; it affects report *visibility* during a
    bounded nightly window, never data correctness or live PBX function.
12. **The exact list of P0 items required before pilot**: F1, F2, F3,
    F4, F6, F7, F8, F9, F11, F12, F13, F14, F16, F17, plus F27 as a
    mandatory deployment action (and F5, F10, F15 pending the
    reachability/scope confirmations noted in each). See §2's
    root-cause grouping for how these cluster into a smaller number of
    actual fix efforts.

---

## 13. Recommended next task order

Given the root-cause clustering in §2, and that fixing bugs without
fixing the authorization gap they're reachable through would understate
the real risk reduction achieved:

1. **TASK-0027 — Fix `Snep_PermissionPlugin`'s action-name authorization gap (F16).** Highest leverage, smallest single change, and changes how several other findings' severity/preconditions should be re-assessed once fixed. Requires a full action inventory across every controller before changing, per its own regression-risk note.
2. **TASK-0028 — Fix unauthenticated pre-auth vulnerabilities (F1, F6).** Both require no login at all; fix together since both are in `AuthController`'s own request path and both need careful login-flow regression testing (reuse this project's own established smoke-suite discipline).
3. **TASK-0029 — Fix raw SQL interpolation across Extensions/Trunks/Users/Profiles/Export (F7, F8, F9, F11, and F10 once reachability is confirmed).** One mechanical fix pattern (swap to `Zend_Db` parameterization, already correctly used elsewhere in this codebase) applied across a bounded, enumerable set of call sites.
4. **TASK-0030 — Fix unescaped shell command construction in Sound Files/Music-on-Hold/Logs (F2, F3, F4, and F5 once reachability is confirmed).** Same shared "safe shell argument" fix pattern.
5. **TASK-0031 — Fix Asterisk PJSIP config-generation injection (F12, F13, F14, and F15 if chan_sip is in pilot scope).** Architecturally distinct from the SQL/shell fixes; one shared "reject control characters in config-bound fields" validation.
6. **TASK-0032 — Fix the standalone `api/index.php` (F17).** Architecturally separate auth model; its own small, self-contained fix.
7. **TASK-0033 — Session/cookie/CSRF hardening (F18, F19, F20).** Can proceed in parallel with the above once F16 is fixed (CSRF rollout scope is cleaner post-F16).
8. **TASK-0034 — Auth hardening: password storage migration, rate limiting, default-credential warning (F21, F22, F23, F24, F27's code-side gap).**
9. Deferred/lower-priority: F25 (one-line fix, can ride along with any of the above), F26/header hardening (explicitly deferred per this task's own scope), F28 (small standalone fix), F10/F5/F15 reachability confirmations (quick, should happen early to correctly prioritize).

Re-run this audit's own new regression targets
(`make external-content-smoke`, `make external-failure-smoke`) plus the
full existing suite after each of the above, per this project's
established validation discipline.

---

## 14. Final decision

**PILOT SECURITY STATUS: BLOCKED**

**P0 blockers:**
F1 (unauthenticated RCE), F2 (authenticated RCE, Sound Files), F3
(authenticated RCE, any logged-in user, Music-on-Hold), F4 (authenticated
RCE, Logs), F6 (unauthenticated SQLi, login), F7 (SQLi, Extensions), F8
(SQLi, Users/Profiles — mass privilege escalation), F9 (SQLi, Trunks),
F11 (SQLi + authz bypass, Export — any logged-in user), F12/F13/F14
(Asterisk PJSIP config injection — Extensions/Trunks/Transports,
auto-applied live), F16 (authorization architecture gap — root cause
amplifying several of the above), F17 (standalone API auth
inconsistency + LFI), F27 (default admin credential, as a mandatory
deployment action). F5/F10/F15 are P0-pending-confirmation (reachability
or scope not fully settled).

**P1 before broad rollout:**
F5 (CNL RCE, pending reachability), F9 already listed as P0, F10 (CSV
import SQLi, pending reachability), F15 (chan_sip config injection, if
in scope), F18 (session fixation), F19 (cookie flags), F20 (CSRF), F21
(password hashing), F22 (login rate limiting), F25 (exception-message
disclosure), F28 (docs path traversal), the timezone artifact (§10).

**P2 post-pilot:**
F23 (PRNG), F24 (auth-bypass design fragility), F26 (missing headers,
`expose_php`), F33 (dead-code latent risk note).

**Required deployment conditions** (independent of code fixes, §11):
TLS termination, firewall-restricted network exposure, verified
non-public AMI/DB, changed admin password, backup strategy verified,
accurate host NTP/timezone.

**Recommended next task:** TASK-0027 — fix the
`Snep_PermissionPlugin` action-name authorization gap (F16) first, per
§13's reasoning; then proceed through the root-cause-grouped task order
in §13.

Stopping at the audit checkpoint, as instructed. No implementation
performed. Do not begin TASK-0027 automatically — awaiting explicit
authorization.
