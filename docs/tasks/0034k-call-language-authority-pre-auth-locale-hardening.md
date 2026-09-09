# TASK-0034K — Call Language Authority & Pre-Auth Locale Hardening

Lead: `senma-telephony-architect` (canonical dialplan/call-language
authority, `Snep_Locale::setExtensionsLanguage()` propagation mechanism).
Reviewers: `senma-application-architect` (pre-auth/authenticated write
boundary, CSRF, authorization), `senma-docker-platform-engineer`
(`extensions.conf` file-permission root cause and fix). `senma-asterisk-
pjsip-engineer` was not invoked -- no Asterisk-specific dialplan/runtime
*implementation* change was required once root-caused (the dialplan's own
`Set(CHANNEL(language)=${SNEP_LANGUAGE})` authority was already correct;
see DIALPLAN AUTHORITY below). `senma-product-designer` was not invoked --
the pre-auth language links keep their exact URL/behavior/redirect shape;
nothing user-visible changed except that the choice is now session-scoped
instead of global.

Split from TASK-0034J's D3 finding (`docs/tasks/0034j-runtime-resource-
follow-up-debt-closure.md`), which traced the authority chain and the
pre-auth writer but deliberately did not fix it (architecture-sensitive,
beyond that task's follow-up-debt-closure mandate).

## STARTING STATE

```
HEAD:   7296c6e docs(tasks): document TASK-0034J debt closure
branch: main
status: clean
```

## ORIGINAL FINDING

TASK-0034J (D3) found that `AuthController::loginAction()`'s pre-auth
`?indexChooseLanguage=en|pt_BR|es` GET handler (reachable by any
unauthenticated visitor via a bare link on the public login page) wrote
`setup.conf`'s global `system.language` and called
`Snep_Locale::setExtensionsLanguage()` -- the same mechanism the
authenticated, CSRF-protected in-app language switcher uses -- with no
authentication, no authorization, and no CSRF applicability (no session
exists yet). It proposed this task to close it without regressing the
pre-auth "view the login page in your language" feature, which had no
session-scoped alternative to fall back to.

## REQUEST PATH (traced live)

```
GET /index.php/default/auth/login?indexChooseLanguage=es
  -> Bootstrap.php (top-level): Snep_Session_CookiePolicy::apply(); Zend_Session::start()
  -> Bootstrap::_initLogin(): registers Snep_AuthPlugin
  -> Snep_AuthPlugin::preDispatch(): !hasIdentity() -> forces module=default/
     controller=auth/action=login (a no-op here -- already that route)
  -> Bootstrap::_initPermission(): Zend_Auth::hasIdentity() is false ->
     Snep_PermissionPlugin and Snep_CsrfPlugin are NEVER REGISTERED for
     this request (both are only registered inside this same `if
     ($auth->hasIdentity())` block) -- structurally, no authorization or
     CSRF check can ever run against this route pre-auth
  -> Bootstrap::_initLocale(): Snep_Locale::getInstance() constructed
     from setup.conf (BEFORE the controller action runs)
  -> AuthController::loginAction() (pre-fix):
       isset($_GET['indexChooseLanguage']) && isSupportedLanguage(...)
         -> write setup.conf (Zend_Config_Writer_Ini, whole-file rewrite)
         -> Snep_Locale::setExtensionsLanguage($_GET['indexChooseLanguage'])
              -> shell out: sed extensions.conf's SNEP_LANGUAGE -> temp file -> mv
              -> PBX_Asterisk_AMI::getInstance()->Command("dialplan reload")
         -> $this->_redirect('/')
