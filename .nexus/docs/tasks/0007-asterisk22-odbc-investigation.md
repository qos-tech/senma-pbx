# TASK-0007 — Asterisk 22 ODBC integration investigation

## Objective
Determine exactly how SENMA/SNEP uses database integration from the
Asterisk side, what still applies to Asterisk 22, and the minimum modern
ODBC architecture required before implementation. **Investigation only —
no code, Docker, or config files were changed.** All live experiments
described below were performed against the running `asterisk` container's
volume-backed `/etc/asterisk` and reverted afterward; `git status` is
clean and `make smoke` returns 16/0/0 as of this writing.

## 1. Legacy database integration matrix

| Component | Classification | Evidence |
|---|---|---|
| `res_odbc` | **A** — required core dependency for every other ODBC module | All 5 other ODBC modules declare `res_odbc` as a direct requirement (confirmed via source, §4 below) |
| `res_config_odbc` | **A** — required for realtime `queues`/`queue_members`/`voicemail` | `extconfig.conf` maps these families through it; SENMA's own tables are actively written by the web UI |
| `func_odbc` | **D** — currently unused/dead | Stock upstream sample file only (already confirmed in TASK-0004); no SNEP-specific `[CONTEXT]` sections, no first-party dialplan references `ODBC()` |
| `cdr_odbc` | **B** — required for a real, currently-reachable feature | `cdr` table exists, schema matches Asterisk's standard CDR columns exactly, actively read by `CallsReportController`/`RankingReportController` (+ API actions) |
| `cdr_adaptive_odbc` | **E** — the recommended modern choice (see §7), not what SNEP historically used | Legacy `modules.conf` `noload`ed this one, keeping `cdr_odbc` active — re-evaluated in §7, not simply inherited |
| `cel_odbc` | **C/D** — historical, confirmed unused | **No `cel` table exists in the schema at all**; zero SENMA code references CEL anywhere |
| `res_config_mysql`, `app_mysql`, `cdr_mysql` | **C** — historical/obsolete, never built | Established in TASK-0005: enabled in the legacy menuselect list but every real shipped config already routes through ODBC; zero `MYSQL()` dialplan usage; not present in this build, not being resurrected |
| Voicemail ODBC storage | **B**, Asterisk-side portion untestable before Phase 6 | `voicemail_users`/`voicemail_messages` tables exist; `ExtensionsController`/`Snep_Extensions_Manager` already write `voicemail_users` directly via Zend_Db, independent of Asterisk. Only Asterisk's own realtime *reading* (for `app_voicemail` to process a real mailbox) needs ODBC, and that can't be exercised without a working SIP channel |
| SIP/IAX/MeetMe realtime | **C** — will be superseded, not needed now | Already commented out in the legacy `extconfig.conf`; maps to `chan_sip`, which doesn't exist in Asterisk 22; PJSIP realtime (Phase 6) uses an entirely different table family |
| `queue_log` realtime | **D from the app's perspective** | Table exists with standard columns, but zero PHP code anywhere reads or writes it |

## 2. Current Asterisk 22.10.1 module matrix

All 7 ODBC-family modules are compiled and present in the built image
(`res_odbc.so`, `res_odbc_transaction.so`, `res_config_odbc.so`,
`cdr_odbc.so`, `cdr_adaptive_odbc.so`, `cel_odbc.so`, `func_odbc.so` —
confirmed via directory listing). None of `res_config_mysql`/`app_mysql`/
`cdr_mysql` exist (never built, confirmed).

## 3. Exact load failure — corrected root cause (see full upstream investigation in §4-6)

