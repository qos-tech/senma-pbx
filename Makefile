.PHONY: dev dev-up up pilot-config pilot-up release-build release-info release-artifact-smoke down restart logs ps shell db-shell asterisk-cli test smoke authorization-coverage harness-lib-selftest authorization-smoke preauth-security-smoke sql-security-smoke residual-sql-security-smoke shell-security-smoke pjsip-config-security-smoke api-security-smoke api-sql-security-smoke session-csrf-security-smoke auth-hardening-security-smoke disclosure-path-security-smoke legacy-maintenance-exposure-security-smoke cdr-window-selftest call-smoke trunk-smoke pjsip-external-trunk-smoke pjsip-lifecycle-smoke wss-platform-smoke tls-cert-management-smoke cert-check wss-cert-check wss-certificate-runtime-smoke pjsip-runtime-status-smoke extensions-trunks-admin-experience-smoke transport-smoke dialplan-legacy-closure-smoke restart-smoke external-failure-smoke external-content-smoke lint regression doctor reset config backup restore backup-smoke backup-restore-smoke fresh-install-smoke reconcile reconcile-check pjsip-reconcile-smoke secrets-check rotate-secrets rotate-db-password rotate-db-root-password rotate-ami-password secrets-consistency-smoke secret-rotation-smoke doctor-smoke doctor-failure-smoke compose-profile-isolation-smoke release-artifact-smoke readiness-smoke readiness-failure-smoke migrate migrate-check db-migration-smoke db-migration-failure-smoke ami-acl-migrate ami-acl-smoke

COMPOSE ?= docker compose

# TASK-0034B: let a pilot operator's shell session make every `up`-based
# target (including `lint`/`migrate-check`/`secrets-check`/
# `reconcile-check`'s own `up` prerequisite, and the `make up` calls in
# the Upgrade/Rollback runbook procedures) target the pilot compose
# overlay and service list instead of silently falling back to the
# base compose.yaml. Both default empty, so plain `make up`/`make dev`
# behavior for development is byte-for-byte unchanged. Export once per
# pilot operator shell session:
#   export COMPOSE_FILES="-f compose.yaml -f compose.pilot.yaml"
#   export SERVICES="app asterisk db"
# See docs/operations/production-release-runbook.md and
# docs/tasks/0034b-production-network-exposure-hardening.md -- without
# this, `up`'s default (no file flags, no service filter) drops the
# pilot's published SIP/WSS/RTP ports (recreating `asterisk` to match the
# narrower base compose.yaml). TASK-0034C closed this same scenario's
# other half (starting the `provider` dev-only trunk-simulator fixture,
# TASK-0034 CH-3) structurally, via the Compose profile gate below and
# in compose.yaml -- that part no longer depends on these two variables
# being exported at all, but COMPOSE_FILES/SERVICES are still required
# for the port-exposure half.
COMPOSE_FILES ?=
SERVICES ?=

# TASK-0034C: closes Finding CH-3 structurally -- the `provider` dev/test
# trunk-simulator fixture (compose.yaml) now carries `profiles: [dev,
# test]`, so Compose only ever creates it when one of those profiles is
# active. This is this repository's single supported mechanism for that
# opt-in: empty by default (plain `make up`/`make dev`/`make pilot-up`
# behavior is unchanged -- no fixture, exactly as before this task), set
# to `dev` by `make dev-up` (interactive developer opt-in) and to `test`
# by the specific regression targets that own this fixture's lifecycle
# (`trunk-smoke`, `pjsip-runtime-status-smoke`, `readiness-smoke`,
# `regression`). `up`'s recipe below passes it as an explicit
# `COMPOSE_PROFILES=` prefix rather than relying on an inherited shell
# environment variable of the same name -- this is deliberate: an
# operator's shell that happens to already export COMPOSE_PROFILES=dev
# (from an unrelated project, or a forgotten previous session) cannot
# silently change what `make up` starts, because this recipe always
# overwrites it with `$(FIXTURE_PROFILE)` (empty unless a target above
# set it). See docs/tasks/0034c-production-fixture-compose-profile-isolation.md.
FIXTURE_PROFILE ?=

# TASK-0034D: release identity (TASK-0034 CH-9). RELEASE_VERSION defaults
# to the literal "dev" tag -- explicitly DEVELOPMENT_ONLY/mutable (see
# docs/tasks/0034d-release-artifact-versioning-image-provenance.md Phase
# 7) -- for every ordinary `make up`/`make dev`/`make pilot-config`
# build. GIT_COMMIT/BUILD_TIMESTAMP are always computed automatically, no
# operator export required, so even a "dev" image still carries real
# source provenance. `make release-build VERSION=vX.Y.Z` (scripts/
# release-build.sh) is the one supported way to override RELEASE_VERSION
# for a real release; `pilot-up` below then refuses to run unless the
# calling shell has since exported that same RELEASE_VERSION. `export`
# (not a recipe-local prefix, unlike COMPOSE_PROFILES above) is
# deliberate: compose.yaml's own `${RELEASE_VERSION:-dev}`/
# `${GIT_COMMIT:-unknown}`/`${BUILD_TIMESTAMP:-unknown}` substitutions
# read these from the process environment `docker compose` runs in, on
# every target below, with no per-recipe wiring needed.
RELEASE_VERSION ?= dev
GIT_COMMIT := $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
BUILD_TIMESTAMP := $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
export RELEASE_VERSION
export GIT_COMMIT
export BUILD_TIMESTAMP

