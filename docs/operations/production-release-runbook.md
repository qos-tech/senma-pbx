# SENMA PBX — Production Release Runbook

Practical operator procedure for deploying, upgrading, and rolling back a
SENMA PBX production/pilot instance. This is the *procedure*; the evidence
and reasoning behind it live in
`docs/tasks/0034-release-readiness-production-pilot-gate.md`. Do not
duplicate that document's findings here — only the steps.

Every command below is a `make` target already present in the repository
Makefile unless stated otherwise.

---

## 0. Before you start

Confirm you have:

- A Debian 14 host with Docker Engine + Docker Compose v2.
- A pilot-scoped network plan (see TASK-0034 Phase 35/36): which ports are
  actually reachable from the public internet vs. internal-only.
- Real TLS/WSS certificate material if WSS is in scope for this pilot (the
  shipped `wss` transport ships pointed at a self-signed dev-fixture
  certificate — this MUST be replaced before go-live, see step 4).
- A place to keep the generated first-admin credential (step 6) and the
  `.env` file itself (both are secrets; neither is recoverable if lost
  without a database-level reset).

---

## 1. Clone / install

```bash
git clone <repo>
cd mag-pbx
git checkout <release-tag-or-commit>   # see Phase 30 — record the exact commit
cp .env.example .env
```

## 2. Configure environment

Edit `.env`:

- Set real, unique values for `DB_PASSWORD`, `DB_ROOT_PASSWORD`,
  `AMI_PASSWORD`. Never deploy the `change-*-for-local-development`
  placeholders.
- Set `ASTERISK_AMI_ACL_SUBNET` to match the Docker network subnet this
  compose project will actually create (`docker network inspect` after
  first `up`, or pre-compute from `compose.yaml`'s `mag` network
  definition) — not the host's own LAN subnet.
- Set `TZ` to the pilot site's real timezone.
- Set `MAG_HTTP_PORT` if 8080 is unavailable on the host.
- If the pilot deploys behind a trusted TLS-terminating reverse proxy that
  itself sets (and cannot be spoofed on) `X-Forwarded-Proto`, set
  `SENMA_TRUST_PROXY_HTTPS=1`. Otherwise leave unset.
- Remove/ignore `TRUNK_TEST_USERNAME`/`TRUNK_TEST_SECRET` — these only
  matter if the `provider` fixture service is intentionally kept in the
  topology (it should not be, for a production pilot; see Phase 4/35).

**Do not start the `provider` service in production.** It is a SIP trunk
simulator for local development/regression only. The current `compose.yaml`
has no profile gate excluding it — until that follow-up lands, `make
pilot-up` (step 5 below) starts only the services a pilot needs
explicitly (`app asterisk db`), never `provider`.

**`compose.yaml` alone does not expose SIP/WSS to the host** — only the
app's HTTP port is published, by design, so a plain development
`make dev`/`make up` never opens telephony ports. `compose.pilot.yaml`
(TASK-0034B, closing Finding CH-7) is an additive override that
publishes the ports this repository's actually-seeded PJSIP transports
use (UDP/TCP 5060, WSS 8089) plus the RTP media range
(`snep/install/etc/asterisk/rtp.conf`, 10000-10199 — narrowed from the
dev default of 10000-20000; see
`docs/tasks/0034b-production-network-exposure-hardening.md` for why
publishing the full 10001-port dev range is impractical on Docker
Desktop, and widen both files together if a pilot's real concurrent-call
volume needs more than ~100 simultaneous calls). Use it instead of
plain `make up`/`make dev` for a pilot deployment:

```bash
make pilot-config   # review the merged, published-port configuration first
make pilot-up       # starts app/asterisk/db only -- never the provider fixture (CH-3)
```

If the pilot adds a `tls` transport (not seeded by default — an
admin-configured port via the Transports UI), publish that port too, in
a copy of `compose.pilot.yaml` tailored to the pilot's own transport
choices; do not publish a port for a transport the pilot does not
actually use. AMI and the database correctly have no `ports:` mapping
in either file and must stay that way.

## 3. Provision storage