**The original TASK-0005/early-TASK-0007 finding of a "circular
dependency bug" was wrong, and this section documents the correction.**
Manual, one-at-a-time `module load X.so` CLI commands against a running
instance reliably produced misleading errors (`"res_odbc has one or more
unknown dependencies"`, then `"undefined symbol:
ast_odbc_class_get_isolation"` when loading `res_odbc_transaction.so`
first) that look exactly like a genuine circular dependency. **They are
not.** Retested properly — a real boot with normal `autoload=yes` and
**no** `noload` entries for any ODBC module — and the loader resolves the
dependency graph correctly every time: `res_odbc_transaction.so` loads
first (successfully), `res_odbc.so` loads second. With no `res_odbc.conf`
present, `res_odbc.so` **gracefully declines** (`"Unable to load config
file res_odbc.conf"` → `"res_odbc declined to load."`) — a normal,
by-design decline, not an error — and every dependent module
(`res_config_odbc`, `cdr_odbc`, `cel_odbc`, `cdr_adaptive_odbc`,
`func_odbc`) correctly declines in turn. Providing a minimal
`res_odbc.conf` (live test, `[snep]` DSN pointing at a placeholder DSN
name) and rebooting made **`res_odbc.so`, `res_odbc_transaction.so`, and
`res_config_odbc.so` all reach `Running` status**, with no undefined
symbol error anywhere in a real boot sequence. `cdr_odbc.so`/`func_odbc.so`
correctly declined further only because their *own* dedicated config
files (`cdr_odbc.conf`/`func_odbc.conf`) weren't provided in this test —
the exact same, expected, non-buggy pattern.

**Actual root cause of TASK-0005's original observation**: `res_odbc`,
`res_config_odbc`, `cdr_odbc`, `cel_odbc` were deliberately `noload`ed in
`docker/asterisk-config/modules.conf` (a correct, intentional TASK-0005
scope decision, already documented as such) — combined with no
`res_odbc.conf` ever having been provided. There was never a genuine
module-loading defect to diagnose. What looked like a bug was an artifact
of testing methodology (manual, isolated, one-shot `module load`
commands, which do not go through the same multi-pass dependency
resolution a real boot uses).

## 4. Upstream source investigation (proving/disproving the cycle from source)