dev: doctor up

# TASK-0034C: developer opt-in for the `provider` fixture -- the one
# explicit, documented command that starts it locally (Phase 8). Plain
# `make dev`/`make up` deliberately do not, so a fixture never appears by
# accident; this target is how a developer who actually wants it (e.g. to
# poke at it manually, or run `make asterisk-cli` equivalent debugging
# against it) asks for it explicitly.
dev-up: FIXTURE_PROFILE = dev
dev-up: up

config:
	COMPOSE_PROFILES="$(FIXTURE_PROFILE)" $(COMPOSE) config

up:
	COMPOSE_PROFILES="$(FIXTURE_PROFILE)" $(COMPOSE) $(COMPOSE_FILES) up -d --build $(SERVICES)

# TASK-0034B: pilot/production-style deployment -- layers
# compose.pilot.yaml's SIP/WSS/RTP host-port exposure (TASK-0034 CH-7)
# on top of the base compose.yaml (which stays internal-only for
# development), and deliberately starts only the services a pilot
# needs -- excluding the `provider` dev-only trunk-simulator fixture
# (TASK-0034 CH-3, structurally closed by TASK-0034C's Compose profile
# gate -- see compose.yaml's own header comment).
#
# TASK-0034C: `COMPOSE_PROFILES=` is hardcoded empty here, not read from
# $(FIXTURE_PROFILE) -- deliberately. Every other Compose-invoking target
# in this Makefile treats the fixture profile as an operator/target
# choice; the pilot path does not get that choice, by design (Phase 6/21:
# "production/pilot should require NO fixture profile"). This also
# defeats an operator's shell that happens to already export
# COMPOSE_PROFILES=dev or =test (Phase 24 environment-contamination
# proof) -- these two recipes always win over whatever is inherited.
pilot-config:
	COMPOSE_PROFILES= $(COMPOSE) -f compose.yaml -f compose.pilot.yaml config

# TASK-0034D: no `--build` (unlike `up`/`dev-up` above) -- pilot/
# production must consume the exact image `make release-build` already
# produced and recorded (Phase 9's preferred model: "build occurs in the
# release process -> immutable tagged image exists -> pilot/production
# Compose consumes it", not "rebuild source opportunistically on the
# production host"), never a second, independently-timestamped rebuild
# of the same commit (live-confirmed: two separate `docker compose
# build` invocations of the identical commit/version still produce
# DIFFERENT image ids, because org.opencontainers.image.created legally
# differs between them -- see docs/tasks/
# 0034d-release-artifact-versioning-image-provenance.md "BUILD
# REPRODUCIBILITY BOUNDARY"). Compose only auto-builds a service that
# has BOTH `image:` and `build:` when the named image does not already
# exist locally -- the two guards below close that gap explicitly,
# rather than silently allowing an unvetted just-in-time build here that
# never went through release-build.sh's dirty-tree/tag-match checks.
pilot-up:
	@if [ "$(RELEASE_VERSION)" = "dev" ] || [ -z "$(RELEASE_VERSION)" ]; then \
		echo "ERROR: pilot-up refuses to deploy the mutable 'dev' tag (TASK-0034 CH-9 -- no mutable-only release)." >&2; \
		echo "Run 'make release-build VERSION=vX.Y.Z' first (from the exact commit tagged vX.Y.Z), then" >&2; \
		echo "'export RELEASE_VERSION=vX.Y.Z' in this shell and retry 'make pilot-up'." >&2; \
		exit 1; \
	fi
	@if ! docker image inspect "senma-app:$(RELEASE_VERSION)" >/dev/null 2>&1 || ! docker image inspect "senma-asterisk:$(RELEASE_VERSION)" >/dev/null 2>&1; then \
		echo "ERROR: senma-app:$(RELEASE_VERSION) / senma-asterisk:$(RELEASE_VERSION) not found locally." >&2; \
		echo "Run 'make release-build VERSION=$(RELEASE_VERSION)' first -- pilot-up never builds an image of its own." >&2; \
		exit 1; \
	fi
	COMPOSE_PROFILES= $(COMPOSE) -f compose.yaml -f compose.pilot.yaml up -d app asterisk db

# TASK-0034D: builds the SENMA-owned production images (app, asterisk --
# never provider, TASK-0034 CH-3) with an explicit release version,
# refuses a dirty/untracked working tree (ALLOW_DIRTY=1 is an explicit
# development override, never for a real release), and validates that
# HEAD is tagged VERSION unless RC=1 (release-candidate mode: explicit
# version + commit, no tag required). Writes release-manifest.json (a
# generated, gitignored build receipt -- not a second source of truth,
# see docs/tasks/0034d-release-artifact-versioning-image-provenance.md
# Phase 11). Never pushes anywhere (no registry is configured -- Phase
# 34/35 of the same doc).
release-build:
	@test -n "$(VERSION)" || (echo "Usage: make release-build VERSION=vX.Y.Z [RC=1] [ALLOW_DIRTY=1]" >&2 && exit 1)
	@if [ -f .env ]; then set -a; . ./.env; set +a; fi; \
	  VERSION="$(VERSION)" RC="$(RC)" ALLOW_DIRTY="$(ALLOW_DIRTY)" bash scripts/release-build.sh

# TASK-0034D: read-only. Compares the currently running app/asterisk
# containers' OCI image labels against release-manifest.json (if one
# exists) and prints MATCH/DRIFT/UNKNOWN per service, plus the
# third-party db image for inventory only (never SENMA-versioned). See
# scripts/release-info.sh's own header.
release-info:
	@if [ -f .env ]; then set -a; . ./.env; set +a; fi; bash scripts/release-info.sh

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f --tail=200

