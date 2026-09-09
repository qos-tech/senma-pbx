# TASK-0034J — Runtime Resource Follow-up Debt Closure

Lead: `senma-application-architect`. Reviewers: `senma-telephony-architect`
(D2/D3 language-authority evidence), `senma-docker-platform-engineer`
(D1/D4/D7 volumes/network/fresh-install evidence). `senma-asterisk-pjsip-
engineer` was not invoked -- no debt required new Asterisk-specific
implementation once root-caused (D1/D2 are Docker/entrypoint provisioning,
D5 is a test-only fixture addition, D6 is a PHP view fix). `senma-product-
designer` was not invoked -- no debt required a real UI/status-presentation
change (D6 removes unreachable dead markup with no visible effect; nothing
else touches a screen).

TASK-0034I closed the pilot-blocking runtime-resource gaps and left seven
explicitly documented follow-up debts (D1-D7). This task closes them
independently: one debt, one root cause, one decision, one evidence chain
each, per the task's own core rule.

## STARTING STATE

```
HEAD:   5d6e604 docs(tasks): document TASK-0034I runtime resource closure
branch: main
status: clean
```

## D1 — Fresh-install proof

**ORIGINAL DEBT**: TASK-0034I's own fresh-install proof was only partial
-- it attempted an isolated `docker compose -p senma-taskcheck` stack to
avoid touching the primary dev environment, and hit `invalid pool
request: Pool overlaps with other one on this address space`, documented
at the time as an environmental conflict with other unrelated concurrent
projects on the host.

**ROOT CAUSE**: re-investigated with fresh evidence, not accepted as
given. `compose.yaml` pins the `mag`/`senma-control` networks to fixed
subnets (`172.28.0.0/16`, `172.29.0.0/24` -- TASK-0005/TASK-0034F,
deliberate, not reversed here) **regardless of Compose project name**.
Any second Compose project using the same `compose.yaml`, started
concurrently with the already-running primary `mag-pbx` stack, therefore
collides with the primary stack's own already-bound subnet on the same
Docker host -- a deterministic self-collision, not a coincidental
conflict with unrelated third-party projects. This corrects TASK-0034I's
own documented root cause with live evidence (`docker network ls`/
`docker network inspect` showing the primary stack already holding both
pinned subnets at the moment any second project would request them).