Confirm host free disk space before first boot (see TASK-0034 Phase 27):
budget at least 10 GB free for images (~2 GB) plus initial volume
footprint, headroom for CDR growth (`mag-db`, unbounded — plan a business
retention policy separately), and Asterisk/app log growth (bounded to
~250 MB combined by TASK-0033D's rotation, ~100 MB Asterisk + ~50 MB app x
5 generations).

## 4. Install certificates (if WSS is in pilot scope)

The `wss` PJSIP transport ships **enabled by default**, pointed at a
self-signed certificate the Asterisk container generates at first boot
(`/etc/asterisk/keys/wss-test-cert.pem`). This keeps `make dev` working
with zero admin action, but it is not a production certificate.

Before accepting real WSS traffic:

1. Obtain a real certificate/key pair for the pilot's public hostname.
2. In the admin UI, edit the `wss` PJSIP transport and point
   `cert_file`/`priv_key_file` at the new files (same mechanism a
   development install uses — see `docs/tasks/0029a-tls-transport-certificate-management.md`).
3. Confirm via `make doctor`'s certificate check — but note (Phase 18/34
   finding) that check currently only validates whatever file sits at the
   dev-fixture path, not whichever file the `wss` transport is actually
   configured to use. Manually confirm the transport's configured path
   points at the real certificate until a dedicated follow-up closes that
   gap.
4. If WSS is not part of this pilot's scope, disable the `wss` transport
   explicitly rather than leaving the fixture certificate live.

**Do this before step 5.** `make pilot-up` (TASK-0034B) publishes port
8089 to the host, making the `wss` transport actually reachable from
outside the Docker network for the first time — if the fixture
certificate hasn't been replaced by then, it is genuinely
internet-reachable on a known, non-secret private key, not merely a
theoretical risk. The gap in step 3 above (`doctor` cannot verify which
certificate is actually configured) means nothing will warn you if this
step is skipped — treat it as a hard prerequisite of step 5, not an
optional hardening pass.

## 5. Start the stack

```bash
export COMPOSE_FILES="-f compose.yaml -f compose.pilot.yaml"
export SERVICES="app asterisk db"
make pilot-up
make ps      # confirm all services report healthy (app/asterisk/db only -- no provider)
```

**Keep `COMPOSE_FILES`/`SERVICES` exported for the rest of this operator
shell session** (and every future session that manages this pilot host).
Every `make` target below that depends on `up` — `lint`, `migrate-check`,
`secrets-check`, `reconcile-check` — re-runs `up` as a prerequisite. With
these two variables unset, that re-run silently falls back to plain
`docker compose up -d --build` against `compose.yaml` alone: it recreates
`asterisk` **without** the pilot ports published in step 5 (silently
undoing Finding CH-7's fix) and starts the `provider` dev-only
trunk-simulator fixture (CH-3) that step 2 said must never run in
production — both confirmed live during TASK-0034B. `make doctor` does
not depend on `up` and is unaffected either way. See
`docs/tasks/0034b-production-network-exposure-hardening.md`.

## 6. Verify readiness

```bash
make doctor
```

Expect no `FAIL` lines. Review any `WARN`/`UNKNOWN` against the classified
list in TASK-0034 Phase 15 before proceeding.

The first application boot generates a one-time admin credential and
prints it once to container logs:

```bash
make logs | grep -A2 bootstrap-admin
```

**Capture this credential immediately — it is never shown again.** If
missed, the only recovery path is a direct database credential reset.

## 7. Run migration check

```bash
make migrate-check
```

Release policy:

| State | Action |
|---|---|
| `SCHEMA_CURRENT` | proceed |
| `SCHEMA_BEHIND` | run `make migrate`, then re-check |
| `SCHEMA_AHEAD` | **STOP** — do not proceed; this means the deployed code is older than the database's own recorded state |
| `SCHEMA_UNKNOWN` | **STOP** — investigate before proceeding |

## 8. Run reconcile check

```bash
make reconcile-check
```

| State | Action |
|---|---|
| `IN_SYNC` | proceed |
| `DRIFTED` | run `make reconcile`, then re-check |
| `INVALID_DB` | **STOP** — investigate before proceeding |
| `RUNTIME_UNAVAILABLE` | **STOP** — Asterisk must be reachable before release |

## 9. Create/verify the admin account

Log in with the credential captured in step 6. Change it, or create a
named per-operator account, immediately — do not keep using the
bootstrap-generated shared credential day to day.

On first authenticated login you will see a one-time legacy "register your
SNEP" interstitial (an inherited, non-SENMA vendor prompt, harmless but
irrelevant to this product). Click **"Don't register"** once; this choice
is permanent for the installation.