ps:
	$(COMPOSE) ps

shell:
	$(COMPOSE) exec app bash

db-shell:
	$(COMPOSE) exec db mariadb -u"$${DB_USER}" -p"$${DB_PASSWORD}" "$${DB_NAME}"

asterisk-cli:
	$(COMPOSE) exec asterisk asterisk -rvvv

test:
	@echo "No automated test suite is wired yet."
	@echo "Add project tests before changing this target to report success."

smoke: up
	@set -a; . ./.env; set +a; bash scripts/smoke-test.sh

# TASK-0026A: static inventory -- every controller/action must be
# resource-registered, a reviewed authenticated-open controller, or a
# resource alias, so no new controller/action can silently fall through
# to an implicit allow. Pure static check, no Docker dependency.
authorization-coverage:
	@bash scripts/authorization-coverage-check.sh

# TASK-0027A: proves scripts/lib/harness.sh's own PASS/FAIL/BLOCKED/
# INCONCLUSIVE state machine and summary printing work on this
# project's actual bash 3.2 host shell, including the empty-row
# "unbound variable" edge case found live and fixed by this task, and
# the bounded container-readiness retry added alongside it. Pure
# self-contained check (fakes $COMPOSE), no Docker dependency.
harness-lib-selftest:
	@bash scripts/harness-lib-selftest.sh

# TASK-0026A: verifies the default-deny authorization boundary using an
# isolated local-dev account.  It performs only harmless GETs and uses the
# existing Users > Permission form for the grant/revoke lifecycle.
authorization-smoke: up
	@set -a; . ./.env; set +a; bash scripts/authorization-smoke-test.sh

preauth-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/preauth-security-smoke-test.sh

# TASK-0026C: proves the F7-F11 SQL-injection boundaries (Extensions,
# Users/Profiles, Trunks, CSV import, Data Export) hold -- SQL-shaped
# values behave as inert literal data through the real, authenticated
# application flows, never a direct database connection. Deliberately
# separate from `make smoke` -- never run implicitly by it.
sql-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/sql-security-smoke-test.sh

# TASK-0026J: proves the two residual SQL-injection sinks found by
# TASK-0026Z's own closure static sweep -- Snep_InterfaceConf's legacy
# chan_sip/iax2 trunk lookup and CallsReportController's report-filter
# SQL construction -- are closed. Deliberately separate from `make
# smoke` -- never run implicitly by it.
residual-sql-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/residual-sql-security-smoke-test.sh

# TASK-0026D: proves the F2-F5 shell/command-injection boundaries
# (Sound Files, Music on Hold, System Logs, CNL Update) hold --
# shell-shaped values behave as inert data (or are rejected outright by
# a filename/directory allowlist) through the real, authenticated
# application flows, never a direct shell/exec() call. Deliberately
# separate from `make smoke` -- never run implicitly by it.
shell-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/shell-security-smoke-test.sh

# TASK-0026E: proves the F12-F15 PJSIP/Asterisk configuration-injection
# boundaries (Extensions, Trunks, PJSIP Transports, legacy chan_sip) hold
# -- newline/section/directive-shaped values are rejected before
# persistence, or (F14, already covered by pre-existing TASK-0019/0020
# validation) never accepted in the first place, through the real,
# authenticated application flows. Deliberately separate from
# `make smoke` -- never run implicitly by it.
pjsip-config-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/pjsip-config-security-smoke-test.sh

# TASK-0026F: proves the F17 standalone-API authentication/service-
# resolution boundaries (snep/modules/default/api/index.php) hold --
# both Basic-auth parsing branches apply the same password
# normalization (no pass-the-hash), and $_GET['service'] only ever
# selects a key into a finite, trusted registry (no path built from
# request data). Deliberately separate from `make smoke` -- never run
# implicitly by it.
api-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/api-security-smoke-test.sh

# TASK-0026F1: proves the SQL-injection boundaries discovered during
# TASK-0026F's own reconnaissance (ContactsService, CSV_ExportDataService,
# CallsReportService, RankingReportService, ServicesReportService) hold --
# SQL-shaped values behave as inert literal data through the real,
# authenticated standalone API dispatcher, never a direct database
# connection. Deliberately separate from `make smoke` -- never run
# implicitly by it.
api-sql-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/api-sql-security-smoke-test.sh

# TASK-0026G: proves the F18-F20 session-fixation/cookie/CSRF boundaries
# hold -- the session id changes on login and the pre-login id cannot
# access an authenticated page afterward, logout invalidates the session,
# the session cookie carries HttpOnly/SameSite/Secure-when-HTTPS, and
# authenticated state-changing POSTs are rejected without a valid
# session-bound CSRF token (missing, invalid, or from a foreign session)
# while GETs and the standalone Basic-auth API remain unaffected.
# Deliberately separate from `make smoke` -- never run implicitly by it.
session-csrf-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/session-csrf-security-smoke-test.sh

# TASK-0026H: proves the F21-F24/F27 authentication-hardening boundaries
# hold -- modern password_hash() storage on every write path, legacy MD5
# accounts migrate transparently on successful login, a stored hash can
# never itself authenticate (pass-the-hash), the standalone API uses the
# same password semantics as browser login, failed logins are rate-
# limited (per-account+source and per-source, both auto-expiring), wrong
# password and unknown user are indistinguishable, and a fresh install no
# longer ships an operational admin/admin123 credential. Deliberately
# separate from `make smoke` -- never run implicitly by it.
auth-hardening-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/auth-hardening-security-smoke-test.sh