Fetched the exact tagged source for `res/res_odbc.c` and
`res/res_odbc_transaction.c` directly from `github.com/asterisk/asterisk`
across `22.9.0`, `22.10.0`, `22.10.1`, and `22.11.0-rc2` (the newest
available tag of any kind). **Identical in every version checked:**
- `res_odbc.c`'s `AST_MODULE_INFO` declares `.requires =
  "res_odbc_transaction"`.
- `res_odbc_transaction.c`'s `AST_MODULE_INFO` declares **no `.requires`
  field at all** — yet its code (`res_odbc_transaction.c:187`) calls
  `ast_odbc_class_get_isolation()`, a real, non-static function defined in
  `res_odbc.c:545` and exported by the compiled `res_odbc.so` (confirmed
  via `nm -D`, present among ~100 exported symbols).

This asymmetry (`res_odbc` formally requires `res_odbc_transaction`;
`res_odbc_transaction` informally, silently, needs a symbol from
`res_odbc` but declares no such requirement) is real, present in the
source, and identical across every 22.x version checked, including the
latest RC. It is **not** what causes module-load failures in real use,
though — see §3: it's real evidence of an *undeclared* runtime dependency
that Asterisk's actual loader-and-linker machinery evidently tolerates
correctly during normal operation (confirmed empirically, §3), which is
consistent with a general pattern search found: a prior refactor
intentionally reversed the `res_odbc`/`res_odbc_transaction` dependency
direction, and `ast_odbc_class_get_isolation` appears to be a function
the refactor didn't fully account for at the *declared-metadata* level —
while the *actual* loader mechanism (dlopen with `AST_MODFLAG_GLOBAL_SYMBOLS`,
present on both modules, plus dependency-sorted multi-pass loading) still
gets the real load order right regardless.

## 5. Would a default/upstream Asterisk 22.10.1 build exhibit this failure?

**No — not in real operation.** Explicitly re-tested per instruction: the
`res_odbc`/`res_odbc_transaction`/`res_config_odbc`/`cdr_odbc`/`cel_odbc`
`noload` lines were removed (live, uncommitted) from the running minimal
build's `modules.conf`, restoring plain `autoload=yes` for all of them —
this is functionally equivalent to how a default Asterisk build handles
these same already-compiled modules. The boot succeeded cleanly (module
resolution correct, no undefined-symbol errors); the only remaining
gating factor was the deliberate absence of `res_odbc.conf`/
`cdr_odbc.conf` (TASK-0005's minimal scope), which was then also directly
tested by supplying a placeholder `res_odbc.conf` — `res_odbc.so` reached
`Running`. This build configuration (menuselect selection, `--without-
pjproject-bundled`, the omitted DAHDI/Khomp/H323/PJSIP dependencies) has
**no bearing** on the res_odbc/res_odbc_transaction relationship — that
pair's compiled code and declared metadata are identical regardless of
what else is or isn't selected, confirmed directly against the actual
compiled `.so` files already present in this exact minimal build.

## 6. `res_odbc_transaction` necessity

`res_odbc_transaction` provides the `ODBC_Commit`/`ODBC_Rollback`
dialplan applications and the `ODBC()` transaction-isolation plumbing.
Grepped exhaustively: **zero first-party dialplan usage of ODBC
transactions anywhere in SENMA.** However, since Asterisk's loader
enforces `res_odbc`'s declared `.requires = "res_odbc_transaction"`
unconditionally, it cannot be skipped even though nothing in this
codebase uses it — and, per §3/§5, it doesn't need to be skipped: it
loads correctly and automatically as part of normal boot, at zero
practical cost (it registers two unused dialplan applications and stays
otherwise idle).

## Resolution of the original circular-dependency finding

Per your item 5's decision tree: this is squarely the "our minimal build
[or, more precisely, testing methodology] caused the apparent problem"
case, **not** a case requiring a version change, an upstream fix check,
or a source patch. There is nothing to patch and nothing to upgrade for
this specific issue — it was never a real defect. The correction needed
is purely in TASK-0005's `docker/asterisk-config/modules.conf`
(removing the ODBC `noload` lines once real config files are ready to be
provided) and in the actual `res_odbc.conf`/`cdr_odbc.conf`/etc. content
that TASK-0007's implementation will add.

## Version policy re-check (item 6)

Re-verified live against the GitHub releases API at investigation time:
`22.10.1` remains the latest non-prerelease Asterisk 22.x release;
`22.11.0` exists only as `rc1`/`rc2`. No version change is recommended or
needed — `22.10.1` stays correct, and this finding (§3-6) means there was
never a version-driven reason to consider moving off it in the first
place.

## 7. CDR backend decision — `cdr_adaptive_odbc` recommended

| Criterion | `cdr_odbc` | `cdr_adaptive_odbc` |
|---|---|---|
| Upstream support tier | **`extended`** (confirmed via live `module show`: `Support Level: extended`) | **`core`** (confirmed via live `module show`: `Support Level: core`) — Asterisk's own metadata marks this the higher-tier, actively-maintained module |
| Config complexity | Trivial: `[global]` + `dsn=`, `table=cdr` (already the default) | Slightly more: one `[context]` section (`connection=`, `table=`) in `cdr_adaptive_odbc.conf` |
| Schema flexibility | None — writes Asterisk's fixed, hardcoded standard CDR column set only | Reads the actual DB table structure; supports column aliases and arbitrary extra dialplan-set CDR variables |
| Compatibility with SENMA's existing `cdr` table | Perfect, zero-friction match today (schema is exactly the standard set) | Also a perfect match today — adaptive discovery finds the same standard columns automatically |
| Future schema evolution | None — adding a custom CDR column requires no Asterisk-side change (since `cdr_odbc` doesn't know about it) but also **can't ever use it** without switching backends later | Any custom column added to `cdr` later becomes usable immediately (dialplan `Set(CDR(newcol)=val)` + a matching column) — no backend migration needed later |
| Migration risk (today) | None | None — both are a fresh `cdr_odbc.conf`/`cdr_adaptive_odbc.conf` write, not a schema change |
| Operational note | Simpler, "just works," never needs a reload after a schema change (it doesn't look at the schema) | Needs `module reload cdr_adaptive_odbc.so` after adding/removing columns — a real but minor operational detail |

**Recommendation: `cdr_adaptive_odbc`.** Not chosen because SNEP
historically used `cdr_odbc` — the opposite: SNEP's historical choice is
explicitly not carried forward. The deciding factor is Asterisk's own
module metadata marking `cdr_adaptive_odbc` as `core` support tier versus
`cdr_odbc`'s `extended` tier, combined with zero present-day cost (the
existing `cdr` table schema already satisfies it with no changes) and
materially better future flexibility. The extra `[context]`-section
config line is a negligible complexity cost for that.

## 8. `queues`/`queue_members` realtime compatibility matrix

Column names verified directly against `apps/app_queue.c` (22.10.1
source: `queue_set_param()` for `queues`, the `ast_load_realtime_multientry`/
`ast_update_realtime` call sites for `queue_members`) — these are
long-stable, standard Asterisk queue option names, unchanged by the
Asterisk 22 migration itself.

**`queues`** (Asterisk realtime family `queues`, keyed on `name`):

| Asterisk option | SENMA column | Compatible? |
|---|---|---|
| musicclass/music/musiconhold | `musiconhold` | Yes |
| announce | `announce` | Yes |
| context | `context` | Yes |
| timeout | `timeout` | Yes |
| monitor-format | `monitor_format` | Yes |
| monitor-type | `monitor_type` | **Needs verification** — Asterisk's option name uses a hyphen (`monitor-type`); the column is `monitor_type` (underscore). SQL identifiers can't contain hyphens, so this substitution is unavoidable and was already present in the original SNEP schema — but it means realtime lookups for this specific option may not match unless Asterisk's realtime column-name handling normalizes this (not confirmed either way in this investigation; low-impact since MixMonitor is a sensible default regardless) |
| retry, wrapuptime, maxlen, ringinuse, servicelevel, strategy, joinempty, leavewhenempty, reportholdtime, weight, timeoutrestart, periodic-announce, periodic-announce-frequency, announce-frequency, announce-round-seconds, announce-holdtime, queue-* (11 announcement-text options), eventmemberstatus/eventwhencalled | matching columns present | Yes — direct 1:1 name match (case-insensitive) for every one checked |
| — | `max_call_queue`, `max_time_call`, `alert_mail` | SENMA-specific extra columns, not recognized Asterisk queue options — harmless, silently ignored by Asterisk's realtime parser, presumably used by SENMA's own PHP layer directly |
| **Required adaptation** | | **None** — schema is already realtime-compatible as-is, aside from the `monitor_type` naming nuance above (worth a one-time live verification during implementation, not a schema change) |

**`queue_members`** (Asterisk realtime family `queue_members`, keyed on
`interface`/`queue_name`, updated by `uniqueid`):

| Asterisk field | SENMA column | Compatible? |
|---|---|---|
| interface | `interface` | Yes |
| queue_name | `queue_name` | Yes |
| uniqueid | `uniqueid` | Yes |
| penalty | `penalty` | Yes |
| paused | `paused` | Yes |
| membername | `membername` | Yes |
| **Required adaptation** | | **None** |

No schema changes proposed or made, per instruction.

## Proposed minimum implementation scope (unchanged conclusion from the accepted architectural inventory, now de-risked)

```
Asterisk (res_odbc + res_odbc_transaction + res_config_odbc + cdr_adaptive_odbc)
   ↓ unixODBC (odbc-mariadb, already installed in the image)
