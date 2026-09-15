# TASK-0035E3 — Asterisk Console Logging & Runtime Debug Observability

## Status

**Final decision: `ASTERISK_CONSOLE_OBSERVABILITY_PASS_WITH_CONSTRAINTS`**

Constraints:

- Real-call PJSIP Tx/Rx packet dump and RTP packet dump on the dedicated
  pilot remain **`PILOT_RUNTIME_PROOF_PENDING`**. CLI enable/disable of
  those debug switches is **PASS** here; packet-level console visibility
  during an active call remains an operator proof after a release that
  includes this task is deployed.
- Release tag creation is **not** authorized by this task.

## Starting state

```text
HEAD before work: 177fc00 (TASK-0035E2 docs)
pilot release context: v0.1.0-rc.4
host networking: PASS
public WSS: PASS
WebRTC <-> SIP bidirectional audio: PASS (pilot evidence, prior tasks)
```

Live pre-change evidence:

```text
logger show channels:
  /var/log/asterisk/full  File  Enabled  NOTICE WARNING ERROR VERBOSE
  (no Console channel)

/etc/asterisk/logger.conf (volume):
  full => notice,warning,error,verbose
```

## Root cause

`docker/asterisk-config/logger.conf` (TASK-0005 minimal Docker config)
configured **only** the `full` file channel and omitted `console`.

Ownership path:

```text
docker/asterisk-config/logger.conf
  -> bind-mounted read-only as /asterisk-config-src
  -> copied into named volume asterisk-etc (/etc/asterisk) on first boot
     by docker/asterisk-entrypoint.sh
  -> persisted across recreate until reconciled
```

Interactive `asterisk -rvvv` therefore had no console logger channel
carrying VERBOSE/DEBUG (and no DEBUG capability on `full` either). Call
diagnostics still landed in `/var/log/asterisk/full`, matching the pilot
finding.

## Logging contract

Authoritative source: `docker/asterisk-config/logger.conf`

```ini
[general]

[logfiles]
console => notice,warning,error,verbose,debug
full => notice,warning,error,verbose,debug
```

Provider simulator mirrors the same contract in
`docker/provider-config/logger.conf`.

### Default runtime behavior

```text
capability available by default
high-volume debugging opt-in at runtime
```

Declaring `debug` on a logger channel does **not** emit high-volume
DEBUG by itself. After recreate, live proof showed:

```text
Debug level: 0
```

until an operator runs `core set debug N`.

The process still starts with its historical foreground verbose floor
(`asterisk -f -vvv` / equivalent). That is separate from DEBUG / PJSIP
packet logger / RTP packet debug.

## Entrypoint ownership

`docker/asterisk-entrypoint.sh` reconciles `logger.conf` from the
bind-mounted source onto the volume when:

- the file is missing; or
- `console` / `full` channels are missing; or
- either channel lacks `debug`.

This survives container recreate, host reboot, and release redeploy
without a manual in-container edit of `/etc/asterisk/logger.conf`.

`logger.conf` is treated as **project-owned**, not customer-owned state.

Image note: the entrypoint is `COPY`'d into the Asterisk image. Applying
the reconcile to an already-running deployment requires rebuilding the
`asterisk` image layer that copies `docker/asterisk-entrypoint.sh` (compile
layers remain cached) and recreating the service once.

## Interactive operator workflow

```bash
docker compose \
  -f compose.yaml \
  -f compose.pilot.yaml \
  exec asterisk \
  asterisk -rvvv
```

Then:

```text
core set verbose 5
core set debug 5
pjsip set logger on
rtp set debug on
```

Disable without restart:

```text
pjsip set logger off
rtp set debug off
core set debug 0
core set verbose 3
```

## Evidence (this environment)

| Check | Result |
|---|---|
| Console channel present with DEBUG | **PASS** |
| Full file retains NOTICE..DEBUG | **PASS** |
| Default `Debug level: 0` | **PASS** |
| `core set debug 5` → DEBUG lines in `docker compose logs asterisk` | **PASS** |
| `pjsip set logger on/off` | **PASS** (CLI) |
| `rtp set debug on/off` | **PASS** (CLI) |
| `/var/log/asterisk/full` still written | **PASS** |
| Active-call PJSIP Tx/Rx console dump | **NOT_RUN** |
| Active-call RTP packet console dump | **NOT_RUN** |

## Container logs

Asterisk runs foreground (`-f`). With the `console` logger channel,
VERBOSE/DEBUG that reach the console also appear in:

```bash
docker compose logs -f asterisk
```

Interactive `asterisk -rvvv` remains the primary supported live-debug
path; container logs are a useful secondary view, not a redesign of
process supervision.

## Doctor

`make doctor` reports:

```text
Asterisk console logger: PASS
  console channel present with DEBUG capability (runtime debug remains opt-in)
```

Missing console is **WARN**, never a hard FAIL solely because debug is
disabled.

## Security

Runtime PJSIP / RTP debug can expose:

- SIP credentials / Authorization headers
- phone numbers / URIs
- IP addresses
- SDP / media details

Treat packet/signaling debug as operationally sensitive. Enable only for
active troubleshooting and disable afterward. This task does not redact
Asterisk's own debug output.

## Tests / docs

- `scripts/asterisk-console-observability-smoke-test.sh`
- `make asterisk-console-observability-smoke`
- wired into `scripts/regression.sh`
- this task document
- production release runbook troubleshooting section

## Remaining debt

- Pilot call-time console capture of PJSIP logger + RTP debug under
  `v0.1.0-rc.4` (or next RC that includes this change).
- Optional: bind-mount `asterisk-entrypoint.sh` in compose (provider
  already does this) so entrypoint edits do not require an image rebuild.