# TASK-0026I: exercises the F25/F26/F28 information-disclosure and
# contained-path-traversal findings -- error.phtml's now-gated exception
# message, expose_php/raw-SQL-in-JSON disclosure, and DocsController's
# allowlist-based path containment (including a symlink-escape proof).
# Deliberately separate from `make smoke` -- never run implicitly by it.
disclosure-path-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/disclosure-path-security-smoke-test.sh

# TASK-0026S: proves snep/install/ (one-time installer/schema-migration
# assets, including the DB-mutating convert-data-rc3.php/updateCallerid.php
# scripts) cannot be invoked over HTTP -- GET/POST both blocked at the
# web-server layer (snep/install/.htaccess), the whole subtree equally
# contained (not just the one known script), no schema/data mutation, no
# source/path/SQL-error disclosure in the blocked response, the ordinary
# application still works, and filesystem/CLI availability (Docker
# bind-mount, php -l) is preserved. Deliberately separate from `make
# smoke` -- never run implicitly by it.
legacy-maintenance-exposure-security-smoke: up
	@set -a; . ./.env; set +a; bash scripts/legacy-maintenance-exposure-security-smoke-test.sh

# TASK-0027A: deterministic, fixed-timestamp proof of
# harness_cdr_report_window() (lib/harness.sh) -- the timezone-safe CDR
# report-window logic call-smoke/trunk-smoke depend on. Never reads the
# wall clock, so it exercises the local-midnight/UTC-divergence boundary
# on demand instead of only when the real clock happens to cross it.
cdr-window-selftest: up
	@set -a; . ./.env; set +a; bash scripts/cdr-window-selftest.sh

call-smoke: up
	@set -a; . ./.env; set +a; bash scripts/call-smoke-test.sh

# TASK-0034A: Calls Report (web CallsReportController) regression suite.
calls-report-smoke: up
	@set -a; . ./.env; set +a; bash scripts/calls-report-smoke-test.sh

# TASK-0034C: this suite owns the `provider` fixture's lifecycle for its
# own run -- FIXTURE_PROFILE=test is a target-specific variable, which
# GNU Make also applies when building this target's own `up` prerequisite,
# so `provider` starts here without requiring the operator to know or
# pass anything. See the FIXTURE_PROFILE header comment above `up`.
trunk-smoke: FIXTURE_PROFILE = test
trunk-smoke: up
	@set -a; . ./.env; set +a; bash scripts/trunk-smoke-test.sh

# TASK-0028X: proves pjsip_external outbound dial-string generation --
# PBX_Trunks::get() now dispatches PJSIP_EXTERNAL trunks to
# PBX_Asterisk_Interface_PJSIP (same as native "pjsip"), producing
# "PJSIP/<destination>@<endpoint>" instead of the previously-generated,
# structurally-wrong "PJSIP/<endpoint>/<destination>". See
# docs/tasks/0028x-pjsip-external-dialstring-fix.md. Deliberately
# separate from trunk-smoke -- a different trunk technology/fixture.
pjsip-external-trunk-smoke: up
	@set -a; . ./.env; set +a; bash scripts/pjsip-external-trunk-smoke-test.sh

transport-smoke: up
	@set -a; . ./.env; set +a; bash scripts/transport-smoke-test.sh

# TASK-0028Y: registrationless PJSIP trunk (reverse_auth=0), qualify
# "specify"/NAT auto_* runtime proof, trunk update (reverse_auth),
# extension update beyond transport_id, and full delete-cleanup proof
# (generated config + live Asterisk + DB, not just HTTP 302) for both
# trunk and extension. See
# docs/tasks/0028y-pjsip-parameter-regression-closure.md. Deliberately
# separate from trunk-smoke/call-smoke -- a different fixture profile
# (no live call, no baresip/provider dependency).
pjsip-lifecycle-smoke: up
	@set -a; . ./.env; set +a; bash scripts/pjsip-lifecycle-smoke-test.sh

# TASK-0028Z: Asterisk built-in HTTP server + WSS platform enablement --
# proves http.conf/TLS-cert persistence, a real TLS+WebSocket handshake
# at /ws, a real SIP REGISTER over that WebSocket, and restart/recreate
# convergence. Restarts/recreates the asterisk container itself
# (deliberately, Phase 9 of the task) -- run in isolation from other
# stateful suites, same as every other suite in this list.
wss-platform-smoke: up
	@set -a; . ./.env; set +a; bash scripts/wss-platform-smoke-test.sh

# TASK-0029A: TLS/WSS transport certificate management -- validation,
# generated-config correctness, live TLS handshake/fingerprint proof,
# rotation, mismatched cert/key runtime-apply failure behavior, and
# restart persistence. Restarts the asterisk container (same "run in
# isolation" reasoning as wss-platform-smoke above).
tls-cert-management-smoke: up
	@set -a; . ./.env; set +a; bash scripts/tls-cert-management-smoke-test.sh