MariaDB (db service, already network-reachable — confirmed live TCP test)
```
1. Remove the `res_odbc.so`/`res_config_odbc.so`/`cdr_odbc.so`/
   `cel_odbc.so` lines from `docker/asterisk-config/modules.conf`'s
   `noload` list (keep `cel_odbc.so` noloaded — still confirmed dead) and
   add `cdr_adaptive_odbc.so` to the noload list instead of `cdr_odbc.so`
   (swap which CDR backend is excluded, per §7).
2. Add `docker/asterisk-config/res_odbc.conf` — `[snep]` DSN pointing at
   the `db` service, real `.env`-sourced credentials (mirroring the
   existing AMI-credential templating pattern from TASK-0005).
3. Add `/etc/odbc.ini` DSN generation to `asterisk-entrypoint.sh` (the
   driver itself, `[MariaDB Unicode]`/`libmaodbc.so`, is already
   auto-registered in `/etc/odbcinst.ini` by the already-installed
   `odbc-mariadb` package — confirmed live, no packaging change needed).
4. Add `docker/asterisk-config/cdr_adaptive_odbc.conf` — one `[context]`
   mapping `connection=snep, table=cdr`.
5. Leave `extconfig.conf`'s `queues`/`queue_members`/`voicemail` realtime
   lines as-is (already correct); leave SIP/IAX/MeetMe lines commented
   out (already correct, Phase 6 concern).

## Validation plan
- `odbc show` / `module show like odbc`: `res_odbc`, `res_odbc_transaction`,
  `res_config_odbc`, `cdr_adaptive_odbc` all `Running` — necessary but not
  sufficient on its own.
- Real DSN connectivity: `asterisk -rx "odbc show all"` reporting the
  `snep` DSN connected, not just configured.
- Real realtime query: `asterisk -rx "realtime load queues name
  <an-actual-seeded-queue-name>"` (or the equivalent CLI) returning real
  row data pulled through ODBC — proves the round trip, not just that the
  module loaded.