Visit **Settings → Parameters** and save a system language choice. A
fresh install has no language configured until this is done once, and at
least the Sound Files feature depends on it (`Snep_SoundFiles_Manager`
filters by the configured language) — see TASK-0034 Finding CH-4/CH-5.

## 10. Configure telephony

Follow the supported lifecycle: create extensions and trunks through the
admin UI (Extensions / Trunks / Transports), not by hand-editing generated
config. See the pilot scope table in TASK-0034 for which trunk/transport
models are supported in this pilot.

---

## Preflight (before any subsequent release/redeploy)

There is currently no single `make preflight` target. Until one exists,
run the individual read-only gates in this order and treat any failure as
a stop. **On a pilot host, `COMPOSE_FILES`/`SERVICES` (step 5) must still
be exported in the shell running these** — otherwise `lint`,
`secrets-check`, and `migrate-check`/`reconcile-check`'s `up` prerequisite
silently drop the pilot's published ports and start `provider` (see
step 5's note):

```bash
make lint
make doctor
make secrets-check
make migrate-check
make reconcile-check
```

---

## Upgrade procedure (existing install)

On a pilot host, `COMPOSE_FILES`/`SERVICES` (step 5) must be exported in
this shell — the closing `make up` is exactly the call that silently
strips pilot ports and starts `provider` if they are not.

```bash
make backup                 # -> ./backups/senma-backup-<ts>.tar.gz — verify it completes and checksums validate
git fetch && git checkout <new-release-tag>
docker compose $COMPOSE_FILES build   # or pull, if using pre-built images
make migrate-check          # confirm SCHEMA_BEHIND (expected) or SCHEMA_CURRENT
make migrate                # only if SCHEMA_BEHIND
make reconcile-check        # confirm IN_SYNC after any config-affecting change
make up                     # recreate containers on the new image
make doctor                 # confirm no FAIL
```

## Rollback procedure

Use when an upgrade fails validation above, or a post-upgrade smoke check
fails. On a pilot host, `COMPOSE_FILES`/`SERVICES` must be exported here
too, for the same reason as the upgrade procedure above:

```bash
git checkout <previous-release-tag>
docker compose $COMPOSE_FILES build
make restore FROM=./backups/senma-backup-<pre-upgrade-ts>.tar.gz CONFIRM=RESTORE
make up
make doctor
```

Rollback restores DB, Asterisk config, and certificates together (single
archive, single restore operation) — do not attempt to roll back the
database and the application code independently.

## Secret rotation

```bash
make secrets-check           # confirm MATCH before rotating
make rotate-secrets          # or a per-secret target, e.g. make rotate-ami-password
make secrets-check           # confirm MATCH after
```

Only rotate secrets as an explicit, planned change — not as part of a
routine deploy unless the release specifically changes secret lifecycle.

---

## Operator watch list (pilot soak period)

Manual, unless the site already has external monitoring wired to these:

- `make doctor` — daily, or after any host/network change.
- Trunk registration state (Trunks list page) — daily.
- Host free disk space — weekly at minimum; more often if CDR volume is
  high.
- Certificate expiry (`make doctor`'s certificate check, or the
  transport's own edit view) — monthly.
- `make backup` success and checksum validation — after every scheduled
  backup run.
- Container restart counts (`docker compose ps`, or `docker inspect
  --format '{{.RestartCount}}'`) — daily; any unexplained restart is
  worth investigating, not ignoring.

No unexplained container restarts, no call failures attributable to
SENMA, no disk/log runaway, no credential drift, and successful backups
are the acceptance bar for the soak period defined in TASK-0034 Phase 40.