# TASK-0034E (closing TASK-0034 CH-2): read-only, secret-safe, runtime-
# aware WSS certificate trust check -- reads whichever certificate the
# live `wss`/`ws` transport is actually configured to use, classifies it
# (TRUSTED/SELF_SIGNED/HOSTNAME_MISMATCH/EXPIRED/.../RUNTIME_MISMATCH),
# and confirms what the live listener actually presents. Never mutates
# state, never prints private key material. `make cert-check` and `make
# wss-cert-check` are the same target under two names -- `cert-check` is
# the short operator-facing form; `wss-cert-check` matches this
# project's other `<subject>-check` naming (migrate-check,
# reconcile-check, secrets-check). Pass PILOT=1 to additionally evaluate
# pilot acceptance (exits nonzero if NOT_ACCEPTABLE_FOR_PILOT) -- this is
# the mandatory release-gate form; see docs/operations/
# production-release-runbook.md Preflight section.
cert-check wss-cert-check: up
	@set -a; . ./.env; set +a; bash scripts/wss-cert-check.sh $(if $(PILOT),--pilot)

# TASK-0034E: focused regression coverage for the WSS certificate trust
# gate above -- fixture classification, missing/mismatched/expired/
# hostname-mismatch negative proofs (no private key material ever
# printed), a real ephemeral test-CA-issued certificate proven TRUSTED/
# PILOT_ACCEPTABLE with a real verified (non-CERT_NONE) SIP-over-WSS
# REGISTER, full-chain (leaf+CA) serving, and the RUNTIME_MISMATCH ->
# reload -> MATCH runtime-staleness proof. Restarts nothing by default;
# rotates and restores the live `wss` transport's own certificate
# through the real HTTP edit-form flow (same "run in isolation"
# reasoning as tls-cert-management-smoke/wss-platform-smoke above).
wss-certificate-runtime-smoke: up
	@set -a; . ./.env; set +a; bash scripts/wss-certificate-runtime-smoke-test.sh

# TASK-0029B: PJSIP runtime status visibility -- extension/trunk
# CONFIGURED-vs-LIVE status, real reachable/unreachable/rejected proof,
# pjsip_external existence proof, and the AMI-down-never-fabricates-
# Offline contract. Stops/restarts the asterisk container (Part C) --
# same "run in isolation" reasoning as the other restart-using suites.
# TASK-0034C: needs the `provider` fixture (reachable-trunk proof) -- see
# trunk-smoke's own FIXTURE_PROFILE comment above.
pjsip-runtime-status-smoke: FIXTURE_PROFILE = test
pjsip-runtime-status-smoke: up
	@set -a; . ./.env; set +a; bash scripts/pjsip-runtime-status-smoke-test.sh

# TASK-0031: Extensions + Trunks administration experience -- credential
# non-disclosure, save/apply feedback (SAVED_ACTIVE/PENDING/RUNTIME_APPLY_FAILED),
# the 4-way trunk connection-type chooser, dead legacy-control removal,
# validation-failure form re-render, and no regression to delete-dependency
# guards/CSRF/authorization. See
# docs/tasks/0031-extensions-trunks-administration-experience.md.
extensions-trunks-admin-experience-smoke: up
	@set -a; . ./.env; set +a; bash scripts/extensions-trunks-admin-experience-smoke-test.sh

# TASK-0032: Transport + shared runtime UX foundation -- shared status
# badge (data-runtime-status alongside the pre-existing TASK-0020
# data-runtime-state), transport protocol disclosure via hidden/
# aria-hidden, WSS-vs-native-TLS certificate wording, transport
# Diagnostics, shared dependency-warning panel across all three entities,
# delete-success feedback, responsive transport list columns, and the
# AMI-down-never-crashes/never-fabricates contract extended to the
# transport list. Stops/restarts the asterisk container (Part E) -- same
# "run in isolation" reasoning as pjsip-runtime-status-smoke. See
# docs/tasks/0032-transport-shared-runtime-ux-foundation.md.
transport-shared-runtime-ux-smoke: up
	@set -a; . ./.env; set +a; bash scripts/transport-shared-runtime-ux-smoke-test.sh

# TASK-0028C: proves the reachable SIP/IAX-era dialplan/config constructs
# closed by that task stay closed (context bleed, SIPAddHeader, callback
# .call generation) -- see docs/tasks/0028c-pjsip-legacy-runtime-closure.md.
dialplan-legacy-closure-smoke: up
	@set -a; . ./.env; set +a; bash scripts/dialplan-legacy-closure-smoke-test.sh

# TASK-0021: restarts the dev Asterisk container multiple times, including
# while a real call is active. Deliberately separate from `make smoke` --
# never run implicitly by it.
restart-smoke: up
	@set -a; . ./.env; set +a; bash scripts/restart-smoke-test.sh

# TASK-0024: deterministically simulates vendor-API failure (DNS,
# refused, blackhole, TLS, HTTP 500, malformed/empty payload) using only
# controlled local/reserved targets -- never the real vendor. Deliberately
# separate from `make smoke` -- never run implicitly by it.
external-failure-smoke: up
	@set -a; . ./.env; set +a; bash scripts/external-failure-smoke-test.sh

# TASK-0025: proves vendor-controlled content (notifications, version
# check, changelog, announce) cannot inject active HTML/JavaScript into
# rendered SENMA pages. Uses only controlled local fixtures, never the
# real vendor. Deliberately separate from `make external-failure-smoke`
# (that suite tests availability, this one tests content) -- never run
# implicitly by `make smoke`.
external-content-smoke: up
	@set -a; . ./.env; set +a; bash scripts/external-content-smoke-test.sh

# TASK-0027: php -l across snep/ (inside the app container), bash -n
# across scripts/, XML well-formedness for resources.xml, and
# git diff --check. Lightweight, reproducible, no external framework.
lint: up
	@set -a; . ./.env; set +a; bash scripts/lint.sh

