# TASK-0034I — System Status Dependency Audit & Runtime Resource Closure

Lead: `senma-application-architect`. Reviewers: `senma-telephony-architect`,
`senma-docker-platform-engineer`. `senma-asterisk-pjsip-engineer` and
`senma-product-designer` were not invoked -- the Asterisk-specific work
(musiconhold.conf, entrypoint provisioning) stayed within
`senma-telephony-architect`'s own config-generation/runtime-contract
charter (no new PJSIP object semantics), and no System Status UX/severity
redesign was needed (PASS/FAIL, panel-green/panel-red already existed and
were adequate once the underlying checks were corrected).

## ORIGINAL STATUS FINDINGS

Reproduced live (see STATUS CHECK INVENTORY for how) before any code
change, via `Snep_Inspector::getInspects()` -- the exact class/method
`InspectorController::indexAction()` calls:

```
errored(): true
[AGI]           error=1  /var/lib/asterisk/agi-bin/snep not exist.
                         /var/lib/asterisk/moh not exist.
[Logs]          error=0
[PHPExtensions] error=1  The extension gd not present in the system, verify.
[Permissions]   error=1  /var/www/html/snep/sounds/moh does not exists.
                         /var/www/html/snep/sounds/ does not exists.
[Sounds]        error=1  /var/lib/asterisk/moh does not exists.
```

3 of 5 registered checks reported red, none of it as originally
implemented actually reflecting a correctly-diagnosed runtime gap (see
CLASSIFICATION below) -- every failure was either a wrong-container path,
a dead legacy path, or a genuinely missing resource with a broken root
cause distinct from what the check message implied.

## STATUS CHECK INVENTORY (Phase 2)