- Controlled CDR write: exercise a path that generates a real CDR write
  (Asterisk's own CDR test/dialplan mechanism) and confirm a new row
  lands in the `cdr` table via a direct DB check — proves write-path
  correctness, not just read.
- `make smoke` must remain **16 PASS, 0 FAIL, 0 EXPECTED_LIMITATION**
  throughout.

## Explicitly deferred debt
CEL entirely (`cel_odbc` stays `noload`ed). Voicemail's Asterisk-side
realtime reading (untestable before Phase 6). `func_odbc` (confirmed
unused). All SIP/IAX/MeetMe realtime (Phase 6). `queue_log` realtime
(zero current consumer). The `monitor_type`/`monitor-type` naming nuance
(flagged, not resolved — low impact, worth a one-time live check during
implementation).

## Explicit implementation recommendation

**B — correct our Asterisk build/config configuration.** Not A (no
version change needed or justified — `22.10.1` remains correct and the
apparent defect was never version-dependent). Not C (no source patch
needed — the res_odbc/res_odbc_transaction relationship works correctly
in real boot conditions; there is nothing upstream to patch for this
issue). The actual, sufficient fix is entirely local and already
understood in detail: remove 4 lines from `docker/asterisk-config/
modules.conf`'s `noload` list, add `res_odbc.conf`, add
`cdr_adaptive_odbc.conf` (swapping out `cdr_odbc.conf` per §7), and add
DSN/`odbc.ini` generation to `asterisk-entrypoint.sh` — all straightforward
extensions of patterns TASK-0005 already established (config templating,
`.env`-sourced credentials, empty-volume-guarded first-boot generation).

---

# Implementation (recommendation B)

## Files changed

- `docker/asterisk-config/modules.conf` — removed `noload` for
  `res_odbc.so`/`res_config_odbc.so`; kept `noload` for `cdr_odbc.so`
  (already present) and `cel_odbc.so` (already present); added explicit
  `noload => func_odbc.so` (previously implicit-only, now documented
  intent). `cdr_adaptive_odbc.so` is not noloaded, so `autoload=yes`
  picks it up once `res_odbc` is available.
- `docker/asterisk-config/res_odbc.conf` (new) — `[snep]` DSN, credentials
  templated from `DB_USER`/`DB_PASSWORD` (the same env vars the app
  container's own DB connection already uses — one source of truth, not a
  second hand-copied pair).
- `docker/asterisk-config/extconfig.conf` (new) — maps only `queues` and
  `queue_members` to the `snep` ODBC connection; no other family.
- `docker/asterisk-config/cdr_adaptive_odbc.conf` (new) — one `[snep]`
  context mapping `connection=snep, table=cdr`.
- `docker/asterisk-entrypoint.sh` — added `DB_USER`/`DB_PASSWORD`
  templating for `res_odbc.conf` (same first-boot-guarded block as the
  existing AMI credential templating); added unconditional, every-start
  generation of `/etc/odbc.ini` (a system path outside the `/etc/asterisk`
  volume, carries no user-editable state, so simplest to regenerate
  deterministically from `DB_HOST`/`DB_PORT`/`DB_NAME` every start rather
  than gate behind a first-boot check). `Driver = MariaDB Unicode`
  references the driver by the name already registered in
  `/etc/odbcinst.ini` by the `odbc-mariadb` package — no
  architecture-specific path anywhere in this stack.
- `docker/asterisk.Dockerfile` — one addition:
  `touch /etc/odbc.ini && chown asterisk:asterisk /etc/odbc.ini`,
  alongside the existing ownership setup. Needed because Asterisk runs as
  the non-root `asterisk` user throughout (TASK-0005) and `/etc/odbc.ini`
  is otherwise root-owned — without this the entrypoint's regeneration
  step fails with `Permission denied` (caught during validation, fixed
  before proceeding).

## DSN configuration

`/etc/odbc.ini` (generated every start):
```
[snep]
Description = SENMA MariaDB DSN
Driver = MariaDB Unicode
Server = db
Port = 3306
Database = snep
Charset = utf8mb4
```
`/etc/odbcinst.ini` (baked into the image by the `odbc-mariadb` package,
untouched): `[MariaDB Unicode]`, `Driver=libmaodbc.so`, resolved via the
linker's own search path — never hardcoded to an architecture-specific
absolute path anywhere in this stack.

## Enabled modules (validated, current boot)
```
res_odbc.so                Running   (Use Count 3)
res_odbc_transaction.so    Running
res_config_odbc.so         Running
cdr_adaptive_odbc.so       Running
```
Exactly these 4, and only these 4 — `cdr_odbc.so`, `cel_odbc.so`,
`func_odbc.so` correctly absent (still `noload`ed).

## Realtime mapping (implemented exactly as documented in §8)
```
queues => odbc,snep,queues                  (SENMA table: queues, unmodified)
queue_members => odbc,snep,queue_members    (SENMA table: queue_members, unmodified)
```
No schema changes. No voicemail, `queue_log`, or SIP/IAX/MeetMe realtime
configured.

## CDR backend
`cdr_adaptive_odbc`, per §7's recommendation — not `cdr_odbc`, never both
active simultaneously (confirmed: `cdr_odbc.so` stays `noload`ed).

## Validation evidence

**A. Module state** — confirmed via `module show like odbc` on a clean
boot (shown above): all 4 target modules `Running`, nothing extra.

**B. DSN — real connection, not just config presence**:
```
$ asterisk -rx "odbc show all"
  Name:   snep
  DSN:    snep
    Number of active connections: 1 (out of 1)
```

**C. Realtime — real lookup proven against real MariaDB data.** Inserted
a controlled, clearly-named test row directly into `queues`
(`task0007test`) and `queue_members`, ran Asterisk's own
`realtime load` CLI command, and confirmed every returned field matched
the inserted row exactly:
```
$ asterisk -rx "realtime load queues name task0007test"
  id=1  name=task0007test  musiconhold=moh  context=from-queues
  timeout=15  maxlen=10  ringinuse=1  strategy=ringall
  (plus max_call_queue/max_time_call -- SENMA-specific extra columns,
  correctly present and simply unused by Asterisk's queue parser)

$ asterisk -rx "realtime load queue_members interface Local/1000@from-queues"
  uniqueid=1  membername=TestMember  queue_name=task0007test
  interface=Local/1000@from-queues  penalty=0  paused=0
```
Both matched the MariaDB rows exactly. Test rows deleted afterward
(`DELETE FROM queue_members/queues WHERE name/queue_name='task0007test'`) —
no test data left in the dev database. (`app_queue` itself is not loaded,
by design — it needs its own `queues.conf`, out of this task's scope;
`realtime load` exercises `res_config_odbc`/`res_odbc` directly, which is
precisely what this task validates.)

**D. CDR — validation limitation, reported honestly rather than worked
around.** Confirmed `cdr_adaptive_odbc` is genuinely registered and wired
to the real `cdr` table: `cdr_adaptive_odbc.c` logged introspecting the
table's actual columns via ODBC at load time (`Found amaflags column...`,
`Found accountcode column...`, `Found uniqueid column...`, `Found
userfield column...`), and `cdr show status` confirms:
```
  Logging: Enabled
* Registered Backends
    Adaptive ODBC
```
A full write-path test (a real row landing in `cdr` from an actual call)
could **not** be performed: this minimal Asterisk build has no
self-contained channel technology available at all. `chan_local` isn't
compiled in this image; every channel driver that *is* compiled
(`chan_iax2`, `chan_rtp`, `chan_unistim`, `chan_websocket`,
`chan_audiosocket`, `chan_bridge_media`) requires an external peer/endpoint;
no dialplan exists (`pbx_config` declines — no `extensions.conf`,
deliberately out of scope) and Asterisk 22's CLI has no dialplan-add
mechanism independent of a config file. Per instruction, **not** worked
around by adding `chan_local` to the build, writing a throwaway dialplan,
or faking a database insert from PHP/SQL to imitate a real CDR write.
Reported as an honest validation limitation: the CDR backend is correctly
configured and registered against the real schema, but an end-to-end
write proof requires a real channel, which requires either PJSIP (Phase 6)
or a build/scope change (adding `chan_local` + a minimal dialplan) that
this task was not authorized to make.