# TASK-0027: the one canonical release-regression gate -- runs the full
# supported suite serially, in a fixed dependency-respecting order, and
# never treats BLOCKED/INCONCLUSIVE as PASS. See
# docs/tasks/0027-regression-harness-reliability.md.
# TASK-0034C: FIXTURE_PROFILE=test on `regression`'s own `up` prerequisite
# starts `provider` once, up front, for the three suites inside
# regression.sh that need it (trunk-smoke, pjsip-runtime-status-smoke,
# readiness-smoke -- regression.sh invokes each suite script directly, not
# via `make <suite>`, so their own individual FIXTURE_PROFILE settings
# don't apply on this path; only this line does).
regression: FIXTURE_PROFILE = test
regression: up
	@set -a; . ./.env; set +a; bash scripts/regression.sh

# TASK-0033D: canonical read-only diagnostic entrypoint -- see
# scripts/doctor.sh's own header and docs/tasks/
# 0033d-diagnostics-logging-storage-lifecycle.md DOCTOR CONTRACT.
# Deliberately does NOT depend on `up` or require .env to exist (it
# reports a missing .env/stopped Docker daemon/absent container as its
# own findings rather than aborting before running) -- .env is sourced
# only if present, so declared-secret-dependent checks (Application DB
# authentication, AMI reachable, Secrets) can still run when it is.
# `make doctor VERBOSE=1` (or `bash scripts/doctor.sh --verbose`) adds
# sanitized supporting detail (e.g. the full secrets-check.sh/
# reconcile-pjsip.php --check breakdown) -- never secret values.
doctor:
	@if [ -f .env ]; then set -a; . ./.env; set +a; fi; bash scripts/doctor.sh $(if $(VERBOSE),--verbose)

reset:
	@echo "WARNING: this removes MAG development containers and volumes."
	@printf "Type RESET to continue: "; read answer; test "$$answer" = "RESET"
	$(COMPOSE) down -v --remove-orphans

# TASK-0033A: bit-identical operational backup -- see docs/tasks/
# 0033a-backup-restore-disaster-recovery-foundation.md. DEST is optional
# (defaults to ./backups); an operator never needs to know a Docker
# volume name to use this.
backup: up
	@set -a; . ./.env; set +a; bash scripts/backup.sh $(if $(DEST),--dest "$(DEST)")

# TASK-0033A: REPLACE-semantics restore. FROM is required. CONFIRM=RESTORE
# is required whenever the target already has existing SENMA state
# (mirrors `make reset`'s typed-confirmation precedent) -- restore.sh
# itself reports the exact reason if this is missing/wrong.
restore:
	@test -n "$(FROM)" || (echo "Usage: make restore FROM=<path-to-backup.tar.gz> [CONFIRM=RESTORE]" && exit 1)
	@set -a; . ./.env; set +a; bash scripts/restore.sh "$(FROM)" $(if $(filter RESTORE,$(CONFIRM)),--confirm)

# TASK-0033A: lightweight, non-destructive backup/restore validation --
# safe to run as part of `make regression` (never stops a container,
# never touches a volume). See scripts/backup-smoke-test.sh.
backup-smoke: up
	@set -a; . ./.env; set +a; bash scripts/backup-smoke-test.sh

# TASK-0033A: the real, destructive disaster-recovery proof -- creates
# fixtures, backs them up, actually destroys the target (db, asterisk-etc,
# mag-asterisk-var volumes; setup.conf; arquivos/), restores, and proves
# a real endpoint re-registers and completes a real call. Deliberately
# NOT part of `make regression` (see scripts/
# backup-restore-dr-smoke-test.sh's own header and docs/tasks/
# 0033a-backup-restore-disaster-recovery-foundation.md's "Regression"
# section for why) -- run this explicitly, and expect it to take
# noticeably longer than an ordinary smoke suite.
backup-restore-smoke: up
	@set -a; . ./.env; set +a; bash scripts/backup-restore-dr-smoke-test.sh

# TASK-0034J (D1): genuinely isolated fresh-install proof -- its own
# throwaway Compose project (own containers/network/volumes), never the
# primary "mag-pbx" project this Makefile's other targets operate on, so
# it deliberately does NOT depend on `up`. See scripts/
# fresh-install-proof-smoke-test.sh's own header for why a concurrent
# second stack previously collided with the primary one, and why it no
# longer does.
fresh-install-smoke:
	bash scripts/fresh-install-proof-smoke-test.sh

# TASK-0033B: full DB->PJSIP runtime reconciliation, independent of any
# single extension/trunk/transport CRUD operation. See docs/tasks/
# 0033b-pjsip-configuration-reconciliation.md. Exit codes: 0 reconciled,
# 2 files reconciled but runtime needs separate attention (restart
# required, or Asterisk unreachable), 1 a real failure.
reconcile: up
	@$(COMPOSE) exec asterisk php /usr/local/bin/reconcile-pjsip.php

# Non-mutating drift check -- never writes to disk, never touches
# Asterisk. Exit codes: 0 in sync, 3 drifted, 1 invalid DB state.
reconcile-check: up
	@$(COMPOSE) exec asterisk php /usr/local/bin/reconcile-pjsip.php --check

