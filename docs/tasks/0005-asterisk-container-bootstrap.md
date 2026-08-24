# TASK-0005 — Asterisk container bootstrap

## Objective

Introduce the minimum viable Asterisk 22 runtime into the Docker topology.
This task is **not** about making SENMA a functional PBX — it is about
establishing and validating the SENMA ↔ Asterisk runtime boundary: AMI
reachability and shared `/etc/asterisk/snep` configuration visibility.

## Scope

Explicitly excluded from this task (deferred to later phases/tasks):
PJSIP endpoints, trunks, SIP registrations, RTP, call routing, AGI
runtime, voicemail runtime, CDR/CEL persistence, conference runtime,
physical hardware drivers (Khomp/DAHDI/H.323/OSS), full ODBC integration.

## Investigation summary (pre-implementation)

Audited the historical `InstallSnepDebian10.sh` (from `qos-tech/snep_307`)
against the current tree. Full findings were reported separately before
implementation began; key conclusions carried into this implementation:

- Every realtime/CDR/CEL/voicemail config the legacy installer shipped
  already routes through ODBC (`res_odbc`, `res_config_odbc`, `cdr_odbc`,
  `cel_odbc`), not the direct-MySQL modules (`res_config_mysql`,
  `app_mysql`, `cdr_mysql`) its own menuselect list also enabled —
  confirmed those were never actually load-bearing (zero `MYSQL()`
  dialplan usage anywhere in first-party code).
- `ConferenceRoomsController.php` generates `ConfBridge(${EXTEN})`
  dialplan, not `MeetMe(...)` — `app_meetme` was already unused.
- `chan_sip` is fully removed from Asterisk as of version 21 (verified
  directly against asterisk.org) — does not exist in Asterisk 22 at all.
  Not fixable within this task's scope; real call/registration flows stay
  impossible until the PJSIP milestone (CLAUDE.md Phase 6), regardless of
  this task.