**E. Regression** — `make smoke`: **16 PASS, 0 FAIL, 0
EXPECTED_LIMITATION** (re-run after the final clean restart). Zero new
PHP Fatal Errors. Asterisk log on the current boot: zero ODBC/realtime/
CDR-related errors or warnings — only the same pre-existing,
already-documented declines from TASK-0005's minimal config (`app_queue`
needs `queues.conf`, `pbx_config` needs `extensions.conf`,
`res_stun_monitor`/`res_phoneprov`/`chan_iax2`/etc. — all unrelated to
ODBC, all unchanged from prior batches).

## Deferred debt (unchanged from the investigation, now implemented-and-confirmed-still-deferred)
CEL entirely (`cel_odbc` stays `noload`ed, no `cel` table exists).
Voicemail realtime (SENMA already writes `voicemail_users` directly via
Zend_Db; the Asterisk-side realtime read can't be exercised without a
real channel). `func_odbc` (confirmed unused, stays `noload`ed). All
SIP/IAX/MeetMe realtime (Phase 6). `queue_log` realtime (zero current
consumer). `cdr_odbc` (superseded by `cdr_adaptive_odbc`, stays
`noload`ed). A genuine CDR write-path end-to-end test (needs a channel —
Phase 6, or a separate, explicitly-scoped decision to add `chan_local` +
a minimal test dialplan). The `monitor_type`/`monitor-type` naming
nuance flagged in §8 (not re-verified during implementation; low impact).

Stopping at a commit checkpoint. Not starting the next task.