# TASK-0033F: apply every pending database schema migration, in order,
# stopping on the first failure. See docs/tasks/
# 0033f-database-bootstrap-resilience-upgrade-path.md. Exit codes: 0
# current/applied, 1 a migration failed, 2 SCHEMA_UNKNOWN (refuses to
# guess), 4 SCHEMA_AHEAD (refuses to act), 5 lock timeout (another
# runner already in progress).
migrate: up
	@$(COMPOSE) exec app php /usr/local/bin/migrate.php

# Non-mutating: reports current/expected schema version and any pending
# migrations, never applies anything. Exit codes: 0 current, 3 pending
# (SCHEMA_BEHIND), 4 SCHEMA_AHEAD, 2 SCHEMA_UNKNOWN.
migrate-check: up
	@$(COMPOSE) exec app php /usr/local/bin/migrate.php --check

# TASK-0033B: regression coverage for the reconciliation contract --
# in-sync/drift detection, deleted-file recovery, stale-section removal,
# customer/certificate byte-identity, pjsip_external non-interference,
# invalid-DB refusal, and a real endpoint registration + call after a
# deliberate delete-and-reconcile. Safe for `make regression` (no volume
# destruction, unlike backup-restore-smoke) -- see scripts/
# pjsip-reconcile-smoke-test.sh's own header.
pjsip-reconcile-smoke: up
	@set -a; . ./.env; set +a; bash scripts/pjsip-reconcile-smoke-test.sh

# TASK-0033C: non-mutating secret-consistency check -- for each
# rotatable credential (DB_PASSWORD, DB_ROOT_PASSWORD, AMI_PASSWORD),
# reports whether the value currently declared in .env matches what is
# actually active/persisted everywhere that credential is consumed.
# Never writes to disk, never touches a DB account, never
# reloads/restarts anything. See docs/tasks/
# 0033c-secret-rotation-contract.md. Exit codes: 0 all MATCH, 3 drift
# detected on at least one secret, 1 could not be determined/error.
secrets-check: up
	@set -a; . ./.env; set +a; bash scripts/secrets-check.sh

# TASK-0033C: reconciles every DECLARED secret in .env into its
# active/persisted state on an EXISTING installation -- the operator
# command that turns "I edited .env" into an actual, verified,
# old-value-rejected/new-value-accepted rotation, with automatic
# rollback to the previous coherent state on any verification failure.
# Fixed order: DB_ROOT_PASSWORD, DB_PASSWORD, AMI_PASSWORD (see
# docs/tasks/0033c-secret-rotation-contract.md ROTATION ORDERING).
# Rotating DB_ROOT_PASSWORD prompts once, interactively, for the
# CURRENT root password (never read from .env, never stored/logged).
# Exit code: 0 if every secret ends ROTATED_SUCCESSFULLY, 1 if any ends
# ROTATION_REJECTED (never a partial "success").
rotate-secrets: up
	@set -a; . ./.env; set +a; bash scripts/rotate-secrets.sh

rotate-db-password: up
	@set -a; . ./.env; set +a; bash scripts/rotate-secrets.sh --only db-password

rotate-db-root-password: up
	@set -a; . ./.env; set +a; bash scripts/rotate-secrets.sh --only db-root-password

rotate-ami-password: up
	@set -a; . ./.env; set +a; bash scripts/rotate-secrets.sh --only ami-password

# TASK-0034F (closing TASK-0034 CH-6): reconciles an EXISTING install's
# already-generated manager.conf permit=/setup.conf ip_sock onto the
# values currently declared in .env (ASTERISK_AMI_ACL_SUBNET/
# ASTERISK_HOST) -- both are FIRST_BOOT_SEED files an ordinary `.env`
# edit + `make up` never touches on their own (same class of gap
# rotate-secrets/rotate-ami-password already solves for AMI_PASSWORD).
# Idempotent (reports ALREADY_CURRENT if nothing to do); rolls back to
# the previous coherent state on any post-migration verification
# failure. See docs/tasks/0034f-production-ami-acl-scoping.md MIGRATION.
ami-acl-migrate: up
	@set -a; . ./.env; set +a; bash scripts/ami-acl-migrate.sh

# TASK-0034F: safe, non-mutating regression coverage for the AMI
# network-ACL trust boundary -- authorized caller PASS, unauthorized
# caller (db/provider) DENIED, 5038 not host-published, reload and a
# scoped asterisk restart both preserve the narrowed ACL. See scripts/
# ami-acl-smoke-test.sh's own header for exactly what it does and does
# not do (a fresh-volume invalid-CIDR rejection proof is deliberately
# NOT run here).
ami-acl-smoke: up
	@set -a; . ./.env; set +a; bash scripts/ami-acl-smoke-test.sh

# TASK-0033C: safe, non-mutating regression coverage for the
# consistency-check contract itself (asserts MATCH on this dev
# install's own baseline, and that no secret value ever appears in
# output). Safe for `make regression` -- see scripts/
# secrets-consistency-smoke-test.sh's own header, and
# secret-rotation-smoke, deliberately NOT part of `make regression`,
# for the full destructive rotation proof.
secrets-consistency-smoke: up
	@set -a; . ./.env; set +a; bash scripts/secrets-consistency-smoke-test.sh

# TASK-0033C: the real, destructive secret-rotation proof -- rotates
# DB_PASSWORD, DB_ROOT_PASSWORD and AMI_PASSWORD forward on this
# existing installation, proves old-value-rejected/new-value-accepted
# for each, proves restart/force-recreate persistence, proves backup/
# reconcile/runtime-status keep working, injects controlled failures,
# then rotates every secret back to its original value. Deliberately
# NOT part of `make regression` (mirrors backup-restore-smoke's own
# precedent, see scripts/secret-rotation-smoke-test.sh's own header) --
# run this explicitly.
secret-rotation-smoke: up
	@set -a; . ./.env; set +a; bash scripts/secret-rotation-smoke-test.sh