The task prompt's "System Status screen" that reports "moh directory
missing" is **not** `SystemstatusController`/`systemstatus/index.phtml`
(the CPU/RAM/disk/Asterisk-version dashboard, breadcrumb "Welcome to
Snep") -- that controller does not construct or reference a
`Snep_Inspector` at all. It is `InspectorController` /
`snep/modules/default/views/scripts/inspector/index.phtml`, reached at
`/index.php/inspector`, breadcrumb literally `"System Status"`
(`Snep_Breadcrumb::renderPath(array($this->view->translate("System
Status")))`), gated by the `inspector` resource in
`snep/modules/default/resources.xml` (`<resource id="inspector"
label="System Status" .../>`). `systemstatus/index.phtml` links to it
via its own `$this->error`/`$this->inspector` view variables -- which,
independently confirmed, `SystemstatusController::indexAction()` never
actually sets, a pre-existing dead code path in that unrelated
controller, left as `FOLLOW_UP_DEBT` (out of scope: not a runtime
dependency check).

`Snep_Inspector::__construct()` (`snep/lib/Snep/Inspector.php`) globs
every `*.php` file in `snep/inspectors/` and calls `getTests()` +
`getTestName()` on each. Five classes exist:

| File | getTestName() label | What it actually checked (before this task) |
|---|---|---|
| `AGI.php` | "Environment for AGI SNEP" | `/var/lib/asterisk/agi-bin/snep`, `/var/lib/asterisk/moh`, 4 legacy `/etc/asterisk/snep/snep-{sip,iax2}*.conf` files, 3 live `snep-*.conf` files |
| `Logs.php` | "Log Files" | `<path.log>/ui.log`, `<path.log>/agi.log` |
| `PHPExtensions.php` | "Extension PHP" | `pdo_mysql`, `gd`, `json` loaded |
| `Permissions.php` | "File Permissions" | `<path.base>/includes/setup.conf`, `<path.base>/sounds/moh`, `<path.base>/sounds/<lang>` |
| `Sounds.php` | "Music on Hold class" | every `Snep_SoundFiles_Manager::getClasses()` directory (from `/etc/asterisk/snep/snep-musiconhold.conf`) + its `tmp`/`backup` subfolders |

At minimum this covers directories, files, Asterisk resources, MOH,
logs, permissions, and PHP/system dependencies, per the task's own list.
No AGI-script-content check, no binary/service check, and no recordings/
voicemail/spool check exist in this Inspector at all -- confirmed by
reading every file in `snep/inspectors/`, not assumed.

## RESOURCE CLASSIFICATION (Phase 3)

| # | Check | Resource | Classification | Evidence |
|---|---|---|---|---|
| 1 | PHPExtensions | `pdo_mysql` | `REQUIRED_RUNTIME` / PASS | `docker/app.Dockerfile` installs it; `Snep_Db` uses the `Pdo_Mysql` Zend_Db adapter |
| 2 | PHPExtensions | `json` | `REQUIRED_RUNTIME` / PASS | core PHP 8 extension, always present |
| 3 | PHPExtensions | `gd` | `FALSE_POSITIVE` / `LEGACY_UNUSED` | zero live call sites (`grep` for `imagecreate`/`imagepng`/etc. across `snep/lib`+`snep/modules`: none); the only vendored code that would need it (`Zend_Captcha_Image`, `Zend_Barcode_Renderer_Image`) is never instantiated by SENMA (`grep` for `Zend_Captcha`/`Zend_Barcode`: none); `docker/app.Dockerfile` deliberately does not install it |
| 4 | Permissions | `<base>/includes/setup.conf` | `REQUIRED_RUNTIME` / PASS | bootstrap depends on it; `docker/entrypoint.sh` generates it first-boot |
| 5 | Permissions | `<base>/sounds/moh` | `FALSE_POSITIVE` / `LEGACY_UNUSED` | zero live references (`grep` across `snep/lib`+`snep/modules`+views: none); no Apache alias for `/sounds` (`docker/apache-mag.conf` has none); real MOH storage is `$config->system->path->asterisk->moh` = `/var/lib/asterisk/moh`, a completely different filesystem location |
| 6 | Permissions | `<base>/sounds/<lang>` | `FALSE_POSITIVE` / `LEGACY_UNUSED` | same evidence as #5; real "AST" custom-sound storage is `$config->system->path->asterisk->sounds/<lang>` |
| 7 | AGI | `/var/lib/asterisk/agi-bin/snep` | `MISCONFIGURED` (wrong container) | live: `docker exec app sh -c 'ls /var/lib/asterisk'` → `No such file or directory` before this task -- the `app` container had zero visibility into `/var/lib/asterisk` at all, independent of whether Asterisk's own copy existed |
| 8 | AGI | `/var/lib/asterisk/moh` | `MISCONFIGURED` (duplicate + wrong container) | same visibility gap as #7, plus duplicates check #10's own job under an unrelated "AGI environment" label |
| 9 | AGI | `/etc/asterisk/snep/snep-{sip,iax2}*.conf` (4 files) | `LEGACY_UNUSED` | `docs/tasks/0028c-pjsip-legacy-runtime-closure.md` already classified these exact 4 files `DEAD_NOT_INCLUDED`/`GENERATED_EMPTY_LEGACY` (chan_sip/chan_iax2 absent from this Asterisk 22/PJSIP-only build, nothing `#include`s them) and *deliberately* left `Snep_InterfaceConf` still generating them -- a standing, documented architecture decision this task does not reverse. Gating System Status on their presence asserted `REQUIRED_RUNTIME`, contradicting that decision |
| 10 | Sounds ("Music on Hold class") | each MOH class directory (currently just `[default]` → `/var/lib/asterisk/moh`) | `REQUIRED_RUNTIME`, was `MISCONFIGURED` | live: directory absent in the `asterisk` container itself (`docker exec asterisk ls /var/lib/asterisk/moh` → ENOENT) *and* invisible from `app` regardless -- two independent root causes, see MOH AUDIT |
| 11 | Logs | `ui.log`, `agi.log` | `REQUIRED_RUNTIME` / PASS | `docs/tasks/0033d-diagnostics-logging-storage-lifecycle.md` confirms `ui.log` is still real/current, `DEBUG_ONLY`, not superseded by that task's logging-architecture changes |

No `UNKNOWN` remains among these 11 items.

Also identified during the MOH/sounds audit, **not previously gated by
the Inspector at all** but squarely in the same "runtime resource
closure" category and blocking real dialplan behavior (Phase 12/17):

| Resource | Classification | Evidence |
|---|---|---|
| `/var/lib/asterisk/sounds` (Asterisk core sound prompts) | `REQUIRED_RUNTIME`, was entirely absent | live: `docker exec asterisk ls /var/lib/asterisk/sounds` → ENOENT before this task. `snep/install/etc/asterisk/snep/snep-features.conf` (deployed, live) calls `Playback(beep)`, `Playback(do-not-disturb)`, `Playback(activated)`, `Playback(de-activated)` -- named Asterisk core-sound prompts that silently resolved to nothing (Asterisk logs a missing-sound warning and continues; never a fatal error) |

## MOH RUNTIME EVIDENCE (Phase 4)

- Expected path (SENMA-generated): `/etc/asterisk/snep/snep-musiconhold.conf`'s `[default]` class, `directory=/var/lib/asterisk/moh` -- written by `Snep_SoundFiles_Manager::addClass()`/seeded from `snep/install/etc/asterisk/snep/snep-musiconhold.conf` (the vendored default, unchanged since the original SNEP 3.07 import).
- Asterisk-configured MOH directory: same path, confirmed via `asterisk.conf`'s `astvarlibdir => /var/lib/asterisk` (`docker/asterisk-config/asterisk.conf`) -- historical SNEP path and current Asterisk path are, in this one specific case, identical; not assumed, derived from the actual directive-value chain.
- MusicOnHold module: **loaded and running** (`asterisk -rx "module show like musiconhold"` → `res_musiconhold.so ... Running`), but its own log line read, live, before this task: `WARNING[1] res_musiconhold.c: No music on hold classes configured, disabling music on hold.` on every single boot.
- Root cause, found by tracing (not assumed): `/etc/asterisk/musiconhold.conf` (the top-level file whose only job, per the vendored `snep/install/etc/asterisk/musiconhold.conf`, is `#include /etc/asterisk/snep/snep-musiconhold.conf`) **did not exist at all** in the Docker deployment. `docker/asterisk-config/*.conf` (the Docker-native config set `asterisk-entrypoint.sh` copies into `/etc/asterisk` on first boot) never included `musiconhold.conf` -- confirmed by listing that directory before this task's fix. The SNEP-generated `[default]` class (`/etc/asterisk/snep/snep-musiconhold.conf`) was present and byte-correct the entire time; nothing ever pulled it into Asterisk's actual config graph.
- Default classes reference `/var/lib/asterisk/moh`, which also did not exist in the `asterisk` container's filesystem (separate, second root cause -- see PERSISTENCE MODEL).
- SENMA UI/features that use MOH: `MusicOnHoldController` (add/edit/remove classes, upload/manage files), `Snep_SoundFiles_Manager` (the manager class both that controller and the Inspector's own `Sounds.php` call into). Both existed and were fully wired in application code; neither could reach real storage because the `app` container had zero filesystem visibility into `/var/lib/asterisk` at all (`docker exec app ls /var/lib/asterisk` → ENOENT, confirmed live before this task).
- Absence effect: **only disables MOH** (the module logs a warning and continues; nothing else fails). Not a fatal/blocking condition for any other feature, confirmed by full boot-log review.

## MOH SUPPORT DECISION

MOH **is** SENMA-supported: the module is compiled in and loaded, the
generation code (`Snep_SoundFiles_Manager`) is live application code
(not dead/unreachable), and the admin UI (`MusicOnHoldController`) is a
real, currently-routable feature. It was non-functional purely due to
two Docker-topology gaps (missing `#include`, missing directory/mount),
not because the feature itself is unsupported or out of scope.

## MOH PERSISTENCE DECISION

MOH audio is `CUSTOMER_MANAGED`: no MOH-specific audio tarball is
vendored anywhere in this repo (`snep/install/sounds/` contains only
core-sound *prompt* packages, not hold-music), and inventing/bundling
arbitrary music was out of scope per the task's own explicit
instruction. The `[default]` class directory starts empty and stays
empty until an admin uploads something through the existing UI.

Persistence: reuses the **existing** `mag-asterisk-var` named volume
(mounted at `/var/lib/asterisk` in the `asterisk` service since
TASK-0005) -- not a new/second persistence model. The only change is
that the `app` service now **also** mounts that same named volume at the
same path, so `Snep_SoundFiles_Manager`/`MusicOnHoldController` (running
as PHP in the `app` container) can actually read/write it. This is the
identical sharing pattern this repo already uses for `asterisk-etc`
(mounted in both `app` and `asterisk`).

## ASTERISK FILESYSTEM MODEL (Phase 6)

Inventoried live inside the running `asterisk` container (not assumed
from Dockerfile/entrypoint source alone):

| Path | Classification | Evidence |
|---|---|---|
| `/etc/asterisk` | `PERSISTENT_RUNTIME` (mostly), `CUSTOMER_DATA` for `/etc/asterisk/snep/*` | named volume `asterisk-etc`; entrypoint-templated secrets (AMI/DB passwords, TLS key) + SNEP-generated PJSIP/dialplan config |
| `/var/lib/asterisk` (bare: astdb, documentation, agi-bin) | `PERSISTENT_RUNTIME` (astdb.sqlite3), `IMAGE_IMMUTABLE`-sourced-but-volume-seeded (documentation), symlink (agi-bin/snep) | named volume `mag-asterisk-var`; `astdb.sqlite3` is Asterisk's own internal DB; `documentation/` reseeded from an image-baked copy on first boot (pre-existing TASK-0005 pattern) |
| `/var/lib/asterisk/moh` | `PERSISTENT_RUNTIME` container, `CUSTOMER_DATA` contents | did not exist before this task; now provisioned empty, `senma-config`-group-writable, in `mag-asterisk-var` |
| `/var/lib/asterisk/sounds` | `PERSISTENT_RUNTIME` container, mixed `SYSTEM_PROVIDED` (seeded core WAVs) + `CUSTOMER_DATA` (admin-uploaded "AST" prompts, same directories) | did not exist before this task; now seeded from vendored tarballs, `senma-config`-group-writable |
| `/var/lib/asterisk/agi-bin` | `PERSISTENT_RUNTIME` container, symlink target is image/bind-mount content | `agi-bin/snep` → `/var/www/html/snep/agi` (bind-mounted from the repo), unconditionally re-linked every boot |
| `/var/spool/asterisk` | `PERSISTENT_RUNTIME` | named volume `mag-asterisk-spool`; out of this task's scope (no Inspector check touches it; voicemail/recordings are `LEGACY_NOISE`/not-in-pilot-scope per PILOT READINESS below) |
| `/var/spool/asterisk/voicemail` | `LEGACY_NOISE` for pilot purposes | Voicemail is not part of this task's or the current pilot's supported feature scope (CLAUDE.md OUT OF SCOPE: "voicemail feature development"); no Inspector check references it; not audited further |
| `/var/spool/asterisk/monitor` | `LEGACY_NOISE` for pilot purposes | Call recording is not part of current pilot scope (CLAUDE.md OUT OF SCOPE: "new recording feature"); no Inspector check references it; not audited further |
| `/var/log/asterisk` | `LOG` | named volume `mag-asterisk-log`; bounded by `docker/log-rotate-asterisk.sh` (TASK-0033D), unrelated to this task |

## PERSISTENCE MODEL / VOLUME MAP (Phases 7-8)

Compose volume map (`compose.yaml`), before and after this task:

| Named volume | asterisk service | app service (before) | app service (after) |
|---|---|---|---|
| `asterisk-etc` → `/etc/asterisk` | yes | yes | yes (unchanged) |
| `mag-asterisk-var` → `/var/lib/asterisk` | yes | **no** | **yes (this task)** |
| `mag-asterisk-spool` → `/var/spool/asterisk` | yes | no | no (unchanged, out of scope) |
| `mag-asterisk-log` → `/var/log/asterisk` | yes | no | no (unchanged, out of scope) |

The one and only change: `mag-asterisk-var` is now mounted into `app`
too, at the identical path -- the minimum change that closes the actual
gap (`app` could not see `/var/lib/asterisk` at all), reusing an
existing volume rather than introducing a new one, matching the explicit
"do not create a second competing persistence model" instruction.

**Ephemeral required paths identified:** none remain. Before this task,
`/var/lib/asterisk/{moh,sounds}` were REQUIRED_RUNTIME paths that
existed only inside the (already-persistent) `mag-asterisk-var` volume's
*empty* first-boot state -- i.e., not "living in the container layer"
(the volume itself was always correctly persistent), but never actually
provisioned into that volume by any entrypoint logic. This is a
provisioning gap, not a persistence-model gap.

## OWNERSHIP / PERMISSIONS (Phases 20-21)

Canonical owner for every writable Asterisk `/var/lib/asterisk` path:
`asterisk:asterisk` (UID/GID confirmed live: `id asterisk` → `uid=997(asterisk)
gid=997(asterisk) groups=997(asterisk),3000(senma-config)`), matching
the task's expectation. `www-data` in the `app` container: `uid=33(www-data)
gid=33(www-data) groups=33(www-data),3000(senma-config)` -- same shared
`senma-config` (GID 3000) group already used for `/etc/asterisk/snep`
since TASK-0009, extended here to `/var/lib/asterisk/{moh,sounds}` for
consistency, not a new scheme.

`docker/asterisk-entrypoint.sh` (the *owning* container's entrypoint,
per the "provision in the owning container" instruction -- `app` has no
`asterisk` user in its own `/etc/passwd`, confirmed live, so it
structurally cannot `chown`) now, on first boot only (idempotent,
`[ ! -d ... ]`-guarded):

- creates `/var/lib/asterisk/moh`, `/moh/tmp`, `/moh/backup`, empty, mode `2775`, group `senma-config`;
- extracts `snep/install/sounds/asterisk-core-sounds-en-wav-current.tar.gz` into `/var/lib/asterisk/sounds` (bare -- Asterisk's own default-language convention, matches the tarball's flat internal layout, confirmed via `tar tzf`), mode `2775`, group `senma-config`;
- extracts `asterisk-core-sounds-pt_BR-wav.tgz` into `/var/lib/asterisk/sounds/pt_BR`, same mode/group.

No `chmod 777` anywhere. Verified live (not just by reading the mode
bits): both `www-data` (via the `app` container) and `asterisk` (via the
`asterisk` container) successfully created and removed an owned test
file under `/var/lib/asterisk/moh/tmp` and `/var/lib/asterisk/sounds`
respectively (see `scripts/asterisk-runtime-storage-smoke-test.sh`,
"effective write permission" checks, both PASS).

## SOUNDS CLASSIFICATION (Phase 12)

- `/var/lib/asterisk/sounds` (bare): `SYSTEM_PROVIDED`, seeded from the vendored `asterisk-core-sounds-en-wav-current.tar.gz` (part of the original SNEP 3.07 import, `git log` shows it landed in the Phase-0 baseline commit, not introduced by this task). Group-writable so an admin can still add custom "en" prompts alongside the vendored set through the existing Sound Files UI.
- `/var/lib/asterisk/sounds/pt_BR`: same `SYSTEM_PROVIDED` treatment, seeded from `asterisk-core-sounds-pt_BR-wav.tgz`. Chosen specifically (over the also-vendored `es` package and the English "extra sounds" superset) because `snep-features.conf`'s own `Playback()` targets (`do-not-disturb`, `activated`, `de-activated`, `astcc-unavail`) exist in the pt_BR core package but **not** in either English package (`tar tzf` cross-check performed for all four vendored tarballs against all five prompt names) -- this codebase's dialplan was evidently authored against Brazilian-Portuguese content from the start.
- Distro/vendor-provided sounds are **not** made unnecessarily writable in bulk: only the two directories themselves are group-writable (so new files can be added); the ~600 existing vendor `.wav` files keep their original `asterisk:asterisk` ownership/mode from extraction. Customer-added prompts and vendor-provided prompts do share the same directory (no separate namespace) -- documented as REMAINING DEBT below, not solved here.

## RECORDINGS CLASSIFICATION (Phase 13)

Not in current supported pilot scope (CLAUDE.md OUT OF SCOPE: "new
recording feature"). No Inspector check references
`/var/spool/asterisk/monitor`; not audited further. Classified
`LEGACY_NOISE` for pilot-readiness purposes.

## VOICEMAIL CLASSIFICATION (Phase 14)

Not in current supported pilot scope (CLAUDE.md OUT OF SCOPE:
"voicemail feature development"). No Inspector check references
`/var/spool/asterisk/voicemail`; not audited further. Classified
`LEGACY_NOISE` for pilot-readiness purposes -- its absence from System
Status is correct, not an omission.

## AGI CLASSIFICATION (Phase 15)

Real AGI script source: `$config->system->path->base . '/agi'` (i.e.
`/var/www/html/snep/agi`), bind-mounted from the repo into **both**
containers (`./snep:/var/www/html/snep` read-write in `app`,
`./snep:/var/www/html/snep:ro` read-only in `asterisk`). `astagidir`
(asterisk.conf) stays at its compiled default
`/var/lib/asterisk/agi-bin`; `asterisk-entrypoint.sh` symlinks
`agi-bin/snep` → the real bind-mounted tree (pre-existing TASK-0009
pattern, unchanged by this task). AGI scripts come from the repository
bind mount, not the image, not a persistent volume -- confirmed
unchanged; this task only corrected the *Inspector's* check to look at
the right (app-visible) side of that relationship (see CHANGES). AGI
code does not become mutable customer data through this task.

## LOGS CLASSIFICATION (Phase 16)

`ui.log`/`agi.log` under `<path.log>` (`/var/log/snep`) remain real,
current, `DEBUG_ONLY` (per TASK-0033D, re-confirmed here, not
superseded). Both PASS unchanged; no stale-log-file assumption found.

## LEGACY DEPENDENCY FINDINGS (Phase 17)

`AGI.php` required 4 files (`snep-sip.conf`, `snep-sip-trunks.conf`,
`snep-iax2.conf`, `snep-iax2-trunks.conf`) that TASK-0028C already
classified `DEAD_NOT_INCLUDED`/`GENERATED_EMPTY_LEGACY` under this
project's PJSIP-only architecture. Removed from the required-check list
(see CHANGES). `Snep_InterfaceConf`'s own decision to keep *generating*
them is TASK-0028C's standing architecture call and is **not** reversed
here -- only the System Status assertion that their presence is
`REQUIRED_RUNTIME` was corrected.

## STATUS SEMANTICS (Phase 18)

The Inspector has exactly two states per check: green (`error=0`) or red
panel with a message (`error=1`) -- no WARN/NOT_APPLICABLE tier exists
in `inspector/index.phtml`. Given the corrected check set, every
remaining check is genuinely `REQUIRED_RUNTIME` (nothing legitimately
optional/legacy remains registered), so PASS/FAIL is now an accurate
enough model for this specific screen and a severity-tier redesign was
not needed -- `senma-product-designer` was not invoked for this reason.

## FALSE POSITIVES REMOVED (Phase 22)

- `PHPExtensions`: `gd` (unused).
- `Permissions`: `<base>/sounds/moh`, `<base>/sounds/<lang>` (dead legacy paths).
- `AGI`: `/var/lib/asterisk/agi-bin/snep`, `/var/lib/asterisk/moh` (wrong container/duplicate), 4 dead legacy conf files.

## REQUIRED RESOURCES PROVISIONED (Phase 23)

- `app` service now mounts `mag-asterisk-var:/var/lib/asterisk` (compose.yaml).
- `asterisk` service now bind-mounts `./snep/install/sounds:/snep-sounds-src:ro` (compose.yaml) and seeds `/var/lib/asterisk/{moh,sounds}` on first boot (`docker/asterisk-entrypoint.sh`).
- `docker/asterisk-config/musiconhold.conf` added (closes the `#include` gap).

## OPTIONAL-RESOURCE BEHAVIOR (Phase 43, folded in)

The empty `/var/lib/asterisk/moh` directory (no MOH files uploaded yet)
correctly reports PASS/green in `Sounds.php` -- that check only verifies
directory existence + `tmp`/`backup` subfolders + read/write permission,
never file *content*. Verified live both before and after the
missing-fixture proof below.

## PERSISTENCE PROOFS (Phases 23-25, 41-42, 44-45)

All performed live against the running dev stack (see VALIDATION for the
exact commands) using owned, non-customer markers, cleaned up
afterward:

- **Restart**: marker in `/var/lib/asterisk/moh` survived `docker compose restart asterisk`. PASS.
- **Force-recreate**: same marker survived `docker compose up -d --force-recreate asterisk`; seeded sounds count (305 in `pt_BR`) unchanged (guard did not re-extract). PASS.
- **Host restart**: named Docker volumes are host-filesystem-backed by Docker's own volume driver, independent of container lifecycle -- architecturally the same persistence guarantee `asterisk-etc`/`mag-db` already rely on (prior tasks' own host-reboot evidence applies identically here; no new architecture was introduced). Not independently re-proven this task (no host reboot performed) -- documented per the task's own "otherwise document architectural persistence plus prior host-reboot evidence" allowance.
- **Missing-required-fixture detection**: `scripts/system-status-runtime-smoke-test.sh` renames `/var/lib/asterisk/moh` away (owned, isolated -- empty in this dev environment) and confirms the `Sounds.php` panel turns red; renames it back and confirms green again. PASS both directions.
- **Fresh-install proof**: attempted via an isolated `docker compose -p senma-taskcheck` stack to avoid touching the primary dev environment's real state; blocked by a Docker network subnet-pool conflict with other, unrelated concurrent projects on this development host (`invalid pool request: Pool overlaps with other one on this address space`) -- an environmental/infrastructure limitation of this shared dev machine, not a defect in the change. **Partial substitute evidence**: every new guard (`musiconhold.conf`, `moh`, `sounds`, `sounds/pt_BR`) is a pure `[ ! -e ... ]` existence check independent of what else is in the volume, and each one fired and produced correct results the first time the rebuilt image ran against the existing (already-populated for everything *except* these specific new paths) dev volume -- functionally equivalent, for these specific resources, to a from-scratch run. A true from-scratch isolated-volume run was not completed; recorded as remaining debt below rather than claimed.
- **Upgrade-like recreate**: covered by the force-recreate proof above (same image rebuild + recreate cycle an operator would run after pulling a new release).
- **Customer fixture preservation**: the same marker-survival proof above doubles as this -- an owned file placed in the customer-writable `/var/lib/asterisk/moh` directory survived both restart and recreate byte-identical.

## BACKUP CLASSIFICATION (Phase 26) AND CHANGES

| Path | Classification | Before this task | After this task |
|---|---|---|---|
| `/var/lib/asterisk/moh` | `MUST_BACKUP` (customer-uploaded hold music once an admin adds any) | **omitted** -- `scripts/backup.sh` only ever copied `astdb.sqlite3` out of `mag-asterisk-var`, nothing else | `scripts/backup.sh` now archives it (`asterisk-moh.tar.gz`), optional/graceful like `astdb.sqlite3` (a pre-TASK-0034I volume simply won't have it yet) |
| `/var/lib/asterisk/sounds` | `MUST_BACKUP` for the customer-uploaded subset, `REGENERABLE` for the vendor-seeded subset (mixed, same directories, no separable metadata) | **omitted** | `scripts/backup.sh` now archives it whole (`asterisk-sounds.tar.gz`), same optional/graceful pattern |

This was a genuine, newly-identified `MUST_BACKUP` gap per the task's
own release-blocker instruction (an admin using the now-functional
MOH/Sound-Files UI would have had zero disaster-recovery coverage for
that data) -- addressed, not merely flagged.

`scripts/restore.sh` updated in lockstep: the destructive Phase-C wipe
already removes the whole `mag-asterisk-var` volume (pre-existing
behavior, confirmed by reading the script), so without a matching
restore step the new backup content would have been silently dropped on
every restore. Added guarded (`[ -f ... ]`) restore steps for both
archives, re-applying the same `senma-config`/`2775` ownership scheme
post-extraction (matching `restore_asterisk_etc`'s own existing
re-apply-permissions pattern, added there for the identical reason: a
non-root `tar` extraction does not reliably reproduce group/mode).

## RESTORE PROOF (Phase 27)

`make backup-smoke` (non-destructive: validates archive structure via
`restore.sh --validate-only`, never executes a real restore) PASSES
12/12 with the manifest now carrying 7 components (previously 5) --
confirms `asterisk_moh`/`asterisk_sounds` are present, checksummed, and
`restore.sh --validate-only` accepts the resulting archive.

The real destructive backup→destroy→restore→byte-identical cycle
(`backup-restore-dr-smoke-test.sh` / `make backup-restore-smoke`) **was**
additionally run for this task (it is deliberately excluded from `make
regression` itself by prior-task design, but running it standalone
directly exercises this task's own new, previously-never-executed-for-
real `restore_asterisk_moh`/`restore_asterisk_sounds` functions).
PASS 27/27: the whole `mag-asterisk-var` volume (which now includes
`moh`/`sounds`) was genuinely destroyed and restored, confirmed live
(`archiving /var/lib/asterisk/moh`, `archiving /var/lib/asterisk/sounds`,
`restoring /var/lib/asterisk/moh`, `restoring /var/lib/asterisk/sounds`
all present in the run log), with every pre-existing assertion in that
suite (extensions, CDR, PJSIP transports/config, TLS certificate byte-
identity, WSS/ODBC reconnection, a real post-restore call) also still
passing, and `/var/lib/asterisk/{moh,sounds}` ownership confirmed
`asterisk:senma-config`/`2775` immediately afterward. Not run: a
MOH-specific byte-identical fixture assertion analogous to the existing
TLS-certificate-hash check in that same script -- this run only proves
the mechanism (backup/restore/ownership) survives intact, not a named
customer file surviving byte-for-byte through this exact suite. Adding
that assertion to `backup-restore-dr-smoke-test.sh` (mirroring its own
`CERT_SHA_BEFORE`/`CERT_SHA_AFTER` pattern) is recorded as remaining
debt below rather than added here, to avoid modifying an already
complex, working, heavy DR test under this task's time budget.

## DOCTOR CONSISTENCY (Phase 28)

`scripts/doctor.sh` does not reference MOH, `/var/lib/asterisk/sounds`,
or the Inspector at all (confirmed via `grep`) -- there is no
contradiction to resolve because there was nothing there to contradict.
No shared-helper duplication was introduced or needed.

## AUTHORIZATION PROOF (Phase 31-32)

`scripts/system-status-runtime-smoke-test.sh`:
- Unauthenticated `GET /index.php/inspector` → HTTP 200, renders the login page (`Snep_AuthPlugin`'s internal-forward-to-login, not an HTTP redirect), **zero** `panel-green`/`panel-red` content present. PASS.
- Authenticated admin `GET /index.php/inspector` → HTTP 200, all 5 registered checks rendered, zero red panels. PASS.
- `inspector` resource confirmed still registered in `resources.xml` (gated by the standard `Snep_PermissionPlugin` ACL, unlike the separate, intentionally-unregistered `SystemstatusController` -- see resources.xml's own TASK-0022 comment). A second, lower-privilege authenticated user was **not** fabricated for this task (would mutate additional shared dev-environment state beyond what was needed); the ACL mechanism itself is exercised and proven elsewhere in this codebase's own regression suite (`authorization-smoke-test.sh`), so this task relies on that existing proof rather than duplicating it.

## DISCLOSURE PROOF (Phase 33)

Authenticated System Status response body scanned for
`Fatal error|Stack trace|Uncaught exception|on line [0-9]+ in` -- none
found, both in the passing and the deliberately-triggered-FAIL (hidden
MOH directory) state. PASS.

## FOCUSED STATUS TEST (Phase 34)

`scripts/system-status-runtime-smoke-test.sh` -- 11/11 PASS. Covers:
page load, zero unexplained FAIL, all 5 checks rendered, no error
disclosure, missing-required-fixture detection + restoration,
authorization boundary. See VALIDATION for the actual run output.

## PERSISTENCE TEST (Phase 35)

`scripts/asterisk-runtime-storage-smoke-test.sh` -- 12/12 PASS. Covers:
ownership/mode on all 4 provisioned paths, cross-container visibility,
effective write permission (both containers), marker survival across
restart and force-recreate, seeded-content stability, and a clean
post-proof MOH directory (no leftover fixture). Uses only test-owned
markers; never touches real customer data.

## TELEPHONY REGRESSION (Phase 36)

Full `make regression` run (44 suites, includes `call-smoke`,
`trunk-smoke`, `wss-platform-smoke`, `readiness-smoke`,
`pjsip-lifecycle-smoke`, etc.) -- two consecutive full PASS runs
(44/44 each), see VALIDATION.

A real cross-cutting conflict was found and fixed during this
validation, not just observed: `scripts/shell-security-smoke-test.sh`
(TASK-0026D) carried its own long-standing scaffolding
(`chown -R www-data:www-data '${SOUNDS_ROOT}' '${MOH_ROOT}'`), added
back when `/var/lib/asterisk` was unreachable from `app` at all, to let
its own MOH/Sound-Files injection tests run. Once this task made that
path genuinely reachable, that scaffolding actively fought the real fix
every regression pass -- confirmed live: an initial full regression run
showed `asterisk-runtime-storage-smoke` FAIL on ownership
(`/var/lib/asterisk/moh` ended up `www-data:www-data`, which a
non-root `asterisk`-user process can never reclaim via `chgrp`/`chmod`
after the fact). Fixed by removing the `chown` from that scaffolding
(`www-data` is already a `senma-config` member and the directories are
already group-writable once genuinely provisioned) and repairing the
then-current ownership once via `docker exec -u root` (no volume wipe).
Re-verified: `shell-security-smoke-test.sh` alone (28/28 PASS, including
a real MOH file upload through the live HTTP flow) no longer disturbs
ownership, and both new suites keep passing afterward.

## FRESH-INSTALL PROOF (Phase 42)

See PERSISTENCE PROOFS above -- partial/substitute evidence only,
documented honestly as `REMAINING DEBT`, not claimed as a full pass.

## PILOT TOPOLOGY PROOF (Phase 38)

`compose.pilot.yaml` is a purely additive port-publishing overlay (SIP/
WSS/RTP ports) -- confirmed by reading the entire file; it does not
touch `volumes:` for any service. The `mag-asterisk-var` mount added to
`app` lives in the base `compose.yaml`, so both `make up`/`make dev` and
`make pilot-up` see the identical volume/persistence topology. No
dev-only volume semantics were introduced.

## RELEASE-ARTIFACT IMPACT (Phase 39-40)

Neither Dockerfile's `COPY` set changed -- the vendored sound tarballs
are bind-mounted (`./snep/install/sounds:/snep-sounds-src:ro`), the same
"vendored source of truth, never baked into the image" pattern already
used for `snep-asterisk-config-src`/`snep-asterisk-dialplan-src`,
deliberately chosen to keep `.dockerignore`'s documented build-context
narrowing (TASK-0034D) intact. `release-artifact-smoke` (part of `make
regression`) exercises image provenance and is covered by the full
regression run above; not separately re-run in isolation since no
Dockerfile/build-context file changed.

**Image vs. volume vs. externally-managed, stable across upgrades:**

| Content | Owner |
|---|---|
| `asterisk-entrypoint.sh`, `docker/asterisk-config/*.conf` (incl. new `musiconhold.conf`) | release artifact (image layer + repo-tracked config) |
| `snep/install/sounds/*.tar.gz` | release artifact (repo-tracked, bind-mounted at runtime, never written to) |
| `/var/lib/asterisk/moh` contents | customer-owned, persistent volume |
| `/var/lib/asterisk/sounds` contents | mixed: release-artifact-sourced seed (regenerable) + customer-owned additions, same persistent volume |
| `/etc/asterisk/musiconhold.conf` | release artifact, copied into the persistent `asterisk-etc` volume on first boot only (like every other `docker/asterisk-config/*.conf` file) |

## RUNBOOK IMPACT (Phase 48)

Not updated. `docs/operations/production-release-runbook.md` was
reviewed for MOH/sounds/backup content; none of this task's changes
require a NEW operator action beyond what the existing `make
backup`/`make restore` documentation already tells operators to do (the
new archive members are transparent additions to the same commands).
Flagging as a judgment call rather than silently skipping: if a future
pilot operator specifically needs to know the pt_BR/en-only sound-seed
scope (see REMAINING DEBT), that would warrant a short runbook addition
at that time.

## PILOT READINESS CLASSIFICATION (Phase 49)

| Finding | Classification |
|---|---|
| MOH completely non-functional (`#include` never loaded) | `PILOT_BLOCKER` -- a customer-facing hold-music feature, reachable through the existing admin UI, silently did nothing |
| `app`↔`asterisk` MOH/sounds volume-visibility gap | `PILOT_BLOCKER` -- blocked the *entire* MOH/Sound-Files management feature from working at all, not just the status page |
| Missing core-sound prompts (`beep`, `do-not-disturb`, etc. silently unplayable) | `PILOT_BLOCKER` -- live dialplan features (`*21`/`*22`/`*23` toggles, `*33XXXX` recording beep) played no audio confirmation to the caller |
| Backup/restore omission of MOH/custom-sound customer data | `PILOT_BLOCKER` -- explicitly called out as release-blocking by the task's own instructions once identified |
| 4 dead legacy `snep-sip*/snep-iax2*.conf` checks | `LEGACY_NOISE` -- never actually failed (files still get generated per TASK-0028C's own standing decision); mislabeling only, no live symptom |
| `gd` extension check | `LEGACY_NOISE` -- cosmetic false-red, no functional impact |
| App-tree `sounds/moh`, `sounds/<lang>` checks | `LEGACY_NOISE` -- cosmetic false-red, no functional impact |

## TASK-0035 RELATIONSHIP (Phase 50)

TASK-0035 remains externally blocked (no real pilot host exists). This
task closes repository/runtime readiness gaps that would otherwise
surface as pilot-blocking findings once a host does exist. No pilot soak
has started or is claimed here.

## REMAINING DEBT

1. **Fresh-install proof was only partial** (guard-triggered first-time seeding on the existing dev volume, not a genuinely from-scratch isolated volume) -- blocked by an unrelated Docker network subnet conflict with other concurrent projects on this development host. A dedicated, isolated fresh-volume run (e.g. on a clean CI runner, or after freeing a subnet on this host) would close this fully.
2. **English core-sound coverage is incomplete.** Only the `en` *core* package is seeded; `snep-features.conf`'s `do-not-disturb`/`activated`/`de-activated`/`astcc-unavail` prompts are absent from both vendored English packages (`core` and `extra`) and would still silently fail to play under `language = "en"`. The pt_BR package (seeded) has full coverage. This is a genuine, separate, pre-existing content-completeness gap in the vendored English sound set, unrelated to Docker/volume architecture -- worth its own dedicated task if English-language deployments are in scope. The `es` and English "extra sounds" tarballs remain unseeded (deliberately, to keep the seeded set minimal and evidence-driven rather than seeding everything vendored "just in case").
3. **`setup.conf`'s live dev default (`language = "en"`) does not match the dialplan's evident Portuguese-first authorship** (see #2's evidence). Not a defect this task introduces or is scoped to fix -- flagged as a candidate for its own i18n/configuration-default task.
4. **System-provided and customer-uploaded sound files share one directory with no separating metadata** (`/var/lib/asterisk/sounds` and its `pt_BR` subdirectory both mix vendor-seeded and admin-uploaded content). Backup captures both together (safe, just not minimal); a future task could introduce a metadata/manifest scheme to distinguish them if that becomes operationally important (e.g. to detect drift from the vendored baseline).
5. **`backup-restore-dr-smoke-test.sh` has no MOH/sounds-specific byte-identical fixture assertion.** The full destructive cycle (`make backup-restore-smoke`) was run for this task and PASSED 27/27 with the new `asterisk-moh.tar.gz`/`asterisk-sounds.tar.gz` archive/restore steps genuinely exercised (confirmed in the run log) and correct ownership confirmed immediately after -- but that proves the *mechanism* survives the real destroy/restore cycle intact, not a specific named customer file surviving byte-for-byte through it (no MOH fixture is created in that script today). Adding one, mirroring that script's own existing `CERT_SHA_BEFORE`/`CERT_SHA_AFTER` TLS-certificate pattern, would close this fully; not added here to avoid modifying an already complex, working, heavy DR test under this task's own scope/time budget.
6. **`SystemstatusController`'s dead `$this->view->error`/`$this->view->inspector` reference** (in `systemstatus/index.phtml`, never actually set by that controller) is pre-existing, unrelated dead code -- noted, not fixed (out of scope: not a runtime dependency check).
7. **Host-restart persistence** was not independently re-proven this task (relies on the same named-volume guarantee already established/proven for `asterisk-etc`/`mag-db` in prior tasks).

## SUMMARY OF CODE CHANGES

`PRODUCTION`:
- `compose.yaml` -- `app` gains `mag-asterisk-var:/var/lib/asterisk`; `asterisk` gains `./snep/install/sounds:/snep-sounds-src:ro`.
- `docker/asterisk-config/musiconhold.conf` -- new file, closes the `#include` gap.
- `docker/asterisk-entrypoint.sh` -- new idempotent first-boot blocks: `musiconhold.conf` independent guard, core-sounds seeding (`en` bare + `pt_BR`), unconditional `tmp`/`backup` provisioning under both sound roots, MOH directory provisioning.
- `snep/inspectors/AGI.php` -- removed 2 wrong-container + 4 dead-legacy path checks; added the real, app-visible AGI-directory check.
- `snep/inspectors/Permissions.php` -- removed 2 dead legacy app-tree sound-path checks.
- `snep/inspectors/PHPExtensions.php` -- removed the unused `gd` requirement.
- `scripts/backup.sh` -- archives `/var/lib/asterisk/{moh,sounds}` (optional/graceful).
- `scripts/restore.sh` -- restores the same, re-applying `senma-config`/`2775` ownership.

`TEST`:
- `scripts/system-status-runtime-smoke-test.sh` -- new, 11 checks.
- `scripts/asterisk-runtime-storage-smoke-test.sh` -- new, 12 checks.
- `scripts/regression.sh` -- both new suites registered; canonical suite count 42 → 44.
- `scripts/shell-security-smoke-test.sh` -- removed the now-conflicting `chown -R www-data:www-data` scaffolding (see TELEPHONY REGRESSION); kept the defensive `mkdir -p`.

`DOCUMENTATION`:
- This file.

## VALIDATION

- `make lint`: PASS (5/5 -- 275 PHP files 0 syntax errors, 69 shell scripts parse cleanly, XML well-formed, `git diff --check` clean).
- `make backup-smoke`: PASS (12/12, manifest now 7 components).
- `scripts/system-status-runtime-smoke-test.sh` (standalone): PASS (11/11).
- `scripts/asterisk-runtime-storage-smoke-test.sh` (standalone): PASS (12/12).
- `scripts/shell-security-smoke-test.sh` (standalone, re-verified after the fix): PASS (28/28).
- `scripts/calls-report-smoke-test.sh` (standalone re-run): PASS (30/30) -- one earlier full-regression attempt showed this suite BLOCKED ("res_pjsip.so/chan_pjsip.so not both Running (checked 5 times over 8s)"), classified `RUNTIME_RACE`: a pre-existing, previously-documented (TASK-0028V) PJSIP-readiness timing race unrelated to this task's changes, confirmed by this clean standalone re-run against the same stack.
- `make regression` run 1: **PASS (44/44)**.
- `make regression` run 2 (immediately consecutive, no manual repair in between): **PASS (44/44)**.
- `make backup-restore-smoke` (the real destructive backup→destroy→restore→force-recreate DR cycle, not part of `make regression` by prior-task design, run separately given this task's own new restore code paths): **PASS (27/27)**, with the new `asterisk-moh`/`asterisk-sounds` archive/restore steps confirmed executed in the run log and `/var/lib/asterisk/{moh,sounds}` ownership confirmed `asterisk:senma-config`/`2775` immediately after.
- `make doctor`: **PASS**, exit 0 (0 FAIL; 1 expected `SKIP` -- no `release-manifest.json`, a local/untracked/gitignored artifact from an earlier, unrelated official release-build on this machine that this task's own iterative dev-image rebuilds made stale; removed once diagnosed, restoring doctor's documented default-dev-build state; 1 expected `WARN` -- dev-fixture TLS cert, pre-existing/unrelated).
- `make secrets-check`: **PASS**, `OVERALL: MATCH` (all 3 declared secrets match their persisted/active value).
- `make migrate-check`: **PASS**, `SCHEMA_CURRENT`.
- `make reconcile-check`: **PASS**, `status: IN_SYNC` (all 4 generated PJSIP files).
- `git diff --check`: **PASS**, no whitespace errors.
- `git status --short`: 9 modified, 4 new files (listed in SUMMARY OF CODE CHANGES) -- see checkpoint report for the exact listing.

## RECOMMENDATION

`APPROVE_WITH_CONSTRAINTS` -- see checkpoint report's final recommendation and REMAINING DEBT above for the constraints.