- Neither `queues` nor `systemstatus` (this task's two target flows)
  actually needs SIP, ODBC, or CDR — `queues`'s failure was a missing
  static file (`snep-musiconhold.conf`, read directly by PHP via
  `Zend_Config_Ini`, never through Asterisk); `systemstatus`'s AMI-driven
  portion only needs a reachable, authenticating AMI connection.

## A. Asterisk version and build strategy

**Version: Asterisk 22.10.1.** Verified directly against the GitHub
releases API (`api.github.com/repos/asterisk/asterisk/releases`) rather
than assumed: `22.10.1` (published 2026-06-25) is the latest
non-prerelease Asterisk 22.x tag; `22.11.0-rc1`/`rc2` exist only as
release candidates. The "Asterisk Certified" LTS track
(`certified-22.8-cert4`) was considered and not chosen — CLAUDE.md's
"Asterisk 22 LTS" target maps most directly to the regular LTS release
train, not the more conservative certified variant.

**Build strategy: compiled from source.** Confirmed empirically —
`apt-cache madison asterisk` against Debian 13 (trixie)'s official repos
returns nothing; Debian ships no `asterisk` package at all for this
release. This matches CLAUDE.md's guidance #8 ("if Asterisk must be
compiled, isolate the build in Docker and pin the exact version") and is
not a choice made for its own sake.

`docker/asterisk.Dockerfile` is a two-stage build: a `build` stage
(`debian:13-slim` + build toolchain) compiles Asterisk from the official
source tarball
(`https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-22.10.1.tar.gz`,
verified reachable), and a slim runtime stage copies out only the
compiled binary, modules, the two runtime shared libraries Asterisk
itself produces (`libasteriskssl.so*` — the only ones found under
`/usr/lib`, verified via `find`), and the XML documentation tree (see
"Boot blockers discovered" below).

## B. Minimal module set

No PJSIP, DAHDI, Khomp, H.323, or OSS support exists in this build at
all — not merely disabled. Their dependency libraries
(`pjproject`/`libpri`/`libss7`/proprietary Khomp SDK/H.323 stack/OSS
headers) are never installed in the build stage, so Asterisk's own
`./configure`/`menuselect` dependency detection excludes those modules
automatically — confirmed via `menuselect/menuselect --check-deps`
output and by inspecting the built `/usr/lib/asterisk/modules` directory
directly (no `chan_pjsip.so`, `chan_dahdi.so`, etc. present).
`--without-pjproject-bundled` additionally prevents Asterisk's own
configure step from silently building its bundled pjproject copy, which
would otherwise pull PJSIP in regardless. `docker/asterisk-config/modules.conf`
also carries explicit `noload` lines for these (and for `res_odbc`/
`res_config_odbc`/`cdr_odbc`/`cel_odbc` — see §E) as a second, explicit
gate, and to fail loudly rather than silently if a future image change
ever makes them buildable by accident.

Everything else Asterisk's default `autoload=yes` selects still gets
built and loaded (272 modules loaded on a clean boot) — this task did
not attempt to hand-curate a minimal allowlist beyond the explicit
excludes above, since the reduced-scope config files (§D) mean most of
those modules simply decline to load anyway (see "Boot blockers
discovered").

## C. Non-root user

Asterisk runs as a dedicated `asterisk:asterisk` system user (created in
the runtime image, `USER asterisk` in the Dockerfile), **not** root. The
legacy installer left `asterisk.conf`'s `runuser`/`rungroup` commented
out, meaning Asterisk ran as root — that default was not replicated; no
blocker was encountered that required it. `/etc/asterisk`,
`/var/lib/asterisk`, `/var/spool/asterisk`, `/var/log/asterisk`,
`/var/run/asterisk` are all owned by `asterisk:asterisk`.

## D. AMI design

No PHP code changes were needed — `PBX_Asterisk_AMI`/`Asterisk_AMI`
already read `ip_sock`/`user_sock`/`pass_sock` from `setup.conf`'s
`[ambiente]` section and default to port 5038 when unset. This was
purely a config-templating problem:

- `docker/asterisk-entrypoint.sh` templates `manager.conf`'s `[snep]`
  section (username/secret) from `AMI_USER`/`AMI_PASSWORD` env vars on
  first boot (empty-volume guard, same idempotent pattern as the app
  container's existing `setup.conf.dist` → `setup.conf` generation).
- `docker/entrypoint.sh` (app container) was extended with the same
  `sed` pattern to template `setup.conf`'s `ip_sock`/`user_sock`/
  `pass_sock` from `ASTERISK_HOST`/`AMI_USER`/`AMI_PASSWORD` — the same
  env vars, so both sides are guaranteed to agree without hand-copying a
  credential into two places.
- AMI (5038/tcp) is **not** published to the Docker host — no `ports:`
  entry for it in `compose.yaml`'s `asterisk` service, container-to-
  container only, per instruction.

## E. Network / ACL design

The legacy `manager.conf` hardcoded `permit=172.17.0.0/255.255.0.0`
(Docker's *default* bridge subnet) with no evidence it was ever verified
against a real deployment. Checked directly against this project's own
`mag` network: an unpinned network on this host came up as
`172.18.0.0/16`, not `172.17.0.0/16` — confirming the legacy value would
have been wrong to reuse. Rather than hardcode whatever subnet happened
to auto-allocate (non-deterministic across hosts/rebuilds), the `mag`
network is now explicitly pinned in `compose.yaml`:
```yaml
networks:
  mag:
    ipam:
      config:
        - subnet: 172.28.0.0/16
```
and `manager.conf`'s ACL (`ASTERISK_AMI_ACL_SUBNET` env var, default
`172.28.0.0/16` in `.env.example`) is templated to match exactly.

## D. Shared Asterisk configuration

`/etc/asterisk` is a named Docker volume (`asterisk-etc`): read-write in
the `asterisk` service, read-only in `app`. It starts empty and is
populated once, on first boot, by `asterisk-entrypoint.sh` from two
bind-mounted, read-only sources — never from a second hand-maintained
copy:
1. `docker/asterisk-config/*.conf` (`asterisk.conf`, `manager.conf`,
   `modules.conf`, `logger.conf`) — the 4 small, genuinely Docker-native
   files, each adapted from and documented against its
   `snep/install/etc/asterisk/` legacy counterpart (see the header
   comment in each file for the exact diff and reasoning).
2. `snep/install/etc/asterisk/snep/*.conf` (9 files: `snep-musiconhold.conf`
   and its 8 siblings) — copied **verbatim, unmodified**, straight from
   the same vendored source of truth the PHP app itself is built from.
   No adaptation needed; these are pure data files with no host-specific
   values.

This satisfies both "use `snep/install/etc/asterisk` as the historical
source" and "do not create a second drifting copy": the 35 legacy config
files this task doesn't need (`queues.conf`, `voicemail.conf`,
`chan_dahdi.conf`, etc.) are neither duplicated nor referenced at all
yet — real TASK-0006+ work, not speculative inclusion here.

Confirmed both directions of the shared-visibility requirement:
`docker compose exec app cat /etc/asterisk/snep/snep-musiconhold.conf`
returns the real, vendored content; `docker compose exec asterisk ls
/etc/asterisk/snep/` shows the same 9 files the app reads.

## E. ODBC investigation

Per instruction, ODBC was **not** made a completion requirement, and was
investigated rather than assumed. Findings:

- Neither target flow (`queues`, `systemstatus`) touches ODBC at all
  (see "Investigation summary" above) — so it was excluded from
  `modules.conf` by default (`noload => res_odbc.so` /
  `res_config_odbc.so` / `cdr_odbc.so` / `cel_odbc.so`), not attempted.
- Tested directly whether this would have blocked boot anyway (in case a
  future task re-enables it without re-deriving this): temporarily added
  `preload => res_odbc.so` / `res_config_odbc.so` to a live container and
  attempted `module load`. Result: **both modules fail to load**
  ("`res_odbc has one or more unknown dependencies`" /
  "`res_config_odbc loaded before dependency res_odbc!`" in
  `/var/log/asterisk/full`) — a real, unresolved dependency issue in this
  minimal build, not merely a missing-DSN warning. Critically, **this
  does not crash or destabilize Asterisk** — confirmed via `asterisk -rx
  "core show version"` responding normally immediately after the failed
  load attempts. The live test change was reverted afterward.
- Root cause of the dependency failure was not further diagnosed — out
  of this task's completion requirement per instruction E, since it
  doesn't block either target flow or Asterisk's own stability. Flagged
  as the starting point for TASK-0006 (full ODBC integration), which
  will need to resolve this before `res_odbc`/`res_config_odbc`/
  `cdr_odbc`/`cel_odbc` can actually be used.

## F. Existing legacy configuration — deliberately not restored

`res_config_mysql`, `app_mysql`, `cdr_mysql`, `app_meetme`: never
installed, never built (see "Investigation summary"). `chan_sip`: cannot
exist in Asterisk 22 (see above). PJSIP: not enabled (see §B).
Khomp/DAHDI/H.323/OSS: not built, and confirmed non-blocking — Asterisk
boots and reaches "Ready" state regardless of their absence.

## G. Health check

`compose.yaml`'s `asterisk` service healthcheck:
```yaml
test: ["CMD", "asterisk", "-rx", "core show version"]
```
— genuine CLI responsiveness over the Asterisk remote-console UNIX
socket, not a process-existence or port-open check. Both `asterisk` and
`app` `depends_on: condition: service_healthy` on it, so the app
container won't start until Asterisk is genuinely responsive.
`make doctor` was extended to report `asterisk: CLI responsive.` when the
stack is already up (best-effort; doesn't fail doctor if the stack isn't
up yet, since doctor also runs pre-`up`). `make ps` surfaces the health
status automatically via `docker compose ps`'s own STATUS column — no
separate change needed there. Added `make asterisk-cli` for convenience
(`docker compose exec asterisk asterisk -rvvv`).

## Boot blockers discovered (fixed during implementation)

Two real boot failures were hit and fixed before Asterisk would start at
all — both about the build/runtime image, unrelated to any config
content:

1. **`libasteriskssl.so.1: cannot open shared object file`** — the
   runtime stage only copied `/usr/lib/asterisk` (the modules directory);
   Asterisk's own runtime shared library lives directly under
   `/usr/lib/`, not under `/usr/lib/asterisk/`. Fixed by copying
   `/usr/lib/libasteriskssl.so*` explicitly and running `ldconfig`.
2. **`Stasis initialization failed. ASTERISK EXITING!`** — Stasis
   (Asterisk's internal message bus, initialized unconditionally
   regardless of this task's reduced module scope) refuses to start
   without its XML documentation tree
   (`Cannot update type 'declined_message_types' in module 'stasis'
   because it has no existing documentation!`). The runtime stage hadn't
   copied `/var/lib/asterisk/documentation` at all. Fixed in two parts:
   baked the docs into an image-only path
   (`/usr/share/asterisk-documentation`, not directly into
   `/var/lib/asterisk/documentation`, because `/var/lib/asterisk` is a
   named volume and an empty volume would shadow anything baked into the
   image at that path); `asterisk-entrypoint.sh` seeds it into the volume
   on first boot (same empty-volume-guard pattern as `/etc/asterisk`).

After both fixes, Asterisk reaches "Asterisk Ready." cleanly. The
subsequent boot log shows ~25 modules logging "declined to load" (ERROR
severity, Asterisk's own convention) — all of them missing-optional-
config declines (`pbx_config` has no `extensions.conf`, `app_queue` has
no `queues.conf`, `app_confbridge` has no working config path, etc.),
exactly matching this task's deliberately minimal config set (§B/§D) —
expected, not a defect.

## Validation performed

- `docker compose config` — valid.
- `make doctor` — passes; reports `asterisk: CLI responsive.` once up.
- `make up` — all three services (`app`, `db`, `asterisk`) reach
  `healthy`, in dependency order (`asterisk`/`db` healthy before `app`
  starts, enforced by `depends_on: condition: service_healthy`).
- `make ps` — shows all three healthy, confirms **no host port
  published** for `asterisk` (no PORTS entry).
- **Asterisk**: `asterisk -V` inside the container reports `Asterisk
  22.10.1`. CLI (`asterisk -rx "core show version"`) responsive.
- **AMI**: TCP reachability confirmed (`asterisk:5038` open from `app`).
  Genuine authentication confirmed separately and more strongly than a
  port check — used SENMA's own `Asterisk_AMI::connect()` (which
  performs a real `Action: login` with `Username`/`Secret` and throws
  `Asterisk_Exception_Auth` on any failure) directly from inside the
  `app` container with the real configured credentials: connected
  without exception. Also confirmed via the app's own `statusbar_info()`
  logic (`SystemstatusController::statusbarAction()`) completing its
  `new AsteriskInfo()` + AMI command step without the old "Unable to
  connect to manager" error.
- **`queues`**: authenticated `GET /index.php/default/queues` →
  **HTTP 200**, `var controller = "queues"` marker present, 20KB of real
  rendered content (was a 500 on `parse_ini_file(...): Failed to open
  stream` before this task).
- **`systemstatus`**: see "Remaining blocker" below — does not reach
  PASS, for a reason unrelated to AMI/Asterisk.
- **Shared config**: confirmed both directions (see §D above).
- **Regression**: `make smoke` → **PASS: 15, FAIL: 0,
  EXPECTED_LIMITATION: 0** (was 14/0/1 before this task).
  `queues` moved from the `EXPECTED_LIMITATION` bucket to a genuine
  `PASS` — the harness was updated only after confirming the flow
  actually, meaningfully works (200 + real content), not because the
  HTTP status merely changed. App error log: `0 → 0` new fatals. Asterisk
  log (`/var/log/asterisk/full`): only the expected missing-optional-
  config declines described above; no crashes, no unexpected errors
  after the two boot blockers were fixed.

## Remaining blocker: `systemstatus` does not reach PASS

Per instruction, stopping and reporting this rather than expanding scope
to fix it.

**What works**: AMI is fully reachable and authenticates correctly (see
Validation above) — target outcomes 3, 4, 5 as literally stated
("systemstatus no longer fails *because AMI is unavailable*") are
genuinely met. The `statusbarAction()` sub-route, which exercises exactly
the AMI-dependent code path (`new AsteriskInfo()` → `status_asterisk()`),
completes that portion cleanly with a working Asterisk present.

**What still fails, and why it's a different bug**: the actual
`/index.php/default/systemstatus` route (`indexAction()`) still 500s —
but now with a **completely different, unrelated error**:
`Unable to Connect to tcp://localhost:8080. Error #111: Connection
refused`. Root cause, traced directly: `indexAction()` makes an internal
HTTP loopback request to `lib/linfo/index.php` using
`'http://localhost:'.$_SERVER['SERVER_PORT']`. Confirmed empirically that
inside this container, `$_SERVER['SERVER_PORT']` reports `8080` (the
*externally-published* Docker port, reflected from the request's `Host:`
header under Apache's default `UseCanonicalName Off` behavior), not `80`
(Apache's actual internal listening port) — so the loopback request
tries to reach a port nothing is listening on inside the container and
fails. A second, related pre-existing bug compounds it:
`indexAction()`'s `catch (HttpException $ex)` only catches the PECL
`HttpException` class, not `Zend_Http_Client_Adapter_Exception` (what
`Zend_Http_Client::request()` actually throws), so the failure propagates
uncaught instead of being handled the way the code evidently intended.

**Why this isn't fixed here**: both of these are pure PHP/HTTP
application-layer bugs in `SystemstatusController.php`, entirely
independent of Asterisk — they would reproduce identically with or
without this task's work, and were simply never observable before now
because `AsteriskInfo`'s own AMI-connection exception always fired first
in the old no-Asterisk topology, masking them. Fixing them means editing
first-party PHP compatibility/correctness code, not the SENMA↔Asterisk
runtime boundary this task is scoped to. Per instruction, reported as the
exact blocker rather than absorbed into this task's scope. Candidate for
a TASK-0004-style PHP compatibility follow-up, not TASK-0006 (which is
ODBC-focused).

## BEFORE / AFTER

```
BEFORE:
queues        EXPECTED_LIMITATION  (500, parse_ini_file: snep-musiconhold.conf missing)
systemstatus  no-Asterisk limitation (500, "Unable to connect to manager")

AFTER:
queues        PASS  (200, real content, verified via make smoke)
systemstatus  BLOCKED — but no longer by Asterisk/AMI. AMI itself is proven
              working (direct authenticated connect + statusbar_info()
              success). Blocked by an unrelated, pre-existing PHP bug in
              SystemstatusController::indexAction()'s loopback HTTP call
              (wrong port derivation + wrong caught exception class).
```

## Files changed
- `docker/asterisk.Dockerfile` (new)
- `docker/asterisk-entrypoint.sh` (new)
- `docker/asterisk-config/{asterisk.conf,manager.conf,modules.conf,logger.conf}` (new)
- `compose.yaml` — `asterisk` service, pinned `mag` network subnet, new
  named volumes, `app`'s new `asterisk-etc:ro` mount and `depends_on`.
- `docker/entrypoint.sh` — AMI credential templating into `setup.conf`.
- `.env.example` / `.env` — `ASTERISK_HOST`, `AMI_USER`, `AMI_PASSWORD`,
  `ASTERISK_AMI_ACL_SUBNET`.
- `Makefile` — `asterisk-cli` target, `doctor` Asterisk CLI check.
- `scripts/smoke-test.sh` — `queues` moved from `known_limitation` mode to
  a normal PASS check.

## Remaining Asterisk/PJSIP debt
- `systemstatus`'s unrelated PHP bug, above — not fixed here.
- Full ODBC integration (realtime queues/CDR/CEL/voicemail) — TASK-0006,
  including diagnosing the `res_odbc`/`res_config_odbc` dependency-load
  failure found in §E.
- `chan_sip` is gone; no SIP channel driver of any kind is active in this
  container yet — PJSIP migration (CLAUDE.md Phase 6) is a separate,
  larger milestone, not started by this task.
- AGI runtime, voicemail runtime, conference runtime, recordings spool
  sharing (`arquivos/`, `sounds/moh`, `sounds/pt_BR`) — not wired yet,
  deferred along with the above.
- Hardware-specific config (Khomp/DAHDI/H.323/OSS) — will never be
  relevant in this Docker topology; not tracked as debt.