# TASK-0033D: safe, non-mutating regression coverage for `make doctor`
# itself (asserts exit 0/no FAIL on this dev install's own healthy
# baseline, every mandatory check present, no secret disclosure in
# normal or --verbose output, and no mutating command in doctor.sh's
# own source). Safe for `make regression` -- see scripts/
# doctor-smoke-test.sh's own header, and doctor-failure-smoke,
# deliberately NOT part of `make regression`, for the real failure-
# injection/log-rotation proof.
doctor-smoke: up
	@set -a; . ./.env; set +a; bash scripts/doctor-smoke-test.sh

# TASK-0034C: focused, non-mutating regression coverage for the Compose
# profile isolation this task added (Finding CH-3) -- proves the base/
# pilot topology excludes `provider` by default, that FIXTURE_PROFILE=
# dev/test explicitly includes it, and that `make pilot-config`'s own
# `COMPOSE_PROFILES=` override survives a contaminated shell. Pure
# `docker compose ... config` inspection -- never starts, stops, or
# mutates any container, volume, or file, so it does not depend on `up`.
# See scripts/compose-profile-isolation-smoke-test.sh's own header.
compose-profile-isolation-smoke:
	@if [ -f .env ]; then set -a; . ./.env; set +a; fi; bash scripts/compose-profile-isolation-smoke-test.sh

# TASK-0034D: focused regression coverage for release-identity (TASK-0034
# CH-9) -- version/revision label metadata present and in agreement
# between the app/asterisk images `up` just built, dirty-tree rejection,
# MATCH/DRIFT/UNKNOWN classification (including a real UNKNOWN case: the
# third-party `db` image, which carries no SENMA OCI labels at all).
# Depends on `up` (needs real just-built labels to inspect) but never
# rebuilds, restarts, or mutates anything itself. See scripts/
# release-artifact-smoke-test.sh's own header.
release-artifact-smoke: up
	@set -a; . ./.env; set +a; bash scripts/release-artifact-smoke-test.sh

# TASK-0033D: the real, destructive doctor-detection proof -- stops
# asterisk/db/app one at a time (restoring each before moving to the
# next), injects secret drift and PJSIP config drift (both via safe,
# non-persistent mechanisms), and forces a live log rotation, proving
# `make doctor` detects each condition, leaves unrelated checks
# unaffected, and that the log-rotation mechanism itself works without
# disrupting Asterisk. Deliberately NOT part of `make regression`
# (mirrors secret-rotation-smoke's own precedent, see scripts/
# doctor-failure-smoke-test.sh's own header) -- run this explicitly.
doctor-failure-smoke: up
	@set -a; . ./.env; set +a; bash scripts/doctor-failure-smoke-test.sh

# TASK-0033E: safe, non-mutating regression coverage for the readiness
# contract (all core containers healthy, each dedicated healthcheck
# script reports READY on demand, AMI/WSS are part of the reported
# invariant, no secret leakage, full-stack restart reconverges). Safe
# for `make regression` -- see scripts/readiness-smoke-test.sh's own
# header, and readiness-failure-smoke, deliberately NOT part of `make
# regression`, for the real failure-injection/recovery proof.
# TASK-0034C: this suite's own contract treats `provider` as one of the
# "core" containers required healthy (see the script's own header) -- only
# true when the fixture is intentionally active, i.e. here. See
# trunk-smoke's own FIXTURE_PROFILE comment above.
readiness-smoke: FIXTURE_PROFILE = test
readiness-smoke: up
	@set -a; . ./.env; set +a; bash scripts/readiness-smoke-test.sh

# TASK-0033E: the real, destructive readiness-detection proof -- proves
# DB-schema-missing (isolated throwaway project), app-without-DB,
# Asterisk-with-a-PJSIP-transport-mismatch (the TASK-0028V class of
# defect, reproduced deterministically), AMI failure, and WSS listener
# failure each correctly make the affected service NOT_READY, that each
# recovers automatically once corrected, and that force-recreate
# converges deterministically. Deliberately NOT part of `make
# regression` (mirrors doctor-failure-smoke's own precedent, see
# scripts/readiness-failure-smoke-test.sh's own header) -- run this
# explicitly.
readiness-failure-smoke: up
	@set -a; . ./.env; set +a; bash scripts/readiness-failure-smoke-test.sh

# TASK-0033F: safe, non-mutating regression coverage for the migration
# runner against the live dev database -- current-install baselining/
# recognition, `migrate-check` reporting SCHEMA_CURRENT, checksum
# verification, no secret disclosure. Included in `make regression`.
db-migration-smoke: up
	@set -a; . ./.env; set +a; bash scripts/db-migration-smoke-test.sh

# TASK-0033F: the real, destructive proof -- isolated Compose project
# only. Partial-bootstrap-failure detection/recovery, an older-schema
# fixture upgrade path, mid-migration failure + retry convergence, and
# concurrent-runner locking. Deliberately NOT part of `make regression`
# (mirrors readiness-failure-smoke/doctor-failure-smoke/secret-rotation-
# smoke's own precedent) -- run this explicitly.
db-migration-failure-smoke: up
	@bash scripts/db-migration-failure-smoke-test.sh