**DECISION**: do not touch the primary stack's pinned subnets (a
standing, deliberate architecture decision). Instead, give the isolated
verification project its own, currently-free subnets via a dedicated,
test-only Compose override file, and fix the one other place a
Docker-project-scoped override does not reach: `env_file: .env` on the
`app`/`asterisk` services reads the literal `.env` **file**, not this
shell's exported overrides, so `ASTERISK_AMI_ACL_SUBNET` also needed an
explicit `environment:` override in the same file (Compose gives
service-level `environment:` precedence over `env_file:` for the same
key) -- discovered live while developing this proof (AMI login was
correctly rejected by manager.conf's ACL until this was added).

**CHANGES** (`PLATFORM`+`TEST`):
- `docker/compose.fresh-check-override.yaml` (new) -- overrides `mag`
  to `172.30.0.0/16`, `senma-control` to `172.31.0.0/24`, and
  `asterisk`'s `ASTERISK_AMI_ACL_SUBNET` to match.
- `scripts/fresh-install-proof-smoke-test.sh` (new) -- preflights that
  both override subnets and an isolated HTTP port are genuinely free
  (BLOCKED, not a guess, otherwise), brings up a brand-new Compose
  project (own containers/network/**brand-new named volumes**,
  concurrently with the primary stack, never stopping it), waits for
  real container health, then reuses this repo's own already-validated
  `SMOKE_COMPOSE`-parameterized suites
  (`system-status-runtime-smoke-test.sh`, `asterisk-runtime-storage-
  smoke-test.sh`, `backup-smoke-test.sh`) against the isolated stack to
  prove required runtime directories, ownership, System Status, and
  backup tooling all come up correctly from nothing. Tears the isolated
  project down completely (containers, network, volumes) on exit,
  success or failure alike.
- `Makefile` -- new `fresh-install-smoke` target (standalone, does NOT
  depend on `up`, deliberately NOT part of `make regression` --  same
  "own heavy multi-minute second-stack boot" rationale as
  `backup-restore-smoke`).

**VALIDATION**: `make fresh-install-smoke` run twice (once to find the
AMI-ACL gap above, once after fixing it) -- **PASS 8/8** both times on
the second run: isolation preflight, isolated stack created, db/asterisk/
app all healthy, System Status clean (11/11 sub-checks), MOH/sounds
provisioned+owned (12/12 sub-checks), backup tooling operational (12/12
sub-checks). Primary `mag-pbx` stack confirmed still running/healthy and
completely untouched (`docker compose ps`, `docker network ls`) after
every run.

**DISPOSITION**: `CLOSED`.

## D2 — English sound-pack coverage

**ORIGINAL DEBT**: "English core-sound coverage is incomplete" --
TASK-0034I's own text claimed `snep-features.conf`'s `do-not-disturb`/
`activated`/`de-activated`/`astcc-unavail` prompts were "absent from
both vendored English packages (core and extra)".

**ROOT CAUSE / CORRECTION**: re-verified directly against the vendored
tarballs (`tar tzf`), not assumed from the prior task's text (per this
project's evidence-hierarchy rule: never trust a documented finding
without targeted re-verification). Two errors found and corrected:
1. `astcc-unavail` is **not called by any deployed dialplan** at all
   (`grep` across every `snep/install/etc/asterisk/snep/*.conf` --
   zero `Playback(astcc-unavail)` sites exist). TASK-0034I's own
   inventory of `snep-features.conf`'s `Playback()` targets was simply
   wrong to include it; it is irrelevant to English (or Spanish)
   coverage.
2. `do-not-disturb`/`activated`/`de-activated` **are** present in the
   vendored `asterisk-extra-sounds-en-wav-current.tar.gz` package --
   just not in the smaller "core" package TASK-0034I seeded. "Absent
   from both" was wrong; they are absent from the seeded one only.

Genuine, narrower gap that remains: `beep` (used by the `*33XXXX`/`*100`
recording-beep flow) is in the seeded en-core package (PASS already);
`do-not-disturb`/`activated`/`de-activated` (used by the `*21`/`*22`/
`*23` do-not-disturb toggles) are not, and silently resolve to nothing.

**DECISION**: English is a fully first-class SENMA-supported language
(`Snep_Locale::$supportedLanguages` includes `en`; `snep/lang/en.mo`
exists with a complete UI translation catalog), so its 4 actually-called
prompts must all resolve. Seed exactly the 3 missing files from the
already-vendored, already-bind-mounted `asterisk-extra-sounds-en-wav-
current.tar.gz` -- not the whole ~1400-file/36 MB package -- matching
the task's own "no large media bundle without justification"
instruction. Spanish (`es`) is also a supported UI language but is
**not** this deployment's default/active language, and this repo vendors
no `es`-"extra" package at all (only `es`-core, which lacks the same 3
prompts) -- full Spanish prompt coverage is not achievable from vendored
content alone without sourcing new external content, which CLAUDE.md's
"do not add large media bundles without justification" and this task's
OUT-OF-SCOPE "new multilingual product feature" both rule out here.

**SOUND-PACK INVENTORY** (classified):

| Package | Files | Seeded | Classification |
|---|---|---|---|
| `asterisk-core-sounds-en-wav-current.tar.gz` | 514 | yes (bare dir) | `REQUIRED` |
| `asterisk-core-sounds-pt_BR-wav.tgz` | 505 | yes (`pt_BR/`) | `REQUIRED` (dialplan default language) |
| `asterisk-extra-sounds-en-wav-current.tar.gz` (3 members only) | 3 of 1413 | yes, this task | `REQUIRED` (closes the actual gap) |
| `asterisk-core-sounds-es-wav-current.tar.gz` | 536 | no | `OPTIONAL` (supported language, not this deployment's default; own gap can't be closed from vendored content) |
| `asterisk-extra-sounds-en-wav-current.tar.gz` (remaining 1410 files) | 1410 | no | `UNUSED` (nothing in this dialplan calls them) |

**CHANGES** (`PRODUCTION`+`DOCUMENTATION`):
- `docker/asterisk-entrypoint.sh` -- new per-file-guarded loop (retrofits
  an already-seeded volume too, not only fresh installs) extracting
  `do-not-disturb.wav`/`activated.wav`/`de-activated.wav` from the
  already-bind-mounted extra-sounds tarball; corrected header comment
  (removes the two factual errors above, documents the `es`/OPTIONAL
  decision).

**VALIDATION**:
- Retrofit against the primary dev stack's already-seeded volume: image
  rebuilt (`docker compose build asterisk`), container recreated, log
  confirms `seeding missing English prompt: {do-not-disturb,activated,
  de-activated}.wav`; files present, `asterisk:senma-config` ownership,
  mode `664`.
  - Idempotency: `docker compose restart asterisk` afterward produced
    **no** re-seed log lines.
- Fresh-install path: `make fresh-install-smoke` (D1) re-run after this
  change -- still PASS 8/8, confirming the retrofit loop behaves
  correctly on a genuinely empty volume too (runs once, right after the
  bare-`en` directory is created).

**DISPOSITION**: `CLOSED`.

## D3 — Language-default / dialplan-authorship mismatch

**ORIGINAL DEBT**: "`setup.conf`'s live dev default (`language = "en"`)
does not match the dialplan's evident Portuguese-first authorship."

**TRACED AUTHORITIES** (evidence, not assumption):
1. `snep/includes/setup.conf.dist` (vendored, tracked-in-git template):
   `language = "pt_BR"`.
2. `snep/install/etc/asterisk/extensions.conf`'s `[globals]`
   (vendored, tracked-in-git): `SNEP_LANGUAGE=pt_BR`.
3. `snep/includes/setup.conf` (this dev machine's live, **gitignored**,
   already-generated file): `language = "en"`.
4. `Snep_Locale::setExtensionsLanguage($lang)` -- the **only** code path
   that ever rewrites `extensions.conf`'s `SNEP_LANGUAGE` global (via a
   `sed` against an allowlisted 3-value set, `en`/`pt_BR`/`es`, then an
   AMI `dialplan reload`). Three call sites, all of which write
   `setup.conf`'s `system.language` immediately before/after calling it:
   `ParametersController::indexAction()` (POST, authenticated),
   `ParametersController::languageAction()` (POST+CSRF, authenticated --
   hardened by TASK-0026G specifically because it used to be a bare,
   state-changing GET), and **`AuthController::loginAction()`**
   (`?indexChooseLanguage=en|pt_BR|es`, a **pre-authentication, bare GET
   link on the public login page**, `login.phtml:36/39/42`).
5. Dialplan execution: `[default]` context's `Set(CHANNEL(language)=
   ${SNEP_LANGUAGE})` runs unconditionally on `_.` (every call), and
   `[transferencias]` does the same on `_X.`. `[ramais-agentes]`
   (line 123) instead hardcodes `Set(CHANNEL(language)=br)` -- a
   **third**, disconnected literal that never reads `${SNEP_LANGUAGE}`
   at all.
6. Per-extension override that **does** exist (corrects an assumption
   made mid-investigation): `peers.language` (`schema.sql`, `CHAR(2)
   DEFAULT 'br'`) is wired into the generated PJSIP endpoint's own
   `language=` option (TASK-0011). Its effect is moot for any call
   routed through `[default]`/`[transferencias]`, since #5's
   `Set(CHANNEL(language)=...)` unconditionally overwrites whatever the
   endpoint set, on every single call.

**ROOT CAUSE OF THE *ORIGINAL* FINDING**: **not a defect** in vendored
code. `setup.conf.dist` and `extensions.conf`'s vendored `[globals]`
already agree (`pt_BR`/`pt_BR`) on a genuinely fresh install --
independently re-confirmed by this task's own `make fresh-install-smoke`
(D1), which never observed an `en`/`pt_BR` mismatch. The `en` value
TASK-0034I observed exists **only** in this one long-lived dev machine's
own gitignored `setup.conf`, produced by legitimate prior use of the
(then only partially CSRF-hardened) language-switcher feature. Not
reset here -- it is admin-authored runtime state on a shared dev
volume, out of this task's authority to silently mutate.

**NEW FINDING (not previously documented)**: `AuthController::
loginAction()`'s pre-auth `indexChooseLanguage` GET handler is a live,
currently-reachable **third writer** of the same global authority,
reachable by *any unauthenticated visitor* via a bare link
(`login.phtml`), with no CSRF applicability (no session exists yet) and
no authorization check. A single anonymous GET request (or simply
clicking the visible login-page link) rewrites this installation's
persisted `setup.conf` **and** forces a live Asterisk `dialplan reload`
via AMI. TASK-0026G already hardened the *authenticated* in-app language
switcher (`ParametersController::languageAction()`) against exactly this
class of "state-changing GET" issue; this pre-auth sibling was missed.

**CANONICAL AUTHORITY (target rule, matching the task's own example
shape)**: `setup.conf`'s `system.language` is the single global source
of truth; `Snep_Locale::setExtensionsLanguage()` is the one supported
mechanism that propagates it into the dialplan's `SNEP_LANGUAGE` global,
invoked synchronously by every *legitimate* (authenticated) writer. No
tenant/user language model exists or is introduced. Per-extension
`peers.language`/PJSIP `language=` is generated but currently
inert for any call reaching the shared contexts -- whether that should
remain "generated but inert" or actually take effect (dialplan changed
to prefer an already-set channel language over the global) is itself an
open design question, not decided here.

**WHY NOT FIXED HERE**: closing this correctly requires either (a) a
narrow authorization/CSRF patch that would **remove** the login page's
real, working "view this page in your language before you log in"
capability (since the *only* mechanism this codebase has for that today
*is* mutating the global, bootstrap-time-read `setup.conf` -- there is
no session-scoped locale override anywhere in `Snep_Locale`/
`Bootstrap.php`), or (b) teaching the shared, every-request `Snep_Locale`
bootstrap singleton to consult a session-scoped override before falling
back to persisted config -- a change to a class every single page load
depends on, well beyond this task's narrow-fix/no-opportunistic-
refactor mandate. Separately, correctly resolving the `[ramais-
agentes]` hardcoded-`br` inconsistency and deciding whether
`peers.language` should actually take dialplan effect are `dialplan
execution` contract changes (`ARCHITECTURE_FIRST` per the routing
skill), not something `senma-application-architect` should decide
unilaterally inside a follow-up-debt-closure task.

**CHANGES**: none (documentation/evidence only).

**REMAINING DEBT** (proposed as a dedicated future task, e.g.
"TASK-0034K -- dialplan call-language authority unification and
pre-auth language-switcher hardening", lead `senma-telephony-architect`,
implementation `senma-asterisk-pjsip-engineer`, reviewer
`senma-application-architect` for the `AuthController`/session-locale
boundary):
1. Remove or narrow `AuthController::loginAction()`'s unauthenticated
   global-mutation capability without regressing the pre-auth
   language-display feature (requires session-scoped locale support).
2. Decide and implement the target dialplan rule for `peers.language`
   vs. the global `SNEP_LANGUAGE` (currently: global always wins,
   silently).
3. Fix `[ramais-agentes]`'s hardcoded `Set(CHANNEL(language)=br)` to use
   the same authority as every other context (or document why it is
   deliberately exempt, if `ramais-agentes`/agent-extensions turn out to
   be a dead/optional module -- not established either way by this
   task).

**DISPOSITION**: `SPLIT_TASK`.

## D4 — Vendor/customer sound namespace

**ORIGINAL DEBT**: "System-provided and customer-uploaded sound files
share one directory with no separating metadata."

**CURRENT NAMESPACE MODEL (traced, not assumed)**: `/var/lib/asterisk/
sounds` (bare = `en`) and its `pt_BR` subdirectory physically co-mingle
~600 vendor-seeded `.wav` files with any admin-uploaded ones. However,
the **application layer already distinguishes them correctly**:
- `Snep_SoundFiles_Manager::getSounds()` (the admin "Sound Files" list)
  queries the `sounds` DB table (`tipo='AST'`), **not** the filesystem --
  vendor-seeded files have no DB row at all, so they never appear as
  manageable customer content.
- `SoundFilesController`'s upload path (`file_exists($arq_dst)`,
  `addAction()` line ~148) explicitly rejects an upload whose filename
  already exists on disk -- an admin cannot accidentally overwrite a
  vendor-seeded prompt (e.g. `beep.wav`) via the UI; confirmed by
  reading the actual collision-check code, not inferred.
- Backup (`scripts/backup.sh`) already archives the whole directory
  (both vendor and customer content together) -- safe, just not
  minimal, exactly as TASK-0034I already documented.

**TARGET OWNERSHIP MODEL CONSIDERED**: a physical `custom/` subdirectory
Asterisk `Playback()` can address via a relative path prefix, so
customer uploads would land in `sounds/<lang>/custom/<file>` instead of
`sounds/<lang>/<file>`.

**MIGRATION/COMPATIBILITY IMPACT OF THAT MODEL**: real and non-trivial --
it would change a `dialplan execution` contract (`Playback()` targets
generated by/for admin-uploaded prompts would need a new path
convention), touch the upload/backup code paths, and require a safe,
idempotent migration of any already-uploaded admin content on existing
installs. This is exactly the kind of change the routing skill's
`ARCHITECTURE_FIRST` trigger describes (changes dialplan execution), for
a benefit that is organizational/hygiene only -- the DB-tracked listing
and collision-safe upload path already prevent the substantive risks
(accidental overwrite, admin confusion about what they can edit) today.

**DECISION**: do not migrate. The debt is real (physical co-mingling
exists) but not urgent -- no data-loss, no security, and no functional-
confusion risk currently exists given the DB-tracked collision-safe
upload path already described. A genuine physical separation is better
suited to its own dedicated, carefully-tested task after pilot, should a
concrete operational need for it emerge (e.g. wanting to diff the
vendor-seeded baseline from customer additions for drift detection --
TASK-0034I's own original framing for why this might someday matter).

**CHANGES**: none (documentation/evidence only).

**DISPOSITION**: `POST_PILOT`.

## D5 — MOH-specific DR assertion

**ORIGINAL DEBT**: `backup-restore-dr-smoke-test.sh` proved the backup/
restore *mechanism* moves `/var/lib/asterisk/moh` (confirmed in its own
run log) but never asserted a **specific named file** survives
byte-for-byte through the real destructive cycle, unlike its own
existing `CERT_SHA_BEFORE`/`CERT_SHA_AFTER` TLS-certificate pattern.

**FIXTURE STRATEGY**: mirrors the existing TLS-certificate proof exactly.
An owned marker file (`${FIXTURE_MARKER}-moh.raw`, reusing this script's
own existing `task0033a-dr-fixture` naming convention) is written into
`/var/lib/asterisk/moh` immediately before backup (alongside
`CERT_SHA_BEFORE`), its sha256 captured, a best-effort cleanup
registered, then verified byte-identical (sha256) and correctly owned
(`asterisk:senma-config`) immediately after the real destroy-and-restore
cycle (alongside `CERT_SHA_AFTER`). Never touches real customer audio --
this dedicated fixture is the only file involved.

**CHANGES** (`TEST`):
- `scripts/backup-restore-dr-smoke-test.sh` -- fixture creation +
  `MOH_SHA_BEFORE` capture (before backup), `MOH_SHA_AFTER` + ownership
  verification (after restore). Purely additive to the existing DR
  suite, per the task's own "prefer adding to existing DR coverage
  rather than duplicating the full backup suite" instruction.

**BACKUP PROOF**: `MOH customer fixture created` -- PASS (fixture
written, sha256 captured before the real backup ran).

**RESTORE PROOF**: full destructive cycle (`make backup-restore-smoke`)
run for real -- fixture survived the actual `docker volume rm` of
`mag-asterisk-var` + restore, sha256 byte-identical, ownership
`asterisk:senma-config` confirmed. Every pre-existing assertion in the
same suite (extensions, CDR, PJSIP config, TLS cert, WSS/ODBC
reconnection, two real calls, `--force-recreate` survival) also still
passed.

**VALIDATION**: `make backup-restore-smoke` -- **PASS 30/30** (up from
TASK-0034I's 27/27; +3 checks: fixture created, fixture restored
byte-identical, fixture ownership correct).

**DISPOSITION**: `CLOSED`.

## D6 — SystemstatusController dead code

**ORIGINAL DEBT**: `systemstatus/index.phtml` references
`$this->error`/`$this->inspector`, which `SystemstatusController::
indexAction()` never sets.

**REACHABILITY EVIDENCE (not grep-absence alone, per the task's own
instruction)**:
- **Routes**: `default_systemstatus` is explicitly whitelisted (open to
  all authenticated users) in `snep/modules/default/model/
  PermissionPlugin.php`; `resources.xml` gates only the destructive
  `restart-dispatch` sub-action, not `index`.
- **References**: `restartDispatchAction()`/`restartStatusAction()`
  implement real, currently-used graceful/immediate Asterisk restart
  functionality (CSRF-protected, TASK-0022-authorized) -- this is a
  live, non-trivial controller, not an abandoned stub.
  `statusbar_info()` renders real AMI-derived Asterisk version/CPU/
  memory/disk data (fixed for real in TASK-0006A/0006B, which explicitly
  root-caused and closed a prior 500 error and an AMI response-format
  incompatibility here).
- **Tests**: `scripts/smoke-test.sh`'s own `systemstatus` check
  (`GET /index.php/default/systemstatus`, asserting the live
  AMI-derived Asterisk version string) is part of `make smoke` and
  passed both before and after this task's change.
- **Runtime access**: `make smoke` exercised the real, authenticated
  flow against the live dev stack (see VALIDATION).

Conclusion: `SystemstatusController` overall is `LIVE_SUPPORTED`, not
dead. Only the narrow `$this->error`/`$this->inspector` conditional
block in the view is genuinely dead -- the view vars are never set by
any code path (confirmed: `grep` for `view->error`/`view->inspector`
assignment anywhere in `SystemstatusController.php` -- zero hits), so
the block was always inert (Zend's view `__get` returns `null` for an
unset var, the `if` never renders).

**REMOVAL/RETENTION DECISION**: remove only the dead 9-line conditional
block; retain the controller/action/every other line of the view
unchanged.

**CHANGES** (`PRODUCTION`):
- `snep/modules/default/views/scripts/systemstatus/index.phtml` --
  removed the unreachable `<?php if ($this->error) : ?> ... <?php endif
  ?>` block (lines 66-74).

**VALIDATION**: `php -l` clean; `make smoke` re-run after the change --
`systemstatus` flow still **PASS** (`HTTP 200, marker 'Asterisk -
22.11.0' found`), 15/15 flows PASS, 0 new PHP Fatal Errors.

**DISPOSITION**: `CLOSED`.

## D7 — Fresh host-restart persistence proof

**ORIGINAL DEBT**: host-restart persistence was not independently
re-proven in TASK-0034I (relied on the same named-volume guarantee
already established for `asterisk-etc`/`mag-db` in prior tasks).

**DECISION**: a genuine host reboot of the machine this session runs on
is out of this session's safe operating boundary -- it would terminate
every other process on the operator's machine (including this very
session, mid-task, with no way to resume and verify the outcome), for a
guarantee (`named Docker volumes are backed by the host filesystem,
independent of container lifecycle`) that is a property of Docker's own
volume driver, not of anything this task's changes could plausibly
break. The task's own instructions explicitly anticipate this
(`"If host restart is not safe/possible in current environment:
BLOCKED_EXTERNAL... Do not simulate host reboot with container restart
and call it equivalent"`) -- no container-restart substitute is claimed
here as equivalent.

**RETAINED ARCHITECTURE-LEVEL EVIDENCE**:
- The exact same named-volume mechanism (`mag-asterisk-var`,
  `asterisk-etc`, `mag-db`) already carries prior tasks' own host-reboot
  evidence (referenced, not re-derived, in TASK-0034I).
- This task's own `docker compose restart asterisk` and
  `docker compose up -d --force-recreate` proofs (D1's `make
  fresh-install-smoke`, D5's `make backup-restore-smoke`) additionally
  reconfirm container-lifecycle-independent persistence for the MOH/
  sounds paths specifically, which is the closest in-session evidence
  available without an actual reboot.

**IF THE OPERATOR WANTS THIS CLOSED FOR REAL**: create an owned fixture
under `/var/lib/asterisk/moh`, restart the host machine, confirm the
fixture/ownership/System-Status state after Docker Desktop reconverges,
then clean up -- this is a manual, operator-initiated action this
session will not perform or request permission to perform
autonomously.

**DISPOSITION**: `BLOCKED_EXTERNAL`.

## CROSS-CHECKS

**Persistence ownership** (post all changes): `asterisk-runtime-storage-
smoke-test.sh` (12/12, run standalone against the primary stack and
again inside `make fresh-install-smoke`) confirms `asterisk:senma-
config`/`2775` on every provisioned directory, cross-container
visibility (`app`+`asterisk`), and effective write permission from both
`www-data` and `asterisk`. `make backup-restore-smoke`'s own post-
restore check additionally reconfirms this after a real volume
destroy/recreate cycle.

**System Status**: `scripts/system-status-runtime-smoke-test.sh`
(11/11) against the live primary stack after every change in this task
-- all 5 registered checks green, no unexplained red, no error
disclosure.

**Doctor / secrets / migrate / reconcile / telephony / release-artifact
/ regression**: see CANONICAL VALIDATION below.

**Pilot impact**: TASK-0035 remains externally blocked (no real pilot
host exists). This task does not claim any pilot soak has started or
that D3/D4's follow-up work is required before the *next* pilot step --
D1/D2/D5/D6 close cleanly now; D3/D4 are recorded as real, non-blocking
debt for a dedicated future task/window respectively.

## CANONICAL VALIDATION

- `make lint`: **PASS** (5/5 -- 275 PHP files 0 syntax errors, 70 shell
  scripts parse cleanly [69 -> 70, the new `fresh-install-proof-smoke-
  test.sh`], XML well-formed, `git diff --check` clean).
- `make regression` run 1: **PASS (44/44)** -- unchanged suite count
  from TASK-0034I (D1/D5's new/extended scripts are standalone, not
  registered in `scripts/regression.sh`, matching `backup-restore-dr-
  smoke-test.sh`'s own existing precedent).
- `make regression` run 2 (immediately consecutive, no manual repair in
  between): **PASS (44/44)**, identical suite list.
- `make doctor`: **PASS**, exit 0, 0 FAIL. 1 expected `SKIP` (no
  `release-manifest.json` -- dev build, same as TASK-0034I). 2 `WARN`:
  Asterisk `full` log at the 100 MiB rotation threshold (expected --
  this task's own two full regression runs plus a real destructive
  backup/restore cycle generated substantially more log volume than a
  quiet day; `docker/log-rotate-asterisk.sh` rotates it on its next
  cycle, unrelated to this task's changes) and the pre-existing dev-
  fixture TLS certificate warning (unrelated, pre-existing per
  TASK-0028Z/TASK-0034H). No new unexplained FAIL/WARN.
- `make secrets-check`: **PASS**, `OVERALL: MATCH` (all 3 declared
  secrets match their persisted/active value).
- `make migrate-check`: **PASS**, `SCHEMA_CURRENT`.
- `make reconcile-check`: **PASS**, `status: IN_SYNC` (all 4 generated
  PJSIP files).
- `git diff --check`: **PASS**, no whitespace errors.
- `git status --short`: 4 modified, 3 new files -- see SUMMARY OF CODE
  CHANGES below; matches exactly what this task touched, nothing else.
- Telephony cross-check: `call-smoke`, `trunk-smoke`, `wss-platform-
  smoke`, `readiness-smoke` all **PASS** within both regression runs
  above (D2 changed sound content; no dialplan/PJSIP/runtime-contract
  change was made, so no additional standalone run was needed).
- Release-artifact cross-check: `docker/asterisk-entrypoint.sh` is
  `COPY`'d into the `asterisk` image (D2's change), so this **is** an
  image-content change -- `release-artifact-smoke` (part of `make
  regression`) ran and **PASSED** in both runs above; not separately
  re-run in isolation since it is already exercised on every
  regression pass, unaffected by this task's use of the term "NOT_
  REQUIRED" (which does not apply here: image content did change).
- System Status cross-check: `scripts/system-status-runtime-smoke-
  test.sh` standalone -- **PASS 11/11** against the live primary stack,
  post every change in this task (5/5 panels green, no error
  disclosure).
- Persistence-ownership cross-check: `scripts/asterisk-runtime-storage-
  smoke-test.sh` standalone -- **PASS 12/12**.
- `make backup-restore-smoke` (D5's real destructive DR cycle, run
  standalone per its own by-design exclusion from `make regression`):
  **PASS 30/30**.
- `make fresh-install-smoke` (D1's new isolated proof): **PASS 8/8**,
  run twice during development (once to find the AMI-ACL override gap,
  once clean after fixing it).

## SUMMARY OF CODE CHANGES

`PRODUCTION`:
- `docker/asterisk-entrypoint.sh` -- D2: retrofit-safe seeding of 3
  missing English prompts from the already-vendored/bind-mounted
  extra-sounds package; corrected header comment.
- `snep/modules/default/views/scripts/systemstatus/index.phtml` -- D6:
  removed the unreachable `$this->error`/`$this->inspector` dead block.

`PLATFORM`:
- `docker/compose.fresh-check-override.yaml` -- new, D1's isolated
  fresh-install verification network/env overrides.
- `Makefile` -- new `fresh-install-smoke` target.

`TEST`:
- `scripts/fresh-install-proof-smoke-test.sh` -- new, D1.
- `scripts/backup-restore-dr-smoke-test.sh` -- D5's additive MOH
  fixture assertion.

`DOCUMENTATION`:
- This file.

## REMAINING DEBT (honest accounting)

- D3 (dialplan call-language authority unification, including the live
  pre-auth `AuthController` global-mutation finding) -- `SPLIT_TASK`,
  proposed as a dedicated future task.
- D4 (physical vendor/customer sound namespace separation) --
  `POST_PILOT`, revisit if a concrete operational need emerges.
- D7 (genuine host-restart persistence proof) -- `BLOCKED_EXTERNAL`,
  requires a manual, operator-initiated host reboot this session will
  not perform autonomously.

Nothing above was hidden: all three are called out by name, with
evidence, in their own sections above.

## PILOT IMPACT

TASK-0035 remains externally blocked (no real pilot host exists). This
task does not claim any pilot soak has started.

## RECOMMENDATION

`APPROVE_WITH_CONSTRAINTS` -- see checkpoint report's final
recommendation and REMAINING DEBT above for the constraints.