```

`Snep_CsrfPlugin`'s own docblock already documented *why* it structurally
never runs pre-auth ("no authenticated session yet for a forged
cross-site request to abuse") -- true for CSRF, but that same structural
gap is exactly what let this route mutate global state with **zero**
authentication check of any kind, not just no CSRF.

## WRITER INVENTORY

Every caller of `Snep_Locale::setExtensionsLanguage()` and every other
writer of `SNEP_LANGUAGE`/language-related `setup.conf` values (grep
across the whole PHP tree; zero unknown writers):

| WRITER | AUTH STATE (before) | CSRF | TARGET | SIDE EFFECT | SUPPORTED/LEGACY |
|---|---|---|---|---|---|
| `AuthController::loginAction()` (`?indexChooseLanguage=`) | **NONE** -- reachable pre-auth | N/A (`Snep_CsrfPlugin` never registered pre-auth) | `setup.conf` + `extensions.conf` + AMI reload | global config mutation + live dialplan reload | **REMOVED** this task -- now session-only, calls neither `setup.conf` writer nor `setExtensionsLanguage()` |
| `ParametersController::indexAction()` (full settings-form POST) | authenticated (`Snep_AuthPlugin`); authorized via `default_parameters` **read** permission only -- see AUTHORIZATION GAP below | yes (`Snep_CsrfPlugin`, POST-only) | `setup.conf` + `extensions.conf` + AMI reload | global config mutation + live dialplan reload | SUPPORTED, unchanged this task except syncing the session UI-language mirror (see CHANGES) |
| `ParametersController::languageAction()` (dedicated switcher, TASK-0026G-hardened) | authenticated; authorized via `default_parameters` **write** permission | yes (`Snep_CsrfPlugin`, POST-only) | `setup.conf` + `extensions.conf` + AMI reload | global config mutation + live dialplan reload | SUPPORTED, unchanged this task except the same session mirror |

No AGI/CLI/cron caller exists (confirmed by grep; `Snep_Locale` is also
constructed by `snep/agi/Bootstrap.php`/`Bootstrap-script.php`, but
neither calls `setExtensionsLanguage()`).

**AUTHORIZATION GAP (pre-existing, out of scope)**: `Snep_PermissionPlugin`
forces `$type = 'read'` for **any** action literally named `index`
(`PermissionPlugin.php:151`), regardless of HTTP method. Since
`ParametersController::indexAction()` both renders the settings form
*and* processes its POST save (including the language field, DB
credentials, mail settings, etc. -- not just language), a user granted
only `default_parameters_read` can currently POST through it and mutate
every field on that form, including the PBX language. `languageAction()`
does not have this gap (`write` correctly required). This is a **general
Parameters-form authorization defect, not a language-specific one** -- it
equally affects DB host/user/password, email, recording settings, and
every other field on that form. Fixing it correctly means changing how
`Snep_PermissionPlugin` classifies `index` actions that also handle a
POST (a change with much broader blast radius than this task's language-
authority scope, and not required to close TASK-0034J's D3 finding, which
was specifically about the *pre-auth* writer). **Classified
`FOLLOW_UP_DEBT`, proposed as a dedicated task** (e.g. "harden
Parameters/other index-action POST saves against read-only-permission
bypass").

## READER INVENTORY

| READER | CLASSIFICATION |
|---|---|
| `[default]` context, `Set(CHANNEL(language)=${SNEP_LANGUAGE})` on `_.` (every call) | **LIVE**, canonical authority |
| `[transferencias]` context, same `Set(...)` on `_X.` | **LIVE**, canonical authority |
| `[ramais-agentes]` context, `Set(CHANNEL(language)=br)` (hardcoded, disconnected from `${SNEP_LANGUAGE}`) | **DEAD/ORPHANED** -- see HARDCODED `br` below |
| `peers.language` / generated PJSIP `language=` (`Snep_PjsipConf.php:322`) | **LEGACY_INERT** -- see PJSIP LANGUAGE METADATA below |
| UI translation catalog (`Zend_Translate`, `Bootstrap::_initLocale()`) | **LIVE**, now resolves via `Snep_Locale::resolveUiLanguage()` (session override first, `setup.conf` fallback) |
| AGI/reports/date-picker locale helpers (`Snep_Locale::getInstance()->getLocale()`) | **LIVE**, unchanged -- these read `system.locale`, a separate field this task never touches |

## AUTHORITY MODEL (canonical decision)

| Concept | Disposition |
|---|---|
| `UI_LOCALE` | **SUPPORTED** -- session-scoped (`Snep_Locale::UI_LANGUAGE_SESSION_KEY`), resolved ahead of the persisted config on every request; never written to `setup.conf`; anyone (anonymous or authenticated) may set their own |
| `PBX_DEFAULT_CALL_LANGUAGE` | **SUPPORTED** -- `setup.conf`'s `system.language`, the single global source of truth, propagated into `extensions.conf`'s `SNEP_LANGUAGE` global by `Snep_Locale::setExtensionsLanguage()`, the one supported mechanism. Changeable only through `ParametersController::indexAction()`/`languageAction()` (authenticated, CSRF-protected) |
| `PER_EXTENSION_CALL_LANGUAGE` (`peers.language`/PJSIP `language=`) | **LEGACY_INERT** -- generated correctly but never takes effect for any call reaching `[default]`/`[transferencias]` (100% of live traffic), which unconditionally overwrite `CHANNEL(language)`. Not expanded this task (a dialplan-execution-contract change, explicitly out of scope -- see 0034J's own "open design question, not decided here") |
| `PER_CALL_LANGUAGE` | **NOT_SUPPORTED** -- no mechanism exists |

## ROOT CAUSE

Two independent, compounding defects, both closed this task:

1. **Security defect**: `AuthController::loginAction()`'s pre-auth
   language block ran before any auth/CSRF plugin could ever apply to it
   (structural, not a missed check -- see REQUEST PATH), so it was the
   *only* caller of `setExtensionsLanguage()` with zero access control of
   any kind.
2. **Independent, pre-existing reliability defect** (found live while
   reproducing #1, not previously documented): `Snep_Locale::
   setExtensionsLanguage()`'s `extensions.conf` rewrite used a
   `sed ... > file.dpkg-new; mv file.dpkg-new file` shell pattern, which
   needs *directory* write permission on `/etc/asterisk`. TASK-0009
   deliberately never grants `www-data` that (only `/etc/asterisk/snep`
   is `senma-config`-group-writable, by design -- see
   `docker/asterisk-entrypoint.sh`'s own TASK-0009 comment). The `exec()`
   call's return value/stderr were never checked, so this failed silently
   for **every caller**, authenticated or not, in every Docker topology
   this method has shipped with. Confirmed live (below): before this
   task's fix, an authenticated admin using the legitimate,
   CSRF-protected `languageAction()` switcher could change `setup.conf`
   but the change **never reached the live dialplan** -- Phase 22's
   "authorized path actually propagates" requirement could not be
   satisfied without fixing this.

## SECURITY IMPACT / CLASSIFICATION

**`SECURITY_DEFECT`** (Phase 41). Evidence, not inflated:
- Reachability: unauthenticated, a single GET (even an `<img>`/link
  click), no CSRF token needed structurally.
- Confirmed impact (live reproduction, PRE-AUTH PROOF below): mutates
  `setup.conf` (persisted, global, admin-owned config file) and triggers
  a genuine, successful Asterisk AMI `dialplan reload` (confirmed via raw
  AMI test -- "Response: Success / Message: Command output follows /
  Output: Dialplan reloaded.").
- Bounded impact: the value is allowlist-constrained to exactly
  `en`/`pt_BR`/`es` (`Snep_Locale::isSupportedLanguage()`, checked in
  both the removed caller and inside `setExtensionsLanguage()` itself) --
  no shell injection, no arbitrary file write, no arbitrary AMI command.
  This is a config-integrity/availability-adjacent defect (forced global
  language flips + forced reloads by anyone), not a code-execution or
  data-exfiltration one.
- Not `FALSE_POSITIVE`: the mutation and the reload are both real, live,
  and reproduced.
- Not `DEFENSE_IN_DEPTH`: there was no other layer catching this --
  `Snep_CsrfPlugin`/`Snep_PermissionPlugin` structurally never run
  pre-auth, by design, for every route on this codebase.

## PILOT IMPACT

`PILOT_CONSTRAINT`, not `PILOT_BLOCKER`: reachability and consequence are
real, but bounded (3-value allowlist, no injection, no data disclosure,
config-integrity/nuisance-reload class of impact, not account takeover or
data exposure). TASK-0035 (pilot soak) remains externally blocked for
unrelated reasons (no real pilot host exists) -- this task does not claim
to unblock it, only that this specific defect would otherwise have been a
legitimate constraint to carry into that pilot.

## CHANGES

`PRODUCTION`:
- `snep/lib/Snep/Locale.php`:
  - New `Snep_Locale::UI_LANGUAGE_SESSION_KEY` constant and
    `resolveUiLanguage()` (private): the UI translation language now
    prefers a session-scoped, allowlist-validated override over
    `setup.conf`'s persisted value. `locale`/`timezone` are untouched
    (narrow scope, matching the pre-existing feature's own behavior,
    which never touched those two fields either).
  - `setExtensionsLanguage()`: added a `Zend_Auth::hasIdentity()` guard
    (structural -- any future caller added without checking auth first
    now fails closed instead of reopening this defect), and replaced the
    shell `sed`/`mv` rewrite with an in-place `file_get_contents()`/
    `preg_replace()`/`file_put_contents()` sequence (only needs *file*
    write permission, not directory write -- see ROOT CAUSE #2). Now
    returns `bool` (previously `void`, failures silently swallowed).
- `snep/modules/default/controllers/AuthController.php`
  (`loginAction()`): the pre-auth `indexChooseLanguage` block no longer
  writes `setup.conf` or calls `setExtensionsLanguage()` -- it only sets
  `$_SESSION[Snep_Locale::UI_LANGUAGE_SESSION_KEY]`. Same allowlist
  check, same redirect-to-`/` behavior, same URL.
- `snep/modules/default/controllers/ParametersController.php`
  (`indexAction()`, `languageAction()`): after the existing, unchanged
  `setExtensionsLanguage()` call, also mirrors the new language into
  `$_SESSION[Snep_Locale::UI_LANGUAGE_SESSION_KEY]` -- otherwise an admin
  with an earlier session-only UI choice active would keep seeing the old
  language immediately after explicitly changing the global default.

`PLATFORM`:
- `docker/asterisk-entrypoint.sh`: new unconditional/idempotent
  `chgrp senma-config`/`chmod 664` on `extensions.conf` specifically
  (mirrors the exact pattern already used for
  `$ASTERISK_ETC/snep/*.conf`), outside the first-boot guard so an
  already-seeded dev/pilot volume self-heals on its next start.
  `/etc/asterisk` itself stays `asterisk:asterisk 0755` -- TASK-0009's
  directory-level boundary is preserved, not widened.

`TEST`:
- `scripts/preauth-security-smoke-test.sh` (already part of `make
  regression`, TASK-0026B's own harness): added `asterisk` to the
  required containers, and five new checks proving a *valid* anonymous
  language choice (a) succeeds, (b) lands in that session only, (c)
  never mutates `setup.conf`, (d) never propagates to `extensions.conf`,
  (e) never reaches the live Asterisk dialplan globals. (The pre-existing
  invalid-language check only ever covered the invalid case.)

`DOCUMENTATION`:
- This file.

Nothing else changed. `git diff --stat`: 5 files, +202/-20.

## HARDCODED `br` IN `[ramais-agentes]` (Phase 11)

Audited, **not changed**. `[ramais-agentes]` is confirmed **DEAD/
ORPHANED** dialplan by four independent lines of evidence:
1. Live `asterisk -rx "dialplan show ramais-agentes"` shows the context
   exists (registered by `pbx_config`) but nothing else in the vendored
   dialplan `Goto()`s or `#include`s into it.
2. Full-repo grep: no PJSIP endpoint config, no PHP code path, and no
   other `.conf` file ever sets `context=ramais-agentes` (`ExtensionsController.php` hardcodes `context = 'default'` for every
   extension it creates).
3. Three independent prior tasks (0008 §1, 0028/0028c, 0028y §5) already
   reached the identical conclusion at different points in time, and
   TASK-0034's own release-readiness gate already tracks this exact
   context under `POST_PILOT` for a *different* reason (its
   `PJSIP_HEADER` conversion is "unproven" for lack of a live producer).
4. This task's own `dialplan-legacy-closure-smoke-test.sh` re-run (21/21
   PASS) independently re-confirms the context's content and the absence
   of any live producer.

Since Phase 11's own condition ("if hardcoded `br` overrides canonical
authority") does not hold for any reachable call, and this exact context
already has an established `POST_PILOT` disposition from dedicated prior
tasks, changing it here would be scope creep with zero live behavior
benefit and a real (if small) chance of colliding with
`dialplan-legacy-closure-smoke-test.sh`'s own existing assertions about
this exact block. **Left as-is, tracked under the same pre-existing
`POST_PILOT` bucket, not a new debt item.**

## PJSIP LANGUAGE METADATA (Phase 12)

Audited, **not changed**. `Snep_PjsipConf.php:293/322` correctly
generates `language=<peers.language>` for every PJSIP endpoint. Confirmed
**inert** for any call reaching `[default]`/`[transferencias]` (100% of
live traffic): Asterisk applies the endpoint's `language=` at channel
creation, but the shared context's `Set(CHANNEL(language)=${SNEP_LANGUAGE})` (priority 2, before anything else) unconditionally
overwrites it on every single call, confirmed live in the DIALPLAN PROOF
call trace below (`Language: en` at `Newchannel`, flipping to the global
value by the time `SnepDial` fires). Deciding whether `peers.language`
should ever take real effect is a dialplan-execution-contract change
(0034J's own "open design question, not decided here") -- out of scope,
not expanded.

## PRE-AUTH PROOF (live, before the fix)

```
BEFORE: setup.conf language = "en" ; extensions.conf SNEP_LANGUAGE=pt_BR
GET /index.php/default/auth?indexChooseLanguage=es (no cookies, no auth) -> HTTP 302
AFTER:  setup.conf language = "es"   <- MUTATED, unauthenticated
        extensions.conf SNEP_LANGUAGE=pt_BR (unchanged only because of the
        independent ROOT CAUSE #2 permission bug, confirmed separately:
        `exec()` as www-data against /etc/asterisk -> "Permission denied")
Raw AMI test (same credentials PHP uses): Action: Command / Command:
dialplan reload -> "Response: Success ... Output: Dialplan reloaded."
  -- the reload itself DOES succeed; only the file content it reloads
  happened to be unchanged due to ROOT CAUSE #2.
```
Restored to the original `en` immediately after capturing this evidence.

## POST-FIX PROOF

`scripts/preauth-security-smoke-test.sh`, run live (15/15 PASS):
- `anonymous language choice succeeds (UI only)` -- HTTP 302.
- `anonymous choice is session-scoped, not global` -- the PHPSESSID's own
  server-side session file (`/tmp/sess_<id>`) carries
  `snep_ui_language|s:2:"es"`.
- `anonymous valid-language choice never mutates setup.conf` --
  byte-identical before/after (previously only proven for *invalid*
  values; a valid one used to legitimately mutate it).
- `anonymous valid-language choice never propagates to extensions.conf`
  -- byte-identical before/after.
- `anonymous valid-language choice never reaches the live dialplan` --
  `asterisk -rx "dialplan show globals"` byte-identical before/after.

Independent-session proof (Phase 14/25): two separate cookie jars
(`indexChooseLanguage=es` then `=en`), distinct `PHPSESSID` values
confirmed, `setup.conf`'s `language` field unchanged (`en`) throughout
both.

Invalid/malformed-input proof (Phase 17, direct unit-level test via a
PHP one-liner in the app container, bypassing HTTP entirely to rule out
any framework-level sanitization confound): `../../etc/passwd`,
`<script>`, an array, an integer, an unsupported `fr`, and an empty
string were all fed into `$_SESSION[Snep_Locale::UI_LANGUAGE_SESSION_KEY]`
directly -- every one safely fell back to the configured default (`en`),
no exception, no warning, no path-traversal effect.

## AUTHENTICATED CONFIG PROOF (Phase 22, controlled fixture)

Using the real, unmodified, CSRF-protected `POST /default/parameters/
language` path (admin session, valid `snep_csrf_token`):
```
BEFORE: setup.conf language="en" ; extensions.conf SNEP_LANGUAGE=en
POST language=es, module=parameters, snep_csrf_token=<valid> -> HTTP 302
AFTER:  setup.conf language="es"
        extensions.conf SNEP_LANGUAGE=es      <- now actually propagates
                                                  (ROOT CAUSE #2 fixed)
        asterisk -rx "dialplan show globals": SNEP_LANGUAGE=es  <- live
                                                  runtime state confirmed
```
Restored to `en` via the same authenticated path immediately after.
**Side note on the dev environment**: before this task, `setup.conf`
("en") and `extensions.conf` ("pt_BR") had drifted apart on this
long-lived dev machine specifically *because* ROOT CAUSE #2 silently
prevented every prior legitimate language change from ever reaching the
dialplan (TASK-0034J's own D3 already documented the "en"/"pt_BR"
mismatch as stale dev-volume state). Restoring "en" through the
now-fixed authenticated path also naturally re-synced `extensions.conf`
to "en" for the first time -- both files now agree, which is the correct,
intended end state, not an unintended side effect.

## DIALPLAN PROOF (Phase 24, real originated call)

With the live global set to `SNEP_LANGUAGE=es` (from the proof above), an
AMI `Originate` into `Local/90005@default` (the real `[default]`
catch-all `_.` context) was captured end-to-end via AMI events
(`Events: on`):
```
Newchannel   (channel creation, before dialplan runs): Language: en
  [dialplan priority 2 executes: Set(CHANNEL(language)=${SNEP_LANGUAGE})]
UserEvent SnepDial (priority 5, after the Set):         Language: es
Newstate / DialEnd / SoftHangupRequest (all subsequent): Language: es
```
This is real per-channel runtime state (`Language:` field on live AMI
channel events), not inferred from config file contents -- satisfying
Phase 24's explicit "do not infer solely from config" requirement.

## PROMPT AVAILABILITY (Phase 23)

Not re-audited broadly (out of scope per the task's own "do not re-open
D2 broadly unless a concrete missing prompt is found" instruction) --
this task did not add, remove, or change which languages are supported or
which prompts are called; TASK-0034J's D2 already closed the one
concrete gap that existed (English `do-not-disturb`/`activated`/
`de-activated`). No new gap was found or is implicated by this task's
changes.

## FRESH-INSTALL DEFAULT (Phase 39)

`snep/includes/setup.conf.dist` (vendored): `language = "pt_BR"`.
`snep/install/etc/asterisk/extensions.conf`'s `[globals]` (vendored):
`SNEP_LANGUAGE=pt_BR`. Both agree on a genuinely fresh install (already
independently re-confirmed by TASK-0034J's `make fresh-install-smoke`,
which never observed an `en`/`pt_BR` mismatch). This task does not change
either vendored default. Documented per current product policy: **the
deterministic fresh-install default is `pt_BR`**.

## UPGRADE COMPATIBILITY (Phase 38)

An existing `setup.conf` with an operator-configured `system.language` is
never touched by any code path in this task except through the same
authenticated, explicit `ParametersController` actions that already
existed -- `Snep_Locale::resolveUiLanguage()` only ever *adds* a
session-scoped override on top of the persisted value; it never mutates
or resets it. An upgraded install's configured language is preserved
exactly as before this task.

## TESTS

- `scripts/preauth-security-smoke-test.sh` (extended, part of `make
  regression`): 15/15 PASS, including the 5 new pre-auth hardening
  checks above (Phase 30).
- `scripts/authorization-smoke-test.sh` (pre-existing, unchanged, part of
  `make regression`): 17/17 PASS -- in particular `restricted direct F16
  action fails closed` (`GET /default/parameters/language` denied for a
  zero-permission authenticated user) already proves Phase 19/31's
  "authenticated unauthorized user cannot change global PBX language"
  boundary; no new test needed for that half of Phase 31 since it already
  existed and already passes.
- `scripts/dialplan-legacy-closure-smoke-test.sh` (pre-existing,
  unchanged): 21/21 PASS, including a full real callback call end-to-end
  -- confirms this task's changes did not disturb dialplan/PJSIP
  integrity (Phase 32/35).
- `scripts/system-status-runtime-smoke-test.sh` (Phase 36, explicitly
  required since TASK-0034I touched nearby runtime/status code): 11/11
  PASS.

## LOGIN/AUTH REGRESSION (Phase 34)

Covered by `authorization-smoke-test.sh` (17/17, includes anonymous
login, admin login, restricted-user login, restart persistence) and
`preauth-security-smoke-test.sh` (15/15, includes SQL-shaped username
rejection and admin login). No dedicated separate run needed -- both are
part of `make regression` and both ran clean above and again in both full
regression passes below.

## REMAINING DEBT

1. **`ParametersController::indexAction()`'s read-permission-gates-write
   gap** (see AUTHORIZATION GAP above) -- real, pre-existing, broader
   than language (affects every field on the settings form). Proposed as
   a dedicated future task. Not required to close TASK-0034J's D3
   finding, which was specifically about the pre-auth writer.
2. `[ramais-agentes]`'s hardcoded `br` -- confirmed dead/orphaned,
   tracked under the pre-existing `POST_PILOT` bucket (0028c), not a new
   item.
3. `peers.language`/PJSIP `language=` remains generated-but-inert --
   0034J's own open design question, not decided by this task either.

## PROPOSED COMMIT

Single thematic commit (all five files implement one coherent fix; the
test file is the regression proof for the same production change, and
the platform file is required for the production fix to actually work --
splitting further would leave intermediate states where the tests fail
or the propagation mechanism is still broken):

```
fix(security): separate UI locale from PBX call-language authority

Close the pre-auth global-mutation defect TASK-0034J (D3) found:
AuthController::loginAction()'s unauthenticated indexChooseLanguage GET
could rewrite setup.conf and force a live Asterisk dialplan reload, with
no auth/CSRF check possible by construction. It is now session-scoped
only. Also root-causes and fixes an independent, pre-existing bug found
while reproducing this live: Snep_Locale::setExtensionsLanguage()'s
extensions.conf rewrite silently failed for every caller (authenticated
included) since TASK-0009, due to a directory-permission mismatch;
switched to an in-place file rewrite plus a narrow, TASK-0009-pattern-
matching entrypoint permission grant.
```

## RECOMMENDATION

`APPROVE_WITH_CONSTRAINTS` -- see REMAINING DEBT above for the one
carried-forward constraint (the broader Parameters-form authorization gap,
not language-specific, proposed as its own task).
